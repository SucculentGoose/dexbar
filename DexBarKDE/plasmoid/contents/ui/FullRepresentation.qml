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
