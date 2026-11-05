# Pencil Trip Planner ✏️

A local-first iOS trip planner with a hand-drawn pencil aesthetic.
100% on-device: your trips live in SwiftData on your iPhone, no account, no server.

- **Overview**: 7-column calendar grid, each day split into morning / afternoon / evening bands, activities placed by time of day, key nodes (✈️ flights, 🏨 check-in/out) circled by hand
- **Detail**: tap a day → horizontal day strip + 24-hour timeline, tap any hour to add an event
- **Quick add**: title, emoji picker, start/end time, location, notes
- **Calendar sync (EventKit)**: one-tap write-through of activities to the system calendar; import system events into the trip grid
- **Trips sidebar** + first-launch empty state

iOS 17+ · SwiftUI + SwiftData · no dependencies

## Run it on your iPhone (free, no paid developer account needed)

You need a Mac with Xcode (free from the Mac App Store).

1. Download this repo: `git clone https://github.com/xueluren/pencil-trip-planner.git`
   (or click **Code → Download ZIP** on GitHub and unzip)
2. Open `ios/PencilTripPlanner.xcodeproj` in Xcode
3. Connect your iPhone with a cable, tap **Trust** on the phone
4. In Xcode, select the **PencilTripPlanner** target → **Signing & Capabilities** →
   **Team** → **Add an Account…**, sign in with your Apple ID, then pick your
   **Personal Team**
5. Change the **Bundle Identifier** to something unique, e.g.
   `me.yourname.penciltripplanner` (free accounts can't use the default one)
6. At the top of Xcode, choose your iPhone as the run destination, then press **⌘R**
7. On first launch, iOS asks you to trust the developer certificate:
   iPhone **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**

Notes for free Apple IDs: sideloaded apps expire after 7 days — just press ⌘R again
in Xcode to refresh. No data ever leaves your phone.

The first launch seeds a 14-day Tahiti sample trip (same data as the HTML prototype
in the repo root) so you can explore immediately. Delete it from the sidebar whenever
you like.

## Project layout

```
ios/PencilTripPlanner/
  PencilTripPlannerApp.swift   @main entry, ModelContainer, first-launch sample data
  Models.swift                 @Model: Trip → TripDay → Activity (cascade delete)
  PlannerStore.swift           @Observable store: selection, CRUD, sample data
  Theme.swift                  design tokens: pencil colors, type scale (600/800),
                               hand-drawn shapes (WavyLine, SketchCircle, PaperPlane…)
  OverviewViews.swift          header + month label + weekday row + 7-column grid +
                               DayCard (3 time bands, time-positioned emoji, clamp)
  DetailViews.swift            day strip + 24h timeline + event blocks
  ChromeViews.swift            ContentView / SidebarView / EmptyStateView
  EditorViews.swift            EventEditorView / EmojiPickerView / TripEditorView
```

The visual spec is `index.html` in the repo root — an interactive, zero-dependency
HTML prototype of the same design. Open it in any browser to preview.

## Permissions

- **Calendars** (`NSCalendarsUsageDescription`): asked on first sync/import.
  Everything stays on-device — the app writes to / reads from your local
  calendars via EventKit, no network involved. If you deny it, the app shows
  an alert with a shortcut to Settings.

## Upgrading from an older build

Phase 3 adds one optional field to the local database. SwiftData migrates it
automatically, but if an old install misbehaves after updating, delete the app
from your iPhone and reinstall (⌘R again) — your trips restart from the
built-in Tahiti sample.

## Roadmap

- ✅ Phase 1 — high-fidelity HTML prototype (done, `index.html`)
- ✅ Phase 2 — native SwiftUI skeleton + SwiftData persistence (this folder)
- ✅ Phase 3 — two-way sync with the system calendar (EventKit)
- ⬜ Phase 4 — Share Extension: share a booking confirmation → auto-create events

## Known simplifications vs the HTML prototype

- Tapping an empty hour creates the event at the top of that hour (HTML snaps to
  15-minute precision; avoided to not fight ScrollView gestures)
- Header icons use SF Symbols (`line.horizontal.3`, `square.and.pencil`)
  approximating the hand-drawn SVGs
- Sketchy button borders approximated with rounded rects + offset shadows

## License

MIT — see [LICENSE](../LICENSE). Do anything you like with it. ✏️
