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
                    .font(.display(19)).foregroundStyle(muted)
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

@MainActor enum ShareCardExporter {
    static func render<V: View>(_ view: V, scale: CGFloat = 1) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.nsImage
    }
    static func todayCard(model: AppModel) -> ShareCard {
        let moments = model.unlockedMoments.filter { Journal.dayKey($0.1.date) == model.today.day }.map(\.0).sorted { $0.rarity > $1.rarity }
        return ShareCard(day: model.today, streak: model.streak, moments: moments, date: model.now)
    }
    static func medalCard(_ moment: Moment, model: AppModel) -> MedalCard? {
        guard let record = model.moments.first(where: { $0.id == moment.rawValue }) else { return nil }
        let number = (model.unlockedMoments.sorted { $0.1.date < $1.1.date }.firstIndex { $0.0 == moment } ?? 0) + 1
        return MedalCard(moment: moment, date: record.date, number: number)
    }
    static func image(_ kind: ShareKind, medal: Moment?, model: AppModel) -> NSImage? {
        switch kind {
        case .today: return render(todayCard(model: model))
        case .week: return render(RecapCard(week: model.week, streak: model.streak, medals: model.unlockedMoments.count, end: model.now))
        case .medal: return medal.flatMap { medalCard($0, model: model) }.flatMap { render($0) }
        }
    }
    static func fileName(_ kind: ShareKind, medal: Moment?, model: AppModel) -> String {
        switch kind {
        case .today: return "Bit-\(model.today.day).png"
        case .week: return "Bit-week-\(model.today.day).png"
        case .medal: return "Bit-medal-\(medal?.rawValue ?? "medal").png"
        }
    }
    static func exportToday(model: AppModel) { if let image = image(.today, medal: nil, model: model) { save(image, name: fileName(.today, medal: nil, model: model), model: model) } }

    @discardableResult static func save(_ image: NSImage, name: String, model: AppModel) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            model.message = "Bit could not draw this card."
            return false
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try png.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        } catch { model.message = "Could not save the card: \(error.localizedDescription)"; return false }
    }
}
