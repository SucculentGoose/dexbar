# macOS Code Reference - Complete Source Files

This document contains the complete source code for the key macOS implementation files.

## File Structure

```
DexBar/
├── Sources/
│   ├── Views/
│   │   ├── MenuBarView.swift          (Popup UI - main dashboard)
│   │   ├── GlucoseChartView.swift     (Chart visualization)
│   │   └── SettingsView.swift         (Settings UI)
│   ├── Managers/
│   │   ├── GlucoseMonitor.swift       (Data management & state)
│   │   └── NotificationManager.swift  (Alerts)
│   ├── Models/
│   │   └── Color+Hex.swift            (Color utilities)
│   ├── Services/
│   │   └── KeychainService.swift      (Password storage)
│   └── DexBarApp.swift                (App entry point)
│
Sources/DexBarCore/
├── Models/
│   └── GlucoseReading.swift           (Data model)
├── Services/
│   └── DexcomService.swift            (API client)
└── Shared/
    └── CoreTypes.swift                (Shared enums)
```

## Key Classes and Their Relationships

```
DexBarApp (App entry point)
├── GlucoseMonitor (Observable state manager)
│   ├── DexcomService (API client)
│   ├── [GlucoseReading]* (Current + historical readings)
│   ├── NotificationManager (Alert dispatch)
│   └── Timer (Auto-refresh scheduler)
│
MenuBarView (Popup display)
├── GlucoseMonitor (injected via @Environment)
├── MenuBarLabel (menu bar text)
├── GlucoseChartView (chart component)
└── [action buttons]
```

## Data Flow

```
1. Authentication (once)
   Settings → DexcomService.authenticate()
   
2. Initial Sync
   GlucoseMonitor.start()
   → DexcomService.getLatestReadings(maxCount: 288)
   → [GlucoseReading] * 288
   → save to ~/Library/Application Support/DexBar/readings.json
   
3. Regular Refresh (every ~5 minutes)
   Timer fires → GlucoseMonitor.refresh()
   → DexcomService.getLatestReadings(maxCount: 2)
   → merge new into recentReadings[]
   → save
   → update UI (via @Observable)
   
4. UI Update
   GlucoseMonitor state changes
   → MenuBarView renders
   → GlucoseChartView filters chartReadings
   → Chart renders with current settings
```

## State Management Summary

GlucoseMonitor maintains:
- `currentReading`: Latest single reading
- `recentReadings`: All readings (newest first), deduped, max 25920
- `selectedTimeRange`: 3h/6h/12h/24h (for chart)
- `selectedStatsRange`: 2d/7d/14d/30d/90d (for TiR)
- `state`: idle/loading/connected/error
- Alert thresholds (4 levels: urgentLow, low, high, urgentHigh)
- Zone colors (5: urgentLow, low, inRange, high, urgentHigh)
- Display preferences: unit, menuBarStyle, showDelta, coloredMenuBar

All user preferences synced with:
- UserDefaults (most settings)
- Keychain (password only)
- Local JSON file (readings history)

## Key Algorithms

### Chart Data Filtering
```
chartReadings = recentReadings.filter { reading.date >= now - selectedTimeRange.interval }
```

### TiR Calculation
```
statsReadings = recentReadings.filter { reading.date >= now - selectedStatsRange.interval }
lowCount = statsReadings.count { reading.value < alertLowThreshold }
inRangeCount = statsReadings.count { alertLowThreshold <= reading.value <= alertHighThreshold }
highCount = statsReadings.count { reading.value > alertHighThreshold }
```

### GMI (Glucose Management Indicator)
```
Formula: GMI = 3.31 + (0.02392 × mean_glucose_mg_dL)
mean = statsReadings.map(\.value).average()
```

### Delta Calculation
```
delta = currentReading.value - previousReading.value  (mg/dL)
if unit == .mmolL: delta_mmol = delta / 18.0
```

### Stale Detection
```
isStale = now.timeIntervalSince(currentReading.date) > 20 minutes
```

## API Integration Details

### Dexcom API Endpoints

**Authentication:**
```
POST /General/AuthenticatePublisherAccount
{
  "accountName": "user@example.com",
  "password": "...",
  "applicationId": "d8665ade-9673-4e27-9ff6-92db4ce13d13"
}
→ "UUID" (quoted string)

POST /General/LoginPublisherAccountById
{
  "accountId": "UUID",
  "password": "...",
  "applicationId": "d8665ade-9673-4e27-9ff6-92db4ce13d13"
}
→ "SESSION-UUID" (quoted string)
```

**Get Readings:**
```
GET /Publisher/ReadPublisherLatestGlucoseValues
?sessionId=SESSION-UUID
&minutes=1440
&maxCount=288
→ [{ WT: "Date(1234567890000)", Value: 150, Trend: "Flat", TrendRate: 0.5 }, ...]
```

### Region URLs
- **US**: `https://share2.dexcom.com/ShareWebServices/Services`
- **OUS**: `https://shareous1.dexcom.com/ShareWebServices/Services`
- **JP**: `https://shareous1.dexcom.jp/ShareWebServices/Services`

## macOS-Specific Dependencies

```swift
import SwiftUI                    // UI framework
import Charts                     // Native Apple Charts framework
import AppKit                     // NSApplication, NSWorkspace, NSImage
import Sparkle                    // Auto-update framework
import UserNotifications          // System notifications
import ServiceManagement          // Launch-at-login
import Foundation                 // Standard library
import Observation                @Observable macro
import CryptoKit                  // (implied for security)
```

## Linux Implementation Considerations

For your Linux port, focus on replicating:

1. **Data Model** (100% reusable)
   - GlucoseReading, GlucoseTrend, DexcomService, CoreTypes
   - These are pure Swift with no platform dependencies

2. **State Management** (90% reusable)
   - GlucoseMonitor logic (mostly math and filtering)
   - Replace: NSWorkspace wake observer, UserDefaults, Keychain
   - Replace: Timer (use equivalent in your framework)

3. **UI Layer** (0% reusable, must rebuild)
   - MenuBarView → GTK/Qt popup window
   - GlucoseChartView → GTK/Qt chart library (e.g., matplotlib, Chart.js wrapper)
   - SettingsView → GTK/Qt settings dialog
   - Notifications → org.freedesktop.Notifications (DBus)

4. **Platform Layer** (must rebuild)
   - Tray icon integration (AppIndicator/StatusNotifier)
   - Persistent storage (XDG_DATA_HOME instead of ~/Library)
   - Keyring access (Secret Service DBus API)
   - Auto-start (XDG autostart desktop files)

## Key Numbers to Know

- **Refresh interval**: 5 minutes (default, configurable 1-15)
- **Max history**: 25,920 readings (288 readings/day × 90 days)
- **API lookback**: Always 1440 minutes (24 hours)
- **Stale threshold**: 20 minutes
- **Alert cooldown**: 15 minutes per alert type
- **Hover symbol size**: 18pt (normal), 55pt (hover)
- **Chart height**: 130pt
- **Min popup width**: 300pt
- **Chart padding**: 15 mg/dL (or 0.8 mmol/L)

