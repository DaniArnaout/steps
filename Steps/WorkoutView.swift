import SwiftUI
import SwiftData
import ActivityKit
import UserNotifications

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
    let workoutID: String
    var id: String { workoutID }
}

struct WorkoutDetailInfo: Identifiable {
    let id: String
    let date: Date
    let workoutType: WorkoutType
    let duration: Int
    let journeyData: [JourneyBlock]
}

// MARK: - Live Activity

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endTime: Date
        var totalDuration: Int
    }
    var workoutName: String
}

// MARK: - Journey Data

struct JourneySetInfo: Identifiable {
    let id = UUID()
    let weight: String
    let reps: String
    let setNumber: Int
    let completionOrder: Int
}

struct JourneyBlock: Identifiable {
    let id = UUID()
    let exerciseName: String
    let sets: [JourneySetInfo]
}

struct SetEntry: Identifiable {
    let id = UUID()
    var weight: String = ""
    var reps: String = ""
    var completed = false
    var completionOrder: Int = -1
}

// MARK: - WorkoutView

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSet.date, order: .reverse) private var allSets: [WorkoutSet]
    @Query(sort: \GymEntry.date, order: .reverse) private var gymEntries: [GymEntry]

    @State private var activeType: WorkoutType?
    @State private var editWorkout: EditWorkoutInfo?
    @State private var showingCategoryPicker = false
    @State private var showingSettings = false
    @State private var showingContact = false
    @State private var detailWorkout: WorkoutDetailInfo?
    @State private var showingNotificationPrompt = false
    @State private var pendingWorkoutType: WorkoutType?
    @AppStorage("hasRequestedNotifications") private var hasRequestedNotifications = false
    @AppStorage("restTimerSeconds") private var restDuration: Int = 120
    @AppStorage("customExercisesJSON") private var customExercisesJSON: String = "[]"
    @AppStorage("customWorkoutTypesJSON") private var customWorkoutTypesJSON: String = "[]"
    @AppStorage("hiddenBuiltInWorkoutsJSON") private var hiddenBuiltInWorkoutsJSON: String = "[]"

    static let builtInExercises: [ExerciseInfo] = [
        ExerciseInfo(name: "Bench Press", categoryName: "Upper Body", defaultWeight: 135, defaultReps: 10),
        ExerciseInfo(name: "Row", categoryName: "Upper Body", defaultWeight: 100, defaultReps: 10),
        ExerciseInfo(name: "Shoulder Press", categoryName: "Upper Body", defaultWeight: 80, defaultReps: 10),
        ExerciseInfo(name: "Lat Pulldown", categoryName: "Upper Body", defaultWeight: 120, defaultReps: 10),
        ExerciseInfo(name: "Bicep Curls", categoryName: "Upper Body", defaultWeight: 25, defaultReps: 12),
        ExerciseInfo(name: "Tricep Curls", categoryName: "Upper Body", defaultWeight: 25, defaultReps: 12),
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

    var hiddenBuiltInWorkouts: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(hiddenBuiltInWorkoutsJSON.utf8))) ?? []
    }

    var allWorkoutTypes: [WorkoutType] {
        let visibleBuiltIn = WorkoutType.builtIn.filter { !hiddenBuiltInWorkouts.contains($0.name) }
        return visibleBuiltIn + customWorkoutTypes
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

    func removeWorkoutType(_ name: String) {
        if WorkoutType.builtIn.contains(where: { $0.name == name }) {
            var hidden = hiddenBuiltInWorkouts
            if !hidden.contains(name) {
                hidden.append(name)
            }
            if let data = try? JSONEncoder().encode(hidden) {
                hiddenBuiltInWorkoutsJSON = String(data: data, encoding: .utf8) ?? "[]"
            }
        } else {
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
    }

    private func setsForEntry(_ entry: GymEntry) -> [WorkoutSet] {
        if !entry.workoutID.isEmpty {
            return allSets.filter { $0.workoutID == entry.workoutID }
        }
        return allSets.filter { $0.date == entry.date }
    }

    private func buildDetailInfo(for workout: (date: Date, workoutType: WorkoutType, exerciseCount: Int, duration: Int, workoutID: String)) -> WorkoutDetailInfo {
        let entry = gymEntries.first { e in
            !e.workoutID.isEmpty ? e.workoutID == workout.workoutID : e.date == workout.date
        }
        let sets: [WorkoutSet]
        if let entry, !entry.workoutID.isEmpty {
            sets = allSets.filter { $0.workoutID == entry.workoutID }
        } else {
            sets = allSets.filter { $0.date == workout.date }
        }
        let grouped = Dictionary(grouping: sets) { $0.exerciseName }
        let sortedNames = grouped.keys.sorted()
        let blocks = sortedNames.map { name in
            let exerciseSets = grouped[name]!.sorted { $0.setNumber < $1.setNumber }
            let journeySets = exerciseSets.enumerated().map { idx, ws in
                JourneySetInfo(
                    weight: formatWeight(ws.weight),
                    reps: "\(ws.reps)",
                    setNumber: idx + 1,
                    completionOrder: idx
                )
            }
            return JourneyBlock(exerciseName: name, sets: journeySets)
        }
        return WorkoutDetailInfo(
            id: workout.workoutID,
            date: workout.date,
            workoutType: workout.workoutType,
            duration: workout.duration,
            journeyData: blocks
        )
    }

    private var recentWorkouts: [(date: Date, workoutType: WorkoutType, exerciseCount: Int, duration: Int, workoutID: String)] {
        return gymEntries.prefix(20).compactMap { entry in
            let sets = setsForEntry(entry)
            guard !sets.isEmpty else { return nil }
            let id = entry.workoutID.isEmpty ? "\(entry.date.timeIntervalSinceReferenceDate)" : entry.workoutID
            let exerciseNames = Set(sets.map(\.exerciseName))
            let matchedType = allWorkoutTypes.first { type in
                let typeExercises = allExercises.filter { $0.categoryName == type.name }
                return typeExercises.contains { exerciseNames.contains($0.name) }
            } ?? WorkoutType(name: "Workout", icon: "dumbbell.fill", isBuiltIn: false)
            return (entry.date, matchedType, exerciseNames.count, entry.duration, id)
        }
    }

    private var groupedByDay: [(day: Date, workouts: [(date: Date, workoutType: WorkoutType, exerciseCount: Int, duration: Int, workoutID: String)])] {
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
            let entry = gymEntries.first { e in
                !e.workoutID.isEmpty ? e.workoutID == workout.workoutID : e.date == workout.date
            }
            let setsToDelete: [WorkoutSet]
            if let entry, !entry.workoutID.isEmpty {
                setsToDelete = allSets.filter { $0.workoutID == entry.workoutID }
            } else {
                setsToDelete = allSets.filter { $0.date == workout.date }
            }
            for set in setsToDelete { modelContext.delete(set) }
            if let entry { modelContext.delete(entry) }
        }
        try? modelContext.save()
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if recentWorkouts.isEmpty {
                    ContentUnavailableView {
                        Label("No Workouts Yet", systemImage: "dumbbell.fill")
                    } description: {
                        Button {
                            showingCategoryPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Start a new workout")
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                        }
                    }
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section {
                                ForEach(group.workouts, id: \.workoutID) { workout in
                                    Button {
                                        detailWorkout = buildDetailInfo(for: workout)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: workout.workoutType.icon)
                                                .font(.title3)
                                                .foregroundStyle(AppColors.accent)
                                                .frame(width: 32)
                                            Text(workout.workoutType.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(Color(.label))
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
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            if let index = recentWorkouts.firstIndex(where: { $0.workoutID == workout.workoutID }) {
                                                deleteWorkouts(at: IndexSet(integer: index))
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            editWorkout = EditWorkoutInfo(date: workout.date, workoutType: workout.workoutType, workoutID: workout.workoutID)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(AppColors.accent)
                                    }
                                }
                            } header: {
                                Text(smartDateLabel(group.day))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

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
                .padding(.vertical, 12)
                .background(.bar)
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
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
                        if !hasRequestedNotifications {
                            pendingWorkoutType = type
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingNotificationPrompt = true
                            }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                activeType = type
                            }
                        }
                    },
                    onAddCustom: { type, newExercises in
                        addCustomWorkoutType(type)
                        for exercise in newExercises {
                            addCustomExercise(exercise)
                        }
                    },
                    onDelete: { type in
                        removeWorkoutType(type.name)
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
                    editDate: info.date,
                    editWorkoutID: info.workoutID
                )
                .background(Color(.systemBackground))
            }
            .fullScreenCover(item: $detailWorkout) { detail in
                WorkoutJourneyView(
                    workoutType: detail.workoutType,
                    journeyData: detail.journeyData,
                    duration: detail.duration,
                    restRecords: [:],
                    workoutDate: detail.date,
                    onEdit: {
                        detailWorkout = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            editWorkout = EditWorkoutInfo(date: detail.date, workoutType: detail.workoutType, workoutID: detail.id)
                        }
                    },
                    onDone: { detailWorkout = nil }
                )
                .background(Color(.systemBackground))
            }
            .overlay {
                if showingNotificationPrompt {
                    NotificationPromptOverlay(
                        restDuration: restDuration,
                        onAllow: {
                            showingNotificationPrompt = false
                            hasRequestedNotifications = true
                            Task {
                                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                if let type = pendingWorkoutType {
                                    activeType = type
                                    pendingWorkoutType = nil
                                }
                            }
                        },
                        onSkip: {
                            showingNotificationPrompt = false
                            hasRequestedNotifications = true
                            if let type = pendingWorkoutType {
                                activeType = type
                                pendingWorkoutType = nil
                            }
                        }
                    )
                }
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
                    onRemoveWorkoutType: { removeWorkoutType($0) }
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
    var onAddCustom: ((WorkoutType, [ExerciseInfo]) -> Void)?
    var onDelete: ((WorkoutType) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateCustom = false
    @State private var isEditing = false
    @State private var deleteTarget: WorkoutType?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(workoutTypes) { type in
                        let exercises = exercisesForType(type)
                        HStack(spacing: 0) {
                            if isEditing {
                                Button {
                                    deleteTarget = type
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                }
                                .padding(.trailing, 12)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }

                            Button {
                                if !isEditing {
                                    onSelect(type)
                                }
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
                                                .foregroundStyle(Color(.label))
                                            Text("\(exercises.count) exercises")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if !isEditing {
                                            Image(systemName: "chevron.right")
                                                .font(.subheadline)
                                                .foregroundStyle(.tertiary)
                                        }
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }
                    }

                    if onAddCustom != nil && !isEditing {
                        Button {
                            showingCreateCustom = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppColors.accent)
                                    .frame(width: 36)
                                Text("Custom")
                                    .font(.headline)
                                    .foregroundStyle(Color(.label))
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 14))
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.25)) { isEditing.toggle() }
                    }
                }
            }
            .alert("Delete Workout?", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        withAnimation { onDelete?(target) }
                        deleteTarget = nil
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                if let target = deleteTarget {
                    Text("This will permanently delete \"\(target.name)\" and all its exercises.")
                }
            }
            .fullScreenCover(isPresented: $showingCreateCustom) {
                CreateCustomWorkoutSheet { type, exercises in
                    onAddCustom?(type, exercises)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Create Custom Workout

struct DraftExercise: Identifiable {
    let id = UUID()
    var name: String
    var sets: [DraftSet]
}

struct DraftSet: Identifiable {
    let id = UUID()
    var weight: String
    var reps: String
}

struct CreateCustomWorkoutSheet: View {
    let onSave: (WorkoutType, [ExerciseInfo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = 1

    @State private var name = ""
    @State private var selectedIcon = "figure.strengthtraining.traditional"
    @State private var defaultSets = 3
    @State private var defaultReps = 10
    @State private var draftExercises: [DraftExercise] = []
    @State private var showingSaveConfirm = false
    @FocusState private var focusedField: Bool

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
            if step == 1 {
                setupStep
            } else {
                editorStep
            }
        }
    }

    // MARK: - Step 1: Setup

    private var setupStep: some View {
        Form {
            Section {
                TextField("Workout name", text: $name)
                    .focused($focusedField)
            }

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

            Section {
                Stepper(value: $defaultSets, in: 1...10) {
                    HStack {
                        Text("Sets per exercise")
                        Spacer()
                        Text("\(defaultSets)")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.accent)
                    }
                }
                Stepper(value: $defaultReps, in: 1...50) {
                    HStack {
                        Text("Reps per set")
                        Spacer()
                        Text("\(defaultReps)")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.accent)
                    }
                }
            } header: {
                Text("Defaults")
            } footer: {
                Text("You can modify these for each exercise in the next step.")
            }
        }
        .navigationTitle("New Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") {
                    buildDraftExercises()
                    withAnimation { step = 2 }
                }
                .fontWeight(.semibold)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { focusedField = true }
    }

    // MARK: - Step 2: Editor

    private var editorStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(draftExercises.enumerated()), id: \.element.id) { index, exercise in
                        draftExerciseCard(index: index)
                    }

                    Button {
                        let repsStr = "\(defaultReps)"
                        let newSets = (0..<defaultSets).map { _ in DraftSet(weight: "", reps: repsStr) }
                        withAnimation {
                            draftExercises.append(DraftExercise(
                                name: "",
                                sets: newSets
                            ))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Exercise")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                                .foregroundStyle(AppColors.accent.opacity(0.3))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            Button {
                showingSaveConfirm = true
            } label: {
                HStack {
                    Text("Save Workout")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
            .disabled(!hasValidExercises)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    withAnimation { step = 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    showingSaveConfirm = true
                }
                .fontWeight(.semibold)
                .disabled(!hasValidExercises)
            }
        }
        .overlay {
            if showingSaveConfirm {
                WorkoutConfirmOverlay(
                    title: "Done editing?",
                    message: "You can always edit this workout later from settings.",
                    buttons: [
                        .init(label: "Save Workout", style: .primary) {
                            showingSaveConfirm = false
                            saveWorkout()
                        },
                        .init(label: "Keep Editing", style: .cancel) {
                            showingSaveConfirm = false
                        },
                    ]
                )
            }
        }
    }

    // MARK: - Draft Exercise Card

    @ViewBuilder
    private func draftExerciseCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Exercise name", text: $draftExercises[index].name)
                    .font(.title3.weight(.semibold))
                Spacer()

                HStack(spacing: 12) {
                    if index > 0 {
                        Button { moveDraft(at: index, direction: -1) } label: {
                            Image(systemName: "arrow.up")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if index < draftExercises.count - 1 {
                        Button { moveDraft(at: index, direction: 1) } label: {
                            Image(systemName: "arrow.down")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if draftExercises.count > 1 {
                        Button { deleteDraft(at: index) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
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
                    .frame(width: 8)
                Text("REPS")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(Array(draftExercises[index].sets.enumerated()), id: \.element.id) { setIdx, _ in
                    HStack(spacing: 8) {
                        Text("\(setIdx + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .frame(width: 24)

                        TextField("0", text: $draftExercises[index].sets[setIdx].weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.body.weight(.bold))
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.2), lineWidth: 1))

                        Text("×")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)

                        TextField("0", text: $draftExercises[index].sets[setIdx].reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.body.weight(.bold))
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.2), lineWidth: 1))
                    }
                }
            }

            HStack(spacing: 16) {
                Button {
                    let lastSet = draftExercises[index].sets.last
                    draftExercises[index].sets.append(DraftSet(
                        weight: lastSet?.weight ?? "",
                        reps: lastSet?.reps ?? "\(defaultReps)"
                    ))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Set")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.accent)
                }

                if draftExercises[index].sets.count > 1 {
                    Button {
                        draftExercises[index].sets.removeLast()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                            Text("Remove Set")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.fill.quinary)
        }
    }

    // MARK: - Helpers

    private var hasValidExercises: Bool {
        draftExercises.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func buildDraftExercises() {
        let repsStr = "\(defaultReps)"
        draftExercises = [
            DraftExercise(name: "", sets: (0..<defaultSets).map { _ in DraftSet(weight: "", reps: repsStr) }),
            DraftExercise(name: "", sets: (0..<defaultSets).map { _ in DraftSet(weight: "", reps: repsStr) }),
        ]
    }

    private func moveDraft(at index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < draftExercises.count else { return }
        withAnimation { draftExercises.swapAt(index, newIndex) }
    }

    private func deleteDraft(at index: Int) {
        guard draftExercises.count > 1 else { return }
        _ = withAnimation { draftExercises.remove(at: index) }
    }

    private func saveWorkout() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let type = WorkoutType(name: trimmedName, icon: selectedIcon, isBuiltIn: false)

        let exercises = draftExercises.compactMap { draft -> ExerciseInfo? in
            let exerciseName = draft.name.trimmingCharacters(in: .whitespaces)
            guard !exerciseName.isEmpty else { return nil }
            let firstWeight = Double(draft.sets.first?.weight ?? "") ?? 50
            let firstReps = Int(draft.sets.first?.reps ?? "") ?? defaultReps
            return ExerciseInfo(
                name: exerciseName,
                categoryName: trimmedName,
                defaultWeight: firstWeight,
                defaultReps: firstReps
            )
        }

        onSave(type, exercises)
        dismiss()
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
    @Binding var restDuration: Int
    var editDate: Date?
    var editWorkoutID: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSet.date, order: .reverse) private var allSets: [WorkoutSet]

    @State private var activeExercises: [ExerciseInfo]
    @State private var sessionSets: [String: [SetEntry]] = [:]
    @State private var isPreviewMode: Bool
    @State private var showingDiscardConfirm = false
    @State private var showingFinishConfirm = false
    @State private var showJourneySummary = false
    @State private var journeyData: [JourneyBlock] = []
    @State private var nextCompletionOrder: Int = 0
    @State private var isEditing = false
    @State private var timerRemaining: Int = 0
    @State private var timerActive = false
    @State private var timerTask: Task<Void, Never>?
    @State private var elapsedSeconds: Int = 0
    @State private var sessionTimerTask: Task<Void, Never>?
    @State private var currentActivity: Activity<RestTimerAttributes>?
    @State private var restRecords: [Int: Int] = [:]
    @State private var restStartedAfterOrder: Int = -1
    @State private var restStartTime: Date?

    private var isEditMode: Bool { editDate != nil }

    init(workoutType: WorkoutType, exercises: [ExerciseInfo], restDuration: Binding<Int>, editDate: Date? = nil, editWorkoutID: String? = nil) {
        self.workoutType = workoutType
        self._restDuration = restDuration
        self.editDate = editDate
        self.editWorkoutID = editWorkoutID
        self._activeExercises = State(initialValue: exercises)
        self._isPreviewMode = State(initialValue: editDate == nil)
    }

    private var editDateTitle: String {
        guard let editDate else { return workoutType.name }
        return editDate.formatted(.dateTime.month().day())
    }

    private var completedExerciseCount: Int {
        activeExercises.filter { exercise in
            let sets = sessionSets[exercise.name] ?? []
            return !sets.isEmpty && sets.allSatisfy { $0.completed }
        }.count
    }

    private var totalSets: Int {
        activeExercises.reduce(0) { $0 + (sessionSets[$1.name]?.count ?? 0) }
    }

    private var completedSets: Int {
        activeExercises.reduce(0) { $0 + (sessionSets[$1.name]?.filter(\.completed).count ?? 0) }
    }

    private var progressFraction: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }

    var body: some View {
        if showJourneySummary {
            WorkoutJourneyView(
                workoutType: workoutType,
                journeyData: journeyData,
                duration: elapsedSeconds,
                restRecords: restRecords,
                onDone: { dismiss() }
            )
        } else {
            workoutContent
        }
    }

    private var workoutContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isPreviewMode {
                    progressHeader
                }

                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(Array(activeExercises.enumerated()), id: \.element.id) { index, exercise in
                            exerciseCard(exercise, number: index + 1, exerciseIndex: index)
                        }
                    }
                    .padding()
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)

                if isPreviewMode {
                    startWorkoutBar
                } else {
                    restTimerBar
                }
            }
            .navigationTitle(isPreviewMode ? workoutType.name : (isEditMode ? editDateTitle : workoutType.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isPreviewMode {
                            dismiss()
                        } else if !isEditMode && hasAnyInput {
                            showingDiscardConfirm = true
                        } else {
                            stopTimer()
                            endLiveActivity()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isPreviewMode {
                        HStack(spacing: 12) {
                            Button {
                                withAnimation { isEditing.toggle() }
                            } label: {
                                Image(systemName: isEditing ? "checkmark" : "pencil")
                                    .font(.subheadline)
                            }

                            Button(isEditMode ? "Save" : "Finish") {
                                if isEditMode {
                                    stopTimer()
                                    saveAndDismiss()
                                } else {
                                    showingFinishConfirm = true
                                }
                            }
                            .fontWeight(.semibold)
                            .disabled(!hasAnyInput)
                        }
                    }
                }
            }
            .overlay {
                if showingDiscardConfirm {
                    WorkoutConfirmOverlay(
                        title: "Discard workout?",
                        buttons: [
                            .init(label: "Save & Finish", style: .primary) {
                                showingDiscardConfirm = false
                                stopTimer(); endLiveActivity(); saveAndDismiss()
                            },
                            .init(label: "Discard", style: .destructive) {
                                showingDiscardConfirm = false
                                stopTimer(); endLiveActivity(); dismiss()
                            },
                            .init(label: "Cancel", style: .cancel) {
                                showingDiscardConfirm = false
                            },
                        ]
                    )
                }
                if showingFinishConfirm {
                    WorkoutConfirmOverlay(
                        title: "Finish workout?",
                        buttons: [
                            .init(label: "Finish", style: .primary) {
                                showingFinishConfirm = false
                                stopTimer()
                                endLiveActivity()
                                saveWorkout()
                                journeyData = captureJourneyData()
                                showJourneySummary = true
                            },
                            .init(label: "Cancel", style: .cancel) {
                                showingFinishConfirm = false
                            },
                        ]
                    )
                }
            }
            .onAppear {
                prepopulate()
                if isEditMode {
                    isEditing = true
                } else if !isPreviewMode {
                    startSessionTimer()
                }
            }
            .onDisappear {
                sessionTimerTask?.cancel()
            }
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
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
    }

    // MARK: - Start Workout Bar (Preview Mode)

    private var startWorkoutBar: some View {
        Button {
            withAnimation {
                isPreviewMode = false
            }
            startSessionTimer()
        } label: {
            HStack {
                Text("Ready? Start Workout")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.right")
                    .fontWeight(.semibold)
            }
            .font(.body)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
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
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                            Text("Rest \(formatTimer(restDuration))")
                        }
                        .fontWeight(.semibold)
                        Spacer()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 14))
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
    private func exerciseCard(_ exercise: ExerciseInfo, number: Int, exerciseIndex: Int) -> some View {
        let sets = sessionSets[exercise.name] ?? []
        let completedCount = sets.filter(\.completed).count

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                Spacer()

                if isPreviewMode || isEditing {
                    HStack(spacing: 12) {
                        Button {
                            moveExercise(at: exerciseIndex, direction: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(exerciseIndex > 0 ? Color(.label) : Color(.quaternaryLabel))
                        }
                        .disabled(exerciseIndex == 0)

                        Button {
                            moveExercise(at: exerciseIndex, direction: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(exerciseIndex < activeExercises.count - 1 ? Color(.label) : Color(.quaternaryLabel))
                        }
                        .disabled(exerciseIndex == activeExercises.count - 1)

                        Button {
                            deleteExercise(at: exerciseIndex)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Text("\(completedCount)/\(sets.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                if !isPreviewMode {
                    Color.clear
                        .frame(width: 36)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, setEntry in
                    setRow(exercise: exercise.name, index: index, setEntry: setEntry)
                }
            }

            if isPreviewMode || isEditing {
                HStack(spacing: 16) {
                    Button {
                        addSet(for: exercise.name, exercise: exercise)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Set")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.accent)
                    }

                    if sets.count > 1 {
                        Button {
                            removeLastSet(for: exercise.name)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "minus.circle.fill")
                                Text("Remove Set")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.top, 10)
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

            if !isPreviewMode {
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
            let daySets: [WorkoutSet]
            if let editWorkoutID, !editWorkoutID.isEmpty {
                daySets = allSets.filter { $0.workoutID == editWorkoutID }
            } else {
                daySets = allSets.filter { $0.date == editDate }
            }
            let grouped = Dictionary(grouping: daySets) { $0.exerciseName }
            for exercise in activeExercises {
                if let sets = grouped[exercise.name]?.sorted(by: { $0.setNumber < $1.setNumber }), !sets.isEmpty {
                    sessionSets[exercise.name] = sets.map { set in
                        SetEntry(weight: formatWeight(set.weight), reps: "\(set.reps)", completed: true)
                    }
                } else {
                    sessionSets[exercise.name] = []
                }
            }
        } else {
            for exercise in activeExercises {
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
        guard let lastSet = pastSets.first else { return [] }
        let matching: [WorkoutSet]
        if !lastSet.workoutID.isEmpty {
            matching = pastSets.filter { $0.workoutID == lastSet.workoutID }
        } else {
            matching = pastSets.filter { $0.date == lastSet.date }
        }
        return matching.sorted { $0.setNumber < $1.setNumber }
    }

    private func markSetDone(exercise: String, index: Int) {
        guard sessionSets[exercise] != nil && index < sessionSets[exercise]!.count else { return }
        sessionSets[exercise]![index].completed.toggle()
        if sessionSets[exercise]![index].completed {
            sessionSets[exercise]![index].completionOrder = nextCompletionOrder
            nextCompletionOrder += 1
        } else {
            sessionSets[exercise]![index].completionOrder = -1
        }
    }

    // MARK: - Exercise Management

    private func moveExercise(at index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < activeExercises.count else { return }
        withAnimation {
            activeExercises.swapAt(index, newIndex)
        }
    }

    private func deleteExercise(at index: Int) {
        guard activeExercises.count > 1 else { return }
        let name = activeExercises[index].name
        withAnimation {
            activeExercises.remove(at: index)
            sessionSets.removeValue(forKey: name)
        }
    }

    private func addSet(for exerciseName: String, exercise: ExerciseInfo) {
        let lastSet = sessionSets[exerciseName]?.last
        let newSet = SetEntry(
            weight: lastSet?.weight ?? formatWeight(exercise.defaultWeight),
            reps: lastSet?.reps ?? "\(exercise.defaultReps)"
        )
        sessionSets[exerciseName, default: []].append(newSet)
    }

    private func removeLastSet(for exerciseName: String) {
        guard sessionSets[exerciseName] != nil && sessionSets[exerciseName]!.count > 1 else { return }
        sessionSets[exerciseName]!.removeLast()
    }

    // MARK: - Timer

    private func startRestTimer() {
        stopTimer()
        timerRemaining = restDuration
        timerActive = true
        restStartTime = Date.now
        restStartedAfterOrder = max(0, nextCompletionOrder - 1)
        startLiveActivity()
        scheduleRestNotification()
        timerTask = Task {
            while timerRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    timerRemaining -= 1
                }
            }
            if !Task.isCancelled {
                if let start = restStartTime {
                    restRecords[restStartedAfterOrder] = Int(Date.now.timeIntervalSince(start))
                    restStartTime = nil
                }
                endLiveActivity()
                timerActive = false
            }
        }
    }

    private func skipTimer() {
        if let start = restStartTime {
            restRecords[restStartedAfterOrder] = Int(Date.now.timeIntervalSince(start))
            restStartTime = nil
        }
        stopTimer()
        cancelRestNotification()
        endLiveActivity()
        withAnimation {
            timerRemaining = 0
            timerActive = false
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        cancelRestNotification()
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

    // MARK: - Rest Notification

    private func scheduleRestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Rest Complete"
        content.body = "Time for your next set!"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(restDuration), repeats: false)
        let request = UNNotificationRequest(identifier: "restTimer", content: content, trigger: trigger)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private func cancelRestNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["restTimer"])
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = RestTimerAttributes(workoutName: workoutType.name)
        let endTime = Date.now.addingTimeInterval(TimeInterval(restDuration))
        let state = RestTimerAttributes.ContentState(endTime: endTime, totalDuration: restDuration)
        let content = ActivityContent(state: state, staleDate: endTime)

        do {
            currentActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            // Live Activity not available
        }
    }

    private func endLiveActivity() {
        guard let activity = currentActivity else { return }
        let state = RestTimerAttributes.ContentState(endTime: .now, totalDuration: 0)
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    // MARK: - Format

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

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }

    // MARK: - Save

    private func captureJourneyData() -> [JourneyBlock] {
        struct OrderedSet {
            let exerciseName: String
            let weight: String
            let reps: String
            let setNumber: Int
            let order: Int
        }

        var orderedSets: [OrderedSet] = []
        for exercise in activeExercises {
            let sets = sessionSets[exercise.name] ?? []
            for (setIdx, entry) in sets.enumerated() {
                guard entry.completed, !entry.weight.isEmpty, !entry.reps.isEmpty,
                      entry.completionOrder >= 0 else { continue }
                orderedSets.append(OrderedSet(
                    exerciseName: exercise.name,
                    weight: entry.weight,
                    reps: entry.reps,
                    setNumber: setIdx + 1,
                    order: entry.completionOrder
                ))
            }
        }

        orderedSets.sort { $0.order < $1.order }

        var blocks: [JourneyBlock] = []
        var currentName = ""
        var currentSets: [JourneySetInfo] = []

        for set in orderedSets {
            if set.exerciseName != currentName {
                if !currentSets.isEmpty {
                    blocks.append(JourneyBlock(exerciseName: currentName, sets: currentSets))
                }
                currentName = set.exerciseName
                currentSets = []
            }
            currentSets.append(JourneySetInfo(weight: set.weight, reps: set.reps, setNumber: set.setNumber, completionOrder: set.order))
        }
        if !currentSets.isEmpty {
            blocks.append(JourneyBlock(exerciseName: currentName, sets: currentSets))
        }

        return blocks
    }

    private func saveWorkout() {
        sessionTimerTask?.cancel()

        let saveDate = Date()
        let workoutID = UUID().uuidString
        for exercise in activeExercises {
            let sets = sessionSets[exercise.name] ?? []
            for (index, entry) in sets.enumerated() {
                guard entry.completed,
                      let weight = Double(entry.weight), let reps = Int(entry.reps),
                      weight > 0, reps > 0 else { continue }
                let workoutSet = WorkoutSet(
                    exerciseName: exercise.name,
                    weight: weight,
                    reps: reps,
                    setNumber: index,
                    date: saveDate,
                    workoutID: workoutID
                )
                modelContext.insert(workoutSet)
            }
        }

        let gymEntry = GymEntry(date: saveDate, duration: elapsedSeconds, workoutID: workoutID)
        modelContext.insert(gymEntry)
        try? modelContext.save()
    }

    private func saveAndDismiss() {
        sessionTimerTask?.cancel()
        endLiveActivity()

        if let editDate {
            let oldSets: [WorkoutSet]
            if let editWorkoutID, !editWorkoutID.isEmpty {
                oldSets = allSets.filter { $0.workoutID == editWorkoutID }
            } else {
                oldSets = allSets.filter { $0.date == editDate }
            }
            for old in oldSets {
                modelContext.delete(old)
            }
        }

        let saveDate = editDate ?? Date()
        let workoutID = editWorkoutID ?? UUID().uuidString
        var savedAnySet = false
        for exercise in activeExercises {
            let sets = sessionSets[exercise.name] ?? []
            for (index, entry) in sets.enumerated() {
                guard entry.completed,
                      let weight = Double(entry.weight), let reps = Int(entry.reps),
                      weight > 0, reps > 0 else { continue }
                let workoutSet = WorkoutSet(
                    exerciseName: exercise.name,
                    weight: weight,
                    reps: reps,
                    setNumber: index,
                    date: saveDate,
                    workoutID: workoutID
                )
                modelContext.insert(workoutSet)
                savedAnySet = true
            }
        }

        if !isEditMode {
            let gymEntry = GymEntry(date: saveDate, duration: elapsedSeconds, workoutID: workoutID)
            modelContext.insert(gymEntry)
        } else if !savedAnySet, let editDate {
            let descriptor = FetchDescriptor<GymEntry>()
            if let entries = try? modelContext.fetch(descriptor) {
                for entry in entries {
                    if let editWorkoutID, !editWorkoutID.isEmpty {
                        if entry.workoutID == editWorkoutID { modelContext.delete(entry) }
                    } else if entry.date == editDate {
                        modelContext.delete(entry)
                    }
                }
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Workout Journey View

struct WorkoutJourneyView: View {
    let workoutType: WorkoutType
    let journeyData: [JourneyBlock]
    let duration: Int
    let restRecords: [Int: Int]
    var workoutDate: Date? = nil
    var onEdit: (() -> Void)? = nil
    let onDone: () -> Void

    private var isHistoryMode: Bool { workoutDate != nil }

    private var totalSets: Int {
        journeyData.reduce(0) { $0 + $1.sets.count }
    }

    private var exerciseCount: Int {
        Set(journeyData.map(\.exerciseName)).count
    }

    private var totalVolume: String {
        let vol = journeyData.reduce(0) { total, block in
            total + block.sets.reduce(0) { $0 + Int((Double($1.weight) ?? 0) * Double(Int($1.reps) ?? 0)) }
        }
        if vol >= 1000 {
            return String(format: "%.1fk", Double(vol) / 1000)
        }
        return "\(vol)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Image(systemName: isHistoryMode ? workoutType.icon : "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(isHistoryMode ? AppColors.accent : AppColors.success)

                        Text(isHistoryMode ? workoutType.name : "Workout Complete")
                            .font(.title2.weight(.bold))

                        if let workoutDate {
                            Text(workoutDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(workoutType.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)

                    HStack(spacing: 0) {
                        statItem(value: formatDuration(duration), label: "Duration", icon: "timer")
                        Divider().frame(height: 32)
                        statItem(value: "\(exerciseCount)", label: "Exercises", icon: "dumbbell.fill")
                        Divider().frame(height: 32)
                        statItem(value: "\(totalSets)", label: "Sets", icon: "checkmark.circle")
                        Divider().frame(height: 32)
                        statItem(value: "\(totalVolume)", label: "Volume", icon: "scalemass")
                    }
                    .padding(.vertical, 16)
                    .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 24)

                    VStack(spacing: 0) {
                        ForEach(Array(journeyData.enumerated()), id: \.element.id) { blockIdx, block in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: "dumbbell.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.accent)
                                    Text(block.exerciseName)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(block.sets.count) sets")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.fill.quaternary, in: Capsule())
                                }
                                .padding(.bottom, 12)

                                ForEach(Array(block.sets.enumerated()), id: \.element.id) { setIdx, set in
                                    HStack {
                                        Text("Set \(set.setNumber)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 48, alignment: .leading)

                                        Text("\(set.weight) lbs")
                                            .font(.body.weight(.semibold).monospacedDigit())

                                        Text("×")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)

                                        Text("\(set.reps) reps")
                                            .font(.body.weight(.semibold).monospacedDigit())

                                        Spacer()

                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(AppColors.success)
                                    }
                                    .padding(.vertical, 8)

                                    if setIdx < block.sets.count - 1 {
                                        if let restDur = restRecords[set.completionOrder] {
                                            HStack(spacing: 6) {
                                                Rectangle()
                                                    .fill(Color(.separator).opacity(0.3))
                                                    .frame(height: 1)
                                                HStack(spacing: 4) {
                                                    Image(systemName: "timer")
                                                    Text(formatTimer(restDur))
                                                }
                                                .font(.caption2)
                                                .foregroundStyle(Color(.quaternaryLabel))
                                                Rectangle()
                                                    .fill(Color(.separator).opacity(0.3))
                                                    .frame(height: 1)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)

                            if blockIdx < journeyData.count - 1,
                               let lastOrder = block.sets.last?.completionOrder,
                               let restDur = restRecords[lastOrder] {
                                HStack(spacing: 8) {
                                    Image(systemName: "timer")
                                        .font(.caption)
                                    Text("Rest \(formatTimer(restDur))")
                                        .font(.caption)
                                }
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle(isHistoryMode ? "Summary" : "Journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onEdit {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit") { onEdit() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppColors.accent)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTimer(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Confirm Overlay

struct WorkoutConfirmButton {
    enum Style { case primary, destructive, cancel }
    let label: String
    let style: Style
    let action: () -> Void
}

struct WorkoutConfirmOverlay: View {
    let title: String
    var message: String? = nil
    let buttons: [WorkoutConfirmButton]

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    buttons.first(where: { $0.style == .cancel })?.action()
                }

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                .padding(.horizontal, 20)

                Divider()

                ForEach(Array(buttons.enumerated()), id: \.offset) { idx, button in
                    Button {
                        button.action()
                    } label: {
                        Text(button.label)
                            .font(.body.weight(button.style == .cancel ? .regular : .semibold))
                            .foregroundStyle(button.style == .destructive ? .red : (button.style == .primary ? AppColors.accent : .primary))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }

                    if idx < buttons.count - 1 {
                        Divider()
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 48)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.easeOut(duration: 0.15), value: true)
    }
}

// MARK: - Notification Prompt

struct NotificationPromptOverlay: View {
    let restDuration: Int
    let onAllow: () -> Void
    let onSkip: () -> Void

    private var formattedDuration: String {
        let m = restDuration / 60
        let s = restDuration % 60
        if s == 0 { return "\(m) minute\(m == 1 ? "" : "s")" }
        return "\(m)m \(s)s"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.accent)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Stay on Track")
                        .font(.title3.weight(.bold))
                    Text("We'll notify you when your \(formattedDuration) rest between sets is over so you can focus on your workout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Button {
                        onAllow()
                    } label: {
                        Text("Enable Notifications")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSkip()
                    } label: {
                        Text("Not Now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 40)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.easeOut(duration: 0.2), value: true)
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    WorkoutView()
        .modelContainer(for: WorkoutSet.self, inMemory: true)
}
