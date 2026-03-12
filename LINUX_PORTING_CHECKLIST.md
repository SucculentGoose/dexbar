# Linux Porting Checklist & Implementation Plan

## Phase 1: Data Layer (100% Reusable)

These files have NO platform-specific code and can be used directly in Linux version:

- [ ] `/Sources/DexBarCore/Models/GlucoseReading.swift`
  - Pure data model, JSON serializable
  - Contains: GlucoseReading, GlucoseTrend, DexcomRawReading
  - No changes needed

- [ ] `/Sources/DexBarCore/Services/DexcomService.swift`
  - HTTP client for Dexcom API
  - Uses standard URLSession (works on Linux)
  - No AppKit/SwiftUI dependencies
  - No changes needed

- [ ] `/Sources/DexBarCore/Shared/CoreTypes.swift`
  - Enum definitions: TimeRange, StatsTimeRange, MonitorState, TiRStats
  - Pure Swift enums
  - No changes needed

**Action**: Copy these files verbatim to DexBarLinux/Sources/DexBarCore/

## Phase 2: Business Logic (80-90% Reusable)

These require MINIMAL changes (mostly replacing platform APIs):

- [ ] `/DexBar/Sources/Managers/GlucoseMonitor.swift`
  - **Reusable**: All calculations (TiR, GMI, filtering, deltas)
  - **Replace**: 
    - `NSWorkspace` notification observer → org.freedesktop.ScreenSaver / systemd-sleep
    - `UserDefaults` → config file or dconf (keep interface identical)
    - `Timer` → equivalent (DispatchSourceTimer / async loop)
    - `@Observable` → Observer pattern or reactive framework
  - **Keep**: All math, state management, refresh logic

**Action**: Port GlucoseMonitor to Linux, replacing platform-specific APIs

- [ ] `/DexBar/Sources/Managers/NotificationManager.swift`
  - **Reusable**: Alert types, cooldown logic
  - **Replace**: 
    - `UNUserNotificationCenter` → org.freedesktop.Notifications (DBus)
  - **Keep**: Alert evaluation, cooldown timing

**Action**: Create LinuxNotificationManager with same interface

## Phase 3: UI Layer (Must Rebuild from Scratch)

These have SwiftUI/AppKit dependencies and must be completely rewritten:

### Main Popup Window
- [ ] `/DexBar/Sources/Views/MenuBarView.swift` 
  **→ Replicate in GTK/Qt**
  - Section 1: Current reading (value, trend, delta, status, times)
  - Section 2: Chart (from GlucoseChartView)
  - Section 3: Time in Range stats
  - Section 4: Action buttons

### Chart Visualization
- [ ] `/DexBar/Sources/Views/GlucoseChartView.swift`
  **→ Implement chart with GTK/Qt + plotting library**
  - Use: matplotlib wrapper, chart.js, or native plotting library
  - Must show:
    - In-range band background
    - Threshold lines (dashed red/orange)
    - Blue line with catmull-rom interpolation
    - Colored data points
    - Interactive hover tooltip
    - Range selector buttons

### Settings Window
- [ ] `/DexBar/Sources/Views/SettingsView.swift`
  **→ Replicate as GTK/Qt dialog**
  - Account tab (username, password, region)
  - Display tab (unit, colors, menu bar style, refresh interval)
  - Alerts tab (thresholds, enable/disable, test buttons)
  - About tab

### Tray/Status Icon
- [ ] Menu bar label text
  **→ Implement as system tray icon**
  - Use: AppIndicator3 or StatusNotifierItem (DBus)
  - Show: glucose value + trend + optional delta
  - Optional: color dot based on zone

## Phase 4: Platform Integration

- [ ] Storage layer
  - Replace: ~/Library/Application Support → $XDG_DATA_HOME/dexbar/
  - Replace: UserDefaults → JSON config file or dconf
  - Replace: Keychain → Secret Service (DBus)

- [ ] System integration
  - Tray icon: AppIndicator3 / StatusNotifierItem
  - Notifications: org.freedesktop.Notifications (DBus)
  - Auto-start: XDG autostart (~/.config/autostart/dexbar.desktop)
  - Window manager: standard X11/Wayland

- [ ] Build system
  - Keep: Swift package manager (if using Swift)
  - Or: Migrate to Python/Go (if switching languages)

## Current Linux Implementation Status

