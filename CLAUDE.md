# SnoreTracker — Claude Project Guide

## Project Overview
iOS app (SwiftUI, iOS 15+) that manually-triggered background microphone monitoring, detects snoring via FFT frequency analysis, auto-records each snoring event, and displays per-session sleep reports.

## Project Structure
```
SnoreTracker/
├── project.yml                          # xcodegen config — deploymentTarget: 15.0
├── SnoreTracker/
│   ├── SnoreTrackerApp.swift            # App entry point; injects ThemeManager as @EnvironmentObject
│   ├── Info.plist                       # NSMicrophoneUsageDescription, UIBackgroundModes: audio
│   ├── Assets.xcassets/AppIcon.appiconset/  # AppIcon-1024.png (fruit-themed, pink-purple gradient)
│   ├── Models/
│   │   └── SleepModels.swift            # SnoringEvent, SleepSession (Codable, Identifiable)
│   ├── Services/
│   │   ├── AudioMonitorService.swift    # AVAudioEngine tap + FFT snoring detection + recording
│   │   ├── SleepSessionManager.swift    # ObservableObject bridging audio service ↔ SwiftUI
│   │   └── SleepStore.swift             # JSON persistence to Documents/sleep_sessions.json
│   ├── Theme/
│   │   ├── AppTheme.swift               # AppTheme struct with semantic color tokens
│   │   └── ThemeManager.swift           # ObservableObject; @AppStorage("selectedThemeID")
│   └── Views/
│       ├── ContentView.swift            # TabView: 监测 / 报告 / 设置; applies theme to tab bar
│       ├── HomeView.swift               # Manual start/stop; circle level indicator
│       ├── ReportsView.swift            # Per-session list with swipe-to-delete
│       ├── SessionDetailView.swift      # Summary card, SnoringTimeline, recordings playback
│       └── SettingsView.swift           # Sensitivity sliders, theme picker, data management
```

## Key Architecture Decisions

### Session Lifecycle
- **Manual start only** — no auto-start on launch; user taps "开始监测"
- **Each start = new SleepSession** — `toggleMonitoring()` calls `startNewSession()` every time
- **Stop writes endTime** — `closeCurrentSession()` stamps `endTime = Date()` and persists
- **Orphan recovery on launch** — `recoverOrphanedSessions()` in `SleepSessionManager.init()`:
  - Sessions with events + `endTime == nil` → set `endTime = Date()` and save (app was force-killed)
  - Sessions with no events + `endTime == nil` → delete (empty, no useful data)

### Theme System
- `AppTheme` struct: `bgColors`, `bgSnoringColors`, `accent`, `accentLight`, `snoringAccent`, `liveIndicator`, `tabBarBackground`, `cardOpacity`
- `ThemeManager: ObservableObject` with `@AppStorage("selectedThemeID")` — persists across launches
- All views: `@EnvironmentObject var themeManager: ThemeManager`, use `themeManager.current.xxx`
- Two themes: `.dark` (deep navy/blue) and `.fruitJelly` (purple-berry/pink/mint/orange)

### Snoring Detection (AudioMonitorService.swift)
- **Algorithm**: RMS gate → 2048-point FFT (Accelerate/vDSP) → band energy ratio
- **Snoring band**: 80–500 Hz; **High-freq band**: 1000–6000 Hz
- **Score**: `snoreRatio * max(0, 1 - highRatio * 1.5)` — rewards low-freq, penalizes speech/whistle
- **State machine**: `onLoud()` → `confirmTimer` → `beginSnoring()`; `onSilent()` → `silenceTimer` → `endSnoring()`
- Settings restored from `UserDefaults` in `init()`: `minimumRMS`, `snoreScoreThreshold`, `confirmDelay`, `silenceDelay`

