import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.notification 1.0
import "../code/dexcom.js" as Dexcom

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    // ── State ──────────────────────────────────────────────────────────────
    property string _sessionId: ""
    property string _baseUrl: Dexcom.BASE_URLS["US"]
    property var currentReading: null        // { value, trend, trendRate, timestampMs }
    property var readingHistory: []          // newest-first, last 24h
    property string errorMessage: ""
    property bool isLoading: false
    property bool isConnected: false
    property var _lastAlertMs: ({})          // { alertType: timestampMs }
    property string glucoseDelta: ""         // formatted delta string e.g. "+3" or "-0.2"
    property var lastRefreshMs: 0            // timestamp of last successful fetch
    property var nextRefreshMs: 0            // timestamp of next scheduled fetch
    property bool _initialFetchDone: false

    // ── Representations ────────────────────────────────────────────────────
    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
        reading: root.currentReading
        delta: root.glucoseDelta
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
        lastRefreshMs: root.lastRefreshMs
        nextRefreshMs: root.nextRefreshMs
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
        onTriggered: {
            if (!root._sessionId) {
                root._maybeAutoConnect()
            } else {
                root.fetchReadings()
            }
        }
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
        // _initialFetchDone is left alone so re-logins after an expired session fetch
        // only new readings; disconnect() resets it.
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
        // After a sleep or outage, request enough readings to fill the gap.
        const lastMs = root.readingHistory.length > 0 ? root.readingHistory[0].timestampMs : 0
        const maxCount = root._initialFetchDone ? Dexcom.fetchCountSince(lastMs, Date.now()) : 26000
        const minutes = root._initialFetchDone ? 1440 : 129600
        Dexcom.fetchReadings(root._baseUrl, root._sessionId, maxCount,
            function(readings) {
                root._initialFetchDone = true
                root.readingHistory = Dexcom.mergeReadings(root.readingHistory, readings, 25920)
                root.currentReading = root.readingHistory[0]
                root.glucoseDelta = root._computeDelta(root.readingHistory)
                root.errorMessage = ""
                root.isLoading = false
                root.lastRefreshMs = Date.now()
                root._checkAlerts(root.readingHistory[0])
                root._scheduleNextPoll(root.readingHistory[0].timestampMs)
            },
            function(err) {
                root.isLoading = false
                if (err === Dexcom.ERR_SESSION_EXPIRED) {
                    root._sessionId = ""
                    root.isConnected = false
                    root._maybeAutoConnect()
                } else {
                    root._setError(err)
                }
            },
            minutes
        )
    }

    function disconnect() {
        root._sessionId = ""
        root.isConnected = false
        root.currentReading = null
        root.readingHistory = []
        root.glucoseDelta = ""
        root.errorMessage = ""
        root.lastRefreshMs = 0
        root.nextRefreshMs = 0
        root._initialFetchDone = false
        pollTimer.stop()
    }

    // ── Private helpers ────────────────────────────────────────────────────

    function _computeDelta(readings) {
        if (readings.length < 2) return ""
        var delta = Dexcom.readingDelta(readings[1], readings[0])
        if (delta === null) return ""
        var useMmol = Plasmoid.configuration.useMmol
        if (useMmol) {
            var dMmol = delta / 18.0
            return dMmol >= 0 ? "+" + dMmol.toFixed(1) : dMmol.toFixed(1)
        }
        return delta >= 0 ? "+" + delta : String(delta)
    }

    function _setError(msg) {
        root.errorMessage = msg
        root.isLoading = false
        // Don't auto-retry credential failures — repeated bad logins can lock the account
        if (msg === Dexcom.ERR_INVALID_CREDENTIALS) return
        const u = Plasmoid.configuration.username
        const p = Plasmoid.configuration.password
        if (u && p) {
            pollTimer.interval = 60000  // retry in 1 minute on error
            pollTimer.restart()
            root.nextRefreshMs = Date.now() + 60000
        }
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
        const intervalMs = (Plasmoid.configuration.pollInterval || 300) * 1000
        // Next reading expected in (interval - elapsed) + 15s grace
        const nextMs = Math.max(15000, intervalMs + 15000 - msSinceReading)
        pollTimer.interval = nextMs
        pollTimer.restart()
        root.nextRefreshMs = nowMs + nextMs
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
