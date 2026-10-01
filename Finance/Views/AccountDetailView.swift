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
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    @Query(sort: \InvestmentSnapshot.snapshotDate, order: .forward) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]

    @Bindable var account: BankAccount

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showingInvestedUpdateSheet = false
    @State private var showingMarketValueUpdateSheet = false

    private var accountSnapshots: [InvestmentSnapshot] {
        InvestmentSnapshot.dailySnapshots(
            from: snapshots.filter { $0.account?.id == account.id }
        )
    }

    var body: some View {
        List {
            Section {
                AccountDetailHero(account: account, currencyCode: appCurrencyCode, hideBalances: hideBalances)
            }
            .financeGlassClearListRow()

            if account.isInvestmentAccount {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        FinanceGlassSectionHeader(title: "Evolución", systemImage: "chart.line.uptrend.xyaxis")

                        investmentHistoryContent(for: self.accountSnapshots)
                            .investmentGlassPanel()
                    }
                }
                .financeGlassClearListRow()

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        FinanceGlassSectionHeader(title: "Inversión", systemImage: "chart.pie.fill")
                        InvestmentSummaryCard(
                            account: account,
                            snapshots: accountSnapshots,
                            currencyCode: appCurrencyCode,
                            hideBalances: hideBalances
                        )
                    }
                }
                .financeGlassClearListRow()
            }

            // Notas
            if !account.notes.isEmpty {
                Section {
                    AccountNotesCard(notes: account.notes)
                }
                .financeGlassClearListRow()
            }

            if account.isArchived {
                Section {
                    Label("Cuenta eliminada", systemImage: "archivebox.fill")
                        .foregroundStyle(.secondary)
                    Text("Esta cuenta está oculta de Mis cuentas. Sus movimientos se conservan como histórico y no se pueden modificar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .financeGlassFormSection()
            }
        }
        .financeGlassListContainer()
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if account.isInvestmentAccount && !account.isArchived {
                InvestmentUpdateFloatingBar(
                    onUpdateInvested: { showingInvestedUpdateSheet = true },
                    onUpdateMarket: { showingMarketValueUpdateSheet = true }
                )
                .padding(.horizontal, 44)
                .padding(.bottom, 10)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    hideBalances.toggle()
                } label: {
                    Image(systemName: hideBalances ? "eye.slash" : "eye")
                        .financeToolbarIconStyle()
                }
                .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")

                if !account.isArchived {
                    Menu {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("Editar cuenta", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label {
                                Text("Eliminar cuenta")
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                        }
                        .tint(.red)
                    } label: {
                        Image(systemName: "ellipsis")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Acciones de cuenta")
                }
            }
        }
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
                deleteAccount()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La cuenta se ocultará permanentemente de Mis cuentas y dejará de aparecer en filtros y selectores. Sus movimientos se conservarán como histórico: seguirán visibles por mes y búsqueda, pero no podrás filtrarlos por cuenta ni editarlos o eliminarlos. Si hay reembolsos pendientes, podrás registrarlos en otra cuenta activa distinta. Esta acción es irreversible.")
        }
        .alert("No se pudo eliminar la cuenta", isPresented: $showingDeleteError) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
    }

    @ViewBuilder
    private func investmentHistoryContent(for accountSnapshots: [InvestmentSnapshot]) -> some View {
        if accountSnapshots.isEmpty {
            FinanceEmptyStateContent(
                "Sin histórico",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Actualiza inversión y valor de mercado para empezar la serie temporal")
            )
            .padding(.vertical, 22)
        } else {
            InvestmentHistoryChartView(
                snapshots: accountSnapshots,
                currencyCode: appCurrencyCode,
                hideBalances: hideBalances
            )
        }
    }

    private func deleteAccount() {
        CrashReportService.shared.recordBreadcrumb("Eliminando cuenta desde su detalle")

        do {
            try AccountDeletionService.delete(account, allMovements: movements, recurringMovements: recurringMovements, in: modelContext)
            showingEditSheet = false
            showingInvestedUpdateSheet = false
            showingMarketValueUpdateSheet = false
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
            showingDeleteError = true
        }
    }

    private func upsertInvestmentSnapshot(on date: Date, investedAmount: Decimal?, marketValue: Decimal?) {
        let normalizedDate = Calendar.current.startOfDay(for: date)

        if let existing = InvestmentSnapshot.latestSnapshot(
            on: normalizedDate,
            from: snapshots.filter { $0.account?.id == account.id }
        ) {
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

private struct AccountDetailHero: View {
    let account: BankAccount
    let currencyCode: String
    let hideBalances: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accent: Color { account.bank?.color ?? account.accountType.color }
    private var typeTint: Color { account.accountType.color }
    private var iconName: String { account.bank?.iconName ?? account.accountType.icon }
    private var balanceText: String { account.balance.masked(hideBalances, code: currencyCode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(account.accountType.displayName)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(typeTint.opacity(0.16), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(typeTint.opacity(0.32), lineWidth: 1)
                        )

                    Text(account.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(account.bankDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Saldo disponible")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(balanceText)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 30 : 38, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)
                    .foregroundStyle(account.balance.isNegative ? .red : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeGlassColorCard(
            gradient: LinearGradient(colors: [accent.opacity(0.24), account.accountType.color.opacity(0.12), Color.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
            cornerRadius: FinanceGlassTokens.Radius.hero
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name), \(account.bankDisplayName), \(account.accountType.displayName), saldo \(hideBalances ? "oculto" : balanceText), actualizada \(account.updatedAt.asSpanishDateTime())")
    }
}

private struct AccountNotesCard: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("Notas")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }

            Text(notes)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notas, \(notes)")
    }
}

private struct AccountMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceGlassIconBadge(systemName: icon, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeInsetCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct InvestmentSummaryCard: View {
    let account: BankAccount
    let snapshots: [InvestmentSnapshot]
    let currencyCode: String
    let hideBalances: Bool

    private var profitTint: Color {
        account.investmentProfit.isNegative ? .red : .green
    }

    private var returnPercentText: String {
        account.investmentReturnPercent?.asPercent() ?? "—"
    }

    private var maximumReturnSnapshot: (snapshot: InvestmentSnapshot, percentage: Decimal)? {
        InvestmentSnapshot.maximumReturnSnapshot(from: snapshots)
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    InvestmentMetricTile(
                        title: "Invertido",
                        value: account.effectiveInvestedAmount.masked(hideBalances, code: currencyCode),
                        systemImage: "tray.and.arrow.down.fill",
                        tint: .purple
                    )

                    InvestmentMetricTile(
                        title: "Mercado",
                        value: account.effectiveMarketValue.masked(hideBalances, code: currencyCode),
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .blue
                    )
                }

                HStack(spacing: 10) {
                    InvestmentMetricTile(
                        title: "Rentabilidad",
                        value: account.investmentProfit.masked(hideBalances, code: currencyCode),
                        systemImage: account.investmentProfit.isNegative ? "arrow.down.right" : "arrow.up.right",
                        tint: profitTint,
                        valueColor: profitTint
                    )

                    InvestmentMetricTile(
                        title: "Rentabilidad %",
                        value: hideBalances ? "••••" : returnPercentText,
                        systemImage: "percent",
                        tint: profitTint,
                        valueColor: profitTint
                    )
                }

                if let maximumReturnSnapshot {
                    InvestmentMetricTile(
                        title: "Máxima rentabilidad",
                        value: hideBalances ? "••••" : maximumReturnSnapshot.percentage.asPercent(),
                        systemImage: "percent",
                        tint: maximumReturnSnapshot.percentage.isNegative ? .red : .green,
                        valueColor: maximumReturnSnapshot.percentage.isNegative ? .red : .green,
                        secondarySubtitle: "Equivale a \((maximumReturnSnapshot.snapshot.marketValue - maximumReturnSnapshot.snapshot.investedAmount).masked(hideBalances, code: currencyCode))",
                        subtitle: "Registrada el \(maximumReturnSnapshot.snapshot.snapshotDate.asSpanishShortDate())",
                        emphasized: true
                    )
                }
            }

            if let marketValueUpdatedAt = account.marketValueUpdatedAt {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mercado actualizado")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(marketValueUpdatedAt.asSpanishDateTime())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
                .padding(.horizontal, 2)
            }

        }
        .investmentGlassPanel()
        .accessibilityElement(children: .contain)
    }
}

private struct InvestmentUpdateFloatingBar: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var highlightedSegment: InvestmentFloatingSegment?

    let onUpdateInvested: () -> Void
    let onUpdateMarket: () -> Void

    private let barHeight: CGFloat = 48
    private let highlightInset: CGFloat = 0.8

    var body: some View {
        buttonContent
            .frame(height: barHeight)
            .padding(3)
            .frame(maxWidth: 344)
            .background {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 0) {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular, in: Capsule())
                    }
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.13), lineWidth: 0.5)
            }
            .overlay {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.055 : 0.095),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(1.2)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
    }

    private var buttonContent: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segmentWidth = width / 2

            ZStack(alignment: .leading) {
                if let highlightedSegment {
                    investmentFloatingHighlight
                        .frame(width: max(0, segmentWidth - highlightInset * 2))
                        .padding(.vertical, highlightInset)
                        .offset(x: highlightedSegment.highlightOffset(segmentWidth: segmentWidth, inset: highlightInset))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 0) {
                    InvestmentFloatingSegmentLabel(
                        title: "Invertido",
                        systemImage: "plus",
                        accessibilityLabel: "Actualizar cantidad invertida",
                        action: onUpdateInvested
                    )

                    InvestmentFloatingSegmentLabel(
                        title: "Mercado",
                        systemImage: "chart.line.uptrend.xyaxis",
                        accessibilityLabel: "Actualizar valor de mercado",
                        action: onUpdateMarket
                    )
                }

                centerDivider
            }
            .contentShape(Capsule())
            .gesture(pressTransferGesture(width: width))
            .animation(.snappy(duration: 0.18), value: highlightedSegment)
        }
    }

    private var investmentFloatingHighlight: some View {
        Capsule(style: .continuous)
            .fill(.clear)
            .background {
                if #available(iOS 26, *) {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .glassEffect(
                            .regular
                                .tint(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18))
                                .interactive(),
                            in: Capsule(style: .continuous)
                        )
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.46),
                                Color.financeAccent.opacity(colorScheme == .dark ? 0.045 : 0.035),
                                Color.white.opacity(colorScheme == .dark ? 0.035 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.38 : 0.72),
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22),
                                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .compositingGroup()
    }

    private var centerDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        colorScheme == .dark ? Color.white.opacity(0.24) : Color.primary.opacity(0.18),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func pressTransferGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                highlightedSegment = InvestmentFloatingSegment(locationX: value.location.x, width: width)
            }
            .onEnded { value in
                let endedSegment = InvestmentFloatingSegment(locationX: value.location.x, width: width)

                switch endedSegment {
                case .invested:
                    onUpdateInvested()
                case .market:
                    onUpdateMarket()
                case nil:
                    break
                }

                highlightedSegment = nil
            }
    }
}

