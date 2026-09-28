import AppKit
import SwiftUI
import SnipkinCore

// Obsidian cards for sharing. Drawn at their real pixel size (1200×630, 1080×1350, 1080×1080).

private let cardBlack = Color(.sRGB, red: 0.035, green: 0.035, blue: 0.04, opacity: 1)
private let emberGlow = Color(.sRGB, red: 1, green: 0.48, blue: 0.24, opacity: 1)
private let emberText = LinearGradient(colors: [.white, Color(.sRGB, red: 1, green: 0.81, blue: 0.7, opacity: 1), accent], startPoint: .top, endPoint: .bottom)

/// Bit, warmly lit from below.
private struct LitBit: View {
    let pose: String
    let width: CGFloat
    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(RadialGradient(colors: [accent.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: width * 0.45))
                .frame(width: width * 0.9, height: width * 0.12).offset(y: -width * 0.02)
            if let bit = PetImages.moviePosters[pose] ?? PetImages.moviePosters["working"] {
                Image(nsImage: bit).resizable().interpolation(.high).scaledToFit().frame(width: width)
                    .shadow(color: .black.opacity(0.6), radius: width * 0.05, y: width * 0.05)
            }
        }
    }
}

/// The signature every card ends with.
private struct Brand: View {
    let text: String
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(accent).frame(width: size * 0.62, height: size * 0.62).overlay(Circle().stroke(accent.opacity(0.2), lineWidth: size * 0.3))
            Text(text.uppercased()).font(.mono(size, .medium)).tracking(size * 0.14).foregroundStyle(muted)
        }
    }
}

/// Today: 1200×630.
struct ShareCard: View {
    let day: DayJournal
    let streak: Int
    let moments: [Moment]
    let date: Date
    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBlack
            Rays(color: Color(.sRGB, red: 1, green: 0.7, blue: 0.5, opacity: 1)).frame(width: 820, height: 820).offset(x: -150, y: -120).opacity(0.26)
                .frame(width: 1200, height: 630, alignment: .topLeading)
            RadialGradient(colors: [emberGlow.opacity(0.42), emberGlow.opacity(0.08), .clear], center: .center, startRadius: 0, endRadius: 380)
                .frame(width: 760, height: 760).offset(x: -120, y: 110).frame(width: 1200, height: 630, alignment: .topLeading)
            LitBit(pose: moments.isEmpty ? "working" : "done", width: 460).offset(x: 50, y: 110)
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker).font(.mono(13, .medium)).tracking(2.6).foregroundStyle(muted)
                Text(headline.0).font(.display(68)).foregroundStyle(ink).padding(.top, 14)
                Text(headline.1).font(.display(68)).foregroundStyle(accent).padding(.top, -16)
                HStack(alignment: .firstTextBaseline, spacing: 44) {
                    ForEach(figures, id: \.1) { value, label in figure(value, label) }
                }.padding(.top, 18)
                ribbon.padding(.top, 22)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    ForEach(moments.prefix(3), id: \.self) { Medal(moment: $0, size: 52) }
                    if !moments.isEmpty {
                        Text(moments.count == 1 ? "1 new medal" : "\(moments.count) new medals").font(.geist(15)).foregroundStyle(muted).fixedSize()
                    }
                    Spacer()
                    Brand(text: "Sidebit · Claude Code + Codex", size: 12).fixedSize()
                }
            }
            .padding(.top, 54).padding(.bottom, 48).padding(.trailing, 56)
            .frame(width: 580, height: 630, alignment: .topLeading).offset(x: 560)
        }
        .overlay { Grain().opacity(0.07).blendMode(.overlay).allowsHitTesting(false) }
        .frame(width: 1200, height: 630).clipped()
        .environment(\.colorScheme, .dark)
    }
    private var kicker: String {
        let base = date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
        return streak >= 2 ? "\(base) · DAY \(streak) OF A STREAK" : base
    }
    /// The three numbers that tell today's story; zeros are left out, lines always come last.
    private var figures: [(String, String)] {
        let counts: [(Int, String)] = [(day.commands, "commands"), (day.edits, "edits"), (day.sessions, "sessions"),
                                       (day.reads, "reads"), (day.asks, "asked me"), (day.prompts, "prompts")]
        var chosen = counts.filter { $0.0 > 0 }.prefix(day.linesAdded > 0 ? 2 : 3).map { ($0.0.formatted(), $0.1) }
        if day.linesAdded > 0 { chosen.append(("+" + day.linesAdded.formatted(), "lines")) }
        return chosen.isEmpty ? [("0", "turns")] : chosen
    }
    private var headline: (String, String) {
        if day.turns == 0 && day.sessions > 0 {
            return (day.sessions == 1 ? "One session." : "\(day.sessions) sessions.", day.sessions >= 10 ? "Bit is dizzy." : "Warming up.")
        }
        if day.turns == 0 { return ("A fresh page.", "Bit is ready.") }
        if day.nightOwl { return (day.turns == 1 ? "One turn." : "\(day.turns) turns.", "Past midnight.") }
        if day.turns >= 50 { return ("\(day.turns) turns.", "What a day.") }
        return day.turns == 1 ? ("One turn.", "One tiny trophy.") : ("\(day.turns) turns.", "Zero regrets.")
    }
    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.geist(64, .ultraLight)).tracking(-2.5).monospacedDigit().foregroundStyle(ink)
            Text(label).font(.geist(14)).foregroundStyle(muted)
        }
    }
    private var ribbon: some View {
        let peak = max(1, day.hours.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(day.hours.indices, id: \.self) { hour in
                let value = Double(day.hours[hour]) / Double(peak)
                RoundedRectangle(cornerRadius: 2)
                    .fill(value > 0.75 ? AnyShapeStyle(LinearGradient(colors: [Color(.sRGB, red: 1, green: 0.69, blue: 0.54, opacity: 1), Color(.sRGB, red: 0.79, green: 0.33, blue: 0.16, opacity: 1)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.1)))
                    .frame(height: max(3, 46 * value))
                    .shadow(color: value > 0.75 ? emberGlow.opacity(0.5) : .clear, radius: 8)
            }
        }.frame(height: 46, alignment: .bottom)
    }
}

