//
//  RecurringCalendarView.swift
//  Finance
//
//  Created by OpenCode on 18/02/2026.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private enum RecurringCalendarStatus: Equatable {
    case confirmed
    case skipped
    case overdue
    case dueToday
    case pending

    var title: String {
        switch self {
        case .confirmed:
            return "Confirmado"
        case .skipped:
            return "Omitido"
        case .overdue:
            return "Vencido"
        case .dueToday:
            return "Hoy"
        case .pending:
            return "Pendiente"
        }
    }

    var color: Color {
        switch self {
        case .confirmed:
            return .green
        case .skipped:
            return .secondary
        case .overdue:
            return .red
        case .dueToday:
            return .orange
        case .pending:
            return .blue
        }
    }

#if canImport(UIKit)
    var uiColor: UIColor {
        switch self {
        case .confirmed:
            return .systemGreen
        case .skipped:
            return .systemGray
        case .overdue:
            return .systemRed
        case .dueToday:
            return .systemOrange
        case .pending:
            return .systemBlue
        }
    }
#endif

    var priority: Int {
        switch self {
        case .overdue:
            return 4
        case .dueToday:
            return 3
        case .pending:
            return 2
        case .confirmed:
            return 1
        case .skipped:
            return 0
        }
    }

    static func merge(_ lhs: RecurringCalendarStatus, _ rhs: RecurringCalendarStatus) -> RecurringCalendarStatus {
        lhs.priority >= rhs.priority ? lhs : rhs
    }
}

private struct RecurringCalendarOccurrence: Identifiable {
    let rule: RecurringMovement
    let dueDate: Date
    let confirmedMovement: Movement?
    let isSkipped: Bool

    var isConfirmed: Bool {
        confirmedMovement != nil
    }

    var effectiveAmount: Decimal {
        confirmedMovement?.amount ?? rule.amount
    }

    var id: String {
        "\(rule.id.uuidString)-\(Int(dueDate.timeIntervalSince1970))"
    }
}

