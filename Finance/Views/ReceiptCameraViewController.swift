//
//  ReceiptCameraViewController.swift
//  Finance
//

import AVFoundation
import ImageIO
import UIKit
import Vision

enum ReceiptCameraError: LocalizedError, Sendable {
    case cameraUnavailable
    case cameraAccessDenied
    case sessionConfigurationFailed
    case sessionRuntimeError
    case imageUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "No hay una cámara disponible en este dispositivo."
        case .cameraAccessDenied:
            return "No se concedió acceso a la cámara. Puedes activarlo desde Ajustes."
        case .sessionConfigurationFailed:
            return "No se pudo iniciar la cámara. Inténtalo de nuevo."
        case .sessionRuntimeError:
            return "La cámara dejó de estar disponible. Inténtalo de nuevo."
        case .imageUnavailable:
            return "No se pudo obtener la imagen capturada."
        }
    }
}

final class ReceiptCameraViewController: UIViewController {
    private enum CameraStatus {
        case searching
        case detected
        case retrying
        case interrupted

        var title: String {
            switch self {
            case .searching: return "Alinea el ticket"
            case .detected: return "Ticket listo"
            case .retrying: return "Reintentando…"
            case .interrupted: return "Cámara no disponible"
            }
        }

        var iconName: String {
            switch self {
            case .searching: return "viewfinder"
            case .detected: return "checkmark.circle.fill"
            case .retrying: return "arrow.clockwise"
            case .interrupted: return "pause.circle.fill"
            }
        }

        var tintColor: UIColor {
            switch self {
            case .searching: return .white
            case .detected: return .systemGreen
            case .retrying: return .systemYellow
            case .interrupted: return .systemOrange
            }
        }

        var accessibilityValue: String {
            switch self {
            case .searching: return "Alinea el ticket dentro del marco"
            case .detected: return "Ticket detectado, listo para capturar"
            case .retrying: return "Reintentando la conexión con la cámara"
            case .interrupted: return "La cámara está temporalmente no disponible"
            }
        }
    }

    private let onScan: ([UIImage]) -> Void
    private let onCancel: () -> Void
    private let onError: (Error) -> Void

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.getincouch.finance.receipt-camera-session")
    private let detectionQueue = DispatchQueue(label: "com.getincouch.finance.receipt-camera-detection")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let overlayView = ReceiptDetectionOverlayView()
    private let statusView = UIButton(type: .system)
    private let shutterButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let lifecycleLock = NSLock()
    private var sessionObservers: [NSObjectProtocol] = []

    private var detector = ReceiptRectangleDetector()
    private var lastFrameTime: CMTime = .invalid
    private var hasPublishedStableDetection = false
    private var isCapturing = false
    private var didFinish = false
    // Read and written on sessionQueue so the preview cannot race configuration.
    private var sessionConfigured = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?
    private var visionOrientation: CGImagePropertyOrientation = .right

    init(
        onScan: @escaping ([UIImage]) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onScan = onScan
        self.onCancel = onCancel
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreview()
        configureControls()
        configureSessionNotifications()
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayView.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isFinished() else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.isFinished(), self.sessionConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    deinit { stopSession() }

    func invalidate() {
        guard finishOnce() else {
            stopSession()
            return
        }
        stopSession()
    }

    func stopSession() {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        sessionObservers.removeAll()
        previewRotationObservation?.invalidate()
        captureRotationObservation?.invalidate()
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil

        let videoOutput = self.videoOutput
        detectionQueue.async {
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
        }
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configurePreview() {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.addSubview(overlayView)
    }

    private func configureControls() {
        statusView.isUserInteractionEnabled = false
        statusView.isAccessibilityElement = true
        statusView.accessibilityTraits = []
        statusView.accessibilityLabel = "Estado de detección"

        cancelButton.setTitle("Cancelar", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.accessibilityLabel = "Cancelar escáner"

        shutterButton.configuration = makeCaptureButtonConfiguration()
        shutterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        shutterButton.addTarget(self, action: #selector(capture), for: .touchUpInside)
        shutterButton.accessibilityLabel = "Confirmar foto del ticket"
        shutterButton.accessibilityHint = "Captura una foto del ticket completo"
        shutterButton.accessibilityTraits = [.button]

        [statusView, cancelButton, shutterButton].forEach { view.addSubview($0) }
        statusView.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.translatesAutoresizingMaskIntoConstraints = false

        let statusLeading = statusView.leadingAnchor.constraint(
            greaterThanOrEqualTo: cancelButton.trailingAnchor,
            constant: 12
        )
        statusLeading.priority = .defaultHigh
        let statusTrailing = statusView.trailingAnchor.constraint(
            lessThanOrEqualTo: view.trailingAnchor,
            constant: -16
        )
        statusTrailing.priority = .defaultHigh

        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLeading,
            statusTrailing,
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            shutterButton.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            shutterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 184),
            shutterButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])

        setStatus(.searching, animated: false)
    }

    private func setStatus(_ status: CameraStatus, animated: Bool = true) {
        let configuration = makeStatusConfiguration(for: status)
        let update = { [weak self] in
            guard let self else { return }
            self.statusView.configuration = configuration
            self.statusView.accessibilityValue = status.accessibilityValue
        }

        guard animated else {
            update()
            return
        }

        UIView.transition(
            with: statusView,
            duration: 0.18,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent],
            animations: update
        )
    }

