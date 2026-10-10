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
    let onSelectCategoryMovements: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]

    @State private var editingCategory: MovementCategory?
    @State private var showingCreateCategory = false
    @State private var hasShownSwipeHint = false
    @State private var hintedCategoryID: UUID?
    @State private var swipeHintOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            Group {
                if categories.isEmpty {
                    FinanceCenteredEmptyState(
                        "Sin categorías",
                        systemImage: "tag",
                        description: Text("Pulsa + para crear tu primera categoría")
                    )
                } else {
                    List {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gestionar categorías")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Toca una categoría para ver sus movimientos. Deslízala a la derecha para editarla o a la izquierda para eliminarla.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Text("\(categories.count)")
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .frame(minWidth: 48, minHeight: 48)
                                .background(.primary.opacity(0.08), in: Circle())
                                .accessibilityLabel("\(categories.count) \(categories.count == 1 ? "categoría" : "categorías")")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
                        .financeGlassClearListRow(insets: EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))

                        FinanceGlassSectionHeader(title: "Tus categorías", systemImage: "square.grid.2x2")
                            .financeGlassClearListRow(insets: EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))

                        ForEach(categories, id: \.id) { category in
                            categoryRow(category)
                        }
                    }
                    .financeGlassListContainer()
                    .task {
                        await showSwipeHintIfNeeded()
                    }
                }
            }
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
                    .accessibilityLabel("Crear categoría")
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

    private func categoryRow(_ category: MovementCategory) -> some View {
        Button {
            onSelectCategoryMovements(category.id)
        } label: {
            categoryRowContent(category)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
                .background { categoryRowBackground(category) }
                .overlay(alignment: .bottom) {
                    if category.id != categories.last?.id {
                        Rectangle()
                            .fill(.primary.opacity(0.08))
                            .frame(height: 1)
                            .padding(.leading, 72)
                            .padding(.trailing, 16)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ver movimientos de \(category.name), \(movementCountText(for: category))")
        .accessibilityHint("Activa para ver movimientos. Acciones disponibles: Editar y Eliminar.")
        .offset(x: category.id == hintedCategoryID ? swipeHintOffset : 0)
        .financeGlassClearListRow(insets: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editingCategory = category
            } label: {
                Label("Editar", systemImage: "pencil")
            }
            .tint(.financeAccent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteCategory(category)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func categoryRowContent(_ category: MovementCategory) -> some View {
        HStack(spacing: 14) {
            CategoryIconView(iconRaw: category.iconRaw, color: category.color, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(movementCountText(for: category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func categoryRowBackground(_ category: MovementCategory) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: category.id == categories.first?.id ? FinanceGlassTokens.Radius.card : 0,
            bottomLeadingRadius: category.id == categories.last?.id ? FinanceGlassTokens.Radius.card : 0,
            bottomTrailingRadius: category.id == categories.last?.id ? FinanceGlassTokens.Radius.card : 0,
            topTrailingRadius: category.id == categories.first?.id ? FinanceGlassTokens.Radius.card : 0,
            style: .continuous
        )
        .fill(.thinMaterial)
    }

    @MainActor
    private func showSwipeHintIfNeeded() async {
        guard !hasShownSwipeHint, !accessibilityReduceMotion, let firstCategory = categories.first else { return }
        hasShownSwipeHint = true
        hintedCategoryID = firstCategory.id

        do {
            try await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = 22 }
            try await Task.sleep(for: .milliseconds(560))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = 0 }
            try await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = -22 }
            try await Task.sleep(for: .milliseconds(560))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = 0 }
        } catch {
            swipeHintOffset = 0
        }
    }

    private func deleteCategory(_ category: MovementCategory) {
        withAnimation {
            modelContext.delete(category)
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
    var onSaved: ((MovementCategory) -> Void)?

    init(category: MovementCategory? = nil, onSaved: ((MovementCategory) -> Void)? = nil) {
        self.category = category
        self.onSaved = onSaved
    }

    @State private var categoryName: String = ""
    @State private var selectedIcon: CategoryIcon = .tag
    @State private var selectedEmoji = ""
    @State private var usesEmoji = false
    @State private var selectedColor: CategoryColor = .blue
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case name
        case emoji
    }

    private var isEditing: Bool { category != nil }
    private var trimmedEmoji: String { selectedEmoji.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var previewIconRaw: String {
        usesEmoji && CategoryIcon.isValidEmoji(trimmedEmoji)
            ? CategoryIcon.emojiPrefix + trimmedEmoji
            : selectedIcon.rawValue
    }

    private let iconColumns = [GridItem(.adaptive(minimum: 46, maximum: 56), spacing: 8)]
    private let colorColumns = [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 8)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre de la categoría", text: $categoryName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                } header: {
                    FinanceGlassSectionHeader(title: "Nombre", systemImage: "textformat")
                }
                .financeGlassFormSection()

                Section {
                    Picker("Tipo de icono", selection: $usesEmoji) {
                        Text("Símbolos").tag(false)
                        Text("Emoji").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if usesEmoji {
                        HStack(spacing: 12) {
                            TextField("Ej. 🍜", text: $selectedEmoji)
                                .font(.title2)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .emoji)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                                .accessibilityLabel("Emoji de la categoría")

                            if !selectedEmoji.isEmpty {
                                Button {
                                    selectedEmoji = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Borrar emoji")
                            }
                        }

                        Text("Escribe o pega un solo emoji desde el teclado.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !trimmedEmoji.isEmpty && !CategoryIcon.isValidEmoji(trimmedEmoji) {
                            Text("Introduce un único emoji para continuar.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        LazyVGrid(columns: iconColumns, spacing: 8) {
                            ForEach(CategoryIcon.allCases) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon.systemName)
                                        .font(.system(size: 19, weight: .regular))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .background(selectedIcon == icon ? selectedColor.color.opacity(0.18) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(selectedIcon == icon ? Color.primary : Color.secondary.opacity(0.3), lineWidth: selectedIcon == icon ? 2 : 1)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Símbolo: \(icon.accessibilityName)")
                                .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    FinanceGlassSectionHeader(title: "Icono", systemImage: "square.grid.3x3", subtitle: "Elige un símbolo o escribe un emoji")
                }
                .financeGlassFormSection()

                Section {
                    LazyVGrid(columns: colorColumns, spacing: 8) {
                        ForEach(CategoryColor.allCases) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 25, height: 25)
                                                .background(Color.black.opacity(0.45), in: Circle())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(color.accessibilityName)")
                            .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    FinanceGlassSectionHeader(title: "Color", systemImage: "paintpalette", subtitle: "Acento para listas y gráficos")
                }
                .financeGlassFormSection()

                Section {
                    HStack(spacing: 10) {
                        if usesEmoji && !CategoryIcon.isValidEmoji(trimmedEmoji) {
                            Image(systemName: "questionmark")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 48, height: 48)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityHidden(true)
                        } else {
                            CategoryIconView(iconRaw: previewIconRaw, color: selectedColor.color, size: 48)
                        }

                        Text(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nombre de la categoría" : categoryName)
                            .fontWeight(.medium)
                            .lineLimit(2)
                    }
                } header: {
                    FinanceGlassSectionHeader(title: "Vista previa", systemImage: "eye")
                }
                .financeGlassFormSection()
            }
            .scrollDismissesKeyboard(.interactively)
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

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") {
                        focusedField = nil
                    }
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
        selectedEmoji = category.emoji ?? ""
        usesEmoji = category.emoji != nil
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

        if usesEmoji && !CategoryIcon.isValidEmoji(trimmedEmoji) {
            validationMessage = "Escribe un único emoji para la categoría."
            showingValidationAlert = true
            return
        }

        if let category {
            category.name = trimmedName
            category.icon = selectedIcon
            if usesEmoji { category.emoji = trimmedEmoji }
            category.categoryColor = selectedColor
            onSaved?(category)
        } else {
            let newCategory = MovementCategory(name: trimmedName, icon: selectedIcon, color: selectedColor)
            if usesEmoji { newCategory.emoji = trimmedEmoji }
            modelContext.insert(newCategory)
            onSaved?(newCategory)
        }

        dismiss()
    }
}

private extension CategoryIcon {
    var accessibilityName: String {
        switch self {
        case .tag: return "etiqueta"
        case .cart: return "carrito"
        case .forkKnife: return "comida"
        case .car: return "coche"
        case .house: return "casa"
        case .bolt: return "rayo"
        case .tv: return "televisión"
        case .heart: return "corazón"
        case .cross: return "salud"
        case .gameController: return "videojuegos"
        case .gift: return "regalo"
        case .plane: return "avión"
        case .briefcase: return "trabajo"
        case .graduationCap: return "estudios"
        case .chartBar: return "gráfico"
        case .banknote: return "billetes"
        case .creditcard: return "tarjeta"
        case .wrench: return "herramientas"
        case .phone: return "teléfono"
        case .wifi: return "wifi"
        case .headphones: return "auriculares"
        case .desktopComputer: return "ordenador de sobremesa"
        case .laptopComputer: return "portátil"
        case .camera: return "cámara"
        case .book: return "libro"
        case .bag: return "bolsa"
        case .bicycle: return "bicicleta"
        case .bus: return "autobús"
        case .train: return "tren"
        case .fuelpump: return "combustible"
        case .pawprint: return "mascotas"
        case .leaf: return "hoja"
        case .cup: return "café"
        case .birthdayCake: return "tarta"
        case .musicNote: return "música"
        case .paintbrush: return "arte"
        case .scissors: return "tijeras"
        case .stethoscope: return "medicina"
        case .building: return "edificio"
        case .shippingbox: return "paquete"
        case .ticket: return "entrada"
        case .dumbbell: return "deporte"
        }
    }
}

private extension CategoryColor {
    var accessibilityName: String {
        switch self {
        case .red: return "rojo"
        case .orange: return "naranja"
        case .yellow: return "amarillo"
        case .green: return "verde"
        case .mint: return "menta"
        case .teal: return "verde azulado"
        case .cyan: return "cian"
        case .blue: return "azul"
        case .indigo: return "añil"
        case .pink: return "rosa"
        case .brown: return "marrón"
        case .gray: return "gris"
        case .purple: return "morado"
        case .magenta: return "magenta"
        case .rose: return "rosa oscuro"
        case .coral: return "coral"
        case .amber: return "ámbar"
        case .lime: return "lima"
        case .olive: return "oliva"
        case .forest: return "verde bosque"
        case .navy: return "azul marino"
        case .sky: return "azul cielo"
        case .slate: return "pizarra"
        case .plum: return "ciruela"
        }
    }
}
