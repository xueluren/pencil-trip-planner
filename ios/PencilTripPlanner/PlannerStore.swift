import Foundation
import SwiftData
import Observation

// MARK: - Sheet contexts

struct EventSheetContext: Identifiable, Equatable {
    let id = UUID()
    var dayID: PersistentIdentifier
    var activityID: PersistentIdentifier?
    var presetStartMinutes: Int
}

struct TripSheetContext: Identifiable, Equatable {
    let id = UUID()
    /// nil -> create new trip
    var editingTripID: PersistentIdentifier?
    var isCreate: Bool { editingTripID == nil }
}

struct EventDraft {
    var dayID: PersistentIdentifier
    var editingActivityID: PersistentIdentifier?
    var title: String
    var emoji: String
    var startMinutes: Int
    var durationMinutes: Int
    var location: String
    var notes: String
    /// Phase 3: write through to the system calendar on save.
    var syncToCalendar: Bool = false
}

/// One row chosen in the calendar-import sheet.
struct CalendarImportItem {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String
    let emoji: String
}

// MARK: - Store (selection state + CRUD, SwiftData on main actor)

@Observable
@MainActor
final class PlannerStore {
    let modelContext: ModelContext

    // Navigation / selection
    var selectedTripID: PersistentIdentifier?
    var selectedDayIndex: Int?
    var detailDayIndex: Int = 0
    var showingDetail = false
    var showingSidebar = false

    // Sheets
    var eventSheet: EventSheetContext?
    var tripSheet: TripSheetContext?
    var showingCalendarImport = false
    var showingEmailImport = false

    // Phase 3: EventKit sync (all on-device). Non-nil -> ContentView shows
    // an alert guiding the user to Settings.
    var calendarNotice: String?
    let calendarSync = CalendarSyncService()

    static let emojis = ["📌","✈️","🏨","🤿","🍹","🚗","🛥️","⛱️","🏖️","🍽️","🥾","🏄","🛍️","⛵","🥂","☕","🏛️","🎟️","📸","🌊","🌴","🚆"]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Trip resolution

    func currentTrip(from trips: [Trip]) -> Trip? {
        if let id = selectedTripID,
           let t = trips.first(where: { $0.persistentModelID == id }) {
            return t
        }
        return trips.first
    }

    func isCurrent(_ trip: Trip, in trips: [Trip]) -> Bool {
        currentTrip(from: trips)?.persistentModelID == trip.persistentModelID
    }

    // MARK: - Navigation

    func openDay(_ day: TripDay, in trip: Trip) {
        let days = trip.sortedDays
        if let i = days.firstIndex(where: { $0.persistentModelID == day.persistentModelID }) {
            selectedDayIndex = i
            detailDayIndex = i
        }
        showingDetail = true
    }

    func closeDetail() {
        showingDetail = false
        selectedDayIndex = nil
    }

    func pickStripDay(_ i: Int) {
        detailDayIndex = i
        selectedDayIndex = i
    }

    func switchTrip(_ trip: Trip) {
        selectedTripID = trip.persistentModelID
        selectedDayIndex = nil
        detailDayIndex = 0
        showingDetail = false
        showingSidebar = false
    }

    // MARK: - Events

    func newEvent(presetStartMinutes: Int, in day: TripDay) {
        eventSheet = EventSheetContext(
            dayID: day.persistentModelID,
            activityID: nil,
            presetStartMinutes: presetStartMinutes
        )
    }

    func editEvent(_ act: Activity, in day: TripDay) {
        eventSheet = EventSheetContext(
            dayID: day.persistentModelID,
            activityID: act.persistentModelID,
            presetStartMinutes: act.startMinutes
        )
    }

    /// Saves the draft; returns the saved activity so the caller can
    /// run calendar sync afterwards. Phase 3: EventKit is write-through
    /// only when the editor asked for it (draft.syncToCalendar).
    @discardableResult
    func saveEvent(_ draft: EventDraft) -> Activity? {
        guard let day = modelContext.model(for: draft.dayID) as? TripDay else { return nil }
        let act: Activity
        if let aid = draft.editingActivityID,
           let existing = modelContext.model(for: aid) as? Activity {
            existing.title = draft.title
            existing.emoji = draft.emoji
            existing.startMinutes = draft.startMinutes
            existing.durationMinutes = draft.durationMinutes
            existing.location = draft.location
            existing.notes = draft.notes
            act = existing
        } else {
            act = Activity(
                title: draft.title,
                emoji: draft.emoji,
                startMinutes: draft.startMinutes,
                durationMinutes: draft.durationMinutes,
                location: draft.location,
                notes: draft.notes
            )
            day.activities.append(act)
        }
        try? modelContext.save()
        return act
    }

