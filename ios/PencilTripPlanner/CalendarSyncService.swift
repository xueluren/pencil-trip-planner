import Foundation
import EventKit

// MARK: - EventKit wrapper (Phase 3: two-way calendar sync, all on-device)
//
// - requestAccess(): asks for full calendar access (iOS 17+ API).
// - syncActivity(_:on:): writes an Activity as an EKEvent; creates a new
//   event or updates the existing one when the activity already carries a
//   calendarEventIdentifier. Returns the event identifier to store back.
// - removeFromCalendar(identifier:): deletes the linked system event.
// - fetchEvents(from:to:): reads system events in a range for import.
// All-day events are skipped (a 24h block makes no sense in the grid).

@MainActor
final class CalendarSyncService {
    enum SyncError: LocalizedError {
        case accessDenied
        case noCalendar
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "Calendar access was not granted."
            case .noCalendar: return "No writable calendar found on this device."
            case .saveFailed: return "Could not save the event to the calendar."
            }
        }
    }

    struct ImportableEvent: Identifiable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
    }

    private let eventStore = EKEventStore()

    /// True when we already hold full access; otherwise prompts the user once.
    func requestAccess() async -> Bool {
        let current = EKEventStore.authorizationStatus(for: .event)
        if current == .fullAccess { return true }
        guard current == .notDetermined else { return false }
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// Write (or update) the activity in the system calendar.
    /// - Returns: the EKEvent identifier; store it on the activity.
    func syncActivity(_ activity: Activity, on day: TripDay) async throws -> String {
        guard await requestAccess() else { throw SyncError.accessDenied }

        let event: EKEvent
        if let id = activity.calendarEventIdentifier,
           let existing = eventStore.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
        }

        event.title = "\(activity.emoji) \(activity.title)"
        let cal = Calendar.current
        let start = cal.date(
            byAdding: .minute, value: activity.startMinutes,
            to: cal.startOfDay(for: day.date)
        ) ?? day.date
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(activity.durationMinutes * 60))
        event.location = activity.location.isEmpty ? nil : activity.location

        var noteBits: [String] = []
        if !activity.tag.isEmpty { noteBits.append("[\(activity.tag)]") }
        if !activity.notes.isEmpty { noteBits.append(activity.notes) }
        event.notes = noteBits.isEmpty ? nil : noteBits.joined(separator: "\n")

        event.calendar = eventStore.defaultCalendarForNewEvents
            ?? eventStore.calendars(for: .event).first
        guard event.calendar != nil else { throw SyncError.noCalendar }

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            throw SyncError.saveFailed
        }
        return event.eventIdentifier
    }

    /// Delete the linked system event. No-op when the identifier is stale.
    func removeFromCalendar(identifier: String) throws {
        if let event = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(event, span: .thisEvent)
        }
    }

    /// System events in [from, to) for the import flow. Skips all-day events.
    func fetchEvents(from: Date, to: Date) async throws -> [ImportableEvent] {
        guard await requestAccess() else { throw SyncError.accessDenied }
        let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: nil)
        return eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { ev in
                ImportableEvent(
                    id: ev.eventIdentifier,
                    title: ev.title ?? "(No title)",
                    startDate: ev.startDate ?? from,
                    endDate: ev.endDate ?? ev.startDate ?? from,
                    location: ev.location
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }
}
