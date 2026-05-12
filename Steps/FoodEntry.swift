import Foundation
import SwiftData

enum MealCategory: String, CaseIterable, Codable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case snack = "Snack"
    case dinner = "Dinner"

    var icon: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .snack: return "cup.and.saucer"
        case .dinner: return "moon.stars"
        }
    }

    static func forTime(_ date: Date) -> MealCategory {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case ..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        default: return .dinner
        }
    }
}

@Model
final class FoodEntry {
    var name: String = ""
    var calories: Int = 0
    var protein: Int = 0
    var date: Date = Date.now
    var categoryRaw: String = MealCategory.breakfast.rawValue

    var category: MealCategory {
        get { MealCategory(rawValue: categoryRaw) ?? .snack }
        set { categoryRaw = newValue.rawValue }
    }

    init(name: String, calories: Int, protein: Int = 0, date: Date = .now, category: MealCategory? = nil) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.date = date
        self.categoryRaw = (category ?? MealCategory.forTime(date)).rawValue
    }
}

@Model
final class FoodPreset {
    var id: UUID = UUID()
    var name: String = ""
    var calories: Int = 0
    var protein: Int = 0
    var icon: String = "fork.knife"
    var categoryRaw: String = MealCategory.snack.rawValue
    var servingSize: String = ""
    var sortOrder: Int = 0

    var category: MealCategory {
        get { MealCategory(rawValue: categoryRaw) ?? .snack }
        set { categoryRaw = newValue.rawValue }
    }

    init(name: String, calories: Int, protein: Int = 0, icon: String, category: MealCategory, servingSize: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.calories = calories
        self.protein = protein
        self.icon = icon
        self.categoryRaw = category.rawValue
        self.servingSize = servingSize
        self.sortOrder = sortOrder
    }
}

@Model
final class WorkoutSet {
    var exerciseName: String = ""
    var weight: Double = 0
    var reps: Int = 0
    var setNumber: Int = 0
    var date: Date = Date.now
    var workoutID: String = ""

    init(exerciseName: String, weight: Double, reps: Int, setNumber: Int, date: Date = .now, workoutID: String = "") {
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.setNumber = setNumber
        self.date = date
        self.workoutID = workoutID
    }
}

@Model
final class GymEntry {
    var date: Date = Date.now
    var duration: Int = 0
    var workoutID: String = ""

    init(date: Date = .now, duration: Int = 0, workoutID: String = "") {
        self.date = date
        self.duration = duration
        self.workoutID = workoutID
    }
}

@Model
final class WeightEntry {
    var weight: Double = 0
    var bodyFat: Double = 0
    var date: Date = Date.now

    init(weight: Double, bodyFat: Double = 0, date: Date = .now) {
        self.weight = weight
        self.bodyFat = bodyFat
        self.date = date
    }
}
