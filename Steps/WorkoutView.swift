import SwiftUI
import SwiftData

struct WorkoutType: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let icon: String
    let isBuiltIn: Bool

    static let upper = WorkoutType(name: "Upper Body", icon: "figure.arms.open", isBuiltIn: true)
    static let lower = WorkoutType(name: "Lower Body", icon: "figure.walk", isBuiltIn: true)
    static let builtIn: [WorkoutType] = [.upper, .lower]
}

struct ExerciseInfo: Identifiable, Hashable, Codable {
    let name: String
    let categoryName: String
    let defaultWeight: Double
    let defaultReps: Int
    var id: String { name }
}

struct EditWorkoutInfo: Identifiable {
    let date: Date
    let workoutType: WorkoutType
    var id: Date { date }
}

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSet.date, order: .reverse) private var allSets: [WorkoutSet]
    @Query(sort: \GymEntry.date, order: .reverse) private var gymEntries: [GymEntry]

    @State private var activeType: WorkoutType?
    @State private var editWorkout: EditWorkoutInfo?
    @State private var showingCategoryPicker = false
    @State private var showingSettings = false
    @State private var showingContact = false
    @AppStorage("restTimerSeconds") private var restDuration: Int = 120
    @AppStorage("customExercisesJSON") private var customExercisesJSON: String = "[]"
    @AppStorage("customWorkoutTypesJSON") private var customWorkoutTypesJSON: String = "[]"

    static let builtInExercises: [ExerciseInfo] = [
        ExerciseInfo(name: "Bench Press", categoryName: "Upper Body", defaultWeight: 135, defaultReps: 10),
        ExerciseInfo(name: "Shoulder Press", categoryName: "Upper Body", defaultWeight: 80, defaultReps: 10),
        ExerciseInfo(name: "Bicep Curls", categoryName: "Upper Body", defaultWeight: 25, defaultReps: 12),
        ExerciseInfo(name: "Tricep Curls", categoryName: "Upper Body", defaultWeight: 25, defaultReps: 12),
        ExerciseInfo(name: "Lat Pulldown", categoryName: "Upper Body", defaultWeight: 120, defaultReps: 10),
        ExerciseInfo(name: "Row", categoryName: "Upper Body", defaultWeight: 100, defaultReps: 10),
        ExerciseInfo(name: "Leg Extension", categoryName: "Lower Body", defaultWeight: 90, defaultReps: 12),
        ExerciseInfo(name: "Leg Curl", categoryName: "Lower Body", defaultWeight: 80, defaultReps: 12),
        ExerciseInfo(name: "Glute Kickback", categoryName: "Lower Body", defaultWeight: 100, defaultReps: 12),
        ExerciseInfo(name: "Hip Adductor", categoryName: "Lower Body", defaultWeight: 120, defaultReps: 15),
        ExerciseInfo(name: "Hip Abductor", categoryName: "Lower Body", defaultWeight: 100, defaultReps: 15),
    ]

    var customExercises: [ExerciseInfo] {
        (try? JSONDecoder().decode([ExerciseInfo].self, from: Data(customExercisesJSON.utf8))) ?? []
    }

    var customWorkoutTypes: [WorkoutType] {
        (try? JSONDecoder().decode([WorkoutType].self, from: Data(customWorkoutTypesJSON.utf8))) ?? []
    }

    var allWorkoutTypes: [WorkoutType] {
        WorkoutType.builtIn + customWorkoutTypes
    }

    var allExercises: [ExerciseInfo] {
        Self.builtInExercises + customExercises
    }

    func exercises(for type: WorkoutType) -> [ExerciseInfo] {
        allExercises.filter { $0.categoryName == type.name }
    }

    func addCustomExercise(_ exercise: ExerciseInfo) {
        var list = customExercises
        list.append(exercise)
        if let data = try? JSONEncoder().encode(list) {
            customExercisesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    func removeCustomExercise(_ name: String) {
        var list = customExercises
        list.removeAll { $0.name == name }
        if let data = try? JSONEncoder().encode(list) {
            customExercisesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    func addCustomWorkoutType(_ type: WorkoutType) {
        var list = customWorkoutTypes
        list.append(type)
        if let data = try? JSONEncoder().encode(list) {
            customWorkoutTypesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    func removeCustomWorkoutType(_ name: String) {
        var list = customWorkoutTypes
        list.removeAll { $0.name == name }
        if let data = try? JSONEncoder().encode(list) {
            customWorkoutTypesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
        var exercises = customExercises
        exercises.removeAll { $0.categoryName == name }
        if let data = try? JSONEncoder().encode(exercises) {
            customExercisesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    private var recentWorkouts: [(date: Date, workoutType: WorkoutType, exerciseCount: Int, duration: Int)] {
        return gymEntries.prefix(20).compactMap { entry in
            let sets = allSets.filter { $0.date == entry.date }
            guard !sets.isEmpty else { return nil }
            let exerciseNames = Set(sets.map(\.exerciseName))
            let matchedType = allWorkoutTypes.first { type in
                let typeExercises = allExercises.filter { $0.categoryName == type.name }
                return typeExercises.contains { exerciseNames.contains($0.name) }
            } ?? WorkoutType.upper
            return (entry.date, matchedType, exerciseNames.count, entry.duration)
        }
    }

    private var groupedByDay: [(day: Date, workouts: [(date: Date, workoutType: WorkoutType, exerciseCount: Int, duration: Int)])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recentWorkouts) { workout in
            calendar.startOfDay(for: workout.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    private func smartDateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())),
                  date >= weekAgo {
            return date.formatted(.dateTime.weekday(.wide))
        } else {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        for offset in offsets {
            let workout = recentWorkouts[offset]
            let setsToDelete = allSets.filter { $0.date == workout.date }
            for set in setsToDelete {
                modelContext.delete(set)
            }
            let entriesToDelete = gymEntries.filter { $0.date == workout.date }
            for entry in entriesToDelete {
                modelContext.delete(entry)
            }
        }
        try? modelContext.save()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button {
                    showingCategoryPicker = true
                } label: {
                    HStack {
                        Text("Start Workout")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if recentWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "dumbbell.fill",
                        description: Text("Start your first workout to track your progress")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(groupedByDay, id: \.day) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(smartDateLabel(group.day))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

                                    ForEach(group.workouts, id: \.date) { workout in
                                        Button {
                                            editWorkout = EditWorkoutInfo(date: workout.date, workoutType: workout.workoutType)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: workout.workoutType.icon)
                                                    .font(.title3)
                                                    .foregroundStyle(AppColors.accent)
                                                    .frame(width: 32)
                                                Text(workout.workoutType.name)
                                                    .font(.body.weight(.medium))
                                                Spacer()
                                                VStack(alignment: .trailing, spacing: 3) {
                                                    Text("\(workout.exerciseCount) exercises")
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                    if workout.duration > 0 {
                                                        Text(formatDuration(workout.duration))
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding()
                                            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                if let index = recentWorkouts.firstIndex(where: { $0.date == workout.date }) {
                                                    deleteWorkouts(at: IndexSet(integer: index))
                                                }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                }

            }
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color(.label))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingContact = true
                    } label: {
                        Image(systemName: "envelope")
                            .foregroundStyle(Color(.label))
                    }
                }
            }
            .sheet(isPresented: $showingContact) {
                ContactUsSheet()
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet(
                    workoutTypes: allWorkoutTypes,
                    exercisesForType: { exercises(for: $0) },
                    onSelect: { type in
                        showingCategoryPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            activeType = type
                        }
                    },
                    onAddCustom: { type in
                        addCustomWorkoutType(type)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(.systemBackground))
            }
            .fullScreenCover(item: $activeType) { type in
                ActiveWorkoutView(
                    workoutType: type,
                    exercises: exercises(for: type),
                    restDuration: $restDuration
                )
                .background(Color(.systemBackground))
            }
            .fullScreenCover(item: $editWorkout) { info in
                ActiveWorkoutView(
                    workoutType: info.workoutType,
                    exercises: exercises(for: info.workoutType),
                    restDuration: $restDuration,
                    editDate: info.date
                )
                .background(Color(.systemBackground))
            }
            .sheet(isPresented: $showingSettings) {
                WorkoutSettingsSheet(
                    restDuration: $restDuration,
                    workoutTypes: allWorkoutTypes,
                    allExercises: allExercises,
                    customExercises: customExercises,
                    onAddExercise: { addCustomExercise($0) },
                    onRemoveExercise: { removeCustomExercise($0) },
                    onAddWorkoutType: { addCustomWorkoutType($0) },
                    onRemoveWorkoutType: { removeCustomWorkoutType($0) }
                )
                .presentationBackground(Color(.systemBackground))
            }
        }
    }
}

// MARK: - Category Picker Sheet

struct CategoryPickerSheet: View {
    let workoutTypes: [WorkoutType]
    let exercisesForType: (WorkoutType) -> [ExerciseInfo]
    let onSelect: (WorkoutType) -> Void
    var onAddCustom: ((WorkoutType) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showingAddWorkoutType = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(workoutTypes) { type in
                        let exercises = exercisesForType(type)
                        Button {
                            onSelect(type)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: type.icon)
                                        .font(.title2)
                                        .foregroundStyle(AppColors.accent)
                                        .frame(width: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(type.name)
                                            .font(.headline)
                                        Text("\(exercises.count) exercises")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }

                                FlowLayout(spacing: 6) {
                                    ForEach(exercises) { exercise in
                                        Text(exercise.name)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(AppColors.accent.opacity(0.1), in: Capsule())
                                            .foregroundStyle(AppColors.accent)
                                    }
                                }
                            }
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.fill.quinary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if onAddCustom != nil {
                        Button {
                            showingAddWorkoutType = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppColors.accent)
                                    .frame(width: 36)
                                Text("Custom")
                                    .font(.headline)
                                Spacer()
                            }
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                                    .foregroundStyle(Color(.quaternaryLabel))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddWorkoutType) {
                AddWorkoutTypeSheet { type in
                    onAddCustom?(type)
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    let categoryName: String
    let onAdd: (ExerciseInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var weightText = ""
    @State private var repsText = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                    .focused($focused)
                TextField("Starting weight (lbs)", text: $weightText)
                    .keyboardType(.decimalPad)
                TextField("Starting reps", text: $repsText)
                    .keyboardType(.numberPad)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let exercise = ExerciseInfo(
                            name: name.trimmingCharacters(in: .whitespaces),
                            categoryName: categoryName,
                            defaultWeight: Double(weightText) ?? 50,
                            defaultReps: Int(repsText) ?? 10
                        )
                        onAdd(exercise)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Add Workout Type Sheet

struct AddWorkoutTypeSheet: View {
    let onAdd: (WorkoutType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIcon = "figure.strengthtraining.traditional"
    @FocusState private var focused: Bool

    private let iconOptions = [
        "figure.strengthtraining.traditional",
        "figure.arms.open",
        "figure.walk",
        "figure.run",
        "figure.core.training",
        "figure.flexibility",
        "figure.highintensity.intervaltraining",
        "figure.pilates",
        "figure.yoga",
        "dumbbell.fill",
        "heart.circle.fill",
        "bolt.fill",
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Workout name", text: $name)
                    .focused($focused)

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        selectedIcon == icon ? AppColors.accent.opacity(0.15) : Color(.systemGray6),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .foregroundStyle(selectedIcon == icon ? AppColors.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let type = WorkoutType(
                            name: name.trimmingCharacters(in: .whitespaces),
                            icon: selectedIcon,
                            isBuiltIn: false
                        )
                        onAdd(type)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Workout Settings

struct WorkoutSettingsSheet: View {
    @Binding var restDuration: Int
    let workoutTypes: [WorkoutType]
    let allExercises: [ExerciseInfo]
    let customExercises: [ExerciseInfo]
    let onAddExercise: (ExerciseInfo) -> Void
    let onRemoveExercise: (String) -> Void
    let onAddWorkoutType: (WorkoutType) -> Void
    let onRemoveWorkoutType: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int = 2
    @State private var seconds: Int = 0
    @State private var showingAddWorkoutType = false

    var body: some View {
        NavigationStack {
            List {
                Section("Rest Timer") {
                    HStack(spacing: 0) {
                        Spacer()
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0...10, id: \.self) { m in
                                Text("\(m)").tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        .clipped()

                        Text("min")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Seconds", selection: $seconds) {
                            ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { s in
                                Text(String(format: "%02d", s)).tag(s)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80)
                        .clipped()

                        Text("sec")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets())
                }

                Section("Workouts") {
                    ForEach(workoutTypes) { type in
                        let exerciseCount = allExercises.filter { $0.categoryName == type.name }.count
                        NavigationLink {
                            WorkoutTypeDetailView(
                                workoutType: type,
                                allExercises: allExercises,
                                customExercises: customExercises,
                                onAddExercise: onAddExercise,
                                onRemoveExercise: onRemoveExercise
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .font(.title3)
                                    .foregroundStyle(AppColors.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(type.name)
                                        .font(.body.weight(.medium))
                                    Text("\(exerciseCount) exercises")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            let type = workoutTypes[offset]
                            if !type.isBuiltIn {
                                onRemoveWorkoutType(type.name)
                            }
                        }
                    }

                    Button {
                        showingAddWorkoutType = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppColors.accent)
                            Text("Add Workout")
                        }
                    }
                }
            }
            .navigationTitle("Workout Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        restDuration = max(minutes * 60 + seconds, 5)
                        dismiss()
                    }
                }
            }
            .onAppear {
                minutes = restDuration / 60
                seconds = (restDuration % 60 / 5) * 5
            }
            .sheet(isPresented: $showingAddWorkoutType) {
                AddWorkoutTypeSheet { type in
                    onAddWorkoutType(type)
                }
            }
        }
    }
}

// MARK: - Workout Type Detail

struct WorkoutTypeDetailView: View {
    let workoutType: WorkoutType
    let allExercises: [ExerciseInfo]
    let customExercises: [ExerciseInfo]
    let onAddExercise: (ExerciseInfo) -> Void
    let onRemoveExercise: (String) -> Void

    @State private var showingAddExercise = false

    private var exercisesForType: [ExerciseInfo] {
        allExercises.filter { $0.categoryName == workoutType.name }
    }

    var body: some View {
        List {
            ForEach(exercisesForType) { exercise in
                HStack {
                    Text(exercise.name)
                    Spacer()
                    if customExercises.contains(where: { $0.name == exercise.name }) {
                        Text("Custom")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray5), in: Capsule())
                    }
                    Text("\(Int(exercise.defaultWeight)) lbs · \(exercise.defaultReps) reps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    let exercise = exercisesForType[offset]
                    if customExercises.contains(where: { $0.name == exercise.name }) {
                        onRemoveExercise(exercise.name)
                    }
                }
            }

            Button {
                showingAddExercise = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(AppColors.accent)
                    Text("Add Exercise")
                }
            }
        }
        .navigationTitle(workoutType.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseSheet(categoryName: workoutType.name) { exercise in
                onAddExercise(exercise)
            }
        }
    }
}

// MARK: - Active Workout

struct ActiveWorkoutView: View {
    let workoutType: WorkoutType
    let exercises: [ExerciseInfo]
    @Binding var restDuration: Int
    var editDate: Date?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSet.date, order: .reverse) private var allSets: [WorkoutSet]

    @State private var sessionSets: [String: [SetEntry]] = [:]
    @State private var showingFinishConfirm = false
    @State private var isEditing = false
    @State private var timerRemaining: Int = 0
    @State private var timerActive = false
    @State private var timerTask: Task<Void, Never>?
    @State private var elapsedSeconds: Int = 0
    @State private var sessionTimerTask: Task<Void, Never>?

    private var isEditMode: Bool { editDate != nil }

    private var editDateTitle: String {
        guard let editDate else { return workoutType.name }
        return editDate.formatted(.dateTime.month().day())
    }

    private var completedExerciseCount: Int {
        exercises.filter { exercise in
            let sets = sessionSets[exercise.name] ?? []
            return !sets.isEmpty && sets.allSatisfy { $0.completed }
        }.count
    }

    private var totalSets: Int {
        exercises.reduce(0) { $0 + (sessionSets[$1.name]?.count ?? 0) }
    }

    private var completedSets: Int {
        exercises.reduce(0) { $0 + (sessionSets[$1.name]?.filter(\.completed).count ?? 0) }
    }

    private var progressFraction: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }

    struct SetEntry: Identifiable {
        let id = UUID()
        var weight: String = ""
        var reps: String = ""
        var completed = false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 10)
                            Capsule()
                                .fill(AppColors.accent)
                                .frame(width: geo.size.width * progressFraction, height: 6)
                                .animation(.easeInOut(duration: 0.3), value: progressFraction)
                        }
                    }
                    .frame(height: 10)

                    HStack {
                        Text("\(completedSets)/\(totalSets) sets")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !isEditMode {
                            HStack(spacing: 5) {
                                Image(systemName: "timer")
                                    .font(.subheadline)
                                Text(formatElapsed(elapsedSeconds))
                                    .font(.body.weight(.semibold).monospacedDigit())
                            }
                            .foregroundStyle(AppColors.accent)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                            exerciseCard(exercise, number: index + 1)
                        }
                    }
                    .padding()
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }

                restTimerBar
            }
            .navigationTitle(isEditMode ? editDateTitle : workoutType.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if !isEditMode && hasAnyInput {
                            showingFinishConfirm = true
                        } else {
                            stopTimer()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                        if isEditMode {
                            Button {
                                withAnimation { isEditing.toggle() }
                            } label: {
                                Image(systemName: isEditing ? "checkmark" : "pencil")
                                    .font(.subheadline)
                            }
                        }
                        Button(isEditMode ? "Save" : "Finish") { stopTimer(); saveAndDismiss() }
                            .fontWeight(.semibold)
                            .disabled(!hasAnyInput)
                    }
                }
            }
            .confirmationDialog("Discard workout?", isPresented: $showingFinishConfirm) {
                Button("Discard", role: .destructive) { stopTimer(); dismiss() }
                Button("Save & Finish") { stopTimer(); saveAndDismiss() }
                Button("Cancel", role: .cancel) { }
            }
            .onAppear {
                prepopulate()
                if isEditMode {
                    isEditing = true
                } else {
                    startSessionTimer()
                }
            }
            .onDisappear {
                sessionTimerTask?.cancel()
            }
        }
    }

    // MARK: - Timer Bar

    private var restTimerBar: some View {
        HStack(spacing: 16) {
            if timerActive {
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(timerRemaining) / CGFloat(max(restDuration, 1)))
                        .stroke(timerRemaining > 0 ? AppColors.accent : AppColors.success, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timerRemaining)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timerRemaining > 0 ? "Rest" : "Done!")
                        .font(.subheadline.weight(.semibold))
                    Text(formatTimer(timerRemaining))
                        .font(.title3.weight(.bold).monospacedDigit())
                }

                Spacer()

                Button {
                    skipTimer()
                } label: {
                    Text(timerRemaining > 0 ? "Skip" : "Dismiss")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.fill.tertiary, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    startRestTimer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                        Text("Rest \(formatTimer(restDuration))")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Exercise Card

    @ViewBuilder
    private func exerciseCard(_ exercise: ExerciseInfo, number: Int) -> some View {
        let sets = sessionSets[exercise.name] ?? []
        let completedCount = sets.filter(\.completed).count

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(completedCount)/\(sets.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 1)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                Text("SET")
                    .frame(width: 24, alignment: .center)
                Text("WEIGHT")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("")
                    .font(.subheadline)
                    .frame(width: 8)
                Text("REPS")
                    .frame(maxWidth: .infinity, alignment: .center)
                Color.clear
                    .frame(width: 36)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, setEntry in
                    setRow(exercise: exercise.name, index: index, setEntry: setEntry)
                }
            }

        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.fill.quinary)
        }
    }

    // MARK: - Set Row

    @ViewBuilder
    private func setRow(exercise: String, index: Int, setEntry: SetEntry) -> some View {
        let fieldBg: Color = setEntry.completed ? AppColors.accent.opacity(0.08) : Color(.systemBackground)
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(setEntry.completed ? AppColors.accent : Color(.tertiaryLabel))
                .frame(width: 24)

            valueField(
                value: binding(exercise: exercise, index: index, keyPath: \.weight),
                unit: "lbs",
                keyboard: .decimalPad,
                bg: fieldBg
            )

            Text("×")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            valueField(
                value: binding(exercise: exercise, index: index, keyPath: \.reps),
                unit: "reps",
                keyboard: .numberPad,
                bg: fieldBg
            )

            Button {
                markSetDone(exercise: exercise, index: index)
            } label: {
                ZStack {
                    if setEntry.completed {
                        Circle()
                            .fill(AppColors.success)
                            .frame(width: 30, height: 30)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .stroke(Color(.systemGray4), lineWidth: 2)
                            .frame(width: 30, height: 30)
                    }
                }
                .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func valueField(
        value: Binding<String>,
        unit: String,
        keyboard: UIKeyboardType,
        bg: Color
    ) -> some View {
        TextField("0", text: value)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.bold))
            .textFieldStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(bg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
    }


    // MARK: - Helpers

    private func binding(exercise: String, index: Int, keyPath: WritableKeyPath<SetEntry, String>) -> Binding<String> {
        Binding(
            get: { sessionSets[exercise]?[safe: index]?[keyPath: keyPath] ?? "" },
            set: { newValue in
                if sessionSets[exercise] != nil && index < sessionSets[exercise]!.count {
                    sessionSets[exercise]![index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var hasAnyInput: Bool {
        sessionSets.values.flatMap { $0 }.contains { !$0.weight.isEmpty || !$0.reps.isEmpty }
    }

    private func prepopulate() {
        if let editDate {
            let daySets = allSets.filter { $0.date == editDate }
            let grouped = Dictionary(grouping: daySets) { $0.exerciseName }
            for exercise in exercises {
                if let sets = grouped[exercise.name]?.sorted(by: { $0.setNumber < $1.setNumber }), !sets.isEmpty {
                    sessionSets[exercise.name] = sets.map { set in
                        SetEntry(weight: formatWeight(set.weight), reps: "\(set.reps)", completed: true)
                    }
                } else {
                    sessionSets[exercise.name] = []
                }
            }
        } else {
            for exercise in exercises {
                let lastSets = previousSets(for: exercise.name)
                if lastSets.isEmpty {
                    let w = formatWeight(exercise.defaultWeight)
                    let r = "\(exercise.defaultReps)"
                    sessionSets[exercise.name] = [
                        SetEntry(weight: w, reps: r),
                        SetEntry(weight: w, reps: r),
                        SetEntry(weight: w, reps: r),
                    ]
                } else {
                    sessionSets[exercise.name] = lastSets.map { set in
                        SetEntry(weight: formatWeight(set.weight), reps: "\(set.reps)")
                    }
                }
            }
        }
    }

    private func previousSets(for exerciseName: String) -> [WorkoutSet] {
        let pastSets = allSets.filter { $0.exerciseName == exerciseName && $0.date < Date() }
        guard let lastDate = pastSets.first?.date else { return [] }
        return pastSets
            .filter { $0.date == lastDate }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func progressionSuggestion(for exerciseName: String) -> String? {
        let previous = previousSets(for: exerciseName)
        guard !previous.isEmpty else { return nil }
        let maxWeight = previous.map(\.weight).max() ?? 0
        let allHitTarget = previous.allSatisfy { $0.reps >= 12 }
        if allHitTarget {
            return "Try \(formatWeight(maxWeight + 5)) lbs"
        }
        let avgReps = previous.map(\.reps).reduce(0, +) / previous.count
        if avgReps < 8 {
            return "Focus on \(formatWeight(maxWeight)) × 8+"
        }
        return nil
    }

    private func markSetDone(exercise: String, index: Int) {
        guard sessionSets[exercise] != nil && index < sessionSets[exercise]!.count else { return }
        sessionSets[exercise]![index].completed.toggle()
    }

    private func startRestTimer() {
        stopTimer()
        timerRemaining = restDuration
        timerActive = true
        timerTask = Task {
            while timerRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    timerRemaining -= 1
                }
            }
            if !Task.isCancelled {
                timerActive = false
            }
        }
    }

    private func skipTimer() {
        stopTimer()
        withAnimation {
            timerRemaining = 0
            timerActive = false
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func startSessionTimer() {
        sessionTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    elapsedSeconds += 1
                }
            }
        }
    }

    private func formatTimer(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatElapsed(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func saveAndDismiss() {
        sessionTimerTask?.cancel()

        if let editDate {
            let oldSets = allSets.filter { $0.date == editDate }
            for old in oldSets {
                modelContext.delete(old)
            }
        }

        let saveDate = editDate ?? Date()
        for exercise in exercises {
            let sets = sessionSets[exercise.name] ?? []
            for (index, entry) in sets.enumerated() {
                guard let weight = Double(entry.weight), let reps = Int(entry.reps),
                      weight > 0, reps > 0 else { continue }
                let workoutSet = WorkoutSet(
                    exerciseName: exercise.name,
                    weight: weight,
                    reps: reps,
                    setNumber: index,
                    date: saveDate
                )
                modelContext.insert(workoutSet)
            }
        }

        if !isEditMode {
            let gymEntry = GymEntry(date: saveDate, duration: elapsedSeconds)
            modelContext.insert(gymEntry)
        }

        try? modelContext.save()
        dismiss()
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    WorkoutView()
        .modelContainer(for: WorkoutSet.self, inMemory: true)
}
