import SwiftUI
import SwiftData

// MARK: - Root: sidebar overlay + overview/detail/empty + sheets

struct ContentView: View {
    @Environment(PlannerStore.self) private var store
    @Query(sort: \Trip.createdAt, order: .forward) private var trips: [Trip]

    var body: some View {
        @Bindable var store = store

        ZStack {
            Group {
                if let trip = store.currentTrip(from: trips) {
                    if store.showingDetail {
                        DetailView(trip: trip)
                    } else {
                        OverviewView(trip: trip)
                    }
                } else {
                    EmptyStateView()
                }
            }

            if store.showingSidebar {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.showingSidebar = false
                    }
                HStack(spacing: 0) {
                    SidebarView(trips: trips)
                    Spacer()
                }
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: store.showingSidebar)
        .sheet(item: $store.eventSheet) { ctx in
            EventEditorView(context: ctx)
        }
        .sheet(item: $store.tripSheet) { ctx in
            TripEditorView(context: ctx)
        }
    }
}

// MARK: - Sidebar (trip list + New Trip)

struct SidebarView: View {
    @Environment(PlannerStore.self) private var store
    let trips: [Trip]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("My Trips")
                    .font(Theme.font(19, .heavy))
                    .foregroundColor(Theme.ink)
                Spacer()
                Button {
                    store.showingSidebar = false
                } label: {
                    Text("✕")
                        .font(Theme.font(24, .heavy))
                        .foregroundColor(Theme.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)
            .overlay(
                Rectangle().frame(height: 2.5).foregroundColor(Theme.ink),
                alignment: .bottom
            )
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(trips) { trip in
                        let sel = store.isCurrent(trip, in: trips)
                        Button {
                            store.switchTrip(trip)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.title)
                                    .font(Theme.font(15, .heavy))
                                Text("\(fmtDayMonthYear(trip.startDate)) ~ \(fmtDayMonthYear(trip.endDate))")
                                    .font(Theme.font(12, .semibold))
                                    .opacity(0.7)
                            }
                            .foregroundColor(sel ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(sel ? Theme.ink : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.ink, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                store.newTrip()
            } label: {
                Text("＋ New Trip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SketchButtonStyle(dark: true))
            .padding(.top, 12)
        }
        .padding(18)
        .frame(width: 272)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .overlay(
            Rectangle().frame(width: 2.5).foregroundColor(Theme.ink),
            alignment: .trailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - First-launch empty state (paper plane doodle + New Trip)

struct EmptyStateView: View {
    @Environment(PlannerStore.self) private var store

    var body: some View {
        VStack {
            ZStack {
                PlaneTrail()
                    .stroke(Theme.gray2, style: StrokeStyle(lineWidth: 2.6, dash: [1, 6]))
                PaperPlane()
                    .stroke(Theme.gray2, lineWidth: 2.6)
            }
            .frame(width: 84, height: 84)
            .padding(.bottom, 20)

            Button {
                store.newTrip()
            } label: {
                Text("＋ New Trip")
                    .font(Theme.font(18, .heavy))
            }
            .buttonStyle(SketchButtonStyle(dark: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}
