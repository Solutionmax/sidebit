import Foundation

/// Bit's lines. Deterministic for a given seed, so a scene never flickers between jokes.
public enum Quips {
    public struct Context: Sendable {
        public var activity: Activity
        public var detail: String = ""
        public var provider: Provider?
        public var hour: Int = 12
        public var bothAgentsBusy = false
        public var lowFuel = false
        public init(activity: Activity, detail: String = "", provider: Provider? = nil, hour: Int = 12, bothAgentsBusy: Bool = false, lowFuel: Bool = false) {
            self.activity = activity; self.detail = detail; self.provider = provider; self.hour = hour; self.bothAgentsBusy = bothAgentsBusy; self.lowFuel = lowFuel
        }
    }

    public static func line(_ context: Context, seed: Int) -> String {
        let pool = candidates(context)
        return pool[abs(seed % pool.count)]
    }

    public static func candidates(_ context: Context) -> [String] {
        var pool = base[context.activity] ?? ["…"]
        if context.activity == .working, let extra = byDetail[context.detail] { pool = extra + extra + pool }
        if context.activity == .thinking && context.detail == "Recovering from an error" { pool = recovering }
        if context.activity == .waiting && context.detail == "A question for you" { pool = questions + pool }
        if context.activity == .working || context.activity == .thinking {
            if context.hour < 5 { pool += lateNight }
            else if context.hour < 8 { pool += earlyMorning }
            if context.bothAgentsBusy { pool += tagTeam }
            if context.lowFuel { pool = lowFuel + lowFuel + pool }
        }
        return pool
    }

    public static let carried = ["Wheee!", "Where are we going?", "I get desk-sick.", "New desk, who dis?", "Gently! I'm load-bearing.", "Is this a promotion?"]
    public static let coffee = ["This is a load-bearing coffee.", "Nothing spilled. Ship it.", "Decaf is a merge conflict.", "Refilling my stack."]
    public static let boop = ["Boop acknowledged.", "Hey! That tickles.", "I'm working here. Kind of.", "You found the secret button.", "+1 friendship."]

    static let base: [Activity: [String]] = [
        .working: ["Works on my laptop.", "Small paws. Big progress.", "One more tiny semicolon.", "Typing at the speed of vibes.",
                   "Look busy, the human is watching.", "It compiles in my heart.", "Adding a feature. Maybe two.", "Keyboard go brrr."],
        .thinking: ["Consulting the senior duck.", "The duck has a follow-up.", "Thinking very hard. Please clap.", "Loading a big thought…",
                    "Hmm. Hmmmm. Hmmmmmm.", "Asking my rubber duck's rubber duck.", "Reading the docs. Voluntarily."],
        .waiting: ["One tiny human, please.", "Your turn! I'll keep your place.", "A little yes would go a long way.", "Psst. You're needed.",
                   "Waiting politely. Very politely.", "The robots need an adult."],
        .done: ["I did a thing!", "That deserves a tiny trophy.", "Ship it! (After you look.)", "Another one done. Snack time?",
                "Turn complete. Tests? Your call.", "Small victory. Big rest."],
        .idle: ["Compiling dreams.", "Dreaming in lowercase.", "Nothing to do. Expertly.", "Resting my tiny CPU.", "Idle, but make it cozy.",
                "Standing by. Sitting, actually."],
        .unknown: ["Lost the thread. Still cute.", "My psychic powers are in beta.", "Signal? Hello? Anyone?", "I'll just wait here, confused."]
    ]
    static let byDetail: [String: [String]] = [
        "Running command": ["sudo make me a sandwich.", "Pressing the big terminal button.", "Running things. Carefully. Mostly.",
                            "rm -rf? Not on my watch.", "It's just a little command."],
        "Editing files": ["Moving pixels around.", "Rewriting history. Just this file.", "Fixing one bug, making friends with two.",
                          "Diff incoming!", "Tidying up the code."],
        "Reading files": ["Reading. Squinting. Understanding.", "Speed-reading your codebase.", "So that's where it was.",
                          "Nice variable names. Mostly."],
        "Searching the web": ["Googling it. Like a pro.", "Asking the internet nicely."],
        "Delegating to a helper": ["Hired a tiny intern.", "Delegation is a skill."]
    ]
    static let recovering = ["That didn't work. Plan B!", "Oops. Nobody saw that.", "Error? I prefer 'plot twist'.", "Character building in progress."]
    static let questions = ["A question for you! Multiple choice, I hope.", "Quick quiz time."]
    static let lateNight = ["It's late. The bugs are nocturnal too.", "Midnight commits hit different.", "Should we be asleep? Probably."]
    static let earlyMorning = ["Coffee not yet loaded.", "Early bird gets the merge.", "Up before the CI."]
    static let lowFuel = ["Running on fumes. Tiny fumes.", "The limit is near. I can feel it.", "Maybe save some for later?", "Sweating in binary."]
    public static let weekReady = ["Your week with Bit is ready!", "I made you a recap. It's Friday!"]
    static let tagTeam = ["Two agents, one tiny me.", "Claude and Codex, in a duet.", "Tag team! I'm the mascot."]
}
