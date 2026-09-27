import AppKit
import AVFoundation
import SwiftUI

/// Local HEVC-with-alpha films. The host owns exactly one queue and one looper.
struct BitMovieView: NSViewRepresentable {
    let url: URL
    let loops: Bool
    let onFailure: () -> Void

    static func url(for scene: String) -> URL? {
        Bundle.module.url(forResource: scene, withExtension: "mov", subdirectory: "Resources/BitMovies")
    }

    func makeNSView(context: Context) -> BitMovieHost { BitMovieHost() }
    func updateNSView(_ view: BitMovieHost, context: Context) {
        view.configure(url: url, loops: loops, onFailure: onFailure)
    }
    static func dismantleNSView(_ view: BitMovieHost, coordinator: ()) { view.dispose() }
}

final class BitMovieHost: NSView {
    private let movieLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var itemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var loopObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var source: URL?
    private var onFailure: (() -> Void)?
    private var ended = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        movieLayer.videoGravity = .resizeAspect
        movieLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(movieLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        movieLayer.frame = bounds
        CATransaction.commit()
    }

    func configure(url: URL, loops: Bool, onFailure: @escaping () -> Void) {
        self.onFailure = onFailure
        guard source != url else { return }
        dispose()
        self.onFailure = onFailure
        source = url
        guard url.isFileURL else { fail(); return }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = loops ? .advance : .pause
        self.player = player
        movieLayer.player = player
        itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self, weak player] _, _ in
            DispatchQueue.main.async { [weak self, weak player] in
                guard let self, let player, self.player === player else { return }
                self.statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self, weak player] item, _ in
                    guard item.status == .failed else { return }
                    DispatchQueue.main.async { [weak self, weak player] in
                        guard let self, let player, self.player === player, player.currentItem === item else { return }
                        self.fail()
                    }
                }
            }
        }
        let item = AVPlayerItem(url: url)
        if loops {
            let looper = AVPlayerLooper(player: player, templateItem: item)
            self.looper = looper
            loopObservation = looper.observe(\.status, options: [.initial, .new]) { [weak self, weak player] looper, _ in
                guard looper.status == .failed else { return }
                DispatchQueue.main.async { [weak self, weak player] in
                    guard let self, let player, self.player === player else { return }
                    self.fail()
                }
            }
        } else {
            player.insert(item, after: nil)
            notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                guard let self, self.player?.currentItem === item else { return }
                self.ended = true
                self.player?.pause()
            })
        }
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            guard let self, let item = notification.object as? AVPlayerItem, item === self.player?.currentItem else { return }
            self.fail()
        })
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.updatePlayback() })
        }
        updatePlayback()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updatePlayback() }
    override func viewDidHide() { super.viewDidHide(); updatePlayback() }
    override func viewDidUnhide() { super.viewDidUnhide(); updatePlayback() }

    private func updatePlayback() {
        if let window, window.isVisible, window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor, !ended {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private func fail() {
        // KVO can arrive off the main thread; avoid changing SwiftUI state during updateNSView.
        let failedSource = source
        DispatchQueue.main.async { [weak self] in
            guard let self, self.source == failedSource else { return }
            self.player?.pause()
            self.onFailure?()
        }
    }

    func dispose() {
        player?.pause()
        itemObservation = nil
        statusObservation = nil
        loopObservation = nil
        looper?.disableLooping()
        looper = nil
        movieLayer.player = nil
        player?.removeAllItems()
        player = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        source = nil
        ended = false
        onFailure = nil
    }

    deinit { dispose() }
}
