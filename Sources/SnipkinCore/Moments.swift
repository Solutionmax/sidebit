import Foundation

/// How hard a moment is to earn. Shown as the medal's metal.
public enum Rarity: Int, Comparable, Sendable, CaseIterable {
    case bronze, silver, gold, obsidian
    public var title: String { ["Bronze", "Silver", "Gold", "Obsidian"][rawValue] }
    public static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }
}

/// Unlockable memories. One line of data each; the rule lives in `earned`.
public enum Moment: String, CaseIterable, Sendable {
    case firstTurn, warmingUp, inTheZone, centurion, terminalVelocity, refactorSeason, tagTeam
    case permissionSlip, oops, nightOwl, earlyBird, weekendWarrior, streak3, streak7
    case thousandLines, marieKondo, projectHopper, marathon
    case chatterbox, bookworm, juggler, fridayDeploy, alDesko, flawless, streak14, streak30
    case club100, club1000, legend, boopEnthusiast, frequentFlyer, freshStart, holidayHacker, leapCoder

    struct Info { let title, blurb, hint, symbol: String; let rarity: Rarity }

    var info: Info {
        switch self {
        case .firstTurn: return Info(title: "Hello, world", blurb: "The first turn Bit ever watched you finish.", hint: "Every story starts somewhere", symbol: "hand.wave.fill", rarity: .bronze)
        case .warmingUp: return Info(title: "Warming up", blurb: "10 turns in one day. The laptop is warm now.", hint: "Ten of something", symbol: "flame.fill", rarity: .bronze)
        case .inTheZone: return Info(title: "In the zone", blurb: "50 turns in one day. Please drink some water.", hint: "Fifty of the same", symbol: "bolt.fill", rarity: .silver)
        case .centurion: return Info(title: "Centurion", blurb: "100 tool runs in one day. Bit lost count at 37.", hint: "A hundred tools", symbol: "shield.lefthalf.filled", rarity: .silver)
        case .terminalVelocity: return Info(title: "Terminal velocity", blurb: "50 commands in one day. The terminal needs a nap.", hint: "The terminal gets tired", symbol: "terminal.fill", rarity: .silver)
        case .refactorSeason: return Info(title: "Refactor season", blurb: "100 file edits in one day. Everything moved slightly.", hint: "Everything moves", symbol: "leaf.fill", rarity: .silver)
        case .tagTeam: return Info(title: "Tag team", blurb: "Claude and Codex both worked with you today.", hint: "Two is company", symbol: "person.2.fill", rarity: .bronze)
        case .permissionSlip: return Info(title: "Permission slip", blurb: "10 permission requests in a day. Mother, may I?", hint: "Mother, may I?", symbol: "hand.raised.fill", rarity: .bronze)
        case .oops: return Info(title: "Oops, all errors", blurb: "10 tool errors in a day. Character building.", hint: "Oops, times ten", symbol: "bandage.fill", rarity: .bronze)
        case .nightOwl: return Info(title: "Night owl", blurb: "Coding between midnight and 5 AM. The bugs are nocturnal too.", hint: "After midnight", symbol: "moon.stars.fill", rarity: .bronze)
        case .earlyBird: return Info(title: "Early bird", blurb: "Coding before 7 AM. Coffee not yet loaded.", hint: "Before the coffee", symbol: "sunrise.fill", rarity: .bronze)
        case .weekendWarrior: return Info(title: "Weekend warrior", blurb: "Finished a turn on the weekend. Rest is a feature.", hint: "Saturday or Sunday", symbol: "beach.umbrella.fill", rarity: .bronze)
        case .streak3: return Info(title: "Three in a row", blurb: "Three days in a row with Bit.", hint: "Three in a row", symbol: "3.circle.fill", rarity: .bronze)
        case .streak7: return Info(title: "A whole week", blurb: "Seven days in a row. Bit made you a tiny friendship bracelet.", hint: "Seven in a row", symbol: "7.circle.fill", rarity: .silver)
        case .thousandLines: return Info(title: "A thousand lines", blurb: "1,000 lines added in one day, as told by Claude Code.", hint: "Four digits of code", symbol: "text.append", rarity: .silver)
        case .marieKondo: return Info(title: "Marie Kondo", blurb: "Removed more than you added, at least 500 lines. It no longer sparked joy.", hint: "It no longer sparks joy", symbol: "sparkles", rarity: .gold)
        case .projectHopper: return Info(title: "Project hopper", blurb: "Five different projects in one day.", hint: "Five places at once", symbol: "shippingbox.fill", rarity: .silver)
        case .marathon: return Info(title: "Marathon", blurb: "Eight hours between your first and last turn today.", hint: "Eight long hours", symbol: "figure.run", rarity: .gold)
        case .chatterbox: return Info(title: "Chatterbox", blurb: "100 prompts in one day. Bit needs a throat lozenge.", hint: "A hundred questions", symbol: "bubble.left.and.bubble.right.fill", rarity: .silver)
        case .bookworm: return Info(title: "Bookworm", blurb: "200 file reads in one day. Speed reading unlocked.", hint: "So much reading", symbol: "book.fill", rarity: .silver)
        case .juggler: return Info(title: "Juggler", blurb: "Started 10 sessions in one day. Bit is dizzy.", hint: "Many balls in the air", symbol: "atom", rarity: .silver)
        case .fridayDeploy: return Info(title: "Friday deploy", blurb: "Ran a command on Friday after 4 PM. Brave. Very brave.", hint: "Friday, late afternoon", symbol: "exclamationmark.triangle.fill", rarity: .gold)
        case .alDesko: return Info(title: "Al desko", blurb: "Ten things happened between noon and one. Lunch is a myth.", hint: "Skipped something tasty", symbol: "fork.knife", rarity: .bronze)
        case .flawless: return Info(title: "Flawless", blurb: "20 turns in a day without a single tool error.", hint: "Twenty, and not one oops", symbol: "checkmark.seal.fill", rarity: .gold)
        case .streak14: return Info(title: "Two weeks strong", blurb: "Fourteen days in a row. Bit is framing the bracelet.", hint: "Fourteen in a row", symbol: "14.circle.fill", rarity: .gold)
        case .streak30: return Info(title: "Thirty days", blurb: "A month without missing a day. Bit is speechless, briefly.", hint: "A whole month", symbol: "30.circle.fill", rarity: .obsidian)
        case .club100: return Info(title: "Hundred club", blurb: "100 turns together since Bit arrived.", hint: "Three digits, all time", symbol: "star.fill", rarity: .bronze)
        case .club1000: return Info(title: "Thousand club", blurb: "1,000 turns together. Bit remembers every one. Roughly.", hint: "Four digits, all time", symbol: "star.circle.fill", rarity: .gold)
        case .legend: return Info(title: "Legend", blurb: "10,000 turns together. There will be a statue.", hint: "Five digits, all time", symbol: "crown.fill", rarity: .obsidian)
        case .boopEnthusiast: return Info(title: "Boop enthusiast", blurb: "Booped Bit 10 times in one day. Bit is flattered.", hint: "Hold on a little", symbol: "hand.point.up.left.fill", rarity: .bronze)
        case .frequentFlyer: return Info(title: "Frequent flyer", blurb: "Carried Bit around 20 times in one day. Miles earned.", hint: "Bit likes to travel", symbol: "airplane", rarity: .silver)
        case .freshStart: return Info(title: "Fresh start", blurb: "Coding on New Year's Day. Resolution: fewer bugs.", hint: "The first page", symbol: "sparkle", rarity: .gold)
        case .holidayHacker: return Info(title: "Holiday hacker", blurb: "Coding between 24 and 26 December. Bit brought cookies.", hint: "Tinsel and terminals", symbol: "gift.fill", rarity: .gold)
        case .leapCoder: return Info(title: "Leap coder", blurb: "Coding on 29 February. See you in four years.", hint: "A day that rarely exists", symbol: "hare.fill", rarity: .obsidian)
        }
    }
    public var title: String { info.title }
    public var blurb: String { info.blurb }
    public var hint: String { info.hint }
    public var symbol: String { info.symbol }
    public var rarity: Rarity { info.rarity }

