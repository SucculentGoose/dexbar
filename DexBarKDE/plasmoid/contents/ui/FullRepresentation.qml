import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasmoid

PlasmaExtras.Representation {
    id: root

    property var reading: null
    property var history: []
    property string errorMessage: ""
    property bool isLoading: false
    property bool isConnected: false
    property bool useMmol: Plasmoid.configuration.useMmol
    property var lastRefreshMs: 0
    property var nextRefreshMs: 0

    signal loginRequested(string username, string password, string region)
    signal refreshRequested()
    signal disconnectRequested()

    implicitWidth: Kirigami.Units.gridUnit * 16
    implicitHeight: contentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

    // Selected chart range in hours
    property int chartRangeHours: 3
    property int _tick: 0  // incremented by tickTimer to force countdown re-evaluation
    property int statsRangeDays: 7  // selected day range for TIR/GMI stats

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            PlasmaComponents3.Label {
                text: "DexBar"
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            // Refresh countdown
            PlasmaComponents3.Label {
                visible: root.isConnected && root.nextRefreshMs > 0
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.6
                text: {
                    void root._tick  // reference to force re-evaluation each second
                    if (root.nextRefreshMs <= 0) return ""
                    var secs = Math.max(0, Math.round((root.nextRefreshMs - Date.now()) / 1000))
                    if (secs > 60) return "Next: " + Math.floor(secs / 60) + "m " + (secs % 60) + "s"
                    return "Next: " + secs + "s"
                }
            }
        }
    }

    // Tick timer to update countdown every second
    Timer {
        id: tickTimer
        interval: 1000
        repeat: true
        running: root.isConnected && root.nextRefreshMs > 0
        onTriggered: root._tick++
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left; right: parent.right
            top: parent.top
            margins: Kirigami.Units.smallSpacing
        }
        spacing: Kirigami.Units.smallSpacing

        // ── Error banner
        PlasmaComponents3.Label {
            visible: root.errorMessage !== ""
            text: root.errorMessage
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ── Login form (not connected)
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

        // ── Connected: glucose display
        ColumnLayout {
            visible: root.isConnected
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true

            // ── Big value row
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: root.reading !== null ? root._displayValue(root.reading.value) : "--"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 2.5
                    font.bold: true
                    color: root.reading !== null ? root._glucoseColor(root.reading.value) : Kirigami.Theme.disabledTextColor
                }

                PlasmaComponents3.Label {
                    text: root.reading !== null ? root._trendArrow(root.reading.trend) : ""
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.8
                    color: root.reading !== null ? root._glucoseColor(root.reading.value) : Kirigami.Theme.disabledTextColor
                }

                PlasmaComponents3.Label {
                    text: {
                        if (root.reading === null) return ""
                        var unit = root.useMmol ? "mmol/L" : "mg/dL"
                        var desc = root._trendDescription(root.reading.trend)
                        var age = root._ageText(root.reading.timestampMs)
                        return unit + "\n" + desc + " · " + age
                    }
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            // Stale warning
            PlasmaComponents3.Label {
                visible: root.reading !== null && root._minutesAgo(root.reading.timestampMs) > 15
                text: "Data is stale — check your receiver"
                color: Kirigami.Theme.negativeTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.alignment: Qt.AlignHCenter
            }

            // ── Range selector buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: "Range"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                Repeater {
                    model: [3, 6, 12, 24]
                    PlasmaComponents3.Button {
                        required property int modelData
                        text: modelData + "h"
                        checked: root.chartRangeHours === modelData
                        checkable: true
                        onClicked: { root.chartRangeHours = modelData; chart.requestPaint() }
                        Layout.fillWidth: true
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }

            // ── Chart with axes
            Item {
                Layout.fillWidth: true
                height: 180
                visible: root.history.length > 1

                // Y-axis labels
                Item {
                    id: yAxis
                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                    width: 28

                    Repeater {
                        model: root._yAxisLabels()
                        PlasmaComponents3.Label {
                            required property var modelData
                            text: modelData.label
                            font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                            opacity: 0.5
                            y: modelData.y - height / 2
                        }
                    }
                }

                // Chart canvas
                Canvas {
                    id: chart
                    anchors { top: parent.top; bottom: xAxisRow.top; left: yAxis.right; right: parent.right }

                    property var slice: []
                    property var xPositions: []
                    property var yPositions: []

                    function recalc() {
                        var maxReadings = root.chartRangeHours * 12  // 5-min intervals
                        if (root.history.length < 2) { slice = []; return }
                        slice = root.history.slice(0, maxReadings).reverse()
                        var minVal = 40, maxVal = 300
                        var pad = 6
                        var xs = [], ys = []
                        for (var i = 0; i < slice.length; i++) {
                            xs.push(pad + (i / (slice.length - 1)) * (width - pad * 2))
                            var clamped = Math.min(Math.max(slice[i].value, minVal), maxVal)
                            ys.push(height - pad - ((clamped - minVal) / (maxVal - minVal)) * (height - pad * 2))
                        }
                        xPositions = xs
                        yPositions = ys
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        recalc()
                        if (slice.length < 2) return

                        var pad = 6
                        var minVal = 40, maxVal = 300
                        function yFor(v) {
                            var c = Math.min(Math.max(v, minVal), maxVal)
                            return height - pad - ((c - minVal) / (maxVal - minVal)) * (height - pad * 2)
                        }

                        // In-range band (70–180)
                        ctx.fillStyle = Qt.rgba(0.2, 0.78, 0.35, 0.08)
                        var yHigh = yFor(180), yLow = yFor(70)
                        ctx.fillRect(pad, yHigh, width - pad * 2, yLow - yHigh)

                        // Threshold dashed lines at 70 and 180
                        ctx.setLineDash([4, 4])
                        ctx.strokeStyle = Qt.rgba(1, 0.6, 0, 0.3)
                        ctx.lineWidth = 1
                        ctx.beginPath(); ctx.moveTo(pad, yFor(180)); ctx.lineTo(width - pad, yFor(180)); ctx.stroke()
                        ctx.beginPath(); ctx.moveTo(pad, yFor(70)); ctx.lineTo(width - pad, yFor(70)); ctx.stroke()
                        ctx.setLineDash([])

                        // Line
                        ctx.beginPath()
                        ctx.strokeStyle = root._glucoseColor(slice[slice.length - 1].value)
                        ctx.lineWidth = 2
                        ctx.lineJoin = "round"
                        for (var i = 0; i < xPositions.length; i++) {
                            if (i === 0) ctx.moveTo(xPositions[i], yPositions[i])
                            else ctx.lineTo(xPositions[i], yPositions[i])
                        }
                        ctx.stroke()

                        // Dots
                        for (var j = 0; j < slice.length; j++) {
                            ctx.beginPath()
                            ctx.arc(xPositions[j], yPositions[j], 2.5, 0, Math.PI * 2)
                            ctx.fillStyle = root._glucoseColor(slice[j].value)
                            ctx.fill()
                        }
                    }

                    Connections {
                        target: root
                        function onHistoryChanged() { chart.requestPaint() }
                    }
                }

                // Hover tooltip
                MouseArea {
                    id: chartMouse
                    anchors.fill: chart
                    hoverEnabled: true
                    property int hoveredIndex: -1

                    onPositionChanged: function(mouse) {
                        if (chart.xPositions.length === 0) { hoveredIndex = -1; return }
                        var closest = -1, closestDist = 999999
                        for (var i = 0; i < chart.xPositions.length; i++) {
                            var dist = Math.abs(mouse.x - chart.xPositions[i])
                            if (dist < closestDist) { closestDist = dist; closest = i }
                        }
                        hoveredIndex = closestDist < 20 ? closest : -1
                    }
                    onExited: hoveredIndex = -1
                }

                Rectangle {
                    id: tooltip
                    visible: chartMouse.hoveredIndex >= 0 && chartMouse.hoveredIndex < chart.slice.length
                    color: Kirigami.Theme.backgroundColor
                    border.color: Kirigami.Theme.textColor
                    border.width: 1
                    radius: 4
                    width: tooltipLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                    height: tooltipLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                    z: 10

                    x: {
                        if (!visible) return 0
                        var tx = yAxis.width + chart.xPositions[chartMouse.hoveredIndex] - width / 2
                        return Math.max(yAxis.width, Math.min(tx, parent.width - width))
                    }
                    y: {
                        if (!visible) return 0
                        var ty = chart.yPositions[chartMouse.hoveredIndex] - height - 6
                        return ty < 0 ? chart.yPositions[chartMouse.hoveredIndex] + 6 : ty
                    }

                    PlasmaComponents3.Label {
                        id: tooltipLabel
                        anchors.centerIn: parent
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: {
                            if (chartMouse.hoveredIndex < 0 || chartMouse.hoveredIndex >= chart.slice.length) return ""
                            var r = chart.slice[chartMouse.hoveredIndex]
                            var val = root._displayValue(r.value)
                            var time = root._timeLabel(r.timestampMs)
                            return val + " " + root._trendArrow(r.trend) + " · " + time
                        }
                    }
                }

                // X-axis time labels
                Row {
                    id: xAxisRow
                    anchors { bottom: parent.bottom; left: yAxis.right; right: parent.right }
                    height: 14

                    Repeater {
                        model: root._xAxisLabels()
                        PlasmaComponents3.Label {
                            required property var modelData
                            text: modelData
                            font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                            opacity: 0.5
                            width: (xAxisRow.width) / root._xAxisLabels().length
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            // ── Time in Range
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.history.length > 0

                // Day range selector
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: [2, 7, 14, 30, 90]
                        PlasmaComponents3.Button {
                            required property int modelData
                            text: modelData + "d"
                            checked: root.statsRangeDays === modelData
                            checkable: true
                            onClicked: root.statsRangeDays = modelData
                            Layout.fillWidth: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }

                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Time in Range: <font color='#34C759'>" + root._tirStats().inRangePct.toFixed(0) + "%</font>"
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                // Colored bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: "transparent"

                    Row {
                        anchors.fill: parent
                        Rectangle {
                            width: parent.width * root._tirStats().lowPct / 100
                            height: parent.height
                            color: "#FF3B30"
                            radius: width > 0 ? 4 : 0
                        }
                        Rectangle {
                            width: parent.width * root._tirStats().inRangePct / 100
                            height: parent.height
                            color: "#34C759"
                        }
                        Rectangle {
                            width: parent.width * root._tirStats().highPct / 100
                            height: parent.height
                            color: "#FFCC00"
                            radius: width > 0 ? 4 : 0
                        }
                    }
                }

                // Low / In Range / High percentages
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        text: "↓ " + root._tirStats().lowPct.toFixed(0) + "%"
                        color: "#FF3B30"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        text: "✓ " + root._tirStats().inRangePct.toFixed(0) + "%"
                        color: "#34C759"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        text: "↑ " + root._tirStats().highPct.toFixed(0) + "%"
                        color: "#FFCC00"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }

                // GMI and data info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Kirigami.Units.largeSpacing

                        PlasmaComponents3.Label {
                            visible: root._gmi() >= 0
                            text: "GMI " + root._gmi().toFixed(1) + "%"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.7
                        }

                        PlasmaComponents3.Label {
                            visible: root._gmi() >= 0 && root.statsRangeDays < 14
                            text: "⚠"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }

                        PlasmaComponents3.Label {
                            text: root._tirStats().count.toLocaleString() + " readings"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.7
                        }
                    }

                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            var stats = root._tirStats()
                            var days = root._actualDataDays()
                            var dayStr = days.toFixed(1) + "d of data"
                            if (root.statsRangeDays >= 14) return "Based on " + dayStr
                            return "Based on " + dayStr + " — 14d+ recommended"
                        }
                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                        opacity: 0.5
                    }
                }
            }

            // ── Actions
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

    // ── Helpers ──────────────────────────────────────────────────────────

    function _displayValue(mgdl) {
        return root.useMmol ? (mgdl / 18.0).toFixed(1) : String(mgdl)
    }

    function _trendArrow(trend) {
        var map = {
            "DoubleUp": "⇈", "SingleUp": "↑", "FortyFiveUp": "↗",
            "Flat": "→", "FortyFiveDown": "↘", "SingleDown": "↓",
            "DoubleDown": "⇊"
        }
        return map[trend] || "?"
    }

    function _trendDescription(trend) {
        var map = {
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
        var mins = _minutesAgo(timestampMs)
        if (mins < 1) return "just now"
        if (mins === 1) return "1 min ago"
        return mins + " min ago"
    }

    function _timeLabel(timestampMs) {
        var d = new Date(timestampMs)
        var h = d.getHours()
        var m = d.getMinutes()
        var ampm = h >= 12 ? "PM" : "AM"
        h = h % 12
        if (h === 0) h = 12
        return h + ":" + (m < 10 ? "0" : "") + m + " " + ampm
    }

    function _xAxisLabels() {
        if (root.history.length < 2) return []
        var maxReadings = root.chartRangeHours * 12
        var slice = root.history.slice(0, maxReadings).reverse()  // oldest-first
        var count = Math.min(4, slice.length)
        var labels = []
        for (var i = 0; i < count; i++) {
            var idx = Math.round(i * (slice.length - 1) / (count - 1))
            labels.push(_timeLabel(slice[idx].timestampMs))
        }
        return labels
    }

    function _yAxisLabels() {
        var minVal = 40, maxVal = 300, pad = 6
        var chartHeight = 180 - 14  // total item height minus x-axis row
        var ticks = [75, 100, 150, 200, 250]
        var labels = []
        for (var i = 0; i < ticks.length; i++) {
            var v = ticks[i]
            var yNorm = (v - minVal) / (maxVal - minVal)
            var y = chartHeight - pad - yNorm * (chartHeight - pad * 2)
            labels.push({ label: String(v), y: y })
        }
        return labels
    }

    // Filter history to selected stats day range
    function _statsHistory() {
        if (root.history.length === 0) return []
        var cutoffMs = Date.now() - root.statsRangeDays * 24 * 60 * 60 * 1000
        var filtered = []
        for (var i = 0; i < root.history.length; i++) {
            if (root.history[i].timestampMs >= cutoffMs) filtered.push(root.history[i])
        }
        return filtered
    }

    // Time in Range stats from filtered history
    function _tirStats() {
        var hist = _statsHistory()
        if (hist.length === 0) return { lowPct: 0, inRangePct: 0, highPct: 0, count: 0 }
        var low = 0, high = 0
        var lowThreshold = Plasmoid.configuration.alertLowMgdl || 70
        var highThreshold = Plasmoid.configuration.alertHighMgdl || 180
        for (var i = 0; i < hist.length; i++) {
            var v = hist[i].value
            if (v < lowThreshold) low++
            else if (v > highThreshold) high++
        }
        var total = hist.length
        var inRange = total - low - high
        return {
            lowPct: total > 0 ? low / total * 100 : 0,
            inRangePct: total > 0 ? inRange / total * 100 : 0,
            highPct: total > 0 ? high / total * 100 : 0,
            count: total
        }
    }

    // Calculate actual days of data available in filtered history
    function _actualDataDays() {
        var hist = _statsHistory()
        if (hist.length < 2) return 0
        var newest = hist[0].timestampMs
        var oldest = hist[hist.length - 1].timestampMs
        return (newest - oldest) / (24 * 60 * 60 * 1000)
    }

    // GMI = 3.31 + 0.02392 × mean glucose mg/dL
    function _gmi() {
        var hist = _statsHistory()
        if (hist.length === 0) return -1
        var sum = 0
        for (var i = 0; i < hist.length; i++) sum += hist[i].value
        var mean = sum / hist.length
        return 3.31 + 0.02392 * mean
    }

    function _doLogin() {
        root.loginRequested(usernameInput.text, passwordInput.text, Plasmoid.configuration.region)
    }
}
