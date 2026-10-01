//
//  ReceiptRectangleDetectorTests.swift
//  FinanceTests
//

import CoreGraphics
import ImageIO
import Testing
@testable import Finance

struct ReceiptRectangleDetectorTests {
    @Test func rejectsLowConfidenceAndSmallRectangles() {
        #expect(!ReceiptRectangleDetector.isValid(candidate(confidence: 0.54)))
        #expect(!ReceiptRectangleDetector.isValid(candidate(points: [CGPoint(x: 0.45, y: 0.45), CGPoint(x: 0.55, y: 0.45), CGPoint(x: 0.55, y: 0.55), CGPoint(x: 0.45, y: 0.55)])))
    }

    @Test func requiresConsecutiveStableFrames() {
        var detector = ReceiptRectangleDetector()
        let ticket = candidate()

        #expect(detector.update(with: ticket) == .searching)
        #expect(detector.update(with: ticket) == .detectedStable(ticket))
    }

    @Test func toleratesSmallMovementBetweenStableFrames() {
        var detector = ReceiptRectangleDetector()
        let ticket = candidate()
        let moved = candidate(points: ticket.points.map { CGPoint(x: $0.x + 0.1, y: $0.y) })

        #expect(detector.update(with: ticket) == .searching)
        #expect(detector.update(with: moved) == .detectedStable(moved))
    }

    @Test func movementResetsTemporalStability() {
        var detector = ReceiptRectangleDetector()
        let ticket = candidate()
        let moved = candidate(points: ticket.points.map { CGPoint(x: $0.x + 0.16, y: $0.y) })

        _ = detector.update(with: ticket)
        #expect(detector.update(with: moved) == .searching)
        #expect(detector.consecutiveValidFrames == 1)
    }

    @Test func convertsVisionCornersToCaptureDeviceCoordinates() {
        let visionCorners = [
            CGPoint(x: 0, y: 1),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 0, y: 0)
        ]

        let expectedByOrientation: [(CGImagePropertyOrientation, [CGPoint])] = [
            (.up, [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]),
            (.right, [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]),
            (.down, [CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)]),
            (.left, [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0)])
        ]

        for (orientation, expectedPoints) in expectedByOrientation {
            for (visionPoint, expectedPoint) in zip(visionCorners, expectedPoints) {
                #expect(ReceiptCameraCoordinateConverter.captureDevicePoint(fromVisionPoint: visionPoint, orientation: orientation) == expectedPoint)
            }
        }
    }

    private func candidate(points: [CGPoint]? = nil, confidence: Float = 0.9) -> ReceiptRectangleCandidate {
        let points = points ?? [
            CGPoint(x: 0.2, y: 0.2),
            CGPoint(x: 0.8, y: 0.2),
            CGPoint(x: 0.8, y: 0.8),
            CGPoint(x: 0.2, y: 0.8)
        ]
        return ReceiptRectangleCandidate(topLeft: points[0], topRight: points[1], bottomRight: points[2], bottomLeft: points[3], confidence: confidence)
    }
}
