//
//  ReceiptScannerView.swift
//  Finance
//

import SwiftUI
import UIKit

/// Puente SwiftUI para la cámara propia del escáner de tickets.
/// No conserva imágenes: las entrega al consumidor y libera la sesión al cerrar.
struct ReceiptScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> ReceiptCameraViewController {
        ReceiptCameraViewController(
            onScan: onScan,
            onCancel: onCancel,
            onError: onError
        )
    }

    func updateUIViewController(_ controller: ReceiptCameraViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: ReceiptCameraViewController, coordinator: ()) {
        controller.invalidate()
    }
}
