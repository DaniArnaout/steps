import SwiftUI
import SwiftData
import WidgetKit

enum AppColors {
    static let accent = Color(red: 0.20, green: 0.68, blue: 0.50)
    static let success = Color(red: 0.20, green: 0.68, blue: 0.50)
    static let warning = Color(red: 0.95, green: 0.58, blue: 0.30)
    static let danger = Color(red: 0.88, green: 0.30, blue: 0.35)
    static let neutral = Color(red: 0.50, green: 0.62, blue: 0.78)
}

@Observable
final class GoalStore {
    private static let appGroupID = "group.com.daniarnaout.SpotMe"

    var stepGoal: Int
    var calorieGoal: Int
    var proteinGoal: Int
    var gymGoal: Int

    var requireSteps: Bool
    var requireCalories: Bool
    var requireProtein: Bool
    var requireGym: Bool

    init() {
        let d = UserDefaults.standard
        self.stepGoal = d.object(forKey: "goalSteps") as? Int ?? 7000
        self.calorieGoal = d.object(forKey: "goalCalories") as? Int ?? 2000
        self.proteinGoal = d.object(forKey: "goalProtein") as? Int ?? 100
        self.gymGoal = d.object(forKey: "goalGym") as? Int ?? 3
        self.requireSteps = d.object(forKey: "requireSteps") as? Bool ?? true
        self.requireCalories = d.object(forKey: "requireCalories") as? Bool ?? true
        self.requireProtein = d.object(forKey: "requireProtein") as? Bool ?? true
        self.requireGym = d.object(forKey: "requireGym") as? Bool ?? false
    }

