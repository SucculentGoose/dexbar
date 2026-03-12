# DexBar Linux Implementation - Complete Documentation Index

## 📚 Overview

This documentation provides **everything needed** to replicate the macOS DexBar popup interface on Linux. The source code has been analyzed and organized into 4 comprehensive guides with over 2,000 lines of reference material.

**Total Documentation**: ~80 KB across 4 files + source code reference

## 📖 Four-Part Documentation System

### 1. ✅ **LINUX_IMPLEMENTATION_GUIDE.md** (15 KB) - START HERE
**Best for**: Understanding the overall design and what needs to be built

**Contains**:
- ✅ Complete popup layout hierarchy with ASCII diagrams
- ✅ Glucose chart visualization (data source, time ranges, colors, hover interaction)
- ✅ Time in Range stats (calculation formulas, display, GMI)
- ✅ GlucoseMonitor state management (data storage, refresh cycle, persistence)
- ✅ DexcomService API integration (all endpoints, authentication)
- ✅ GlucoseReading model (all fields and conversions)
- ✅ Shared types (TimeRange, StatsTimeRange, MonitorState, TiRStats)
- ✅ Notification system (alert types, triggers, cooldowns)
- ✅ Configuration storage (UserDefaults keys, Keychain)

**Structure**: Organized by component, each section is self-contained

---

### 2. 🔧 **TECHNICAL_SPECIFICATIONS.md** (12 KB) - IMPLEMENTATION REFERENCE
**Best for**: Coding each component with precise requirements

**Contains**:
- ✅ Data models with exact field definitions
- ✅ API client specification (endpoints, parameters, response format)
- ✅ Storage format and paths
- ✅ UI component specifications (dimensions in pt/px, colors, fonts)
- ✅ Color system (hex codes and zone mappings)
- ✅ Unit conversions (formulas and display rules)
- ✅ Time calculations (all time range formulas)
- ✅ Key algorithms (filtering, TiR calculation, GMI, domain scaling)
- ✅ Refresh timing logic
- ✅ Alert system details
- ✅ Data deduplication algorithm
- ✅ Error recovery procedures

**Structure**: Organized by component type (data, API, storage, UI, etc.)

---

### 3. 🏗️ **MACOS_CODE_REFERENCE.md** (6.6 KB) - ARCHITECTURE & RELATIONSHIPS
**Best for**: Understanding how pieces fit together

**Contains**:
- ✅ File structure and organization
- ✅ Class relationships and dependencies
- ✅ Data flow diagrams
- ✅ State management overview
- ✅ Key algorithms in pseudocode
- ✅ API integration details
- ✅ Dexcom region URLs
- ✅ macOS dependencies (reference)
- ✅ Linux implementation considerations
- ✅ Key numbers and thresholds

**Structure**: High-level architecture view

---

### 4. ✓ **LINUX_PORTING_CHECKLIST.md** (7.7 KB) - IMPLEMENTATION PLAN
**Best for**: Tracking progress and planning work

**Contains**:
- ✅ Phase 1: Data layer (100% reusable files)
- ✅ Phase 2: Business logic (80-90% reusable)
- ✅ Phase 3: UI layer (must rebuild)
- ✅ Phase 4: Platform integration
- ✅ File-by-file reusability checklist
- ✅ Current Linux implementation status
- ✅ Key implementation principles
- ✅ Testing checklist
- ✅ Integration points to verify

**Structure**: Action-oriented with checkboxes

---

### 5. 📋 **README_LINUX_IMPLEMENTATION.md** (13 KB) - QUICK START
**Best for**: Navigation and high-level overview

**Contains**:
- ✅ Quick start guide (by use case)
- ✅ Data flow overview (diagram)
- ✅ Key concepts explained
- ✅ Important formulas (in box format)
- ✅ Color zones reference table
- ✅ Chart implementation notes
- ✅ External APIs reference
- ✅ Implementation order recommendation
- ✅ Testing priority guide
- ✅ License & attribution info

**Structure**: Organized for quick lookup

---