    private func makeStatusConfiguration(for status: CameraStatus) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = status.title
        configuration.image = UIImage(
            systemName: status.iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14)
        configuration.baseForegroundColor = status.tintColor
        configuration.background.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        configuration.background.cornerRadius = 18
        configuration.background.strokeColor = status.tintColor.withAlphaComponent(0.46)
        configuration.background.strokeWidth = 1
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .subheadline)
                .scaledFont(for: UIFont.systemFont(ofSize: 15, weight: .semibold))
            return outgoing
        }
        return configuration
    }

    private func makeCaptureButtonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Confirmar foto"
        configuration.image = UIImage(
            systemName: "camera.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.background.backgroundColor = UIColor.black.withAlphaComponent(0.74)
        configuration.background.cornerRadius = 28
        configuration.background.strokeColor = UIColor.white.withAlphaComponent(0.72)
        configuration.background.strokeWidth = 1.5
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .headline)
                .scaledFont(for: UIFont.systemFont(ofSize: 16, weight: .semibold))
            return outgoing
        }
        return configuration
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted { self.configureSession() }
                else { self.finish(with: ReceiptCameraError.cameraAccessDenied) }
            }
        case .denied, .restricted:
            finish(with: ReceiptCameraError.cameraAccessDenied)
        @unknown default:
            finish(with: ReceiptCameraError.cameraAccessDenied)
        }
    }

    private func configureSessionNotifications() {
        let notificationCenter = NotificationCenter.default
        sessionObservers = [
            notificationCenter.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleRuntimeError(notification)
            },
            notificationCenter.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            },
            notificationCenter.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.resumeAfterInterruption()
            }
        ]
    }

    private func handleRuntimeError(_ notification: Notification) {
        guard !isFinished() else { return }
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        guard error?.code == AVError.mediaServicesWereReset.rawValue else {
            setStatus(.retrying)
            sessionQueue.async { [weak self] in
                guard let self, !self.isFinished(), self.sessionConfigured else { return }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                let recovered = self.session.isRunning
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isFinished() else { return }
                    if recovered {
                        self.shutterButton.isEnabled = !self.isCapturing
                        self.setStatus(.searching)
                    } else {
                        self.finish(with: ReceiptCameraError.sessionRuntimeError)
                    }
                }
            }
            return
        }
        resumeAfterInterruption()
    }

    private func handleInterruption(_ notification: Notification) {
        guard !isFinished() else { return }
        shutterButton.isEnabled = false
        setStatus(.interrupted)
    }

    private func resumeAfterInterruption() {
        guard !isFinished() else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.isFinished(), self.sessionConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isFinished() else { return }
                self.shutterButton.isEnabled = !self.isCapturing
                self.setStatus(.searching)
            }
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isFinished() else { return }
            guard let camera = self.backCamera() else {
                self.finish(with: ReceiptCameraError.cameraUnavailable)
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                guard self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.videoOutput) else {
                    self.session.commitConfiguration()
                    self.finish(with: ReceiptCameraError.sessionConfigurationFailed)
                    return
                }
                self.session.addInput(input)
                self.session.addOutput(self.photoOutput)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                  kCVPixelBufferWidthKey as String: 640,
                                                  kCVPixelBufferHeightKey as String: 480]
                DispatchQueue.main.sync {
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.detectionQueue)
                }
                self.session.addOutput(self.videoOutput)
                self.session.commitConfiguration()
                self.sessionConfigured = true
                guard !self.isFinished() else { return }
                DispatchQueue.main.sync {
                    self.configureRotationCoordinator(for: camera)
                }
                guard !self.isFinished() else { return }
                self.session.startRunning()
            } catch {
                self.finish(with: error)
            }
        }
    }

    private func backCamera() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera
            ],
            mediaType: .video,
            position: .back
        )
        return discoverySession.devices.first ?? AVCaptureDevice.default(for: .video)
    }

    private func configureRotationCoordinator(for camera: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(\AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
            self?.applyRotationAngles()
        }
        captureRotationObservation = coordinator.observe(\AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] _, _ in
            self?.applyRotationAngles()
        }
        applyRotationAngles()
    }

    private func applyRotationAngles() {
        guard let rotationCoordinator else { return }
        let previewAngle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        let captureAngle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture

        if let previewConnection = previewLayer.connection,
           previewConnection.isVideoRotationAngleSupported(previewAngle) {
            previewConnection.videoRotationAngle = previewAngle
        }

        // Keep analysis buffers in the camera's native, unrotated orientation.
        // Vision receives the orientation separately, avoiding a second rotation.
        if let videoConnection = videoOutput.connection(with: .video),
           videoConnection.isVideoRotationAngleSupported(0) {
            videoConnection.videoRotationAngle = 0
        }

        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoRotationAngleSupported(captureAngle) {
            photoConnection.videoRotationAngle = captureAngle
        }

        lifecycleLock.lock()
        visionOrientation = ReceiptCameraCoordinateConverter.visionOrientation(forRotationAngle: previewAngle)
        lifecycleLock.unlock()
    }

    @objc private func cancel() {
        guard finishOnce() else { return }
        stopSession()
        onCancel()
    }

    @objc private func capture() {
        guard !isCapturing, session.isRunning else { return }
        isCapturing = true
        shutterButton.isEnabled = false
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.off) { settings.flashMode = .off }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finish(with error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.finishOnce() else { return }
            self.stopSession()
            self.onError(error)
        }
    }

    private func updateDetection(_ detection: ReceiptRectangleDetection) {
        switch detection {
        case .searching:
            guard hasPublishedStableDetection else { return }
            hasPublishedStableDetection = false
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isFinished() else { return }
                self.overlayView.candidate = nil
                self.overlayView.isStable = false
                self.setStatus(.searching)
            }
        case let .detectedStable(candidate):
            let didBecomeStable = !hasPublishedStableDetection
            hasPublishedStableDetection = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isFinished() else { return }
                // Keep publishing the candidate: the camera can move after
                // the first stable frame and the outline must follow it.
                self.overlayView.candidate = candidate
                self.overlayView.isStable = true
                if didBecomeStable {
                    self.setStatus(.detected)
                }
            }
        }
    }

    private func isFinished() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return didFinish
    }

    @discardableResult
    private func finishOnce() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !didFinish else { return false }
        didFinish = true
        return true
    }

    private func currentVisionOrientation() -> CGImagePropertyOrientation {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return visionOrientation
    }
}

