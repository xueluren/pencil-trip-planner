import SwiftUI
import SwiftData

// MARK: - New / Edit Event sheet

struct EventEditorView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let context: EventSheetContext

    @State private var title = ""
    @State private var emoji = "📌"
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var location = ""
    @State private var notes = ""
    @State private var showEmojiPicker = false
    /// Phase 3: write-through to the system calendar on save.
    @State private var syncToCalendar = false
    @State private var previouslySynced = false

    private var isEditing: Bool { context.activityID != nil }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack {
                    Text(isEditing ? "Edit Event" : "New Event")
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

                TextField("Add title...", text: $title)
                    .font(Theme.font(16))
                    .padding(13)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                    )
                    .padding(.bottom, 14)

                HStack(spacing: 10) {
                    Button {
                        showEmojiPicker = true
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(width: 64, height: 64)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    Text("Tap to change icon")
                        .font(Theme.font(15, .semibold))
                        .foregroundColor(Theme.gray2)
                    Spacer()
                }
                .padding(.bottom, 14)

                HStack(spacing: 10) {
                    Text("🕐")
                        .font(.system(size: 22))
                    DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                        )
                    Text("to")
                        .font(Theme.font(15, .semibold))
                        .foregroundColor(Theme.gray2)
                    DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                        )
                }
                .padding(.bottom, 14)

                HStack(spacing: 10) {
                    Text("📍")
                        .font(.system(size: 22))
                    TextField("Add location", text: $location)
                        .font(Theme.font(16))
                        .padding(13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                        )
                }
                .padding(.bottom, 14)

                HStack(alignment: .top, spacing: 10) {
                    Text("📝")
                        .font(.system(size: 22))
                    TextEditor(text: $notes)
                        .font(Theme.font(16))
                        .frame(minHeight: 96)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                        )
                }
                .padding(.bottom, 20)

                // Phase 3: system-calendar sync toggle
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("📅")
                            .font(.system(size: 22))
                        Toggle("Sync to system calendar", isOn: $syncToCalendar)
                            .font(Theme.font(15, .heavy))
                            .foregroundColor(Theme.ink)
                            .tint(Theme.ink)
                    }
                    if previouslySynced {
                        Text("Linked — turning this off removes the event from your calendar.")
                            .font(Theme.font(12, .semibold))
                            .foregroundColor(Theme.gray1)
                            .padding(.leading, 32)
                    }
                }
                .padding(.bottom, 20)

                HStack(spacing: 10) {
                    if isEditing {
                        Button {
                            if let aid = context.activityID {
                                store.deleteEvent(id: aid)
                            }
                            dismiss()
                        } label: {
                            Text("Delete")
                                .font(Theme.font(15, .heavy))
                                .foregroundColor(Theme.danger)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    } else {
                        Spacer()
                    }
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(SketchButtonStyle())
                    Button("Save", action: save)
                        .buttonStyle(SketchButtonStyle(dark: true))
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
        .onAppear(perform: load)
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerView(selected: $emoji)
        }
    }

    private func load() {
        guard let day = store.modelContext.model(for: context.dayID) as? TripDay else { return }
        if let aid = context.activityID,
           let act = store.modelContext.model(for: aid) as? Activity {
            title = act.title
            emoji = act.emoji
            location = act.location
            notes = act.notes
            startDate = dateOn(day.date, minutes: act.startMinutes)
            endDate = dateOn(day.date, minutes: act.endMinutes)
            // Phase 3: reflect the existing calendar link in the toggle.
            let linked = act.calendarEventIdentifier != nil
            syncToCalendar = linked
            previouslySynced = linked
        } else {
            startDate = dateOn(day.date, minutes: context.presetStartMinutes)
            endDate = dateOn(day.date, minutes: context.presetStartMinutes + 60)
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let sm = minutesOfDay(startDate)
        let em = minutesOfDay(endDate)
        var dur = em - sm
        if dur <= 0 { dur += 24 * 60 }
        var draft = EventDraft(
            dayID: context.dayID,
            editingActivityID: context.activityID,
            title: t,
            emoji: emoji,
            startMinutes: sm,
            durationMinutes: dur,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        draft.syncToCalendar = syncToCalendar
        guard let act = store.saveEvent(draft) else { dismiss(); return }
        dismiss()
        // Phase 3: calendar write-through / unlink after the local save.
        Task { @MainActor in
            if syncToCalendar {
                await store.syncActivityToCalendar(act)
            } else if previouslySynced {
                await store.removeActivityFromCalendar(act)
            }
        }
    }
}

// MARK: - Emoji picker sheet

struct EmojiPickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Icon")
                    .font(Theme.font(15, .heavy))
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
            .padding(.bottom, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 6) {
                ForEach(PlannerStore.emojis, id: \.self) { e in
                    Button {
                        selected = e
                        dismiss()
                    } label: {
                        Text(e)
                            .font(.system(size: 26))
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(selected == e ? Theme.dateHeadBG : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(16)
        .presentationDetents([.medium])
    }
}

// MARK: - New / Edit Trip sheet

struct TripEditorView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let context: TripSheetContext

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(context.isCreate ? "New Trip" : "Edit Trip Details")
                    .font(Theme.font(19, .heavy))
                    .foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .overlay(
                        Rectangle().frame(height: 2).foregroundColor(Theme.ink),
                        alignment: .bottom
                    )
                    .padding(.bottom, 14)

                Text("Trip Title")
                    .font(Theme.font(12, .heavy))
                    .foregroundColor(Theme.ink)
                    .padding(.bottom, 4)
                TextField("", text: $title)
                    .font(Theme.font(16))
                    .padding(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                    )
                    .padding(.bottom, 12)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Date")
                            .font(Theme.font(12, .heavy))
                            .foregroundColor(Theme.ink)
                        DatePicker("", selection: $start, displayedComponents: .date)
                            .labelsHidden()
                            .padding(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("End Date")
                            .font(Theme.font(12, .heavy))
                            .foregroundColor(Theme.ink)
                        DatePicker("", selection: $end, displayedComponents: .date)
                            .labelsHidden()
                            .padding(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2)
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(SketchButtonStyle())
                    Button("Save", action: save)
                        .buttonStyle(SketchButtonStyle(dark: true))
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
        .onAppear(perform: load)
    }

    private func load() {
        if let eid = context.editingTripID,
           let trip = store.modelContext.model(for: eid) as? Trip {
            title = trip.title
            start = trip.startDate
            end = trip.endDate
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.saveTrip(title: t, start: start, end: end, editingID: context.editingTripID)
        dismiss()
    }
}
