//
//  ReceiptCameraCoordinateConverter.swift
//  Finance
//

import CoreGraphics
import ImageIO

enum ReceiptCameraCoordinateConverter {
    static func visionOrientation(forRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        let normalizedAngle = Int((angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360).rounded()) % 360

        switch normalizedAngle {
        case 90:
            return .right
        case 180:
            return .down
        case 270:
            return .left
        default:
            return .up
        }
    }

    /// Converts Vision's normalized points (origin at bottom-left) into the
    /// unrotated capture-device coordinates expected by AVCaptureVideoPreviewLayer.
    static func captureDevicePoint(
        fromVisionPoint point: CGPoint,
        orientation: CGImagePropertyOrientation
    ) -> CGPoint {
        let orientedTopLeftPoint = CGPoint(x: point.x, y: 1 - point.y)

        switch orientation {
        case .right:
            return CGPoint(x: orientedTopLeftPoint.y, y: 1 - orientedTopLeftPoint.x)
        case .left:
            return CGPoint(x: 1 - orientedTopLeftPoint.y, y: orientedTopLeftPoint.x)
        case .down:
            return CGPoint(x: 1 - orientedTopLeftPoint.x, y: 1 - orientedTopLeftPoint.y)
        default:
            return orientedTopLeftPoint
        }
    }
}