    func save() {
        let d = UserDefaults.standard
        d.set(stepGoal, forKey: "goalSteps")
        d.set(calorieGoal, forKey: "goalCalories")
        d.set(proteinGoal, forKey: "goalProtein")
        d.set(gymGoal, forKey: "goalGym")
        d.set(requireSteps, forKey: "requireSteps")
        d.set(requireCalories, forKey: "requireCalories")
        d.set(requireProtein, forKey: "requireProtein")
        d.set(requireGym, forKey: "requireGym")
        if let shared = UserDefaults(suiteName: Self.appGroupID) {
            shared.set(stepGoal, forKey: "goalSteps")
            shared.set(calorieGoal, forKey: "goalCalories")
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

struct LazyView<Content: View>: View {
    let build: () -> Content
    init(@ViewBuilder _ build: @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

struct ContentView: View {
    static let appGroupID = "group.com.daniarnaout.SpotMe"

    @State private var goalStore = GoalStore()
    @State private var stepCounter = StepCounter()
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodEntry.date, order: .reverse) private var allEntries: [FoodEntry]
    @Query(sort: \GymEntry.date, order: .reverse) private var allGymEntries: [GymEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var allWeightEntries: [WeightEntry]

    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAddSheet = false
    @State private var showingMealDetails = false
    @State private var showingSettings = false
    @State private var showingWeightLog = false
    @State private var showingContact = false
    @State private var selectedDate: Date = Date()
    @State private var lastActiveDate: Date = Date()
    @AppStorage("stepsEnabled") private var stepsEnabled = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var navigationTitle: String {
        if isToday { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Food data

    private var selectedEntries: [FoodEntry] {
        let calendar = Calendar.current
        return allEntries.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var totalCalories: Int {
        selectedEntries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Int {
        selectedEntries.reduce(0) { $0 + $1.protein }
    }

    private var remainingCalories: Int {
        max(goalStore.calorieGoal - totalCalories, 0)
    }

    private var calorieProgress: Double {
        min(Double(totalCalories) / Double(goalStore.calorieGoal), 1.0)
    }

    private var proteinProgress: Double {
        min(Double(totalProtein) / Double(goalStore.proteinGoal), 1.0)
    }

    private var calorieColor: Color {
        if totalCalories > goalStore.calorieGoal { return AppColors.danger }
        return AppColors.success
    }

    private var proteinColor: Color {
        if proteinProgress >= 1.0 { return AppColors.success }
        return AppColors.warning
    }

    private var groupedEntries: [(MealCategory, [FoodEntry])] {
        MealCategory.allCases.compactMap { category in
            let entries = selectedEntries.filter { $0.category == category }
            return entries.isEmpty ? nil : (category, entries)
        }
    }

    // MARK: - Steps data

    private var displayWeek: [DaySteps] {
        if !stepCounter.pastWeek.isEmpty { return stepCounter.pastWeek }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: today).map { DaySteps(date: $0, steps: 0) }
        }
    }

    private var selectedDaySteps: Int {
        if isToday { return stepCounter.todaySteps }
        let calendar = Calendar.current
        return stepCounter.pastWeek.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }?.steps ?? 0
    }

    private var selectedStepProgress: Double {
        min(Double(selectedDaySteps) / Double(goalStore.stepGoal), 1.0)
    }

    private var selectedStepsRemaining: Int {
        max(goalStore.stepGoal - selectedDaySteps, 0)
    }

    private var stepProgressColor: Color {
        if selectedStepProgress >= 1.0 { return AppColors.success }
        return AppColors.warning
    }

    // MARK: - Gym data

    private var weekGymCount: Int {
        let calendar = Calendar.current
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) else { return 0 }
        return allGymEntries.filter { $0.date >= sevenDaysAgo }.count
    }

    private var gymProgress: Double {
        min(Double(weekGymCount) / Double(goalStore.gymGoal), 1.0)
    }

    private var gymColor: Color {
        if gymProgress >= 1.0 { return AppColors.success }
        return AppColors.warning
    }

    private var didGymSelectedDay: Bool {
        let calendar = Calendar.current
        return allGymEntries.contains { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    // MARK: - Weight data

    private var selectedDateWeightEntry: WeightEntry? {
        let calendar = Calendar.current
        return allWeightEntries.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    // MARK: - Streak

    private var currentStreak: Int {
        var streak = 0
        for day in displayWeek.reversed() {
            if daySuccess(for: day) { streak += 1 } else { break }
        }
        return streak
    }

    // MARK: - Day success

    private func dayProgress(for day: DaySteps) -> Double {
        let calendar = Calendar.current
        let dayEntries = allEntries.filter { calendar.isDate($0.date, inSameDayAs: day.date) }
        let dayCalories = dayEntries.reduce(0) { $0 + $1.calories }
        let dayProtein = dayEntries.reduce(0) { $0 + $1.protein }
        let didGym = allGymEntries.contains { calendar.isDate($0.date, inSameDayAs: day.date) }

        var total = 0
        var met = 0
        if goalStore.requireSteps {
            total += 1
            if day.steps >= goalStore.stepGoal { met += 1 }
        }
        if goalStore.requireCalories {
            total += 1
            if dayCalories <= goalStore.calorieGoal { met += 1 }
        }
        if goalStore.requireProtein {
            total += 1
            if dayProtein >= goalStore.proteinGoal { met += 1 }
        }
        if goalStore.requireGym {
            total += 1
            if didGym { met += 1 }
        }
        guard total > 0 else { return 1.0 }
        return Double(met) / Double(total)
    }

    private func daySuccess(for day: DaySteps) -> Bool {
        dayProgress(for: day) >= 1.0
    }

    // MARK: - Body

    var body: some View {
        TabView {
            homeTab
                .tabItem { Label("Home", systemImage: "house.fill") }
            LazyView { WorkoutView() }
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
            LazyView {
                AnalyticsView(goalStore: goalStore, stepCounter: stepCounter)
            }
                .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .tint(AppColors.accent)
        .task {
            await stepCounter.requestAuthorization()
            if stepCounter.todaySteps > 0 || stepCounter.pastWeek.contains(where: { $0.steps > 0 }) {
                stepsEnabled = true
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                let calendar = Calendar.current
                if !calendar.isDate(lastActiveDate, inSameDayAs: Date()) {
                    selectedDate = Date()
                    lastActiveDate = Date()
                }
                Task {
                    await stepCounter.refresh()
                    if !stepsEnabled && (stepCounter.todaySteps > 0 || stepCounter.pastWeek.contains(where: { $0.steps > 0 })) {
                        stepsEnabled = true
                    }
                }
                syncCaloriesToWidget()
            }
        }
        .onChange(of: allEntries.count) {
            syncCaloriesToWidget()
        }
    }

    private var homeTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    weekCard
                    activityCard
                    foodCard
                    weightCard
                }
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
            .navigationTitle(navigationTitle)
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
            .sheet(isPresented: $showingAddSheet) {
                AddFoodSheet(initialDate: selectedDate)
                    .tint(Color(.label))
            }
            .sheet(isPresented: $showingSettings) {
                GoalsSettingsSheet(goalStore: goalStore, stepCounter: stepCounter)
                    .tint(Color(.label))
            }
            .sheet(isPresented: $showingWeightLog) {
                LogWeightSheet(existingEntry: selectedDateWeightEntry, date: selectedDate)
                    .tint(Color(.label))
                    .presentationDetents([.height(220)])
            }
        }
    }

    private func syncCaloriesToWidget() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        var caloriesByDay: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for entry in allEntries {
            let key = formatter.string(from: entry.date)
            caloriesByDay[key, default: 0] += entry.calories
        }
        defaults.set(caloriesByDay, forKey: "dailyCalories")
        defaults.set(goalStore.stepGoal, forKey: "goalSteps")
        defaults.set(goalStore.calorieGoal, forKey: "goalCalories")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func toggleGym() {
        let calendar = Calendar.current
        if let existing = allGymEntries.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(GymEntry(date: selectedDate))
        }
    }

    // MARK: - Week Card

    private var weekCard: some View {
        HStack(spacing: 0) {
            ForEach(displayWeek) { day in
                let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                let progress = dayProgress(for: day)
                let success = progress >= 1.0
                let isPast = !Calendar.current.isDateInToday(day.date) && day.date < Date.now
                let ringColor = success ? AppColors.success : (isPast ? AppColors.danger : AppColors.success)
                Button {
                    withAnimation {
                        selectedDate = day.date
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.weekdayLetter)
                            .font(.caption2)
                            .fontWeight(isSelected ? .bold : .regular)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        ZStack {
                            Circle()
                                .stroke(Color(.quaternarySystemFill), lineWidth: 3)
                                .frame(width: 24, height: 24)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 24, height: 24)
                            if success {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AppColors.success)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isToday && currentStreak > 0 {
                    Text("\(currentStreak)-day streak!")
                        .font(.system(size: 11, weight: .regular))
                }
                Button {
                    toggleGym()
                } label: {
                    Text(didGymSelectedDay ? "Gym Logged" : "Log Gym")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(didGymSelectedDay ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(.primary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

            HStack(spacing: 28) {
                if stepsEnabled {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(.quaternary, lineWidth: 14)
                            Circle()
                                .trim(from: 0, to: selectedStepProgress)
                                .stroke(stepProgressColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut, value: selectedStepProgress)

                            VStack(spacing: 2) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 18))
                                    .foregroundStyle(stepProgressColor)
                                Text("\(selectedDaySteps)")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText())
                                Text("steps")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 148, height: 148)
                    }
                } else {
                    Button {
                        if let url = URL(string: "x-apple-health://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.quaternary, lineWidth: 14)
                            VStack(spacing: 6) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 24))
                                    .foregroundStyle(AppColors.accent)
                                Text("Enable Steps")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .underline()
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                        .frame(width: 148, height: 148)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: gymProgress)
                            .stroke(gymColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: gymProgress)

                        VStack(spacing: 2) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(gymColor)
                            Text("\(weekGymCount)/\(goalStore.gymGoal)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("Gym")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 90, height: 90)
                }
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 28)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Food Card

    private var foodCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Food")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !selectedEntries.isEmpty {
                    Button {
                        showingMealDetails = true
                    } label: {
                        Text("\(selectedEntries.count) meals")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .overlay(Capsule().stroke(.primary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
                Button {
                    showingAddSheet = true
                } label: {
                    Text("Log")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(.primary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

            HStack(spacing: 28) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: calorieProgress)
                            .stroke(calorieColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: calorieProgress)

                        VStack(spacing: 2) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 18))
                                .foregroundStyle(calorieColor)
                            Text("\(totalCalories)")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            Text("kcal")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 148, height: 148)
                }

                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: proteinProgress)
                            .stroke(proteinColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: proteinProgress)

                        VStack(spacing: 2) {
                            Image(systemName: "fish.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(proteinColor)
                            Text("\(totalProtein)/\(goalStore.proteinGoal)g")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text("Protein")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 90, height: 90)
                }
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 28)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .sheet(isPresented: $showingMealDetails) {
            MealDetailsSheet(entries: groupedEntries)
                .tint(Color(.label))
        }
    }

    // MARK: - Weight Card

    private var weightCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Weight")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showingWeightLog = true
                } label: {
                    Text(selectedDateWeightEntry != nil ? "Edit" : "Log")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(.primary, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

            if let entry = selectedDateWeightEntry {
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", entry.weight))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("lbs")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if entry.bodyFat > 0 {
                        VStack(spacing: 2) {
                            Text("Body Fat")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", entry.bodyFat))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                    }
                    Spacer()
                }
            } else {
                HStack {
                    Text("No weight logged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

struct LogWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingEntry: WeightEntry?
    var date: Date

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @FocusState private var focusedField: WeightField?

    enum WeightField { case weight, bodyFat }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    VStack(spacing: 10) {
                        Text("\u{2696}\u{fe0f}")
                            .font(.system(size: 28))
                        Text("Weight (lbs)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.title2.weight(.bold))
                            .focused($focusedField, equals: .weight)
                            .onChange(of: weightText) {
                                if let val = Double(weightText), val > 999 {
                                    weightText = "999"
                                }
                            }
                            .overlay(alignment: .bottom) {
                                Line()
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .foregroundStyle(Color(.tertiaryLabel))
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                                    .offset(y: 4)
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
                    .onTapGesture { focusedField = .weight }

                    VStack(spacing: 10) {
                        Text("\u{1f4ca}")
                            .font(.system(size: 28))
                        Text("Body Fat (%)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.title2.weight(.bold))
                            .focused($focusedField, equals: .bodyFat)
                            .onChange(of: bodyFatText) {
                                if let val = Double(bodyFatText), val > 99.9 {
                                    bodyFatText = "99.9"
                                }
                            }
                            .overlay(alignment: .bottom) {
                                Line()
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .foregroundStyle(Color(.tertiaryLabel))
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                                    .offset(y: 4)
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
                    .onTapGesture { focusedField = .bodyFat }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 8)
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(Double(weightText) == nil)
                }
            }
            .onAppear {
                if let e = existingEntry {
                    weightText = String(format: "%.1f", e.weight)
                    if e.bodyFat > 0 {
                        bodyFatText = String(format: "%.1f", e.bodyFat)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .weight
                }
            }
        }
    }

    private func save() {
        guard let weight = Double(weightText), weight <= 999 else { return }
        let bodyFat = min(Double(bodyFatText) ?? 0, 99.9)

        if let existing = existingEntry {
            existing.weight = weight
            existing.bodyFat = bodyFat
        } else {
            modelContext.insert(WeightEntry(weight: weight, bodyFat: bodyFat, date: date))
        }
        dismiss()
    }
}

struct MealDetailsSheet: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [(MealCategory, [FoodEntry])]
    @State private var editingEntry: FoodEntry?

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries, id: \.0) { category, meals in
                    Section {
                        ForEach(meals) { entry in
                            Button {
                                editingEntry = entry
                            } label: {
                                HStack {
                                    Text(entry.name)
                                    Spacer()
                                    if entry.protein > 0 {
                                        Text("\(entry.protein)g")
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(entry.calories) cal")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                modelContext.delete(meals[index])
                            }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }
            }
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingEntry) { entry in
                EditFoodEntrySheet(entry: entry)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct EditFoodEntrySheet: View {
    @Bindable var entry: FoodEntry
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var category: MealCategory = .breakfast

    var body: some View {
        NavigationStack {
            Form {
                TextField("Meal name", text: $name)
                    .onChange(of: name) {
                        if name.count > 50 { name = String(name.prefix(50)) }
                    }
                TextField("Calories", text: $caloriesText)
                    .keyboardType(.numberPad)
                    .onChange(of: caloriesText) {
                        if let val = Int(caloriesText), val > 10000 { caloriesText = "10000" }
                    }
                TextField("Protein (g)", text: $proteinText)
                    .keyboardType(.numberPad)
                    .onChange(of: proteinText) {
                        if let val = Int(proteinText), val > 999 { proteinText = "999" }
                    }
                Picker("Meal", selection: $category) {
                    ForEach(MealCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        entry.name = String(name.prefix(50))
                        entry.calories = min(Int(caloriesText) ?? entry.calories, 10000)
                        entry.protein = min(Int(proteinText) ?? 0, 999)
                        entry.category = category
                        dismiss()
                    }
                    .disabled(name.isEmpty || Int(caloriesText) == nil)
                }
            }
            .onAppear {
                name = entry.name
                caloriesText = "\(entry.calories)"
                proteinText = entry.protein > 0 ? "\(entry.protein)" : ""
                category = entry.category
            }
        }
    }
}

struct GoalsSettingsSheet: View {
    var goalStore: GoalStore
    var stepCounter: StepCounter? = nil
    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    @Environment(\.modelContext) private var modelContext
    @Query private var existingFood: [FoodEntry]
    @Query private var existingGym: [GymEntry]
    @Query private var existingSets: [WorkoutSet]
    @Query private var existingWeight: [WeightEntry]
    @AppStorage("stepsEnabled") private var stepsEnabledFlag = false
    #endif

    @State private var stepsText = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var gymText = ""
    @State private var requireSteps = true
    @State private var requireCalories = true
    @State private var requireProtein = true
    @State private var requireGym = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    goalRow(
                        icon: "figure.walk",
                        title: "Steps",
                        value: $stepsText,
                        placeholder: "7000",
                        unit: "steps",
                        isRequired: $requireSteps
                    )
                    goalRow(
                        icon: "fork.knife",
                        title: "Calories",
                        value: $caloriesText,
                        placeholder: "2000",
                        unit: "kcal",
                        isRequired: $requireCalories
                    )
                    goalRow(
                        icon: "fish.fill",
                        title: "Protein",
                        value: $proteinText,
                        placeholder: "100",
                        unit: "g",
                        isRequired: $requireProtein
                    )
                    goalRow(
                        icon: "dumbbell.fill",
                        title: "Gym / week",
                        value: $gymText,
                        placeholder: "3",
                        unit: "days",
                        isRequired: $requireGym
                    )
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Goals & Day Completion")
                        Text("Toggle on to count toward a completed day.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                } footer: {
                    Text("\u{2139}\u{fe0f} Suggested defaults (7,000 steps · 2,000 kcal · 100g protein · 3 gym days) are based on guidance from the CDC, USDA, NIH, and WHO. See Health Information Sources below for details.")
                }

                Section {
                    sourceLink(
                        icon: "figure.walk",
                        title: "Daily Activity",
                        source: "CDC Physical Activity Guidelines",
                        url: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html"
                    )
                    sourceLink(
                        icon: "fork.knife",
                        title: "Daily Calories",
                        source: "U.S. Dietary Guidelines (HHS/USDA)",
                        url: "https://odphp.health.gov/our-work/nutrition-physical-activity/dietary-guidelines"
                    )
                    sourceLink(
                        icon: "fish.fill",
                        title: "Daily Protein",
                        source: "NIH MedlinePlus",
                        url: "https://medlineplus.gov/dietaryproteins.html"
                    )
                    sourceLink(
                        icon: "dumbbell.fill",
                        title: "Strength Training",
                        source: "WHO Physical Activity",
                        url: "https://www.who.int/news-room/fact-sheets/detail/physical-activity"
                    )
                    sourceLink(
                        icon: "timer",
                        title: "Rest Between Sets",
                        source: "American College of Sports Medicine",
                        url: "https://www.acsm.org/"
                    )
                    sourceLink(
                        icon: "scalemass.fill",
                        title: "Body Weight & Fat",
                        source: "NIH NIDDK Weight Management",
                        url: "https://www.niddk.nih.gov/health-information/weight-management"
                    )
                } header: {
                    Text("Health Information Sources")
                } footer: {
                    Text("Always consult a healthcare professional for personalized advice.")
                }

                Section {
                    Link(destination: URL(string: "mailto:hello@deadsimple.tools")!) {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundStyle(AppColors.accent)
                            Text("Contact Us")
                            Spacer()
                            Text("hello@deadsimple.tools")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://github.com/DaniArnaout/steps/blob/main/docs/support.html")!) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(AppColors.accent)
                            Text("Support")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Link(destination: URL(string: "https://github.com/DaniArnaout/steps/blob/main/docs/privacy.html")!) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(AppColors.accent)
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } footer: {
                    Text("Send us feedback or report issues.")
                }

                #if DEBUG
                Section {
                    Button {
                        seedDemoData()
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(AppColors.accent)
                            Text("Fill Demo Data")
                        }
                    }
                    Button(role: .destructive) {
                        clearAllData()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Data")
                        }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug only. Not included in App Store builds.")
                }
                #endif
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let s = Int(stepsText), s > 0 { goalStore.stepGoal = min(s, 200000) }
                        if let c = Int(caloriesText), c > 0 { goalStore.calorieGoal = min(c, 10000) }
                        if let p = Int(proteinText), p > 0 { goalStore.proteinGoal = min(p, 999) }
                        if let g = Int(gymText), g > 0 { goalStore.gymGoal = min(g, 7) }
                        goalStore.requireSteps = requireSteps
                        goalStore.requireCalories = requireCalories
                        goalStore.requireProtein = requireProtein
                        goalStore.requireGym = requireGym
                        goalStore.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                stepsText = "\(goalStore.stepGoal)"
                caloriesText = "\(goalStore.calorieGoal)"
                proteinText = "\(goalStore.proteinGoal)"
                gymText = "\(goalStore.gymGoal)"
                requireSteps = goalStore.requireSteps
                requireCalories = goalStore.requireCalories
                requireProtein = goalStore.requireProtein
                requireGym = goalStore.requireGym
            }
        }
    }

    #if DEBUG
    private func seedDemoData() {
        clearAllData()

        let calendar = Calendar.current
        let now = Date()

        var fullHistory: [DaySteps] = []
        for dayOffset in 0..<90 {
            if let day = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)) {
                let steps = Int.random(in: 6500...9800)
                fullHistory.append(DaySteps(date: day, steps: steps))
            }
        }
        fullHistory.sort { $0.date < $1.date }

        let fakeWeek = Array(fullHistory.suffix(7))
        if let data = try? JSONEncoder().encode(fakeWeek) {
            UserDefaults.standard.set(data, forKey: "stepsCacheV1")
        }
        stepCounter?.pastWeek = fakeWeek
        stepCounter?.todaySteps = fakeWeek.last?.steps ?? 7000
        #if DEBUG
        stepCounter?.mockHistory = fullHistory
        #endif
        stepsEnabledFlag = true

        let foodTemplate: [(String, Int, Int, MealCategory)] = [
            ("Oats", 320, 12, .breakfast),
            ("Greek Yogurt", 150, 18, .breakfast),
            ("Chicken & Rice", 620, 45, .lunch),
            ("Protein Shake", 180, 30, .snack),
            ("Salmon & Veggies", 580, 42, .dinner),
        ]

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            for (idx, item) in foodTemplate.enumerated() {
                let hour = [8, 9, 13, 16, 19][idx]
                let entryDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let entry = FoodEntry(
                    name: item.0,
                    calories: item.1 + Int.random(in: -30...30),
                    protein: item.2 + Int.random(in: -3...3),
                    date: entryDate,
                    category: item.3
                )
                modelContext.insert(entry)
            }

            let weightVariance = Double(dayOffset) * 0.2
            let weight = WeightEntry(
                weight: 178.0 + weightVariance + Double.random(in: -0.4...0.4),
                bodyFat: 18.5 + weightVariance * 0.1,
                date: day
            )
            modelContext.insert(weight)
        }

        let workoutDayOffsets = [0, 2, 4, 6]
        for offset in workoutDayOffsets {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let workoutDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
            let workoutID = UUID().uuidString
            let isUpper = offset % 4 == 0

            let exercises: [(String, Double, Int)] = isUpper
                ? [
                    ("Bench Press", 145, 10),
                    ("Row", 110, 10),
                    ("Shoulder Press", 85, 10),
                    ("Lat Pulldown", 130, 10),
                    ("Bicep Curls", 30, 12),
                    ("Tricep Curls", 30, 12),
                ]
                : [
                    ("Leg Extension", 100, 12),
                    ("Leg Curl", 90, 12),
                    ("Glute Kickback", 110, 12),
                    ("Hip Adductor", 130, 15),
                    ("Hip Abductor", 110, 15),
                ]

            for exercise in exercises {
                for setNumber in 0..<3 {
                    let set = WorkoutSet(
                        exerciseName: exercise.0,
                        weight: exercise.1,
                        reps: exercise.2,
                        setNumber: setNumber,
                        date: workoutDate,
                        workoutID: workoutID
                    )
                    modelContext.insert(set)
                }
            }

            let gym = GymEntry(date: workoutDate, duration: 2700 + Int.random(in: -300...600), workoutID: workoutID)
            modelContext.insert(gym)
        }

        try? modelContext.save()
        dismiss()
    }

    private func clearAllData() {
        for entry in existingFood { modelContext.delete(entry) }
        for entry in existingGym { modelContext.delete(entry) }
        for entry in existingSets { modelContext.delete(entry) }
        for entry in existingWeight { modelContext.delete(entry) }
        try? modelContext.save()
        UserDefaults.standard.removeObject(forKey: "stepsCacheV1")
        stepCounter?.pastWeek = []
        stepCounter?.todaySteps = 0
        stepCounter?.mockHistory = nil
        stepsEnabledFlag = false
    }
    #endif

    private func sourceLink(icon: String, title: String, source: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func goalRow(
        icon: String,
        title: String,
        value: Binding<String>,
        placeholder: String,
        unit: String? = nil,
        isRequired: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { isRequired.wrappedValue.toggle() }
            } label: {
                Image(systemName: isRequired.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isRequired.wrappedValue ? AppColors.accent : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)

            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 20)

            Text(title)
                .font(.body)

            Spacer()

            HStack(spacing: 4) {
                TextField(placeholder, text: value)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.medium))
                    .frame(width: 60)
                    .onChange(of: value.wrappedValue) {
                        if let val = Int(value.wrappedValue) {
                            let limit: Int
                            switch title {
                            case "Steps": limit = 200000
                            case "Calories": limit = 10000
                            case "Protein": limit = 999
                            case "Gym / week": limit = 7
                            default: limit = 99999
                            }
                            if val > limit { value.wrappedValue = "\(limit)" }
                        }
                    }
                if let unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FoodEntry.self, GymEntry.self, WeightEntry.self], inMemory: true)
}