## 🗺️ How to Use This Documentation

### For Quick Understanding (30 minutes)
1. Read "Quick Start Guide" in **README_LINUX_IMPLEMENTATION.md**
2. Scan "Data Flow Overview" diagram
3. Review "Key Concepts" section
4. Check "Key Numbers to Know"

### For Component Implementation (per component)
1. **Planning phase**: Check **LINUX_PORTING_CHECKLIST.md** Phase 3 for component scope
2. **Understanding phase**: Read relevant section in **LINUX_IMPLEMENTATION_GUIDE.md**
3. **Coding phase**: Reference **TECHNICAL_SPECIFICATIONS.md** for exact requirements
4. **Integration phase**: Check **MACOS_CODE_REFERENCE.md** for relationships
5. **Testing phase**: Use checklist in **LINUX_PORTING_CHECKLIST.md**

### For Data Layer Implementation
1. Read Section 1 of **LINUX_IMPLEMENTATION_GUIDE.md** (Models)
2. Study **TECHNICAL_SPECIFICATIONS.md** Section 1-2 (Data Models & API)
3. Review source: `Sources/DexBarCore/Models/GlucoseReading.swift`
4. Review source: `Sources/DexBarCore/Services/DexcomService.swift`

### For UI Layer Implementation
1. Read Section 1 of **LINUX_IMPLEMENTATION_GUIDE.md** (Popup layout)
2. Study **TECHNICAL_SPECIFICATIONS.md** Section 4 (UI specs)
3. Review **README_LINUX_IMPLEMENTATION.md** "Chart Implementation Notes"
4. Review source: `DexBar/Sources/Views/MenuBarView.swift`
5. Review source: `DexBar/Sources/Views/GlucoseChartView.swift`

### For Testing Strategy
1. Use checklist in **LINUX_PORTING_CHECKLIST.md**
2. Cross-reference with **TECHNICAL_SPECIFICATIONS.md** Section 12 (Error Recovery)
3. Test in order: Data → Logic → UI → Integration

---

## 📂 Source Code Files Referenced

### ✅ Reusable (Copy as-is)
```
Sources/DexBarCore/Models/GlucoseReading.swift
Sources/DexBarCore/Services/DexcomService.swift
Sources/DexBarCore/Shared/CoreTypes.swift
```

### ⚠️ Adaptable (Replace platform APIs)
```
DexBar/Sources/Managers/GlucoseMonitor.swift
DexBar/Sources/Managers/NotificationManager.swift
```

### ❌ Reference Only (Rebuild in GTK/Qt)
```
DexBar/Sources/Views/MenuBarView.swift
DexBar/Sources/Views/GlucoseChartView.swift
DexBar/Sources/Views/SettingsView.swift
DexBar/Sources/DexBarApp.swift
```

---

## 🎯 Key Numbers Reference

| Parameter | Value | Location |
|-----------|-------|----------|
| Refresh interval | 5 minutes | SettingsView, GlucoseMonitor |
| Max history | 25,920 readings | GlucoseMonitor |
| API lookback | 1440 minutes (24h) | DexcomService |
| Stale threshold | 20 minutes | GlucoseMonitor.isStale |
| Alert cooldown | 15 minutes | NotificationManager |
| Initial fetch | 288 readings | GlucoseMonitor.refresh |
| Regular fetch | 2 readings | GlucoseMonitor.refresh |
| Minimum wait | 30 seconds | scheduleTimer |
| Chart height | 130pt | GlucoseChartView |
| Popup width | 300pt min | MenuBarView |
| Point size | 18pt normal, 55pt hover | GlucoseChartView |
| Chart padding | 15 mg/dL (0.8 mmol/L) | yDomain |
| GMI warning | < 14 days | MenuBarView |

---

## 🔗 API Reference

### Dexcom Share API
- **US**: `https://share2.dexcom.com/ShareWebServices/Services`
- **OUS**: `https://shareous1.dexcom.com/ShareWebServices/Services`
- **Japan**: `https://shareous1.dexcom.jp/ShareWebServices/Services`

