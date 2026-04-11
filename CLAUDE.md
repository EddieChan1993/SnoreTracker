# SnoreTracker — Claude Project Guide

## Project Overview
iOS app (SwiftUI, iOS 17+) that passively monitors microphone in the background, detects snoring via FFT frequency analysis, auto-records snoring events, and displays nightly sleep reports.

## Project Structure
```
SnoreTracker/
├── project.yml                          # xcodegen config — run `xcodegen generate` to regenerate .xcodeproj
├── SnoreTracker/
│   ├── SnoreTrackerApp.swift            # App entry point, creates SleepStore + SleepSessionManager
│   ├── Info.plist                       # NSMicrophoneUsageDescription, UIBackgroundModes: audio
│   ├── Assets.xcassets/AppIcon.appiconset/  # AppIcon-1024.png (universal iOS icon)
│   ├── Models/
│   │   └── SleepModels.swift            # SnoringEvent, SleepSession (Codable, Identifiable)
│   ├── Services/
│   │   ├── AudioMonitorService.swift    # AVAudioEngine tap + FFT snoring detection + recording
│   │   └── SleepSessionManager.swift   # ObservableObject bridging audio service ↔ SwiftUI
│   └── Views/
│       ├── ContentView.swift            # TabView: 监测 / 报告 / 设置
│       ├── HomeView.swift               # Live monitoring UI + LiveWaveform + Color(hex:) extension
│       ├── ReportsView.swift            # Session list with swipe-to-delete
│       ├── SessionDetailView.swift      # Detail: summary card, bar chart timeline, recordings playback
│       └── SettingsView.swift           # Sensitivity sliders, data management
```

## Key Architecture Decisions

### Snoring Detection (AudioMonitorService.swift)
- **Not RMS-only**: Uses FFT (4096-point, Accelerate/vDSP) to analyze frequency content
- **Snoring band**: 80–500 Hz; **High-freq band**: 1000–6000 Hz
- **Score formula**: `snoreRatio * max(0, 1 - highRatio * 1.5)` — rewards low-freq energy, penalizes whistle/speech
- **State machine**: `onLoud()` → 1s `confirmTimer` → `beginSnoring()`; `onSilent()` → 5s `silenceTimer` → `endSnoring()`
- Recording written directly in audio thread via `AVAudioFile.write(from:)`

### Background Audio
- `AVAudioSession` category: `.playAndRecord` with `.mixWithOthers`
- `UIBackgroundModes: audio` in Info.plist

### State Management (SleepSessionManager.swift)
- `@Published liveSnoreDuration`: driven by a 0.1s `Timer`, shows real-time duration while snoring
- `deleteSession()` does NOT call `loadOrCreateTodaySession()` — session is lazily re-created next time snoring starts
- `clearAllData()` resets all published state and stops timers

### Data Persistence (SleepStore.swift)
- JSON-encoded `[SleepSession]` stored at `Documents/sleep_sessions.json`
- Recording audio files: `Documents/snore_<timestamp>.m4a`

### Bar Chart (SessionDetailView.swift — SnoringBarChart)
- X-axis spans (first event start − 20% pad) → (last event end + 20% pad), NOT limited to session.endTime
- **Overlap prevention**: forward-push pass then backward-pull pass (`adjustedXPositions()`)

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
