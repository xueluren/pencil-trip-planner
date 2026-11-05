import Foundation
import SwiftData

// MARK: - Trip -> TripDay -> Activity (SwiftData, offline-first)

@Model
final class Trip {
    var title: String
    var startDate: Date
    var endDate: Date
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TripDay.trip)
    var days: [TripDay] = []

    init(title: String, startDate: Date, endDate: Date, createdAt: Date = Date()) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }

    var sortedDays: [TripDay] {
        days.sorted { $0.date < $1.date }
    }
}

@Model
final class TripDay {
    var date: Date
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Activity.day)
    var activities: [Activity] = []

    init(date: Date) {
        self.date = date
    }

    var sortedActivities: [Activity] {
        activities.sorted { $0.startMinutes < $1.startMinutes }
    }
}

@Model
final class Activity {
    var title: String
    var emoji: String
    /// Minutes since midnight, e.g. 8:00 -> 480
    var startMinutes: Int
    var durationMinutes: Int
    var location: String
    var notes: String
    /// Key nodes (flight / hotel in-out) get the hand-drawn circle treatment
    var isKeyNode: Bool
    /// "In" / "Out" tag under the hotel emoji
    var tag: String
    /// System-calendar link (Phase 3): the EKEvent identifier this app wrote.
    /// nil = not synced. Lightweight-migration friendly (optional property).
    var calendarEventIdentifier: String?
    var day: TripDay?

    init(title: String,
         emoji: String = "📌",
         startMinutes: Int,
         durationMinutes: Int = 60,
         location: String = "",
         notes: String = "",
         isKeyNode: Bool = false,
         tag: String = "",
         calendarEventIdentifier: String? = nil) {
        self.title = title
        self.emoji = emoji
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.location = location
        self.notes = notes
        self.isKeyNode = isKeyNode
        self.tag = tag
        self.calendarEventIdentifier = calendarEventIdentifier
    }

    var endMinutes: Int { startMinutes + durationMinutes }
}
