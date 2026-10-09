//
//  MovementCategoryPickerSheet.swift
//  Finance
//
//  Created by OpenCode on 23/05/2026.
//

import SwiftUI
import SwiftData

/// Selector de categoría en rejilla, presentado a pantalla completa (estilo flujo dedicado, no menú contextual).
struct MovementCategoryPickerSheet: View {
    /// Ventana para «Tus categorías»: solo movimientos desde hace N días (30 ≈ último mes; 14 ≈ dos semanas).
    private static let frequentCategoryLookbackDays = 30

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query private var recentMovements: [Movement]

    @Binding var selection: MovementCategory?

    var onCreateCategory: () -> Void

    @State private var draftSelectionID: UUID?
    @State private var frozenFrequentCategories: [MovementCategory] = []
    @State private var frozenOtherCategories: [MovementCategory] = []
    @State private var hasFrozenLayout = false

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    init(
        selection: Binding<MovementCategory?>,
        onCreateCategory: @escaping () -> Void
    ) {
        _selection = selection
        self.onCreateCategory = onCreateCategory

        let lookbackStart = Calendar.current.date(
            byAdding: .day,
            value: -Self.frequentCategoryLookbackDays,
            to: Date()
        ) ?? .distantPast

        _recentMovements = Query(filter: #Predicate<Movement> { movement in
            movement.occurredAt >= lookbackStart
        })
    }

    private var frequentSectionSubtitle: String {
        Self.frequentCategoryLookbackDays == 14
            ? "Más usadas en las últimas 2 semanas"
            : "Más usadas en el último mes"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.xLarge) {
                    frequentSection
                    if !frozenOtherCategories.isEmpty {
                        otherSection
                    }
                }
                .padding(.horizontal, FinanceGlassTokens.Spacing.large)
                .padding(.top, FinanceGlassTokens.Spacing.small)
                .padding(.bottom, FinanceGlassTokens.Spacing.xLarge)
            }
            .financeGlassPageBackground()
            .navigationTitle("Categoría")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Cerrar sin guardar")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyDraftSelectionAndDismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(draftSelectionID == nil)
                    .accessibilityLabel("Confirmar categoría")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: freezeLayoutIfNeeded)
        .onChange(of: categories.count) { _, _ in
            freezeLayoutIfNeeded()
        }
    }

    /// Calcula y congela el orden de secciones una sola vez por presentación del sheet.
    private func freezeLayoutIfNeeded() {
        guard !hasFrozenLayout, !categories.isEmpty else { return }

        let usageCounts = usageCountByCategoryID(from: recentMovements)
        let initialSelection = selection

        frozenFrequentCategories = buildFrequentCategories(
            initialSelection: initialSelection,
            usageCounts: usageCounts
        )
        let frequentIDs = Set(frozenFrequentCategories.map(\.id))
        frozenOtherCategories = categories.filter { !frequentIDs.contains($0.id) }

        draftSelectionID = initialSelection?.id
        hasFrozenLayout = true
    }

    private func usageCountByCategoryID(from movements: [Movement]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for movement in movements {
            guard let categoryID = movement.category?.id else { continue }
            counts[categoryID, default: 0] += 1
        }
        return counts
    }

    private func buildFrequentCategories(
        initialSelection: MovementCategory?,
        usageCounts: [UUID: Int]
    ) -> [MovementCategory] {
        var result: [MovementCategory] = []

        if let initialSelection {
            result.append(initialSelection)
        }

        let usedInLookback = categories
            .filter { usageCounts[$0.id, default: 0] > 0 }
            .sorted { lhs, rhs in
                let leftCount = usageCounts[lhs.id, default: 0]
                let rightCount = usageCounts[rhs.id, default: 0]
                if leftCount != rightCount {
                    return leftCount > rightCount
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        for category in usedInLookback where result.count < 8 {
            if !result.contains(where: { $0.id == category.id }) {
                result.append(category)
            }
        }

        return result
    }

    private func applyDraftSelectionAndDismiss() {
        guard let draftSelectionID else { return }
        selection = categories.first { $0.id == draftSelectionID }
        dismiss()
    }

    private var frequentSection: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            FinanceGlassSectionHeader(
                title: "Tus categorías",
                systemImage: "star.fill",
                subtitle: frequentSectionSubtitle
            )

            LazyVGrid(columns: gridColumns, spacing: 16) {
                createCategoryCell

                ForEach(frozenFrequentCategories, id: \.id) { category in
                    categoryCell(category)
                }
            }
            .padding(FinanceGlassTokens.Spacing.medium)
            .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
        }
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.medium) {
            FinanceGlassSectionHeader(
                title: "Todas las categorías",
                systemImage: "square.grid.3x3.fill",
                subtitle: "Elige entre el resto"
            )

            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(frozenOtherCategories, id: \.id) { category in
                    categoryCell(category)
                }
            }
            .padding(FinanceGlassTokens.Spacing.medium)
            .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
        }
    }

    private var createCategoryCell: some View {
        Button {
            dismiss()
            DispatchQueue.main.async {
                onCreateCategory()
            }
        } label: {
            MovementCategoryPickerGridCell(
                title: "Crear",
                systemImage: "plus",
                iconRaw: nil,
                tint: .financeAccent,
                isSelected: false,
                showsCreateStyle: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Crear categoría")
    }

    private func categoryCell(_ category: MovementCategory) -> some View {
        Button {
            draftSelectionID = category.id
        } label: {
            MovementCategoryPickerGridCell(
                title: category.name,
                systemImage: category.iconName,
                iconRaw: category.iconRaw,
                tint: category.color,
                isSelected: draftSelectionID == category.id,
                showsCreateStyle: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(draftSelectionID == category.id ? .isSelected : [])
    }
}

private struct MovementCategoryPickerGridCell: View {
    let title: String
    let systemImage: String
    let iconRaw: String?
    let tint: Color
    let isSelected: Bool
    let showsCreateStyle: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let emoji = CategoryIcon.emoji(from: iconRaw) {
                        Text(emoji)
                            .font(.system(size: 29))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(showsCreateStyle ? Color.primary : Color.white)
                    }
                }
                .frame(width: 52, height: 52)
                .background(
                    showsCreateStyle
                        ? Color.primary.opacity(0.08)
                        : tint,
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            showsCreateStyle ? Color.primary.opacity(0.12) : Color.white.opacity(0.2),
                            lineWidth: 1
                        )
                )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.financeAccent))
                        .offset(x: 4, y: 4)
                }
            }

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }
}
