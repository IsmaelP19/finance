//
//  WalletAutomationSetupView.swift
//  Finance
//
//  Created by Codex on 11/08/2026.
//

import AppIntents
import SwiftUI

/// Guía para crear en Atajos una automatización personal por cada tarjeta de Wallet.
struct WalletAutomationSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xLarge) {
                introduction
                draftNotice
                setupSteps
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
                Text("Una automatización por tarjeta")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "wallet.pass.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityAddTraits(.isHeader)

            Text("iOS no permite que Finance cree esta automatización por ti. Debes crear una automatización personal en Atajos para cada tarjeta que quieras usar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FinanceGlassTokens.Spacing.xSmall)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var draftNotice: some View {
        HStack(alignment: .top, spacing: FinanceGlassTokens.Spacing.medium) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
                Text("Tú confirmas cada gasto")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Finance solo prepara un borrador. No guarda ningún gasto hasta que revisas o eliges la cuenta y la categoría y pulsas Guardar.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FinanceGlassTokens.Spacing.xSmall)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
        .accessibilityElement(children: .combine)
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            Text("Configura una tarjeta")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            WalletSetupStep(
                number: 1,
                title: "Crea la automatización",
                detail: "En Atajos, abre Automatización, crea una automatización de tipo Transacción y elige una tarjeta."
            )

            WalletSetupStep(
                number: 2,
                title: "Añade la acción de Finance",
                detail: "Busca «Preparar gasto desde Wallet» y asigna las variables Importe, Comercio, Tarjeta y Fecha de la transacción."
            )

            WalletSetupStep(
                number: 3,
                title: "Configura la ejecución",
                detail: "Selecciona ejecución inmediata y desactiva la confirmación previa si aparece."
            )

            WalletSetupStep(
                number: 4,
                title: "Repite por cada tarjeta",
                detail: "iOS crea estas automatizaciones por tarjeta. Repite los pasos para cada tarjeta que quieras usar con Finance."
            )
        }
    }

    private var shortcutsLink: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
                Text("Abre los Atajos de Finance")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text("Este enlace te ayuda a localizar la acción de Finance. No crea ni configura la automatización.")
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
        .padding(FinanceGlassTokens.Spacing.xSmall)
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
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
        .padding(FinanceGlassTokens.Spacing.xSmall)
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
