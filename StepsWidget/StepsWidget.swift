import WidgetKit
import SwiftUI
import HealthKit

private let appGroupID = "group.com.daniarnaout.SpotMe"

private func loadStepGoal() -> Int {
    UserDefaults(suiteName: appGroupID)?.object(forKey: "goalSteps") as? Int ?? 7000
}

private func loadCalorieGoal() -> Int {
    UserDefaults(suiteName: appGroupID)?.object(forKey: "goalCalories") as? Int ?? 2400
}

struct DayData {
    let date: Date
    let steps: Int
    let calories: Int
    let stepGoal: Int
    let calorieGoal: Int

    var hitGoal: Bool { steps >= stepGoal && calories <= calorieGoal }
    var hitStepGoal: Bool { steps >= stepGoal }

    var weekdayLetter: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

struct StepsEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let calories: Int
    let pastWeek: [DayData]
    let stepGoal: Int
    let calorieGoal: Int

    var progress: Double {
        min(Double(steps) / Double(stepGoal), 1.0)
    }

    var remaining: Int {
        max(stepGoal - steps, 0)
    }

    var progressColor: Color {
        if progress >= 1.0 { return .green }
        if progress >= 0.5 { return .blue }
        return .orange
    }

    var calorieProgress: Double {
        min(Double(calories) / Double(calorieGoal), 1.0)
    }

    var remainingCalories: Int {
        max(calorieGoal - calories, 0)
    }

    var calorieColor: Color {
        if calories > calorieGoal { return .red }
        if calorieProgress >= 0.75 { return .orange }
        return .green
    }

    var currentStreak: Int {
        var streak = 0
        for day in pastWeek.reversed() {
            if day.hitGoal { streak += 1 } else { break }
        }
        return streak
    }
}

struct StepsTimelineProvider: TimelineProvider {
    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: .now, steps: 4832, calories: 1200, pastWeek: [], stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal())
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        if context.isPreview {
            completion(StepsEntry(date: .now, steps: 4832, calories: 1200, pastWeek: [], stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal()))
            return
        }
        Task {
            let sg = loadStepGoal(); let cg = loadCalorieGoal()
            let (steps, week) = await fetchStepsData(stepGoal: sg, calorieGoal: cg)
            let todayCalories = caloriesForToday()
            completion(StepsEntry(date: .now, steps: steps, calories: todayCalories, pastWeek: week, stepGoal: sg, calorieGoal: cg))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        Task {
            let sg = loadStepGoal(); let cg = loadCalorieGoal()
            let (steps, week) = await fetchStepsData(stepGoal: sg, calorieGoal: cg)
            let todayCalories = caloriesForToday()
            let entry = StepsEntry(date: .now, steps: steps, calories: todayCalories, pastWeek: week, stepGoal: sg, calorieGoal: cg)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func caloriesForToday() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let caloriesByDay = defaults.dictionary(forKey: "dailyCalories") as? [String: Int] else {
            return 0
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: .now)
        return caloriesByDay[todayKey] ?? 0
    }

    private func caloriesForDate(_ date: Date) -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let caloriesByDay = defaults.dictionary(forKey: "dailyCalories") as? [String: Int] else {
            return 0
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date)
        return caloriesByDay[key] ?? 0
    }

    private func fetchStepsData(stepGoal: Int, calorieGoal: Int) async -> (Int, [DayData]) {
        guard HKHealthStore.isHealthDataAvailable() else { return (0, []) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else { return (0, []) }

        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: .now)
        let samplePredicate = HKSamplePredicate.quantitySample(type: stepType, predicate: predicate)

        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let result = try await query.result(for: healthStore)
            var days: [DayData] = []
            var todaySteps = 0
            result.enumerateStatistics(from: weekAgo, to: today) { stats, _ in
                let steps = Int(stats.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0)
                let calories = caloriesForDate(stats.startDate)
                days.append(DayData(date: stats.startDate, steps: steps, calories: calories, stepGoal: stepGoal, calorieGoal: calorieGoal))
                if calendar.isDateInToday(stats.startDate) {
                    todaySteps = steps
                }
            }
            return (todaySteps, days)
        } catch {
            return (0, [])
        }
    }
}

