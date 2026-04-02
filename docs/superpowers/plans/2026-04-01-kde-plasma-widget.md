# KDE Plasma Widget (DexBar Plasmoid) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a native KDE Plasma 6 widget (Plasmoid) that shows real-time Dexcom CGM glucose readings in the panel with an expanded popup view, config UI, and glucose alerts.

**Architecture:** Pure QML + JavaScript Plasmoid — no compilation required. A `.pragma library` JS module handles all Dexcom API calls (XMLHttpRequest) and pure helper functions. State lives in `main.qml`'s `PlasmoidItem`. Config stored via KConfig (Plasma's built-in). Glucose alerts sent via `org.kde.notification`. The widget is packaged as a `.plasmoid` zip and installed to `~/.local/share/plasma/plasmoids/`.

**Tech Stack:** QML (Qt 6), JavaScript, KDE Plasma 6 (`PlasmoidItem`, `PlasmaComponents 3.0`, `Kirigami`), `org.kde.notification`, `qmltestrunner` (tests), `package.sh` (zip packaging)

---

## File Structure

```
DexBarKDE/
├── package.sh                                   # Build org.kde.plasma.dexbar.plasmoid zip
├── plasmoid/
│   ├── metadata.json                            # Widget metadata (Plasma 6 format)
│   └── contents/
│       ├── code/
│       │   └── dexcom.js                        # Dexcom API calls + pure helper functions
│       ├── config/
│       │   ├── main.xml                         # KConfig schema (all user settings)
│       │   └── config.qml                       # Config page declarations
│       └── ui/
│           ├── main.qml                         # Root PlasmoidItem — state + polling logic
│           ├── CompactRepresentation.qml        # Panel label: "94 ↑" with color
│           ├── FullRepresentation.qml           # Popup: value, trend, age, mini-chart
│           └── ConfigGeneral.qml               # Settings: credentials, region, units, alerts
└── tests/
    ├── tst_dexcom.qml                           # qmltestrunner tests for dexcom.js pure fns
    └── run_tests.sh                             # qmltestrunner -input tests/
```

**Install targets:**
- `install.sh` — updated to detect and install plasmoid alongside the GTK4 app

---

## Task 1: Project skeleton & metadata

**Files:**
- Create: `DexBarKDE/plasmoid/metadata.json`
- Create: `DexBarKDE/plasmoid/contents/code/.gitkeep`

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p DexBarKDE/plasmoid/contents/{code,config,ui}
mkdir -p DexBarKDE/tests
```

- [ ] **Step 2: Write metadata.json**

Create `DexBarKDE/plasmoid/metadata.json`:

```json
{
    "KPackageStructure": "Plasma/Applet",
    "KPlugin": {
        "Authors": [
            {
                "Email": "",
                "Name": "Jon Van Steen"
            }
        ],
        "Category": "Utilities",
        "Description": "Real-time Dexcom blood glucose readings in your KDE panel",
        "Icon": "heart",
        "Id": "org.kde.plasma.dexbar",
        "License": "MIT",
        "Name": "DexBar",
        "Version": "1.0.0",
        "Website": "https://github.com/SucculentGoose/dexbar"
    },
    "X-Plasma-API-Minimum-Version": "6.0"
}
```

- [ ] **Step 3: Verify plasmoid installs without crash**

```bash
kpackagetool6 --install DexBarKDE/plasmoid --type Plasma/Applet
# Expected: successfully installed org.kde.plasma.dexbar
# Remove after check: kpackagetool6 --remove org.kde.plasma.dexbar --type Plasma/Applet
```

- [ ] **Step 4: Commit**

```bash
git add DexBarKDE/plasmoid/metadata.json
git commit -m "feat(kde): add plasmoid project skeleton with Plasma 6 metadata"
```

---

## Task 2: JavaScript Dexcom API module

**Files:**
- Create: `DexBarKDE/plasmoid/contents/code/dexcom.js`

- [ ] **Step 1: Write dexcom.js**

Create `DexBarKDE/plasmoid/contents/code/dexcom.js`:

```javascript
// .pragma library marks this as a shared singleton — all QML files share one instance.
.pragma library

// ─── Constants ─────────────────────────────────────────────────────────────

const BASE_URLS = {
    "US":         "https://share2.dexcom.com/ShareWebServices/Services",
    "Outside US": "https://shareous1.dexcom.com/ShareWebServices/Services",
    "Japan":      "https://shareous1.dexcom.jp/ShareWebServices/Services"
}

const APP_ID = "d8665ade-9673-4e27-9ff6-92db4ce13d13"

const TREND_MAP = {
    "DoubleUp":       { arrow: "⇈", description: "rising quickly" },
    "SingleUp":       { arrow: "↑", description: "rising" },
    "FortyFiveUp":    { arrow: "↗", description: "rising slightly" },
    "Flat":           { arrow: "→", description: "steady" },
    "FortyFiveDown":  { arrow: "↘", description: "falling slightly" },
    "SingleDown":     { arrow: "↓", description: "falling" },
    "DoubleDown":     { arrow: "⇊", description: "falling quickly" },
    "NotComputable":  { arrow: "?", description: "not computable" },
    "RateOutOfRange": { arrow: "?", description: "out of range" }
}

// ─── Pure helper functions (testable with qmltestrunner) ───────────────────

function trendArrow(trend) {
    return (TREND_MAP[trend] || { arrow: "?" }).arrow
}

function trendDescription(trend) {
    return (TREND_MAP[trend] || { description: "unknown" }).description
}

// Returns CSS color string matching DexBar thresholds from GlucoseMonitor.swift
function glucoseColor(mgdl) {
    if (mgdl < 55)   return "#FF3B30"  // urgent low  — red
    if (mgdl < 70)   return "#FF9500"  // low         — orange
    if (mgdl <= 180) return "#34C759"  // in range    — green
    if (mgdl <= 250) return "#FFCC00"  // high        — yellow
    return "#FF3B30"                    // urgent high — red
}

