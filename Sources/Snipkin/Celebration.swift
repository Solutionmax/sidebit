import SwiftUI
import SnipkinCore

/// A medal arriving. Choreography in seconds: the coin flips in (0 to 0.9), light sweeps it (0.9 to 1.6),
/// sparks burst (0.35 to 2.2), words follow (0.6 to 1.4), then everything breathes until dismissed.
/// `time` pins a frame for previews and snapshots.
struct MomentToast: View {
    let moment: Moment
    var count: Int = 1
    var time: Double?
    /// Follows the companion size, so a small Bit gets a proportionate card.
    var scale: CGFloat = 1
    @State private var started = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || time != nil)) { context in
            let t = reduceMotion ? 4 : (time ?? context.date.timeIntervalSince(started))
            card(t)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New \(moment.rarity.title) medal: \(moment.title). \(moment.blurb)")
    }

    private var metal: [Color] { moment.rarity.metal }

    private func card(_ t: Double) -> some View {
        let appear = ease(t / 0.45)
        let s = scale
        return HStack(spacing: 0) {
            stage(t).frame(width: 220 * s, height: 220 * s)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("\(moment.rarity.title.uppercased()) MEDAL UNLOCKED").font(.mono(max(9, 10.5 * s), .medium)).tracking(s < 0.8 ? 1.4 : 2.2).foregroundStyle(metal[1])
                    RarityPips(rarity: moment.rarity, color: metal[1])
                }.opacity(fade(t, 0.55, 0.9)).offset(x: 10 * (1 - fade(t, 0.55, 0.9)))
                Text(moment.title).font(.serif(max(26, 46 * s))).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 4 * s + 2)
                    .foregroundStyle(moment.rarity == .obsidian ? AnyShapeStyle(LinearGradient(colors: [Color(.sRGB, red: 1, green: 0.72, blue: 0.52, opacity: 1), accent], startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(LinearGradient(colors: [.white, metal[0], metal[1]], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: metal[1].opacity(0.35), radius: 12)
                    .opacity(fade(t, 0.7, 1.1)).offset(x: 14 * (1 - fade(t, 0.7, 1.1)))
                Text(moment.blurb).font(.geist(max(11.5, 13 * s))).foregroundStyle(muted).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    .opacity(fade(t, 0.9, 1.3))
                Spacer(minLength: 12 * s)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("\(count) OF \(Moment.allCases.count)").font(.mono(9, .medium)).tracking(1.2).foregroundStyle(faint)
                        Spacer()
                        Text("OPEN MEDALS ›").font(.mono(9, .medium)).tracking(1.2).foregroundStyle(muted)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [metal[0], metal[1]], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(3, geometry.size.width * Double(count) / Double(Moment.allCases.count) * fade(t, 1.1, 1.9)))
                        }
                    }.frame(height: 2)
                }.opacity(fade(t, 1.0, 1.4))
            }
            .padding(.vertical, 30 * s).padding(.trailing, 28 * s)
        }
        .frame(width: 600 * s).frame(minHeight: 220 * s)
        .fixedSize(horizontal: false, vertical: true)
        .background(alignment: .leading) {
            ZStack {
                PanelBackground(radius: 22)
                // The light reaches across the whole card, strongest behind the coin.
                Rays(color: metal[0]).rotationEffect(.degrees(t * 9)).frame(width: 640 * s, height: 640 * s).offset(x: -190 * s)
                    .opacity(0.32 * fade(t, 0.3, 1.2)).blendMode(.screen)
                RadialGradient(colors: [metal[1].opacity(0.38), metal[1].opacity(0.06), .clear], center: UnitPoint(x: 0.18, y: 0.5), startRadius: 0, endRadius: 260 * s)
                    .opacity(fade(t, 0.1, 0.8))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(LinearGradient(colors: [metal[1].opacity(0.55), .clear, metal[1].opacity(0.2)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: metal[1].opacity(0.18), radius: 28, y: 8)
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
        .scaleEffect(0.92 + 0.08 * appear).opacity(appear)
        .padding(34 * s)
    }

    private func stage(_ t: Double) -> some View {
        let flip = ease((t - 0.1) / 0.8)
        return ZStack {
            Sparks(t: t, colors: metal, reach: scale)
            Medal(moment: moment, size: 132 * scale)
                .overlay { Shine(progress: (t - 0.95) / 0.7).clipShape(Circle()).allowsHitTesting(false) }
                .rotation3DEffect(.degrees((1 - flip) * 540), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .scaleEffect(0.35 + 0.65 * spring(t - 0.1) + 0.015 * sin(max(0, t - 2) * 2.2))
                .offset(y: -3 * sin(max(0, t - 2) * 1.6))
        }
    }

    // Easing helpers, all clamped to 0...1.
    private func fade(_ t: Double, _ a: Double, _ b: Double) -> Double { ease((t - a) / (b - a)) }
    private func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return 1 - pow(1 - c, 3) }
    private func spring(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        return 1 - exp(-6 * x) * cos(9 * x)
    }
}

/// Soft god rays, cut from an angular gradient.
struct Rays: View {
    let color: Color
    var body: some View {
        let stops = (0..<24).flatMap { i -> [Gradient.Stop] in
            let start = Double(i) / 24
            return [.init(color: .clear, location: start), .init(color: color.opacity(0.55), location: start + 0.012), .init(color: .clear, location: start + 0.03)]
        }
        Circle().fill(AngularGradient(stops: stops, center: .center))
            .mask(RadialGradient(colors: [.white, .white.opacity(0.4), .clear], center: .center, startRadius: 30, endRadius: 210))
    }
}

/// Metal sparks: one burst outwards, falling slightly, fading as they go.
private struct Sparks: View {
    let t: Double
    let colors: [Color]
    var reach: Double = 1
    var body: some View {
        Canvas { context, size in
            let local = t - 0.35
            guard local > 0, local < 2 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<34 {
                let angle = Double(i) * 2.399963 + Double(i % 3) * 0.2
                let speed = (70 + Double((i * 53) % 90)) * reach
                let d = speed * (1 - exp(-2.6 * local))
                let x = center.x + cos(angle) * d, y = center.y + sin(angle) * d * 0.8 + 22 * local * local
                var spark = context
                spark.opacity = max(0, 1 - local / 1.9)
                let length = 3 + Double(i % 4) * 2 * max(0, 1 - local)
                spark.translateBy(x: x, y: y); spark.rotate(by: .radians(angle))
                spark.fill(Path(roundedRect: CGRect(x: -length / 2, y: -1, width: length, height: 2), cornerRadius: 1), with: .color(colors[i % 2 == 0 ? 0 : 1]))
            }
        }.allowsHitTesting(false)
    }
}

/// A diagonal band of light sweeping across the coin once.
private struct Shine: View {
    let progress: Double
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.35, height: w * 1.6)
                .rotationEffect(.degrees(22))
                .offset(x: -w * 0.6 + w * 1.8 * min(1, max(0, progress)), y: -w * 0.3)
                .opacity(progress > 0 && progress < 1 ? 1 : 0)
                .blendMode(.screen)
        }
    }
}

/// Four small diamonds: how rare this medal is.
private struct RarityPips: View {
    let rarity: Rarity
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Rarity.allCases, id: \.self) { level in
                Rectangle().fill(level <= rarity ? color : Color.white.opacity(0.12)).frame(width: 5, height: 5).rotationEffect(.degrees(45))
            }
        }.accessibilityHidden(true)
    }
}
