import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.plasmoid
import org.kde.kirigami 2.20 as Kirigami

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
