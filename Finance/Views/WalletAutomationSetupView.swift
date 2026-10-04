//
//  WalletAutomationSetupView.swift
//  Finance
//
//  Created by Codex on 11/08/2026.
//

import AppIntents
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Guía para crear en Atajos una automatización personal de pagos de Wallet.
struct WalletAutomationSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.large) {
                introduction
                templateImport
                automationSteps
            }
            .padding(.horizontal, 20)
            .padding(.top, FinanceGlassTokens.Spacing.large)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(FinanceGlassBackground().ignoresSafeArea())
        .navigationTitle("Pagos con Wallet")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.small) {
            Label {
                Text("Configurar en Atajos")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "wallet.pass.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityAddTraits(.isHeader)

            Text("Importa la plantilla y completa estos pasos en Atajos.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var templateImport: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            sectionHeading("Importa la plantilla")

            if let templateURL {
                ShareLink(
                    item: WalletShortcutTemplate(url: templateURL),
                    preview: SharePreview("Plantilla de pagos con Wallet")
                ) {
                    Label("Importar plantilla", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Abre la hoja de compartir para añadir el atajo de Wallet a Atajos.")
                Text("Si no aparece Atajos, guarda el archivo en Archivos y ábrelo desde allí.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label {
                    Text("No se encuentra la plantilla de Wallet en esta versión de Finance. Actualiza la app o vuelve a intentarlo más tarde.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.body)
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FinanceGlassTokens.Spacing.medium)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var templateURL: URL? {
        Bundle.main.url(forResource: "Finance-Wallet-plantilla-universal", withExtension: "shortcut")
    }

    private var automationSteps: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            sectionHeading("En Atajos")
            WalletSetupStep(number: 1, title: "Selecciona las tarjetas", detail: "Abre la plantilla en Atajos. En «Al usar», marca las tarjetas Wallet de la misma cuenta.")
            WalletSetupStep(number: 2, title: "Añade Finance", detail: "Debajo de «Texto», añade «Registrar gasto desde Wallet».")

            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.small) {
                Text("3. Completa los campos")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Elige la cuenta bancaria y asigna:")
                    .font(.body)
                WalletFieldRow(label: "Importe", value: "Texto")
                WalletFieldRow(label: "Comercio", value: "Comercio")
                WalletFieldRow(label: "Tarjeta", value: "Tarjeta o pase")
                WalletFieldRow(label: "Fecha", value: "Fecha actual")
                WalletFieldRow(label: "Moneda", value: "Código de Finance (p. ej. EUR)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Activa solo tarjetas que siempre paguen en esa moneda.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            WalletSetupStep(number: 4, title: "Activa la automatización", detail: "En «Al usar», activa «Automatización». En Información → Privacidad, permite ejecutar con el iPhone bloqueado.")

            Text("Categoría: déjala vacía o usa «Preguntar cada vez» (pedirá intervención al pagar).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Abrir Atajos de Finance")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FinanceGlassTokens.Spacing.medium)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct WalletShortcutTemplate: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            exportedContentType: UTType(importedAs: "com.apple.shortcut", conformingTo: .data)
        ) { template in
            SentTransferredFile(template.url)
        }
    }
}

private struct WalletFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FinanceGlassTokens.Spacing.small) {
            Text(label)
                .foregroundStyle(.primary)
            Spacer(minLength: FinanceGlassTokens.Spacing.small)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WalletSetupStep: View {
    @ScaledMetric(relativeTo: .headline) private var markerSize = 36.0

    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: FinanceGlassTokens.Spacing.medium) {
            Text(number, format: .number)
                .font(.headline)
                .foregroundStyle(Color.financeAccent)
                .frame(width: markerSize, height: markerSize)
                .background(Color.financeAccent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paso \(number): \(title). \(detail)")
    }
}

#Preview {
    NavigationStack {
        WalletAutomationSetupView()
    }
}
