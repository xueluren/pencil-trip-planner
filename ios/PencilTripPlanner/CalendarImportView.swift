import SwiftUI
import SwiftData

// MARK: - Import system-calendar events into the trip grid (Phase 3)
//
// Pick a date range (defaults to the current trip), load the events,
// tick the ones to import. Each event lands on the trip day matching its
// date; events outside the trip are shown disabled. Imported rows are NOT
// auto-synced back (they already live in the calendar) — link them later
// with the "Sync to system calendar" toggle in the event editor.

struct CalendarImportView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    struct ImportRow: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let location: String
        let inTrip: Bool
        var selected: Bool
        var emoji: String
    }

    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var rows: [ImportRow] = []
    @State private var isLoading = false
    @State private var loaded = false
    @State private var errorText: String?
    @State private var emojiRow: Int?

    init(trip: Trip) {
        self.trip = trip
        let cal = Calendar.current
        _fromDate = State(initialValue: cal.startOfDay(for: trip.startDate))
        _toDate = State(initialValue: cal.startOfDay(for: trip.endDate))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack {
                    Text("Import from Calendar")
                        .font(Theme.font(24, .heavy))
                        .foregroundColor(Theme.ink)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("✕")
                            .font(Theme.font(24, .heavy))
                            .foregroundColor(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 16)

                // Date range
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From")
                            .font(Theme.font(12, .heavy))
                            .foregroundColor(Theme.ink)
                        DatePicker("", selection: $fromDate, displayedComponents: .date)
                            .labelsHidden()
                            .padding(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("To")
                            .font(Theme.font(12, .heavy))
                            .foregroundColor(Theme.ink)
                        DatePicker("", selection: $toDate, displayedComponents: .date)
                            .labelsHidden()
                            .padding(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 12)

                Button {
                    load()
                } label: {
                    Text(isLoading ? "Loading…" : "Load events")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SketchButtonStyle(dark: true))
                .disabled(isLoading)
                .padding(.bottom, 12)

                if let err = errorText {
                    Text(err)
                        .font(Theme.font(13, .semibold))
                        .foregroundColor(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                if loaded && rows.isEmpty {
                    Text("No events in this range.")
                        .font(Theme.font(15, .semibold))
                        .foregroundColor(Theme.gray1)
                        .padding(.vertical, 16)
                }

                VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { i in
                        let row = rows[i]
                        HStack(spacing: 10) {
                            Button {
                                if row.inTrip { rows[i].selected.toggle() }
                            } label: {
                                Image(systemName: row.selected && row.inTrip
                                      ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundColor(row.inTrip ? Theme.ink : Theme.gray3)
                            }
                            .buttonStyle(.plain)
                            .disabled(!row.inTrip)

                            Button {
                                emojiRow = i
                            } label: {
                                Text(row.emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Theme.cardBorder, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(Theme.font(15, .heavy))
                                    .foregroundColor(Theme.ink)
                                    .lineLimit(1)
                                Text("\(fmtDayMonth(row.start)) \(fmtTime(minutesOfDay(row.start))) – \(fmtTime(minutesOfDay(row.end)))")
                                    .font(Theme.font(12, .semibold))
                                    .foregroundColor(Theme.gray1)
                                if !row.location.isEmpty {
                                    Text(row.location)
                                        .font(Theme.font(12, .semibold))
                                        .foregroundColor(Theme.gray1)
                                        .lineLimit(1)
                                }
                                if !row.inTrip {
                                    Text("Outside this trip — can't import")
                                        .font(Theme.font(12, .semibold))
                                        .foregroundColor(Theme.danger)
                                }
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(row.selected && row.inTrip ? Theme.ink : Theme.cardBorder,
                                        lineWidth: row.selected && row.inTrip ? 2 : 1)
                        )
                        .opacity(row.inTrip ? 1 : 0.55)
                    }
                }
                .padding(.bottom, 16)

                if loaded && rows.contains(where: { $0.inTrip }) {
                    Button {
                        importSelected()
                    } label: {
                        Text("Import \(selectedCount) event\(selectedCount == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SketchButtonStyle(dark: true))
                    .disabled(selectedCount == 0)
                }
            }
            .padding(22)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18).stroke(Theme.ink, lineWidth: 3)
                )
                .shadow(color: Theme.ink.opacity(0.85), radius: 0, x: 6, y: 6)
                .padding(20)
        )
        .sheet(isPresented: Binding(
            get: { emojiRow != nil },
            set: { if !$0 { emojiRow = nil } }
        )) {
            if let i = emojiRow, rows.indices.contains(i) {
                EmojiPickerView(selected: Binding(
                    get: { rows[i].emoji },
                    set: { rows[i].emoji = $0 }
                ))
            }
        }
        .onAppear {
            if !loaded { load() }
        }
    }

    private var selectedCount: Int {
        rows.filter { $0.selected && $0.inTrip }.count
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            let granted = await store.calendarSync.requestAccess()
            guard granted else {
                isLoading = false
                errorText = "Calendar access is off. Enable it in Settings → Privacy & Security → Calendars."
                return
            }
            do {
                let cal = Calendar.current
                let from = cal.startOfDay(for: fromDate)
                let to = cal.date(byAdding: .day, value: 1,
                                  to: cal.startOfDay(for: toDate)) ?? toDate
                let events = try await store.calendarSync.fetchEvents(from: from, to: to)
                let days = trip.sortedDays
                rows = events.map { ev in
                    let inTrip = days.contains {
                        cal.isDate($0.date, inSameDayAs: ev.startDate)
                    }
                    return ImportRow(
                        id: ev.id,
                        title: ev.title,
                        start: ev.startDate,
                        end: ev.endDate,
                        location: ev.location ?? "",
                        inTrip: inTrip,
                        selected: inTrip,
                        emoji: "📌"
                    )
                }
                loaded = true
            } catch {
                errorText = "Couldn't read calendar events. Try again."
            }
            isLoading = false
        }
    }

    private func importSelected() {
        let items = rows
            .filter { $0.selected && $0.inTrip }
            .map {
                CalendarImportItem(
                    title: $0.title,
                    startDate: $0.start,
                    endDate: $0.end,
                    location: $0.location,
                    emoji: $0.emoji
                )
            }
        store.importCalendarEvents(items, into: trip)
        dismiss()
    }
}
