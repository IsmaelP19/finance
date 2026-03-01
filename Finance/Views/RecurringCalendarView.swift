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
    case overdue
    case dueToday
    case pending

    var title: String {
        switch self {
        case .confirmed:
            return "Confirmado"
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
        }
    }

    static func merge(_ lhs: RecurringCalendarStatus, _ rhs: RecurringCalendarStatus) -> RecurringCalendarStatus {
        lhs.priority >= rhs.priority ? lhs : rhs
    }
}

private struct RecurringCalendarOccurrence: Identifiable {
    let rule: RecurringMovement
    let dueDate: Date
    let isConfirmed: Bool

    var id: String {
        "\(rule.id.uuidString)-\(Int(dueDate.timeIntervalSince1970))"
    }
}

struct RecurringCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]

    @State private var selectedDate: Date = Date()
    @State private var showingActionAlert = false
    @State private var actionAlertMessage = ""

    private var recurringCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private var selectedDateOccurrences: [RecurringCalendarOccurrence] {
        let dayStart = recurringCalendar.startOfDay(for: selectedDate)
        let dayEnd = recurringCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let interval = DateInterval(start: dayStart, end: dayEnd)
        return occurrences(in: interval, includeConfirmed: true)
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
            from: recurringCalendar.dateComponents([.year, .month], from: selectedDate)
        ) ?? recurringCalendar.startOfDay(for: selectedDate)

        let selectedWindowStart = recurringCalendar.date(byAdding: .month, value: -6, to: monthStart) ?? monthStart
        let selectedWindowEnd = recurringCalendar.date(byAdding: .month, value: 18, to: monthStart) ?? monthStart

        let activeRules = recurringMovements.filter { $0.isActive && $0.type != .transfer }
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

    var body: some View {
        NavigationStack {
            List {
                Section("Calendario") {
#if canImport(UIKit)
                    DecoratedRecurringCalendarView(
                        selectedDate: $selectedDate,
                        decorations: decoratedDates
                    )
                    .frame(minHeight: 340)
#else
                    DatePicker(
                        "Fecha",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
#endif
                }

                Section("Cobros y pagos del día") {
                    if selectedDateOccurrences.isEmpty {
                        Text("No hay pagos recurrentes para este día.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedDateOccurrences) { occurrence in
                            RecurringCalendarRow(
                                occurrence: occurrence,
                                currencyCode: appCurrencyCode,
                                status: status(for: occurrence)
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !occurrence.isConfirmed {
                                    Button {
                                        confirmOccurrence(occurrence)
                                    } label: {
                                        Label("Confirmar", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.green)
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !occurrence.isConfirmed {
                                    Button(role: .destructive) {
                                        cancelRecurringRule(occurrence.rule)
                                    } label: {
                                        Label("Cancelar", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Próximos pagos recurrentes") {
                    if upcomingOccurrences.isEmpty {
                        Text("No hay próximos pagos pendientes en los próximos 90 días.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcomingOccurrences.prefix(30)) { occurrence in
                            RecurringCalendarRow(
                                occurrence: occurrence,
                                currencyCode: appCurrencyCode,
                                status: status(for: occurrence)
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    confirmOccurrence(occurrence)
                                } label: {
                                    Label("Confirmar", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }

                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    cancelRecurringRule(occurrence.rule)
                                } label: {
                                    Label("Cancelar", systemImage: "xmark.circle")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calendario")
            .alert("Acción no disponible", isPresented: $showingActionAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(actionAlertMessage)
            }
        }
    }

    private func occurrences(in interval: DateInterval, includeConfirmed: Bool) -> [RecurringCalendarOccurrence] {
        var results: [RecurringCalendarOccurrence] = []

        for rule in recurringMovements where rule.isActive && rule.type != .transfer {
            let dueDates = RecurringMovementService.dueDates(of: rule, in: interval, calendar: recurringCalendar)

            for dueDate in dueDates {
                let confirmed = RecurringMovementService.isOccurrenceConfirmed(
                    ruleID: rule.id,
                    dueDate: dueDate,
                    movements: movements,
                    calendar: recurringCalendar
                )

                if includeConfirmed || !confirmed {
                    results.append(
                        RecurringCalendarOccurrence(
                            rule: rule,
                            dueDate: dueDate,
                            isConfirmed: confirmed
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

    private func confirmOccurrence(_ occurrence: RecurringCalendarOccurrence) {
        guard occurrence.rule.type != .transfer else {
            actionAlertMessage = "Las transferencias no se pueden confirmar como recurrentes."
            showingActionAlert = true
            return
        }

        guard let account = occurrence.rule.account else {
            actionAlertMessage = "La cuenta asociada ya no está disponible. Edita la recurrencia para continuar."
            showingActionAlert = true
            return
        }

        guard !RecurringMovementService.isOccurrenceConfirmed(
            ruleID: occurrence.rule.id,
            dueDate: occurrence.dueDate,
            movements: movements
        ) else {
            return
        }

        let resultingBalance = applyRecurringImpact(
            type: occurrence.rule.type,
            amount: occurrence.rule.amount,
            account: account
        )

        let movement = Movement(
            concept: occurrence.rule.concept,
            amount: occurrence.rule.amount,
            type: occurrence.rule.type,
            occurredAt: occurrence.dueDate,
            account: account,
            destinationAccount: nil,
            category: occurrence.rule.category,
            notes: occurrence.rule.notes,
            resultingBalance: resultingBalance,
            recurringRuleId: occurrence.rule.id,
            recurringScheduledAt: occurrence.dueDate
        )

        withAnimation {
            modelContext.insert(movement)
            occurrence.rule.updatedAt = Date()
        }

        HapticFeedback.success()
    }

    private func cancelRecurringRule(_ recurring: RecurringMovement) {
        withAnimation {
            recurring.isActive = false
            recurring.updatedAt = Date()
        }
    }

    @discardableResult
    private func applyRecurringImpact(type: MovementType, amount: Decimal, account: BankAccount) -> Decimal {
        account.currency = appCurrencyCode

        switch type {
        case .expense:
            account.balance -= amount
        case .income:
            account.balance += amount
        case .transfer:
            break
        }

        account.updatedAt = Date()
        return account.balance
    }
}

#if canImport(UIKit)
private struct DecoratedRecurringCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let decorations: [Date: RecurringCalendarStatus]

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.locale = Locale(identifier: "es_ES")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.timeZone = .autoupdatingCurrent
        calendarView.calendar = calendar
        calendarView.delegate = context.coordinator

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        calendarView.selectionBehavior = selection

        context.coordinator.calendarView = calendarView
        context.coordinator.calendar = calendarView.calendar
        context.coordinator.updateDecorations(decorations)
        context.coordinator.selectDate(selectedDate, animated: false)

        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.calendar = uiView.calendar
        context.coordinator.updateDecorations(decorations)
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

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents else { return }
            guard let date = calendar.date(from: dateComponents) else { return }

            let normalizedDate = calendar.startOfDay(for: date)
            if parent.selectedDate != normalizedDate {
                parent.selectedDate = normalizedDate
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

private struct RecurringCalendarRow: View {
    let occurrence: RecurringCalendarOccurrence
    let currencyCode: String
    let status: RecurringCalendarStatus

    private var amountText: String {
        switch occurrence.rule.type {
        case .expense, .income:
            return (occurrence.rule.amount * occurrence.rule.type.signMultiplier).asCurrency(code: currencyCode)
        case .transfer:
            return occurrence.rule.amount.asCurrency(code: currencyCode)
        }
    }

    private var accountText: String {
        occurrence.rule.account?.name ?? "Cuenta no disponible"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: occurrence.rule.type.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(occurrence.rule.type.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.rule.concept)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let category = occurrence.rule.category {
                    CategoryChipView(
                        name: category.name,
                        iconName: category.iconName,
                        color: category.color
                    )
                }

                Text(accountText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(occurrence.dueDate.asSpanishShortDate())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(occurrence.rule.type == .expense ? .red : .green)

                Text(status.title)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.15))
                    .foregroundStyle(status.color)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
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
