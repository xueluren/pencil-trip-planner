import SwiftUI
import SwiftData

// MARK: - Gmail booking import (self-contained view)
//
// Hook-up (for the integrator): present from anywhere, e.g. in ContentView:
//   @State private var showEmailImport = false
//   .toolbar { Button { showEmailImport = true } label: { Image(systemName: "envelope") } }
//   .sheet(isPresented: $showEmailImport) { EmailImportView() }
// The view only needs a ModelContainer in the environment (the app root has one).

/// Editable draft for one parsed flight.
struct FlightDraft: Identifiable {
    let id = UUID()
    var flightNumber: String
    var from: String
    var to: String
    var dateText: String   // "Jan 10, 2027"
    var timeText: String   // "19:25"
    var durationHours: Int

    init(flightNumber: String, from: String, to: String,
         dateText: String, timeText: String, durationHours: Int = 2) {
        self.flightNumber = flightNumber
        self.from = from
        self.to = to
        self.dateText = dateText
        self.timeText = timeText
        self.durationHours = durationHours
    }
}

/// Editable draft for one parsed hotel stay.
struct HotelDraft: Identifiable {
    let id = UUID()
    var name: String
    var checkInText: String   // "Jan 10, 2027"
    var checkOutText: String
}

private func parseDraftDate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for fmt in ["MMM d, yyyy", "MMMM d, yyyy"] {
        f.dateFormat = fmt
        if let d = f.date(from: s.trimmingCharacters(in: .whitespaces)) { return d }
    }
    return nil
}

private func parseDraftTime(_ s: String) -> Int? {
    let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0..<24).contains(h), (0..<60).contains(m) else { return nil }
    return h * 60 + m
}

private func draftDateText(_ d: Date?) -> String {
    guard let d = d else { return "" }
    return fmtDayMonthYear(d)
}

// MARK: - Email list