### Performance Optimizations (AudioMonitorService.swift)
- **SnoringDetector**: all FFT buffers pre-allocated in `init()` (zero per-frame malloc); Hann window pre-computed once; bin indices pre-computed
- **Sample rate**: requests `preferredSampleRate(16000)` — 64% less DSP data vs 44100 Hz
- **Buffer size**: 8192 frames + `preferredIOBufferDuration(0.2s)` → ~5 CPU wake-ups/sec (was ~10)
- **FFT size**: 2048 (was 4096) — half the computation, still >7 Hz resolution for snoring bands
- **RMS computed once** per frame, passed into `score()` — no duplicate `vDSP_rmsqv` call
- **stableFrames gate**: if clearly silent (rms < 50% threshold) and stable 8+ frames → skip `score()` entirely; UI updates every 5 frames (~1 Hz) during quiet periods
- **State dispatch**: main thread dispatched only on loud/silent transition or UI throttle tick (~3.5 Hz)
- **Session mode**: `.measurement` (optimized for capture apps vs `.default`)
- **liveTimer**: 0.5s interval (was 0.1s) — sufficient for text label updates

### Scoring (SleepModels.swift)
- **Dual metric**: takes the **worse** of snoring-time-percentage and events-per-hour
- Events/hour thresholds (ref: medical AHI): 优秀 <5, 良好 <15, 一般 <30, 较差 ≥30
- Percentage thresholds: 优秀 <5%, 良好 <15%, 一般 <30%, 较差 ≥30%

### SnoringTimeline (SessionDetailView.swift)
- Track background = full session duration; empty = non-snoring time
- Block X = proportional to `event.startTime` within session
- Block width = `event.duration / sessionDuration * trackWidth` (min 4pt)
- Blocks: plain rectangles, no corner radius; clipped to rounded track via `ctx.drawLayer { lc.clip(to:) }`
- Labels: `HH:mm` at block center x; edges at track start/end; overlapping labels skipped with `prevRight` cursor
- Old `SnoringBarChart` commented out below for reference

### Background Audio
- `AVAudioSession` category: `.playAndRecord`, mode: `.measurement`, options: `.mixWithOthers`
- `UIBackgroundModes: audio` in Info.plist

### Data Persistence
- `SleepStore`: JSON-encoded `[SleepSession]` at `Documents/sleep_sessions.json` — survives recompiles
- Recordings: `Documents/snore_<timestamp>.m4a`
- `addSession()` inserts at index 0 → newest first in list

## iOS Compatibility (iOS 15+)
All iOS 17/16-only APIs have been replaced:
- `AVAudioApplication` → `AVAudioSession` (iOS 15 compatible)
- `.onChange(of:) { _, _ in }` → single-param `{ _ in }` (iOS 17 two-param removed)
- `.scrollContentBackground(.hidden)` → `UITableView.appearance().backgroundColor = .clear`
- `.symbolEffect(.pulse)` → `opacity + scaleEffect` animation
- `.contentTransition(.numericText())` → removed

## Build Instructions
```bash
# Requires xcodegen
brew install xcodegen

# Regenerate Xcode project
cd SnoreTracker
xcodegen generate

open SnoreTracker.xcodeproj
```
Select your device → Cmd+R.

**If white screen after scheme edits:**
```bash
rm -rf SnoreTracker.xcodeproj/xcshareddata && xcodegen generate
```

**Bundle ID**: `com.eddiechan.snoretracker.dev` (Personal Team, 7-day provisioning)

## Common Pitfalls
- `Color(hex:)` is defined in `HomeView.swift` — available globally across the module
- FFT uses nested `withUnsafeMutableBufferPointer` closures to stabilize `DSPSplitComplex` pointer — do not flatten to single-level
- `vDSP_sve` uses direct pointer offset (`buf.baseAddress! + lo`) — no Array copy per band
- Theme colors: always `themeManager.current.xxx`, never hardcoded
- `SleepStore` created once in `SnoreTrackerApp.init()`, passed to `SleepSessionManager`
- `UITableView.appearance().backgroundColor = .clear` set in `ReportsView.onAppear` for iOS 15 compat
- List swipe state resets on tab switch via `listID = UUID()` in `ReportsView.onAppear`
