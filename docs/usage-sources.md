# Account usage sources

## Preferred: the Claude Code status line

When **Settings → Connections → Show Bit below the prompt** is on, Claude Code runs `Sidebit --statusline` and passes its documented [status-line JSON](https://code.claude.com/docs/en/statusline) on standard input. Sidebit reads only `rate_limits.five_hour`, `rate_limits.seven_day`, the workspace folder name, `session_id` and the cumulative `cost.total_lines_added`/`total_lines_removed`. The snapshot is stored in `~/Library/Application Support/Snipkin/usage/claude.json`. While it is younger than ten minutes, Sidebit makes no Claude usage request at all. `rate_limits` is present only for Pro and Max subscribers after the first response of a session.

An existing `statusLine` is saved to `~/Library/Application Support/Snipkin/statusline.json`, runs first with the same input, and is printed unchanged. Turning the option off restores the original object exactly.

## Fallback: account endpoints

Sidebit reads account quota, not context-window fullness. Only provider-returned windows are displayed. A Codex primary window can be weekly; a missing secondary window does not mean 0% usage. Claude's `five_hour` and `seven_day` names define their durations; Codex uses `limit_window_seconds`. Values outside 0–100, missing utilization, malformed dates and empty responses fail visibly. A legitimate returned zero remains zero.

## Credentials and requests

- Claude: read `~/.claude/.credentials.json`, `claudeAiOauth.accessToken`; GET `https://api.anthropic.com/api/oauth/usage`, with the OAuth beta header. This is an undocumented account endpoint, not a supported public API. The installed first-party Claude Code 2.1.283 binary was checked for the exact endpoint, official API host, beta identifier and window keys; only boolean match results were printed. [Anthropic's own issue tracker](https://github.com/anthropics/claude-code/issues/30930) also records this endpoint and possible persistent throttling.
- Codex: read `~/.codex/auth.json`, `tokens.access_token` and optional `tokens.account_id`; GET `https://chatgpt.com/backend-api/wham/usage`. Request construction follows the [first-party Codex backend client](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client.rs) and its [rate-limit usage implementation](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client/rate_limit_resets.rs). This internal HTTP API can change without notice. It does not opt into reserve usage or consume reset credits.

The documented Codex app-server account API is a potential future adapter. Sidebit currently avoids launching an app-server that might refresh or persist authentication. No refresh tokens are read by the reader's extraction logic or used, no login changes occur, and API keys are not accepted as subscription authentication. Standard credential file locations are supported; custom homes, keychain-only credentials, managed/FedRAMP routing and API-key billing are not automatically discovered. Sign in with the relevant CLI when existing credentials expire. No general keychain scanning occurs.

The network session is ephemeral, disables cookies and caching, rejects every redirect (including same-host redirects), and uses fixed HTTPS destinations. Credentials never enter logs, snapshots, subprocess arguments, error messages or repository files. Requests time out after 15 seconds of inactivity and 20 seconds overall; response and credential reads are limited to 256 KiB. HTTP error bodies are never exposed. No conversation logs or prompts are read. Tokens today and current model remain unavailable because account quota responses do not supply reliable values for them.

## Caller behavior

`UsageReader.fetch` is a single read with no automatic retry, credential refresh or persistence. The dashboard should poll no more often than every five minutes per provider, prevent overlapping reads, respect `UsageFailure.rateLimited(retryAfter:)` for both manual and scheduled refreshes, and retain the last successful snapshot with an explicit stale/error state. HTTP 429 and 503 with Retry-After support seconds and HTTP dates, with a 60-second minimum and a 300-second fallback. HTTP 401/403 asks for sign-in; unsupported data, redirects and other server failures are unavailable, never a fabricated quota reset.
