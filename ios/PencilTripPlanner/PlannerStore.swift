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
        let trips = (try? modelContext.fetch(descriptor)) ?? []
        if trips.isEmpty {
            let tahiti = seedTahiti()
            let kyoto = seedKyoto()
            modelContext.insert(tahiti)
            modelContext.insert(kyoto)
            try? modelContext.save()
            selectedTripID = tahiti.persistentModelID
        }
        // Real Europe itinerary (added 2026-11-12 for testing): insert once
        // if missing, so existing installs pick it up on next launch too.
        if !trips.map(\.title).contains("Europe Christmas Trip") {
            modelContext.insert(seedEurope())
            try? modelContext.save()
        }
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

    /// Europe Christmas 2026 — the user's real Prague → Vienna → Budapest
    /// itinerary (flights PNR 268NIZ, trains RJ 253 / EC 145), mirrored 1:1
    /// from the EUROPE data in index.html. Times are local at each stop.
    private func seedEurope() -> Trip {
        let trip = Trip(
            title: "Europe Christmas Trip",
            startDate: noon(2026, 12, 12),
            endDate: noon(2026, 12, 24)
        )
        let rows: [(Int, [SeedAct])] = [
            (12, [
                SeedAct(time: "19:25", dur: 240, emoji: "✈️", title: "SFO → PRG", loc: "San Francisco Intl", notes: "LX39 + LX1488 · PNR 268NIZ", key: true, tag: ""),
            ]),
            (13, [
                SeedAct(time: "19:10", dur: 50, emoji: "✈️", title: "Arrive Prague", loc: "Václav Havel Airport", notes: "LX1488 lands 19:10", key: true, tag: ""),
                SeedAct(time: "20:30", dur: 60, emoji: "🏨", title: "SOHO Old Town", loc: "Karoliny Světlé 299/12, Praha 1", notes: "Check-in · Conf HMMWM9E9K3", key: true, tag: "In"),
            ]),
            (14, [
                SeedAct(time: "07:30", dur: 60, emoji: "📸", title: "Charles Bridge at Sunrise", loc: "Karlův most", notes: "Solo shoot · Hasselblad", key: false, tag: ""),
                SeedAct(time: "08:30", dur: 60, emoji: "📸", title: "Old Town Square Empty Shots", loc: "Staroměstské náměstí", notes: "", key: false, tag: ""),
                SeedAct(time: "09:30", dur: 30, emoji: "🎟️", title: "Philharmonic Restkarten", loc: "Back at the apartment", notes: "Vienna Philharmonic 12/19 15:30 · 3 seats", key: false, tag: ""),
                SeedAct(time: "10:30", dur: 240, emoji: "🎄", title: "Old Town & Christmas Market", loc: "Old Town", notes: "", key: false, tag: ""),
                SeedAct(time: "15:40", dur: 50, emoji: "📸", title: "Powder Tower Sunset", loc: "Prašná brána", notes: "", key: false, tag: ""),
            ]),
            (15, [
                SeedAct(time: "07:30", dur: 90, emoji: "📸", title: "Smetanovo nábřeží Shoot", loc: "Smetanovo nábřeží", notes: "Riverbank under the bridge · on the bridge if foggy", key: false, tag: ""),
                SeedAct(time: "09:30", dur: 60, emoji: "📸", title: "Lesser Town Tram Shoot", loc: "Malostranské náměstí", notes: "", key: false, tag: ""),
                SeedAct(time: "11:00", dur: 240, emoji: "🏰", title: "Prague Castle & St. Vitus", loc: "Pražský hrad", notes: "", key: false, tag: ""),
                SeedAct(time: "15:30", dur: 45, emoji: "📸", title: "Park Cihelná Sunset", loc: "Park Cihelná", notes: "", key: false, tag: ""),
            ]),
            (16, [
                SeedAct(time: "07:30", dur: 90, emoji: "📸", title: "Letná Park Sunrise", loc: "Letenské sady", notes: "Bridge panorama at sunrise", key: false, tag: ""),
                SeedAct(time: "10:30", dur: 180, emoji: "🏛️", title: "Jewish Quarter & Pařížská", loc: "Josefov", notes: "", key: false, tag: ""),
                SeedAct(time: "15:40", dur: 50, emoji: "📸", title: "Astronomical Tower at Dusk", loc: "Staroměstská radnice", notes: "", key: false, tag: ""),
            ]),
            (17, [
                SeedAct(time: "07:30", dur: 90, emoji: "📸", title: "Charles Bridge Final Shoot", loc: "Karlův most", notes: "", key: false, tag: ""),
                SeedAct(time: "10:30", dur: 240, emoji: "☕", title: "Free Day · Pack", loc: "Old Town", notes: "", key: false, tag: ""),
                SeedAct(time: "15:50", dur: 40, emoji: "🕯️", title: "Lamp Lighting Ceremony", loc: "Křižovnické náměstí", notes: "Gas lamps lit from 16:05", key: false, tag: ""),
            ]),
            (18, [
                SeedAct(time: "07:30", dur: 60, emoji: "📸", title: "Petřín Hill Sunrise", loc: "Petřínské sady", notes: "Back by 09:00", key: false, tag: ""),
                SeedAct(time: "10:00", dur: 30, emoji: "🏨", title: "SOHO Old Town Checkout", loc: "Praha 1", notes: "", key: true, tag: "Out"),
                SeedAct(time: "12:36", dur: 253, emoji: "🚆", title: "RJ 253 → Wien Hbf", loc: "Praha hl.n.", notes: "Car 368 · Seat 31 · ČD 205096 228 00", key: true, tag: ""),
                SeedAct(time: "17:30", dur: 60, emoji: "🏨", title: "Andreas Apartment", loc: "Südtiroler Pl. 9/20, 1040 Wien", notes: "Check-in · Conf HMATQ9YW3X", key: true, tag: "In"),
            ]),
            (19, [
                SeedAct(time: "10:00", dur: 180, emoji: "🛍️", title: "Chanel & Miu Miu", loc: "Goldenes Quartier · Tuchlauben", notes: "Chanel Tuchlauben 1 · Miu Miu Tuchlauben 7 · 10:00–18:00", key: false, tag: ""),
                SeedAct(time: "15:30", dur: 150, emoji: "🎟️", title: "Vienna Philharmonic", loc: "Musikverein", notes: "Restkarten · 3 seats", key: false, tag: ""),
            ]),
            (20, [
                SeedAct(time: "11:30", dur: 30, emoji: "🏨", title: "Andreas Apartment Checkout", loc: "Favoriten, Wien", notes: "", key: true, tag: "Out"),
                SeedAct(time: "12:42", dur: 173, emoji: "🚆", title: "EC 145 → Budapest-Keleti", loc: "Wien Hbf", notes: "First class · Car 422 · Seat 16 · MÁV 2404247131", key: true, tag: ""),
                SeedAct(time: "16:30", dur: 60, emoji: "🏨", title: "Parliament Apartment by Mazi", loc: "Alkotmány u. 21, 1054 Budapest", notes: "Check-in · Conf HM2FN8D4SP", key: true, tag: "In"),
            ]),
            (21, [
                SeedAct(time: "10:00", dur: 180, emoji: "🏛️", title: "Parliament & Kossuth Square", loc: "Kossuth Lajos tér", notes: "", key: false, tag: ""),
                SeedAct(time: "14:00", dur: 120, emoji: "🎄", title: "Christmas Market", loc: "Vörösmarty tér", notes: "", key: false, tag: ""),
            ]),
            (22, [
                SeedAct(time: "10:00", dur: 300, emoji: "🛍️", title: "Andrássy Avenue Shopping", loc: "Andrássy út", notes: "LV · Gucci · Prada · Burberry · 10:00–19:00", key: false, tag: ""),
            ]),
            (23, [
                SeedAct(time: "10:00", dur: 240, emoji: "🏰", title: "Castle Hill · Fisherman's Bastion", loc: "Buda Castle", notes: "", key: false, tag: ""),
            ]),
            (24, [
                SeedAct(time: "11:00", dur: 60, emoji: "🏨", title: "Parliament Apartment Checkout", loc: "Budapest", notes: "", key: true, tag: "Out"),
                SeedAct(time: "13:30", dur: 240, emoji: "✈️", title: "BUD → SFO", loc: "Budapest Airport", notes: "LH1677 + LH458 · arrive SFO 19:35", key: true, tag: ""),
            ]),
        ]
        trip.days = rows.map { dayNum, acts in
            let td = TripDay(date: noon(2026, 12, dayNum))
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