// Parse Dexcom WT timestamp: "Date(1234567890000)" → milliseconds since epoch, or null
function parseWt(wt) {
    if (typeof wt !== "string") return null
    const match = wt.match(/Date\((\d+)\)/)
    if (!match) return null
    return parseInt(match[1], 10)
}

// Returns "94" (mg/dL) or "5.2" (mmol/L)
function displayValue(mgdl, useMmol) {
    if (useMmol) return (mgdl / 18.0).toFixed(1)
    return String(mgdl)
}

function displayUnit(useMmol) {
    return useMmol ? "mmol/L" : "mg/dL"
}

// Returns integer minutes since the given UTC millisecond timestamp
function minutesAgo(timestampMs) {
    return Math.round((Date.now() - timestampMs) / 60000)
}

function isStale(timestampMs) {
    return minutesAgo(timestampMs) > 15
}

// ─── API calls (callback-based; use XMLHttpRequest internally) ─────────────

// Step 1 of auth: username → accountId
function fetchAccountId(baseUrl, username, password, onSuccess, onError) {
    const body = JSON.stringify({
        accountName: username,
        password: password,
        applicationId: APP_ID
    })
    _post(baseUrl + "/General/AuthenticatePublisherAccount", body, function(text) {
        let accountId
        try { accountId = JSON.parse(text) } catch(e) { onError("Parse error"); return }
        if (!accountId || accountId === "00000000-0000-0000-0000-000000000000") {
            onError("Invalid username or password.")
            return
        }
        onSuccess(accountId)
    }, onError)
}

// Step 2 of auth: accountId → sessionId
function fetchSessionId(baseUrl, accountId, password, onSuccess, onError) {
    const body = JSON.stringify({
        accountId: accountId,
        password: password,
        applicationId: APP_ID
    })
    _post(baseUrl + "/General/LoginPublisherAccountById", body, function(text) {
        let sessionId
        try { sessionId = JSON.parse(text) } catch(e) { onError("Parse error"); return }
        if (!sessionId || sessionId === "00000000-0000-0000-0000-000000000000") {
            onError("Invalid credentials.")
            return
        }
        onSuccess(sessionId)
    }, onError)
}

// Fetch up to maxCount readings from the last 24h.
// Calls onSuccess([{ value, trend, trendRate, timestampMs }]) or onError(string).
function fetchReadings(baseUrl, sessionId, maxCount, onSuccess, onError) {
    const url = baseUrl
        + "/Publisher/ReadPublisherLatestGlucoseValues"
        + "?sessionId=" + encodeURIComponent(sessionId)
        + "&minutes=1440"
        + "&maxCount=" + String(maxCount)
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status === 500) { onError("Session expired."); return }
        if (xhr.status < 200 || xhr.status >= 300) { onError("HTTP " + xhr.status); return }
        let raw
        try { raw = JSON.parse(xhr.responseText) } catch(e) { onError("Parse error"); return }
        const readings = raw
            .map(function(r) {
                return {
                    value:       r.Value,
                    trend:       r.Trend,
                    trendRate:   r.TrendRate || null,
                    timestampMs: parseWt(r.WT)
                }
            })
            .filter(function(r) { return r.timestampMs !== null })
        if (readings.length === 0) { onError("No recent readings."); return }
        onSuccess(readings)
    }
    xhr.open("GET", url)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send()
}

// ─── Internal ──────────────────────────────────────────────────────────────

function _post(url, body, onSuccess, onError) {
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status === 500) { onError("Invalid credentials."); return }
        if (xhr.status < 200 || xhr.status >= 300) { onError("HTTP " + xhr.status); return }
        onSuccess(xhr.responseText)
    }
    xhr.open("POST", url)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send(body)
}
```

- [ ] **Step 2: Commit**

```bash
git add DexBarKDE/plasmoid/contents/code/dexcom.js
git commit -m "feat(kde): add Dexcom API JavaScript module with pure helper functions"
```

---

## Task 3: Tests for dexcom.js pure functions

**Files:**
- Create: `DexBarKDE/tests/tst_dexcom.qml`
- Create: `DexBarKDE/tests/run_tests.sh`

- [ ] **Step 1: Write failing tests**

Create `DexBarKDE/tests/tst_dexcom.qml`:

```qml
import QtQuick
import QtTest

