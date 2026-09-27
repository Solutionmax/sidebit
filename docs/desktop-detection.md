# Desktop apps and hover allowance

## What is supported

Local Claude Code desktop sessions use the same settings/hooks as the CLI, as documented in [Claude's desktop reference](https://code.claude.com/docs/en/desktop#shared-configuration). Sidebit's existing hooks remain the preferred source of session activity. Codex lifecycle hooks use the configured local runtime; review/trust still applies. See [Codex hooks](https://learn.chatgpt.com/docs/hooks).

The optional desktop observer targets exactly `com.anthropic.claudefordesktop` and `com.openai.codex`. It does not inspect browsers, ChatGPT, Terminal or Orca UI. Existing Terminal/Orca hooks continue working independently. The [Claude plugin documentation](https://support.claude.com/en/articles/13837440-use-plugins-in-claude) distinguishes chat from Code/Cowork: ordinary chat does not run lifecycle hooks.

## Setup

In **Settings → Connections**, enable **Follow Claude & Codex desktop**, then click **Allow Accessibility…**. Enable Sidebit in macOS **Privacy & Security → Accessibility**. macOS requires the user to grant this; Sidebit cannot grant itself permission. Detection polls every two seconds and notices permission changes without a restart. Disable the setting to clear desktop observations and stop monitoring. It is off by default on fresh installations.

Opening an app without Accessibility permission can establish presence only, shown as **Accessibility permission required**. It does not establish working, idle, or completion.

## Experimental activity inference

The observer reads the focused non-minimized window in each supported running app. It uses accessibility roles and short button labels. An enabled stop-generation button indicates work; paired approval/rejection buttons indicate a request for input; a send or empty-composer microphone button indicates an idle composer. Returning to a send button means Idle. The observer never infers Done: switching conversations can reuse the same window/composer while work continues elsewhere. Done remains a hook-backed state.

Permission loss and hidden/minimized windows produce Unknown. Incomplete or partially failed scans can retain a positively observed work or paired-approval control, but never infer Idle from missing controls. UI versions/languages can change labels; inference is intentionally marked experimental. Only the observed window is covered, not all background chats. Desktop inference does not trigger automatic sounds or recent-moment records; those remain hook-backed to avoid guessed alerts.

The allowlist is native apps only. No conversation fields, static text, window titles, input values, screenshots or transcripts are read by this observer. It examines button titles/descriptions/help in memory to match known controls and discards them after each poll. It enables Electron's accessibility tree when available. Per-app traversal is bounded by 1,200 nodes, depth 64 and a short deadline, off the main thread with one poll in flight. No desktop observations are written to session files. Hook sessions from the same app suppress the app-level observation to avoid duplicate entries.

## Allowance is a separate signal

The hover card appears after 120 ms over the companion and never takes keyboard focus. It shows the same controlling session/provider as the companion, respecting attention priority. It stays open over the companion or card, with a 250 ms exit grace period to cross the gap. Clicking the card opens session details; dragging the companion dismisses it. The full card also limits allowance rows to currently represented providers.

Usage is the existing cached **CLI account allowance**, not per-session tokens and not an independently verified desktop login. If the desktop and CLI use different accounts, these figures may differ from the desktop account. Missing windows stay missing; stale data stays labeled. Hovering does not trigger network requests. With no session or observed app, the card offers setup guidance instead of unrelated provider usage.

## Permission after an update

Ad-hoc signed builds are identified by their code hash, so macOS can treat an update as a new app. If Sidebit still says Accessibility permission required after you enabled it, switch Sidebit off and on in **Privacy & Security → Accessibility**, or remove the entry and add `/Applications/Sidebit.app` again. Sidebit never edits permission databases or bypasses the system check.