### Linux DBus Services
- **Notifications**: `org.freedesktop.Notifications`
- **Secrets**: `org.freedesktop.Secret`
- **AppIndicator**: `com.canonical.AppMenu`

### XDG Directories
- **Data**: `$XDG_DATA_HOME/dexbar/` (default: `~/.local/share/dexbar/`)
- **Config**: `$XDG_CONFIG_HOME/dexbar/` (default: `~/.config/dexbar/`)
- **Autostart**: `~/.config/autostart/dexbar.desktop`

---

## 🧮 Critical Formulas

### Glucose Unit Conversion
```
mmol/L = mg/dL / 18.0
mg/dL = mmol/L * 18.0
```

### Time in Range
```
lowPct = (lowCount / total) * 100
inRangePct = (inRangeCount / total) * 100
highPct = (highCount / total) * 100
```

### GMI (Glucose Management Indicator)
```
Formula: GMI = 3.31 + (0.02392 * mean_glucose_mg_dL)
Valid when: at least 1 reading in range
Warning when: data_span < 14 days
```

### Data Span
```
data_span_days = (now - oldest_reading_date) / 86400
```

---

## 📊 Component Dependency Tree

```
DexcomService (API client)
    ↑
    ├─ GlucoseMonitor (state management)
    │   ├─ GlucoseReading[] (data)
    │   ├─ NotificationManager (alerts)
    │   └─ Timer (refresh scheduling)
    │
    └─ UI Layer
        ├─ PopupWindow
        │   ├─ CurrentReadingSection
        │   ├─ GlucoseChart
        │   ├─ TimeInRangeSection
        │   └─ ActionButtons
        ├─ SettingsWindow
        └─ TrayIcon
```

---

## ✅ Documentation Completeness Checklist

- [x] Popup layout and hierarchy
- [x] Chart visualization (all elements)
- [x] TiR statistics (calculation and display)
- [x] GlucoseMonitor (state management)
- [x] DexcomService (API client)
- [x] GlucoseReading (data model)
- [x] Shared types (enums and structures)
- [x] Alert system (types, triggers, cooldowns)
- [x] Configuration storage (all keys)
- [x] UI specifications (dimensions, colors, fonts)
- [x] Unit conversions (formulas and rules)
- [x] Time calculations (all ranges)
- [x] Key algorithms (filtering, TiR, GMI)
- [x] Refresh timing logic
- [x] Data deduplication
- [x] Error recovery
- [x] Color system (hex codes)
- [x] File structure (reusability matrix)
- [x] Testing strategy
- [x] Implementation phases

---

## 📞 Questions Answered

**Q: What needs to be built from scratch?**
A: UI layer (popup, chart, settings) and platform integration (tray, notifications, storage)

**Q: What can be reused?**
A: All data models and API client (DexBarCore) + 80-90% of GlucoseMonitor logic

**Q: How long should implementation take?**
A: 2-3 weeks for experienced developer familiar with GTK/Qt

**Q: What are the hardest parts?**
A: Chart visualization (catmull-rom interpolation) and system tray integration (DBus)

**Q: What are the easy parts?**
A: Data model, API client, and most calculations (already in macOS version)

---

## 🚀 Next Steps

1. **Start with Phase 1** (Data Layer)
   - Copy DexBarCore files
   - Test authentication and API calls
   - Verify data model

2. **Move to Phase 2** (Business Logic)
   - Port GlucoseMonitor
   - Test calculations
   - Verify persistence

3. **Build Phase 3** (UI Layer)
   - Create popup window
   - Implement chart
   - Add settings dialog

4. **Complete Phase 4** (Platform Integration)
   - Add tray icon
   - Wire notifications
   - Setup autostart

5. **Test & Polish**
   - Run full test suite
   - Fix edge cases
   - Optimize performance

---

**Last Updated**: March 2024
**Documentation Version**: 1.0
**Status**: Complete reference implementation guide

For questions or clarifications, refer to the specific section in the appropriate documentation file.
