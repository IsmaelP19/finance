//
//  CategoryManagementView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData

/// Pantalla para gestionar categorías de movimientos.
struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]

    @State private var editingCategory: MovementCategory?
    @State private var showingCreateCategory = false

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "Sin categorías",
                        systemImage: "tag",
                        description: Text("Pulsa + para crear tu primera categoría")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(categories, id: \.id) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.iconName)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(category.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)

                                    Text(movementCountText(for: category))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.45), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingCategory = category
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete(perform: deleteCategories)
                }
            }
            .financeGlassListContainer()
            .navigationTitle("Categorías")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateCategory = true
                    } label: {
                        Image(systemName: "plus")
                            .financeToolbarIconStyle()
                    }
                }
            }
            .sheet(item: $editingCategory) { (category: MovementCategory) in
                CategoryEditorSheet(category: category)
            }
            .sheet(isPresented: $showingCreateCategory) {
                CategoryEditorSheet()
            }
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(categories[index])
            }
        }
    }

    private func movementCountText(for category: MovementCategory) -> String {
        let count = (category.movements ?? []).count
        return "\(count) \(count == 1 ? "movimiento" : "movimientos")"
    }
}

/// Formulario para crear o editar una categoría.
struct CategoryEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]

    var category: MovementCategory?

    init(category: MovementCategory? = nil) {
        self.category = category
    }

    @State private var categoryName: String = ""
    @State private var selectedIcon: CategoryIcon = .tag
    @State private var selectedColor: CategoryColor = .blue
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    private var isEditing: Bool { category != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Nombre de la categoría", text: $categoryName)
                }

                Section("Icono") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryIcon.allCases) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon.systemName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                    .background(selectedIcon == icon ? selectedColor.color : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedIcon == icon ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryColor.allCases) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .overlay(
                                        Circle().stroke(color.color, lineWidth: selectedColor == color ? 1 : 0)
                                            .padding(-2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Vista previa") {
                    HStack(spacing: 10) {
                        Image(systemName: selectedIcon.systemName)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(selectedColor.color)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text(categoryName.isEmpty ? "Nombre de la categoría" : categoryName)
                            .fontWeight(.medium)
                    }
                }
            }
            .financeGlassListContainer()
            .navigationTitle(isEditing ? "Editar categoría" : "Nueva categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Guardar" : "Crear") {
                        saveCategory()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadData)
            .alert("Error", isPresented: $showingValidationAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func loadData() {
        guard let category else { return }
        categoryName = category.name
        selectedIcon = category.icon
        selectedColor = category.categoryColor
    }

    private func saveCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "El nombre de la categoría es obligatorio."
            showingValidationAlert = true
            return
        }

        let duplicateExists = categories.contains { existing in
            guard let current = category else {
                return existing.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
            }

            return existing.id != current.id && existing.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }

        guard !duplicateExists else {
            validationMessage = "Ya existe una categoría con ese nombre."
            showingValidationAlert = true
            return
        }

        if let category {
            category.name = trimmedName
            category.icon = selectedIcon
            category.categoryColor = selectedColor
        } else {
            let newCategory = MovementCategory(name: trimmedName, icon: selectedIcon, color: selectedColor)
            modelContext.insert(newCategory)
        }

        dismiss()
    }
}