/// The week: 1080×1350, with a seven-day by 24-hour heatmap.
struct RecapCard: View {
    let week: WeekSummary
    let streak: Int
    let medals: Int
    let end: Date
    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBlack
            RadialGradient(colors: [emberGlow.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 520).frame(width: 1060, height: 1060).offset(x: 380, y: -300)
                .frame(width: 1080, height: 1350, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker).font(.mono(20, .medium)).tracking(4).foregroundStyle(muted)
                Text(week.turns.formatted()).font(.geist(250, .ultraLight)).tracking(-12).foregroundStyle(emberText).padding(.top, 20).lineLimit(1).minimumScaleFactor(0.5)
                (Text("turns with Bit. ").foregroundColor(ink) + Text(tagline).foregroundColor(accent)).font(.display(52)).padding(.top, 0)
                heatmap.padding(.top, 50)
                VStack(spacing: 0) {
                    if let best = week.bestDay { fact("Best day", "\(weekday(best.day)) · \(best.turns) turns") }
                    if let hour = week.latestHour { fact("Latest", String(format: "%02d:00", hour) + (hour < 5 ? ". Bit is concerned." : ".")) }
                    if let share = week.claudeShare { split(share) }
                    fact("Medals", "\(medals) of \(Moment.allCases.count) collected")
                }.padding(.top, 44).frame(maxWidth: 780, alignment: .leading)
                Spacer(minLength: 0)
                Brand(text: "Sidebit", size: 20)
            }
            .padding(.horizontal, 72).padding(.top, 76).padding(.bottom, 64)
            LitBit(pose: "done", width: 340).offset(x: 770, y: 1010)
        }
        .frame(width: 1080, height: 1350).clipped()
        .environment(\.colorScheme, .dark)
    }
    private var kicker: String {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        let number = calendar.component(.weekOfYear, from: end)
        return "WEEK \(number) · \(start.formatted(.dateTime.day().month(.wide))) to \(end.formatted(.dateTime.day().month(.wide)))".uppercased()
    }
    private var tagline: String {
        if week.turns == 0 { return "A quiet one." }
        if streak >= 7 { return "Every single day." }
        if week.turns >= 150 { return "Big week." }
        return "Nice rhythm."
    }
    private var heatmap: some View {
        let peak = max(1, week.days.flatMap(\.hours).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(week.days.indices, id: \.self) { index in
                let day = week.days[index]
                HStack(spacing: 6) {
                    Text(weekday(day.day, short: true)).font(.mono(16, .medium)).foregroundStyle(faint).frame(width: 52, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        let value = day.hours.count == 24 ? Double(day.hours[hour]) / Double(peak) : 0
                        RoundedRectangle(cornerRadius: 5)
                            .fill(value == 0 ? Color.white.opacity(0.05) : accent.opacity(value > 0.66 ? 1 : value > 0.33 ? 0.55 : 0.28))
                            .frame(width: 32, height: 32)
                            .shadow(color: value > 0.66 ? emberGlow.opacity(0.55) : .clear, radius: 10)
                    }
                }
            }
            HStack(spacing: 0) {
                Spacer().frame(width: 58)
                ForEach(["00", "06", "12", "18"], id: \.self) { Text($0).font(.mono(15)).foregroundStyle(faint).frame(width: 228, alignment: .leading) }
            }
        }
    }
    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased()).font(.mono(17, .medium)).tracking(2.4).foregroundStyle(muted).frame(width: 210, alignment: .leading)
            Text(value).font(.geist(27)).foregroundStyle(ink)
            Spacer(minLength: 0)
        }.padding(.vertical, 20).overlay(alignment: .top) { Rectangle().fill(hairline).frame(height: 1.5) }
    }
    private func split(_ share: Double) -> some View {
        let claude = Int((share * 100).rounded())
        return HStack(alignment: .firstTextBaseline) {
            Text("SPLIT").font(.mono(17, .medium)).tracking(2.4).foregroundStyle(muted).frame(width: 210, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                Text("Claude \(claude)% · Codex \(100 - claude)%").font(.geist(27)).foregroundStyle(ink)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle().fill(accent).frame(width: geometry.size.width * share)
                        Rectangle().fill(ice)
                    }.clipShape(Capsule())
                }.frame(height: 12)
            }
        }.padding(.vertical, 20).overlay(alignment: .top) { Rectangle().fill(hairline).frame(height: 1.5) }
    }
    private func weekday(_ key: String, short: Bool = false) -> String {
        let parser = DateFormatter(); parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        return short ? date.formatted(.dateTime.weekday(.abbreviated)).uppercased() : date.formatted(.dateTime.weekday(.wide))
    }
}

