//
//  ReceiptScanFlowView.swift
//  Finance
//

import SwiftUI
import UIKit

/// Estado visual del flujo captura → OCR → revisión.
/// La operación OCR se inyecta para mantener este archivo libre de persistencia y
/// permitir que ReceiptOCRService conecte su API real cuando esté disponible.
struct ReceiptScanFlowView: View {
    enum Phase: Equatable {
        case ready
        case processing
        case review
        case error(String)
    }

    let recognize: ([UIImage]) async throws -> ReceiptScanDraft
    let onComplete: (ReceiptScanDraft) -> Void
    let onManualEntry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .ready
    @State private var scannedPageCount = 0
    @State private var draft: ReceiptScanDraft?
    @State private var showingScanner = false
    @State private var recognitionTask: Task<Void, Never>?

    init(
        recognize: @escaping ([UIImage]) async throws -> ReceiptScanDraft,
        onComplete: @escaping (ReceiptScanDraft) -> Void,
        onManualEntry: @escaping () -> Void = {}
    ) {
        self.recognize = recognize
        self.onComplete = onComplete
        self.onManualEntry = onManualEntry
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ready:
                    readyContent
                case .processing:
                    processingContent
                case .review:
                    reviewContent
                case let .error(message):
                    errorContent(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .financeGlassPageBackground()
            .navigationTitle("Escanear ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        recognitionTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                recognitionTask?.cancel()
                recognitionTask = nil
            }
            .sheet(isPresented: $showingScanner) {
                ReceiptScannerView(
                    onScan: beginOCR,
                    onCancel: { showingScanner = false },
                    onError: { error in
                        showingScanner = false
                        phase = .error(error.localizedDescription)
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var readyContent: some View {
        VStack(spacing: FinanceGlassTokens.Spacing.xLarge) {
            scanIcon

            VStack(spacing: FinanceGlassTokens.Spacing.small) {
                Text("Captura el ticket")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Alinea el ticket dentro del marco de la cámara. La detección automática te ayudará a encuadrarlo y revisarás los datos antes de guardar el movimiento.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingScanner = true
            } label: {
                Label("Abrir cámara", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Abre la cámara para capturar el ticket completo")
            .padding(.horizontal, FinanceGlassTokens.Spacing.xLarge)
        }
        .padding(FinanceGlassTokens.Spacing.xLarge)
        .frame(maxWidth: 440)
        .accessibilityElement(children: .contain)
    }

    private var processingContent: some View {
        VStack(spacing: FinanceGlassTokens.Spacing.large) {
            ProgressView()
                .controlSize(.large)
                .tint(.financeAccent)

            Text("Leyendo el ticket…")
                .font(.headline)

            Text("Esto puede tardar unos segundos. No se guardará la imagen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(FinanceGlassTokens.Spacing.xLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Procesando ticket")
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.large) {
            Label {
                Text("Datos detectados")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.10, green: 0.46, blue: 0.23))
            }
            .font(.title3.weight(.semibold))

            Text("Revisa el borrador y completa manualmente la cuenta y la categoría en el formulario de movimiento. Si algún dato es ambiguo, corrígelo antes de guardar.")
                .font(.body)
                .foregroundStyle(.secondary)

            if let draft {
                ReceiptDraftSummary(draft: draft)
            }

            if scannedPageCount > 1 {
                Label("\(scannedPageCount) páginas capturadas", systemImage: "doc.on.doc")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                guard let draft else { return }
                onComplete(draft)
                dismiss()
            } label: {
                Text("Revisar movimiento")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(FinanceGlassTokens.Spacing.xLarge)
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: FinanceGlassTokens.Spacing.large) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("No se pudo leer el ticket")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(message.isEmpty ? "Inténtalo de nuevo o introduce el movimiento manualmente." : message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: FinanceGlassTokens.Spacing.small) {
                Button("Intentar de nuevo") {
                    phase = .ready
                    showingScanner = true
                }
                .buttonStyle(.borderedProminent)

                Button("Introducir manualmente") {
                    onManualEntry()
                    dismiss()
                }
                    .buttonStyle(.bordered)
            }
        }
        .padding(FinanceGlassTokens.Spacing.xLarge)
        .frame(maxWidth: 460)
        .accessibilityElement(children: .contain)
    }

    private var scanIcon: some View {
        Image(systemName: "doc.viewfinder")
            .font(.system(size: 56, weight: .medium))
            .foregroundStyle(Color.financeAccent)
            .frame(width: 112, height: 112)
            .background(Color.financeAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous))
            .accessibilityHidden(true)
    }

    private func beginOCR(images: [UIImage]) {
        recognitionTask?.cancel()
        showingScanner = false
        scannedPageCount = images.count
        phase = .processing

        recognitionTask = Task {
            do {
                let result = try await recognize(images)
                guard !Task.isCancelled else { return }
                draft = result
                phase = .review
            } catch {
                guard !Task.isCancelled else { return }
                phase = .error(error.localizedDescription)
            }
        }
    }
}

private struct ReceiptDraftSummary: View {
    let draft: ReceiptScanDraft

    var body: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.small) {
            if let merchant = draft.merchant, !merchant.isEmpty {
                Label(merchant, systemImage: "storefront")
            }

            if let amount = draft.amount {
                Label(amount.asCurrency(code: draft.currencyCode ?? AppCurrency.fallbackCode), systemImage: "banknote")
            } else {
                Label("Importe pendiente de revisión manual", systemImage: "questionmark.circle")
            }

            if let occurredAt = draft.occurredAt {
                Label(occurredAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }

            ForEach(draft.warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(red: 0.66, green: 0.29, blue: 0.03))
                        .accessibilityHidden(true)

                    Text(warning)
                        .foregroundStyle(.primary)
                }
                .font(.caption)
            }
        }
        .font(.subheadline)
        .padding(FinanceGlassTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