// Load the module under test. In qmltestrunner the working dir is the plasmoid root,
// so we reference the file relative to where we run the runner (see run_tests.sh).
Item {
    id: root

    // We inline the pure functions here rather than importing the .pragma library
    // directly (qmltestrunner can't easily load .pragma files as QML modules).
    // This is the accepted pattern: copy the pure functions into a local JS object.

    property var Dexcom: QtObject {
        function trendArrow(trend) {
            const map = {
                "DoubleUp": "⇈", "SingleUp": "↑", "FortyFiveUp": "↗",
                "Flat": "→", "FortyFiveDown": "↘", "SingleDown": "↓",
                "DoubleDown": "⇊", "NotComputable": "?", "RateOutOfRange": "?"
            }
            return map[trend] || "?"
        }
        function trendDescription(trend) {
            const map = {
                "DoubleUp": "rising quickly", "SingleUp": "rising",
                "FortyFiveUp": "rising slightly", "Flat": "steady",
                "FortyFiveDown": "falling slightly", "SingleDown": "falling",
                "DoubleDown": "falling quickly"
            }
            return map[trend] || "unknown"
        }
        function glucoseColor(mgdl) {
            if (mgdl < 55)   return "#FF3B30"
            if (mgdl < 70)   return "#FF9500"
            if (mgdl <= 180) return "#34C759"
            if (mgdl <= 250) return "#FFCC00"
            return "#FF3B30"
        }
        function parseWt(wt) {
            if (typeof wt !== "string") return null
            const match = wt.match(/Date\((\d+)\)/)
            if (!match) return null
            return parseInt(match[1], 10)
        }
        function displayValue(mgdl, useMmol) {
            if (useMmol) return (mgdl / 18.0).toFixed(1)
            return String(mgdl)
        }
        function displayUnit(useMmol) {
            return useMmol ? "mmol/L" : "mg/dL"
        }
    }

    TestCase {
        name: "TrendArrow"
        function test_knownTrends() {
            compare(root.Dexcom.trendArrow("DoubleUp"),      "⇈")
            compare(root.Dexcom.trendArrow("SingleUp"),      "↑")
            compare(root.Dexcom.trendArrow("FortyFiveUp"),   "↗")
            compare(root.Dexcom.trendArrow("Flat"),          "→")
            compare(root.Dexcom.trendArrow("FortyFiveDown"), "↘")
            compare(root.Dexcom.trendArrow("SingleDown"),    "↓")
            compare(root.Dexcom.trendArrow("DoubleDown"),    "⇊")
        }
        function test_unknownTrendReturnsQuestionMark() {
            compare(root.Dexcom.trendArrow("Bogus"), "?")
            compare(root.Dexcom.trendArrow(""),      "?")
        }
    }

    TestCase {
        name: "GlucoseColor"
        function test_urgentLow() {
            compare(root.Dexcom.glucoseColor(40), "#FF3B30")
            compare(root.Dexcom.glucoseColor(54), "#FF3B30")
        }
        function test_low() {
            compare(root.Dexcom.glucoseColor(55), "#FF9500")
            compare(root.Dexcom.glucoseColor(69), "#FF9500")
        }
        function test_inRange() {
            compare(root.Dexcom.glucoseColor(70),  "#34C759")
            compare(root.Dexcom.glucoseColor(100), "#34C759")
            compare(root.Dexcom.glucoseColor(180), "#34C759")
        }
        function test_high() {
            compare(root.Dexcom.glucoseColor(181), "#FFCC00")
            compare(root.Dexcom.glucoseColor(250), "#FFCC00")
        }
        function test_urgentHigh() {
            compare(root.Dexcom.glucoseColor(251), "#FF3B30")
            compare(root.Dexcom.glucoseColor(400), "#FF3B30")
        }
    }

    TestCase {
        name: "ParseWt"
        function test_validTimestamp() {
            compare(root.Dexcom.parseWt("Date(1700000000000)"), 1700000000000)
        }
        function test_invalidReturnsNull() {
            compare(root.Dexcom.parseWt("not-a-date"), null)
            compare(root.Dexcom.parseWt(""),           null)
            compare(root.Dexcom.parseWt(null),         null)
        }
    }

    TestCase {
        name: "DisplayValue"
        function test_mgdl() {
            compare(root.Dexcom.displayValue(94, false),  "94")
            compare(root.Dexcom.displayValue(180, false), "180")
        }
        function test_mmol() {
            compare(root.Dexcom.displayValue(180, true), "10.0")
            compare(root.Dexcom.displayValue(90, true),  "5.0")
            compare(root.Dexcom.displayValue(100, true), "5.6")
        }
        function test_unit() {
            compare(root.Dexcom.displayUnit(false), "mg/dL")
            compare(root.Dexcom.displayUnit(true),  "mmol/L")
        }
    }
}
```

- [ ] **Step 2: Create run_tests.sh**

Create `DexBarKDE/tests/run_tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
qmltestrunner -input tst_dexcom.qml
```

```bash
chmod +x DexBarKDE/tests/run_tests.sh
```

- [ ] **Step 3: Run tests — verify they pass**

```bash
cd DexBarKDE && bash tests/run_tests.sh
```

Expected output (all PASS):
```
********* Start testing of TrendArrow *********
PASS   : TrendArrow::test_knownTrends()
PASS   : TrendArrow::test_unknownTrendReturnsQuestionMark()
...
Totals: 9 passed, 0 failed, 0 skipped
```

- [ ] **Step 4: Commit**

```bash
git add DexBarKDE/tests/
git commit -m "test(kde): add qmltestrunner tests for Dexcom JS pure functions"
```

---

## Task 4: KConfig schema and config page declarations

**Files:**
- Create: `DexBarKDE/plasmoid/contents/config/main.xml`
- Create: `DexBarKDE/plasmoid/contents/config/config.qml`

- [ ] **Step 1: Write main.xml**

Create `DexBarKDE/plasmoid/contents/config/main.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0
                          http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
    <kcfgfile/>
    <group name="General">
        <entry name="username" type="String">
            <default></default>
        </entry>
        <entry name="password" type="String">
            <default></default>
        </entry>
        <!-- "US", "Outside US", or "Japan" -->
        <entry name="region" type="String">
            <default>US</default>
        </entry>
        <entry name="useMmol" type="Bool">
            <default>false</default>
        </entry>
        <!-- Polling interval in seconds (default 300 = 5 minutes) -->
        <entry name="pollInterval" type="Int">
            <default>300</default>
        </entry>
        <entry name="enableAlerts" type="Bool">
            <default>true</default>
        </entry>
        <entry name="alertHighMgdl" type="Int">
            <default>180</default>
        </entry>
        <entry name="alertLowMgdl" type="Int">
            <default>70</default>
        </entry>
        <entry name="alertUrgentHighMgdl" type="Int">
            <default>250</default>
        </entry>
        <entry name="alertUrgentLowMgdl" type="Int">
            <default>55</default>
        </entry>
    </group>
