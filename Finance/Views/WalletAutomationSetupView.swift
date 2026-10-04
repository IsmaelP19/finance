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
                amountExplanation
                fieldMapping
                testInstructions
                shortcutsLink
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

            Text("La plantilla prepara el disparador de Wallet y el importe. Para registrar movimientos, añade después la acción local de Finance y completa sus campos: cada instalación de la app tiene una firma distinta.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var templateImport: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
                Text("1. Añade la plantilla universal")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text("Comparte o importa el atajo firmado para cualquiera. Incluye el disparador de Wallet y Texto con el importe; no incluye la acción de Finance.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let templateURL {
                ShareLink(
                    item: WalletShortcutTemplate(url: templateURL),
                    preview: SharePreview("Plantilla de pagos con Wallet")
                ) {
                    Label("Compartir o importar plantilla", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Abre la hoja de compartir para añadir el atajo de Wallet a Atajos.")
                Text("Si Atajos no aparece en la hoja, guarda el archivo .shortcut en Archivos y ábrelo desde allí para importarlo en Atajos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(FinanceGlassTokens.Spacing.medium)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var templateURL: URL? {
        Bundle.main.url(forResource: "Finance-Wallet-plantilla-universal", withExtension: "shortcut")
    }

    private var automationSteps: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            sectionHeading("2. Completa la automatización en Atajos (iOS 27)")
            WalletSetupStep(number: 1, title: "Abre y edita la plantilla", detail: "En Atajos, abre la plantilla que acabas de añadir y entra en Editar. En Automatización de Wallet, selecciona Al usar una tarjeta y marca las tarjetas que quieras. Puedes reutilizar una automatización para varias tarjetas si todas van a la misma cuenta.")
            WalletSetupStep(number: 2, title: "Añade la acción de Finance", detail: "Debajo de Texto, busca y añade «Registrar gasto desde Wallet». Esta acción se añade en tu dispositivo porque la plantilla no puede incluir una acción firmada para otra instalación de Finance.")
            WalletSetupStep(number: 3, title: "Elige cuenta y asigna los campos", detail: "Selecciona la cuenta bancaria. Asigna Importe a la salida de Texto, Comercio y Tarjeta a los datos del disparador de Wallet, Fecha a Fecha actual y Moneda al código configurado en Finance.")
            WalletSetupStep(number: 4, title: "Activa la automatización", detail: "Guarda el atajo y activa el interruptor «Automatización». En Editar → Información → Privacidad, activa «Permitir ejecutar con el iPhone bloqueado» si quieres que funcione con el móvil bloqueado.")
        }
    }

    private var amountExplanation: some View {
        HStack(alignment: .top, spacing: FinanceGlassTokens.Spacing.medium) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.headline)
                .foregroundStyle(Color.financeAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
                Text("Por qué va Importe dentro de Texto")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("La plantilla pone el importe de Wallet dentro de Texto para que puedas conectarlo con el campo Importe de Finance al añadir la acción local.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
        .accessibilityElement(children: .combine)
    }

    private var fieldMapping: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            sectionHeading("Asignación de campos")
            MappingRow(title: "Importe", detail: "Salida de Texto, que contiene la variable Importe de Wallet.")
            MappingRow(title: "Comercio y Tarjeta", detail: "Selecciona Comercio y Tarjeta en las variables del disparador de Wallet.")
            MappingRow(title: "Cuenta", detail: "Elige la cuenta donde se registrarán los pagos. Una automatización con varias tarjetas usa la misma cuenta para todas.")
            MappingRow(title: "Fecha", detail: "Selecciona Fecha actual.")
            MappingRow(title: "Moneda", detail: "Indica el código de moneda configurado en Finance, por ejemplo EUR.")
            Label("Si una tarjeta puede pagar en una moneda distinta a la configurada en Finance, el importe podría registrarse mal. No actives esa tarjeta hasta garantizar que la moneda real del pago coincide.", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            MappingRow(title: "Categoría", detail: "Opcional. Déjala vacía para clasificar después o usa «Preguntar cada vez» si quieres elegirla al ejecutar; esa opción requiere interacción y no será totalmente automática.")
        }
    }

    private var testInstructions: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.small) {
            Label("Prueba sin comprar", systemImage: "checkmark.shield")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Crea un atajo normal temporal con Texto «12,50» seguido de «Registrar gasto desde Wallet». Elige una cuenta de prueba, ejecútalo y comprueba el movimiento ficticio en Finance. Después, bórralo. Esta prueba comprueba la acción de Finance, pero no simula el disparador de Wallet.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var shortcutsLink: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
                Text("Abrir Atajos de Finance")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text("Usa este enlace si necesitas volver a localizar la acción de Finance. Abrir Atajos por sí solo no añade la acción a la automatización.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Abrir Atajos de Finance")
                .accessibilityHint("Abre Atajos para localizar las acciones publicadas por Finance.")
        }
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

private struct MappingRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FinanceGlassTokens.Spacing.small)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.row)
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
        .padding(FinanceGlassTokens.Spacing.small)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paso \(number): \(title). \(detail)")
    }
}

#Preview {
    NavigationStack {
        WalletAutomationSetupView()
    }
}
