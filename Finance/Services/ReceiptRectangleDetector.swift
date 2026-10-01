//
//  ReceiptRectangleDetector.swift
//  Finance
//

import CoreGraphics
import Foundation

nonisolated struct ReceiptRectangleCandidate: Equatable, Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
    let confidence: Float

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
}

nonisolated enum ReceiptRectangleDetection: Equatable, Sendable {
    case searching
    case detectedStable(ReceiptRectangleCandidate)
}

/// Valida y estabiliza rectángulos detectados en frames consecutivos.
/// No depende de Vision para que sus reglas sean fáciles de probar.
nonisolated struct ReceiptRectangleDetector {
    var minimumConfidence: Float = 0.55
    var minimumArea: CGFloat = 0.06
    var maximumSideRatio: CGFloat = 6.0
    var stableFrameCount = 2
    var maximumCornerMovement: CGFloat = 0.12

    private(set) var consecutiveValidFrames = 0
    private var previousCandidate: ReceiptRectangleCandidate?

    static func isValid(_ candidate: ReceiptRectangleCandidate, minimumConfidence: Float = 0.55, minimumArea: CGFloat = 0.06, maximumSideRatio: CGFloat = 6.0) -> Bool {
        guard candidate.confidence >= minimumConfidence else { return false }
        let points = candidate.points
        guard points.allSatisfy({ $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 }) else { return false }

        let area = abs(points.enumerated().reduce(CGFloat.zero) { result, item in
            let next = points[(item.offset + 1) % points.count]
            return result + item.element.x * next.y - next.x * item.element.y
        }) / 2
        guard area >= minimumArea else { return false }

        let horizontalLength = max(distance(candidate.topLeft, candidate.topRight), distance(candidate.bottomLeft, candidate.bottomRight))
        let verticalLength = max(distance(candidate.topLeft, candidate.bottomLeft), distance(candidate.topRight, candidate.bottomRight))
        guard horizontalLength > 0, verticalLength > 0 else { return false }
        return max(horizontalLength, verticalLength) / min(horizontalLength, verticalLength) <= maximumSideRatio
    }

    mutating func update(with candidate: ReceiptRectangleCandidate?) -> ReceiptRectangleDetection {
        guard let candidate,
              Self.isValid(candidate, minimumConfidence: minimumConfidence, minimumArea: minimumArea, maximumSideRatio: maximumSideRatio)
        else {
            consecutiveValidFrames = 0
            previousCandidate = nil
            return .searching
        }

        if let previousCandidate,
           maximumCornerMovement(from: previousCandidate, to: candidate) <= maximumCornerMovement {
            consecutiveValidFrames += 1
        } else {
            consecutiveValidFrames = 1
        }
        previousCandidate = candidate

        guard consecutiveValidFrames >= stableFrameCount else { return .searching }
        return .detectedStable(candidate)
    }

    private func maximumCornerMovement(from lhs: ReceiptRectangleCandidate, to rhs: ReceiptRectangleCandidate) -> CGFloat {
        zip(lhs.points, rhs.points).map { distance($0, $1) }.max() ?? .greatestFiniteMagnitude
    }
}

private nonisolated func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}
