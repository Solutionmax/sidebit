import SwiftUI
import SnipkinCore

/// Deterministic scene choreography, in seconds and fractions of the artwork size.
struct CharacterScene {
    let activity: Activity
    let gag: Bool
    var index: Int {
        if gag { return 5 }
        switch activity {
        case .working: return 0
        case .thinking: return 1
        case .waiting, .unknown: return 2
        case .done: return 3
        case .idle: return 4
        }
    }
    struct Motion {
        var x = 0.0, y = 0.0, angle = 0.0, scaleX = 1.0, scaleY = 1.0
    }
    /// One minute of activity has its own pacing; short gestures never replace the real status.
    static let cycleDuration = 48.0
    func phase(at time: Double) -> Double { max(0, time).truncatingRemainder(dividingBy: Self.cycleDuration) }

    func typingStrength(at time: Double) -> Double {
        let p = phase(at: time)
        return min(1, pulse(p, 0, 8) * 2 + pulse(p, 11, 17) * 2
            + pulse(p, 23, 34) * 2 + pulse(p, 39, 45) * 2)
    }

    func showsQuip(at time: Double) -> Bool {
        if gag { return (3...7).contains(time) || (11...15).contains(time) }
        let p = phase(at: time)
        // Early window too: short desktop replies often end before second 17.
        return (1.5...6.5).contains(p) || (17...22).contains(p) || (35...39).contains(p)
    }

    func motion(at time: Double, frozen: Bool) -> Motion {
        guard !frozen else { return Motion() }
        let p = phase(at: time)
        var m = Motion()
        if gag {
            // A single 16-second vignette, controlled by the parent, never a repeating spill.
            let wobble = pulse(time, 1, 4) + pulse(time, 5, 7)
            m.angle = sin(time * 5) * 6 * wobble + pulse(time, 9, 12) * -2
            m.x = sin(time * 5) * 0.012 * wobble
            m.scaleY = 1 - pulse(time, 6, 7) * 0.03 + pulse(time, 12, 15) * 0.008
            return m
        }
        switch activity {
        case .working:
            let typing = typingStrength(at: time)
            let cadence = p < 18 ? 10.5 : p < 35 ? 8.3 : 12.2
            m.y = -abs(sin(p * cadence)) * 0.009 * typing
            m.scaleX = 1 + sin(p * cadence) * 0.006 * typing
            m.scaleY = 1 + sin(p * 1.3) * 0.004 * (1 - typing)
            m.angle = sin(p * cadence / 2) * 0.65 * typing
                - pulse(p, 18, 22) * 2 + pulse(p, 35, 39) * 1.5
        case .thinking:
            m.angle = -pulse(p, 2, 7) * 3 + pulse(p, 10, 14) * 2
                - pulse(p, 25, 31) * 2.5 + pulse(p, 35, 39) * 1.5
            m.y = -pulse(p, 17, 19) * 0.018 - pulse(p, 41, 43) * 0.012
            m.scaleY = 1 + sin(p * .pi / 4) * 0.004
        case .waiting:
            // A gentle whole-pose greeting, using the illustrated raised paw/hand.
            let wave = pulse(p, 3, 7) + pulse(p, 24, 29) + pulse(p, 41, 44)
            m.angle = sin(p * 3) * 2 * wave
            m.x = sin(p * 3) * 0.006 * wave
            m.scaleY = 1 + sin(p * .pi / 4) * 0.005
        case .unknown:
            m.angle = -pulse(p, 7, 12) * 1.5 + pulse(p, 31, 36) * 1.5
            m.scaleY = 1 + sin(p * .pi / 5) * 0.005
        case .done:
            // Absolute elapsed time: the initial celebration never restarts each macrocycle.
            let crouch = pulse(time, 0, 0.55)
            let jump = pulse(time, 0.55, 1.7)
            let land = pulse(time, 1.7, 2.2)
            m.scaleX = 1 + crouch * 0.05 + land * 0.035 - jump * 0.02
            m.scaleY = 1 - crouch * 0.06 - land * 0.05 + jump * 0.025
                + (time > 3 ? sin(time * .pi / 4) * 0.004 : 0)
            m.y = -jump * 0.08
            m.angle = jump * -3 + pulse(p, 22, 28) * 1.2
        case .idle:
            let breath = sin(p * .pi / 4)
            m.scaleY = 1 + breath * 0.012
            m.scaleX = 1 - breath * 0.005
            // One sleepy hiccup, followed by a longer settling breath.
            m.y = -pulse(p, 32, 32.55) * 0.018
            m.angle = pulse(p, 32.4, 33.2) * 1.5 - pulse(p, 33.2, 34) * 1
        }
        return m
    }
    private func pulse(_ t: Double, _ start: Double, _ end: Double) -> Double {
        guard t > start && t < end else { return 0 }
        return pow(sin((t - start) / (end - start) * .pi), 2)
    }
}