private enum InvestmentFloatingSegment {
    case invested
    case market

    init?(locationX: CGFloat, width: CGFloat) {
        guard width > 0, locationX >= 0, locationX <= width else { return nil }
        self = locationX < width / 2 ? .invested : .market
    }

    func highlightOffset(segmentWidth: CGFloat, inset: CGFloat) -> CGFloat {
        switch self {
        case .invested:
            inset
        case .market:
            segmentWidth + inset
        }
    }
}

private struct InvestmentGlassPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct InvestmentFloatingSegmentLabel: View {
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
    }
}

private extension View {
    func investmentGlassPanel() -> some View {
        modifier(InvestmentGlassPanelModifier())
    }
}

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
                Section {
                    HStack {
                        TextField("0,00", text: $valueText)
                            .keyboardType(.decimalPad)
                        CurrencySymbolLabel(code: currencyCode, companion: .body)
                    }
                } header: {
                    FinanceGlassSectionHeader(title: title, systemImage: "eurosign.circle.fill")
                }
                .financeGlassFormSection()

                Section {
                    DatePicker("Fecha del dato", selection: $snapshotDate, displayedComponents: .date)
                } header: {
                    FinanceGlassSectionHeader(title: "Fecha", systemImage: "calendar")
                }
                .financeGlassFormSection()
            }
            .financeGlassListContainer()
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
                valueText = initialValue.asEditableAmount()
            }
            .onChange(of: valueText) { _, newValue in
                let sanitized = EditableAmount.sanitizeInput(newValue)
                if sanitized != newValue {
                    valueText = sanitized
                }
            }
            .alert("Importe inválido", isPresented: $showingAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text("Introduce un importe válido mayor o igual que cero.")
            }
        }
    }

    private func save() {
        guard let parsed = EditableAmount.parse(valueText), parsed >= 0 else {
            showingAlert = true
            return
        }

        onSave(parsed, snapshotDate)
        dismiss()
    }
}