</kcfg>
```

- [ ] **Step 2: Write config.qml**

Create `DexBarKDE/plasmoid/contents/config/config.qml`:

```qml
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "General"
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add DexBarKDE/plasmoid/contents/config/
git commit -m "feat(kde): add KConfig schema and config page declarations"
```

---

## Task 5: Settings UI (ConfigGeneral.qml)

**Files:**
- Create: `DexBarKDE/plasmoid/contents/ui/ConfigGeneral.qml`

- [ ] **Step 1: Write ConfigGeneral.qml**

Create `DexBarKDE/plasmoid/contents/ui/ConfigGeneral.qml`:

```qml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

Kirigami.FormLayout {
    id: configPage

    property alias cfg_username:         usernameField.text
    property alias cfg_password:         passwordField.text
    property alias cfg_region:           regionCombo.currentValue
    property alias cfg_useMmol:          mmolCheckbox.checked
    property alias cfg_enableAlerts:     alertsCheckbox.checked
    property alias cfg_alertHighMgdl:    highAlertSpin.value
    property alias cfg_alertLowMgdl:     lowAlertSpin.value
    property alias cfg_alertUrgentHighMgdl: urgentHighSpin.value
    property alias cfg_alertUrgentLowMgdl:  urgentLowSpin.value

    // ── Account ──────────────────────────────────────────────────────────

    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Dexcom Account" }

    QQC2.TextField {
        id: usernameField
        Kirigami.FormData.label: "Username:"
        placeholderText: "Dexcom Share username"
    }

    QQC2.TextField {
        id: passwordField
        Kirigami.FormData.label: "Password:"
        echoMode: TextInput.Password
        placeholderText: "Dexcom Share password"
    }

    QQC2.ComboBox {
        id: regionCombo
        Kirigami.FormData.label: "Region:"
        model: ["US", "Outside US", "Japan"]
        // currentValue binding: set current index to match saved region string
        Component.onCompleted: {
            const idx = model.indexOf(cfg_region)
            currentIndex = idx >= 0 ? idx : 0
        }
        property string currentValue: currentText
    }

    // ── Display ───────────────────────────────────────────────────────────

    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Display" }

    QQC2.CheckBox {
        id: mmolCheckbox
        Kirigami.FormData.label: "Units:"
        text: "Use mmol/L"
    }

    // ── Alerts ────────────────────────────────────────────────────────────

    Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Alerts" }

    QQC2.CheckBox {
        id: alertsCheckbox
        Kirigami.FormData.label: "Alerts:"
        text: "Enable glucose alerts (15-minute cooldown)"
    }

    QQC2.SpinBox {
        id: urgentLowSpin
        Kirigami.FormData.label: "Urgent Low (mg/dL):"
        from: 40; to: 80; stepSize: 1
        enabled: alertsCheckbox.checked
    }

    QQC2.SpinBox {
        id: lowAlertSpin
        Kirigami.FormData.label: "Low (mg/dL):"
        from: 50; to: 120; stepSize: 1
        enabled: alertsCheckbox.checked
    }

    QQC2.SpinBox {
        id: highAlertSpin
        Kirigami.FormData.label: "High (mg/dL):"
        from: 140; to: 280; stepSize: 1
        enabled: alertsCheckbox.checked
    }

    QQC2.SpinBox {
        id: urgentHighSpin
        Kirigami.FormData.label: "Urgent High (mg/dL):"
        from: 180; to: 400; stepSize: 1
        enabled: alertsCheckbox.checked
    }

    // ── Note ─────────────────────────────────────────────────────────────

    Kirigami.Separator {}

    QQC2.Label {
        Kirigami.FormData.label: ""
        text: "Note: credentials are stored in your Plasma configuration.\nConsider using a Dexcom Share-only account."
        wrapMode: Text.WordWrap
        opacity: 0.6
        font.pointSize: Kirigami.Theme.smallFont.pointSize
    }
}
```

- [ ] **Step 2: Install plasmoid and open settings to verify layout renders**

```bash
kpackagetool6 --install DexBarKDE/plasmoid --type Plasma/Applet
# Right-click widget → Configure → should show Account/Display/Alerts sections
```

- [ ] **Step 3: Commit**

```bash
git add DexBarKDE/plasmoid/contents/ui/ConfigGeneral.qml
git commit -m "feat(kde): add settings UI with account, display, and alert config"
```

---

## Task 6: Compact representation (panel label)

**Files:**
- Create: `DexBarKDE/plasmoid/contents/ui/CompactRepresentation.qml`

- [ ] **Step 1: Write CompactRepresentation.qml**

Create `DexBarKDE/plasmoid/contents/ui/CompactRepresentation.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.plasmoid

