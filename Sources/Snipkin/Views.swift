import AppKit
import SwiftUI
import SnipkinCore

struct SettingsCard: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    @State private var tab: Int
    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
        _tab = State(initialValue: model.settingsTab ?? (CommandLine.arguments.contains("--show-connections") ? 2 : CommandLine.arguments.contains("--show-moments") ? 3 : 0))
    }
    private let tabs = [(0, "Bit"), (3, "Medals"), (1, "Sounds"), (2, "Connections")]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Settings").font(.serif(30))
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26).background(surface, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Close settings")
            }.padding(.horizontal, 22).padding(.top, 22)
            HStack(spacing: 18) {
                ForEach(tabs, id: \.0) { id, title in
                    Button { tab = id } label: {
                        VStack(spacing: 7) {
                            Text(title).font(.geist(12.5, tab == id ? .medium : .regular)).foregroundStyle(tab == id ? ink : muted)
                            Rectangle().fill(tab == id ? accent : .clear).frame(height: 1.5)
                        }.fixedSize()
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.horizontal, 22).padding(.top, 14)
            Rectangle().fill(hairline).frame(height: 1)
            Group {
                if tab == 0 { companion }
                else if tab == 1 { sounds }
                else if tab == 3 { MomentsGrid(model: model) }
                else { connections }
            }.padding(22)
            Rectangle().fill(hairline).frame(height: 1)
            HStack {
                Button("Reset position") { model.resetPosition?() }.buttonStyle(.plain)
                Spacer()
                Text("Sidebit \(SidebitVersion.current)")
            }.font(.mono(10)).foregroundStyle(faint).padding(.horizontal, 22).padding(.vertical, 14)
        }.frame(width: 440).background(PanelBackground()).foregroundStyle(ink).environment(\.colorScheme, .dark)
    }

    private var companion: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    RadialGradient(colors: [accent.opacity(0.35), .clear], center: .bottom, startRadius: 0, endRadius: 70)
                    PetView(activity: .working, size: 92, reducedMotion: true)
                }.frame(width: 104, height: 104).background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(hairline))
                VStack(alignment: .leading, spacing: 6) {
                    Text(Bit.name).font(.serif(26))
                    Text(Bit.subtitle).font(.geist(12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    Text("Click for sessions · hold to boop · drag to move · ⌥B").font(.mono(10)).foregroundStyle(faint)
                }
            }
            group("Companion") {
                HStack { Text("Size").font(.geist(12)); Slider(value: $model.size, in: 140...250).tint(accent).accessibilityLabel("Companion size") }
                toggle("Coffee breaks while idle", value: $model.sillyMoments)
                toggle("Reduce motion", value: $model.reducedMotion)
                toggle("Keep above other windows", value: $model.floating)
                toggle("Notch alert when an agent needs you", value: $model.notchAlerts)
                toggle("Open at login", value: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                toggle("Preview with example data", value: $model.demo)
            }
            group("Updates") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.update.map { "Sidebit \($0.version) is available" } ?? "You're on \(SidebitVersion.current)").font(.geist(12.5, .medium))
                        Text(model.updateStatus ?? (model.updaterAvailable ? "Signed updates from GitHub Releases." : "Updates are not configured for this build.")).font(.geist(11)).foregroundStyle(muted)
                    }
                    Spacer()
                    if model.update != nil {
                        Button("Install and restart") { model.installUpdate() }.buttonStyle(PrimaryButton()).disabled(model.updating)
                    } else {
                        Button("Check now") { model.checkForUpdates(manual: true) }.buttonStyle(QuietButton()).disabled(!model.updaterAvailable || model.updating)
                    }
                }
                toggle("Check for updates automatically", value: $model.autoUpdate)
            }
        }
    }

    private var sounds: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("A gentle heads-up.").font(.serif(24))
                Text("A small sound when an agent needs you or finishes. Quiet the rest of the time.").font(.geist(12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
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
        VStack(alignment: .leading, spacing: 18) {
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
            group("Status line") {
                toggle("Show Bit below the Claude Code prompt", value: Binding(get: { model.statusLineInstalled }, set: { model.installStatusLine($0) }))
                note("Also delivers your real limits without extra requests. An existing status line keeps running above Bit and returns exactly as it was.")
            }
            group("Allowance") {
                toggle("Show account usage", value: $model.usageEnabled)
                toggle("Use Claude Code's sign-in from the Keychain", value: $model.claudeKeychain)
                note("macOS asks once before Sidebit may read Claude Code's Keychain item; Sidebit never changes it. Credentials only go to the matching provider, at most every five minutes.")
            }
            group("Desktop apps", badge: "Experimental") {
                toggle("Follow Claude & Codex desktop", value: $model.desktopEnabled)
                if model.desktopEnabled && !model.desktopTrusted {
                    Button("Allow Accessibility…") { model.requestDesktopAccess() }.buttonStyle(QuietButton())
                }
                note(!model.desktopEnabled ? "Off. Hooks still work." : !model.desktopTrusted ? "Accessibility permission required." : "Reads recognizable buttons only. No chat text, no browser.")
            }
            if let message = model.message { Text(message).font(.geist(11)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true) }
        }
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
