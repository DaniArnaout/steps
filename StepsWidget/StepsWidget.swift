import WidgetKit
import SwiftUI
import HealthKit

private let appGroupID = "group.com.daniarnaout.Steps"
private let accentGreen = Color(red: 0.20, green: 0.68, blue: 0.50)
private let dangerRed = Color(red: 0.88, green: 0.30, blue: 0.35)
private let warningOrange = Color(red: 0.95, green: 0.58, blue: 0.30)

private func loadStepGoal() -> Int {
    UserDefaults(suiteName: appGroupID)?.object(forKey: "goalSteps") as? Int ?? 7000
}

private func loadCalorieGoal() -> Int {
    UserDefaults(suiteName: appGroupID)?.object(forKey: "goalCalories") as? Int ?? 2400
}

struct StepsEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let calories: Int
    let stepGoal: Int
    let calorieGoal: Int

    var stepProgress: Double {
        min(Double(steps) / Double(max(stepGoal, 1)), 1.0)
    }

    var stepsRemaining: Int {
        max(stepGoal - steps, 0)
    }

    var stepColor: Color {
        stepProgress >= 1.0 ? accentGreen : warningOrange
    }

    var calorieProgress: Double {
        min(Double(calories) / Double(max(calorieGoal, 1)), 1.0)
    }

    var caloriesRemaining: Int {
        max(calorieGoal - calories, 0)
    }

    var calorieColor: Color {
        if calories > calorieGoal { return dangerRed }
        return accentGreen
    }
}

struct StepsTimelineProvider: TimelineProvider {
    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    func placeholder(in context: Context) -> StepsEntry {
        StepsEntry(date: .now, steps: 4832, calories: 1200, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal())
    }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        if context.isPreview {
            completion(StepsEntry(date: .now, steps: 4832, calories: 1200, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal()))
            return
        }
        Task {
            let steps = await fetchTodaySteps()
            let calories = caloriesForToday()
            completion(StepsEntry(date: .now, steps: steps, calories: calories, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        Task {
            let steps = await fetchTodaySteps()
            let calories = caloriesForToday()
            let entry = StepsEntry(date: .now, steps: steps, calories: calories, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal())
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func caloriesForToday() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let caloriesByDay = defaults.dictionary(forKey: "dailyCalories") as? [String: Int] else {
            return 0
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return caloriesByDay[formatter.string(from: .now)] ?? 0
    }

    private func fetchTodaySteps() async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let samplePredicate = HKSamplePredicate.quantitySample(type: stepType, predicate: predicate)

        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let result = try await query.result(for: healthStore)
            var todaySteps = 0
            result.enumerateStatistics(from: start, to: .now) { stats, _ in
                todaySteps = Int(stats.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0)
            }
            return todaySteps
        } catch {
            return 0
        }
    }
}

// MARK: - Widget Views

struct StepsWidgetEntryView: View {
    var entry: StepsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            mediumWidget
        }
    }

    // MARK: - Small: Steps Only

    private var smallWidget: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.stepProgress)
                    .stroke(entry.stepColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(entry.steps)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        Text("steps")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if entry.stepProgress >= 1.0 {
                        Text("goal reached")
                            .font(.system(size: 9))
                            .foregroundStyle(accentGreen)
                    } else {
                        Text("\(entry.stepsRemaining.formatted()) left")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            Text("Steps")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Medium: Steps + Calories

    private var mediumWidget: some View {
        HStack(spacing: 32) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: entry.stepProgress)
                        .stroke(entry.stepColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(entry.steps)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText())
                            Text("steps")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        if entry.stepProgress >= 1.0 {
                            Text("goal reached")
                                .font(.system(size: 9))
                                .foregroundStyle(accentGreen)
                        } else {
                            Text("\(entry.stepsRemaining.formatted()) left")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Steps")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: entry.calorieProgress)
                        .stroke(entry.calorieColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(entry.calories)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText())
                            Text("kcal")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        if entry.calories > entry.calorieGoal {
                            Text("\(entry.calories - entry.calorieGoal) over")
                                .font(.system(size: 9))
                                .foregroundStyle(dangerRed)
                        } else {
                            Text("\(entry.caloriesRemaining.formatted()) left")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Food")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct StepsWidget: Widget {
    let kind = "StepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepsTimelineProvider()) { entry in
            StepsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Spot Me")
        .description("Track your steps and calories at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    StepsWidget()
} timeline: {
    StepsEntry(date: .now, steps: 4832, calories: 1200, stepGoal: 7000, calorieGoal: 2400)
}

#Preview(as: .systemMedium) {
    StepsWidget()
} timeline: {
    StepsEntry(date: .now, steps: 4832, calories: 1200, stepGoal: 7000, calorieGoal: 2400)
}
