import AppKit
import SwiftUI
import SnipkinCore
import ServiceManagement

/// Sidebit ships one companion. Its original internal name `pixel` stays in preferences and resources.
enum Bit {
    static let name = "Bit"
    static let subtitle = "Eight bits. Approximately a million feelings."
}

extension Activity {
    var tint: Color {
        switch self {
        case .working, .thinking: return adaptive(NSColor(srgbRed: 0.23, green: 0.43, blue: 0.49, alpha: 1), NSColor(srgbRed: 0.49, green: 0.76, blue: 0.84, alpha: 1))
        case .waiting: return adaptive(NSColor(srgbRed: 0.62, green: 0.34, blue: 0.10, alpha: 1), NSColor(srgbRed: 0.98, green: 0.66, blue: 0.36, alpha: 1))
        case .done: return adaptive(NSColor(srgbRed: 0.22, green: 0.44, blue: 0.32, alpha: 1), NSColor(srgbRed: 0.52, green: 0.81, blue: 0.62, alpha: 1))
        case .idle, .unknown: return adaptive(NSColor(srgbRed: 0.46, green: 0.44, blue: 0.42, alpha: 1), NSColor(srgbRed: 0.68, green: 0.66, blue: 0.64, alpha: 1))
        }
    }
    var symbol: String {
        switch self {
        case .working: return "keyboard"
        case .thinking: return "ellipsis"
        case .waiting: return "hand.raised.fill"
        case .done: return "checkmark"
        case .idle: return "moon.zzz.fill"
        case .unknown: return "questionmark"
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var completionSound: Bool { didSet { defaults.set(completionSound, forKey: "completionSound") } }
    @Published var attentionSound: Bool { didSet { defaults.set(attentionSound, forKey: "attentionSound") } }
    @Published var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: "soundVolume") } }
    @Published var recentEvents: [SessionTransition] = []
    private var transitionTracker = SessionTransitionTracker()
    private let soundPlayer = SoundPlayer()
    private var lastSoundAt = Date.distantPast
    @Published var desktopEnabled: Bool {
        didSet { defaults.set(desktopEnabled, forKey: "desktopEnabled"); desktopMonitor.refresh(enabled: desktopEnabled && !demo) }
    }
    @Published var desktopSessions: [Session] = []
    @Published var desktopTrusted = false
    private let desktopMonitor = DesktopMonitor()
    func requestDesktopAccess() { desktopMonitor.requestAccess() }
    @Published var sessions: [Session] = []
    @Published var now = Date()
    @Published var selectedID: String?
    @Published var message: String?
    @Published var installed: Set<Provider> = []
    @Published var demo = false
    @Published var demoActivity: Activity = .waiting
    @Published var usage: [Provider: UsageSnapshot] = [:]
    @Published var usageErrors: [Provider: String] = [:]
    @Published var refreshingUsage: Set<Provider> = []
    @Published var usageEnabled: Bool {
        didSet {
            defaults.set(usageEnabled, forKey: "usageEnabled")
            if usageEnabled { refreshUsage() } else {
                usageTasks.values.forEach { $0.cancel() }
                usageTasks.removeAll(); refreshingUsage.removeAll()
            }
        }
    }
    @Published var sillyMoments: Bool { didSet { defaults.set(sillyMoments, forKey: "sillyMoments") } }
    @Published var gagUntil: Date?
    @Published var today = DayJournal(day: Journal.dayKey(Date()))
    @Published var moments: [MomentRecord] = []
    @Published var streak = 0
    @Published var celebration: Moment?
    @Published var statusLineInstalled = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var celebrationUntil = Date.distantPast
    private var overrideQuip: (text: String, until: Date)?
    private var activityStarted = Date()
    private let journal = Journal(directory: Journal.defaultDirectory)
    private let usageStore = UsageStore()
    @Published var size: Double { didSet { defaults.set(size, forKey: "size"); appearanceChanged?() } }
    @Published var reducedMotion: Bool { didSet { defaults.set(reducedMotion, forKey: "reducedMotion") } }
    @Published var floating: Bool { didSet { defaults.set(floating, forKey: "floating"); appearanceChanged?() } }
    var appearanceChanged: (() -> Void)?
    var showSettings: (() -> Void)?
    var resetPosition: (() -> Void)?
    var showRecap: (() -> Void)?
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private let files = SessionFiles(directory: SessionFiles.defaultDirectory)
    private let readQueue = DispatchQueue(label: "net.solutionmax.snipkin.sessions", qos: .utility)
    private var isRefreshing = false
    private var usageReader: UsageReader { UsageReader(allowKeychain: claudeKeychain) }
    /// Opt-in: read Claude Code's own Keychain sign-in when the file copy is missing or expired.
    @Published var claudeKeychain: Bool {
        didSet {
            defaults.set(claudeKeychain, forKey: "claudeKeychain")
            usageCooldown.reset(.claude); usageErrors[.claude] = nil; needsKeychain = false
            refreshUsage()
        }
    }
    @Published var needsKeychain = false
    /// The settings tab to open next, for example after clicking a medal.
    var settingsTab: Int?
    var settingsShare: ShareKind?
    @Published var notchAlerts: Bool { didSet { defaults.set(notchAlerts, forKey: "notchAlerts") } }
    // MARK: Updates
    @Published var autoUpdate: Bool { didSet { defaults.set(autoUpdate, forKey: "autoUpdate") } }
    @Published var update: UpdateInfo?
    @Published var updateStatus: String?
    @Published var updating = false
    private let updater = Updater()
    var updaterAvailable: Bool { updater != nil }
    private var nextUpdateCheck = Date().addingTimeInterval(60)
    @Published var week = WeekSummary(days: [])
    @Published var weekReady = false
    /// When each visible session entered its current state, for the live timers.
    @Published var stateSince: [String: Date] = [:]
    private var seenStates: [String: Activity] = [:]
    private var usageTasks: [Provider: Task<Void, Never>] = [:]
    private let usageCooldown = UsageCooldown()
    private var lastGag = Date()
    private var idleSince = Date()
    private var lastActivity: Activity = .idle

    init() {
        // Keep appearance preferences when upgrading from the first development name.
        let preferences = UserDefaults.standard
        if !preferences.bool(forKey: "migratedMaatje") {
            let old = UserDefaults(suiteName: "net.solutionmax.maatje")
            for key in ["pet", "size", "reducedMotion", "floating", "petX", "petY"] where preferences.object(forKey: key) == nil {
                if let value = old?.object(forKey: key) { preferences.set(value, forKey: key) }
            }
            preferences.set(true, forKey: "migratedMaatje")
        }
        desktopEnabled = preferences.bool(forKey: "desktopEnabled")
        soundsEnabled = preferences.bool(forKey: "soundsEnabled")
        completionSound = preferences.object(forKey: "completionSound") == nil ? true : preferences.bool(forKey: "completionSound")
        attentionSound = preferences.object(forKey: "attentionSound") == nil ? true : preferences.bool(forKey: "attentionSound")
        soundVolume = preferences.object(forKey: "soundVolume") == nil ? 0.45 : min(1, max(0, preferences.double(forKey: "soundVolume")))
        let storedSize = UserDefaults.standard.double(forKey: "size")
        size = storedSize == 0 ? 190 : min(250, max(140, storedSize))
        reducedMotion = UserDefaults.standard.bool(forKey: "reducedMotion")
        floating = UserDefaults.standard.object(forKey: "floating") == nil ? true : UserDefaults.standard.bool(forKey: "floating")
        usageEnabled = UserDefaults.standard.object(forKey: "usageEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "usageEnabled")
        sillyMoments = UserDefaults.standard.object(forKey: "sillyMoments") == nil ? true : UserDefaults.standard.bool(forKey: "sillyMoments")
        claudeKeychain = preferences.bool(forKey: "claudeKeychain")
        notchAlerts = preferences.object(forKey: "notchAlerts") == nil ? true : preferences.bool(forKey: "notchAlerts")
        autoUpdate = preferences.object(forKey: "autoUpdate") == nil ? true : preferences.bool(forKey: "autoUpdate")
        demo = CommandLine.arguments.contains("--demo")
        desktopMonitor.receive = { [weak self] sessions, trusted in
            self?.desktopSessions = sessions
            self?.desktopTrusted = trusted
        }
        for provider in Provider.allCases {
            if let stored = usageStore.load(provider) { usage[provider] = stored }
            let next = usageCooldown.nextRead(for: provider)
            if next > Date() {
                usageErrors[provider] = "Usage refresh paused until \(next.formatted(date: .omitted, time: .shortened))."
            }
        }
        refreshInstallations()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var visibleSessions: [Session] {
        let values = demo ? [
            Session(sessionID: "demo-claude", provider: .claude, cwd: "/Example/Website", activity: demoActivity,
                    detail: demoActivity == .waiting ? "Permission needed" : "Running command", updatedAt: now),
            Session(sessionID: "demo-codex", provider: .codex, cwd: "/Example/API", activity: .working,
                    detail: "Editing files", updatedAt: now, model: "Example model"),
            Session(sessionID: "demo-docs", provider: .claude, cwd: "/Example/Docs", activity: .idle,
                    detail: "Response complete", updatedAt: now.addingTimeInterval(-120))
        ] : sessions + desktopSessions.filter { desktop in
            !sessions.contains { $0.appBundlePath != nil && $0.appBundlePath == desktop.appBundlePath }
        }
        return values.sorted {
            let a = $0.effectiveActivity(now: now).priority, b = $1.effectiveActivity(now: now).priority
            return a == b ? $0.updatedAt > $1.updatedAt : a > b
        }
    }
    var selected: Session? { visibleSessions.first { $0.id == selectedID } ?? visibleSessions.first }
    var controllingSession: Session? { visibleSessions.first }
    var companionContext: String {
        if demo { return "Preview · \(demoActivity.title)" }
        guard let session = controllingSession else { return "Ready when you are" }
        return "\(session.project) · \(session.effectiveActivity(now: now).title)"
    }
    func previewSound(_ activity: Activity) { soundPlayer.play(activity, volume: soundVolume) }

    /// Clearly fictional numbers for the preview and README screenshots.
    static func sampleDay(_ now: Date) -> (DayJournal, [MomentRecord]) {
        var day = DayJournal(day: Journal.dayKey(now))
        (day.turns, day.commands, day.edits, day.asks, day.tools) = (37, 52, 64, 6, 141)
        day.projects = ["Example Website", "Example API"]
        day.sessionLines = ["demo": [1284, 311]]
        day.hours = [0, 0, 0, 0, 0, 0, 0, 0, 4, 9, 14, 8, 3, 0, 5, 11, 13, 7, 0, 10, 0, 0, 0, 0]
        let moments = [Moment.tagTeam, .terminalVelocity, .thousandLines].map { MomentRecord(id: $0.rawValue, date: now, project: "Example API", seen: true) }
        return (day, moments)
    }

    private func trackStates() {
        var next: [String: Date] = [:]
        for session in visibleSessions {
            let state = session.effectiveActivity(now: now)
            next[session.id] = seenStates[session.id] == state ? stateSince[session.id] ?? now : (state == .done || state == .idle ? session.updatedAt : now)
            seenStates[session.id] = state
        }
        seenStates = seenStates.filter { next[$0.key] != nil }
        if next != stateSince { stateSince = next }
    }

    private func checkWeekRecap() {
        let calendar = Calendar.current
        guard !demo, calendar.component(.weekday, from: now) == 6, calendar.component(.hour, from: now) >= 15, week.turns > 0 else { return }
        let key = Journal.dayKey(now)
        guard defaults.string(forKey: "weekRecapShown") != key else { return }
        defaults.set(key, forKey: "weekRecapShown")
        weekReady = true
        say(Quips.weekReady, for: 8)
    }

    var lowFuel: Bool {
        guard let provider = controllingSession?.provider, let snapshot = usageSnapshot(provider) else { return false }
        return snapshot.windows.contains { $0.usedPercent >= 90 && ($0.resetsAt ?? .distantFuture) > now }
    }

    private var lastWeekRead = Date.distantPast
    private func receive(_ loaded: [Session], day: DayJournal, moments: [MomentRecord], streak: Int, statusUsage: UsageSnapshot?, week: WeekSummary?) {
        if let week, week != self.week { self.week = week }
        defer { trackStates(); checkWeekRecap() }
        if demo {
            let sample = Self.sampleDay(now)
            if today != sample.0 { today = sample.0 }
            if self.moments != sample.1 { self.moments = sample.1 }
            self.streak = 4
            // Seven real dates with varied rhythm, so previews and README images read naturally.
            var days = (0..<7).map { offset -> DayJournal in
                var day = sample.0
                day.day = Journal.dayKey(Calendar.current.date(byAdding: .day, value: offset - 6, to: now) ?? now)
                day.hours = day.hours.enumerated().map { hour, value in value == 0 ? 0 : max(1, value + (hour * 7 + offset * 5) % 6 - 3) }
                day.claudeEvents = 70; day.codexEvents = 30
                return day
            }
            days[2].turns = 61; days[3].hours[2] = 4; days[3].hours[1] = 2
            days[5].hours = days[5].hours.map { $0 / 3 }; days[5].turns = 8
            self.week = WeekSummary(days: days)
            if loaded != sessions { sessions = loaded }
            return
        }
        if day != today { today = day }
        if moments != self.moments { self.moments = moments }
        if streak != self.streak { self.streak = streak }
        if let statusUsage, statusUsage.fetchedAt > (usage[.claude]?.fetchedAt ?? .distantPast) { usage[.claude] = statusUsage; usageErrors[.claude] = nil }
        celebrateNextMoment()
        let events = transitionTracker.consume(loaded, now: now)
        if !events.isEmpty {
            recentEvents = Array((events.sorted { $0.date > $1.date } + recentEvents).prefix(6))
            let audible = events.filter { ($0.activity == .waiting && attentionSound) || ($0.activity == .done && completionSound) }
            if soundsEnabled && !demo && now.timeIntervalSince(lastSoundAt) >= 3,
               let event = audible.sorted(by: { $0.activity.priority > $1.activity.priority }).first {
                soundPlayer.play(event.activity, volume: soundVolume)
                lastSoundAt = now
            }
        }
        if loaded != sessions { sessions = loaded }
    }

    var activity: Activity { demo ? demoActivity : visibleSessions.first?.effectiveActivity(now: now) ?? .idle }
    /// What Bit shows: a fresh memory briefly borrows the celebration, never over a request for input.
    var displayActivity: Activity { celebration != nil && activity != .waiting ? .done : activity }

    var isGag: Bool { activity != .waiting && activity != .unknown && celebration == nil && (gagUntil ?? .distantPast) > now }
    var hasUrgentQuip: Bool { activity != .waiting && (celebration != nil || (overrideQuip?.until ?? .distantPast) > now) }
    var quip: String {
        if let celebration, activity != .waiting { return "New moment: \(celebration.title)!" }
        if let overrideQuip, overrideQuip.until > now, activity != .waiting { return overrideQuip.text }
        let elapsed = max(0, now.timeIntervalSince(isGag ? (gagUntil ?? now).addingTimeInterval(-18) : activityStarted))
        let seed = Int(activityStarted.timeIntervalSince1970) &+ Int(elapsed / 24)
        if isGag { return Quips.coffee[abs(seed) % Quips.coffee.count] }
        let busy = Set(visibleSessions.filter { [.working, .thinking].contains($0.effectiveActivity(now: now)) }.map(\.provider))
        let context = Quips.Context(activity: activity, detail: controllingSession?.detail ?? "", provider: controllingSession?.provider,
                                    hour: Calendar.current.component(.hour, from: now), bothAgentsBusy: busy.count > 1, lowFuel: lowFuel)
        return Quips.line(context, seed: seed)
    }

    /// The small second line under Bit's bubble: what the joke is about.
    var quipContext: String? {
        guard activity != .unknown, let session = controllingSession else { return nil }
        if celebration != nil && activity != .waiting { return nil }
        return "\(session.project) · \(session.detail)"
    }

    func say(_ lines: [String], for seconds: TimeInterval = 2.5) {
        guard !lines.isEmpty, overrideQuip.map({ $0.until <= now }) ?? true else { return }
        overrideQuip = (lines[Int.random(in: 0..<lines.count)], Date().addingTimeInterval(seconds))
        now = Date()
    }
    func carried() { say(Quips.carried); record(.carry) }
    func boop() { say(Quips.boop, for: 3); record(.boop) }
    private func record(_ interaction: Journal.Interaction) {
        guard !demo else { return }
        let journal = self.journal
        readQueue.async { _ = try? journal.record(interaction) }
    }

    /// Checks GitHub Releases; runs at most every six hours unless asked.
    func checkForUpdates(manual: Bool = false) {
        guard let updater, !updating, manual || (autoUpdate && !demo && now >= nextUpdateCheck) else { return }
        nextUpdateCheck = now.addingTimeInterval(6 * 3600)
        if manual { updateStatus = "Checking…" }
        Task {
            do {
                let found = try await updater.check()
                update = found
                updateStatus = found == nil ? (manual ? "Sidebit is up to date." : nil) : nil
                if found != nil && !manual { say(["A new me is ready. Shiny!", "Update available. I got a haircut."], for: 6) }
                // Release testing only: the archive still has to pass the signature check.
                if found != nil && updater.isTestFeed && CommandLine.arguments.contains("--auto-install-update") { installUpdate() }
            } catch { if manual { updateStatus = error.localizedDescription } }
        }
    }

    /// Downloads, verifies the signature, swaps the app and relaunches.
    func installUpdate() {
        guard let updater, let update, !updating else { return }
        updating = true
        updateStatus = "Downloading and verifying \(update.version)…"
        Task {
            do {
                let staged = try await updater.prepare(update, bundleIdentifier: Bundle.main.bundleIdentifier ?? "net.solutionmax.snipkin")
                try Updater.scheduleInstall(update: staged, replacing: Bundle.main.bundleURL, pid: ProcessInfo.processInfo.processIdentifier)
                updateStatus = "Restarting…"
                NSApp.terminate(nil)
            } catch {
                updating = false
                updateStatus = error.localizedDescription
            }
        }
    }
    var unlockedCount: Int { moments.count }

    private func celebrateNextMoment() {
        if celebration != nil, now < celebrationUntil { return }
        celebration = nil
        // A request for input comes first; the memory waits its turn.
        guard !demo, activity != .waiting, let next = moments.first(where: { !$0.seen }).flatMap({ Moment(rawValue: $0.id) }) else { return }
        celebration = next
        celebrationUntil = now.addingTimeInterval(11)
        if soundsEnabled && completionSound { soundPlayer.play(.done, volume: soundVolume) }
        moments = moments.map { var r = $0; if r.id == next.rawValue { r.seen = true }; return r }
        let journal = self.journal
        readQueue.async { try? journal.markSeen(id: next.rawValue) }
    }

    var unlockedMoments: [(Moment, MomentRecord)] {
        moments.compactMap { record in Moment(rawValue: record.id).map { ($0, record) } }.sorted { $0.1.date > $1.1.date }
    }

    func installStatusLine(_ enabled: Bool) {
        do {
            if enabled { try installer.installStatusLine() } else { try installer.uninstallStatusLine() }
            message = enabled ? "Bit joined your Claude Code status line. Existing status lines keep running above Bit." : "The status line is back the way you had it."
        } catch { message = "Could not update the status line: \(error.localizedDescription)" }
        refreshInstallations()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { message = "macOS did not change the login item. Move Sidebit to Applications and try again." }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func playTinyBreak() {
        guard activity != .waiting && activity != .unknown && celebration == nil else { return }
        gagUntil = Date().addingTimeInterval(18)
        lastGag = Date()
    }

    func usageSnapshot(_ provider: Provider) -> UsageSnapshot? {
        if demo {
            return UsageSnapshot(provider: provider, windows: [
                UsageWindow(id: "demo-primary", title: "5-hour", usedPercent: provider == .claude ? 38 : 16,
                            resetsAt: now.addingTimeInterval(2 * 3600 + 24 * 60), durationMinutes: 300),
                UsageWindow(id: "demo-secondary", title: "7-day", usedPercent: provider == .claude ? 67 : 28,
                            resetsAt: now.addingTimeInterval(3 * 86400 + 7 * 3600), durationMinutes: 10080)
            ], fetchedAt: now, source: "Example data", plan: "Demo")
        }
        return usage[provider]
    }

    func refreshUsage() {
        guard usageEnabled && !demo else { return }
        for provider in Provider.allCases {
            guard usageTasks[provider] == nil, now >= usageCooldown.nextRead(for: provider) else { continue }
            // Claude Code already hands Bit first-party limits through the status line; no extra request needed.
            if let live = usage[provider], live.source == "Claude Code status line", now.timeIntervalSince(live.fetchedAt) < 600 { continue }
            refreshingUsage.insert(provider)
            usageCooldown.postpone(provider)
            usageTasks[provider] = Task { [weak self, usageReader] in
                do {
                    let value = try await usageReader.fetch(provider)
                    guard !Task.isCancelled, let self, self.usageEnabled else { return }
                    self.usage[provider] = value
                    self.usageErrors[provider] = nil
                    try? self.usageStore.save(value)
                } catch {
                    guard !Task.isCancelled, let self, self.usageEnabled else { return }
                    self.usageErrors[provider] = error.localizedDescription
                    if case UsageFailure.needsKeychain = error { self.needsKeychain = true }
                    if case UsageFailure.rateLimited(let retry) = error {
                        self.usageCooldown.postpone(provider, by: retry)
                        let next = self.usageCooldown.nextRead(for: provider)
                        self.usageErrors[provider] = "Usage refresh rate limited. Next attempt at \(next.formatted(date: .omitted, time: .shortened))."
                    }
                }
                guard let self else { return }
                self.refreshingUsage.remove(provider)
                self.usageTasks[provider] = nil
            }
        }
    }

    func refresh() {
        now = Date()
        desktopMonitor.refresh(enabled: desktopEnabled && !demo)
        refreshUsage()
        checkForUpdates()
        let state = activity
        if state != lastActivity { idleSince = now; activityStarted = now; lastActivity = state }
        if state == .waiting { gagUntil = nil }
        if sillyMoments && !reducedMotion && state == .idle && now.timeIntervalSince(idleSince) > 45 && now.timeIntervalSince(lastGag) > 90 {
            playTinyBreak()
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        let files = self.files, journal = self.journal, usageStore = self.usageStore, date = now
        // The week changes slowly; read seven days once a minute, not every tick.
        let readWeek = now.timeIntervalSince(lastWeekRead) >= 60
        if readWeek { lastWeekRead = now }
        readQueue.async { [weak self] in
            let loaded = files.load(now: date)
            let day = journal.day(date), moments = journal.moments(), streak = journal.streak(endingOn: date)
            let week = readWeek ? WeekSummary(days: journal.week(endingOn: date)) : nil
            let statusUsage = usageStore.load(.claude).flatMap { $0.source == "Claude Code status line" ? $0 : nil }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.receive(loaded, day: day, moments: moments, streak: streak, statusUsage: statusUsage, week: week)
            }
        }
    }

    private var installer: HookInstaller {
        HookInstaller(executable: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    }

    func refreshInstallations() {
        installed = Set(Provider.allCases.filter { installer.isInstalled($0) })
        statusLineInstalled = installer.isStatusLineInstalled()
    }

    func connect(_ provider: Provider) {
        do {
            _ = try installer.install(provider)
            refreshInstallations()
            message = provider == .codex
                ? "Codex hooks are ready. Start a new Codex session and trust the Sidebit hooks when prompted."
                : "Claude Code is connected. Start a new session to receive its first status."
        } catch { message = "Could not connect: \(error.localizedDescription)" }
    }

    func disconnect(_ provider: Provider) {
        do {
            try installer.uninstall(provider)
            refreshInstallations()
            message = "Sidebit hooks for \(provider.title) have been removed."
        } catch { message = "Could not disconnect: \(error.localizedDescription)" }
    }

    func openSource(_ session: Session) {
        guard !demo else { return }
        guard let path = session.appBundlePath, path.hasSuffix(".app"), FileManager.default.fileExists(atPath: path) else {
            message = "The source app could not be identified. Open your session in Orca or your terminal."
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) { [weak self] _, error in
            if let error { Task { @MainActor in self?.message = "Could not open app: \(error.localizedDescription)" } }
        }
    }
}
