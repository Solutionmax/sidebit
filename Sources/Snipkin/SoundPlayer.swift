import AppKit
import SnipkinCore

@MainActor
final class SoundPlayer {
    private var current: NSSound?

    init() {}

    func play(_ activity: Activity, volume: Double) {
        let name: String
        switch activity {
        case .waiting: name = "Glass"
        case .done: name = "Ping"
        default: return
        }
        current?.stop()
        current = nil
        guard volume.isFinite, volume > 0,
              let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = Float(min(volume, 1))
        current = sound
        sound.play()
    }
}
