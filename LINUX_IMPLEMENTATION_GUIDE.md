# DexBar macOS Popup Implementation Guide for Linux Replication

## 1. POPUP VIEW LAYOUT HIERARCHY (MenuBarView.swift)

The macOS popup is a comprehensive dashboard shown when clicking the menu bar icon. It uses a vertical stack layout:

```
VStack(alignment: .leading, spacing: 0) {
  ├── Current Reading Section
  │   ├── [Optional] Stale Data Warning (orange banner if >20 min old)
  │   ├── HStack with:
  │   │   ├── LEFT: Glucose value & trend
  │   │   │   ├── Text: "{value}{trend_arrow}" (size 36, semibold, rounded)
  │   │   │   └── Text: "{trend} · {unit}" or "{trend} · {delta} · {unit}"
  │   │   └── RIGHT: Status info
  │   │       ├── Status badge (Live/Updating/Error/Disconnected)
  │   │       ├── Last updated (relative time)
  │   │       └── Next refresh (relative time)
  │   └── Divider
  │
  ├── Chart Section (GlucoseChartView)
  │   ├── Picker: 3h / 6h / 12h / 24h range selector (segmented)
  │   └── Apple Charts with:
  │       ├── In-range shaded background band
  │       ├── High/Low threshold dashed lines (red/orange)
  │       ├── Glucose line (blue, 2pt, catmull-rom interpolation)
  │       ├── Data points (colored by zone)
  │       └── Interactive hover callout (shows value + time + delta)
  │   └── Divider
  │
  ├── Time in Range Section
  │   ├── Label + percentage (if data exists)
  │   ├── Picker: 2d / 7d / 14d / 30d / 90d (segmented)
  │   ├── Stacked bar chart:
  │   │   └── Colored segments: Low% | InRange% | High%
  │   ├── Three labels: Low%, InRange%, High% with icons
  │   ├── GMI display with warning if <14 days of data
  │   └── Reading count
  │   └── Divider
  │
  ├── Actions Section
  │   ├── "Refresh Now" button
  │   ├── "Check for Updates" button
  │   ├── "Settings..." button
  │   └── "Quit DexBar" button (destructive)
  └── All padding: 4pt vertical, 16pt horizontal sections
```

**Key Visual Details:**
- Min width: 300pt
- Glucose value: color-coded (red/orange/green/yellow based on zone)
- Trend arrow: Single character (⇈ ⇊ ↑ ↓ ↗ ↘ → ?)
- Font stack: System font with rounded design
- All sections separated by dividers for clarity

## 2. GLUCOSE CHART (GlucoseChartView.swift)

### Data Source
```swift
chartReadings: [GlucoseReading] {
  let cutoff = Date().addingTimeInterval(-selectedTimeRange.interval)
  return recentReadings.filter { $0.date >= cutoff }
}
```

### Time Ranges
- **3h**: 180 minutes (x-axis stride: every 1 hour)
- **6h**: 360 minutes (x-axis stride: every 2 hours)
- **12h**: 720 minutes (x-axis stride: every 3 hours)
- **24h**: 1440 minutes (x-axis stride: every 6 hours)

### Chart Components

1. **Background Band (In-Range Zone)**
   - Rectangle from Low threshold to High threshold
   - Color: `colorInRange.opacity(0.08)`
   - Spans full width

2. **Threshold Lines**
   - High threshold: red dashed line, opacity 0.35
   - Low threshold: orange dashed line, opacity 0.5
   - Dash pattern: [4, 3] (4 on, 3 off)

3. **Glucose Line**
   - Color: `accentColor.opacity(0.8)`
   - Width: 2pt
   - Interpolation: Catmull-Rom (smooth curve)
   - One line per data point

4. **Data Points**
   - Symbol size: 18pt (normal), 55pt (hover)
   - Colors (in order of evaluation):
     - `colorUrgentLow` if < urgentLowThreshold
     - `colorLow` if < lowThreshold
     - `colorUrgentHigh` if > urgentHighThreshold
     - `colorHigh` if > highThreshold
     - `colorInRange` (default)

5. **Hover Callout**
   - Shows: "{value} {trend_arrow} · {delta} (optional)"
   - Shows: Time (HH:MM format)
   - Background: regularMaterial (macOS frosted glass effect)
   - Corner radius: 5pt