struct SceneAccents: View {
    let scene: CharacterScene
    let time: Double
    let frozen: Bool

    var body: some View {
        Canvas { context, size in
            let p = scene.phase(at: time)
            let unit = size.width
            func label(_ text: String, x: Double, y: Double, opacity: Double = 1, color: Color = .white, scale: Double = 1) {
                var layer = context
                layer.opacity = opacity
                let content = Text(text).font(.system(size: max(10, unit * 0.09 * scale), weight: .bold, design: .rounded)).foregroundColor(color)
                layer.draw(content, at: CGPoint(x: unit * x, y: size.height * y))
            }
            // Reduced motion preserves the pose without any timed particles or cues.
            guard !frozen else { return }
            if scene.gag {
                if time > 2 && time < 4 {
                    label("!", x: 0.83, y: 0.26, color: .orange, scale: 1.3)
                    for i in 0..<3 {
                        let q = (time - 2 + Double(i) * 0.18).truncatingRemainder(dividingBy: 1)
                        label("·", x: 0.77 + q * 0.1, y: 0.48 - sin(q * .pi) * 0.12 + Double(i) * 0.025, opacity: 1 - q, color: .brown)
                    }
                }
                if time > 8 && time < 11 { label("♥", x: 0.77, y: 0.22 - (time - 8) * 0.025, opacity: sin((time - 8) / 3 * .pi), color: .pink) }
                return
            }
            switch scene.activity {
            case .working:
                if scene.typingStrength(at: time) > 0.15 {
                    for i in 0..<3 {
                        let q = (p * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        label(["{ }", "</>", ";"][i], x: 0.16 + Double(i) * 0.31, y: 0.48 - q * 0.24, opacity: sin(q * .pi) * 0.7 * scene.typingStrength(at: time), color: Color(red: 0.65, green: 0.77, blue: 0.95), scale: 0.8)
                    }
                    label(p.truncatingRemainder(dividingBy: 0.5) < 0.25 ? "˙ ˙" : "· ·", x: 0.51, y: 0.67, opacity: 0.65, color: .orange)
                }
            case .thinking:
                let p = p < 24 ? p - 1 : p - 25
                if p > 1 && p < 8 {
                    var bubble = context
                    bubble.opacity = min(1, (p - 1) * 2, (8 - p) * 2)
                    bubble.fill(Path(roundedRect: CGRect(x: unit * 0.71, y: size.height * 0.08, width: unit * 0.19, height: size.height * 0.16), cornerRadius: unit * 0.06), with: .color(Color(white: 0.16).opacity(0.9)))
                    label(p < 3.5 ? "?" : p < 6 ? "…" : "✦", x: 0.805, y: 0.16, opacity: min(1, (p - 1) * 2, (8 - p) * 2), color: p < 6 ? .white : .yellow, scale: 1.2)
                    label("·", x: 0.72, y: 0.27, opacity: 0.7)
                }
            case .waiting, .unknown:
                let p = p < 20 ? p : p < 36 ? p - 21 : p - 38
                if p > 4 && p < 6.5 {
                    label(scene.activity == .unknown ? "?" : "psst…", x: 0.74, y: 0.18, opacity: min(1, (p - 4) * 2, (6.5 - p) * 2), color: Color(red: 1, green: 0.76, blue: 0.42), scale: 0.8)
                    label("((", x: 0.12, y: 0.3, opacity: 0.6, color: .orange, scale: 0.7)
                }
            case .done:
                if time > 0.6 && time < 2.7 {
                    let q = (time - 0.6) / 2.1
                    let colors: [Color] = [.orange, .yellow, .pink, .mint, .purple]
                    for i in 0..<15 {
                        let angle = Double(i) * 2.39996
                        let x = 0.5 + cos(angle) * q * 0.43
                        let y = 0.34 + sin(angle) * q * 0.26 + q * q * 0.17
                        var layer = context
                        layer.opacity = 1 - q
                        let rect = CGRect(x: unit * x, y: size.height * y, width: max(2, unit * 0.018), height: max(3, unit * 0.027))
                        layer.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[i % colors.count]))
                    }
                }
            case .idle:
                if p > 32 && p < 34 {
                    label("hic", x: 0.76, y: 0.23, opacity: sin((p - 32) / 2 * .pi), color: .orange, scale: 0.7)
                }
                for i in 0..<2 {
                    let q = (p / 5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    label(i == 0 ? "z" : "Z", x: 0.72 + q * 0.09, y: 0.36 - q * 0.19, opacity: sin(q * .pi) * 0.65, color: Color(red: 0.76, green: 0.73, blue: 0.94), scale: 0.8 + q * 0.3)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