/// One medal: 1080×1080.
struct MedalCard: View {
    let moment: Moment
    let date: Date
    let number: Int
    var body: some View {
        let metal = moment.rarity.metal
        ZStack {
            cardBlack
            Rays(color: metal[0]).frame(width: 1500, height: 1500).opacity(0.55).offset(y: -110).frame(width: 1080, height: 1080)
            RadialGradient(colors: [metal[1].opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 440).offset(y: -110).frame(width: 1080, height: 1080)
            VStack(spacing: 0) {
                Medal(moment: moment, size: 380)
                Text("\(moment.rarity.title.uppercased()) MEDAL · NO. \(String(format: "%02d", number)) OF \(Moment.allCases.count)")
                    .font(.mono(22, .medium)).tracking(5).foregroundStyle(metal[1]).padding(.top, 60)
                Text(moment.title).font(.display(124)).padding(.top, 10)
                    .foregroundStyle(moment.rarity == .obsidian ? AnyShapeStyle(emberText) : AnyShapeStyle(LinearGradient(colors: [.white, metal[0], metal[1]], startPoint: .top, endPoint: .bottom)))
                Text(moment.blurb).font(.geist(29)).foregroundStyle(muted).multilineTextAlignment(.center).frame(maxWidth: 760).padding(.top, 8)
                HStack(spacing: 10) {
                    ForEach(Rarity.allCases, id: \.self) { level in
                        Rectangle().fill(level <= moment.rarity ? metal[1] : Color.white.opacity(0.12)).frame(width: 13, height: 13).rotationEffect(.degrees(45))
                    }
                }.padding(.top, 36)
            }.offset(y: -30)
            VStack { Spacer(); Brand(text: "Earned with Sidebit · \(date.formatted(.dateTime.day().month(.abbreviated).year()))", size: 20).padding(.bottom, 52) }
        }
        .frame(width: 1080, height: 1080).clipped()
        .environment(\.colorScheme, .dark)
    }
}

/// Fine film grain, deterministic so a card renders the same every time.
struct Grain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
            for _ in 0..<Int(size.width * size.height / 9) {
                let x = next() * size.width, y = next() * size.height, v = next()
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(v > 0.5 ? .white : .black))
            }
        }
    }
}
