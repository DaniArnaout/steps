import SwiftUI
import SwiftData

@main
struct StepsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([FoodEntry.self, GymEntry.self, WeightEntry.self, FoodPreset.self, WorkoutSet.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