### Y-Axis Domain Calculation
```swift
let padding = unit == .mgdL ? 15 : 0.8  // mg/dL or mmol/L
let minV = min(readings.min, lowThreshold) - padding
let maxV = max(readings.max, highThreshold) + padding
return minV...maxV
```

### Unit Conversion
- All glucose values stored as **mg/dL internally**
- Display conversion: `mmolL = mgdL / 18.0`
- Threshold conversion: same formula

## 3. TIME IN RANGE STATS (MenuBarView.swift)

### TiRStats Calculation
```swift
struct TiRStats {
  lowCount: Int       // readings < lowThreshold
  inRangeCount: Int   // readings >= low && <= high
  highCount: Int      // readings > highThreshold
  total: Int
  
  // Computed percentages
  lowPct = (lowCount / total) * 100
  inRangePct = (inRangeCount / total) * 100
  highPct = (highCount / total) * 100
}
```

### Thresholds Used
- `alertLowThresholdMgdL` (default 70)
- `alertHighThresholdMgdL` (default 180)

### Time Ranges
- 2d, 7d, 14d, 30d, 90d
- User-selectable via segmented picker
- Calculated from `recentReadings` filtered by time

### GMI Calculation
```swift
Formula: GMI = 3.31 + (0.02392 × mean_glucose_mg_dL)
- Based on mean of all readings in selected range
- Warning flag if < 14 days of data available
- Display: "%.1f%%"
```

### TiR Stacked Bar
- Three colored segments with proportional widths
- Gap between segments: 1pt
- Corner radius: 4pt
- Heights: 8pt
- Three labels below with icons:
  - "Low" with down arrow icon
  - "In Range" with checkmark icon
  - "High" with up arrow icon

## 4. GLUCOSEMONITOR - DATA MANAGEMENT (GlucoseMonitor.swift)

### Reading Storage
```swift
var recentReadings: [GlucoseReading] = []  // Newest first, up to 90 days
var currentReading: GlucoseReading?         // Latest single reading
```

### Persistence
- Stored in: `~/Library/Application Support/DexBar/readings.json`
- Auto-saved after each refresh
- Auto-loaded on app startup
- Capacity: 25,920 readings (90 days × 288 readings/day)

### Refresh Mechanism
```swift
private func refresh(initialLoad: Bool = false) async {
  // Initial load: fetch 288 readings (90 days)
  // Regular refresh: fetch 2 readings (last 2)
  let newReadings = try await service.getLatestReadings(maxCount: initialLoad ? 288 : 2)
  
  // Deduplicate by date and merge
  let toAdd = newReadings.filter { !existingDates.contains($0.date) }
  let merged = (toAdd + recentReadings).sorted { $0.date > $1.date }
  recentReadings = Array(merged.prefix(25920))
}
```

### Auto-Refresh Scheduling
```swift
private func scheduleTimer(after lastReadingDate: Date? = nil) {
  // Next refresh = lastReadingDate + refreshInterval
  // Minimum: 30 seconds from now (to avoid hammering API)
  refreshInterval = 5 minutes (default, user-configurable)
}
```

### Selection State
```swift
var selectedTimeRange: TimeRange = .threeHours
var selectedStatsRange: StatsTimeRange = .sevenDays
```

### Color Zone Configuration
```swift
colorUrgentLow = red(0.85, 0.1, 0.1)    // < 55 mg/dL
colorLow = orange                        // 55-70 mg/dL
colorInRange = green                     // 70-180 mg/dL
colorHigh = yellow                       // 180-250 mg/dL
colorUrgentHigh = red(0.85, 0.1, 0.1)   // > 250 mg/dL
```

### Alert Thresholds (All stored as mg/dL)
```swift
alertUrgentHighThresholdMgdL = 250
alertHighThresholdMgdL = 180
alertLowThresholdMgdL = 70
alertUrgentLowThresholdMgdL = 55
```

### Delta Calculation
```swift
glucoseDelta: Int? {
  guard recentReadings.count >= 2 else { return nil }
  return recentReadings[0].value - recentReadings[1].value  // Latest - Previous
}

// Formatted for display
func formattedDelta(unit: GlucoseUnit) -> String? {
  case .mgdL: delta >= 0 ? "+\(delta)" : "\(delta)"
  case .mmolL: delta / 18.0, formatted with ±%.1f
}
```

