# SnoreTracker — Claude Project Guide

## Project Overview
iOS app (SwiftUI, iOS 17+) that passively monitors microphone in the background, detects snoring via FFT frequency analysis, auto-records snoring events, and displays nightly sleep reports.

## Project Structure
```
SnoreTracker/
├── project.yml                          # xcodegen config — run `xcodegen generate` to regenerate .xcodeproj
├── SnoreTracker/
│   ├── SnoreTrackerApp.swift            # App entry point; injects ThemeManager as @EnvironmentObject
│   ├── Info.plist                       # NSMicrophoneUsageDescription, UIBackgroundModes: audio
│   ├── Assets.xcassets/AppIcon.appiconset/  # AppIcon-1024.png (fruit-themed, pink-purple gradient)
│   ├── Models/
│   │   └── SleepModels.swift            # SnoringEvent, SleepSession (Codable, Identifiable)
│   ├── Services/
│   │   ├── AudioMonitorService.swift    # AVAudioEngine tap + FFT snoring detection + recording
│   │   └── SleepSessionManager.swift   # ObservableObject bridging audio service ↔ SwiftUI; toggleMonitoring()
│   ├── Theme/
│   │   ├── AppTheme.swift               # AppTheme struct with semantic color tokens; .dark + .fruitJelly themes
│   │   └── ThemeManager.swift           # ObservableObject; @AppStorage("selectedThemeID"); current: AppTheme
│   └── Views/
│       ├── ContentView.swift            # TabView: 监测 / 报告 / 设置; applies theme to tab bar
│       ├── HomeView.swift               # Live monitoring UI; stoppedView + monitoringView; LiveWaveform
│       ├── ReportsView.swift            # Session list with swipe-to-delete; SessionRowView(theme:)
│       ├── SessionDetailView.swift      # Detail: summary card, SnoringTimeline, recordings playback
│       └── SettingsView.swift           # Sensitivity sliders, theme picker, data management
```

## Key Architecture Decisions

### Theme System
- `AppTheme` struct has semantic color tokens: `bgColors`, `bgSnoringColors`, `accent`, `accentLight`, `snoringAccent`, `liveIndicator`, `tabBarBackground`, `cardOpacity`
- `ThemeManager: ObservableObject` with `@AppStorage("selectedThemeID")` — persists selected theme across launches
- All views access theme via `@EnvironmentObject var themeManager: ThemeManager`, using `themeManager.current`
- Two themes: `.dark` (deep navy/blue) and `.fruitJelly` (purple-berry/pink/mint/orange)

### Snoring Detection (AudioMonitorService.swift)
- **Not RMS-only**: Uses FFT (4096-point, Accelerate/vDSP) to analyze frequency content
- **Snoring band**: 80–500 Hz; **High-freq band**: 1000–6000 Hz
- **Score formula**: `snoreRatio * max(0, 1 - highRatio * 1.5)` — rewards low-freq energy, penalizes whistle/speech
- **State machine**: `onLoud()` → 1s `confirmTimer` → `beginSnoring()`; `onSilent()` → 5s `silenceTimer` → `endSnoring()`
- `init()` reads all 4 settings from `UserDefaults` on launch (`minimumRMS`, `snoreScoreThreshold`, `confirmDelay`, `silenceDelay`)
- Recording written directly in audio thread via `AVAudioFile.write(from:)`

### Background Audio
- `AVAudioSession` category: `.playAndRecord` with `.mixWithOthers`
- `UIBackgroundModes: audio` in Info.plist

### State Management (SleepSessionManager.swift)
- `@Published liveSnoreDuration`: driven by a 0.1s `Timer`, shows real-time duration while snoring
- `toggleMonitoring()`: starts or stops `audioService` based on `isMonitoring` state
- `deleteSession()` does NOT call `loadOrCreateTodaySession()` — session is lazily re-created next time snoring starts
- `clearAllData()` resets all published state and stops timers

### Data Persistence (SleepStore.swift)
- JSON-encoded `[SleepSession]` stored at `Documents/sleep_sessions.json` — survives recompiles
- Recording audio files: `Documents/snore_<timestamp>.m4a`

### HomeView Settings Display
- `@AppStorage("silenceDelay") private var silenceDelay: Double = 5.0` — reads persisted value on first render, not `audioService.silenceDelay`

### SnoringTimeline (SessionDetailView.swift)
- **X position** = `event.startTime` proportional to full session duration → gaps between blocks = real non-snoring time
- **Block width** = `event.duration / sessionDuration * trackWidth` (min 4pt) — truly proportional, small events = small ticks
- **No forward-push algorithm** — blocks stay at natural positions; overlapping is acceptable since events shouldn't overlap in reality
- Blocks are plain rectangles clipped inside the rounded track via `ctx.drawLayer { lc.clip(to: trackPath) }` — sharp internal edges, rounded outer corners
- **Labels**: `HH:mm` format at block center x; left/right axis labels at track edges; overlapping labels skipped via `prevRight` cursor
- Old `SnoringBarChart` (vertical bars) is commented out below and preserved for reference

## Build Instructions
```bash
# Requires xcodegen
brew install xcodegen

# Regenerate Xcode project
cd SnoreTracker
xcodegen generate

# Open in Xcode
open SnoreTracker.xcodeproj
```
Then select your device and press Cmd+R.

**Important**: Do NOT manually create/edit `.xcscheme` files inside `xcshareddata/` — always let xcodegen manage the project. If a white screen occurs after scheme edits, run:
```bash
rm -rf SnoreTracker.xcodeproj/xcshareddata
xcodegen generate
```

## Common Pitfalls
- `Color(hex:)` extension is defined in `HomeView.swift` — available globally across the module
- `SleepStore` is created once in `SnoreTrackerApp.init()` and passed to `SleepSessionManager`; the property default `= SleepStore()` is overridden in init (intentional pattern)
- FFT uses `withUnsafeMutableBufferPointer` nested closures to stabilize `DSPSplitComplex` pointer — do not refactor to single-level closures
- `vDSP_sve` is called on `Array` slices (not pointer arithmetic) to avoid Swift strict-concurrency pointer issues
- Theme colors must use `themeManager.current.xxx` (not hardcoded); all views receive `themeManager` via `.environmentObject(themeManager)` from `SnoreTrackerApp`
