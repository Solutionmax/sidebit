import AppKit
import SwiftUI
import SnipkinCore

/// The wide settings window: a sidebar, medals and sharing up top, settings below.
struct SettingsCard: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    @State private var page: SettingsPage
    @State private var share: ShareKind
    @State private var medal: Moment?
    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
        let arguments = CommandLine.arguments
        let fallback: SettingsPage = arguments.contains("--show-connections") ? .connections : arguments.contains("--show-moments") ? .medals
            : arguments.contains("--show-share") ? .share : arguments.contains("--show-status") ? .now : .bit
        _page = State(initialValue: model.settingsTab.flatMap(SettingsPage.init(rawValue:)) ?? fallback)
        _share = State(initialValue: model.settingsShare ?? (arguments.contains("--show-week") ? .week : .today))
        _medal = State(initialValue: model.unlockedMoments.first?.0)
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 208)
            Rectangle().fill(hairline).frame(width: 1)
            Group {
                switch page {
                case .now: NowPage(model: model) { target, card in if let card { share = card }; page = target }
                case .medals: MedalsPage(model: model, selected: $medal) { moment in medal = moment; share = .medal; page = .share }
                case .share: SharePage(model: model, kind: $share, medal: medal)
                case .bit: bitPage
                case .sounds: scrolling { PageHeader(title: "Sounds", subtitle: "A small sound when an agent needs you or finishes."); sounds }
                case .connections: scrolling { PageHeader(title: "Connections", subtitle: "What Bit follows, and how."); connections }
                }
            }
            .padding(.horizontal, 30).padding(.top, 34).padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelBackground(radius: 0)).foregroundStyle(ink).environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .onExitCommand(perform: close)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                BitAvatar(activity: model.displayActivity, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sidebit").font(.display(22))
                    Text(model.controllingSession.map { "\($0.provider.title) · \(model.activity.title)" } ?? "No agent yet").font(.mono(9.5)).foregroundStyle(faint).lineLimit(1)
                }
            }.padding(.horizontal, 8).padding(.top, 40).padding(.bottom, 18)
            SidebarItem(title: "Now", symbol: "dot.radiowaves.left.and.right", trailing: model.visibleSessions.isEmpty ? nil : "\(model.visibleSessions.count)",
                        dot: model.activity == .waiting, selected: page == .now) { page = .now }
            SidebarItem(title: "Medals", symbol: "medal", trailing: "\(model.unlockedMoments.count)/\(Moment.allCases.count)", selected: page == .medals) { page = .medals }
            SidebarItem(title: "Share", symbol: "square.and.arrow.up", dot: model.weekReady, selected: page == .share) { page = .share }
            Kicker(text: "Settings").padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 6)
            SidebarItem(title: "Bit", symbol: "face.smiling", selected: page == .bit) { page = .bit }
            SidebarItem(title: "Sounds", symbol: "speaker.wave.2", selected: page == .sounds) { page = .sounds }
            SidebarItem(title: "Connections", symbol: "powerplug", selected: page == .connections) { page = .connections }
            Spacer()
            updates.padding(.horizontal, 10)
        }
        .font(.mono(10)).foregroundStyle(faint)
        .padding(.horizontal, 12).padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.02))
    }

    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) { content() }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8) }
            .scrollIndicators(.hidden)
    }

    /// Version and updates, in the sidebar footer.
    private var updates: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Sidebit \(SidebitVersion.current)")
            if let update = model.update {
                Button(model.updating ? "Installing…" : "Install \(update.version)") { model.installUpdate() }
                    .buttonStyle(PrimaryButton()).disabled(model.updating)
            } else {
                Button(model.updating ? "Checking…" : "Check for updates") { model.checkForUpdates(manual: true) }
                    .buttonStyle(.plain).foregroundStyle(model.updaterAvailable ? muted : faint).disabled(!model.updaterAvailable || model.updating)
            }
            if let status = model.updateStatus { Text(status).font(.geist(10.5)).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
            Toggle(isOn: $model.autoUpdate) { Text("Update automatically") }.toggleStyle(.switch).controlSize(.mini).tint(accent)
        }
    }

    private var bitPage: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.047))
                    RoundedRectangle(cornerRadius: 18).fill(RadialGradient(colors: [accent.opacity(0.2), .clear], center: UnitPoint(x: 0.5, y: 0.75), startRadius: 0, endRadius: 180))
                    PetView(activity: .working, size: 180, reducedMotion: model.reducedMotion, showQuip: true,
                            quip: "Works on my laptop.", quipContext: "Bit · Compiling dreams", urgentQuip: true)
                        .padding(.top, 40)
                }
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(hairline))
                .frame(height: 330)
                Text("Click for sessions · hold to boop · drag to move · ⌥B").font(.mono(9.5)).foregroundStyle(faint)
            }.frame(width: 270)
            scrolling { BitLore(); companion }
        }
    }

    private var companion: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Companion") {
                HStack { Text("Size").font(.geist(12)); Slider(value: $model.size, in: 140...250).tint(accent).accessibilityLabel("Companion size") }
                toggle("Coffee breaks while idle", value: $model.sillyMoments)
                toggle("Reduce motion", value: $model.reducedMotion)
                toggle("Keep above other windows", value: $model.floating)
                toggle("Notch alert when an agent needs you", value: $model.notchAlerts)
                toggle("Open at login", value: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                toggle("Preview with example data", value: $model.demo)
                HStack {
                    Text("Lost Bit off screen?").font(.geist(12)).foregroundStyle(muted)
                    Spacer()
                    Button("Reset position") { model.resetPosition?() }.buttonStyle(QuietButton())
                }
            }
        }
    }

    private var sounds: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Events") {
                toggle("Enable event sounds", value: $model.soundsEnabled)
                soundRow("Turn finished", activity: .done, value: $model.completionSound)
                soundRow("Needs your input", activity: .waiting, value: $model.attentionSound)
                HStack { Image(systemName: "speaker.fill").foregroundStyle(muted); Slider(value: $model.soundVolume, in: 0...1).tint(accent).accessibilityLabel("Sound volume")
                    Text("\(Int(model.soundVolume * 100))%").font(.mono(11)).frame(width: 36, alignment: .trailing) }
            }
            note("Preview plays at this volume even when event sounds are off. Repeated status updates stay silent.")
        }
    }
    private func soundRow(_ title: String, activity: Activity, value: Binding<Bool>) -> some View {
        HStack {
            toggle(title, value: value)
            Button { model.previewSound(activity) } label: { Image(systemName: "play.fill").font(.system(size: 9)) }.buttonStyle(QuietButton()).accessibilityLabel("Preview \(title)")
        }
    }

    private var connections: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 18) { agents; statusLine }.frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 18) { allowance; desktop }.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var agents: some View {
            group("Agents") {
                ForEach(Provider.allCases) { provider in
                    HStack {
                        Circle().fill(model.installed.contains(provider) ? Activity.done.tint : faint).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.title).font(.geist(13, .medium))
                            Text(model.installed.contains(provider) ? "Hooks connected" : "Not connected").font(.geist(11)).foregroundStyle(muted)
                        }
                        Spacer()
                        if model.installed.contains(provider) {
                            Menu("Connected") { Button("Repair connection") { model.connect(provider) }; Button("Disconnect") { model.disconnect(provider) } }.menuStyle(.borderlessButton).fixedSize().font(.geist(12))
                        } else { Button("Connect") { model.connect(provider) }.buttonStyle(PrimaryButton()) }
                    }
                }
                note("Adds local status hooks and keeps a backup. Covers the CLIs, the IDE extensions, the Codex app and Claude's Code tab. Codex asks you to trust the hooks once.")
            }
    }
    private var statusLine: some View {
            group("Status line") {
                toggle("Show Bit below the Claude Code prompt", value: Binding(get: { model.statusLineInstalled }, set: { model.installStatusLine($0) }))
                note("Also delivers your real limits without extra requests. An existing status line keeps running above Bit and returns exactly as it was.")
            }
    }
    private var allowance: some View {
            group("Allowance") {
                toggle("Show account usage", value: $model.usageEnabled)
                toggle("Use Claude Code's sign-in from the Keychain", value: $model.claudeKeychain)
                note("macOS asks once before Sidebit may read Claude Code's Keychain item; Sidebit never changes it. Credentials only go to the matching provider, at most every five minutes.")
            }
    }
    @ViewBuilder private var desktop: some View {
            group("Desktop apps", badge: "Experimental") {
                toggle("Follow Claude & Codex desktop", value: $model.desktopEnabled)
                if model.desktopEnabled && !model.desktopTrusted {
                    Button("Allow Accessibility…") { model.requestDesktopAccess() }.buttonStyle(QuietButton())
                }
                note(!model.desktopEnabled ? "Off. Hooks still work." : !model.desktopTrusted ? "Accessibility permission required." : "Reads recognizable buttons only. No chat text, no browser.")
            }
            if let message = model.message { Text(message).font(.geist(11)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true) }
    }

    private func group<Content: View>(_ title: String, badge: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Kicker(text: title, trailing: badge)
            VStack(alignment: .leading, spacing: 11) { content() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hairline))
        }
    }
    private func note(_ text: String) -> some View { Text(text).font(.geist(11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true).lineSpacing(2) }
    private func toggle(_ title: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { Text(title).font(.geist(12)) }.toggleStyle(.switch).controlSize(.small).tint(accent)
    }
}

/// A glance at the session that drives Bit; hovering never fetches usage.
struct HoverCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                BitAvatar(activity: model.displayActivity, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.controllingSession?.project ?? "Ready when you are").font(.geist(14, .medium)).lineLimit(1)
                    Text(model.controllingSession == nil ? "Your next idea starts here." : model.activity == .unknown ? "Status unavailable" : "\(model.activity.title) · \(model.controllingSession?.detail ?? "")")
                        .font(.mono(10.5)).foregroundStyle(muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle().fill(model.activity.tint).frame(width: 6, height: 6)
            }
            if let session = model.controllingSession {
                FuelCard(model: model, providers: [session.provider])
            } else {
                Text("Start a connected session, or turn on desktop detection in Settings.").font(.geist(11.5)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
            Text(model.demo ? "EXAMPLE DATA · CLICK FOR DETAILS" : "CLICK FOR DETAILS · HOLD TO BOOP").font(.mono(9, .medium)).tracking(1).foregroundStyle(faint)
        }.padding(16).frame(width: 340).background(PanelBackground(radius: 18)).foregroundStyle(ink).environment(\.colorScheme, .dark)
    }
}