struct RecurringCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]

    @State private var selectedDate: Date = Date()
    @State private var visibleMonthDate: Date = Date()
    @State private var calendarHeightMonthDate: Date = Date()
    @State private var calendarHeightUpdateTask: DispatchWorkItem?
    @State private var showingActionAlert = false
    @State private var actionAlertMessage = ""
    @State private var occurrenceToEditAmount: RecurringCalendarOccurrence?
    @State private var occurrenceToManage: RecurringCalendarOccurrence?
    @State private var showingOccurrenceActions = false

    private var recurringCalendar: Calendar {
        RecurringMovementService.recurrenceCalendar
    }

    private var selectedDateOccurrences: [RecurringCalendarOccurrence] {
        let dayStart = recurringCalendar.startOfDay(for: selectedDate)
        let dayEnd = recurringCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let interval = DateInterval(start: dayStart, end: dayEnd)
        return occurrences(in: interval, includeConfirmed: true)
    }

    private var visibleMonthWeekRows: Int {
        let monthStartDate = monthStart(for: calendarHeightMonthDate)
        guard let dayRange = recurringCalendar.range(of: .day, in: .month, for: monthStartDate) else {
            return 6
        }

        let firstDayWeekday = recurringCalendar.component(.weekday, from: monthStartDate)
        let leadingEmptyDays = (firstDayWeekday - recurringCalendar.firstWeekday + 7) % 7
        let totalGridCells = leadingEmptyDays + dayRange.count
        return min(6, max(4, Int(ceil(Double(totalGridCells) / 7.0))))
    }

    private var calendarBlockHeight: CGFloat {
        let baseHeight: CGFloat = 126
        let weekRowHeight: CGFloat = 61
        return baseHeight + (CGFloat(visibleMonthWeekRows) * weekRowHeight)
    }

    private var selectedMonthInterval: DateInterval {
        let monthStart = recurringCalendar.date(
            from: recurringCalendar.dateComponents([.year, .month], from: visibleMonthDate)
        ) ?? recurringCalendar.startOfDay(for: visibleMonthDate)
        let monthEnd = recurringCalendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return DateInterval(start: monthStart, end: monthEnd)
    }

    private var selectedMonthOccurrences: [RecurringCalendarOccurrence] {
        occurrences(in: selectedMonthInterval, includeConfirmed: true)
    }

    private var selectedMonthRecurringExpenseTotal: Decimal {
        selectedMonthOccurrences.reduce(Decimal(0)) { partialResult, occurrence in
            guard occurrence.rule.type == .expense, !occurrence.isSkipped else { return partialResult }
            return partialResult + occurrence.effectiveAmount
        }
    }

    private var selectedMonthRecurringIncomeTotal: Decimal {
        selectedMonthOccurrences.reduce(Decimal(0)) { partialResult, occurrence in
            guard occurrence.rule.type == .income, !occurrence.isSkipped else { return partialResult }
            return partialResult + occurrence.effectiveAmount
        }
    }

    private var selectedMonthExpenseOccurrenceCount: Int {
        selectedMonthOccurrences.reduce(into: 0) { partialResult, occurrence in
            if occurrence.rule.type == .expense, !occurrence.isSkipped {
                partialResult += 1
            }
        }
    }

    private var selectedDateHeaderTitle: String {
        selectedDate.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .locale(Locale(identifier: "es_ES"))
        ).capitalized
    }

    private var selectedDatePendingCount: Int {
        selectedDateOccurrences.filter { !$0.isConfirmed && !$0.isSkipped }.count
    }

    private var selectedDateConfirmedCount: Int {
        selectedDateOccurrences.filter(\.isConfirmed).count
    }

    private var selectedDateSkippedCount: Int {
        selectedDateOccurrences.filter(\.isSkipped).count
    }

    private var nextUpcomingPreviewCount: Int {
        min(upcomingOccurrences.count, 12)
    }

    private var shouldShowTodayShortcut: Bool {
        !recurringCalendar.isDate(selectedDate, inSameDayAs: Date())
    }

    private var upcomingOccurrences: [RecurringCalendarOccurrence] {
        let now = Date()
        let dayStart = recurringCalendar.startOfDay(for: now)
        let end = recurringCalendar.date(byAdding: .day, value: 90, to: dayStart) ?? dayStart
        let interval = DateInterval(start: dayStart, end: end)
        return occurrences(in: interval, includeConfirmed: false)
    }

    private var decorationInterval: DateInterval {
        let monthStart = recurringCalendar.date(
            from: recurringCalendar.dateComponents([.year, .month], from: visibleMonthDate)
        ) ?? recurringCalendar.startOfDay(for: visibleMonthDate)

        let selectedWindowStart = recurringCalendar.date(byAdding: .month, value: -6, to: monthStart) ?? monthStart
        let selectedWindowEnd = recurringCalendar.date(byAdding: .month, value: 18, to: monthStart) ?? monthStart

        let activeRules = recurringMovements.filter { $0.isActive && $0.type != .transfer && $0.account?.isActive == true }
        let earliestRuleStart = activeRules
            .map { recurringCalendar.startOfDay(for: $0.startDate) }
            .min()

        let defaultOpenEnded = recurringCalendar.date(byAdding: .year, value: 3, to: monthStart) ?? selectedWindowEnd
        let latestRuleEnd = activeRules
            .map { recurring in
                recurring.endDate.map { recurringCalendar.startOfDay(for: $0) } ?? defaultOpenEnded
            }
            .max()

        let start = min(selectedWindowStart, earliestRuleStart ?? selectedWindowStart)
        let end = max(selectedWindowEnd, latestRuleEnd ?? selectedWindowEnd)
        return DateInterval(start: start, end: end)
    }

    private var decoratedDates: [Date: RecurringCalendarStatus] {
        let allOccurrences = occurrences(in: decorationInterval, includeConfirmed: true)

        var map: [Date: RecurringCalendarStatus] = [:]

        for occurrence in allOccurrences {
            let day = recurringCalendar.startOfDay(for: occurrence.dueDate)
            let occurrenceStatus = status(for: occurrence)

            if let existing = map[day] {
                map[day] = .merge(existing, occurrenceStatus)
            } else {
                map[day] = occurrenceStatus
            }
        }

        return map
    }

    private func monthStart(for date: Date) -> Date {
        recurringCalendar.date(
            from: recurringCalendar.dateComponents([.year, .month], from: date)
        ) ?? recurringCalendar.startOfDay(for: date)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
#if canImport(UIKit)
                    DecoratedRecurringCalendarView(
                        selectedDate: $selectedDate,
                        visibleMonthDate: $visibleMonthDate,
                        decorations: decoratedDates
                    )
                    .frame(height: calendarBlockHeight)
                    .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
#else
                    DatePicker(
                        "Fecha",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
#endif
                }

                Section {
                    RecurringCalendarLegendCard()
                    .financeGlassClearListRow()
                }

                Section {
                    RecurringMonthlySummaryCard(
                        monthDate: visibleMonthDate,
                        expenseTotal: selectedMonthRecurringExpenseTotal,
                        incomeTotal: selectedMonthRecurringIncomeTotal,
                        occurrenceCount: selectedMonthExpenseOccurrenceCount,
                        currencyCode: appCurrencyCode,
                        hideBalances: hideBalances
                    )
                    .financeGlassClearListRow()
                }

                selectedDaySections
                upcomingSections
            }
            .financeGlassListContainer()
            .navigationTitle("Calendario")
            .onAppear {
                let initialMonth = monthStart(for: selectedDate)
                visibleMonthDate = initialMonth
                setCalendarHeightMonthDate(initialMonth)
            }
            .onChange(of: selectedDate) { _, newValue in
                let newMonthStart = monthStart(for: newValue)
                if !recurringCalendar.isDate(newMonthStart, equalTo: visibleMonthDate, toGranularity: .month) {
                    visibleMonthDate = newMonthStart
                    scheduleCalendarHeightUpdate(for: newMonthStart)
                }
            }
            .onChange(of: visibleMonthDate) { _, newValue in
                scheduleCalendarHeightUpdate(for: newValue)
                if !recurringCalendar.isDate(selectedDate, equalTo: newValue, toGranularity: .month) {
                    selectedDate = newValue
                }
            }
            .onDisappear {
                calendarHeightUpdateTask?.cancel()
                calendarHeightUpdateTask = nil
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        hideBalances.toggle()
                    } label: {
                        Image(systemName: hideBalances ? "eye.slash" : "eye")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if shouldShowTodayShortcut {
                        Button("Hoy") {
                            let today = recurringCalendar.startOfDay(for: Date())
                            let todayMonth = monthStart(for: today)
                            selectedDate = today
                            visibleMonthDate = todayMonth
                            setCalendarHeightMonthDate(todayMonth)
                        }
                        .font(.subheadline.weight(.semibold))
                        .financeGlassPill(tint: .blue, isSelected: false)
                    }
                }
            }
            .sheet(item: $occurrenceToEditAmount) { occurrence in
                amountEditor(for: occurrence)
            }
            .confirmationDialog(
                "Gestionar recurrencia",
                isPresented: $showingOccurrenceActions,
                titleVisibility: .visible,
                presenting: occurrenceToManage
            ) { occurrence in
                occurrenceManagementActions(for: occurrence)
            } message: { occurrence in
                occurrenceManagementMessage(for: occurrence)
            }
            .alert("Acción no disponible", isPresented: $showingActionAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                actionAlertText
            }
        }
    }

    private func amountEditor(for occurrence: RecurringCalendarOccurrence) -> some View {
        RecurringOccurrenceAmountEditor(
            concept: occurrence.rule.concept,
            scheduledDate: occurrence.dueDate,
            suggestedAmount: occurrence.rule.amount,
            currencyCode: appCurrencyCode
        ) { amount, applyToFuture in
            try confirmOccurrenceWithAmount(
                occurrence,
                amount: amount,
                applyToFuture: applyToFuture
            )
        }
    }

    @ViewBuilder
    private var selectedDaySections: some View {
        RecurringCalendarSectionHeader(
            title: "Cobros y pagos del día",
            subtitle: selectedDateHeaderTitle,
            trailingText: selectedDateOccurrences.isEmpty ? nil : "\(selectedDateOccurrences.count) previstos",
            detailText: selectedDateOccurrences.isEmpty ? "" : selectedDateSummaryText
        )

        Section {
            if selectedDateOccurrences.isEmpty {
                FinanceEmptyStateContent(
                    "Sin movimientos para este día",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Cambia el día o vuelve a hoy para revisar otros cobros y pagos recurrentes.")
                )
                .financeGlassClearListRow()
            } else {
                ForEach(selectedDateOccurrences) { occurrence in
                    interactiveOccurrenceRow(occurrence)
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSections: some View {
        RecurringCalendarSectionHeader(
            title: "Próximos pagos recurrentes",
            subtitle: "Agenda inmediata",
            trailingText: upcomingOccurrences.isEmpty ? nil : "\(nextUpcomingPreviewCount) visibles",
            detailText: upcomingOccurrences.isEmpty ? "" : "Mostrando los siguientes movimientos pendientes"
        )

        Section {
            if upcomingOccurrences.isEmpty {
                FinanceEmptyStateContent(
                    "Sin próximos vencimientos",
                    systemImage: "checkmark.circle",
                    description: Text("No hay pagos recurrentes pendientes en los próximos 90 días.")
                )
                .financeGlassClearListRow()
            } else {
                ForEach(Array(upcomingOccurrences.prefix(12))) { occurrence in
                    interactiveOccurrenceRow(occurrence)
                }
            }
        }
    }

    private func interactiveOccurrenceRow(_ occurrence: RecurringCalendarOccurrence) -> some View {
        InteractiveRecurringCalendarRow(
            occurrence: occurrence,
            currencyCode: appCurrencyCode,
            hideBalances: hideBalances,
            status: status(for: occurrence),
            onConfirm: {
                confirmOccurrenceImmediately(occurrence)
            },
            onManage: {
                occurrenceToManage = occurrence
                showingOccurrenceActions = true
            },
            onEditAmount: {
                occurrenceToEditAmount = occurrence
            }
        )
    }

    @ViewBuilder
    private func occurrenceManagementActions(for occurrence: RecurringCalendarOccurrence) -> some View {
        Button("Omitir solo esta ocurrencia") {
            skipOccurrence(occurrence)
        }
        Button("Finalizar recurrencia", role: .destructive) {
            endRecurrence(occurrence)
        }
        Button("Cancelar", role: .cancel) {}
    }

    private func occurrenceManagementMessage(for occurrence: RecurringCalendarOccurrence) -> Text {
        Text("\(occurrence.rule.concept) · \(occurrence.dueDate.asSpanishShortDate())")
    }

    private var actionAlertText: Text {
        Text(actionAlertMessage)
    }

    private func occurrences(in interval: DateInterval, includeConfirmed: Bool) -> [RecurringCalendarOccurrence] {
        var results: [RecurringCalendarOccurrence] = []

        for rule in recurringMovements where rule.type != .transfer {
            var dueDateSet = Set<Date>()

            if (rule.isActive && rule.account?.isActive == true) || rule.endDate != nil {
                let scheduledDates = RecurringMovementService.dueDates(
                    of: rule,
                    in: interval,
                    calendar: recurringCalendar
                )
                dueDateSet.formUnion(scheduledDates.map { recurringCalendar.startOfDay(for: $0) })
            }

            for movement in movements where movement.recurringRuleId == rule.id {
                let scheduledDate = movement.recurringScheduledAt ?? movement.occurredAt
                let normalizedDate = recurringCalendar.startOfDay(for: scheduledDate)
                if interval.contains(normalizedDate) {
                    dueDateSet.insert(normalizedDate)
                }
            }

            for skippedDate in rule.skippedOccurrenceDates {
                let normalizedDate = recurringCalendar.startOfDay(for: skippedDate)
                if interval.contains(normalizedDate) {
                    dueDateSet.insert(normalizedDate)
                }
            }

            for dueDate in dueDateSet {
                let confirmedMovement = RecurringMovementService.confirmedMovement(
                    ruleID: rule.id,
                    dueDate: dueDate,
                    movements: movements,
                    calendar: recurringCalendar
                )
                let skipped = RecurringMovementService.isOccurrenceSkipped(
                    rule: rule,
                    dueDate: dueDate,
                    calendar: recurringCalendar
                )

                if includeConfirmed || (confirmedMovement == nil && !skipped) {
                    results.append(
                        RecurringCalendarOccurrence(
                            rule: rule,
                            dueDate: dueDate,
                            confirmedMovement: confirmedMovement,
                            isSkipped: skipped
                        )
                    )
                }
            }
        }

        return results.sorted { lhs, rhs in
            lhs.dueDate < rhs.dueDate
        }
    }

    private func status(for occurrence: RecurringCalendarOccurrence) -> RecurringCalendarStatus {
        if occurrence.isConfirmed {
            return .confirmed
        }
        if occurrence.isSkipped {
            return .skipped
        }

        let today = recurringCalendar.startOfDay(for: Date())
        let dueDate = recurringCalendar.startOfDay(for: occurrence.dueDate)

        if dueDate < today {
            return .overdue
        }

        if recurringCalendar.isDate(dueDate, inSameDayAs: today) {
            return .dueToday
        }

        return .pending
    }

    private func confirmOccurrenceWithAmount(
        _ occurrence: RecurringCalendarOccurrence,
        amount: Decimal,
        applyToFuture: Bool
    ) throws {
        do {
            _ = try RecurringMovementService.confirmOccurrence(
                rule: occurrence.rule,
                dueDate: occurrence.dueDate,
                amount: amount,
                applyToFuture: applyToFuture,
                currencyCode: appCurrencyCode,
                in: modelContext,
                calendar: recurringCalendar
            )
            HapticFeedback.success()
        } catch {
            modelContext.rollback()
            CrashReportService.shared.recordDiagnosticEvent(
                "RecurringMovementService.confirmOccurrence failed error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    private func confirmOccurrenceImmediately(_ occurrence: RecurringCalendarOccurrence) {
        do {
            try confirmOccurrenceWithAmount(occurrence, amount: occurrence.rule.amount, applyToFuture: false)
        } catch {
            actionAlertMessage = "No se pudo confirmar el movimiento recurrente: \(error.localizedDescription)"
            showingActionAlert = true
        }
    }

    private func skipOccurrence(_ occurrence: RecurringCalendarOccurrence) {
        do {
            try RecurringMovementService.skipOccurrence(
                rule: occurrence.rule,
                dueDate: occurrence.dueDate,
                in: modelContext,
                calendar: recurringCalendar
            )
            HapticFeedback.success()
        } catch {
            modelContext.rollback()
            actionAlertMessage = "No se pudo omitir la ocurrencia: \(error.localizedDescription)"
            showingActionAlert = true
        }
    }

    private func endRecurrence(_ occurrence: RecurringCalendarOccurrence) {
        do {
            try RecurringMovementService.endRecurrence(
                occurrence.rule,
                before: occurrence.dueDate,
                in: modelContext,
                calendar: recurringCalendar
            )
            HapticFeedback.success()
        } catch {
            modelContext.rollback()
            actionAlertMessage = "No se pudo finalizar la recurrencia: \(error.localizedDescription)"
            showingActionAlert = true
        }
    }

    private func scheduleCalendarHeightUpdate(for monthDate: Date) {
        let normalizedMonth = monthStart(for: monthDate)
        calendarHeightUpdateTask?.cancel()

        let task = DispatchWorkItem {
            setCalendarHeightMonthDate(normalizedMonth)
            calendarHeightUpdateTask = nil
        }

        calendarHeightUpdateTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: task)
    }

    private func setCalendarHeightMonthDate(_ monthDate: Date) {
        guard !recurringCalendar.isDate(monthDate, equalTo: calendarHeightMonthDate, toGranularity: .month) else {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            calendarHeightMonthDate = monthDate
        }
    }

    private var selectedDateSummaryText: String {
        var parts = [
            "\(selectedDatePendingCount) pendientes",
            "\(selectedDateConfirmedCount) confirmados"
        ]
        if selectedDateSkippedCount > 0 {
            parts.append("\(selectedDateSkippedCount) omitidos")
        }
        return parts.joined(separator: " · ")
    }
}

private struct RecurringCalendarLegendCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            legendItem(color: .red, title: "Vencido")
            legendItem(color: .orange, title: "Hoy")
            legendItem(color: .blue, title: "Pendiente")
            legendItem(color: .green, title: "Confirmado")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.row)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }
}

private struct RecurringCalendarSectionHeader: View {
    let title: String
    let subtitle: String
    let trailingText: String?
    let detailText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.bold))

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let trailingText {
                    Text(trailingText)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            if !detailText.isEmpty {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.top, 6)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

#if canImport(UIKit)
private struct DecoratedRecurringCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date
    @Binding var visibleMonthDate: Date
    let decorations: [Date: RecurringCalendarStatus]

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear

        let calendarView = UICalendarView()
        calendarView.translatesAutoresizingMaskIntoConstraints = false
        calendarView.locale = Locale(identifier: "es_ES")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.timeZone = .autoupdatingCurrent
        calendarView.calendar = calendar
        calendarView.delegate = context.coordinator

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        calendarView.selectionBehavior = selection

        containerView.addSubview(calendarView)
        NSLayoutConstraint.activate([
            calendarView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 6),
            calendarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            calendarView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            calendarView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -6)
        ])

        context.coordinator.calendarView = calendarView
        context.coordinator.calendar = calendarView.calendar
        context.coordinator.updateDecorations(decorations)
        context.coordinator.setVisibleMonth(visibleMonthDate, animated: false)
        context.coordinator.selectDate(selectedDate, animated: false)

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        guard let calendarView = context.coordinator.calendarView else { return }
        context.coordinator.calendar = calendarView.calendar
        context.coordinator.updateDecorations(decorations)
        context.coordinator.setVisibleMonth(visibleMonthDate, animated: false)
        context.coordinator.selectDate(selectedDate, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: DecoratedRecurringCalendarView
        weak var calendarView: UICalendarView?
        var calendar: Calendar = Calendar(identifier: .gregorian)
        var decorationMap: [DateComponents: RecurringCalendarStatus] = [:]

        init(parent: DecoratedRecurringCalendarView) {
            self.parent = parent
        }

        func updateDecorations(_ decorations: [Date: RecurringCalendarStatus]) {
            var mapped: [DateComponents: RecurringCalendarStatus] = [:]

            for (date, status) in decorations {
                let components = normalizedDayComponents(from: date)
                mapped[components] = status
            }

            guard mapped != decorationMap else {
                return
            }

            let oldComponents = Set(decorationMap.keys)
            let newComponents = Set(mapped.keys)
            let componentsToReload = Array(oldComponents.union(newComponents))

            decorationMap = mapped

            calendarView?.reloadDecorations(forDateComponents: componentsToReload, animated: false)
        }

        func selectDate(_ date: Date, animated: Bool) {
            guard let calendarView else { return }
            guard let selection = calendarView.selectionBehavior as? UICalendarSelectionSingleDate else { return }

            let target = normalizedDayComponents(from: date)

            if let selected = selection.selectedDate,
               selected.year == target.year,
               selected.month == target.month,
               selected.day == target.day {
                return
            }

            selection.setSelected(target, animated: animated)
        }

        func setVisibleMonth(_ date: Date, animated: Bool) {
            guard let calendarView else { return }

            let target = calendar.dateComponents([.year, .month], from: date)
            let current = calendarView.visibleDateComponents

            guard current.year != target.year || current.month != target.month else {
                return
            }

            calendarView.setVisibleDateComponents(target, animated: animated)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents else { return }
            guard let date = calendar.date(from: dateComponents) else { return }

            let normalizedDate = calendar.startOfDay(for: date)
            if parent.selectedDate != normalizedDate {
                parent.selectedDate = normalizedDate
            }

            let selectedMonthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: normalizedDate)
            ) ?? normalizedDate
            if parent.visibleMonthDate != selectedMonthStart {
                parent.visibleMonthDate = selectedMonthStart
            }
        }

        func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
            let visible = calendarView.visibleDateComponents
            guard let year = visible.year, let month = visible.month else { return }
            guard let visibleMonthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return }

            let normalizedMonthStart = calendar.startOfDay(for: visibleMonthStart)
            if parent.visibleMonthDate != normalizedMonthStart {
                parent.visibleMonthDate = normalizedMonthStart
            }
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            let key = normalizedDayComponents(from: dateComponents)
            guard let status = decorationMap[key] else { return nil }
            return .default(color: status.uiColor, size: .small)
        }

        private func normalizedDayComponents(from date: Date) -> DateComponents {
            let raw = calendar.dateComponents([.year, .month, .day], from: date)
            return DateComponents(year: raw.year, month: raw.month, day: raw.day)
        }

        private func normalizedDayComponents(from components: DateComponents) -> DateComponents {
            DateComponents(year: components.year, month: components.month, day: components.day)
        }
    }
}
#else
private struct DecoratedRecurringCalendarView: View {
    @Binding var selectedDate: Date
    let decorations: [Date: RecurringCalendarStatus]

