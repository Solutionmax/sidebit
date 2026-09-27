import AppKit
import CoreText
import SwiftUI
import SnipkinCore

/// Obsidian: graphite surfaces, hairlines, one warm glow. Panels are always dark; Bit is the only warm object.
func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}
private func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
    Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
}
let ink = rgb(0xECECEE)
let muted = rgb(0x8B8B91)
let faint = rgb(0x6E6E74)
let accent = rgb(0xFF8A4C)
let emberDeep = rgb(0xFF5B2E)
let ice = rgb(0x8FD3FF)
let hairline = Color.white.opacity(0.08)
let surface = Color.white.opacity(0.045)
let peach = rgb(0x1C1C1F)

extension Font {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Geist", size: size).weight(weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Geist Mono", size: size).weight(weight) }
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font { .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size) }
}

/// Bundled OFL fonts, registered for this process only. Missing files fall back to the system font.
enum Fonts {
    static func register() {
        for name in ["Geist", "GeistMono", "InstrumentSerif-Regular", "InstrumentSerif-Italic"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Resources/Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct PanelBackground: View {
    var radius: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(LinearGradient(colors: [rgb(0x161618), rgb(0x111113)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.white.opacity(0.08)))
            .overlay(alignment: .top) {
                // A single top highlight gives the surface its machined edge.
                RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(colors: [.white.opacity(0.09), .clear], startPoint: .top, endPoint: .center))
            }
    }
}

/// Section label: small monospaced capitals.
struct Kicker: View {
    let text: String
    var trailing: String?
    var body: some View {
        HStack {
            Text(text.uppercased())
            Spacer()
            if let trailing { Text(trailing.uppercased()) }
        }.font(.mono(10, .medium)).tracking(1.2).foregroundStyle(faint)
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.geist(11.5, .medium))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hairline)).foregroundStyle(ink)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.geist(12, .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(rgb(0x0B0B0C))
    }
}

extension Rarity {
    /// Highlight, body and shadow tones of the medal's metal.
    var metal: [Color] {
        switch self {
        case .bronze: return [rgb(0xF6D2B0), rgb(0xC07A45), rgb(0x6A3417)]
        case .silver: return [rgb(0xFFFFFF), rgb(0xC5C9D1), rgb(0x6F7580)]
        case .gold: return [rgb(0xFFF3DC), rgb(0xE9B36A), rgb(0x8A4E17)]
        case .obsidian: return [rgb(0x7A7A84), rgb(0x2A2A30), rgb(0x09090B)]
        }
    }
    var glyph: Color { self == .obsidian ? accent : rgb(0x2B1A0C, 0.85) }
}

/// A struck coin: machined rim, recessed guilloché field, engraved glyph and a soft specular sheen.
/// The metal says how rare it is. Locked medals are a blind-embossed outline.
struct Medal: View {
    let moment: Moment
    var unlocked = true
    var size: CGFloat = 46
    var body: some View {
        let m = moment.rarity.metal
        ZStack {
            if unlocked {
                // Rim: an angular gradient reads as turned metal catching light.
                Circle().fill(AngularGradient(colors: [m[0], m[1], m[2], m[1], m[0], m[1], m[2], m[1], m[0]], center: .center))
                Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: max(0.5, size * 0.012))
                // Field, slightly recessed.
                Circle().fill(RadialGradient(colors: [m[0].opacity(0.95), m[1], m[2]], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: size * 0.55))
                    .padding(size * 0.1)
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.black.opacity(0.45), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.6, size * 0.018)).padding(size * 0.1))
                // Guilloché: fine concentric rings.
                ForEach(1..<7) { ring in
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 0.5).padding(size * (0.12 + Double(ring) * 0.045))
                }
                // Engraved glyph: a light lower edge and a dark upper edge.
                glyph.foregroundStyle(.white.opacity(0.45)).offset(y: size * 0.012)
                glyph.foregroundStyle(moment.rarity.glyph)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: -size * 0.008)
                // Specular sheen.
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.62, height: size * 0.34).offset(x: -size * 0.1, y: -size * 0.22).blendMode(.screen).allowsHitTesting(false)
            } else {
                Circle().fill(Color.white.opacity(0.03))
                Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                Circle().strokeBorder(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: 1, dash: [2, 3])).padding(size * 0.1)
                Image(systemName: "lock.fill").font(.system(size: size * 0.24)).foregroundStyle(faint.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(unlocked ? 0.45 : 0), radius: size * 0.06, y: size * 0.05)
        .shadow(color: unlocked ? m[1].opacity(0.25) : .clear, radius: size * 0.2)
        .accessibilityHidden(true)
    }
    private var glyph: some View {
        Image(systemName: moment.symbol).font(.system(size: size * 0.34, weight: .bold)).symbolRenderingMode(.monochrome)
    }
}

/// Bit in the menu bar: a small speech bubble with eyes. No head, so it never reads as a skull or a toy brick.
enum BitGlyph {
    enum Eyes: Hashable { case open, closed, wide, star }

    /// 18 × 18 pt, drawn as vectors. Without a tint it is a template image that follows the menu bar's appearance.
    static func image(_ eyes: Eyes, tint: NSColor? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            (tint ?? .black).setFill()
            bubble().fill()
            // Cut the eyes out of the bubble.
            context.compositingOperation = .clear
            NSColor.black.setFill(); NSColor.black.setStroke()
            switch eyes {
            case .open: eye(x: 5.4, y: 6.2, height: 3.4); eye(x: 10.7, y: 6.2, height: 3.4)
            case .wide: eye(x: 5.4, y: 5.2, height: 4.4); eye(x: 10.7, y: 5.2, height: 4.4)
            case .closed:
                NSBezierPath(roundedRect: NSRect(x: 5, y: 8.6, width: 2.6, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
                NSBezierPath(roundedRect: NSRect(x: 10.4, y: 8.6, width: 2.6, height: 1.3), xRadius: 0.65, yRadius: 0.65).fill()
            case .star:
                for x in [5.0, 10.4] {
                    let caret = NSBezierPath()
                    caret.move(to: NSPoint(x: x, y: 10)); caret.line(to: NSPoint(x: x + 1.3, y: 8.2)); caret.line(to: NSPoint(x: x + 2.6, y: 10))
                    caret.lineWidth = 1.3; caret.lineCapStyle = .round; caret.lineJoinStyle = .round; caret.stroke()
                }
            }
            context.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = tint == nil
        return image
    }

    private static func eye(x: CGFloat, y: CGFloat, height: CGFloat) {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 1.9, height: height), xRadius: 0.95, yRadius: 0.95).fill()
    }

    /// The bubble with its tail at the lower left, in top-left-origin coordinates.
    private static func bubble() -> NSBezierPath {
        let path = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 2.6, width: 14.8, height: 10.8), xRadius: 3, yRadius: 3)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.2, y: 12.6)); tail.line(to: NSPoint(x: 4.2, y: 17)); tail.line(to: NSPoint(x: 9.2, y: 12.6)); tail.close()
        path.append(tail)
        return path
    }
}
