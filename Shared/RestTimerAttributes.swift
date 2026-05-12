import ActivityKit

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endTime: Date
        var totalDuration: Int
    }
    var workoutName: String
}