    var body: some View {
        DatePicker(
            "Fecha",
            selection: $selectedDate,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
    }
}
#endif

private struct InteractiveRecurringCalendarRow: View {
    let occurrence: RecurringCalendarOccurrence
    let currencyCode: String
    let hideBalances: Bool
    let status: RecurringCalendarStatus
    let onConfirm: () -> Void
    let onManage: () -> Void
    let onEditAmount: () -> Void

    var body: some View {
        RecurringCalendarRow(
            occurrence: occurrence,
            currencyCode: currencyCode,
            hideBalances: hideBalances,
            status: status
        )
        .financeGlassClearListRow()
        .contextMenu {
            if !occurrence.isConfirmed && !occurrence.isSkipped {
                Button(action: onEditAmount) {
                    Label("Editar importe", systemImage: "pencil")
                }
                Button(action: onConfirm) {
                    Label("Confirmar", systemImage: "checkmark.circle.fill")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !occurrence.isConfirmed && !occurrence.isSkipped {
                Button(action: onConfirm) {
                    Label("Confirmar", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !occurrence.isConfirmed && !occurrence.isSkipped {
                Button(action: onEditAmount) {
                    Label("Editar importe", systemImage: "pencil")
                }
                .tint(.financeAccent)

                Button(action: onManage) {
                    Label("Gestionar", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

private struct RecurringCalendarRow: View {
    let occurrence: RecurringCalendarOccurrence
    let currencyCode: String
    let hideBalances: Bool
    let status: RecurringCalendarStatus

    private var amountText: String {
        switch occurrence.rule.type {
        case .expense, .income:
            return (occurrence.effectiveAmount * occurrence.rule.type.signMultiplier).masked(hideBalances, code: currencyCode)
        case .transfer:
            return occurrence.effectiveAmount.masked(hideBalances, code: currencyCode)
        }
    }

    private var accountText: String {
        occurrence.rule.account?.name ?? "Cuenta no disponible"
    }

    var body: some View {
        let badges: [MovementRowBadge] = {
            guard let categoryName = occurrence.rule.category?.name,
                  let categoryIconName = occurrence.rule.category?.iconName,
                  let categoryColor = occurrence.rule.category?.color else {
                return []
            }

            return [
                MovementRowBadge(
                    id: "category",
                    name: categoryName,
                    iconName: categoryIconName,
                    color: categoryColor
                )
            ]
        }()

        RecurringMovementRowContent(
            type: occurrence.rule.type,
            concept: occurrence.rule.concept,
            badges: badges,
            detailLines: [accountText],
            amountText: amountText,
            trailingPill: MovementTrailingPill(title: status.title, color: status.color),
            dateText: occurrence.dueDate.asSpanishShortDate()
        )
    }
}

#Preview {
    RecurringCalendarView()
        .modelContainer(
            for: [
                Bank.self,
                BankAccount.self,
                MovementCategory.self,
                Movement.self,
                InvestmentSnapshot.self,
                RecurringMovement.self
            ],
            inMemory: true
        )
}
