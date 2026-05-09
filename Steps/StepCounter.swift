import Foundation
import HealthKit
import Observation
import WidgetKit

struct DaySteps: Identifiable, Codable {
    var id: String { dateKey }
    let dateKey: String
    let date: Date
    let steps: Int

    var weekdayLetter: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    init(date: Date, steps: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateKey = formatter.string(from: date)
        self.date = date
        self.steps = steps
    }
}

@Observable
final class StepCounter {
    private static let cacheKey = "stepsCacheV1"

    var todaySteps: Int = 0
    var pastWeek: [DaySteps] = []
    var isAuthorized = false
    var errorMessage: String?

    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private var observeTask: Task<Void, Never>?

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data is not available on this device."
            return
        }

        loadCache()

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType])
            isAuthorized = true
            await fetchPastWeek()
            startObserving()
        } catch {
            errorMessage = "Authorization failed: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard isAuthorized else { return }
        await fetchPastWeek()
        startObserving()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func fetchHistory(days: Int) async -> [DaySteps] {
        guard isAuthorized else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let samplePredicate = HKSamplePredicate.quantitySample(type: stepType, predicate: predicate)

        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let result = try await query.result(for: healthStore)
            var allDays: [DaySteps] = []
            result.enumerateStatistics(from: start, to: today) { stats, _ in
                let steps = stats.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                allDays.append(DaySteps(date: stats.startDate, steps: Int(steps)))
            }
            return allDays
        } catch {
            return []
        }
    }

    private func startObserving() {
        observeTask?.cancel()
        observeTask = Task { await startObservingSteps() }
    }

    // MARK: - Cache

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([DaySteps].self, from: data) else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else { return }

        let relevant = cached.filter { $0.date >= weekAgo }
        if !relevant.isEmpty {
            pastWeek = relevant.sorted { $0.date < $1.date }
            if let todayEntry = relevant.first(where: { calendar.isDateInToday($0.date) }) {
                todaySteps = todayEntry.steps
            }
        }
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(pastWeek) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    // MARK: - Fetch

    private func fetchPastWeek() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: Date())
        let samplePredicate = HKSamplePredicate.quantitySample(type: stepType, predicate: predicate)

        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let result = try await query.result(for: healthStore)
            var days: [DaySteps] = []
            result.enumerateStatistics(from: weekAgo, to: today) { stats, _ in
                let steps = stats.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                days.append(DaySteps(date: stats.startDate, steps: Int(steps)))
            }
            pastWeek = days
            if let todayEntry = days.first(where: { calendar.isDateInToday($0.date) }) {
                todaySteps = todayEntry.steps
            }
            saveCache()
        } catch {
            errorMessage = "Failed to fetch weekly steps: \(error.localizedDescription)"
        }
    }

    private func startObservingSteps() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: nil)
        let samplePredicate = HKSamplePredicate.quantitySample(type: stepType, predicate: predicate)

        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: startOfDay,
            intervalComponents: DateComponents(day: 1)
        )

        let updates = query.results(for: healthStore)

        do {
            for try await result in updates {
                let now = Date()
                let today = calendar.startOfDay(for: now)
                if let stats = result.statisticsCollection.statistics(for: today) {
                    let steps = stats.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    todaySteps = Int(steps)
                    if let lastIndex = pastWeek.lastIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
                        pastWeek[lastIndex] = DaySteps(date: today, steps: Int(steps))
                    }
                    saveCache()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = "Failed to observe steps: \(error.localizedDescription)"
            }
        }
    }
}
