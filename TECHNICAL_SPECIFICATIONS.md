# Technical Specifications for Linux Implementation

## 1. Data Model Classes (Shared - 100% Reusable)

### GlucoseReading
```swift
struct GlucoseReading: Identifiable, Codable {
  id: UUID                    // Generated on decode
  value: Int                  // Always mg/dL
  trend: GlucoseTrend        // Enum
  date: Date                  // ISO8601 timestamp
  trendRate: Double?          // mg/dL/min (optional)
}
```

**Important**: All glucose values are stored internally as mg/dL. Display conversion happens at render time.

### GlucoseTrend Enum
```
0 = none
1 = doubleUp (⇈)
2 = singleUp (↑)
3 = fortyFiveUp (↗)
4 = flat (→)
5 = fortyFiveDown (↘)
6 = singleDown (↓)
7 = doubleDown (⇊)
8 = notComputable (?)
9 = rateOutOfRange (?)
```

### TiRStats
```swift
struct TiRStats {
  lowCount: Int              // Readings < lowThreshold
  inRangeCount: Int          // In range
  highCount: Int             // > highThreshold
  total: Int                 // Sum of above
  
  computed:
  lowPct = (lowCount / total) * 100
  inRangePct = (inRangeCount / total) * 100
  highPct = (highCount / total) * 100
}
```

## 2. API Client (DexcomService)

### Authentication Flow
1. POST `/General/AuthenticatePublisherAccount`
   - Input: username, password, applicationId
   - Output: accountID (UUID string)
   
2. POST `/General/LoginPublisherAccountById`
   - Input: accountID, password, applicationId
   - Output: sessionID (UUID string)

### Get Readings
```
GET /Publisher/ReadPublisherLatestGlucoseValues
Parameters:
  sessionId = {sessionID from auth}
  minutes = 1440 (always 24h lookback)
  maxCount = 288 (initial) or 2 (regular refresh)

Response: Array of readings
[{
  "WT": "Date(1234567890000)",  // Milliseconds since epoch in ASP.NET format
  "Value": 150,                  // mg/dL
  "Trend": "Flat",               // String name of trend
  "TrendRate": 0.5               // Optional, mg/dL/min
}]
```

### Error Handling
- 500 status with invalid credentials
- Empty/null response = noReadings error
- Keep sessionID valid until invalidCredentials error
- Retry logic for transient failures (429, network)

## 3. Data Storage & Persistence

### Local Readings File
- **Path**: `$XDG_DATA_HOME/dexbar/readings.json` (Linux)
  - Falls back to `~/.local/share/dexbar/readings.json`
- **Format**: JSON array of GlucoseReading objects
- **Max size**: 25,920 readings (90 days × 288/day)
- **When saved**: After every successful refresh
- **On startup**: Load from disk and merge with API data

### Configuration Storage
- **Backend**: User's chosen method (dconf, json files, etc.)
- **Keys needed**:

```
display:
  glucoseUnit: "mgdL" | "mmolL"
  menuBarStyle: "Value & Arrow" | "Compact" | "Value Only" | "Arrow Only"
  showDelta: bool
  refreshIntervalMinutes: 1-15 (default 5)
  
thresholds (all in mg/dL):
  alertUrgentHighMgdL: 40-400 (default 250)
  alertHighMgdL: 40-400 (default 180)
  alertLowMgdL: 40-400 (default 70)
  alertUrgentLowMgdL: 40-400 (default 55)
  
  alert_enabled flags for each of above
  alertRisingFastEnabled: bool
  alertDroppingFastEnabled: bool
  alertStaleDataEnabled: bool
  alertCriticalEnabled: bool
  
colors (hex #RRGGBB):
  colorUrgentLow: #CC1A1A (or store as RGB)
  colorLow: #FF9500
  colorInRange: #34C759
  colorHigh: #FFCC00
  colorUrgentHigh: #CC1A1A
  
account:
  dexcomUsername: string
  dexcomRegion: "US" | "Outside US" | "Japan"
  [password goes to keyring]
```

## 4. UI Components Specification

### Popup Window
- **Minimum width**: 300pt (312px)
- **Height**: Dynamic (400-600px typical)
- **Background**: Transparent or system window
- **Border**: System window chrome
- **Position**: Below tray icon (or under cursor)
- **Always on top**: Yes, but not sticky across workspaces

### Current Reading Section
- **Layout**: HStack
- **Left side**:
  - Glucose value: 36pt, semibold, rounded design, COLOR-CODED
  - Trend + unit text: 14pt (subheading size)
  - Optional delta: inserted between trend and unit
  
