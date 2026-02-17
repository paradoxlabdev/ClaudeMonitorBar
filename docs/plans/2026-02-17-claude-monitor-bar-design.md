# Claude Monitor Bar — Design

## Overview

Native macOS menu bar app (SwiftUI) that monitors active Claude Code CLI sessions and displays usage/cost information.

## Features

### 1. Session Status
- Detect active Claude Code processes
- Show current task/status from session data
- Token usage for current session
- Session duration

### 2. Cost Tracking
- Estimated cost of current session (based on token count)
- Daily and monthly cumulative cost
- Breakdown by model (Opus, Sonnet, Haiku)

## Architecture

### Technology: SwiftUI (native macOS)
- Lightweight (~5MB), native look & feel, low RAM usage
- Runs as login item (auto-start with system)
- Menu bar only (no dock icon)

### Data Sources
- **Process monitoring**: `ProcessInfo` / `NSWorkspace` to detect running `claude` processes
- **Session files**: Read from `~/.claude/projects/` and `~/.claude/` for session data, token counts
- **File watching**: `DispatchSource.makeFileSystemObjectSource` or `FSEvents` to react to changes in `~/.claude/`

### UI Components

#### Menu Bar Icon
- Small Claude-style icon
- Color dot indicator:
  - Green = active session
  - Gray = no active session

#### Dropdown Menu
- List of active sessions with:
  - Project name / working directory
  - Current status (active / idle)
  - Token count (input + output)
  - Estimated cost
- Separator
- Daily total cost
- Monthly total cost
- Separator
- "Open in Terminal" button
- "Preferences" (cost per token rates, auto-start toggle)
- "Quit"

## Token Pricing (defaults, configurable)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Opus 4 | $15.00 | $75.00 |
| Sonnet 4 | $3.00 | $15.00 |
| Haiku 4 | $0.80 | $4.00 |

## File Structure

```
ClaudeMonitorBar/
├── ClaudeMonitorBar.xcodeproj
├── ClaudeMonitorBar/
│   ├── App.swift                  # @main, MenuBarExtra
│   ├── MenuBarView.swift          # Dropdown UI
│   ├── SessionMonitor.swift       # Process detection + file watching
│   ├── CostCalculator.swift       # Token → cost conversion
│   ├── SessionData.swift          # Data models
│   ├── Preferences.swift          # Settings storage (UserDefaults)
│   └── Assets.xcassets/           # Menu bar icons
├── docs/
│   └── plans/
└── README.md
```

## Technical Notes

- Minimum macOS 14.0 (Sonoma) for latest MenuBarExtra API
- No network requests — all data is local
- Polling interval: 5 seconds for process check, file watcher for session data
- Persist daily/monthly stats in UserDefaults or local JSON file
