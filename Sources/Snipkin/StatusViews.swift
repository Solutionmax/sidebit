import AppKit
import SwiftUI
import SnipkinCore

/// Bit's face on a graphite tile, lit from below by its own warm glow.
struct BitAvatar: View {
    let activity: Activity
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RadialGradient(colors: [accent.opacity(0.38), peach], center: UnitPoint(x: 0.5, y: 0.8), startRadius: 0, endRadius: size * 0.75)
            if let image = PetImages.moviePosters[activity.rawValue] ?? PetImages.moviePosters["working"] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(width: size * 1.2, height: size * 1.2).offset(y: size * 0.14)
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.27))
        .overlay(RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(hairline))
        .accessibilityHidden(true)
    }
}

/// "0:42" for live states, "2m ago" for finished ones.
func elapsedLabel(since date: Date?, now: Date, activity: Activity) -> String {
    guard let date else { return "" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if activity == .done || activity == .idle || activity == .unknown {
        return seconds < 60 ? "just now" : seconds < 3600 ? "\(seconds / 60)m ago" : "\(seconds / 3600)h ago"
    }
    return seconds < 3600 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds / 3600)h \(seconds / 60 % 60)m"
}

/// The first page Bit opens: what needs you, live sessions, today and allowance.
struct NowPage: View {
    @ObservedObject var model: AppModel
    /// Moves the window to another page, optionally picking a share card.
    let go: (SettingsPage, ShareKind?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Now", subtitle: summary)
                Spacer()
                Text("⌥ B").font(.mono(10.5, .medium)).foregroundStyle(faint)
                    .padding(.horizontal, 7).padding(.vertical, 4).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1)))
                    .help("Open this window from anywhere")
            }
            if !model.demo && model.installed.isEmpty { card { welcome } }
            if let attention = model.visibleSessions.first(where: { $0.effectiveActivity(now: model.now) == .waiting }) { urgent(attention) }
            if let update = model.update { updateBanner(update) }
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 18) {
                        card { sessions }
                        card { medals }
                        if model.demo { card { previewControls } }
                    }.frame(width: 360)
                    VStack(spacing: 18) {
                        card { TodayCard(model: model) }
                        if model.usageEnabled || model.demo {
                            card {
                                Kicker(text: "Allowance", trailing: fuelSource)
                                FuelCard(model: model, providers: fuelProviders, framed: false)
                            }
                        }
                        if let message = model.message {
                            HStack(alignment: .top) {
                                Text(message).font(.geist(11)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Button { model.message = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                            }.foregroundStyle(accent)
                        }
                    }.frame(maxWidth: .infinity)
                }.padding(.bottom, 4)
            }.scrollIndicators(.hidden)
            footer
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hairline))
    }

    private var fuelProviders: [Provider] {
        let active = Provider.allCases.filter { provider in model.visibleSessions.contains { $0.provider == provider } || model.usageSnapshot(provider) != nil }
        return active.isEmpty ? Provider.allCases : active
    }
    private var fuelSource: String {
        if model.demo { return "Example" }
        if model.usage[.claude]?.source == "Claude Code status line" { return "Live" }
        return model.refreshingUsage.isEmpty ? "Every 5 min" : "Updating"
    }

    private var summary: String {
        if model.demo { return "Preview with example data" }
        let count = model.visibleSessions.count
        let sessions = count == 0 ? "No sessions" : count == 1 ? "1 session" : "\(count) sessions"
        switch model.activity {
        case .waiting: return "Waiting on you · \(sessions)"
        case .working, .thinking: return "Busy · \(sessions)"
        default: return sessions
        }
    }

    private func urgent(_ session: Session) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised").font(.system(size: 14, weight: .medium)).foregroundStyle(rgbEmberSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.project) needs you").font(.geist(13, .medium)).lineLimit(1)
                Text("\(session.detail) · \(elapsedLabel(since: model.stateSince[session.id], now: model.now, activity: .waiting))")
                    .font(.mono(10.5)).foregroundStyle(rgbEmberSoft.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Open") { model.openSource(session) }.buttonStyle(PrimaryButton()).disabled(model.demo)
        }
        .padding(.vertical, 11).padding(.leading, 13).padding(.trailing, 10)
        .background(LinearGradient(colors: [accent.opacity(0.13), accent.opacity(0.04)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.28)))
    }
    private var rgbEmberSoft: Color { Color(.sRGB, red: 1, green: 0.66, blue: 0.47, opacity: 1) }

    private func updateBanner(_ update: UpdateInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(ice)
            Text("Sidebit \(update.version) is ready").font(.geist(12.5, .medium))
            Spacer()
            Button(model.updating ? "Installing…" : "Install") { model.installUpdate() }.buttonStyle(QuietButton()).disabled(model.updating)
        }.padding(10).background(ice.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ice.opacity(0.2)))
    }

    /// First run: two buttons away from a working companion.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Say hi to Bit.").font(.display(24))
            Text("Connect your agents and Bit will type, think, wave and celebrate with them. Everything stays on this Mac.")
                .font(.geist(12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(Provider.allCases) { provider in
                    Button("Connect \(provider.title)") { model.connect(provider) }.buttonStyle(PrimaryButton()).lineLimit(1).fixedSize()
                }
                Spacer(minLength: 0)
                Button("Preview") { model.demo = true }.buttonStyle(.plain).font(.geist(11.5, .medium)).foregroundStyle(accent)
            }
        }
    }

    @ViewBuilder private var sessions: some View {
        Kicker(text: "Sessions", trailing: model.demo ? "Example" : model.visibleSessions.isEmpty ? nil : "Live")
        if model.visibleSessions.isEmpty {
            HStack {
                Text("Room for your next big idea.").font(.display(19)).foregroundStyle(muted)
                Spacer()
                Button("Setup") { go(.connections, nil) }.buttonStyle(QuietButton())
            }
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.visibleSessions) { session in
                        let activity = session.effectiveActivity(now: model.now)
                        Button { model.selectedID = session.id } label: {
                            SessionRow(session: session, activity: activity, selected: model.selected?.id == session.id,
                                       elapsed: elapsedLabel(since: model.stateSince[session.id], now: model.now, activity: activity))
                        }.buttonStyle(.plain)
                            .contextMenu { if !model.demo { Button("Open app") { model.openSource(session) } } }
                            .accessibilityLabel("\(session.provider.title), \(session.project), \(activity.title)")
                    }
                }
            }.scrollIndicators(.hidden).frame(height: min(CGFloat(model.visibleSessions.count) * 48, 250))
        }
    }

    /// The most recent medals, and the way into the full case.
    @ViewBuilder private var medals: some View {
        let unlocked = model.unlockedMoments
        Kicker(text: "Medals", trailing: "\(unlocked.count) of \(Moment.allCases.count)")
        Button { go(.medals, nil) } label: {
            HStack(spacing: 8) {
                ForEach(unlocked.prefix(5), id: \.0) { moment, _ in Medal(moment: moment, size: 34).help("\(moment.title): \(moment.blurb)") }
                ForEach(0..<max(0, min(5, Moment.allCases.count) - unlocked.prefix(5).count), id: \.self) { _ in
                    Medal(moment: .firstTurn, unlocked: false, size: 34)
                }
                Spacer(minLength: 6)
                Text(unlocked.isEmpty ? "See what you can earn ›" : "View all ›").font(.geist(12, .medium)).foregroundStyle(muted)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Open medals, \(unlocked.count) of \(Moment.allCases.count) unlocked")
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: "Preview")
            HStack(spacing: 6) {
                ForEach([Activity.working, .thinking, .waiting, .done, .idle], id: \.rawValue) { state in
                    Button { model.gagUntil = nil; model.demoActivity = state } label: {
                        Image(systemName: state.symbol).font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 28)
                            .background(model.demoActivity == state ? accent.opacity(0.14) : surface, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(model.demoActivity == state ? accent : muted)
                    }.buttonStyle(.plain).help(state.title).accessibilityLabel(state.title)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button { model.soundsEnabled.toggle() } label: {
                Label(model.soundsEnabled ? "Sound" : "Muted", systemImage: model.soundsEnabled ? "speaker.wave.2" : "speaker.slash")
            }.buttonStyle(.plain).help("Turn event sounds on or off")
            Button { model.playTinyBreak() } label: { Label("Coffee", systemImage: "cup.and.saucer") }.buttonStyle(.plain)
                .disabled(model.activity == .waiting || model.activity == .unknown)
            Spacer()
            Button { go(.share, .week) } label: { Label("Share your week", systemImage: "calendar") }.buttonStyle(.plain)
                .foregroundStyle(model.weekReady ? accent : muted)
        }.font(.geist(11.5)).foregroundStyle(muted).labelStyle(.titleAndIcon).padding(.top, 2)
    }
}

struct SessionRow: View {
    let session: Session
    let activity: Activity
    let selected: Bool
    var elapsed = ""
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(activity == .idle || activity == .unknown ? faint.opacity(0.6) : activity == .waiting ? accent : session.provider == .codex ? ice : activity.tint)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project).font(.geist(13, .medium)).lineLimit(1)
                Text("\(session.sessionID.hasPrefix("desktop:") ? "\(session.provider == .claude ? "Claude" : "Codex") app" : session.provider.title) · \(activity == .unknown ? "No recent signal" : session.detail)")
                    .font(.geist(11.5)).foregroundStyle(faint).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(elapsed).font(.mono(11)).foregroundStyle(activity == .waiting ? accent : muted).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(selected ? Color.white.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }
}

