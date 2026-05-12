import WidgetKit
import SwiftUI
import HealthKit
import ActivityKit

private let appGroupID = "group.com.daniarnaout.SpotMe"
private let accentGreen = Color(red: 0.20, green: 0.68, blue: 0.50)
private let dangerRed = Color(red: 0.88, green: 0.30, blue: 0.35)
private let warningOrange = Color(red: 0.95, green: 0.58, blue: 0.30)

private func loadStepGoal() -> Int {
    UserDefaults(suiteName: appGroupID)?.object(forKey: "goalSteps") as? Int ?? 7000
}

private func loadCalorieGoal() -> Int {
    UserDefaults(suiteName: appGroupID)?.object(forKey: "goalCalories") as? Int ?? 2400
}

struct SpotMeEntry: TimelineEntry {
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

struct SpotMeTimelineProvider: TimelineProvider {
    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    func placeholder(in context: Context) -> SpotMeEntry {
        SpotMeEntry(date: .now, steps: 4832, calories: 1200, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal())
    }

    func getSnapshot(in context: Context, completion: @escaping (SpotMeEntry) -> Void) {
        if context.isPreview {
            completion(SpotMeEntry(date: .now, steps: 4832, calories: 1200, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal()))
            return
        }
        Task {
            let steps = await fetchTodaySteps()
            let calories = caloriesForToday()
            completion(SpotMeEntry(date: .now, steps: steps, calories: calories, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpotMeEntry>) -> Void) {
        Task {
            let steps = await fetchTodaySteps()
            let calories = caloriesForToday()
            let entry = SpotMeEntry(date: .now, steps: steps, calories: calories, stepGoal: loadStepGoal(), calorieGoal: loadCalorieGoal())
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

struct SpotMeWidgetEntryView: View {
    var entry: SpotMeEntry
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
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 10)
            Circle()
                .trim(from: 0, to: entry.stepProgress)
                .stroke(entry.stepColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(entry.steps)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("steps")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Medium: Steps + Calories

    private var mediumWidget: some View {
        HStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.stepProgress)
                    .stroke(entry.stepColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.steps)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("steps")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.calorieProgress)
                    .stroke(entry.calorieColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.calories)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct SpotMeWidget: Widget {
    let kind = "SpotMeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpotMeTimelineProvider()) { entry in
            SpotMeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Spot Me")
        .description("Track your steps and calories at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Live Activity

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endTime: Date
        var totalDuration: Int
    }
    var workoutName: String
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(accentGreen)
                        Text("Spot Me")
                            .font(.headline)
                        Spacer()
                        Text(timerInterval: Date.now...context.state.endTime, countsDown: true)
                            .font(.title.weight(.bold).monospacedDigit())
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(accentGreen)
                    Text("Spot Me")
                        .font(.caption2.weight(.semibold))
                }
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.endTime, countsDown: true)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(accentGreen)
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<RestTimerAttributes>) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 4)
                    .frame(width: 50, height: 50)
                Image(systemName: "dumbbell.fill")
                    .font(.title2)
                    .foregroundStyle(accentGreen)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Spot Me")
                    .font(.subheadline.weight(.semibold))
                Text("\(context.attributes.workoutName) · Rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(timerInterval: Date.now...context.state.endTime, countsDown: true)
                .font(.title.weight(.bold).monospacedDigit())
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.8))
    }
}

#Preview(as: .systemSmall) {
    SpotMeWidget()
} timeline: {
    SpotMeEntry(date: .now, steps: 4832, calories: 1200, stepGoal: 7000, calorieGoal: 2400)
}

#Preview(as: .systemMedium) {
    SpotMeWidget()
} timeline: {
    SpotMeEntry(date: .now, steps: 4832, calories: 1200, stepGoal: 7000, calorieGoal: 2400)
}
