import SwiftUI

// MARK: - Pencil-sketch design tokens (mirrors index.html v13)

enum Theme {
    static let ink = Color(hex: 0x111111)
    static let paper = Color(hex: 0xFAF9F5)
    static let dateHeadBG = Color(hex: 0xF1F0EB)
    static let weekdayBG = Color(hex: 0xF7F6F2)
    static let cardBorder = Color(hex: 0xDBD8D2)
    static let hourLine = Color(hex: 0xE8E5DE)
    static let gray1 = Color(hex: 0x6B6862)   // secondary text
    static let gray2 = Color(hex: 0x8A8781)   // hints
    static let gray3 = Color(hex: 0xA3A09A)   // faint labels
    static let danger = Color(hex: 0xDD3333)

    /// Type scale (v12 audit): 800 for titles/numbers/buttons, 600 for secondary.
    /// .heavy == 800, .semibold == 600.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Hand-drawn shapes

/// Wavy pencil line (title flourish, overview end mark).
struct WavyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.04, y: h * 0.58))
        p.addCurve(
            to: CGPoint(x: w * 0.60, y: h * 0.50),
            control1: CGPoint(x: w * 0.25, y: h * 0.28),
            control2: CGPoint(x: w * 0.42, y: h * 0.85)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.58),
            control1: CGPoint(x: w * 0.78, y: h * 0.35),
            control2: CGPoint(x: w * 0.88, y: h * 0.70)
        )
        return p
    }
}

/// Imperfect hand-drawn ellipse for key nodes (✈️ / 🏨 In / 🏨 Out).
struct SketchCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let steps = 48
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let wobble = 1 + 0.045 * sin(3 * t + 1.2) + 0.02 * sin(5 * t)
            let x = cx + CGFloat(cos(t)) * rx * CGFloat(wobble)
            let y = cy + CGFloat(sin(t)) * ry * CGFloat(wobble)
            if i == 0 {
                p.move(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        p.closeSubpath()
        return p
    }
}

/// Paper-plane doodle for the first-launch empty state (from v11 SVG).
struct PaperPlane: Shape {
    func path(in rect: CGRect) -> Path {
        // SVG viewBox is 84x84
        let s = min(rect.width, rect.height) / 84
        let ox = rect.minX + (rect.width - 84 * s) / 2
        let oy = rect.minY + (rect.height - 84 * s) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var p = Path()
        p.move(to: pt(12, 46))
        p.addLine(to: pt(66, 14))
        p.addLine(to: pt(30, 70))
        p.addLine(to: pt(34, 48))
        p.closeSubpath()
        // fold line
        p.move(to: pt(34, 48))
        p.addLine(to: pt(66, 14))
        return p
    }
}

/// Dashed flight trail behind the paper plane.
struct PlaneTrail: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 84
        let ox = rect.minX + (rect.width - 84 * s) / 2
        let oy = rect.minY + (rect.height - 84 * s) / 2
        var p = Path()
        p.move(to: CGPoint(x: ox + 8 * s, y: oy + 66 * s))
        p.addCurve(
            to: CGPoint(x: ox + 28 * s, y: oy + 56 * s),
            control1: CGPoint(x: ox + 16 * s, y: oy + 60 * s),
            control2: CGPoint(x: ox + 22 * s, y: oy + 62 * s)
        )
        return p
    }
}

// MARK: - Sketch button

struct SketchButtonStyle: ButtonStyle {
    var dark: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .heavy))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(dark ? Theme.ink : Color.white)
            .foregroundColor(dark ? .white : Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink, lineWidth: 2))
            .shadow(
                color: Theme.ink,
                radius: 0,
                x: configuration.isPressed ? 0 : 2,
                y: configuration.isPressed ? 0 : 2
            )
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
    }
}

// MARK: - Shared formatters

func fmtTime(_ minutes: Int) -> String {
    let m = max(0, min(1439, minutes))
    return String(format: "%02d:%02d", m / 60, m % 60)
}

func fmtDur(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let h = Double(minutes) / 60
    if h == floor(h) { return "\(Int(h)) hr" }
    return String(format: "%.1f hr", h)
}

func fmtDayMonth(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d"
    return f.string(from: date)
}

func fmtDayMonthYear(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d, yyyy"
    return f.string(from: date)
}

func weekdayShort(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE"
    return f.string(from: date).uppercased()
}

func minutesOfDay(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

func dateOn(_ day: Date, minutes: Int) -> Date {
    Calendar.current.date(
        bySettingHour: minutes / 60,
        minute: minutes % 60,
        second: 0,
        of: day
    ) ?? day
}