/// Allowance as fine lines: the bar, an even-pace tick, and a quiet prediction when running ahead.
struct FuelCard: View {
    @ObservedObject var model: AppModel
    let providers: [Provider]
    var framed = true
    var body: some View {
        let content = VStack(alignment: .leading, spacing: 11) {
            ForEach(providers) { provider in rows(provider) }
            if let hint { Text(hint).font(.geist(11.5)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true) }
        }
        if framed {
            content.padding(13).background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hairline))
        } else { content }
    }

    @ViewBuilder private func rows(_ provider: Provider) -> some View {
        let name = provider == .claude ? "Claude" : "Codex"
        if !model.usageEnabled && !model.demo {
            Text("\(name) · usage paused in Settings").font(.geist(11.5)).foregroundStyle(muted)
        } else if let snapshot = model.usageSnapshot(provider) {
            ForEach(snapshot.windows) { window in
                let pace = UsagePace(window: window, now: model.now)
                let used = min(1, max(0, window.usedPercent / 100))
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("\(name) · \(window.title)").font(.geist(12)).foregroundStyle(muted)
                        Spacer()
                        Text("\(Int(window.usedPercent.rounded()))%").font(.mono(12)).foregroundStyle(tint(window.usedPercent))
                    }
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            // The scale spans the whole track, so a fuller bar reveals warmer colours.
                            LinearGradient(stops: UsageTint.stops.map { .init(color: tint($0.percent), location: $0.percent / 100) }, startPoint: .leading, endPoint: .trailing)
                                .frame(width: width)
                                .mask(alignment: .leading) { Capsule().frame(width: width * used) }
                            if let pace {
                                Rectangle().fill(faint).frame(width: 1, height: 10).offset(x: width * min(1, pace.expectedPercent / 100))
                            }
                        }
                    }.frame(height: 3)
                }
                .help("\(resetLabel(window.resetsAt))\(pace.map { " · even pace \(Int($0.expectedPercent))%" } ?? "")")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name) \(window.title), \(Int(window.usedPercent.rounded())) percent used. \(resetLabel(window.resetsAt))")
            }
            status(provider, snapshot)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(name) · \(model.refreshingUsage.contains(provider) ? "Checking your allowance…" : model.usageErrors[provider] ?? "Waiting for account data.")")
                    .font(.geist(11.5)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                if provider == .claude && model.needsKeychain && !model.claudeKeychain {
                    Button("Use Claude Code sign-in from Keychain") { model.claudeKeychain = true }.buttonStyle(QuietButton())
                }
            }
        }
    }
    private func tint(_ percent: Double) -> Color {
        let c = UsageTint.rgb(percent)
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    @ViewBuilder private func status(_ provider: Provider, _ snapshot: UsageSnapshot) -> some View {
        if !model.demo && model.now.timeIntervalSince(snapshot.fetchedAt) > 1800 {
            Text("\(provider == .claude ? "Claude" : "Codex") last seen \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))").font(.mono(10)).foregroundStyle(accent)
        }
        if provider == .claude && model.needsKeychain && !model.claudeKeychain && !model.demo {
            Button("Use Claude Code sign-in from Keychain") { model.claudeKeychain = true }.buttonStyle(QuietButton())
        }
    }

    private var hint: AttributedString? {
        let windows = providers.compactMap { model.usageSnapshot($0) }.flatMap(\.windows)
        let ahead = windows.compactMap { w in UsagePace(window: w, now: model.now).flatMap { pace in pace.runsOutAt.map { (w, $0) } } }
        guard let (window, out) = ahead.min(by: { $0.1 < $1.1 }), let reset = window.resetsAt else {
            return windows.contains { $0.usedPercent >= 90 } ? AttributedString("Almost empty. Bit is sweating in binary.") : nil
        }
        let time = { (d: Date) in Calendar.current.isDate(d, inSameDayAs: model.now) ? d.formatted(date: .omitted, time: .shortened)
                                                                                    : d.formatted(.dateTime.weekday(.wide).hour().minute()) }
        return (try? AttributedString(markdown: "\(window.title) runs out around **\(time(out))** at this pace. Resets \(time(reset)).")) ?? nil
    }
    private func resetLabel(_ date: Date?) -> String {
        guard let date else { return "Reset time unavailable" }
        let seconds = Int(date.timeIntervalSince(model.now))
        guard seconds > 0 else { return "Reset due · updating soon" }
        let hours = seconds / 3600, minutes = seconds / 60 % 60
        return hours >= 24 ? "Resets in \(hours / 24)d \(hours % 24)h" : "Resets in \(hours)h \(minutes)m"
    }
}
