# Pencil Trip Planner ✏️

A local-first iOS trip planner with a hand-drawn pencil aesthetic.
Your trips live on your device (SwiftData) — no account, no server, no tracking.

**Why it exists:** regular calendars chop a multi-day trip into disconnected
day/week/month views. This app shows the whole trip at a glance: a 7-column
overview grid where every day is split into morning / afternoon / evening,
activities placed by time of day, and key moments (✈️ flights, 🏨 check-in/out)
highlighted with hand-drawn circles. Tap any day for a 24-hour timeline.

![MIT License](https://img.shields.io/badge/license-MIT-green)

## What's in this repo

| Path | What |
|---|---|
| `ios/` | The native iOS app (SwiftUI + SwiftData, iOS 17+) — the real thing |
| `index.html` | Interactive design prototype (single file, zero dependencies, works offline) |
| `LICENSE` | MIT |

## Use it on your iPhone

No App Store, no TestFlight — build it yourself in 5 minutes, free:

1. On a Mac, install **Xcode** (free, Mac App Store)
2. `git clone https://github.com/xueluren/pencil-trip-planner.git`
3. Open `ios/PencilTripPlanner.xcodeproj`
4. Plug in your iPhone → in **Signing & Capabilities** pick your Apple ID
   (**Personal Team**), set a unique Bundle Identifier
5. Select your iPhone at the top, press **⌘R**
6. On the phone: **Settings → General → VPN & Device Management** → trust your Apple ID

Full step-by-step with screenshots-level detail: [`ios/README.md`](ios/README.md).
Free Apple IDs need a ⌘R refresh every 7 days — that's Apple's rule, not ours.

## Roadmap

- ✅ Phase 1 — high-fidelity HTML prototype
- ✅ Phase 2 — native SwiftUI skeleton + SwiftData persistence
- ⬜ Phase 3 — two-way sync with system calendar (EventKit)
- ⬜ Phase 4 — Share Extension: share a booking email → auto-create events

## License

MIT — do anything you like with it. See [LICENSE](LICENSE). ✏️
