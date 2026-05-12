import SwiftUI
import SwiftData
import Charts

struct DailyNutrition: Identifiable {
    let date: Date
    let calories: Int
    let protein: Int
    var id: Date { date }
}

enum TimeRange: String, CaseIterable {
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .year: return 365
        }
    }
}

struct AnalyticsView: View {
    var goalStore: GoalStore
    var stepCounter: StepCounter

    @Query(sort: \WeightEntry.date) private var allWeightEntries: [WeightEntry]
    @Query(sort: \FoodEntry.date) private var allFoodEntries: [FoodEntry]
    @Query(sort: \GymEntry.date) private var allGymEntries: [GymEntry]

    @State private var selectedRange: TimeRange = .week
    @State private var stepHistory: [DaySteps] = []
    @State private var dailyNutritionData: [DailyNutrition] = []
    @State private var stepsData: [DaySteps] = []
    @State private var isLoading = true
    @State private var selectedStepDate: Date?
    @State private var selectedCalorieDate: Date?
    @State private var selectedProteinDate: Date?
    @State private var selectedWeightDate: Date?
    @State private var selectedBodyFatDate: Date?
    @State private var showingContact = false

    private var dateRange: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<selectedRange.days).compactMap { offset in
            calendar.date(byAdding: .day, value: -(selectedRange.days - 1 - offset), to: today)
        }
    }

    private var startDate: Date {
        dateRange.first ?? Date()
    }

    private func loadData() async {
        isLoading = true
        let range = dateRange
        let start = range.first ?? Date()

        let steps = await stepCounter.fetchHistory(days: selectedRange.days)

        let calendar = Calendar.current
        let stepsByDay = Dictionary(uniqueKeysWithValues: steps.map {
            (calendar.startOfDay(for: $0.date), $0)
        })
        let computedSteps = range.map { date in
            let dayStart = calendar.startOfDay(for: date)
            return stepsByDay[dayStart] ?? DaySteps(date: dayStart, steps: 0)
        }

        let filtered = allFoodEntries.filter { $0.date >= start }
        let grouped = Dictionary(grouping: filtered) { entry in
            calendar.startOfDay(for: entry.date)
        }
        let computedNutrition = range.map { date in
            let dayStart = calendar.startOfDay(for: date)
            let entries = grouped[dayStart] ?? []
            return DailyNutrition(
                date: dayStart,
                calories: entries.reduce(0) { $0 + $1.calories },
                protein: entries.reduce(0) { $0 + $1.protein }
            )
        }

        withAnimation {
            stepHistory = steps
            stepsData = computedSteps
            dailyNutritionData = computedNutrition
            isLoading = false
        }
    }

    private var gymDaysInRange: [GymEntry] {
        allGymEntries.filter { $0.date >= startDate }
    }

    private var weightInRange: [WeightEntry] {
        allWeightEntries.filter { $0.date >= startDate }
    }

    private var weightYMin: Double {
        let weights = weightInRange.map(\.weight)
        return (weights.min() ?? 0) - 5
    }

    private var weightYMax: Double {
        let weights = weightInRange.map(\.weight)
        return (weights.max() ?? 200) + 5
    }

    private var bodyFatYMin: Double {
        let values = weightInRange.filter { $0.bodyFat > 0 }.map(\.bodyFat)
        return (values.min() ?? 0) - 2
    }

    private var bodyFatYMax: Double {
        let values = weightInRange.filter { $0.bodyFat > 0 }.map(\.bodyFat)
        return (values.max() ?? 30) + 2
    }

    private func stepColor(_ steps: Int) -> Color {
        if steps == 0 { return AppColors.neutral }
        return steps >= goalStore.stepGoal ? AppColors.success : AppColors.danger
    }

    private func calorieColor(_ calories: Int) -> Color {
        if calories == 0 { return AppColors.neutral }
        return calories <= goalStore.calorieGoal ? AppColors.success : AppColors.danger
    }

    private func proteinColor(_ protein: Int) -> Color {
        if protein == 0 { return AppColors.neutral }
        return protein >= goalStore.proteinGoal ? AppColors.success : AppColors.danger
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        stepsChartSection
                        caloriesChartSection
                        proteinChartSection
                        if !weightInRange.isEmpty {
                            weightChartSection
                        }
                        if weightInRange.contains(where: { $0.bodyFat > 0 }) {
                            bodyFatChartSection
                        }
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .task {
                await loadData()
            }
            .onChange(of: selectedRange) {
                Task { await loadData() }
            }
            .onChange(of: allFoodEntries.count) {
                Task { await loadData() }
            }
        }
    }

    // MARK: - Steps

    private var selectedStepValue: String? {
        guard let selected = selectedStepDate,
              let day = stepsData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) else { return nil }
        return "\(day.steps) steps"
    }

    private var selectedCalorieValue: String? {
        guard let selected = selectedCalorieDate,
              let day = dailyNutritionData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) else { return nil }
        return "\(day.calories) kcal"
    }

    private var selectedProteinValue: String? {
        guard let selected = selectedProteinDate,
              let day = dailyNutritionData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) else { return nil }
        return "\(day.protein)g"
    }

    private var selectedWeightValue: String? {
        guard let selected = selectedWeightDate,
              let entry = weightInRange.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) else { return nil }
        return String(format: "%.1f lbs", entry.weight)
    }

    private var selectedBodyFatValue: String? {
        guard let selected = selectedBodyFatDate,
              let entry = weightInRange.filter({ $0.bodyFat > 0 }).first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) else { return nil }
        return String(format: "%.1f%%", entry.bodyFat)
    }

    private var stepsChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                    Text("Steps")
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                if let value = selectedStepValue {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .transition(.opacity)
                } else if !gymDaysInRange.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill")
                            .font(.caption2)
                        Text("\(gymDaysInRange.count) gym")
                            .font(.caption)
                    }
                    .foregroundStyle(Color(.label))
                }
            }

            Chart {
                ForEach(stepsData) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Steps", day.steps)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(stepColor(day.steps))
                }

                ForEach(gymDaysInRange) { entry in
                    PointMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Steps", goalStore.stepGoal + 500)
                    )
                    .symbol {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(.label))
                    }
                }

                RuleMark(y: .value("Goal", goalStore.stepGoal))
                    .foregroundStyle(Color(.label).opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(goalStore.stepGoal)")
                            .font(.caption2)
                            .foregroundStyle(Color(.label))
                    }

                if let selected = selectedStepDate {
                    RuleMark(x: .value("Date", selected, unit: .day))
                        .foregroundStyle(Color(.label).opacity(0.3))
                }
            }
            .chartXSelection(value: $selectedStepDate)
            .frame(height: 180)
        }
        .padding()
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Calories

    private var caloriesChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                    Text("Calories")
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                if let value = selectedCalorieValue {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(dailyNutritionData) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Calories", day.calories)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(calorieColor(day.calories))
                }
                RuleMark(y: .value("Goal", goalStore.calorieGoal))
                    .foregroundStyle(Color(.label).opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(goalStore.calorieGoal) kcal")
                            .font(.caption2)
                            .foregroundStyle(Color(.label))
                    }

                if let selected = selectedCalorieDate {
                    RuleMark(x: .value("Date", selected, unit: .day))
                        .foregroundStyle(Color(.label).opacity(0.3))
                }
            }
            .chartXSelection(value: $selectedCalorieDate)
            .frame(height: 180)
        }
        .padding()
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Protein

    private var proteinChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "fish.fill")
                    Text("Protein")
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                if let value = selectedProteinValue {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(dailyNutritionData) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Protein", day.protein)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(proteinColor(day.protein))
                }
                RuleMark(y: .value("Goal", goalStore.proteinGoal))
                    .foregroundStyle(Color(.label).opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(goalStore.proteinGoal)g")
                            .font(.caption2)
                            .foregroundStyle(Color(.label))
                    }

                if let selected = selectedProteinDate {
                    RuleMark(x: .value("Date", selected, unit: .day))
                        .foregroundStyle(Color(.label).opacity(0.3))
                }
            }
            .chartXSelection(value: $selectedProteinDate)
            .frame(height: 180)
        }
        .padding()
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Weight

    private var weightChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "scalemass.fill")
                    Text("Weight")
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                if let value = selectedWeightValue {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(weightInRange) { entry in
                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Weight", entry.weight)
                    )
                    .foregroundStyle(Color(.label))
                    PointMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Weight", entry.weight)
                    )
                    .foregroundStyle(Color(.label))
                }

                if let selected = selectedWeightDate {
                    RuleMark(x: .value("Date", selected, unit: .day))
                        .foregroundStyle(Color(.label).opacity(0.3))
                }
            }
            .chartXSelection(value: $selectedWeightDate)
            .chartXScale(domain: startDate...Date())
            .chartYScale(domain: weightYMin...weightYMax)
            .frame(height: 180)
        }
        .padding()
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Body Fat

    private var bodyFatChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "percent")
                    Text("Body Fat")
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                if let value = selectedBodyFatValue {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(weightInRange.filter { $0.bodyFat > 0 }) { entry in
                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Body Fat", entry.bodyFat)
                    )
                    .foregroundStyle(Color(.label))
                    PointMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Body Fat", entry.bodyFat)
                    )
                    .foregroundStyle(Color(.label))
                }

                if let selected = selectedBodyFatDate {
                    RuleMark(x: .value("Date", selected, unit: .day))
                        .foregroundStyle(Color(.label).opacity(0.3))
                }
            }
            .chartXSelection(value: $selectedBodyFatDate)
            .chartXScale(domain: startDate...Date())
            .chartYScale(domain: bodyFatYMin...bodyFatYMax)
            .frame(height: 180)
        }
        .padding()
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

struct ContactUsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Please report issues and request new features:")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    UIPasteboard.general.string = "hello@deadsimple.tools"
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Text("hello@deadsimple.tools")
                        .foregroundStyle(.blue)
                }

                if copied {
                    Text("Copied!")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .padding()
            .navigationTitle("Contact Us")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(250)])
    }
}

#Preview {
    AnalyticsView(goalStore: GoalStore(), stepCounter: StepCounter())
        .modelContainer(for: [FoodEntry.self, GymEntry.self, WeightEntry.self], inMemory: true)
}
