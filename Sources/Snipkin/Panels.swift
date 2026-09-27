import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import SnipkinCore

final class FloatingPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey && styleMask.contains(.titled) }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

@MainActor final class PetInteractionView: NSView {
    var hovered: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered?(true) }
    override func mouseExited(with event: NSEvent) { hovered?(false) }
    var allowsDragging = true
    var clicked: (() -> Void)?
    var held: (() -> Void)?
    var dragging: (() -> Void)?
    var moved: (() -> Void)?
    private var downAt = Date.distantPast
    var contextMenu: (() -> NSMenu)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragged = false

    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        hovered?(false)
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        downAt = Date()
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard allowsDragging else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
        guard hypot(dx, dy) > 3 || dragged else { return }
        if !dragged { dragging?() }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        moved?()
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { moved?() }
        else if let held, Date().timeIntervalSince(downAt) > 0.5 { held() }
        else { clicked?() }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
}

@MainActor final class CompanionController: NSObject {
    let model: AppModel
    private(set) var petPanel: FloatingPanel!
    private(set) var statusPanel: FloatingPanel?
    private(set) var settingsPanel: FloatingPanel?
    private var statusItem: NSStatusItem!
    private var subscriptions: Set<AnyCancellable> = []
    private var clickMonitor: Any?
    private var statusHeightLimit: CGFloat = 0
    private var hoverPanel: FloatingPanel?
    private var hoverTask: DispatchWorkItem?
    private var pointerOverPet = false
    private var pointerOverHover = false
    private var hoverDismissTask: DispatchWorkItem?