- **Right side** (smaller text):
  - Status badge: "Live" (green dot) / "Updating" (blue) / "Error" (red) / "Disconnected" (gray)
  - "Last updated: 2 minutes ago" (relative time)
  - "Next refresh: in 3 minutes" (relative time)

### Stale Data Warning
- **Trigger**: Reading age > 20 minutes
- **Display**: Orange banner with warning triangle icon
- **Text**: "No new readings for 20+ min"

### Glucose Chart
- **Height**: 130pt minimum
- **Width**: Match popup width minus padding (8pt sides)
- **Elements**:
  1. In-range background band (light green, 8% opacity)
  2. Low threshold line (orange, dashed [4,3], 50% opacity)
  3. High threshold line (red, dashed [4,3], 35% opacity)
  4. Glucose line (blue, 2pt, smooth catmull-rom)
  5. Data points as circles
     - Size: 18pt radius when normal, 55pt when hovered
     - Colors: determined by glucose value vs thresholds
  6. Hover tooltip showing value + trend + time + delta
  
- **Range selector buttons**: 3h / 6h / 12h / 24h (segmented picker)
- **X-axis stride** (hours per grid line):
  - 3h: every 1 hour
  - 6h: every 2 hours
  - 12h: every 3 hours
  - 24h: every 6 hours
  
- **Y-axis**:
  - Auto-calculated domain with padding
  - Padding: 15 mg/dL (or 0.8 mmol/L)
  - 4 grid lines auto-spaced
  - Labels: rounded to 1 decimal if mmol/L, integer if mg/dL

### Time in Range Section
- **Header**: "Time in Range: 92%" (if data exists)
- **Range selector**: 2d / 7d / 14d / 30d / 90d (segmented picker)
- **Stacked bar**:
  - Three colored segments: Low% | InRange% | High%
  - Height: 8pt
  - Corner radius: 4pt
  - Gap between: 1pt
  - Fill formula: `width * (percent / 100)`

- **Statistics labels** (3 columns):
  - Column 1: "↓ X.X%" (down arrow, low percentage, color-coded)
  - Column 2: "✓ X.X%" (checkmark, in-range percentage, color-coded)
  - Column 3: "↑ X.X%" (up arrow, high percentage, color-coded)

- **GMI display** (if >= 1 reading):
  - Format: "⚙️ GMI X.X%" (waveform icon)
  - Yellow warning triangle if < 14 days data
  - Subtitle: "Based on 9.5d of data — 14d+ recommended"

- **Reading count**: "150 readings" at bottom right

### Action Buttons
- **Refresh Now**: Arrow.clockwise icon, refreshes immediately
- **Check for Updates**: Arrow.down.circle icon, checks GitHub releases
- **Settings**: Gear icon, opens settings window
- **Quit**: Power icon (destructive/red), terminates app

- **Style**: Minimal, no background, hover effect
- **Layout**: Single column, full width, separated by dividers

## 5. Color System

### Zone Colors (Configurable)
```
Urgent Low  (< 55 mg/dL):  #CC1A1A (red)
Low         (55-70):       #FF9500 (orange)
In Range    (70-180):      #34C759 (green)
High        (180-250):     #FFCC00 (yellow)
Urgent High (> 250):       #CC1A1A (red)
```

### Chart Colors
- **Line**: accentColor (system blue) at 80% opacity
- **Band**: colorInRange at 8% opacity
- **Grid**: gray, low opacity
- **Text**: system default (light/dark mode aware)

## 6. Unit Conversions

### mg/dL ↔ mmol/L
```
mmol/L = mg/dL / 18.0
mg/dL = mmol/L * 18.0
```

### Display Formatting
```
mg/dL: Integer (e.g., "150")
mmol/L: One decimal (e.g., "8.3")

Delta:
mg/dL: +5 or -3 (integer)
mmol/L: +0.3 or -0.2 (one decimal)

Thresholds:
Stored internally as mg/dL
Displayed based on user's selected unit
```

## 7. Time Calculations

### Chart Ranges (from now)
```
3h   = 3 * 3600 = 10,800 seconds
6h   = 6 * 3600 = 21,600 seconds
12h  = 12 * 3600 = 43,200 seconds
24h  = 24 * 3600 = 86,400 seconds
```