struct StepsWidgetEntryView: View {
    var entry: StepsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemLarge:
            largeWidget
        default:
            mediumWidget
        }
    }

    private var smallWidget: some View {
        VStack(spacing: 0) {
            Spacer()

            if entry.steps >= entry.stepGoal {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Done!")
                    .font(.system(.headline, design: .rounded))
            } else {
                Text("\(entry.remaining)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Text("Steps to go")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            if !entry.pastWeek.isEmpty {
                HStack(spacing: 2)  {
                    ForEach(Array(entry.pastWeek.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 2) {
                            Image(systemName: day.hitStepGoal ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(day.hitStepGoal ? .green : .secondary)
                            Text(day.weekdayLetter)
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumWidget: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(entry.progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .foregroundStyle(entry.progressColor)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    if entry.steps >= entry.stepGoal {
                        Text("\(entry.steps)")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .contentTransition(.numericText())
                        Text("Goal reached!")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(entry.remaining)")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .contentTransition(.numericText())
                        Text("\(entry.steps.formatted()) walked")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if entry.currentStreak > 0 {
                    VStack(spacing: 2) {
                        Text("\(entry.currentStreak)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("streak")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !entry.pastWeek.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(entry.pastWeek.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 4) {
                            Image(systemName: day.hitGoal ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(day.hitGoal ? .green : .secondary)
                            Text(day.weekdayLetter)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var largeWidget: some View {
        VStack(spacing: 16) {
            if !entry.pastWeek.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(entry.pastWeek.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 4) {
                            Image(systemName: day.hitGoal ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.title3)
                                .foregroundStyle(day.hitGoal ? .green : .secondary)
                            Text(day.weekdayLetter)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Spacer()

            // Steps ring
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(entry.progressColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Image(systemName: entry.progress >= 1.0 ? "figure.walk.diamond.fill" : "figure.walk")
                        .font(.system(size: 20))
                        .foregroundStyle(entry.progressColor)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(entry.steps)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("steps")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if entry.progress >= 1.0 {
                        Text("goal reached")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(entry.remaining.formatted()) left")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 120, height: 120)

            // Calorie ring
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.calorieProgress)
                    .stroke(entry.calorieColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 20))
                        .foregroundStyle(entry.calorieColor)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(entry.calories)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("kcal")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if entry.calories > entry.calorieGoal {
                        Text("\(entry.calories - entry.calorieGoal) over")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    } else {
                        Text("\(entry.remainingCalories.formatted()) left")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 120, height: 120)

            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StepsWidget: Widget {
    let kind = "StepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepsTimelineProvider()) { entry in
            StepsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Steps")
        .description("Shows your step count, calories, and weekly streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    StepsWidget()
} timeline: {
    StepsEntry(date: .now, steps: 4832, calories: 1200, pastWeek: [
        DayData(date: Calendar.current.date(byAdding: .day, value: -6, to: .now)!, steps: 8200, calories: 2100, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -5, to: .now)!, steps: 3100, calories: 2500, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -4, to: .now)!, steps: 7500, calories: 1800, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -3, to: .now)!, steps: 7100, calories: 2300, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -2, to: .now)!, steps: 9200, calories: 2000, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, steps: 7800, calories: 2200, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: .now, steps: 4832, calories: 1200, stepGoal: 7000, calorieGoal: 2400),
    ], stepGoal: 7000, calorieGoal: 2400)
}

#Preview(as: .systemMedium) {
    StepsWidget()
} timeline: {
    StepsEntry(date: .now, steps: 7500, calories: 1800, pastWeek: [
        DayData(date: Calendar.current.date(byAdding: .day, value: -6, to: .now)!, steps: 8200, calories: 2100, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -5, to: .now)!, steps: 3100, calories: 2500, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -4, to: .now)!, steps: 7500, calories: 1800, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -3, to: .now)!, steps: 7100, calories: 2300, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -2, to: .now)!, steps: 9200, calories: 2000, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, steps: 7800, calories: 2200, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: .now, steps: 7500, calories: 1800, stepGoal: 7000, calorieGoal: 2400),
    ], stepGoal: 7000, calorieGoal: 2400)
}

#Preview(as: .systemLarge) {
    StepsWidget()
} timeline: {
    StepsEntry(date: .now, steps: 4832, calories: 1200, pastWeek: [
        DayData(date: Calendar.current.date(byAdding: .day, value: -6, to: .now)!, steps: 8200, calories: 2100, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -5, to: .now)!, steps: 3100, calories: 2500, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -4, to: .now)!, steps: 7500, calories: 1800, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -3, to: .now)!, steps: 7100, calories: 2300, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -2, to: .now)!, steps: 9200, calories: 2000, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, steps: 7800, calories: 2200, stepGoal: 7000, calorieGoal: 2400),
        DayData(date: .now, steps: 4832, calories: 1200, stepGoal: 7000, calorieGoal: 2400),
    ], stepGoal: 7000, calorieGoal: 2400)
}