extension ReceiptCameraViewController: @MainActor AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isFinished() else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard !lastFrameTime.isValid || CMTimeGetSeconds(timestamp - lastFrameTime) >= 0.12 else { return }
        lastFrameTime = timestamp

        let request = VNDetectRectanglesRequest { [weak self] request, _ in
            let observation = (request.results as? [VNRectangleObservation])?.first
            let candidate = observation.map {
                ReceiptRectangleCandidate(topLeft: $0.topLeft, topRight: $0.topRight, bottomRight: $0.bottomRight, bottomLeft: $0.bottomLeft, confidence: $0.confidence)
            }
            guard let self else { return }
            self.updateDetection(self.detector.update(with: candidate))
        }
        request.maximumObservations = 1
        request.minimumConfidence = 0.55
        request.minimumSize = 0.08
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: currentVisionOrientation()).perform([request])
        } catch {
            self.updateDetection(.searching)
        }
    }
}

extension ReceiptCameraViewController: @MainActor AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCapturing = false
            self.shutterButton.isEnabled = true
            if let error {
                self.finish(with: error)
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                self.finish(with: ReceiptCameraError.imageUnavailable)
                return
            }
            guard self.finishOnce() else { return }
            self.stopSession()
            self.onScan([image])
        }
    }
}

private final class ReceiptDetectionOverlayView: UIView {
    var candidate: ReceiptRectangleCandidate? { didSet { setNeedsDisplay() } }
    var isStable = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // This view is only a drawing overlay. If UIKit treats its backing
        // store as opaque, the undrawn area hides the camera preview in the
        // exact moment a candidate triggers a redraw.
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let candidate, let previewLayer = superview?.layer.sublayers?.compactMap({ $0 as? AVCaptureVideoPreviewLayer }).first else { return }
        let orientation = ReceiptCameraCoordinateConverter.visionOrientation(forRotationAngle: previewLayer.connection?.videoRotationAngle ?? 0)
        let converted = candidate.points.map {
            let capturePoint = ReceiptCameraCoordinateConverter.captureDevicePoint(
                fromVisionPoint: $0,
                orientation: orientation
            )
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: capturePoint)
        }
        guard let first = converted.first else { return }
        let path = UIBezierPath()
        path.move(to: first)
        converted.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        (isStable ? UIColor.systemGreen : UIColor.systemYellow).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}