### Stats Ranges (from now)
```
2d   = 2 * 86,400 = 172,800 seconds
7d   = 7 * 86,400 = 604,800 seconds
14d  = 14 * 86,400 = 1,209,600 seconds
30d  = 30 * 86,400 = 2,592,000 seconds
90d  = 90 * 86,400 = 7,776,000 seconds
```

### Age Calculations
```
reading_age = now - reading.date
stale_threshold = 20 minutes = 1200 seconds
```

## 8. Algorithms

### Chart Filtering
```
Filter readings where:
  reading.date >= (now - selected_time_range.interval)
Return sorted by date ascending (oldest first for chart)
```

### TiR Calculation
```
Filter readings where:
  reading.date >= (now - selected_stats_range.interval)

Count by zone:
  lowCount = count where value < alertLowThreshold
  highCount = count where value > alertHighThreshold
  inRangeCount = total - lowCount - highCount
  
Percentages:
  lowPct = (lowCount / total) * 100
  inRangePct = (inRangeCount / total) * 100
  highPct = (highCount / total) * 100
```

### GMI (Glucose Management Indicator)
```
formula: GMI = 3.31 + (0.02392 * mean_glucose_mg_dL)

mean_glucose = sum(reading.value for all readings) / count(readings)
gmi = 3.31 + (0.02392 * mean_glucose)

Valid only if:
  1. At least 1 reading in selected range
  2. Optionally, show warning if < 14 days of data
```

### Data Span Calculation
```
oldestReadingDate = statsReadings.last().date
dataSpanDays = (now - oldestReadingDate) / 86400
Used to warn when GMI data is insufficient
```

### Y-Domain for Chart
```
let padding = unit == .mgdL ? 15 : 0.8
let minThreshold = alertLowThreshold_mgdL
let maxThreshold = alertHighThresholdMgdL

dataMin = min(readings.map(\.value)) converted to display unit
dataMax = max(readings.map(\.value)) converted to display unit

yMin = min(dataMin, minThreshold) - padding
yMax = max(dataMax, maxThreshold) + padding

return yMin...yMax (closed range)
```

## 9. Refresh/Auto-Update Timing

### Initial Load
```
user clicks Connect
→ authenticate (2 API calls)
→ fetch 288 readings (1 API call)
→ schedule first timer
```

### Scheduled Refresh
```
Every ~5 minutes (user configurable 1-15):
  fetch 2 readings
  merge into history (deduplicate by date)
  save to disk
  evaluate alerts
  reschedule timer for next interval
```

### Timer Calculation
```
nextFireTime = max(
  lastReadingDate + refreshInterval,
  now + 30 seconds (minimum delay)
)
```

### On System Wake
```
Detect: system wake notification
Wait: 3 seconds (for network to stabilize)
Action: refresh immediately if already connected
```

## 10. Alert System

### Alert Types
```
urgentHigh     - glucose > urgentHighThreshold
high           - glucose > highThreshold (and not urgent high)
urgentLow      - glucose < urgentLowThreshold
low            - glucose < lowThreshold (and not urgent low)
risingFast     - trend == doubleUp or singleUp
droppingFast   - trend == doubleDown or singleDown
staleData      - reading age > 20 minutes
```

### Alert Cooldown
```
15 minutes between identical alert types
Can be reset for testing
```

### Critical Alerts
```
For urgent high/low:
  if alertCriticalEnabled:
    interruptionLevel = .timeSensitive
    Can break through Do Not Disturb / Focus mode
```

### Notification Format
```
Title: "{Urgent High Blood Sugar}"
Body: "{value} {unit} — urgently above your high threshold"
Sound: System default
```

## 11. Data Deduplication

### When Merging
```
existingDates = set of all dates in recentReadings
toAdd = newReadings.filter { reading.date not in existingDates }
merged = toAdd + recentReadings
sorted = merged.sorted { a.date > b.date }  // Newest first
final = sorted[0..<min(25920, sorted.count)]
```

### Important
- Dedupe by **date** (full timestamp), not by value
- Keep newest readings first in array
- Drop readings when array exceeds 25,920

## 12. Error Recovery

### Invalid Credentials / Session Expired
```
Attempt to re-authenticate using stored username + keyring password
If successful: resume normal operation
If fails: show "Session expired — reconnect in Settings"
```

### Rate Limit (HTTP 429)
```
Set error state: "Rate limited by Dexcom — will retry soon"
Schedule retry in ~30 seconds
```

### Network Error
```
Log error
Keep current reading displayed
Schedule retry in 30 seconds
```

### Parse Error
```
Log error details
Treat as transient
Retry next interval
```