    init(model: AppModel) {
        self.model = model
        super.init()
        createPet()
        createMenuBar()
        model.showSettings = { [weak self] in self?.openSettings() }
        model.resetPosition = { [weak self] in self?.resetPetPosition() }
        model.showRecap = { [weak self] in self?.showRecap() }
        registerHotKey()
        model.appearanceChanged = { [weak self] in self?.updateAppearance() }
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeCards() }
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.statusPanel?.orderOut(nil) }
        }
    }

    private func makePanel(key: Bool = false, standard: Bool = false) -> FloatingPanel {
        let panel = FloatingPanel(contentRect: .zero, styleMask: standard ? [.titled, .closable, .miniaturizable] : [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.allowsKey = key
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = key
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = key ? .normal : .floating
        panel.collectionBehavior = key ? [.moveToActiveSpace] : [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = key
        panel.isMovableByWindowBackground = key
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    private func createPet() {
        petPanel = makePanel()
        petPanel.title = "Sidebit — your companion"
        let interaction = PetInteractionView()
        interaction.setAccessibilityElement(true)
        interaction.setAccessibilityRole(.button)
        interaction.setAccessibilityLabel("Bit. Click for sessions, hold to boop, drag to move.")
        let hosting = NSHostingView(rootView: PetRoot(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        interaction.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: interaction.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: interaction.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: interaction.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: interaction.bottomAnchor)
        ])
        interaction.hovered = { [weak self] inside in self?.hoverChanged(inside) }
        interaction.clicked = { [weak self] in self?.toggleStatus() }
        interaction.moved = { [weak self] in self?.petMoved() }
        interaction.dragging = { [weak self] in self?.model.carried() }
        interaction.held = { [weak self] in self?.model.boop() }
        interaction.contextMenu = { [weak self] in self?.menu() ?? NSMenu() }
        petPanel.contentView = interaction
        updateAppearance()
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "petX") != nil {
            petPanel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY")))
            clampPet()
        } else { resetPetPosition() }
        petPanel.orderFrontRegardless()
    }

    private func hoverChanged(_ inside: Bool) {
        pointerOverPet = inside
        hoverTask?.cancel()
        guard inside else { scheduleHoverDismissal(); return }
        hoverDismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.pointerOverPet else { return }
            self.showHover()
        }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }

    private func hoverCardChanged(_ inside: Bool) {
        pointerOverHover = inside
        if inside { hoverDismissTask?.cancel() }
        else { scheduleHoverDismissal() }
    }

    private func scheduleHoverDismissal() {
        hoverDismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.pointerOverPet, !self.pointerOverHover else { return }
            self.hideHover()
        }
        hoverDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    private func hideHover() {
        hoverTask?.cancel(); hoverTask = nil
        hoverDismissTask?.cancel(); hoverDismissTask = nil
        pointerOverHover = false
        hoverPanel?.orderOut(nil)
    }

    func showHover() {
        guard statusPanel?.isVisible != true, settingsPanel?.isVisible != true else { return }
        if hoverPanel == nil {
            let panel = makePanel()
            panel.title = "Sidebit — quick glance"
            panel.hasShadow = true
            let interaction = PetInteractionView()
            interaction.allowsDragging = false
            interaction.hovered = { [weak self] inside in self?.hoverCardChanged(inside) }
            interaction.clicked = { [weak self] in self?.showStatus() }
            interaction.setAccessibilityElement(true)
            interaction.setAccessibilityRole(.button)
            interaction.setAccessibilityLabel("Show session details")
            let hosting = NSHostingView(rootView:
                FittedPanelContent(maximumHeight: 380, width: 340, onResize: { [weak self, weak panel] height in
                    panel?.setContentSize(NSSize(width: 340, height: height))
                    self?.positionHover()
                }) { [model] in HoverCard(model: model) }
            )
            hosting.translatesAutoresizingMaskIntoConstraints = false
            interaction.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: interaction.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: interaction.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: interaction.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: interaction.bottomAnchor)
            ])
            panel.contentView = interaction
            panel.setContentSize(NSSize(width: 340, height: 230))
            hoverPanel = panel
        }
        positionHover()
        hoverPanel?.orderFrontRegardless()
    }

    private func positionHover() {
        guard let panel = hoverPanel, let petPanel else { return }
        let bounds = (petPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(petPanel.frame.midX - panel.frame.width / 2, bounds.minX + 8), bounds.maxX - panel.frame.width - 8)
        let above = petPanel.frame.maxY + 7
        let y = above + panel.frame.height <= bounds.maxY ? above : max(bounds.minY + 8, petPanel.frame.minY - panel.frame.height - 7)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func createMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.button?.toolTip = "Sidebit — Claude Code + Codex"
        statusItem.menu = menu()
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        let items: [(String, Selector, String)] = [
            ("Show sessions", #selector(menuStatus), ""),
            ("Boop Bit", #selector(menuBoop), ""),
            ("Share today with Bit…", #selector(menuShare), ""),
            ("Your week with Bit…", #selector(menuRecap), ""),
            ("Check for Updates…", #selector(menuUpdate), ""),
            ("Settings…", #selector(menuSettings), ","),
            ("Reset position", #selector(menuReset), "")
        ]
        for (title, action, key) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Sidebit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func menuStatus() { showStatus() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuReset() { resetPetPosition() }
    @objc private func menuBoop() { model.boop() }
    @objc private func menuShare() { ShareCardExporter.exportToday(model: model) }
    @objc private func menuRecap() { showRecap() }
    @objc private func menuUpdate() { model.checkForUpdates(manual: true); openSettings() }

    // MARK: Notch alert

    private var notchPanel: FloatingPanel?
    private var notchSession: String?
    private var dismissedNotch: Set<String> = []
    /// A black live activity under the menu bar when an agent starts waiting. Later hides it for that request.
    private func updateNotch() {
        let waiting = model.visibleSessions.first { $0.effectiveActivity(now: model.now) == .waiting }
        let key = waiting.map { "\($0.id):\($0.updatedAt.timeIntervalSince1970)" }
        guard model.notchAlerts, !model.demo, let waiting, let key, !dismissedNotch.contains(key) else {
            if notchSession != nil { notchSession = nil; notchPanel?.orderOut(nil) }
            return
        }
        guard key != notchSession else { return }
        notchSession = key
        let panel = notchPanel ?? makePanel()
        panel.title = "Sidebit, needs you"
        panel.hasShadow = true
        let hosting = NSHostingView(rootView: NotchAlert(model: model, session: waiting, later: { [weak self] in
            guard let self else { return }
            self.dismissedNotch.insert(key); self.notchSession = nil; self.notchPanel?.orderOut(nil)
        }, open: { [weak self] in
            self?.model.openSource(waiting); self?.dismissedNotch.insert(key); self?.notchPanel?.orderOut(nil)
        }))
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.frame, let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: visible.maxY - panel.frame.height - 6))
        }
        notchPanel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 1 }
    }

    // MARK: Hotkey

    private var hotKey: EventHotKeyRef?
    /// ⌥B toggles the panel from anywhere. Carbon hotkeys need no Accessibility permission.
    private func registerHotKey() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let controller = Unmanaged<CompanionController>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { controller.toggleStatus() } }
            return noErr
        }, 1, &type, context, nil)
        let id = EventHotKeyID(signature: OSType(0x5342_4954), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private var statusSignature = ""
    /// Bit's own face in the menu bar. Text appears only when an agent needs you.
    private func updateStatusIcon() {
        let activity = model.activity
        let blink = (activity == .working || activity == .thinking) && Int(model.now.timeIntervalSince1970) % 5 == 0
        let eyes: BitGlyph.Eyes = activity == .waiting ? .wide : activity == .done ? .star : activity == .idle || activity == .unknown || blink ? .closed : .open
        let text = activity == .waiting ? " \(model.controllingSession?.project ?? "Bit") needs you" : ""
        let signature = "\(eyes)" + text
        guard signature != statusSignature, let button = statusItem?.button else { return }
        statusSignature = signature
        button.image = BitGlyph.image(eyes, tint: activity == .waiting ? .systemOrange : nil)
        button.image?.accessibilityDescription = "Sidebit, \(activity.title)"
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: String(text.prefix(30)), attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: NSColor.systemOrange])
    }

    // MARK: Moments and recap

    private var toastPanel: FloatingPanel?
    private var toastMoment: Moment?
    private func updateToast() {
        // A request for input always wins over a celebration.
        let moment = model.activity == .waiting ? nil : model.celebration
        guard moment != toastMoment else { positionToast(); return }
        toastMoment = moment
        guard let moment else { toastPanel?.orderOut(nil); return }
        let panel = toastPanel ?? makePanel()
        panel.title = "Sidebit, new moment"
        // The card draws its own soft shadow; a window shadow would trace it as a dark outline.
        panel.hasShadow = false
        // 140 pt Bit gets a 62% card, 250 pt gets the full size.
        let scale = 0.62 + 0.38 * min(1, max(0, (model.size - 140) / 110))
        let hosting = NSHostingView(rootView: MomentToast(moment: moment, count: model.unlockedCount, scale: scale))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let interaction = PetInteractionView()
        interaction.allowsDragging = false
        interaction.clicked = { [weak self] in
            self?.model.celebration = nil
            self?.model.settingsTab = 3
            self?.openSettings()
        }
        interaction.setAccessibilityElement(true)
        interaction.setAccessibilityRole(.button)
        interaction.setAccessibilityLabel("New medal: \(moment.title). Open your medals")
        interaction.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: interaction.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: interaction.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: interaction.topAnchor), hosting.bottomAnchor.constraint(equalTo: interaction.bottomAnchor)
        ])
        panel.contentView = interaction
        panel.setContentSize(hosting.fittingSize)
        toastPanel = panel
        positionToast()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 1 }
    }
    private func positionToast() {
        guard let panel = toastPanel, let petPanel, toastMoment != nil else { return }
        let bounds = (petPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let left = petPanel.frame.minX - panel.frame.width + 14
        let x = left >= bounds.minX ? left : min(petPanel.frame.maxX - 20, bounds.maxX - panel.frame.width)
        let y = min(max(petPanel.frame.midY - panel.frame.height / 2, bounds.minY), bounds.maxY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private var recapPanel: FloatingPanel?
    func showRecap() {
        hideHover()
        model.weekReady = false
        let panel = recapPanel ?? makePanel(key: true, standard: true)
        panel.title = "Your week with Bit"
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .windowBackgroundColor
        let hosting = NSHostingView(rootView: RecapWindow(model: model))
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        if recapPanel == nil { panel.center() }
        recapPanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func screensChanged() {
        clampPet()
        if settingsPanel != nil { rebuildSettingsContent(); clampSettings() }
        resizeCards()
    }

    func toggleStatus() {
        if statusPanel?.isVisible == true { statusPanel?.orderOut(nil) } else { showStatus() }
    }

    func showStatus() {
        hideHover()
        if statusPanel == nil {
            let panel = makePanel(key: true)
            panel.title = "Sidebit — sessions"
            statusPanel = panel
        }
        resizeCards()
        positionStatus()
        statusPanel?.makeKeyAndOrderFront(nil)
    }

    func openSettings() {
        hideHover()
        model.refreshInstallations()
        if settingsPanel == nil {
            let panel = makePanel(key: true, standard: true)
            panel.title = "Sidebit — settings"
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .windowBackgroundColor
            panel.setFrameAutosaveName("SnipkinSettings")
            settingsPanel = panel
            rebuildSettingsContent()
            if !panel.setFrameUsingName("SnipkinSettings") { panel.center() }
        }
        rebuildSettingsContent()
        clampSettings()
        settingsPanel?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.model.settingsTab = nil }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func rebuildSettingsContent() {
        guard let panel = settingsPanel else { return }
        let available = ((panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) - 55
        panel.contentView = NSHostingView(rootView:
            FittedPanelContent(maximumHeight: available, onResize: { [weak panel, weak self] height in
                panel?.setContentSize(NSSize(width: 420, height: height))
                self?.clampSettings()
            }) { [model, weak self] in
                SettingsCard(model: model, close: { [weak self] in self?.settingsPanel?.orderOut(nil) })
            }
        )
        panel.setContentSize(NSSize(width: 420, height: min(600, available)))
    }

    private func clampSettings() {
        guard let panel = settingsPanel, let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: min(max(panel.frame.minX, bounds.minX + 10), bounds.maxX - panel.frame.width - 10),
                                     y: min(max(panel.frame.minY, bounds.minY + 10), bounds.maxY - panel.frame.height - 10)))
    }

    private func updateAppearance() {
        guard let panel = petPanel else { return }
        panel.setContentSize(NSSize(width: max(230, model.size + 30), height: model.size + 58))
        panel.level = model.floating ? .floating : .normal
        clampPet()
        resizeCards()
    }

    func resetPetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let panel = petPanel else { return }
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 35, y: screen.visibleFrame.minY + 25))
        petMoved()
        panel.orderFrontRegardless()
    }

    private func petMoved() {
        hideHover()
        clampPet()
        UserDefaults.standard.set(petPanel.frame.minX, forKey: "petX")
        UserDefaults.standard.set(petPanel.frame.minY, forKey: "petY")
        resizeCards()
    }

    private func clampPet() {
        guard let panel = petPanel else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: min(max(panel.frame.minX, bounds.minX), bounds.maxX - panel.frame.width),
                                     y: min(max(panel.frame.minY, bounds.minY), bounds.maxY - panel.frame.height)))
    }

    private func resizeCards() {
        updateStatusIcon()
        updateToast()
        updateNotch()
        positionHover()
        if let statusPanel {
            let limit = ((petPanel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) - 55
            if statusHeightLimit != limit {
                statusHeightLimit = limit
                statusPanel.contentView = NSHostingView(rootView:
                    FittedPanelContent(maximumHeight: limit, onResize: { [weak statusPanel] height in
                        statusPanel?.setContentSize(NSSize(width: 420, height: height))
                    }) { [model] in StatusCard(model: model) }
                )
            }
        }

    }

    private func positionStatus() {
        guard let statusPanel, let petPanel else { return }
        let bounds = (petPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(petPanel.frame.midX - statusPanel.frame.width / 2, bounds.minX + 10), bounds.maxX - statusPanel.frame.width - 10)
        let above = petPanel.frame.maxY + 6
        let y = above + statusPanel.frame.height <= bounds.maxY ? above : max(bounds.minY + 10, petPanel.frame.minY - statusPanel.frame.height - 6)
        statusPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // Development-only native view captures. No desktop pixels or other apps are read.
    func captureViews(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, panel) in [("pet", petPanel), ("status", statusPanel), ("settings", settingsPanel), ("hover", hoverPanel)] {
                guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) { try data.write(to: directory.appendingPathComponent("\(name).png")) }
            }
            let cards: [(String, NSImage?)] = [("share", ShareCardExporter.render(ShareCardExporter.todayCard(model: model))),
                                               ("recap", ShareCardExporter.render(RecapCard(week: model.week, streak: model.streak, medals: model.unlockedMoments.count, end: model.now))),
                                               ("medal-card", ShareCardExporter.render(MedalCard(moment: .juggler, date: model.now, number: 7))),
                                               ("menubar", ShareCardExporter.render(HStack(spacing: 24) { ForEach([BitGlyph.Eyes.open, .closed, .wide, .star], id: \.self) { Image(nsImage: BitGlyph.image($0, tint: $0 == .wide ? .systemOrange : .white)).resizable().frame(width: 72, height: 72) } }.padding(20).background(Color.black))),
                                               ("toast", ShareCardExporter.render(MomentToast(moment: .juggler, count: 1, time: 4))),
                                               ("toast-small", ShareCardExporter.render(MomentToast(moment: .juggler, count: 1, time: 4, scale: 0.62))),
                                               ("toast-flip", ShareCardExporter.render(MomentToast(moment: .juggler, count: 1, time: 0.45))),
                                               ("toast-shine", ShareCardExporter.render(MomentToast(moment: .juggler, count: 1, time: 1.25))),
                                               ("medals", ShareCardExporter.render(HStack(spacing: 22) { ForEach([Moment.juggler, .firstTurn, .fridayDeploy, .legend], id: \.self) { Medal(moment: $0, size: 120) } }.padding(30).background(Color.black)))]
            for (name, image) in cards {
                if let tiff = image?.tiffRepresentation, let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try data.write(to: directory.appendingPathComponent("\(name).png"))
                }
            }
        } catch { fputs("Sidebit snapshot: \(error)\n", stderr) }
    }
}

