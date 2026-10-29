import SwiftUI

// MARK: - Detail: day strip + 24h timeline (v20: no drag handle;
// tap the title to return to the overview)

struct DetailView: View {
    @Environment(PlannerStore.self) private var store
    let trip: Trip

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(trip: trip, onTitleTap: {
                store.closeDetail()
            })

            DayStripView(trip: trip)
                .background(Color.white)
                .overlay(
                    Rectangle().frame(height: 2.5).foregroundColor(Theme.ink),
                    alignment: .bottom
                )

            TimelineView(trip: trip)
        }
        .background(Theme.paper)
    }
}

// MARK: - Horizontal day strip (selected day = black card)

struct DayStripView: View {
    @Environment(PlannerStore.self) private var store
    let trip: Trip

    var body: some View {
        let days = trip.sortedDays
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days.indices, id: \.self) { i in
                        let d = days[i].date
                        let sel = store.detailDayIndex == i
                        VStack(spacing: 2) {
                            Text(weekdayShort(d))
                                .font(Theme.font(11, .semibold))
                                .foregroundColor(sel ? Theme.gray3 : Theme.gray1)
                            Text("\(Calendar.current.component(.day, from: d))")
                                .font(Theme.font(20, .heavy))
                        }
                        .foregroundColor(sel ? .white : Theme.ink)
                        .frame(width: 62)
                        .padding(.vertical, 8)
                        .background(sel ? Theme.ink : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.ink, lineWidth: 2)
                        )
                        .id(i)
                        .onTapGesture {
                            store.pickStripDay(i)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onAppear {
                proxy.scrollTo(store.detailDayIndex, anchor: .center)
            }
            .onChange(of: store.detailDayIndex) { _, v in
                withAnimation {
                    proxy.scrollTo(v, anchor: .center)
                }
            }
        }
    }
}

// MARK: - 24h timeline (64pt/hour, event blocks span their duration)

struct TimelineView: View {
    @Environment(PlannerStore.self) private var store
    let trip: Trip

    private let hourH: CGFloat = 64

    var body: some View {
        let days = trip.sortedDays
        // Trip always has >= 1 day; clamp defensively.
        let day = days[min(max(store.detailDayIndex, 0), days.count - 1)]

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        HStack(spacing: 0) {
                            Text(String(format: "%02d:00", h))
                                .font(Theme.font(12, .semibold))
                                .foregroundColor(Theme.gray3)
                                .frame(width: 58, alignment: .trailing)
                                .padding(.trailing, 10)
                                .offset(y: -9)
                            Spacer()
                        }
                        .frame(height: hourH)
                        .overlay(
                            Rectangle().frame(height: 1).foregroundColor(Theme.hourLine),
                            alignment: .bottom
                        )
                        .id(h)
                        .onTapGesture {
                            // Tap an empty hour -> new event starting at that hour.
                            store.newEvent(presetStartMinutes: h * 60, in: day)
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(day.sortedActivities) { act in
                            EventBlock(act: act)
                                .frame(height: max(CGFloat(act.durationMinutes) / 60 * hourH, 48))
                                .offset(y: CGFloat(act.startMinutes) / 60 * hourH)
                                .onTapGesture {
                                    store.editEvent(act, in: day)
                                }
                        }
                    }
                    .padding(.leading, 66)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .onAppear {
                // HTML scrolls to ~07:00 on open.
                proxy.scrollTo(7, anchor: .top)
            }
        }
    }
}

// MARK: - Event block

struct EventBlock: View {
    let act: Activity

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(act.emoji)
                    .font(.system(size: 15))
                Text(act.title)
                    .font(Theme.font(15, .heavy))
                    .lineLimit(1)
            }
            Text(subtitle)
                .font(Theme.font(12, .semibold))
                .foregroundColor(Theme.gray1)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.ink, lineWidth: 2)
        )
        .shadow(color: Theme.ink.opacity(0.15), radius: 0, x: 1.5, y: 1.5)
    }

    private var subtitle: String {
        var s = "\(fmtTime(act.startMinutes)) • \(fmtDur(act.durationMinutes))"
        if !act.location.isEmpty { s += " • \(act.location)" }
        return s
    }
}
