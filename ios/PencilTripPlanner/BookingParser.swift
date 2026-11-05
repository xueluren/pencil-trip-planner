import Foundation

// MARK: - Booking confirmation parsing (conservative heuristics)
//
// Everything here is best-effort: when a field can't be extracted it comes
// back nil/empty and the import UI lets the user fix it before creating
// the trip. Nothing is ever silently invented.

struct ParsedFlight {
    var airline: String      // "UA"
    var number: String       // "115"
    var from: String?        // "SFO"
    var to: String?          // "PPT"
    var date: Date?
    var time24: String?      // "19:25" departure, when found nearby
}

struct ParsedHotelStay {
    var name: String
    var checkIn: Date?
    var checkOut: Date?
}

struct ParsedBooking {
    var confirmationCode: String?
    var subject: String
    var from: String
    var flights: [ParsedFlight]
    var hotels: [ParsedHotelStay]
}

enum BookingParser {

    static func parse(subject: String, from: String, body: String) -> ParsedBooking {
        let text = body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return ParsedBooking(
            confirmationCode: findConfirmationCode(in: text),
            subject: subject,
            from: from,
            flights: findFlights(in: text),
            hotels: findHotels(in: text)
        )
    }

    // MARK: - Regex helpers

    /// Capture groups of the first match (index 0 = group 1).
    private static func matchGroups(_ pattern: String, in text: String,
                                   options: NSRegularExpression.Options = []) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i -> String? in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    private static func allMatches(_ pattern: String, in text: String,
                                  options: NSRegularExpression.Options = []) -> [(range: NSRange, groups: [String?])] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            let groups = (1..<m.numberOfRanges).map { i -> String? in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            return (m.range, groups)
        }
    }

    // MARK: - Confirmation code (6-char alphanumeric near a label)

    private static func findConfirmationCode(in text: String) -> String? {
        let pat = "(?:confirmation(?:\\s+code|\\s+number|\\s+#)?|booking\\s+(?:reference|number)|record\\s+locator|\\bpnr\\b|itinerary\\s*(?:#|number)?)\\s*[:#]?\\s*\\b([A-Za-z0-9]{6})\\b"
        guard let g = matchGroups(pat, in: text, options: [.caseInsensitive]),
              let raw = g.first, let code = raw,
              code == code.uppercased(),
              code.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil else { return nil }
        return code
    }

    // MARK: - Flights: "UA 115" + nearby route + date + time

    private static let notAirport: Set<String> = [
        "THE", "AND", "FOR", "ARE", "YOU", "ALL", "ANY", "CAN", "HAD", "HER",
        "WAS", "ONE", "OUR", "OUT", "DAY", "GET", "HAS", "HIM", "HIS", "HOW",
        "ITS", "NEW", "NOW", "OLD", "SEE", "TWO", "WAY", "WHO", "DID", "LET",
        "PUT", "SAY", "SHE", "TOO", "USE", "NOT", "BUT", "WHAT", "WHEN",
        "WILL", "WITH", "FROM",
    ]

    private static func validAirportCode(_ s: String?) -> String? {
        guard let s = s, s.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil,
              !notAirport.contains(s) else { return nil }
        return s
    }

    private static func findFlights(in text: String) -> [ParsedFlight] {
        var out: [ParsedFlight] = []
        var seen = Set<String>()
        let ns = text as NSString
        for (range, g) in allMatches("\\b([A-Z]{2})\\s?(\\d{2,4})\\b", in: text) {
            guard let airline = g[0], let num = g[1] else { continue }
            let key = airline + num
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            if out.count >= 6 { break }

            let winStart = max(0, range.location - 160)
            let winEnd = min(ns.length, range.location + range.length + 160)
            let window = ns.substring(with: NSRange(location: winStart, length: winEnd - winStart))

            let (from, to) = findRoute(in: window)
            let date = findDate(in: window)
            let afterStart = min(ns.length, range.location + range.length)
            let afterLen = min(120, ns.length - afterStart)
            let after = afterLen > 0 ? ns.substring(with: NSRange(location: afterStart, length: afterLen)) : ""
            let time = findTime(in: after) ?? findTime(in: window)

            out.append(ParsedFlight(airline: airline, number: num, from: from, to: to, date: date, time24: time))
        }
        return out
    }

    private static func findRoute(in window: String) -> (String?, String?) {
        let patterns = [
            "([A-Z]{3})\\s*[→–—\\-/]\\s*([A-Z]{3})",
            "\\bfrom\\s+([A-Z]{3})\\s+to\\s+([A-Z]{3})",
            "\\b([A-Z]{3})\\s+to\\s+([A-Z]{3})",
        ]
        for p in patterns {
            if let g = matchGroups(p, in: window, options: [.caseInsensitive]),
               let a = validAirportCode(g[0]?.uppercased()),
               let b = validAirportCode(g[1]?.uppercased()) {
                return (a, b)
            }
        }
        return (nil, nil)
    }

    private static func findTime(in text: String) -> String? {
        if let g = matchGroups("\\b((?:[01]?\\d|2[0-3]):[0-5]\\d)\\b", in: text),
           let t = g.first, let time = t {
            return time
        }
        if let g = matchGroups("\\b(\\d{1,2}):(\\d{2})\\s*([AP])\\.?M\\.?", in: text, options: [.caseInsensitive]),
           let hs = g[0], let ms = g[1], let ap = g[2],
           let h0 = Int(hs), let m0 = Int(ms), (1...12).contains(h0), (0..<60).contains(m0) {
            var h = h0 % 12
            if ap.uppercased() == "P" { h += 12 }
            return String(format: "%02d:%02d", h, m0)
        }
        return nil
    }

    // MARK: - Hotels: name + check-in / check-out dates

    private static func findHotels(in text: String) -> [ParsedHotelStay] {
        let name = matchGroups("([A-Z][A-Za-z0-9&'.,\\- ]{2,48}?)\\s+(?:Hotel|Resort|Inn|Suites|Lodge|Hostel)",
                               in: text)?.first??.trimmingCharacters(in: .whitespaces)
            ?? "Hotel stay"
        let checkIn = findLabeledDate(label: "check[\\s\\-]*in", in: text)
        let checkOut = findLabeledDate(label: "check[\\s\\-]*out", in: text)
        if name == "Hotel stay" && checkIn == nil && checkOut == nil { return [] }
        return [ParsedHotelStay(name: name, checkIn: checkIn, checkOut: checkOut)]
    }

    private static func findLabeledDate(label: String, in text: String) -> Date? {
        let pat = "((?:" + label + ")\\s*[:\\-–—]?\\s*.{0,80})"
        guard let g = matchGroups(pat, in: text, options: [.caseInsensitive]),
              let snippet = g.first, let s = snippet else { return nil }
        return findDate(in: s)
    }

    // MARK: - Dates

    private static let months = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"

    private static func findDate(in text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let patterns: [(String, [String])] = [
            ("((?:\(months))[a-z]*\\s+\\d{1,2},\\s*\\d{4})", ["MMM d, yyyy", "MMMM d, yyyy"]),
            ("((?:\(months))[a-z]*\\s+\\d{1,2}\\s+\\d{4})", ["MMM d yyyy", "MMMM d yyyy"]),
            ("(\\d{1,2}\\s+(?:\(months))[a-z]*\\s+\\d{4})", ["d MMM yyyy", "d MMMM yyyy"]),
            ("(\\d{4}-\\d{2}-\\d{2})", ["yyyy-MM-dd"]),
            ("(\\d{1,2}/\\d{1,2}/\\d{4})", ["M/d/yyyy"]),
            ("((?:\(months))[a-z]*\\s+\\d{1,2})(?!\\s*\\d)", ["MMM d", "MMMM d"]),
        ]
        for (pat, fmts) in patterns {
            guard let g = matchGroups(pat, in: text, options: [.caseInsensitive]),
                  let raw = g.first, let cleaned = raw else { continue }
            for fmt in fmts {
                f.dateFormat = fmt
                if var d = f.date(from: cleaned) {
                    if !fmt.contains("y") {
                        var c = Calendar.current.dateComponents([.month, .day], from: d)
                        c.year = Calendar.current.component(.year, from: Date())
                        if let y = Calendar.current.date(from: c) { d = y }
                    }
                    return d
                }
            }
        }
        return nil
    }
}