    /// Pure unlock rules. `streak` counts consecutive days with finished turns, ending today.
    public static func earned(by day: DayJournal, streak: Int, lifetime: Lifetime = Lifetime()) -> [Moment] {
        let date = day.day.split(separator: "-").dropFirst().joined(separator: "-")
        let active = !day.isEmpty
        let rules: [(Moment, Bool)] = [
            (.firstTurn, day.turns >= 1), (.warmingUp, day.turns >= 10), (.inTheZone, day.turns >= 50),
            (.centurion, day.tools >= 100), (.terminalVelocity, day.commands >= 50), (.refactorSeason, day.edits >= 100),
            (.tagTeam, day.claudeEvents > 0 && day.codexEvents > 0), (.permissionSlip, day.asks >= 10), (.oops, day.failures >= 10),
            (.nightOwl, day.nightOwl), (.earlyBird, day.earlyBird), (.weekendWarrior, day.weekend && day.turns >= 1),
            (.streak3, streak >= 3), (.streak7, streak >= 7), (.thousandLines, day.linesAdded >= 1000),
            (.marieKondo, day.linesRemoved >= 500 && day.linesRemoved > day.linesAdded), (.projectHopper, day.projects.count >= 5),
            (.marathon, day.turns >= 2 && day.activeSpan >= 8 * 3600),
            (.chatterbox, day.prompts >= 100), (.bookworm, day.reads >= 200), (.juggler, day.sessions >= 10),
            (.fridayDeploy, day.fridayLateCommand), (.alDesko, day.hours.count == 24 && day.hours[12] >= 10),
            (.flawless, day.turns >= 20 && day.failures == 0), (.streak14, streak >= 14), (.streak30, streak >= 30),
            (.club100, lifetime.turns >= 100), (.club1000, lifetime.turns >= 1000), (.legend, lifetime.turns >= 10_000),
            (.boopEnthusiast, day.boops >= 10), (.frequentFlyer, day.carries >= 20),
            (.freshStart, active && date == "01-01"), (.holidayHacker, active && ["12-24", "12-25", "12-26"].contains(date)),
            (.leapCoder, active && date == "02-29"),
        ]
        return rules.filter(\.1).map(\.0)
    }
}
