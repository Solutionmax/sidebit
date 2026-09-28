# Changelog

## 0.8.0-beta.1

One window.

- **Everything in one wide window.** Clicking Bit (or ⌥B) opens it on **Now**: what needs you, live sessions, today, medals and allowance. Medals, Share and the settings sit in a sidebar. The separate sessions panel and the week window are gone; hovering Bit still shows the quick glance.
- **A proper medal case.** The medal you pick sits big on the left with its story; all 34 medals sit by metal on the right, bronze first. Earned medals catch the light every few seconds (off with Reduce motion). Locked medals are a faint stamp of their real icon with the riddle as their name.
- **Share without the extra window.** Pick Today, This week or a medal, see it full size, then **Save PNG** or **Copy image**.
- **Meet Bit.** The Bit page now tells who Bit is: born 27 September 2026, what Bit always carries and a few favourite lines.
- **One clear typeface.** Geist everywhere, in the app and on the share cards. The serif is gone.
- **Updates live in the sidebar footer**, with the version and automatic updates. Reset position moved to the Bit page. Connections uses two columns.
- **Fixed: wrong Claude limits.** An idle Claude Code session kept repeating the limits of its last request through the status line, and Bit believed it. A status line reading now only counts when it is newer, so Bit fetches your real account usage again.
- **Fixed:** the share card no longer shows zero before your day has loaded, and says "One turn." instead of "1 turns."

## 0.7.0-beta.2

- **Accessibility permission now survives updates.** Sidebit is signed with a stable certificate instead of ad hoc, so following Claude Desktop chat and Cowork keeps working after an update. Coming from beta 1, remove Sidebit in *Privacy & Security → Accessibility* and add it again, once.
- **Plain status for Claude Desktop.** Bit's bubble now says *Working on it*, *Needs your approval* or *Ready* for desktop chat and Cowork.
- **Bit speaks up sooner.** The speech bubble also appears in the first seconds of a new state, so short desktop replies show it too.

## 0.7.0-beta.1

Obsidian.

- **A new look**: graphite surfaces, hairlines and one warm glow. Geist and Instrument Serif are bundled. Bit's lines appear as small serif quotes.
- **34 medals** in bronze, silver, gold and obsidian, including *Friday deploy*, *Flawless*, *Al desko*, *Leap coder*, streaks up to 30 days and lifetime clubs up to 10,000 turns. Booping and carrying Bit count too.
- **Signed over-the-air updates** from GitHub Releases, verified with Ed25519 before anything is installed.
- **Notch alert** when an agent needs you, with Later and Open.
- **⌥B** opens the panel from anywhere.
- Share cards in Obsidian: today (1200×630), your week with an hour heatmap (1080×1350), and a card per medal (1080×1080).
- The menu bar shows a small speech bubble with Bit's eyes; the eyes follow the state, and text appears only when an agent needs you.
- Medals are reachable from the panel. Claude's Keychain sign-in is read the way Claude Code reads it, so no repeated prompts.

## 0.6.0

Bit gets a memory, and a voice.

- **Allowance works with today's Claude Code on macOS**: when the sign-in file is missing or expired, Sidebit can read Claude Code's own Keychain item after you allow it once. It never refreshes or changes credentials.
- **Speech bubbles**: Bit talks in a white comic bubble with a note about what it's reacting to.
- **Sticker book**: moments are round stickers; locked ones show a riddle. New stickers pop out next to Bit with confetti.
- **A shorter, warmer panel**: Bit's face and current line in the header, live timers per session ("Needs you · 0:42"), an hour-by-hour day ribbon with one sentence about your day.
- **Fuel**: allowance bars with an even-pace marker and a prediction when you run ahead of it. Bit gets nervous near the limit.
- **Your week with Bit**: a Friday recap card (best day, latest night, Claude and Codex split), saveable as an image.
- **Menu bar** shows the short story, such as *Website needs you*.

- **Moments**: 18 unlockable memories (Night owl, Tag team, Terminal velocity, Marie Kondo, streaks and more). Bit celebrates each one as it happens; browse them under **Settings → Moments**.
- **Today with Bit**: daily turns, commands, edits, permission requests and streaks, plus a **Share** button that saves a 1200×630 postcard of your day.
- **Claude Code status line**: optional `Bit` segment below the prompt. It wraps an existing status line instead of replacing it and restores it exactly when turned off.
- **Real allowance from the status line**: Claude's 5-hour and 7-day limits arrive with every status-line update, with no extra network request. The last reading of each provider is kept across restarts with a live, updated or last-seen label.
- **Many more quips** that react to commands, edits, reads, web searches, helpers, errors, late nights, early mornings and both agents working at once.
- **Boop and carry**: hold Bit to boop it; drag it and it has opinions.
- **Welcome card** with one-click connections, **Open at login**, and a menu bar icon that mirrors Bit's state.
- Bit is now the only companion. The app icon is Bit.
- Fixed CI checking a non-existent app path; the build script derives the version from `Info.plist`.

## 0.5.6

- Claude Chat/Cowork detection scans deeper hierarchies and recognizes the empty composer.
- Hover card with allowance and reset times; experimental desktop detection; seven animated Bit scenes; optional sounds.
