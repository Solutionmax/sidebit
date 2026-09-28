import AppKit
import SwiftUI
import SnipkinCore

/// Raw values match the old tab numbers, so `model.settingsTab = 3` still opens Medals.
enum SettingsPage: Int { case bit = 0, sounds = 1, connections = 2, medals = 3, share = 5, now = 6 }

enum ShareKind: String, CaseIterable { case today = "Today", week = "This week", medal = "Medal" }

/// A page title in the wide settings window.
struct PageHeader: View {
    let title: String
    var trailing: String?
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(title) + Text(trailing.map { "  \($0)" } ?? "").foregroundColor(faint)).font(.display(34))
            Text(subtitle).font(.geist(12.5)).foregroundStyle(muted)
        }
    }
}

struct SidebarItem: View {
    let title: String
    let symbol: String
    var trailing: String?
    var dot = false
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12.5)).frame(width: 16)
                Text(title).font(.geist(13, selected ? .medium : .regular))
                Spacer(minLength: 4)
                if let trailing { Text(trailing).font(.mono(10)).foregroundStyle(faint) }
                if dot { Circle().fill(accent).frame(width: 7, height: 7).shadow(color: accent, radius: 4) }
            }
            .foregroundStyle(selected || hovered ? ink : muted)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(selected ? 0.07 : hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A band of light that crosses an unlocked medal every few seconds.
struct GlintSweep: View {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let period = 4.8, sweep = 0.9
    var body: some View {
        if !reduceMotion {
            // ponytail: one 30 fps timeline per medal; share one clock across the grid if the case ever gets large.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = (context.date.timeIntervalSinceReferenceDate + delay).truncatingRemainder(dividingBy: Self.period)
                let p = min(1, max(0, (t - (Self.period - Self.sweep)) / Self.sweep))
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.35, height: geometry.size.height * 1.6)
                        .rotationEffect(.degrees(22))
                        .offset(x: -geometry.size.width * 0.5 + p * geometry.size.width * 1.6, y: -geometry.size.height * 0.3)
                        .opacity(p > 0 && p < 1 ? 1 : 0)
                }
                .blendMode(.overlay)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

// MARK: Medals

struct MedalsPage: View {
    @ObservedObject var model: AppModel
    @Binding var selected: Moment?
    let share: (Moment) -> Void
    private var motion: Bool { !model.reducedMotion }

    var body: some View {
        let unlocked = Dictionary(model.unlockedMoments.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Medals", trailing: "\(unlocked.count) of \(Moment.allCases.count)", subtitle: "Bit hands these out for how you work. Click one to see it up close.")
                Spacer()
                HStack(spacing: 6) { ForEach(Rarity.allCases, id: \.self) { chip($0, unlocked) } }
            }
            HStack(alignment: .top, spacing: 26) {
                showcase.frame(width: 250)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Rarity.allCases, id: \.self) { tier($0, unlocked) }
                        Text("Medals stay on this Mac. Bit only counts events; it never reads your prompts or code.")
                            .font(.geist(11)).foregroundStyle(faint).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 8)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func tint(_ rarity: Rarity) -> Color { rarity == .obsidian ? accent : rarity.metal[1] }

    private func chip(_ rarity: Rarity, _ unlocked: [Moment: MomentRecord]) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint(rarity)).frame(width: 7, height: 7)
            Text("\(unlocked.keys.filter { $0.rarity == rarity }.count)/\(Moment.allCases.filter { $0.rarity == rarity }.count)")
        }
        .font(.mono(10.5)).foregroundStyle(muted).padding(.horizontal, 9).padding(.vertical, 5)
        .overlay(Capsule().strokeBorder(hairline)).help(rarity.title)
    }

    @ViewBuilder private var showcase: some View {
        let earned = model.unlockedMoments
        VStack(spacing: 0) {
            if let current = selected.flatMap({ s in earned.first { $0.0 == s } }) ?? earned.first {
                let (moment, record) = current
                Kicker(text: "Your case", trailing: moment.rarity.title)
                Medal(moment: moment, size: 118, glint: motion).padding(.top, 22).padding(.bottom, 16)
                Text(moment.title).font(.display(26)).multilineTextAlignment(.center)
                Text("\(moment.rarity.title) · \(caption(record))".uppercased()).font(.mono(10)).tracking(0.8).foregroundStyle(faint).padding(.top, 4)
                Text(moment.blurb).font(.geist(12.5)).foregroundStyle(muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12).padding(.bottom, 16)
                Button { share(moment) } label: { Label("Share medal", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButton())
                if earned.count > 1 {
                    Rectangle().fill(hairline).frame(height: 1).padding(.top, 18).padding(.bottom, 14)
                    HStack(spacing: 10) {
                        ForEach(earned.prefix(5), id: \.0) { other, _ in
                            Medal(moment: other, size: 36)
                                .overlay(alignment: .bottom) { if other == moment { Circle().fill(accent).frame(width: 4, height: 4).offset(y: 8) } }
                                .opacity(other == moment ? 1 : 0.8)
                                .onTapGesture { selected = other }.help(other.title)
                        }
                    }
                }
            } else {
                Kicker(text: "Your case")
                Medal(moment: .firstTurn, unlocked: false, size: 118).padding(.vertical, 22)
                Text("Nothing here yet").font(.display(24))
                Text("Your first medal is one finished turn away.").font(.geist(12.5)).foregroundStyle(muted).multilineTextAlignment(.center).padding(.top, 8)
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [peach, Color(white: 0.075)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 18).fill(RadialGradient(colors: [accent.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 220))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(hairline))
    }

    private func tier(_ rarity: Rarity, _ unlocked: [Moment: MomentRecord]) -> some View {
        let list = Moment.allCases.filter { $0.rarity == rarity }
        let got = list.filter { unlocked[$0] != nil }.count
        return VStack(alignment: .leading, spacing: 0) {
            Kicker(text: rarity.title, trailing: "\(got)/\(list.count)")
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(tint(rarity)).frame(width: geometry.size.width * Double(got) / Double(list.count))
                }
            }.frame(height: 2).padding(.top, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), alignment: .leading, spacing: 14) {
                ForEach(list, id: \.self) { cell($0, record: unlocked[$0]) }
            }.padding(.top, 14)
        }
    }

    private func cell(_ moment: Moment, record: MomentRecord?) -> some View {
        let isSelected = record != nil && (selected ?? model.unlockedMoments.first?.0) == moment
        return VStack(spacing: 8) {
            Medal(moment: moment, unlocked: record != nil, size: 46, glint: motion && record != nil)
                .overlay(Circle().strokeBorder(accent.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5).padding(-4))
            Text(record == nil ? moment.hint : moment.title)
                .font(.geist(11, record == nil ? .regular : .medium)).foregroundStyle(record == nil ? faint : ink)
                .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).frame(height: 96, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { if record != nil { selected = moment } }
        .help(record.map { "\(moment.blurb) \(caption($0))." } ?? "Hint: \(moment.hint)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record == nil ? "Locked \(moment.rarity.title) medal. Hint: \(moment.hint)" : "\(moment.title), \(moment.rarity.title). \(moment.blurb)")
        .accessibilityAddTraits(record == nil ? [] : .isButton)
    }

    private func caption(_ record: MomentRecord) -> String {
        let date = Journal.dayKey(record.date) == Journal.dayKey(model.now) ? "Today" : record.date.formatted(.dateTime.day().month(.abbreviated))
        return record.project.map { "\(date) · \($0)" } ?? date
    }
}

// MARK: Share

struct SharePage: View {
    @ObservedObject var model: AppModel
    @Binding var kind: ShareKind
    let medal: Moment?
    @State private var image: NSImage?
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Share", subtitle: "Pick a card, then save or copy it. Counts only, never your prompts or code.")
            Picker("Card", selection: $kind) { ForEach(ShareKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            HStack(alignment: .top, spacing: 26) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.047))
                    if let image {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.6), radius: 24, y: 14).padding(22)
                    } else {
                        Text(kind == .medal ? "Earn a medal to share it." : "Bit could not draw this card.").font(.geist(12)).foregroundStyle(faint)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(hairline))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                info.frame(width: 220)
            }
        }
        .onAppear(perform: redraw)
        .onChange(of: kind) { _, _ in redraw() }
        .onChange(of: medal) { _, _ in redraw() }
        // The journal loads after the window opens and keeps growing; redraw with the latest numbers.
        .onChange(of: model.today) { _, _ in if kind == .today { redraw() } }
        .onChange(of: model.week) { _, _ in if kind == .week { redraw() } }
        .onChange(of: model.moments.count) { _, _ in redraw() }
    }

    private var copy: (kicker: String, title: String, text: String) {
        switch kind {
        case .today: return ("Today · 1200 × 630", "Your day with Bit.", "Today's numbers, the hour ribbon and any new medals.")
        case .week: return ("This week · 1080 × 1350", "Seven days, by the hour.", "Your heatmap, the Claude and Codex split and medals collected. Bit brings a fresh one on Friday afternoon.")
        case .medal: return ("Medal · 1080 × 1080", medal?.title ?? "No medal yet", medal?.blurb ?? "Earn one and it shows up here.")
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: copy.kicker)
            Text(copy.title).font(.display(24)).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Text(copy.text).font(.geist(12.5)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true).lineSpacing(2).padding(.top, 8)
            VStack(spacing: 8) {
                Button { save() } label: { Label("Save PNG…", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
                Button { copyImage() } label: { Label("Copy image", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(QuietButton())
            }.disabled(image == nil).padding(.top, 18)
            if let status { Text(status).font(.geist(11.5)).foregroundStyle(Activity.done.tint).padding(.top, 10) }
            Spacer(minLength: 0)
        }
    }

    private func redraw() {
        status = nil
        if kind == .week { model.weekReady = false }
        image = ShareCardExporter.image(kind, medal: medal, model: model)
    }
    private func save() {
        guard let image else { return }
        if ShareCardExporter.save(image, name: ShareCardExporter.fileName(kind, medal: medal, model: model), model: model) { status = "Saved." }
    }
    private func copyImage() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        status = NSPasteboard.general.writeObjects([image]) ? "Copied. Paste it anywhere." : "Could not copy the image."
    }
}

// MARK: Bit

/// Who Bit is. Only Bit: the other cast members stay private until they ship.
struct BitLore: View {
    private let facts = [
        ("Born", "27 September 2026, the first public beta"),
        ("Always carries", "A graphite laptop"),
        ("Thinks with", "A rubber duck, consulted like a senior engineer"),
        ("Celebrates with", "A trophy lift and a wink"),
        ("On a break", "Three espresso cups, balanced far too seriously"),
    ]
    private let lines = ["Works on my laptop.", "One tiny human, please.", "I did a thing!", "This is a load-bearing coffee.", "Compiling dreams."]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Bit.name).font(.display(34))
                Text(Bit.subtitle).font(.display(17)).foregroundStyle(accent)
            }
            Text("A small orange voxel robot with a graphite laptop, and the first one on your desk. Diligent, slightly stubborn and disproportionately proud of small wins. Bit believes in every pull request.")
                .font(.geist(12.5)).foregroundStyle(muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(facts, id: \.0) { label, value in
                    HStack(alignment: .firstTextBaseline) {
                        Text(label.uppercased()).font(.mono(10)).tracking(1).foregroundStyle(faint).frame(width: 120, alignment: .leading)
                        Text(value).font(.geist(12.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.padding(.vertical, 9)
                    if label != facts.last?.0 { Rectangle().fill(hairline).frame(height: 1) }
                }
            }
            Kicker(text: "Favourite lines")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    Text("“\(line)”").font(.display(14)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.04), in: Capsule()).overlay(Capsule().strokeBorder(hairline))
                }
            }
        }
    }
}
