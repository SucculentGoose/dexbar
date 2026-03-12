# DexBar macOS to Linux Implementation Guide

This directory contains comprehensive documentation for replicating the macOS DexBar application on Linux.

## 📚 Documentation Files

### 1. **LINUX_IMPLEMENTATION_GUIDE.md** (PRIMARY REFERENCE)
Complete specification of the macOS popup implementation including:
- Popup view layout hierarchy (all sections and components)
- Glucose chart visualization (data source, time ranges, colors, interpolation)
- Time in Range statistics (calculation, display, GMI formula)
- GlucoseMonitor data management (storage, refresh, persistence)
- DexcomService API integration (endpoints, authentication, error handling)
- GlucoseReading model (all fields and conversions)
- Shared types and enums (TimeRange, StatsTimeRange, MonitorState)
- Notification/alert system (types, triggers, cooldowns)
- Configuration and persistence (UserDefaults keys, Keychain)

**Read this first for the complete picture.**

### 2. **TECHNICAL_SPECIFICATIONS.md** (IMPLEMENTATION DETAILS)
Deep technical specifications for each component:
- Data model classes (GlucoseReading, TiRStats, GlucoseTrend)
- API client details (authentication, endpoints, error handling)
- Storage and persistence (file locations, formats)
- UI component specifications (dimensions, colors, fonts, spacing)
- Color system and zone definitions
- Unit conversions and display formatting
- Time calculations for all ranges
- Key algorithms (filtering, TiR, GMI, domain calculation)
- Refresh and auto-update timing
- Alert system details
- Data deduplication strategy
- Error recovery procedures

**Use this for implementation of specific components.**

### 3. **MACOS_CODE_REFERENCE.md** (ARCHITECTURE)
Architecture and code organization:
- File structure and component relationships
- Key classes and their interactions
- Data flow diagrams
- State management summary
- Key algorithms in pseudocode
- API integration details
- macOS-specific dependencies
- Linux implementation considerations
- Key numbers and thresholds

**Use this to understand how pieces fit together.**

### 4. **LINUX_PORTING_CHECKLIST.md** (IMPLEMENTATION PLAN)
Step-by-step porting strategy:
- Phase 1: Data layer (100% reusable files)
- Phase 2: Business logic (80-90% reusable with adaptations)
- Phase 3: UI layer (must rebuild from scratch)
- Phase 4: Platform integration
- Current Linux implementation status
- Key implementation principles
- File-by-file reusability checklist
- Testing and integration checklist

**Use this to plan and track your implementation work.**

## 🗂️ Source Code Files in This Repository

### macOS Implementation (Reference)
```
DexBar/Sources/
├── Views/
│   ├── MenuBarView.swift          ← Main popup UI (REFERENCE)
│   ├── GlucoseChartView.swift     ← Chart visualization (REFERENCE)
│   └── SettingsView.swift         ← Settings UI (REFERENCE)
├── Managers/
│   ├── GlucoseMonitor.swift       ← Data management (ADAPT FOR LINUX)
│   └── NotificationManager.swift  ← Alerts (ADAPT FOR LINUX)
├── Models/
│   └── Color+Hex.swift            ← Color utilities (REFERENCE)
├── Services/
│   └── KeychainService.swift      ← Password storage (REFERENCE)
└── DexBarApp.swift                ← App entry point (REFERENCE)

Sources/DexBarCore/
├── Models/
│   └── GlucoseReading.swift       ← Data model (REUSE AS-IS)
├── Services/
│   └── DexcomService.swift        ← API client (REUSE AS-IS)
└── Shared/
    └── CoreTypes.swift             ← Enums (REUSE AS-IS)
```