From `/DexBarLinux/Sources/`:

**Already exists:**
- [ ] `Managers/GlucoseMonitorLinux.swift` - Linux port of monitor
- [ ] `Managers/LinuxNotificationManager.swift` - DBus notifications
- [ ] `Views/PopupWindow.swift` - Main popup UI
- [ ] `Views/TrayIcon.swift` - Tray integration
- [ ] `Views/SettingsWindow.swift` - Settings UI
- [ ] `Services/SecretServiceStorage.swift` - Secret Service integration
- [ ] `Services/LinuxUpdater.swift` - Update checking

**TODO**: Review and enhance these with proper implementations

## Key Implementation Principles

### 1. Model Immutability
Keep GlucoseReading and related models immutable. Always create new arrays when merging readings.

### 2. Timezone Handling
All timestamps are Date objects (UTC internally). Display conversion happens at render time only.

### 3. Unit Consistency
**Internally**: Always store glucose as mg/dL
**Display**: Convert at render time based on user preference
**API**: Dexcom provides mg/dL, convert on input if needed

### 4. Data Deduplication Strategy
```
When fetching new readings:
  1. Create set of existing dates
  2. Filter incoming by date
  3. Merge: new + existing
  4. Sort: by date, newest first
  5. Truncate: max 25920
```

### 5. Refresh Scheduling
```
timer_fire_time = max(
  last_reading_date + refresh_interval,
  now + 30_seconds  // never hammer API
)
```

### 6. UI Update Pattern
Use observer pattern or reactive library:
```
Monitor state changes
  → Notify UI listeners
  → UI re-renders
  → New data displayed
```

### 7. Error Recovery
```
Network error → schedule retry in 30s
Session expired → re-authenticate with stored credentials
Rate limited → log, retry in 30s
Parse error → log, continue with old data
```

## File-by-File Reusability Checklist

```
✅ = 100% reusable (no changes)
⚠️  = Needs adaptation (replace platform APIs)
❌ = Must rewrite (SwiftUI/AppKit)

Sources/DexBarCore/Models/GlucoseReading.swift      ✅
Sources/DexBarCore/Services/DexcomService.swift     ✅
Sources/DexBarCore/Shared/CoreTypes.swift           ✅

DexBar/Sources/Managers/GlucoseMonitor.swift        ⚠️  (Platform APIs)
DexBar/Sources/Managers/NotificationManager.swift   ⚠️  (UNUserNotificationCenter)

DexBar/Sources/Views/MenuBarView.swift              ❌ (SwiftUI)
DexBar/Sources/Views/GlucoseChartView.swift         ❌ (Swift Charts)
DexBar/Sources/Views/SettingsView.swift             ❌ (SwiftUI)
DexBar/Sources/Views/DexBarApp.swift                ❌ (SwiftUI App)

DexBar/Sources/Models/Color+Hex.swift               ✅ (Use as reference)
DexBar/Sources/Services/KeychainService.swift       ❌ (AppKit Keychain)
```

## Testing Checklist

- [ ] Can authenticate with Dexcom credentials
- [ ] Initial load fetches 288 readings
- [ ] Regular refresh fetches 2 readings every 5 min
- [ ] Readings deduplicated by date
- [ ] History persists across app restart
- [ ] Chart displays correct readings for selected time range
- [ ] TiR percentages calculate correctly
- [ ] GMI displays and warns correctly
- [ ] Colors update based on thresholds
- [ ] Alerts trigger at correct times
- [ ] Alert cooldown prevents spam
- [ ] Settings persist across restart
- [ ] Unit conversion works in both directions
- [ ] Delta calculation is correct
- [ ] Stale detection triggers at 20+ min
- [ ] System tray shows glucose value
- [ ] Hover tooltip on chart shows correct info

## Integration Points to Verify

1. **Dexcom Share API**
   - Test with real credentials
   - Test with invalid credentials
   - Test rate limiting (429)
   - Verify response parsing

2. **Persistent Storage**
   - Verify readings saved as JSON
   - Verify settings persist
   - Verify keyring stores password
   - Verify file permissions

3. **System Integration**
   - Tray icon visible and clickable
   - Popup window position correct
   - Notifications appear
   - Auto-start works

4. **User Interface**
   - Chart renders with data
   - Hover tooltips work
   - Range selectors update chart/stats
   - Buttons are functional
   - Colors update dynamically

