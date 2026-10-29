import SwiftUI

// MARK: - Header (menu | title + flourish + subtitle | edit)

struct HeaderView: View {
    @Environment(PlannerStore.self) private var store
    let trip: Trip

    var body: some View {
        HStack {
            Button {
                store.showingSidebar = true
            } label: {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(Theme.ink)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 0) {
                Text(trip.title)
                    .font(Theme.font(21, .heavy))
                    .foregroundColor(Theme.ink)
                WavyLine()
                    .stroke(Theme.gray1, lineWidth: 2)
                    .frame(width: 118, height: 9)
                    .padding(.top, 2)
                Text("\(fmtDayMonth(trip.startDate)) - \(fmtDayMonthYear(trip.endDate)) • \(trip.sortedDays.count) Days")
                    .font(Theme.font(13, .semibold))
                    .foregroundColor(Theme.gray1)
                    .padding(.top, 4)
            }

            Spacer()

            Button {
                store.editTrip(trip)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(
            Rectangle().frame(height: 2.5).foregroundColor(Theme.ink),
            alignment: .bottom
        )
    }
}

// MARK: - Weekday row

struct WeekdayRow: View {
    private let names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(names.indices, id: \.self) { i in
                Text(names[i])
                    .font(Theme.font(11, .heavy))
                    .foregroundColor((i == 0 || i == 6) ? Theme.gray3 : Theme.ink)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Theme.weekdayBG)
        .overlay(
            Rectangle().frame(height: 2).foregroundColor(Theme.ink),
            alignment: .bottom
        )
    }
}

// MARK: - Overview: 7-column grid that fills the screen

struct OverviewView: View {
    @Environment(PlannerStore.self) private var store
    let trip: Trip

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(trip: trip)
            WeekdayRow()

            GeometryReader { geo in
                let days = trip.sortedDays
                let rows = max(1, Int(ceil(Double(days.count) / 7.0)))
                // Rows share the available height equally (HTML: grid-auto-rows: 1fr),
                // so shorter/longer trips also stretch to fill the screen.
                let rowH = max(geo.size.height / CGFloat(rows), 150)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                        spacing: 6
                    ) {
                        ForEach(days.indices, id: \.self) { i in
                            DayCardView(
                                day: days[i],
                                height: rowH,
                                selected: store.selectedDayIndex == i
                            )
                            .onTapGesture {
                                store.openDay(days[i], in: trip)
                            }
                        }
                    }
                    .padding(6)
                }
            }

            // Hand-drawn end mark (HTML: #overview-end wavy line)
            WavyLine()
                .stroke(Theme.gray2, lineWidth: 2.2)
                .frame(width: 150, height: 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.white)
        }
        .background(Color.white)
    }
}

// MARK: - Day card: gray date head + time-proportional emoji dots

struct DayCardView: View {
    let day: TripDay
    let height: CGFloat
    let selected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Calendar.current.component(.day, from: day.date))")
                .font(Theme.font(19, .heavy))
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.dateHeadBG)
                .overlay(
                    Rectangle().frame(height: 2).foregroundColor(Theme.ink),
                    alignment: .bottom
                )

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    ForEach(day.sortedActivities) { act in
                        activityDot(act, bodyWidth: w, bodyHeight: h)
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .frame(height: height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Theme.ink : Theme.cardBorder, lineWidth: selected ? 2 : 1)
        )
    }

    /// Emoji centered at its time-of-day position, clamped so it never
    /// leaves the card (HTML v13: clamp(margin, pct, 100% - margin)).
    private func activityDot(_ act: Activity, bodyWidth w: CGFloat, bodyHeight h: CGFloat) -> some View {
        let pct = CGFloat(act.startMinutes) / 1440.0
        let margin: CGFloat = act.isKeyNode ? 32 : 15
        let y = min(max(pct * h, margin), max(h - margin, margin))
        return Group {
            if act.isKeyNode {
                VStack(spacing: 1) {
                    Text(act.emoji)
                        .font(.system(size: 24))
                    if !act.tag.isEmpty {
                        Text(act.tag)
                            .font(Theme.font(12, .heavy))
                            .foregroundColor(Theme.ink)
                    }
                }
                .padding(7)
                .background(
                    SketchCircle()
                        .stroke(Theme.ink, lineWidth: 2.5)
                )
            } else {
                Text(act.emoji)
                    .font(.system(size: 25))
            }
        }
        .position(x: w / 2, y: y)
    }
}