### Linux Implementation (Incomplete - Build Upon These)
```
DexBarLinux/Sources/
├── Views/
│   ├── PopupWindow.swift          ← Main UI (INCOMPLETE)
│   ├── SettingsWindow.swift       ← Settings (INCOMPLETE)
│   ├── TrayIcon.swift             ← Tray integration (INCOMPLETE)
│   └── GTKHelpers.swift           ← GTK utilities (INCOMPLETE)
├── Managers/
│   ├── GlucoseMonitorLinux.swift  ← Data management (INCOMPLETE)
│   └── LinuxNotificationManager.swift ← Alerts (INCOMPLETE)
├── Services/
│   ├── SecretServiceStorage.swift ← Secret Service (INCOMPLETE)
│   └── LinuxUpdater.swift         ← Updates (INCOMPLETE)
└── main.swift                      ← Entry point
```

## 🎯 Quick Start Guide

### For Understanding the Architecture:
1. Read **LINUX_IMPLEMENTATION_GUIDE.md** sections 1-3 (Popup, Chart, TiR)
2. Skim **MACOS_CODE_REFERENCE.md** for overall architecture
3. Review the complete **GlucoseMonitor.swift** file

### For Detailed Implementation:
1. Use **TECHNICAL_SPECIFICATIONS.md** as reference while coding
2. Implement each section from the checklist in **LINUX_PORTING_CHECKLIST.md**
3. Cross-reference with **LINUX_IMPLEMENTATION_GUIDE.md** for display details

### For Building the UI:
1. Review **LINUX_IMPLEMENTATION_GUIDE.md** section 1 for layout
2. Check **TECHNICAL_SPECIFICATIONS.md** section 4 for dimensions/colors
3. Study **MenuBarView.swift** to understand component structure
4. Implement equivalent in GTK/Qt

## 📊 Data Flow Overview

```
┌─────────────────┐
│  User Opens App │
└────────┬────────┘
         │
         ▼
┌──────────────────────┐
│ Load Settings & Auth │  → Stored in JSON config + Secret Service
└────────┬─────────────┘
         │
         ▼
┌──────────────────────┐
│ Load Cached Readings │  → From ~/.local/share/dexbar/readings.json
└────────┬─────────────┘
         │
         ▼
┌──────────────────────┐
│ Authenticate Dexcom  │  → API call: 2-step authentication
└────────┬─────────────┘
         │
         ▼
┌──────────────────────┐
│ Fetch Initial 288    │  → API call: get last 24h of readings
│ Readings             │
└────────┬─────────────┘
         │
         ▼
┌──────────────────────┐
│ Show Popup UI        │  → Render current reading + chart + stats
│ Update Tray Icon     │
└────────┬─────────────┘
         │
         ├──────────────────────────────┐
         │                              │
         ▼                              ▼
    ┌─────────────┐           ┌──────────────────┐
    │  User Sees  │           │ Timer Fires Every │
    │   Dashboard │           │ ~5 Minutes        │
    └─────────────┘           └────────┬─────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │ Fetch Latest 2  │  → API call
                              │ Readings        │
                              └────────┬────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │ Merge & Save    │  → Dedup by date
                              └────────┬────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │ Update UI       │
                              │ Check Alerts    │
                              └─────────────────┘
```

## 🔑 Key Concepts

### Internal vs Display Units
- **All calculations**: mg/dL (Dexcom native)
- **Display conversion**: At render time only
- **mmol/L formula**: value / 18.0
- **Delta calculation**: Same conversion applies

### Data Persistence
- **Readings**: JSON file (~7 MB for 90 days)
- **Settings**: Config file or dconf
- **Password**: Secret Service (DBus)
- **Auto-loaded** on app start

### Refresh Timing
- **Initial**: Fetch 288 readings (full 24h)
- **Regular**: Fetch 2 readings every 5 min
- **Minimum wait**: 30 seconds (API protection)
- **Stale threshold**: 20 minutes warning

### Alert System
- **Per-type cooldown**: 15 minutes
- **Critical mode**: Break through Do Not Disturb
- **7 alert types**: high/low, urgent high/low, rising/dropping fast, stale
- **Sent via**: org.freedesktop.Notifications (DBus)