    /// Writes the activity to the system calendar and stores the event
    /// identifier back on the activity. Shows a Settings alert on denial.
    func syncActivityToCalendar(_ activity: Activity) async {
        guard let day = activity.day else { return }
        do {
            let id = try await calendarSync.syncActivity(activity, on: day)
            activity.calendarEventIdentifier = id
            try? modelContext.save()
        } catch let err as CalendarSyncService.SyncError {
            if case .accessDenied = err {
                calendarNotice = "Calendar access is off. Turn it on in Settings → Privacy & Security → Calendars to sync."
            } else {
                calendarNotice = err.localizedDescription
            }
        } catch {
            calendarNotice = error.localizedDescription
        }
    }

    /// Unlinks the activity: deletes the system-calendar copy (best effort)
    /// and clears the stored identifier.
    func removeActivityFromCalendar(_ activity: Activity) async {
        if let id = activity.calendarEventIdentifier {
            try? calendarSync.removeFromCalendar(identifier: id)
            activity.calendarEventIdentifier = nil
            try? modelContext.save()
        }
    }

    /// Imports picked system-calendar events as activities on the matching
    /// trip days. Imported rows are NOT auto-synced (they already live in
    /// the calendar); the user can link them later via the editor toggle.
    func importCalendarEvents(_ items: [CalendarImportItem], into trip: Trip) {
        let cal = Calendar.current
        let days = trip.sortedDays
        for item in items {
            guard let day = days.first(where: { cal.isDate($0.date, inSameDayAs: item.startDate) })
            else { continue }
            let startMin = minutesOfDay(item.startDate)
            let durMin = max(15, Int(item.endDate.timeIntervalSince(item.startDate) / 60))
            day.activities.append(Activity(
                title: item.title.isEmpty ? "Imported event" : item.title,
                emoji: item.emoji,
                startMinutes: startMin,
                durationMinutes: durMin,
                location: item.location
            ))
        }
        try? modelContext.save()
    }

    func deleteEvent(id: PersistentIdentifier) {
        if let act = modelContext.model(for: id) as? Activity {
            // Best effort: also remove the system-calendar copy we wrote.
            let calID = act.calendarEventIdentifier
            modelContext.delete(act)
            try? modelContext.save()
            if let calID {
                Task { @MainActor in
                    try? calendarSync.removeFromCalendar(identifier: calID)
                }
            }
        }
    }

    // MARK: - Trips

    func newTrip() {
        showingSidebar = false
        tripSheet = TripSheetContext(editingTripID: nil)
    }

    func editTrip(_ trip: Trip) {
        tripSheet = TripSheetContext(editingTripID: trip.persistentModelID)
    }

    func saveTrip(title: String, start: Date, end: Date, editingID: PersistentIdentifier?) {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: end)
        let span = max(0, cal.dateComponents([.day], from: s, to: e).day ?? 0)
        let count = span + 1

