import SwiftUI
import SwiftData

@Observable
class PresetStore {
    private var modelContext: ModelContext

    var allPresets: [FoodPreset] = []

    var grouped: [(MealCategory, [FoodPreset])] {
        MealCategory.allCases.compactMap { cat in
            let items = allPresets.filter { $0.category == cat }.sorted { $0.sortOrder < $1.sortOrder }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        load()
    }

    func load() {
        let descriptor = FetchDescriptor<FoodPreset>(sortBy: [SortDescriptor(\.sortOrder)])
        let results = (try? modelContext.fetch(descriptor)) ?? []
        if results.isEmpty {
            seedDefaults()
        } else {
            allPresets = results
        }
    }

    func add(_ preset: FoodPreset) {
        preset.sortOrder = (allPresets.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(preset)
        allPresets.append(preset)
        save()
    }

    func update(_ preset: FoodPreset) {
        if let i = allPresets.firstIndex(where: { $0.id == preset.id }) {
            allPresets[i] = preset
        }
        save()
    }

    func remove(_ preset: FoodPreset) {
        allPresets.removeAll { $0.id == preset.id }
        modelContext.delete(preset)
        save()
    }

    func move(category: MealCategory, from source: IndexSet, to destination: Int) {
        var items = allPresets.filter { $0.category == category }.sorted { $0.sortOrder < $1.sortOrder }
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.sortOrder = categoryBaseOrder(category) + index
        }
        save()
        let descriptor = FetchDescriptor<FoodPreset>(sortBy: [SortDescriptor(\.sortOrder)])
        allPresets = (try? modelContext.fetch(descriptor)) ?? allPresets
    }

    func resetToDefaults() {
        for preset in allPresets {
            modelContext.delete(preset)
        }
        allPresets.removeAll()
        seedDefaults()
    }

    private func save() {
        try? modelContext.save()
    }

    private func categoryBaseOrder(_ category: MealCategory) -> Int {
        switch category {
        case .breakfast: return 0
        case .lunch: return 100
        case .snack: return 200
        case .dinner: return 300
        }
    }

    private func seedDefaults() {
        let defaults = Self.defaultPresets
        for preset in defaults {
            modelContext.insert(preset)
        }
        allPresets = defaults
        save()
    }

    static var defaultPresets: [FoodPreset] {
        var order = 0
        func next() -> Int { defer { order += 1 }; return order }
        return [
            // Breakfast
            FoodPreset(name: "Oats", calories: 300, protein: 10, icon: "leaf.fill", category: .breakfast, servingSize: "1 cup", sortOrder: next()),
            FoodPreset(name: "Greek Yogurt", calories: 130, protein: 15, icon: "cup.and.saucer.fill", category: .breakfast, servingSize: "1 cup", sortOrder: next()),
            FoodPreset(name: "Boiled Eggs", calories: 140, protein: 12, icon: "oval.fill", category: .breakfast, servingSize: "2 large", sortOrder: next()),
            FoodPreset(name: "Scrambled Eggs", calories: 200, protein: 12, icon: "frying.pan.fill", category: .breakfast, servingSize: "2 large", sortOrder: next()),
            FoodPreset(name: "Cappuccino", calories: 120, protein: 8, icon: "cup.and.heat.waves.fill", category: .breakfast, servingSize: "12 oz", sortOrder: next()),
            FoodPreset(name: "Protein Bar", calories: 320, protein: 20, icon: "rectangle.fill", category: .breakfast, servingSize: "1 bar", sortOrder: next()),
            // Lunch
            FoodPreset(name: "Meal Prep", calories: 640, protein: 40, icon: "fork.knife.circle.fill", category: .lunch, servingSize: "1 container", sortOrder: next()),
            FoodPreset(name: "Chicken Breast", calories: 165, protein: 31, icon: "bird.fill", category: .lunch, servingSize: "6 oz", sortOrder: next()),
            FoodPreset(name: "Rice", calories: 205, protein: 4, icon: "frying.pan.fill", category: .lunch, servingSize: "1 cup", sortOrder: next()),
            FoodPreset(name: "Poke Bowl", calories: 550, protein: 30, icon: "takeoutbag.and.cup.and.straw.fill", category: .lunch, servingSize: "1 bowl", sortOrder: next()),
            // Snack
            FoodPreset(name: "Coconut Water", calories: 120, protein: 0, icon: "drop.fill", category: .snack, servingSize: "1 bottle", sortOrder: next()),
            FoodPreset(name: "Cappuccino", calories: 120, protein: 8, icon: "cup.and.heat.waves.fill", category: .snack, servingSize: "12 oz", sortOrder: next()),
            FoodPreset(name: "Protein Shake", calories: 130, protein: 25, icon: "waterbottle.fill", category: .snack, servingSize: "1 scoop", sortOrder: next()),
            FoodPreset(name: "Blueberries", calories: 85, protein: 1, icon: "apple.meditate", category: .snack, servingSize: "1 cup", sortOrder: next()),
            FoodPreset(name: "Milk", calories: 150, protein: 8, icon: "mug.fill", category: .snack, servingSize: "1 cup", sortOrder: next()),
            // Dinner
            FoodPreset(name: "Tuna", calories: 130, protein: 28, icon: "fish.fill", category: .dinner, servingSize: "1 can", sortOrder: next()),
            FoodPreset(name: "Beans", calories: 220, protein: 15, icon: "leaf.circle.fill", category: .dinner, servingSize: "1 cup", sortOrder: next()),
            FoodPreset(name: "Steamed Veggies", calories: 80, protein: 4, icon: "carrot.fill", category: .dinner, servingSize: "1 cup", sortOrder: next()),
            FoodPreset(name: "Rice", calories: 205, protein: 4, icon: "frying.pan.fill", category: .dinner, servingSize: "1 cup", sortOrder: next()),
        ]
    }
}

struct FoodLogView: View {
    static let dailyCalorieGoal = 2400

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodEntry.date, order: .reverse) private var allEntries: [FoodEntry]