### Stale Data Detection
```swift
var isStale: Bool {
  Date().timeIntervalSince(currentReading.date) > 20 minutes
}
```

## 5. DEXCOMSERVICE - API INTERACTION (DexcomService.swift)

### Service Methods

#### `authenticate(username, password)`
Two-step authentication:
1. Call `/General/AuthenticatePublisherAccount` → get accountID
2. Call `/General/LoginPublisherAccountById` → get sessionID
Both return quoted UUID strings

**Request format:**
```json
{
  "accountName": "user@example.com",
  "password": "...",
  "applicationId": "d8665ade-9673-4e27-9ff6-92db4ce13d13"
}
```

#### `getLatestReadings(maxCount: Int)`
```
GET /Publisher/ReadPublisherLatestGlucoseValues
?sessionId={sessionId}&minutes=1440&maxCount={maxCount}
```

**Parameters:**
- `minutes=1440`: Always 24-hour lookback window
- `maxCount`: 288 (initial), 2 (regular refresh)

**Response:** Array of `DexcomRawReading` objects

### Regions
```swift
enum DexcomRegion {
  case us = "https://share2.dexcom.com/ShareWebServices/Services"
  case ous = "https://shareous1.dexcom.com/ShareWebServices/Services"
  case jp = "https://shareous1.dexcom.jp/ShareWebServices/Services"
}
```

### Error Handling
```swift
case invalidCredentials       // 500 status or empty accountID/sessionID
case sessionExpired           // When sessionID is nil
case noReadings               // Empty response
case networkError(Error)      // Network failure
case serverError(Int)         // HTTP 4xx/5xx
case decodingError(Error)     // JSON parse failure
```

**Retry logic:**
- Session expired → attempt re-authenticate
- Rate limited (429) → retry with timer
- Other errors → log, schedule retry

### Response Parsing
```swift
struct DexcomRawReading: Decodable {
  let wt: String        // "Date(1234567890000)" format
  let value: Int        // mg/dL always
  let trend: String     // "DoubleUp", "SingleUp", etc.
  let trendRate: Double?
}

// Conversion
func toGlucoseReading() -> GlucoseReading? {
  // Extract milliseconds from WT, convert to Date
  let date = Date(timeIntervalSince1970: ms / 1000.0)
  let trend = trendMap[trend_string] ?? .none
  return GlucoseReading(value, trend, date, trendRate)
}
```

## 6. GLUCOSE READING MODEL (GlucoseReading.swift)

```swift
public struct GlucoseReading: Identifiable, Codable {
  public let id: UUID                    // Auto-generated on decode
  public let value: Int                  // Always mg/dL (core unit)
  public let trend: GlucoseTrend        // Enum with arrow, description
  public let date: Date                  // Reading timestamp
  public let trendRate: Double?          // mg/dL per minute (optional)
  
  // Helper properties
  var mmolL: Double { Double(value) / 18.0 }
  
  func displayValue(unit: GlucoseUnit) -> String
  func menuBarLabel(unit: GlucoseUnit) -> String
}
```

### GlucoseTrend Enum
```swift
public enum GlucoseTrend: Int, Codable {
  case none = 0
  case doubleUp = 1           // ⇈ "rising quickly"
  case singleUp = 2           // ↑ "rising"
  case fortyFiveUp = 3        // ↗ "rising slightly"
  case flat = 4               // → "steady"
  case fortyFiveDown = 5      // ↘ "falling slightly"
  case singleDown = 6         // ↓ "falling"
  case doubleDown = 7         // ⇊ "falling quickly"
  case notComputable = 8      // ? "not computable"
  case rateOutOfRange = 9     // ? "out of range"
}
```

### Trend Properties
```swift
var isRisingFast: Bool { self == .doubleUp || self == .singleUp }
var isDroppingFast: Bool { self == .doubleDown || self == .singleDown }
```

### Serialization
- ID excluded from JSON (regenerated on decode)
- CodingKeys explicitly specify which fields persist
- Date stored as ISO format

## 7. CORETYPES - SHARED ENUMS (CoreTypes.swift)

