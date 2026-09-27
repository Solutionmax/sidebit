import AppKit
import SwiftUI
import SnipkinCore

/// Today: three large figures, an hour ribbon and one sentence, straight from the local journal.
struct TodayCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: "Today", trailing: model.streak >= 2 ? "\(model.streak) day streak" : nil)
            if model.today.isEmpty {
                Text(model.installed.isEmpty ? "Connect an agent and Bit starts keeping a diary." : "A blank page. Bit is holding the pen.")
                    .font(.serif(19)).foregroundStyle(muted)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    figure(model.today.turns, "turns")
                    figure(model.today.commands, "commands")
                    if model.today.linesAdded > 0 { figure(model.today.linesAdded, "lines added") } else { figure(model.today.edits, "edits") }
                }
                DayRibbon(hours: model.today.hours, currentHour: Calendar.current.component(.hour, from: model.now))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(story).font(.geist(11.5)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { ShareCardExporter.exportToday(model: model) } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 11)) }
                        .buttonStyle(QuietButton()).help("Save today as an image").accessibilityLabel("Share today")
                }
            }
        }
    }
    private func figure(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.formatted()).font(.geist(32, .light)).monospacedDigit().tracking(-1).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.geist(11.5)).foregroundStyle(faint)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var todayMoments: Int { model.unlockedMoments.filter { Journal.dayKey($0.1.date) == model.today.day }.count }
    private var story: AttributedString {
        var parts: [String] = []
        if let hour = model.today.busiestHour { parts.append("Busiest around **\(String(format: "%02d:00", hour))**.") }
        if model.today.asks > 0 { parts.append("Needed you **\(model.today.asks)×**.") }
        if todayMoments > 0 { parts.append("**\(todayMoments) new \(todayMoments == 1 ? "medal" : "medals")**.") }
        return (try? AttributedString(markdown: parts.isEmpty ? "Just getting started." : parts.joined(separator: " "))) ?? AttributedString()
    }
}

/// 24 bars, one per hour; the busiest hours glow.
struct DayRibbon: View {
    let hours: [Int]
    let currentHour: Int
    var body: some View {
        let peak = max(1, hours.max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(hours.indices, id: \.self) { hour in
                let value = Double(hours[hour]) / Double(peak)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(value > 0.75 ? AnyShapeStyle(LinearGradient(colors: [Color(.sRGB, red: 1, green: 0.6, blue: 0.38, opacity: 1), Color(.sRGB, red: 0.79, green: 0.33, blue: 0.16, opacity: 1)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(hours[hour] == 0 ? 0.07 : 0.14 + 0.2 * value)))
                    .frame(height: hours[hour] == 0 ? 2 : 5 + 25 * value)
                    .overlay(alignment: .bottom) { if hour == currentHour { Circle().fill(ink).frame(width: 3, height: 3).offset(y: 6) } }
                    .help("\(String(format: "%02d:00", hour)) · \(hours[hour]) events")
            }
        }.frame(height: 30, alignment: .bottom).padding(.bottom, 6)
            .accessibilityElement(children: .ignore).accessibilityLabel("Activity by hour today")
    }
}

/// The medal case, grouped by metal, rarest first.
struct MomentsGrid: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let unlocked = Dictionary(model.unlockedMoments.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(unlocked.count) of \(Moment.allCases.count) medals").font(.serif(26))
                    Text(Rarity.allCases.map { rarity in "\(unlocked.keys.filter { $0.rarity == rarity }.count) \(rarity.title.lowercased())" }.joined(separator: " · "))
                        .font(.mono(10.5)).foregroundStyle(faint)
                }
                Spacer()
                Button { ShareCardExporter.exportToday(model: model) } label: { Label("Share today", systemImage: "square.and.arrow.up") }.buttonStyle(QuietButton())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(accent).frame(width: geometry.size.width * Double(unlocked.count) / Double(Moment.allCases.count))
                }
            }.frame(height: 2)
            ForEach(Rarity.allCases.reversed(), id: \.self) { rarity in
                VStack(alignment: .leading, spacing: 10) {
                    Kicker(text: rarity.title)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), alignment: .leading, spacing: 14) {
                        ForEach(Moment.allCases.filter { $0.rarity == rarity }, id: \.self) { moment in
                            let record = unlocked[moment]
                            VStack(spacing: 7) {
                                Medal(moment: moment, unlocked: record != nil, size: 50)
                                Text(record == nil ? "Locked" : moment.title).font(.geist(11, .medium)).foregroundStyle(record == nil ? faint : ink)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Text(record.map { caption($0) } ?? moment.hint).font(.geist(9.5)).foregroundStyle(faint)
                                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { if record != nil { ShareCardExporter.exportMedal(moment, model: model) } }
                            .help(record == nil ? "Hint: \(moment.hint)" : "\(moment.blurb) Click to share.")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(record == nil ? "Locked \(rarity.title) medal. Hint: \(moment.hint)" : "\(moment.title), \(rarity.title). \(moment.blurb)")
                        }
                    }
                }
            }
            Text("Medals stay on this Mac. Bit only counts events; it never reads your prompts or code.")
                .font(.geist(11)).foregroundStyle(faint).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func caption(_ record: MomentRecord) -> String {
        let date = Journal.dayKey(record.date) == Journal.dayKey(model.now) ? "Today" : record.date.formatted(.dateTime.day().month(.abbreviated))
        return record.project.map { "\(date) · \($0)" } ?? date
    }
}

/// The recap window: the card, shown at half size, plus a way to keep it.
struct RecapWindow: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            RecapCard(week: model.week, streak: model.streak, medals: model.unlockedMoments.count, end: model.now)
                .scaleEffect(0.5, anchor: .topLeading).frame(width: 540, height: 675, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            HStack {
                Text("Counts from this Mac only.").font(.geist(11)).foregroundStyle(faint)
                Spacer()
                Button { ShareCardExporter.exportWeek(model: model) } label: { Label("Save image", systemImage: "square.and.arrow.down") }.buttonStyle(PrimaryButton())
            }
        }.padding(18).background(PanelBackground()).foregroundStyle(ink).environment(\.colorScheme, .dark)
    }
}

@MainActor enum ShareCardExporter {
    static func render<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }
    static func todayCard(model: AppModel) -> ShareCard {
        let moments = model.unlockedMoments.filter { Journal.dayKey($0.1.date) == model.today.day }.map(\.0).sorted { $0.rarity > $1.rarity }
        return ShareCard(day: model.today, streak: model.streak, moments: moments, date: model.now)
    }
    static func exportToday(model: AppModel) { save(render(todayCard(model: model)), name: "Bit-\(model.today.day).png", model: model) }
    static func exportWeek(model: AppModel) {
        save(render(RecapCard(week: model.week, streak: model.streak, medals: model.unlockedMoments.count, end: model.now)), name: "Bit-week-\(model.today.day).png", model: model)
    }
    static func exportMedal(_ moment: Moment, model: AppModel) {
        guard let record = model.moments.first(where: { $0.id == moment.rawValue }) else { return }
        let number = (model.unlockedMoments.sorted { $0.1.date < $1.1.date }.firstIndex { $0.0 == moment } ?? 0) + 1
        save(render(MedalCard(moment: moment, date: record.date, number: number)), name: "Bit-medal-\(moment.rawValue).png", model: model)
    }

    private static func save(_ image: NSImage?, name: String, model: AppModel) {
        guard let image, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            model.message = "Bit could not draw this card."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { model.message = "Could not save the card: \(error.localizedDescription)" }
    }
}
