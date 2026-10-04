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
                registrationNotice
                setupSteps
                Text("Si prefieres revisar cada pago antes de guardarlo, puedes usar «Preparar gasto desde Wallet». Los pagos en una moneda distinta a la configurada en Finance no se registran automáticamente.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var registrationNotice: some View {
        HStack(alignment: .top, spacing: FinanceGlassTokens.Spacing.medium) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xSmall) {
                Text("El gasto se registra automáticamente")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("El pago se guarda sin abrir Finance en la cuenta que elijas para esa tarjeta. Puedes dejar la categoría vacía y asignarla después.")
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
                detail: "Busca «Registrar gasto desde Wallet» y asigna las variables Importe, Comercio, Tarjeta y Fecha de la transacción. Importe debe recibirse como texto, por ejemplo «12,50» o «12.50», sin separadores de miles. Para una variable del pago, conviértela a texto conservando los decimales."
            )

            WalletSetupStep(
                number: 3,
                title: "Asocia la cuenta bancaria",
                detail: "Elige una cuenta fija de Finance para esta tarjeta y asigna la moneda real de cada pago (EUR, USD, GBP o JPY). No fijes EUR si esa tarjeta puede pagar en otra moneda. La categoría es opcional."
            )

            WalletSetupStep(
                number: 4,
                title: "Configura la ejecución inmediata",
                detail: "Selecciona ejecución inmediata y desactiva la confirmación previa si aparece. Repite los pasos por cada tarjeta con su cuenta correspondiente."
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