### MonitorState
```swift
enum MonitorState {
  case idle              // "Not connected"
  case loading           // "Loading…"
  case connected         // "Connected"
  case error(String)     // Custom error message
}
```

### TimeRange (Chart range selector)
```swift
enum TimeRange: String, CaseIterable {
  case threeHours = "3h"    // 3 × 3600 = 10,800 sec
  case sixHours = "6h"      // 6 × 3600 = 21,600 sec
  case twelveHours = "12h"  // 12 × 3600 = 43,200 sec
  case day = "24h"          // 24 × 3600 = 86,400 sec
}
```

### StatsTimeRange (TiR range selector)
```swift
enum StatsTimeRange: String, CaseIterable {
  case twoDays = "2d"          // 2 × 86400 = 172,800 sec
  case sevenDays = "7d"        // 7 × 86400 = 604,800 sec
  case fourteenDays = "14d"    // 14 × 86400 = 1,209,600 sec
  case thirtyDays = "30d"      // 30 × 86400 = 2,592,000 sec
  case ninetyDays = "90d"      // 90 × 86400 = 7,776,000 sec
}
```

## 8. NOTIFICATION/ALERT SYSTEM (NotificationManager.swift)

### Alert Types
```swift
enum AlertType {
  case urgentHigh
  case high
  case urgentLow
  case low
  case risingFast
  case droppingFast
  case staleData
}
```

### Trigger Logic
```swift
// Evaluated after each refresh:
if v > urgentHighThreshold       → urgentHigh alert (critical optional)
else if v > highThreshold        → high alert
if v < urgentLowThreshold        → urgentLow alert (critical optional)
else if v < lowThreshold         → low alert
if trend.isRisingFast            → risingFast alert
if trend.isDroppingFast          → droppingFast alert
if age > 20 minutes              → staleData alert
```

### Cooldown
- 15 minutes between same-type alerts
- Critical alerts can break through Focus/Do Not Disturb

## 9. CONFIGURATION & PERSISTENCE

### UserDefaults Keys
```swift
// Account
"dexcomUsername"        // String
"dexcomRegion"          // DexcomRegion.rawValue
// (password stored in Keychain)

// Display
"glucoseUnit"           // GlucoseUnit.rawValue
"refreshIntervalMinutes" // Double (5.0 default)
"coloredMenuBar"        // Bool (shows color dot)
"menuBarStyle"          // MenuBarStyle.rawValue
"showDelta"             // Bool

// Alerts
"alertUrgentHighEnabled"       // Bool
"alertUrgentHighMgdL"          // Double (250.0)
"alertHighEnabled"             // Bool
"alertHighMgdL"                // Double (180.0)
"alertLowEnabled"              // Bool
"alertLowMgdL"                 // Double (70.0)
"alertUrgentLowEnabled"        // Bool
"alertUrgentLowMgdL"           // Double (55.0)
"alertRisingFastEnabled"       // Bool
"alertDroppingFastEnabled"     // Bool
"alertStaleDataEnabled"        // Bool
"alertCriticalEnabled"         // Bool

// Colors (hex strings)
"colorUrgentLow"               // #RRGGBB
"colorLow"                     // #RRGGBB
"colorInRange"                 // #RRGGBB
"colorHigh"                    // #RRGGBB
"colorUrgentHigh"              // #RRGGBB
```

### Keychain Keys
```swift
"password"  // Dexcom account password
```

## 10. KEY DIFFERENCES FROM TYPICAL DASHBOARDS

1. **Dual Range Selection**: Separate controls for chart (3h-24h) and stats (2d-90d)
2. **Threshold-Based Stats**: Low/InRange/High percentages based on exact threshold values
3. **Catmull-Rom Interpolation**: Smooth glucose curves rather than step functions
4. **Interactive Hover**: Context tooltips on chart hover with delta
5. **Persistent Storage**: Full 90-day history saved locally as JSON
6. **Auto-Deduplication**: New readings merged with history by date
7. **Stale Detection**: Orange warning if >20 min without update
8. **GMI Calculation**: Glucose Management Indicator from mean glucose
9. **Trend-Based Alerts**: Separate alerts for rising/falling fast
10. **Region-Aware API**: Multi-region Dexcom Share support (US, OUS, Japan)