private struct PetRoot: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: -5) {
            PetView(activity: model.displayActivity, size: model.size, reducedMotion: model.reducedMotion, gag: model.isGag,
                    showQuip: model.sillyMoments, quip: model.quip, quipContext: model.quipContext, urgentQuip: model.hasUrgentQuip)
            HStack(spacing: 6) {
                Circle().fill(model.activity == .waiting ? accent : model.activity.tint).frame(width: 5, height: 5)
                Text(model.companionContext).font(.geist(10.5, .medium)).lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Color(.sRGB, red: 0.086, green: 0.086, blue: 0.094, opacity: 0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .frame(maxWidth: model.size + 25)
        }
    }
}

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FittedPanelContent<Content: View>: View {
    let maximumHeight: CGFloat
    var width: CGFloat = 420
    let onResize: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 600
    var body: some View {
        ScrollView(.vertical) {
            content().fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in Color.clear.preference(key: CardHeightKey.self, value: geometry.size.height) })
        }
        .scrollIndicators(.hidden)
        .frame(width: width, height: min(contentHeight, maximumHeight))
        .onPreferenceChange(CardHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
            DispatchQueue.main.async { onResize(min(height, maximumHeight)) }
        }
        .background(PanelBackground()).clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

/// The notch alert: Bit's face, what needs you, and two choices.
private struct NotchAlert: View {
    @ObservedObject var model: AppModel
    let session: Session
    let later: () -> Void
    let open: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            BitAvatar(activity: .waiting, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.project) needs you").font(.geist(13.5, .medium)).foregroundStyle(.white).lineLimit(1)
                Text("\(session.detail) · \(elapsedLabel(since: model.stateSince[session.id], now: model.now, activity: .waiting))")
                    .font(.geist(11.5)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Later", action: later).buttonStyle(QuietButton())
            Button("Open", action: open).buttonStyle(PrimaryButton())
        }
        .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 10).frame(width: 440)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.08)))
        .padding(8)
        .environment(\.colorScheme, .dark)
    }
}