private enum InvestmentChartRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth:
            return "1M"
        case .threeMonths:
            return "3M"
        case .sixMonths:
            return "6M"
        case .oneYear:
            return "1A"
        case .all:
            return "Todo"
        }
    }

    func startDate(relativeTo reference: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: reference)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: reference)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: reference)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: reference)
        case .all:
            return nil
        }
    }
}

private struct InvestmentHistoryChartView: View {
    let snapshots: [InvestmentSnapshot]
    let currencyCode: String
    let hideBalances: Bool

    @State private var selectedRange: InvestmentChartRange = .sixMonths

    private var displayedSnapshots: [InvestmentSnapshot] {
        guard let latestDate = snapshots.last?.snapshotDate else { return snapshots }
        guard let startDate = selectedRange.startDate(relativeTo: latestDate) else { return snapshots }

        let filtered = snapshots.filter { $0.snapshotDate >= startDate }
        return filtered.isEmpty ? [snapshots.last].compactMap { $0 } : filtered
    }

    private var bestAvailableRange: InvestmentChartRange {
        let preferredOrder: [InvestmentChartRange] = [.sixMonths, .threeMonths, .oneMonth, .oneYear, .all]
        return preferredOrder.first(where: isRangeAvailable) ?? .all
    }

    private var hasUnavailableRanges: Bool {
        InvestmentChartRange.allCases.contains { !isRangeAvailable($0) }
    }

