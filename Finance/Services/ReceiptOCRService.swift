//
//  ReceiptOCRService.swift
//  Finance
//

import CoreImage
import UIKit
import Vision

enum ReceiptOCRServiceError: LocalizedError, Sendable {
    case imageUnavailable
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "No se pudo acceder a la imagen capturada."
        case .recognitionFailed:
            return "No se pudo leer el texto del ticket."
        }
    }
}

/// On-device OCR adapter. Text interpretation remains in ReceiptTotalParser.
struct ReceiptOCRService: Sendable {
    private let parser: ReceiptTotalParser

    init(parser: ReceiptTotalParser = ReceiptTotalParser()) { self.parser = parser }

    func scan(image: UIImage, referenceDate: Date = Date()) async throws -> ReceiptScanDraft {
        try await scan(images: [image], referenceDate: referenceDate)
    }

    func scan(images: [UIImage], referenceDate: Date = Date()) async throws -> ReceiptScanDraft {
        guard !images.isEmpty else { throw ReceiptOCRServiceError.imageUnavailable }
        let pages = images.compactMap { image -> (CGImage, CGImagePropertyOrientation)? in
            guard let cgImage = image.cgImage else { return nil }
            return (cgImage, CGImagePropertyOrientation(image.imageOrientation))
        }
        guard !pages.isEmpty else { throw ReceiptOCRServiceError.imageUnavailable }
        let parser = self.parser
        return try await Task.detached(priority: .userInitiated) {
            var drafts: [ReceiptScanDraft] = []
            for (cgImage, orientation) in pages {
                let normalizedImage = Self.normalizedImage(cgImage, orientation: orientation) ?? cgImage
                let candidateImages = [normalizedImage] + Self.receiptCrops(in: normalizedImage)
                for candidateImage in candidateImages {
                    do {
                        let text = try Self.recognizeText(in: candidateImage, orientation: .up)
                        guard !text.isEmpty else { continue }
                        drafts.append(parser.parse(text, referenceDate: referenceDate))
                    } catch {
                        // A failed crop must not discard a valid full-frame OCR result.
                        continue
                    }
                }
            }
            guard let bestDraft = drafts.enumerated().max(by: { lhs, rhs in
                let lhsScore = Self.draftScore(lhs.element)
                let rhsScore = Self.draftScore(rhs.element)
                return lhsScore == rhsScore ? lhs.offset < rhs.offset : lhsScore < rhsScore
            })?.element else {
                throw ReceiptOCRServiceError.recognitionFailed
            }
            return bestDraft
        }.value
    }

    nonisolated private static func recognizeText(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
        var recognizedText: [String] = []
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01
        do { try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request]) }
        catch { throw ReceiptOCRServiceError.recognitionFailed }
        return recognizedText.joined(separator: "\n")
    }

    nonisolated private static func normalizedImage(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        guard orientation != .up else { return image }
        let input = CIImage(cgImage: image)
            .oriented(forExifOrientation: Int32(orientation.rawValue))
        return CIContext().createCGImage(input, from: input.extent)
    }

    nonisolated private static func receiptCrops(in image: CGImage) -> [CGImage] {
        var observations: [VNRectangleObservation] = []
        let request = VNDetectRectanglesRequest { request, _ in
            observations = (request.results as? [VNRectangleObservation]) ?? []
        }
        request.maximumObservations = 6
        request.minimumConfidence = 0.45
        request.minimumSize = 0.04
        request.quadratureTolerance = 30

        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            return []
        }

        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return observations
            .filter { observation in
                let points = points(for: observation, in: extent)
                let area = polygonArea(points, in: extent)
                let width = max(distance(points[0], points[1]), distance(points[2], points[3]))
                let height = max(distance(points[0], points[3]), distance(points[1], points[2]))
                let sideRatio = max(width, height) / max(min(width, height), 1)
                return area >= 0.04 && area <= 0.92 && sideRatio <= 6
            }
            .sorted { lhs, rhs in
                let lhsPoints = points(for: lhs, in: extent)
                let rhsPoints = points(for: rhs, in: extent)
                let lhsRank = lhs.confidence * Float(polygonArea(lhsPoints, in: extent))
                let rhsRank = rhs.confidence * Float(polygonArea(rhsPoints, in: extent))
                return lhsRank > rhsRank
            }
            .prefix(3)
            .compactMap { perspectiveCorrectedImage(for: $0, in: image, extent: extent) }
    }

    nonisolated private static func points(for observation: VNRectangleObservation, in extent: CGRect) -> [CGPoint] {
        [
            pixelPoint(observation.topLeft, in: extent),
            pixelPoint(observation.topRight, in: extent),
            pixelPoint(observation.bottomRight, in: extent),
            pixelPoint(observation.bottomLeft, in: extent)
        ]
    }

    nonisolated private static func perspectiveCorrectedImage(
        for observation: VNRectangleObservation,
        in image: CGImage,
        extent: CGRect
    ) -> CGImage? {
        let expandedPoints = expanded(points(for: observation, in: extent), in: extent, factor: 1.04)
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: expandedPoints[0]), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: expandedPoints[1]), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: expandedPoints[2]), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: expandedPoints[3]), forKey: "inputBottomLeft")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    nonisolated private static func polygonArea(_ points: [CGPoint], in extent: CGRect) -> CGFloat {
        guard points.count == 4 else { return 0 }
        let area = abs(points.enumerated().reduce(CGFloat.zero) { result, item in
            let next = points[(item.offset + 1) % points.count]
            return result + item.element.x * next.y - next.x * item.element.y
        }) / 2
        return area / max(extent.width * extent.height, 1)
    }

    nonisolated private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    nonisolated private static func draftScore(_ draft: ReceiptScanDraft) -> Int {
        var score: Int
        switch draft.amountStatus {
        case .detected: score = 1_000
        case .ambiguous: score = 300
        case .missing: score = 0
        }
        if draft.amount != nil { score += 100 }
        if let merchant = draft.merchant, !merchant.isEmpty {
            score += 40
            if merchant.range(of: #"\bS\.?\s*(?:A|L)\.?\b|\bSLU\b|\bINC\.?\b|\bLTD\.?\b|\bLLC\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                score += 100
            }
        }
        score -= draft.warnings.count * 5
        return score
    }

    nonisolated private static func pixelPoint(_ point: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + point.x * extent.width,
            y: extent.minY + point.y * extent.height
        )
    }

    nonisolated private static func expanded(_ points: [CGPoint], in extent: CGRect, factor: CGFloat) -> [CGPoint] {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else { return points }
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return points.map { point in
            CGPoint(
                x: min(max(center.x + (point.x - center.x) * factor, extent.minX), extent.maxX),
                y: min(max(center.y + (point.y - center.y) * factor, extent.minY), extent.maxY)
            )
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up; case .down: self = .down; case .left: self = .left; case .right: self = .right
        case .upMirrored: self = .upMirrored; case .downMirrored: self = .downMirrored; case .leftMirrored: self = .leftMirrored; case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