struct EmailImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = GmailAuth.shared

    @State private var messages: [GmailMessageMeta] = []
    @State private var loadingList = false
    @State private var selected: GmailMessageMeta?
    @State private var errorText: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if GmailAuth.clientID() == nil {
                    missingConfigView
                } else if !auth.isSignedIn {
                    signInView
                } else {
                    messageList
                }
            }
            .navigationTitle("Import from Gmail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if auth.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Sign out") {
                            auth.signOut()
                            messages = []
                        }
                    }
                }
            }
            .navigationDestination(item: $selected) { meta in
                EmailParseDetailView(meta: meta)
            }
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "Unknown error")
            }
        }
        .task {
            if auth.isSignedIn { await loadList() }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { Task { await loadList() } }
        }
    }

    private func fail(_ error: Error) {
        errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showError = true
    }

    private func loadList() async {
        loadingList = true
        defer { loadingList = false }
        do {
            let token = try await auth.validAccessToken()
            messages = try await GmailAPI.searchConfirmations(token: token)
        } catch {
            fail(error)
        }
    }

    // MARK: Subviews

    private var missingConfigView: some View {
        VStack(spacing: 14) {
            Text("📧").font(.system(size: 44))
            Text("Gmail is not configured")
                .font(Theme.font(19))
            Text("The developer needs to add a Google OAuth client ID as GmailClientID in Info.plist, plus the redirect URL scheme.")
                .font(Theme.font(14, .semibold))
                .foregroundColor(Theme.gray1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var signInView: some View {
        VStack(spacing: 16) {
            Text("📧").font(.system(size: 44))
            Text("Import bookings from Gmail")
                .font(Theme.font(19))
            Text("Sign in with Google (read-only access). The app scans your inbox for booking confirmations and turns them into trips. Tokens never leave this device.")
                .font(Theme.font(14, .semibold))
                .foregroundColor(Theme.gray1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Sign in with Google") {
                Task {
                    do { try await auth.signIn() }
                    catch { fail(error) }
                }
            }
            .buttonStyle(SketchButtonStyle(dark: true))
            .padding(.top, 8)
        }
    }

    private var messageList: some View {
        Group {
            if loadingList && messages.isEmpty {
                ProgressView("Searching confirmations…")
            } else if messages.isEmpty {
                VStack(spacing: 12) {
                    Text("No booking emails found")
                        .font(Theme.font(17))
                    Text("in the last 180 days")
                        .font(Theme.font(14, .semibold))
                        .foregroundColor(Theme.gray1)
                    Button("Search again") { Task { await loadList() } }
                        .buttonStyle(SketchButtonStyle())
                }
            } else {
                List(messages) { m in
                    Button { selected = m } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.subject.isEmpty ? "(no subject)" : m.subject)
                                .font(Theme.font(15))
                                .foregroundColor(Theme.ink)
                                .lineLimit(2)
                            Text(m.from)
                                .font(Theme.font(12, .semibold))
                                .foregroundColor(Theme.gray1)
                                .lineLimit(1)
                            if let d = m.date {
                                Text(fmtDayMonthYear(d))
                                    .font(Theme.font(12, .semibold))
                                    .foregroundColor(Theme.gray3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .refreshable { await loadList() }
            }
        }
    }
}

// MARK: - Parse preview + editable drafts + create trip

struct EmailParseDetailView: View {
    let meta: GmailMessageMeta
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var loadError: String?
    @State private var tripTitle = ""
    @State private var confirmationCode = ""
    @State private var flightDrafts: [FlightDraft] = []
    @State private var hotelDrafts: [HotelDraft] = []
    @State private var createdTripTitle: String?
    @State private var createError: String?
    @State private var showCreateError = false

    var body: some View {
        Group {
            if let done = createdTripTitle {
                successView(done)
            } else if loading {
                ProgressView("Reading email…")
            } else if let err = loadError {
                VStack(spacing: 12) {
                    Text("Couldn't parse this email").font(Theme.font(17))
                    Text(err)
                        .font(Theme.font(13, .semibold))
                        .foregroundColor(Theme.gray1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(SketchButtonStyle())
                }
            } else {
                editorView
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Couldn't create trip", isPresented: $showCreateError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(createError ?? "")
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let token = try await GmailAuth.shared.validAccessToken()
            let body = try await GmailAPI.getMessageBody(id: meta.id, token: token)
            let parsed = BookingParser.parse(subject: body.subject, from: body.from, body: body.plainText)
            tripTitle = body.subject.isEmpty ? "Imported trip" : body.subject
            confirmationCode = parsed.confirmationCode ?? ""
            flightDrafts = parsed.flights.map {
                FlightDraft(
                    flightNumber: "\($0.airline) \($0.number)",
                    from: $0.from ?? "",
                    to: $0.to ?? "",
                    dateText: draftDateText($0.date),
                    timeText: $0.time24 ?? "",
                    durationHours: 2
                )
            }
            hotelDrafts = parsed.hotels.map {
                HotelDraft(
                    name: $0.name,
                    checkInText: draftDateText($0.checkIn),
                    checkOutText: draftDateText($0.checkOut)
                )
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Editor

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(Theme.font(12)).foregroundColor(Theme.gray2)
    }

    private func textField(_ placeholder: String, text: Binding<String>, size: CGFloat = 15) -> some View {
        TextField(placeholder, text: text)
            .font(Theme.font(size, .semibold))
            .padding(10)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder, lineWidth: 1.5))
    }

    private var editorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("TRIP TITLE")
                    textField("Trip title", text: $tripTitle, size: 16)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("CONFIRMATION CODE")
                    textField("e.g. ABC123", text: $confirmationCode)
                }
                if !flightDrafts.isEmpty {
                    fieldLabel("FLIGHTS")
                    ForEach($flightDrafts) { $f in flightCard($f) }
                }
                if !hotelDrafts.isEmpty {
                    fieldLabel("HOTELS")
                    ForEach($hotelDrafts) { $h in hotelCard($h) }
                }
                if flightDrafts.isEmpty && hotelDrafts.isEmpty {
                    Text("Nothing recognizable was found in this email. You can still create the trip and add events by hand.")
                        .font(Theme.font(14, .semibold))
                        .foregroundColor(Theme.gray1)
                }
                Button("Create Trip") { createTrip() }
                    .buttonStyle(SketchButtonStyle(dark: true))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding()
        }
    }

    private func flightCard(_ f: Binding<FlightDraft>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("✈️").font(.system(size: 22))
                TextField("Flight (UA 115)", text: f.flightNumber)
                    .font(Theme.font(16))
                Spacer()
                Stepper("\(f.durationHours.wrappedValue)h", value: f.durationHours, in: 1...14)
                    .font(Theme.font(13, .semibold))
            }
            HStack(spacing: 8) {
                textField("From", text: f.from)
                Text("→").font(Theme.font(15)).foregroundColor(Theme.gray2)
                textField("To", text: f.to)
            }
            HStack(spacing: 8) {
                textField("Date (Jan 10, 2027)", text: f.dateText)
                textField("Time (19:25)", text: f.timeText)
            }
        }
        .padding(12)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1.5))
    }

    private func hotelCard(_ h: Binding<HotelDraft>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("🏨").font(.system(size: 22))
                TextField("Hotel name", text: h.name)
                    .font(Theme.font(16))
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("CHECK-IN")
                    textField("Jan 10, 2027", text: h.checkInText)
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("CHECK-OUT")
                    textField("Jan 14, 2027", text: h.checkOutText)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1.5))
    }

    private func successView(_ title: String) -> some View {
        VStack(spacing: 14) {
            Text("✈️").font(.system(size: 44))
            Text("Trip created").font(Theme.font(19))
            Text(title)
                .font(Theme.font(15, .semibold))
                .foregroundColor(Theme.gray1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(SketchButtonStyle(dark: true))
                .padding(.top, 8)
        }
    }

    // MARK: Create trip

    private func createTrip() {
        let cal = Calendar.current
        var dates: [Date] = []
        for f in flightDrafts {
            if let d = parseDraftDate(f.dateText) { dates.append(cal.startOfDay(for: d)) }
        }
        for h in hotelDrafts {
            if let d = parseDraftDate(h.checkInText) { dates.append(cal.startOfDay(for: d)) }
            if let d = parseDraftDate(h.checkOutText) { dates.append(cal.startOfDay(for: d)) }
        }
        guard let start = dates.min(), let end = dates.max() else {
            createError = "Add at least one valid date (e.g. Jan 10, 2027)."
            showCreateError = true
            return
        }
        let notes = confirmationCode.isEmpty ? "" : "Conf: \(confirmationCode)"
        let trip = Trip(
            title: tripTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Imported trip" : tripTitle,
            startDate: start,
            endDate: end
        )
        let dayCount = (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        var days: [TripDay] = []
        for i in 0..<dayCount {
            days.append(TripDay(date: cal.date(byAdding: .day, value: i, to: start) ?? start))
        }
        func day(for date: Date) -> TripDay? {
            days.first { cal.isDate($0.date, inSameDayAs: date) }
        }
        for f in flightDrafts {
            guard let d = parseDraftDate(f.dateText), let target = day(for: d) else { continue }
            target.activities.append(Activity(
                title: "\(f.flightNumber) \(f.from)→\(f.to)",
                emoji: "✈️",
                startMinutes: parseDraftTime(f.timeText) ?? 480,
                durationMinutes: max(1, f.durationHours) * 60,
                location: "\(f.from) → \(f.to)",
                notes: notes,
                isKeyNode: true
            ))
        }
        for h in hotelDrafts {
            let name = h.name.trimmingCharacters(in: .whitespaces)
            if let d = parseDraftDate(h.checkInText), let target = day(for: d) {
                target.activities.append(Activity(
                    title: name.isEmpty ? "Hotel check-in" : name,
                    emoji: "🏨",
                    startMinutes: 900,
                    durationMinutes: 60,
                    notes: notes,
                    isKeyNode: true,
                    tag: "In"
                ))
            }
            if let d = parseDraftDate(h.checkOutText), let target = day(for: d) {
                target.activities.append(Activity(
                    title: name.isEmpty ? "Hotel check-out" : h.name,
                    emoji: "🏨",
                    startMinutes: 660,
                    durationMinutes: 60,
                    notes: notes,
                    isKeyNode: true,
                    tag: "Out"
                ))
            }
        }
        trip.days = days
        modelContext.insert(trip)
        do {
            try modelContext.save()
            createdTripTitle = trip.title
        } catch {
            createError = error.localizedDescription
            showCreateError = true
        }
    }
}