        if let eid = editingID,
           let trip = modelContext.model(for: eid) as? Trip {
            let changed = !cal.isDate(trip.startDate, inSameDayAs: s)
                || !cal.isDate(trip.endDate, inSameDayAs: e)
            trip.title = title
            trip.startDate = s
            trip.endDate = e
            if changed {
                // Explicit delete so cascade removes orphaned days + activities.
                for d in trip.days { modelContext.delete(d) }
                trip.days = makeDays(from: s, count: count)
            }
        } else {
            let trip = Trip(title: title, startDate: s, endDate: e)
            trip.days = makeDays(from: s, count: count)
            modelContext.insert(trip)
            try? modelContext.save()
            selectedTripID = trip.persistentModelID
        }
        selectedDayIndex = nil
        detailDayIndex = 0
        showingDetail = false
        try? modelContext.save()
    }

    private func makeDays(from start: Date, count: Int) -> [TripDay] {
        let cal = Calendar.current
        return (0..<count).map { i in
            TripDay(date: cal.date(byAdding: .day, value: i, to: start) ?? start)
        }
    }

    // MARK: - Seed (first launch)

    func seedIfNeeded() {
        let descriptor = FetchDescriptor<Trip>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }
        let tahiti = seedTahiti()
        let kyoto = seedKyoto()
        modelContext.insert(tahiti)
        modelContext.insert(kyoto)
        try? modelContext.save()
        selectedTripID = tahiti.persistentModelID
    }

    private struct SeedAct {
        let time: String
        let dur: Int
        let emoji: String
        let title: String
        let loc: String
        let notes: String
        let key: Bool
        let tag: String
    }

    private func mins(_ t: String) -> Int {
        let p = t.split(separator: ":")
        return (Int(p[0]) ?? 0) * 60 + (Int(p[1]) ?? 0)
    }

    private func noon(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date()
    }

    /// Tahiti 14-day itinerary, ported 1:1 from index.html v13.
    private func seedTahiti() -> Trip {
        let trip = Trip(
            title: "Tahiti Dive & Chill",
            startDate: noon(2027, 1, 10),
            endDate: noon(2027, 1, 23)
        )
        let rows: [(Int, [SeedAct])] = [
            (10, [
                SeedAct(time: "08:00", dur: 300, emoji: "✈️", title: "SFO → PPT", loc: "San Francisco Intl", notes: "UA115", key: true, tag: ""),
                SeedAct(time: "16:00", dur: 60, emoji: "🏨", title: "InterContinental Tahiti", loc: "Tahiti", notes: "Check-in", key: true, tag: "In"),
            ]),
            (11, [
                SeedAct(time: "08:30", dur: 180, emoji: "🤿", title: "Lagoon Scuba", loc: "Rangiroa", notes: "Manta ray cleaning station", key: false, tag: ""),
                SeedAct(time: "13:00", dur: 120, emoji: "🍹", title: "Beach Chill", loc: "Les Roulottes", notes: "", key: false, tag: ""),
            ]),
            (12, [
                SeedAct(time: "10:00", dur: 120, emoji: "🚗", title: "Island Drive", loc: "Tahiti Nui", notes: "", key: false, tag: ""),
            ]),
            (13, [
                SeedAct(time: "09:00", dur: 180, emoji: "🛥️", title: "Boat Tour", loc: "Moorea", notes: "", key: false, tag: ""),
                SeedAct(time: "14:00", dur: 120, emoji: "🤿", title: "Reef Dive", loc: "Tiahura", notes: "", key: false, tag: ""),
            ]),
            (14, [
                SeedAct(time: "10:00", dur: 240, emoji: "⛱️", title: "Beach Day", loc: "Temae Beach", notes: "", key: false, tag: ""),
            ]),
            (15, [
                SeedAct(time: "19:00", dur: 120, emoji: "🍽️", title: "Seafood Dinner", loc: "Papeete", notes: "", key: false, tag: ""),
            ]),
            (16, [
                SeedAct(time: "08:00", dur: 240, emoji: "🥾", title: "Volcano Hike", loc: "Mt. Aorai trailhead", notes: "", key: false, tag: ""),
            ]),
            (17, [
                SeedAct(time: "09:00", dur: 120, emoji: "🏄", title: "Surf Lesson", loc: "Taapuna", notes: "", key: false, tag: ""),
            ]),
            (18, [
                SeedAct(time: "15:00", dur: 90, emoji: "🍹", title: "Sunset Cocktails", loc: "Beach bar", notes: "", key: false, tag: ""),
            ]),
            (19, [
                SeedAct(time: "09:00", dur: 150, emoji: "🤿", title: "Manta Dive", loc: "Tiputa Pass", notes: "", key: false, tag: ""),
            ]),
            (20, [
                SeedAct(time: "11:00", dur: 120, emoji: "🛍️", title: "Market Shopping", loc: "Papeete Market", notes: "", key: false, tag: ""),
            ]),
            (21, [
                SeedAct(time: "10:00", dur: 180, emoji: "⛵", title: "Sail Trip", loc: "Lagoon", notes: "", key: false, tag: ""),
            ]),
            (22, [
                SeedAct(time: "18:00", dur: 90, emoji: "🥂", title: "Farewell Toast", loc: "Overwater bungalow deck", notes: "", key: false, tag: ""),
            ]),
            (23, [
                SeedAct(time: "11:00", dur: 60, emoji: "🏨", title: "Resort Checkout", loc: "Tahiti", notes: "", key: true, tag: "Out"),
                SeedAct(time: "22:00", dur: 240, emoji: "✈️", title: "PPT → SFO", loc: "Faa'a Intl", notes: "UA116", key: true, tag: ""),
            ]),
        ]
        trip.days = rows.map { dayNum, acts in
            let td = TripDay(date: noon(2027, 1, dayNum))
            td.activities = acts.map { a in
                Activity(
                    title: a.title,
                    emoji: a.emoji,
                    startMinutes: mins(a.time),
                    durationMinutes: a.dur,
                    location: a.loc,
                    notes: a.notes,
                    isKeyNode: a.key,
                    tag: a.tag
                )
            }
            return td
        }
        return trip
    }

    private func seedKyoto() -> Trip {
        let trip = Trip(
            title: "Kyoto Autumn Getaway",
            startDate: noon(2026, 11, 12),
            endDate: noon(2026, 11, 16)
        )
        var days: [TripDay] = []
        for i in 0..<5 {
            let td = TripDay(date: noon(2026, 11, 12 + i))
            if i == 0 {
                td.activities = [Activity(title: "Outbound flight", emoji: "✈️", startMinutes: 480, durationMinutes: 180, isKeyNode: true)]
            } else if i == 4 {
                td.activities = [Activity(title: "Return flight", emoji: "✈️", startMinutes: 1080, durationMinutes: 180, isKeyNode: true)]
            } else if i % 2 == 0 {
                td.activities = [Activity(title: "Explore", emoji: "📸", startMinutes: 600, durationMinutes: 120)]
            }
            days.append(td)
        }
        trip.days = days
        return trip
    }
}