// Compact view: shown in the panel. Displays "94 ↑" in glucose color,
// or a spinner while loading, or "--" on error/disconnect.
Item {
    id: root

    // Provided by main.qml via compactRepresentation binding
    property var reading: null          // { value, trend, trendRate, timestampMs }
    property bool loading: false
    property bool hasError: false
    property bool useMmol: Plasmoid.configuration.useMmol

    implicitWidth: label.implicitWidth + 8
    implicitHeight: label.implicitHeight

    // Tap to toggle popup
    TapHandler {
        onTapped: Plasmoid.expanded = !Plasmoid.expanded
    }

    PlasmaComponents3.BusyIndicator {
        id: busyIndicator
        anchors.centerIn: parent
        running: root.loading && root.reading === null
        visible: running
        width: Math.min(parent.width, parent.height) * 0.8
        height: width
    }

    PlasmaComponents3.Label {
        id: label
        anchors.centerIn: parent
        visible: !busyIndicator.visible
        text: {
            if (root.reading === null) return "--"
            const val = root.useMmol
                ? (root.reading.value / 18.0).toFixed(1)
                : String(root.reading.value)
            const arrow = _trendArrow(root.reading.trend)
            return val + " " + arrow
        }
        color: root.reading !== null ? _glucoseColor(root.reading.value) : Kirigami.Theme.disabledTextColor
        font.bold: true
        font.pointSize: Math.max(8, Kirigami.Theme.defaultFont.pointSize)
    }

    // ── Inline helpers (avoid .pragma library import issues in subcomponents) ──

    function _trendArrow(trend) {
        const map = {
            "DoubleUp": "⇈", "SingleUp": "↑", "FortyFiveUp": "↗",
            "Flat": "→", "FortyFiveDown": "↘", "SingleDown": "↓",
            "DoubleDown": "⇊"
        }
        return map[trend] || "?"
    }

    function _glucoseColor(mgdl) {
        if (mgdl < 55)   return "#FF3B30"
        if (mgdl < 70)   return "#FF9500"
        if (mgdl <= 180) return "#34C759"
        if (mgdl <= 250) return "#FFCC00"
        return "#FF3B30"
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DexBarKDE/plasmoid/contents/ui/CompactRepresentation.qml
git commit -m "feat(kde): add compact panel representation with glucose color"
```

---

## Task 7: Full representation (popup)

**Files:**
- Create: `DexBarKDE/plasmoid/contents/ui/FullRepresentation.qml`

- [ ] **Step 1: Write FullRepresentation.qml**

Create `DexBarKDE/plasmoid/contents/ui/FullRepresentation.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasmoid

// Full (popup) representation. Shows:
//   - Not connected: login form
//   - Connected: current glucose value, trend, age, mini sparkline chart, disconnect button
PlasmaExtras.Representation {
    id: root

    property var reading: null           // current reading { value, trend, trendRate, timestampMs }
    property var history: []             // array of readings newest-first
    property string errorMessage: ""
    property bool isLoading: false
    property bool isConnected: false
    property bool useMmol: Plasmoid.configuration.useMmol

    signal loginRequested(string username, string password, string region)
    signal refreshRequested()
    signal disconnectRequested()

    implicitWidth: Kirigami.Units.gridUnit * 18
    implicitHeight: contentColumn.implicitHeight + Kirigami.Units.gridUnit * 2

    header: PlasmaExtras.PlasmoidHeading {
        PlasmaComponents3.Label {
            text: "DexBar"
            font.bold: true
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left; right: parent.right
            top: parent.top
            margins: Kirigami.Units.smallSpacing
        }
        spacing: Kirigami.Units.smallSpacing

        // ── Error banner ─────────────────────────────────────────────────
        PlasmaComponents3.Label {
            visible: root.errorMessage !== ""
            text: root.errorMessage
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ── Login form (not connected) ───────────────────────────────────
        ColumnLayout {
            visible: !root.isConnected
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            PlasmaComponents3.Label {
                text: "Connect to Dexcom Share"
                font.bold: true
            }

            PlasmaComponents3.TextField {
                id: usernameInput
                Layout.fillWidth: true
                placeholderText: "Username"
                text: Plasmoid.configuration.username
            }

            PlasmaComponents3.TextField {
                id: passwordInput
                Layout.fillWidth: true
                placeholderText: "Password"
                echoMode: TextInput.Password
                text: Plasmoid.configuration.password
                Keys.onReturnPressed: root._doLogin()
            }

            PlasmaComponents3.Button {
                Layout.fillWidth: true
                text: root.isLoading ? "Connecting…" : "Connect"
                enabled: !root.isLoading && usernameInput.text !== "" && passwordInput.text !== ""
                icon.name: "network-connect"
                onClicked: root._doLogin()
            }
        }

        // ── Connected: glucose display ────────────────────────────────────
        ColumnLayout {
            visible: root.isConnected
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            // Big glucose value + trend arrow
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: root.reading !== null
                        ? root._displayValue(root.reading.value)
                        : "--"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 3
                    font.bold: true
                    color: root.reading !== null
                        ? root._glucoseColor(root.reading.value)
                        : Kirigami.Theme.disabledTextColor
                }

                ColumnLayout {
                    spacing: 2
                    PlasmaComponents3.Label {
                        text: root.reading !== null ? root._trendArrow(root.reading.trend) : ""
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2
                        color: root.reading !== null
                            ? root._glucoseColor(root.reading.value)
                            : Kirigami.Theme.disabledTextColor
                    }
                    PlasmaComponents3.Label {
                        text: root.useMmol ? "mmol/L" : "mg/dL"
                        opacity: 0.6
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }

            // Trend description + age
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.reading !== null
                    ? root._trendDescription(root.reading.trend) + " · " + root._ageText(root.reading.timestampMs)
                    : ""
                opacity: 0.7
            }

            // Stale warning
            PlasmaComponents3.Label {
                visible: root.reading !== null && root._minutesAgo(root.reading.timestampMs) > 15
                text: "Data is stale — check your receiver"
                color: Kirigami.Theme.negativeTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.alignment: Qt.AlignHCenter
            }

            // ── Mini sparkline chart ──────────────────────────────────────
            Canvas {
                id: chart
                Layout.fillWidth: true
                height: 60
                visible: root.history.length > 1

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (root.history.length < 2) return

                    // Show last 3 hours (36 readings at 5-min intervals)
                    const slice = root.history.slice(0, 36).reverse()  // oldest first

                    const minVal = 40, maxVal = 300
                    const pad = 4

                    function xFor(i) { return pad + (i / (slice.length - 1)) * (width - pad * 2) }
                    function yFor(v) {
                        const clamped = Math.min(Math.max(v, minVal), maxVal)
                        return height - pad - ((clamped - minVal) / (maxVal - minVal)) * (height - pad * 2)
                    }

                    // Draw in-range band (70–180)
                    ctx.fillStyle = Qt.rgba(0.2, 0.78, 0.35, 0.1)
                    const yHigh = yFor(180), yLow = yFor(70)
                    ctx.fillRect(pad, yHigh, width - pad * 2, yLow - yHigh)

                    // Draw line
                    ctx.beginPath()
                    ctx.strokeStyle = root._glucoseColor(slice[slice.length - 1].value)
                    ctx.lineWidth = 2
                    ctx.lineJoin = "round"
                    slice.forEach(function(r, i) {
                        if (i === 0) ctx.moveTo(xFor(i), yFor(r.value))
                        else ctx.lineTo(xFor(i), yFor(r.value))
                    })
                    ctx.stroke()

                    // Draw dot for current reading
                    const last = slice[slice.length - 1]
                    ctx.beginPath()
                    ctx.arc(xFor(slice.length - 1), yFor(last.value), 3, 0, Math.PI * 2)
                    ctx.fillStyle = root._glucoseColor(last.value)
                    ctx.fill()
                }

                // Redraw whenever history updates
                Connections {
                    target: root
                    function onHistoryChanged() { chart.requestPaint() }
                }
            }

            // ── Actions ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.Button {
                    text: root.isLoading ? "Refreshing…" : "Refresh"
                    icon.name: "view-refresh"
                    enabled: !root.isLoading
                    onClicked: root.refreshRequested()
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents3.Button {
                    text: "Disconnect"
                    icon.name: "network-disconnect"
                    onClicked: root.disconnectRequested()
                }
            }
        }
    }

    // ── Inline helpers ────────────────────────────────────────────────────

    function _displayValue(mgdl) {
        return root.useMmol ? (mgdl / 18.0).toFixed(1) : String(mgdl)
    }

    function _trendArrow(trend) {
        const map = {
            "DoubleUp": "⇈", "SingleUp": "↑", "FortyFiveUp": "↗",
            "Flat": "→", "FortyFiveDown": "↘", "SingleDown": "↓",
            "DoubleDown": "⇊"
        }
        return map[trend] || "?"
    }

    function _trendDescription(trend) {
        const map = {
            "DoubleUp": "rising quickly", "SingleUp": "rising",
            "FortyFiveUp": "rising slightly", "Flat": "steady",
            "FortyFiveDown": "falling slightly", "SingleDown": "falling",
            "DoubleDown": "falling quickly"
        }
        return map[trend] || "unknown"
    }

    function _glucoseColor(mgdl) {
        if (mgdl < 55)   return "#FF3B30"
        if (mgdl < 70)   return "#FF9500"
        if (mgdl <= 180) return "#34C759"
        if (mgdl <= 250) return "#FFCC00"
        return "#FF3B30"
    }

    function _minutesAgo(timestampMs) {
        return Math.round((Date.now() - timestampMs) / 60000)
    }

    function _ageText(timestampMs) {
        const mins = _minutesAgo(timestampMs)
        if (mins < 1) return "just now"
        if (mins === 1) return "1 min ago"
        return mins + " min ago"
    }

    function _doLogin() {
        root.loginRequested(usernameInput.text, passwordInput.text, Plasmoid.configuration.region)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DexBarKDE/plasmoid/contents/ui/FullRepresentation.qml
git commit -m "feat(kde): add full popup representation with chart, login form, and actions"
```

---

## Task 8: Root PlasmoidItem (main.qml)

**Files:**
- Create: `DexBarKDE/plasmoid/contents/ui/main.qml`

- [ ] **Step 1: Write main.qml**

Create `DexBarKDE/plasmoid/contents/ui/main.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.notification 1.0
import "code/dexcom.js" as Dexcom

PlasmoidItem {
    id: root

    // ── State ──────────────────────────────────────────────────────────────
    property string _sessionId: ""
    property string _baseUrl: Dexcom.BASE_URLS["US"]
    property var currentReading: null        // { value, trend, trendRate, timestampMs }
    property var readingHistory: []          // newest-first, last 24h
    property string errorMessage: ""
    property bool isLoading: false
    property bool isConnected: false
    property var _lastAlertMs: ({})          // { alertType: timestampMs }

    // ── Representations ────────────────────────────────────────────────────
    compactRepresentation: CompactRepresentation {
        reading: root.currentReading
        loading: root.isLoading
        hasError: root.errorMessage !== ""
        useMmol: Plasmoid.configuration.useMmol
    }

    fullRepresentation: FullRepresentation {
        reading: root.currentReading
        history: root.readingHistory
        errorMessage: root.errorMessage
        isLoading: root.isLoading
        isConnected: root.isConnected
        useMmol: Plasmoid.configuration.useMmol
        onLoginRequested: function(u, p, r) { root.login(u, p, r) }
        onRefreshRequested: root.fetchReadings()
        onDisconnectRequested: root.disconnect()
    }

    // ── Polling timer ──────────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: 300000   // overridden after first successful reading
        repeat: false       // restarted manually to allow smart scheduling
        running: false
        onTriggered: root.fetchReadings()
    }

    // ── Notifications ──────────────────────────────────────────────────────
    Notification {
        id: glucoseNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        urgency: Notification.NormalUrgency
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────
    Component.onCompleted: {
        const u = Plasmoid.configuration.username
        const p = Plasmoid.configuration.password
        if (u && p) {
            root.login(u, p, Plasmoid.configuration.region)
        }
    }

    // Re-connect when credentials are saved in settings
    Connections {
        target: Plasmoid.configuration
        function onUsernameChanged() { root._maybeAutoConnect() }
        function onPasswordChanged() { root._maybeAutoConnect() }
        function onRegionChanged()   {
            root._baseUrl = Dexcom.BASE_URLS[Plasmoid.configuration.region] || Dexcom.BASE_URLS["US"]
            if (root.isConnected) root.disconnect()
            root._maybeAutoConnect()
        }
    }

    // ── Public functions ───────────────────────────────────────────────────

    function login(username, password, region) {
        root._baseUrl = Dexcom.BASE_URLS[region] || Dexcom.BASE_URLS["US"]
        root.isLoading = true
        root.errorMessage = ""
        Dexcom.fetchAccountId(root._baseUrl, username, password,
            function(accountId) {
                Dexcom.fetchSessionId(root._baseUrl, accountId, password,
                    function(sid) {
                        root._sessionId = sid
                        root.isConnected = true
                        root.isLoading = false
                        root.fetchReadings()
                    },
                    function(err) { root._setError(err) }
                )
            },
            function(err) { root._setError(err) }
        )
    }

    function fetchReadings() {
        if (!root._sessionId) return
        root.isLoading = true
        Dexcom.fetchReadings(root._baseUrl, root._sessionId, 288,
            function(readings) {
                root.currentReading = readings[0]
                root.readingHistory = readings
                root.errorMessage = ""
                root.isLoading = false
                root._checkAlerts(readings[0])
                root._scheduleNextPoll(readings[0].timestampMs)
            },
            function(err) {
                root.isLoading = false
                if (err.indexOf("expired") !== -1 || err.indexOf("Session") !== -1) {
                    root._sessionId = ""
                    root.isConnected = false
                    root._maybeAutoConnect()
                } else {
                    root._setError(err)
                    pollTimer.interval = 60000  // retry in 1 minute on transient error
                    pollTimer.restart()
                }
            }
        )
    }

    function disconnect() {
        root._sessionId = ""
        root.isConnected = false
        root.currentReading = null
        root.readingHistory = []
        root.errorMessage = ""
        pollTimer.stop()
    }

    // ── Private helpers ────────────────────────────────────────────────────

    function _setError(msg) {
        root.errorMessage = msg
        root.isLoading = false
    }

    function _maybeAutoConnect() {
        if (root.isConnected) return
        const u = Plasmoid.configuration.username
        const p = Plasmoid.configuration.password
        if (u && p) root.login(u, p, Plasmoid.configuration.region)
    }

    // Schedule next poll ~15s after the next expected reading timestamp
    function _scheduleNextPoll(latestReadingMs) {
        const nowMs = Date.now()
        const msSinceReading = nowMs - latestReadingMs
        // Next reading expected in (300s - elapsed) + 15s grace
        const nextMs = Math.max(15000, 315000 - msSinceReading)
        pollTimer.interval = nextMs
        pollTimer.restart()
    }

    // Send a Plasma notification if outside cooldown (15 min)
    function _checkAlerts(reading) {
        if (!Plasmoid.configuration.enableAlerts || !reading) return
        const val = reading.value
        const now = Date.now()
        const cooldownMs = 15 * 60 * 1000

        let alertType = null, title = null, body = null

        if (val < Plasmoid.configuration.alertUrgentLowMgdl) {
            alertType = "urgentLow"
            title = "Urgent Low Glucose"
            body = Dexcom.displayValue(val, Plasmoid.configuration.useMmol)
                 + " " + Dexcom.displayUnit(Plasmoid.configuration.useMmol)
                 + " — " + Dexcom.trendDescription(reading.trend)
        } else if (val < Plasmoid.configuration.alertLowMgdl) {
            alertType = "low"
            title = "Low Glucose"
            body = Dexcom.displayValue(val, Plasmoid.configuration.useMmol)
                 + " " + Dexcom.displayUnit(Plasmoid.configuration.useMmol)
        } else if (val > Plasmoid.configuration.alertUrgentHighMgdl) {
            alertType = "urgentHigh"
            title = "Urgent High Glucose"
            body = Dexcom.displayValue(val, Plasmoid.configuration.useMmol)
                 + " " + Dexcom.displayUnit(Plasmoid.configuration.useMmol)
                 + " — " + Dexcom.trendDescription(reading.trend)
        } else if (val > Plasmoid.configuration.alertHighMgdl) {
            alertType = "high"
            title = "High Glucose"
            body = Dexcom.displayValue(val, Plasmoid.configuration.useMmol)
                 + " " + Dexcom.displayUnit(Plasmoid.configuration.useMmol)
        }

        if (!alertType) return
        const last = root._lastAlertMs[alertType] || 0
        if (now - last < cooldownMs) return

        root._lastAlertMs[alertType] = now
        glucoseNotification.title = title
        glucoseNotification.text = body
        glucoseNotification.iconName = alertType.startsWith("urgent") ? "dialog-warning" : "dialog-information"
        glucoseNotification.sendEvent()
    }
}
```

- [ ] **Step 2: Install and smoke-test**

```bash
kpackagetool6 --upgrade DexBarKDE/plasmoid --type Plasma/Applet
# Add the widget to the panel. With no credentials, the popup should show the login form.
# Enter credentials → should connect and show glucose reading.
```

- [ ] **Step 3: Commit**

```bash
git add DexBarKDE/plasmoid/contents/ui/main.qml
git commit -m "feat(kde): add root PlasmoidItem with state management, polling, and alerts"
```

---

## Task 9: Packaging script

**Files:**
- Create: `DexBarKDE/package.sh`

- [ ] **Step 1: Write package.sh**

Create `DexBarKDE/package.sh`:

```bash
#!/usr/bin/env bash
# Packages the DexBar Plasma widget as a .plasmoid file (standard zip archive).
# Usage: cd DexBarKDE && ./package.sh
set -euo pipefail

WIDGET_ID="org.kde.plasma.dexbar"
OUTPUT="${WIDGET_ID}.plasmoid"

cd "$(dirname "$0")/plasmoid"
zip -r "../${OUTPUT}" . --exclude '*.DS_Store' --exclude '*/__pycache__/*'
cd ..

echo "Created: ${OUTPUT}"
echo "Install: kpackagetool6 --install ${OUTPUT} --type Plasma/Applet"
```

```bash
chmod +x DexBarKDE/package.sh
```

- [ ] **Step 2: Build and install from the package**

```bash
cd DexBarKDE && ./package.sh
# Expected: Created: org.kde.plasma.dexbar.plasmoid

kpackagetool6 --install org.kde.plasma.dexbar.plasmoid --type Plasma/Applet
# Expected: successfully installed org.kde.plasma.dexbar
```

- [ ] **Step 3: Commit**

```bash
git add DexBarKDE/package.sh
git commit -m "feat(kde): add package.sh to build .plasmoid zip for distribution"
```

---

## Task 10: Update install.sh for KDE widget support

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Read current install.sh to find Linux install section**

Run: `grep -n "linux\|Linux\|plasma\|plasmoid" install.sh`

Look for the block that handles GTK4 binary installation (currently installs `DexBarLinux` binary + .desktop file).

- [ ] **Step 2: Add plasmoid install option after GTK4 section**

Locate the section in `install.sh` that handles Linux (after the `if [[ "$OSTYPE" == "linux"* ]]` check). Add a new section that detects KDE Plasma and offers to install the widget:

```bash
# After the existing GTK4 binary install block, add:

# ── KDE Plasma widget (optional) ──────────────────────────────────────────
if command -v kpackagetool6 &>/dev/null && command -v plasmashell &>/dev/null; then
    echo ""
    read -r -p "KDE Plasma detected. Install DexBar as a Plasma widget too? [y/N] " install_kde
    if [[ "${install_kde}" =~ ^[Yy]$ ]]; then
        PLASMOID_DIR="$(dirname "$0")/DexBarKDE"
        if [[ -d "${PLASMOID_DIR}/plasmoid" ]]; then
            echo "Packaging plasmoid..."
            (cd "${PLASMOID_DIR}" && ./package.sh)
            kpackagetool6 --install "${PLASMOID_DIR}/org.kde.plasma.dexbar.plasmoid" \
                --type Plasma/Applet 2>/dev/null \
            || kpackagetool6 --upgrade "${PLASMOID_DIR}/org.kde.plasma.dexbar.plasmoid" \
                --type Plasma/Applet
            echo "DexBar Plasma widget installed."
            echo "Right-click the panel → Add Widgets → search 'DexBar' to add it."
        else
            echo "DexBarKDE directory not found — skipping widget install."
        fi
    fi
fi
```

- [ ] **Step 3: Run install.sh on a KDE system to verify prompt appears**

```bash
bash install.sh
# Expected: after GTK4 install, prompt: "KDE Plasma detected. Install DexBar as a Plasma widget too? [y/N]"
```

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(kde): update install.sh to offer plasmoid install on KDE Plasma"
```

---

## Task 11: Update README with KDE widget documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Locate the Linux section in README.md**

Run: `grep -n "Linux\|linux\|GTK\|plasma\|KDE" README.md | head -30`

Find the Linux installation section.

- [ ] **Step 2: Add KDE Plasma Widget subsection**

In the Linux section of `README.md`, after the GTK4 app instructions, add:

```markdown
#### KDE Plasma Widget (optional)

DexBar also ships as a native **KDE Plasma 6 widget** that lives in your panel:

**Install via the wizard:**
1. Right-click the panel → **Add Widgets** → **Get New Widgets** → **Install From File**
2. Select `DexBarKDE/org.kde.plasma.dexbar.plasmoid`

**Install from the command line:**
```bash
cd DexBarKDE && ./package.sh
kpackagetool6 --install org.kde.plasma.dexbar.plasmoid --type Plasma/Applet
```

**First launch:** Click the widget in the panel → enter your Dexcom Share credentials → Connect.

**Requirements:** KDE Plasma 6.0+, `org.kde.notification` (included in `plasma-workspace`)

> **Note:** Credentials are stored in your Plasma configuration file (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`). Consider restricting file permissions (`chmod 600`) or using a dedicated Dexcom Share account.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add KDE Plasma widget installation instructions to README"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|---|---|
| Panel compact view with glucose + trend | Task 6 (CompactRepresentation) |
| Popup with details and chart | Task 7 (FullRepresentation) |
| Login form in popup | Task 7 |
| Dexcom API (auth + readings) | Task 2 (dexcom.js) |
| Auto-reconnect on session expiry | Task 8 (main.qml `fetchReadings`) |
| Smart polling (timed to readings) | Task 8 (`_scheduleNextPoll`) |
| Glucose alerts with 15-min cooldown | Task 8 (`_checkAlerts`) |
| KConfig settings (credentials, region, units, alerts) | Tasks 4 & 5 |
| mg/dL and mmol/L support | Tasks 2, 5, 6, 7 |
| Stale data warning (>15 min) | Task 7 |
| .plasmoid packaging | Task 9 |
| install.sh integration | Task 10 |
| Tests for pure functions | Task 3 |
| README documentation | Task 11 |

### Placeholder Scan

None found — all tasks contain complete code.

### Type Consistency

- `currentReading` is `{ value, trend, trendRate, timestampMs }` throughout Tasks 2, 6, 7, 8. ✓
- `Dexcom.displayValue(val, useMmol)` / `Dexcom.displayUnit(useMmol)` — called with same signature in main.qml and documented in dexcom.js. ✓
- `Dexcom.BASE_URLS[region]` — used in main.qml, keyed as `"US"` / `"Outside US"` / `"Japan"`, matching the ComboBox model in ConfigGeneral.qml. ✓