    @State private var showingAddSheet = false

    private var todayEntries: [FoodEntry] {
        let calendar = Calendar.current
        return allEntries.filter { calendar.isDateInToday($0.date) }
    }

    private var totalCalories: Int {
        todayEntries.reduce(0) { $0 + $1.calories }
    }

    private var remainingCalories: Int {
        max(Self.dailyCalorieGoal - totalCalories, 0)
    }

    private var progress: Double {
        min(Double(totalCalories) / Double(Self.dailyCalorieGoal), 1.0)
    }

    private var progressColor: Color {
        if totalCalories > Self.dailyCalorieGoal { return .red }
        if progress >= 0.75 { return .orange }
        return .green
    }

    private var groupedEntries: [(MealCategory, [FoodEntry])] {
        MealCategory.allCases.compactMap { category in
            let entries = todayEntries.filter { $0.category == category }
            return entries.isEmpty ? nil : (category, entries)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                calorieRing
                mealList
            }
            .navigationTitle("Food Log")
            .toolbar {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddFoodSheet()
            }
        }
    }

    private var calorieRing: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            VStack(spacing: 4) {
                if totalCalories > Self.dailyCalorieGoal {
                    Text("\(totalCalories - Self.dailyCalorieGoal)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("over budget")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("\(remainingCalories)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("cal remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(totalCalories) / \(Self.dailyCalorieGoal)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, height: 180)
        .padding(.top)
    }

    private var mealList: some View {
        List {
            if todayEntries.isEmpty {
                ContentUnavailableView(
                    "No meals logged",
                    systemImage: "fork.knife",
                    description: Text("Tap + to log your first meal")
                )
            } else {
                ForEach(groupedEntries, id: \.0) { category, entries in
                    Section {
                        ForEach(entries) { entry in
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text("\(entry.calories) cal")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                modelContext.delete(entries[index])
                            }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

enum AddFoodStep {
    case pickPreset
    case editDetails
}

struct AddFoodSheet: View {
    var initialDate: Date = Date()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var presetStore: PresetStore?
    @State private var step: AddFoodStep = .pickPreset
    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var category: MealCategory = MealCategory.forTime(.now)
    @State private var date: Date = Date()
    @State private var showingManagePresets = false

    @FocusState private var focusedField: Field?
    enum Field { case name, calories, protein }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pickPreset:
                    presetGrid
                case .editDetails:
                    detailsForm
                }
            }
            .navigationTitle(step == .pickPreset ? "What did you eat?" : "Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if step == .editDetails {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { save() }
                            .disabled(name.isEmpty || Int(caloriesText) == nil)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            date = initialDate
        }
        .task {
            if presetStore == nil {
                presetStore = PresetStore(modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showingManagePresets) {
            if let presetStore {
                ManagePresetsSheet(store: presetStore)
            }
        }
    }

    private var presetGrid: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 12) {
                    Button {
                        selectOther()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Custom meal")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingManagePresets = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .frame(width: 50, height: 50)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                ForEach(presetStore?.grouped ?? [], id: \.0) { category, items in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(category.rawValue, systemImage: category.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { preset in
                                Button {
                                    selectPreset(preset)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: preset.icon)
                                            .font(.title2)
                                            .frame(height: 28)
                                        Text(preset.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                        Text("\(preset.calories) cal")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if !preset.servingSize.isEmpty {
                                            Text(preset.servingSize)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var detailsForm: some View {
        Form {
            TextField("Meal name", text: $name)
                .focused($focusedField, equals: .name)
            TextField("Calories", text: $caloriesText)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .calories)
            TextField("Protein (g)", text: $proteinText)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .protein)
            Picker("Meal", selection: $category) {
                ForEach(MealCategory.allCases, id: \.self) { cat in
                    Label(cat.rawValue, systemImage: cat.icon)
                        .tag(cat)
                }
            }
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
        }
        .onAppear {
            focusedField = .name
        }
    }

    private func selectPreset(_ preset: FoodPreset) {
        name = preset.name
        caloriesText = "\(preset.calories)"
        proteinText = preset.protein > 0 ? "\(preset.protein)" : ""
        category = preset.category
        step = .editDetails
    }

    private func selectOther() {
        name = ""
        caloriesText = ""
        proteinText = ""
        category = MealCategory.forTime(.now)
        step = .editDetails
    }

    private func save() {
        guard let calories = Int(caloriesText), !name.isEmpty else { return }
        let protein = Int(proteinText) ?? 0
        let entry = FoodEntry(name: name, calories: calories, protein: protein, date: date, category: category)
        modelContext.insert(entry)
        dismiss()
    }
}

struct ManagePresetsSheet: View {
    @Bindable var store: PresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingPreset: FoodPreset?
    @State private var showingAddPreset = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.grouped, id: \.0) { category, items in
                    Section {
                        ForEach(items) { preset in
                            Button {
                                editingPreset = preset
                            } label: {
                                HStack {
                                    Image(systemName: preset.icon)
                                        .frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text(preset.name)
                                        HStack(spacing: 8) {
                                            Text("\(preset.calories) cal")
                                            if preset.protein > 0 {
                                                Text("\(preset.protein)g protein")
                                            }
                                            if !preset.servingSize.isEmpty {
                                                Text(preset.servingSize)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.remove(items[index])
                            }
                        }
                        .onMove { source, destination in
                            store.move(category: category, from: source, to: destination)
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }

                Section {
                    Button {
                        store.resetToDefaults()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Manage Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        EditButton()
                        Button {
                            showingAddPreset = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(item: $editingPreset) { preset in
                EditPresetSheet(store: store, preset: preset)
            }
            .sheet(isPresented: $showingAddPreset) {
                EditPresetSheet(store: store, preset: nil)
            }
        }
    }
}

struct EditPresetSheet: View {
    var store: PresetStore
    var preset: FoodPreset?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var icon = "fork.knife"
    @State private var category: MealCategory = .lunch
    @State private var servingSize = ""
    @State private var showingSymbolPicker = false

    private var isEditing: Bool { preset != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Calories", text: $caloriesText)
                    .keyboardType(.numberPad)
                TextField("Protein (g)", text: $proteinText)
                    .keyboardType(.numberPad)
                TextField("Serving size (e.g. 1 cup)", text: $servingSize)
                Button {
                    showingSymbolPicker = true
                } label: {
                    HStack {
                        Text("Icon")
                        Spacer()
                        Image(systemName: icon)
                            .font(.title2)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                Picker("Meal", selection: $category) {
                    ForEach(MealCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Preset" : "New Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePreset() }
                        .disabled(name.isEmpty || Int(caloriesText) == nil)
                }
            }
            .sheet(isPresented: $showingSymbolPicker) {
                SymbolPickerSheet(selectedSymbol: $icon)
            }
            .onAppear {
                if let p = preset {
                    name = p.name
                    caloriesText = "\(p.calories)"
                    proteinText = p.protein > 0 ? "\(p.protein)" : ""
                    icon = p.icon
                    category = p.category
                    servingSize = p.servingSize
                }
            }
        }
    }

    private func savePreset() {
        let cal = Int(caloriesText) ?? 0
        let prot = Int(proteinText) ?? 0
        if let existing = preset {
            existing.name = name
            existing.calories = cal
            existing.protein = prot
            existing.icon = icon
            existing.category = category
            existing.servingSize = servingSize
            store.update(existing)
        } else {
            let new = FoodPreset(name: name, calories: cal, protein: prot, icon: icon, category: category, servingSize: servingSize)
            store.add(new)
        }
        dismiss()
    }
}

struct SymbolPickerSheet: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private static let symbols = [
        "fork.knife", "fork.knife.circle.fill",
        "cup.and.saucer.fill", "cup.and.heat.waves.fill",
        "mug.fill", "wineglass.fill", "waterbottle.fill",
        "takeoutbag.and.cup.and.straw.fill",
        "carrot.fill", "frying.pan.fill", "birthday.cake.fill",
        "leaf.fill", "leaf.circle.fill",
        "fish.fill", "bird.fill", "hare.fill", "tortoise.fill",
        "ladybug.fill", "ant.fill",
        "figure.walk", "figure.run", "figure.cooldown",
        "figure.strengthtraining.traditional",
        "figure.yoga", "figure.dance", "figure.hiking",
        "dumbbell.fill", "sportscourt.fill", "bicycle",
        "heart.fill", "heart.circle.fill",
        "bolt.fill", "flame.fill",
        "cross.vial.fill", "pills.fill",
        "stethoscope",
        "star.fill", "drop.fill",
        "sun.max.fill", "moon.stars.fill", "sunrise.fill",
        "snowflake", "globe",
        "oval.fill", "rectangle.fill", "capsule.fill",
        "plus.circle.fill", "minus.circle.fill",
        "scalemass.fill", "clock.fill",
        "bag.fill", "cart.fill", "basket.fill",
        "apple.logo",
    ]

    private var filtered: [String] {
        if searchText.isEmpty { return Self.symbols }
        return Self.symbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = [GridItem(.adaptive(minimum: 56))]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filtered, id: \.self) { symbol in
                        Button {
                            selectedSymbol = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.title2)
                                .frame(width: 48, height: 48)
                                .background(
                                    selectedSymbol == symbol
                                        ? Color.accentColor.opacity(0.2)
                                        : Color(.systemGray6),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search symbols")
            .navigationTitle("Pick Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    FoodLogView()
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
