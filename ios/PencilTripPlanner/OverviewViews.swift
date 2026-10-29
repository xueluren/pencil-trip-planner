import SwiftUI

// MARK: - Header (menu | tappable title + flourish + subtitle | edit)
//
// v18/v20: tapping the title returns to the trip top (overview) or
// closes the detail view (detail). The callback decides per context.

struct HeaderView: View {
    @Environment(PlannerStore.self) private var store
    let trip: Trip
    var onTitleTap: () -> Void = {}

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

            Button(action: onTitleTap) {
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
            }
            .buttonStyle(.plain)

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
        .background(Color.white)
        .overlay(
            Rectangle().frame(height: 2).foregroundColor(Theme.ink),
            alignment: .bottom
        )
    }
}

// MARK: - Overview: month label + 7-column grid + scrolling wave footer

/// Reports each day card's frame in the overview scroll space so the
/// month label can follow the first visible card (HTML v17: #cal-month).
private struct CardFrame: Equatable {
    let date: Date
    let frame: CGRect
}

private struct CardFrameKey: PreferenceKey {
    static var defaultValue: [CardFrame] = []
    static func reduce(value: inout [CardFrame], nextValue: () -> [CardFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct OverviewView: View {
    @Environment(PlannerStore.self) private var store
    let trip: Trip

    @State private var monthLabel: String = ""

    /// Wave footer height incl. its vertical padding (HTML v19: #overview-end).
    private let waveH: CGFloat = 30

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HeaderView(trip: trip, onTitleTap: {
                    withAnimation {
                        proxy.scrollTo("gridTop", anchor: .top)
                    }
                })

                // Month label, top-left, follows the scroll
                // (HTML v17 #cal-head: month label sits ABOVE the weekday row).
                Text(monthLabel)
                    .font(Theme.font(17, .heavy))
                    .foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .background(Color.white)

                WeekdayRow()

                GeometryReader { geo in
                    let days = trip.sortedDays
                    let rows = max(1, Int(ceil(Double(days.count) / 7.0)))
                    // HTML v19: grid-auto-rows: minmax(200px, 1fr) — short trips
                    // stretch to fill the screen (minus the wave footer), long
                    // trips scroll with the wave at the end.
                    let rowH = max((geo.size.height - waveH) / CGFloat(rows), 200)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
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
                            .id("gridTop")

                            // Hand-drawn end mark (HTML: #overview-end wavy line)
                            WavyLine()
                                .stroke(Theme.waveGray, lineWidth: 2.2)
                                .frame(width: 150, height: 14)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.white)
                        }
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .coordinateSpace(name: "overviewScroll")
                    .onPreferenceChange(CardFrameKey.self) { frames in
                        updateMonth(from: frames)
                    }
                }
            }
            .background(Color.white)
            .onAppear {
                monthLabel = monthText(trip.startDate)
            }
        }
    }

    /// First card whose bottom is still below the scroll top decides the label.
    private func updateMonth(from frames: [CardFrame]) {
        let visible = frames
            .sorted { $0.frame.minY < $1.frame.minY }
            .first { $0.frame.maxY > 2 }
        if let d = visible?.date {
            let t = monthText(d)
            if t != monthLabel { monthLabel = t }
        }
    }
}

private func monthText(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMMM yyyy"
    return f.string(from: date)
}

// MARK: - Day card: gray date head + 3 time bands with proportional emoji

/// Time bands (HTML v14/v15): AM 6–12 / PM 12–18 / Eve 18–24.
/// Bands share the card body equally; emoji sit at their time fraction
/// *within* their band, clamped so they never leave it.
private let bandRanges = [(360, 720), (720, 1080), (1080, 1440)]

private func bandIndex(for minutes: Int) -> Int {
    minutes < 720 ? 0 : (minutes < 1080 ? 1 : 2)
}

struct DayCardView: View {
    let day: TripDay
    let height: CGFloat
    let selected: Bool

    private let bandColors: [Color] = [Theme.bandAM, Theme.bandPM, Theme.bandEve]

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

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { b in
                    bandView(b)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(bandColors[b])
                }
            }
        }
        .frame(height: height)
        .background(Color.white)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CardFrameKey.self,
                    value: [CardFrame(
                        date: day.date,
                        frame: geo.frame(in: .named("overviewScroll"))
                    )]
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Theme.ink : Theme.cardBorder, lineWidth: selected ? 2 : 1)
        )
    }

    private func bandView(_ b: Int) -> some View {
        GeometryReader { geo in
            let (s, e) = bandRanges[b]
            let acts = day.sortedActivities.filter { bandIndex(for: $0.startMinutes) == b }
            ZStack {
                ForEach(acts) { act in
                    let frac = CGFloat(max(0, min(act.startMinutes - s, e - s))) / CGFloat(e - s)
                    let margin: CGFloat = act.isKeyNode ? 28 : 13
                    let h = geo.size.height
                    let y = min(max(frac * h, margin), max(h - margin, margin))
                    activityDot(act)
                        .position(x: geo.size.width / 2, y: y)
                }
            }
        }
    }

    /// Emoji centered at its time-of-day position (HTML v13 clamp behavior
    /// for the whole body is now per-band: bands never overlap).
    private func activityDot(_ act: Activity) -> some View {
        Group {
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
    }
}