    var body: some View {
        let displayedSnapshotsForBody = self.displayedSnapshots

        VStack(alignment: .leading, spacing: 12) {
            Text("Evolución del fondo")
                .font(.headline)

            rangeSelector

            if hasUnavailableRanges {
                Text("Los rangos se habilitan según el histórico disponible.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            InvestmentHistoryChartPlotView(
                snapshots: displayedSnapshotsForBody,
                currencyCode: currencyCode,
                hideBalances: hideBalances,
                selectionResetID: "\(selectedRange.rawValue)-\(hideBalances)"
            )
        }
        .onAppear {
            if !isRangeAvailable(selectedRange) {
                selectedRange = bestAvailableRange
            }
        }
        .onChange(of: snapshots.count) { _, _ in
            if !isRangeAvailable(selectedRange) {
                selectedRange = bestAvailableRange
            }
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 8) {
            ForEach(InvestmentChartRange.allCases) { range in
                Button {
                    guard isRangeAvailable(range) else { return }
                    selectedRange = range
                } label: {
                    Text(range.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedRange == range ? .white : (isRangeAvailable(range) ? .secondary : .secondary.opacity(0.6)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedRange == range
                                ? Color.black
                                : (isRangeAvailable(range) ? Color.gray.opacity(0.14) : Color.gray.opacity(0.22))
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isRangeAvailable(range))
                .opacity(isRangeAvailable(range) ? 1 : 0.55)
            }
        }
    }

    private func isRangeAvailable(_ range: InvestmentChartRange) -> Bool {
        guard range != .all else { return true }
        guard let latestDate = snapshots.last?.snapshotDate else { return false }
        guard let firstDate = snapshots.first?.snapshotDate else { return false }
        guard let startDate = range.startDate(relativeTo: latestDate) else { return false }
        return firstDate <= startDate
    }
}

private struct InvestmentHistoryChartPlotView: View {
    let snapshots: [InvestmentSnapshot]
    let currencyCode: String
    let hideBalances: Bool
    let selectionResetID: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    private let investedColor = Color(red: 0.58, green: 0.86, blue: 0.89)
    private let marketColor = Color(red: 0.96, green: 0.26, blue: 0.50)
    private let xDomain: ClosedRange<Date>
    private let yDomain: ClosedRange<Double>
    private let renderSnapshots: [InvestmentSnapshot]

    init(
        snapshots: [InvestmentSnapshot],
        currencyCode: String,
        hideBalances: Bool,
        selectionResetID: String
    ) {
        self.snapshots = snapshots
        self.currencyCode = currencyCode
        self.hideBalances = hideBalances
        self.selectionResetID = selectionResetID
        self.xDomain = Self.chartXDomain(for: snapshots)
        self.yDomain = Self.chartYDomain(for: snapshots)
        self.renderSnapshots = Self.visualSnapshots(for: snapshots)
    }

    var body: some View {
        let highlightedSnapshot = highlightedSnapshot(in: snapshots)
        let areaBaseline = yDomain.lowerBound

        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(renderSnapshots) { snapshot in
                    AreaMark(
                        x: .value("Fecha", snapshot.snapshotDate),
                        yStart: .value("Base", areaBaseline),
                        yEnd: .value("Aportación neta", snapshot.investedAmount.asDouble)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [investedColor.opacity(0.45), investedColor.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Fecha", snapshot.snapshotDate),
                        y: .value("Valor de mercado", snapshot.marketValue.asDouble)
                    )
                    .foregroundStyle(marketColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                if let highlightedSnapshot {
                    RuleMark(x: .value("Selección", highlightedSnapshot.snapshotDate))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Fecha", highlightedSnapshot.snapshotDate),
                        y: .value("Mercado", highlightedSnapshot.marketValue.asDouble)
                    )
                    .symbolSize(70)
                    .foregroundStyle(marketColor)
                }
            }
            .id(hideBalances)
            .frame(height: 250)
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartPlotStyle { plot in
                plot
                    .clipped()
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.25))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(Decimal(doubleValue).asCurrency(code: currencyCode))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(
                                        at: value.location,
                                        proxy: proxy,
                                        geometry: geometry,
                                        snapshots: snapshots
                                    )
                                }
                                .onEnded { _ in
                                    setSelectedDate(nil)
                                }
                        )
                }
            }