## 🧮 Important Formulas

### Glucose Display
```
mgdL = reading.value (stored)
mmolL = reading.value / 18.0
display_mgdL = "150"        (integer)
display_mmolL = "8.3"       (1 decimal)
```

### TiR (Time in Range)
```
Low%     = (lowCount / total) * 100
InRange% = (inRangeCount / total) * 100
High%    = (highCount / total) * 100
```

### GMI (Glucose Management Indicator)
```
mean = sum(all readings) / count
GMI = 3.31 + (0.02392 * mean_mg_dL)
Warning if: data_span_days < 14
```

### Delta (Change from Previous)
```
delta_mg = current.value - previous.value
delta_mmol = delta_mg / 18.0
display_delta_mg = "+5" or "-3"  (with sign)
display_delta_mmol = "+0.3" or "-0.2"  (with sign, 1 decimal)
```

## 🎨 Color Zones

```
< 55 mg/dL:        Urgent Low    #CC1A1A (red)
55-70 mg/dL:       Low           #FF9500 (orange)
70-180 mg/dL:      In Range      #34C759 (green)
180-250 mg/dL:     High          #FFCC00 (yellow)
> 250 mg/dL:       Urgent High   #CC1A1A (red)
```

## 📱 Chart Implementation Notes

### Interpolation
- Use **Catmull-Rom** spline (smooth curve)
- NOT step function
- NOT linear interpolation
- Smooth glucose trends naturally

### Data Point Colors
- Evaluate in order:
  1. If < urgentLow → red
  2. Else if < low → orange
  3. Else if > urgentHigh → red
  4. Else if > high → yellow
  5. Else → green

### Hover Interaction
- Show tooltip with: value + trend + time + delta
- Point size increases: 18pt → 55pt
- Background: semi-transparent frosted glass effect
- Position: above point

## 🔗 External Resources

### Dexcom Share API
- **US**: https://share2.dexcom.com
- **OUS**: https://shareous1.dexcom.com
- **Japan**: https://shareous1.dexcom.jp
- Returns readings in mg/dL always

### Linux APIs Used
- **Secret Service**: org.freedesktop.Secret (password storage)
- **Notifications**: org.freedesktop.Notifications (D-Bus)
- **AppIndicator**: com.canonical.AppMenu (tray icon)
- **XDG Base Dirs**: $XDG_DATA_HOME, $XDG_CONFIG_HOME

## 📝 Implementation Order Recommendation

1. **Start with data layer**
   - Copy DexBarCore files as-is
   - Test DexcomService authentication and API calls

2. **Implement business logic**
   - Port GlucoseMonitor to Linux
   - Replace platform APIs incrementally
   - Test calculations (TiR, GMI, filtering)

3. **Build UI mockup**
   - Create basic GTK/Qt window
   - Add dummy data to verify layout
   - Test chart rendering with sample data

4. **Integrate real data**
   - Connect monitor to UI
   - Test refresh cycle
   - Verify data persistence

5. **Add system integration**
   - Tray icon
   - Notifications
   - Auto-start
   - Settings dialog

6. **Polish & test**
   - UI refinement
   - Error handling
   - Accessibility
   - User testing

## 🐛 Testing Priority

**High priority:**
- Authentication flow
- Reading fetching & dedup
- Chart rendering
- TiR calculation
- Data persistence

**Medium priority:**
- Alert timing & cooldown
- Unit conversion
- Settings persistence
- Tray icon display

**Low priority:**
- Auto-update checking
- Auto-start on login
- Focus mode handling

## 📄 License & Attribution

This is based on the macOS DexBar application. When implementing:
- Maintain the MIT/open-source license
- Keep attribution to original DexBar project
- Use same icons/branding if allowed
- Document any changes from original design

---

**Last Updated**: 2024
**Version**: 1.0
**Status**: Reference documentation for Linux porting
