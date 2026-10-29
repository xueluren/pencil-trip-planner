import SwiftUI
import SwiftData

@main
struct PencilTripPlannerApp: App {
    let container: ModelContainer

    @State private var store: PlannerStore

    init() {
        do {
            // Variadic form: ModelContainer(for: Trip.self, TripDay.self, Activity.self)
            container = try ModelContainer(for: Trip.self, TripDay.self, Activity.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        let store = PlannerStore(modelContext: container.mainContext)
        store.seedIfNeeded()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
