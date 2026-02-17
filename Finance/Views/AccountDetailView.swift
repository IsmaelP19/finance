//
//  AccountDetailView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData
import Charts

/// Pantalla de detalle de una cuenta bancaria.
/// Muestra toda la información y permite editar o eliminar la cuenta.
struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \InvestmentSnapshot.snapshotDate, order: .forward) private var snapshots: [InvestmentSnapshot]

    @Bindable var account: BankAccount

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingInvestedUpdateSheet = false
    @State private var showingMarketValueUpdateSheet = false

    private var accountSnapshots: [InvestmentSnapshot] {
        snapshots
            .filter { $0.account?.id == account.id }
            .sorted { $0.snapshotDate < $1.snapshotDate }
    }

    var body: some View {
        List {
            // Cabecera con icono del tipo de cuenta y saldo
            Section {
                VStack(spacing: 12) {
                    Image(systemName: account.accountType.icon)
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(account.accountType.color)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    Text(account.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(account.bankDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(account.balance.asCurrency())
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(account.balance.isNegative ? .red : .primary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }

            // Información detallada
            Section("Detalles") {
                DetailRow(label: "Banco", value: account.bankDisplayName)
                DetailRow(label: "Tipo", value: account.accountType.displayName)
                DetailRow(label: "Moneda", value: appCurrencyCode)
                DetailRow(
                    label: "Creada",
                    value: account.createdAt.asSpanishDateTime()
                )
                DetailRow(
                    label: "Última actualización",
                    value: account.updatedAt.asSpanishDateTime()
                )
            }

            if account.isInvestmentAccount {
                Section("Evolución") {
                    if accountSnapshots.isEmpty {
                        ContentUnavailableView(
                            "Sin histórico",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Actualiza inversión y valor de mercado para empezar la serie temporal")
                        )
                    } else {
                        InvestmentHistoryChartView(
                            snapshots: accountSnapshots,
                            currencyCode: appCurrencyCode
                        )
                    }
                }

                Section("Inversión") {
                    DetailRow(label: "Cantidad invertida", value: account.effectiveInvestedAmount.asCurrency(code: appCurrencyCode))
                    DetailRow(label: "Valor de mercado", value: account.effectiveMarketValue.asCurrency(code: appCurrencyCode))

                    DetailRow(
                        label: "Rentabilidad",
                        value: account.investmentProfit.asCurrency(code: appCurrencyCode),
                        valueColor: account.investmentProfit.isNegative ? .red : .green
                    )

                    if let returnPercent = account.investmentReturnPercent {
                        DetailRow(
                            label: "Rentabilidad %",
                            value: returnPercent.asPercent(),
                            valueColor: returnPercent.isNegative ? .red : .green
                        )
                    }

                    if let marketValueUpdatedAt = account.marketValueUpdatedAt {
                        DetailRow(label: "Mercado actualizado", value: marketValueUpdatedAt.asSpanishDateTime())
                    }
                }

                Section("Actualización de inversión") {
                    Button {
                        showingInvestedUpdateSheet = true
                    } label: {
                        Label("Actualizar cantidad invertida", systemImage: "plus.circle")
                    }

                    Button {
                        showingMarketValueUpdateSheet = true
                    } label: {
                        Label("Actualizar valor de mercado", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }

            // Notas
            if !account.notes.isEmpty {
                Section("Notas") {
                    Text(account.notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Acciones
            Section {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Editar cuenta", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Eliminar cuenta", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditSheet) {
            AddAccountView(existingAccount: account)
        }
        .sheet(isPresented: $showingInvestedUpdateSheet) {
            InvestmentValueUpdateSheet(
                title: "Cantidad invertida",
                initialValue: account.effectiveInvestedAmount,
                currencyCode: appCurrencyCode,
                onSave: { value, snapshotDate in
                    upsertInvestmentSnapshot(
                        on: snapshotDate,
                        investedAmount: value,
                        marketValue: nil
                    )

                    if isToday(snapshotDate) {
                        account.investedAmount = value
                        account.updatedAt = Date()
                    }
                }
            )
        }
        .sheet(isPresented: $showingMarketValueUpdateSheet) {
            InvestmentValueUpdateSheet(
                title: "Valor de mercado",
                initialValue: account.effectiveMarketValue,
                currencyCode: appCurrencyCode,
                onSave: { value, snapshotDate in
                    upsertInvestmentSnapshot(
                        on: snapshotDate,
                        investedAmount: nil,
                        marketValue: value
                    )

                    if shouldUpdateCurrentMarketValue(using: snapshotDate) {
                        account.marketValue = value
                        account.marketValueUpdatedAt = snapshotDate
                        account.balance = value
                        account.updatedAt = Date()
                    }
                }
            )
        }
        .confirmationDialog(
            "¿Eliminar cuenta?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                modelContext.delete(account)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará la cuenta \"\(account.name)\" permanentemente. Esta acción no se puede deshacer.")
        }
    }

    private func upsertInvestmentSnapshot(on date: Date, investedAmount: Decimal?, marketValue: Decimal?) {
        let normalizedDate = Calendar.current.startOfDay(for: date)

        if let existing = accountSnapshots.first(where: { Calendar.current.isDate($0.snapshotDate, inSameDayAs: normalizedDate) }) {
            if let investedAmount {
                existing.investedAmount = investedAmount
            }
            if let marketValue {
                existing.marketValue = marketValue
            }
            existing.updatedAt = Date()
            return
        }

        let snapshot = InvestmentSnapshot(
            snapshotDate: normalizedDate,
            investedAmount: investedAmount ?? account.effectiveInvestedAmount,
            marketValue: marketValue ?? account.effectiveMarketValue,
            account: account
        )
        modelContext.insert(snapshot)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func shouldUpdateCurrentMarketValue(using snapshotDate: Date) -> Bool {
        guard let current = account.marketValueUpdatedAt else { return true }
        let selectedDay = Calendar.current.startOfDay(for: snapshotDate)
        let currentDay = Calendar.current.startOfDay(for: current)
        return selectedDay >= currentDay
    }
}

// MARK: - Componente auxiliar

/// Fila de detalle con etiqueta y valor.
private struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
        }
    }
}

private struct InvestmentValueUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialValue: Decimal
    let currencyCode: String
    let onSave: (Decimal, Date) -> Void

    @State private var valueText = ""
    @State private var snapshotDate = Date()
    @State private var showingAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section(title) {
                    HStack {
                        TextField("0,00", text: $valueText)
                        Text(currencyCode)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Fecha") {
                    DatePicker("Fecha del dato", selection: $snapshotDate, displayedComponents: .date)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                valueText = formatDecimal(initialValue)
            }
            .alert("Importe inválido", isPresented: $showingAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text("Introduce un importe válido mayor o igual que cero.")
            }
        }
    }

    private func save() {
        let parsed = parseDecimal(valueText)
        guard parsed >= 0 else {
            showingAlert = true
            return
        }

        onSave(parsed, snapshotDate)
        dismiss()
    }

    private func parseDecimal(_ text: String) -> Decimal {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned) ?? -1
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

private struct InvestmentHistoryChartView: View {
    let snapshots: [InvestmentSnapshot]
    let currencyCode: String

    var body: some View {
        Chart {
            ForEach(snapshots) { snapshot in
                LineMark(
                    x: .value("Fecha", snapshot.snapshotDate),
                    y: .value("Invertido", snapshot.investedAmount.asDouble)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                LineMark(
                    x: .value("Fecha", snapshot.snapshotDate),
                    y: .value("Mercado", snapshot.marketValue.asDouble)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .frame(height: 220)
        .chartLegend(position: .bottom) {
            HStack(spacing: 12) {
                legendItem(color: .orange, text: "Invertido")
                legendItem(color: .blue, text: "Mercado")
            }
        }

        if let latest = snapshots.last {
            HStack {
                Text("Último mercado")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(latest.marketValue.asCurrency(code: currencyCode))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.top, 4)
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension Decimal {
    var asDouble: Double {
        (self as NSDecimalNumber).doubleValue
    }

    func asPercent() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        let formatted = formatter.string(from: self as NSDecimalNumber) ?? "0,00"
        return "\(formatted)%"
    }
}
