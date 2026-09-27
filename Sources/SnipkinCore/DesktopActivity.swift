/// UI controls establish only the current visible state, never successful completion.
/// Switching conversations can reuse a window and composer, so stop → send is idle.
public enum DesktopActivity {
    public static func fromControls(labels: Set<String>, enabled: Set<String>, complete: Bool) -> Activity {
        let stop = !enabled.isDisjoint(with: ["stop", "stop task", "stop response", "stop generating", "stop streaming", "stop generation", "stop turn"])
        let composer = !labels.isDisjoint(with: ["send", "send message", "send prompt", "send now", "submit prompt", "press and hold to record", "use voice mode"])
        let approval = !enabled.isDisjoint(with: ["allow once", "approve once", "allow", "approve"]) && !enabled.isDisjoint(with: ["deny", "reject", "don't allow"])
        // Positive controls remain evidence even if unrelated sidebar nodes exceed the scan budget.
        // Only an exhaustive scan may infer idle from a composer without a stop button.
        return classify(observed: complete || stop || approval, stop: stop, send: composer, approval: approval)
    }

    public static func classify(observed: Bool, stop: Bool, send: Bool, approval: Bool) -> Activity {
        guard observed else { return .unknown }
        if approval { return .waiting }
        if stop { return .working }
        if send { return .idle }
        return .unknown
    }
}
