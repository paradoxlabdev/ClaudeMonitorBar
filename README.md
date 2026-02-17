# Claude Monitor Bar

A native macOS menu bar app that displays your Claude Code API usage limits in real time.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Real-time usage data** from Anthropic's API (5-hour, 7-day, and 7-day Sonnet limits)
- **Circular progress ring** showing your current 5-hour utilization
- **Reset times** for each limit window
- **Plan recommendation** — suggests whether to upgrade, downgrade, or keep your current plan based on 7-day usage projections
- **Subscription renewal date** displayed from your profile
- **Claude logo** in the menu bar

## How It Works

The app reads your Claude Code OAuth token from the macOS Keychain and makes a minimal API call (`max_tokens=1`) to Anthropic's Messages API. The response headers contain real-time rate limit utilization data:

- `anthropic-ratelimit-unified-5h-utilization`
- `anthropic-ratelimit-unified-7d-utilization`
- `anthropic-ratelimit-unified-7d_sonnet-utilization`

No usage data is stored on disk — everything is fetched live.

## Requirements

- macOS 14.0 (Sonoma) or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (the app uses its OAuth token)

## Build & Run

```bash
# Clone the repo
git clone https://github.com/yourusername/ClaudeMonitorBar.git
cd ClaudeMonitorBar

# Build and create the .app bundle
./build-app.sh

# Move to Applications (optional)
mv ClaudeMonitorBar.app /Applications/
```

On first launch, macOS may warn about an unidentified developer. Right-click the app and select **Open** to bypass this.

## Development

```bash
# Build
swift build

# Run from terminal
.build/arm64-apple-macosx/debug/ClaudeMonitorBar

# Run tests
swift test
```

## Project Structure

```
Sources/ClaudeMonitorBar/
  ClaudeMonitorBarApp.swift          # App entry point (MenuBarExtra)
  Models/
    UsageLimit.swift                 # Rate limit data model
    PlanRecommendation.swift         # Upgrade/downgrade recommendation logic
    PlanTier.swift                   # Plan tier definitions
  Services/
    RateLimitFetcher.swift           # API calls for usage data & profile
    SessionManager.swift             # Observable state manager
  Views/
    MenuBarView.swift                # Main popup UI
    CircularProgressView.swift       # Progress ring
    LimitRowView.swift               # Individual limit row
```

## Security

- OAuth token is read from the macOS Keychain (never stored or exported by this app)
- Only connects to `api.anthropic.com` — no third-party services
- Each refresh consumes 1 token (minimal API call to retrieve rate limit headers)
- Ad-hoc code signed for local use

## License

MIT