            if let highlightedSnapshot {
                selectionCard(for: highlightedSnapshot)
            }

            if snapshots.count <= 1, let onlySnapshot = snapshots.first {
                Label(
                    "Solo hay un registro (\(onlySnapshot.snapshotDate.asSpanishShortDate())). Añade más días para ver la tendencia.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: selectionResetID) { _, _ in
            setSelectedDate(nil)
        }
    }

    private func selectionCard(for snapshot: InvestmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Datos a \(snapshot.snapshotDate.asSpanishShortDate())")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                legendItem(
                    color: marketColor,
                    text: "Valor de mercado",
                    value: snapshot.marketValue.masked(hideBalances, code: currencyCode)
                )
                Spacer()
            }

            HStack {
                legendItem(
                    color: investedColor,
                    text: "Aportación neta",
                    value: snapshot.investedAmount.masked(hideBalances, code: currencyCode)
                )
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func legendItem(color: Color, text: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    private static func chartXDomain(for snapshots: [InvestmentSnapshot]) -> ClosedRange<Date> {
        guard let first = snapshots.first?.snapshotDate,
              let last = snapshots.last?.snapshotDate else {
            let now = Date()
            return now...now
        }

        if first == last {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -3, to: first) ?? first
            let end = calendar.date(byAdding: .day, value: 3, to: first) ?? first
            return start...end
        }

        return first...last
    }

    private static func chartYDomain(for snapshots: [InvestmentSnapshot]) -> ClosedRange<Double> {
        guard let firstSnapshot = snapshots.first else { return 0...1 }

        var minValue = min(firstSnapshot.investedAmount.asDouble, firstSnapshot.marketValue.asDouble)
        var maxValue = max(firstSnapshot.investedAmount.asDouble, firstSnapshot.marketValue.asDouble)

        for snapshot in snapshots.dropFirst() {
            minValue = min(minValue, snapshot.investedAmount.asDouble, snapshot.marketValue.asDouble)
            maxValue = max(maxValue, snapshot.investedAmount.asDouble, snapshot.marketValue.asDouble)
        }

        let span = maxValue - minValue
        let minPadding = max(abs(maxValue) * 0.05, 1)
        let padding = max(span * 0.12, minPadding)
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding

        if lower == upper {
            return max(0, lower - 1)...(upper + 1)
        }

        return lower...upper
    }

    private static func visualSnapshots(for snapshots: [InvestmentSnapshot]) -> [InvestmentSnapshot] {
        let maximumPointCount = 512
        guard snapshots.count > maximumPointCount else { return snapshots }

        let bucketCount = max(maximumPointCount / 4, 1)
        let bucketSize = Int(ceil(Double(snapshots.count) / Double(bucketCount)))
        var selectedIndices = Set<Int>()

        for bucket in 0..<bucketCount {
            let start = bucket * bucketSize
            guard start < snapshots.count else { break }
            let end = min(start + bucketSize, snapshots.count)
            let indices = start..<end
            selectedIndices.insert(start)
            selectedIndices.insert(end - 1)
            selectedIndices.insert(indices.min { Self.investedValue($0, snapshots) < Self.investedValue($1, snapshots) } ?? start)
            selectedIndices.insert(indices.max { Self.investedValue($0, snapshots) < Self.investedValue($1, snapshots) } ?? start)
            selectedIndices.insert(indices.min { Self.marketValue($0, snapshots) < Self.marketValue($1, snapshots) } ?? start)
            selectedIndices.insert(indices.max { Self.marketValue($0, snapshots) < Self.marketValue($1, snapshots) } ?? start)
        }

        return selectedIndices.sorted().map { snapshots[$0] }
    }

    private static func investedValue(_ index: Int, _ snapshots: [InvestmentSnapshot]) -> Double {
        (snapshots[index].investedAmount as NSDecimalNumber).doubleValue
    }

    private static func marketValue(_ index: Int, _ snapshots: [InvestmentSnapshot]) -> Double {
        (snapshots[index].marketValue as NSDecimalNumber).doubleValue
    }

    private func highlightedSnapshot(in snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        guard let selectedDate else { return snapshots.last }
        return nearestSnapshot(to: selectedDate, in: snapshots) ?? snapshots.last
    }

    private func nearestSnapshot(to date: Date, in snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        guard !snapshots.isEmpty else { return nil }

        var low = 0
        var high = snapshots.count

        while low < high {
            let middle = (low + high) / 2
            if snapshots[middle].snapshotDate < date {
                low = middle + 1
            } else {
                high = middle
            }
        }

        if low == 0 {
            return snapshots[0]
        }

        if low == snapshots.count {
            return snapshots[snapshots.count - 1]
        }

        let previous = snapshots[low - 1]
        let next = snapshots[low]
        let previousDistance = date.timeIntervalSince(previous.snapshotDate)
        let nextDistance = next.snapshotDate.timeIntervalSince(date)
        return previousDistance <= nextDistance ? previous : next
    }

    private func updateSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        snapshots: [InvestmentSnapshot]
    ) {
        guard let plotFrame = proxy.plotFrame else {
            setSelectedDate(nil)
            return
        }

        let frame = geometry[plotFrame]
        let relativeX = location.x - frame.origin.x

        guard relativeX >= 0, relativeX <= frame.size.width else {
            setSelectedDate(nil)
            return
        }

        guard let date: Date = proxy.value(atX: relativeX),
              let nearestSnapshot = nearestSnapshot(to: date, in: snapshots) else {
            setSelectedDate(nil)
            return
        }

        setSelectedDate(nearestSnapshot.snapshotDate)
    }

    private func setSelectedDate(_ date: Date?) {
        guard selectedDate != date else { return }
        selectedDate = date
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
