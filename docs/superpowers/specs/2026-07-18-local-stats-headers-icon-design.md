# Local usage stats, new API headers, percent menu bar icon — design

Date: 2026-07-18
Status: approved by user ("pasuje rób wszystko")

## Context

The Anthropic rate-limit API dropped the `7d_sonnet` weekly limit (removed from the app
earlier today) and now exposes new headers the app ignores. Separately, Claude Code writes
full session logs to `~/.claude/projects/**/*.jsonl`, which contain per-message token usage
including the model name — this restores per-model visibility that the API no longer provides.

Three features, implemented in order B → C → A.

## Feature B — surface new API rate-limit headers

`RateLimitFetcher.RateLimitData` gains:

- `representativeClaim: String` — from `anthropic-ratelimit-unified-representative-claim`
  (`five_hour` | `seven_day`); which limit currently binds.
- `fiveHourStatus: String`, `sevenDayStatus: String` — from
  `anthropic-ratelimit-unified-5h-status` / `-7d-status` (`allowed` | `rejected`).
- `overageStatus: String` — from `anthropic-ratelimit-unified-overage-status`.
- `overageDisabledReason: String` — from `anthropic-ratelimit-unified-overage-disabled-reason`.

`SessionManager` stores these; `UsageLimit` gains `isBinding: Bool` and `isRejected: Bool`.

UI (`LimitRowView` / `MenuBarView`):

- Bolt icon (`bolt.fill`) next to the binding limit's name, tinted to the row's status color.
- Row name tinted red when that limit's status is `rejected`.
- Footer line "Overage: off (org)" (or similar) only when overage is disabled/rejected;
  nothing shown in the default healthy state.

## Feature C — percent menu bar icon option

`AppPreferences` gains:

- `menuBarStyle`: `"ring"` (default, current behavior) | `"percent"`.
- `menuBarMetric`: `"5h"` (default) | `"7d"` — only used by percent style.

`ClaudeMonitorBarApp` label: when style is `percent`, render an NSImage of the percentage
text (e.g. `42%`, monospaced bold, dynamic width) colored by the selected metric's
threshold color (green < 70%, yellow < 90%, red ≥ 90%). Metric picks the value: 5h =
`overallPercentage`, 7d = `usageLimits[1]`. Ring style unchanged and remains default.

`SettingsSection`: two new segmented rows following the existing button-segment pattern —
"Menu bar: Ring | %" and, visible only when percent is selected, "Metric: 5h | 7d".

## Feature A — local Claude Code log token stats

New service `LocalUsageScanner` (background actor / detached task):

- Scans `~/.claude/projects/**/*.jsonl` with mtime within the last 8 days
  (measured on this machine: 253 of 3126 files, 145 MB of 920 MB).
- Per-file cache keyed by path → (mtime, size, per-day/per-model partial aggregates), so
  only changed files are re-parsed on refresh. First scan ~1–2 s, later scans near-instant.
- Line handling: substring prefilter `"type":"assistant"` before JSON decoding; skip
  `model == "<synthetic>"`; dedupe by `message.id` + `requestId`; read
  `timestamp`, `message.model`, `message.usage.{input_tokens, output_tokens,
  cache_creation_input_tokens, cache_read_input_tokens}`.
- Model display names: `claude-fable-5` → "Fable 5", `claude-opus-4-8` → "Opus 4.8",
  `claude-sonnet-*` → "Sonnet", `claude-haiku-*` → "Haiku"; bare aliases (`fable`, `opus`,
  `sonnet`, `haiku`) map to the same buckets; unknown ids shown as-is.
- Aggregates: Today (since local midnight) and last 7 days; per model: message count,
  output tokens, input tokens, cache tokens (creation + read).

UI: collapsible "Local usage" section in the popover (below the chart) with a
Today / 7 days toggle. One row per model — name, **output tokens** as the headline number
(cache read dominates total volume ~90% and would be misleading), share bar/percent by
output tokens. Totals line at the bottom: In / Out / Cache. Section hidden entirely when
`~/.claude/projects` is missing or unreadable. Scan triggered on refresh cycle, throttled,
off the main thread.

## Error handling

- Malformed JSONL lines: skipped silently.
- Missing headers: empty-string defaults, UI treats as "feature absent" (no bolt, no footer).
- Scanner never blocks UI; failures degrade to hiding the section.

## Testing

- Unit tests for the scanner on fixture JSONL files: dedupe, synthetic skip, model
  normalization, date filtering, aggregation math, cache invalidation on mtime change.
- Header parsing covered via `RateLimitData` construction tests where practical; UI and
  icon rendering verified manually (build + relaunch).
