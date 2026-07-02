# Changelog

All notable changes to DexBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.8.1] - 2026-07-01

Cross-platform bug-fix release from a full audit of the macOS, Linux, Windows, and KDE code.

### Fixed (macOS)
- Settings (unit, refresh interval, alert thresholds and toggles) are now loaded at launch — previously they silently reverted to defaults after every restart until the Settings window was opened
- A failed re-authentication no longer permanently stops auto-refresh; it now retries with delays and always reschedules the next poll
- Transient network errors during connect now retry automatically instead of requiring a manual reconnect
- Notification cooldowns are only recorded when the notification is actually delivered
- "Break through Focus/DND" setting relabeled to accurately describe time-sensitive notification behavior

### Fixed (Windows)
- Fixed continuous zero-delay polling of the Dexcom API whenever readings were stale (sensor warmup/gaps) — now backs off 30s → 300s like the other platforms
- Startup authentication failure (e.g. launch at login before Wi-Fi connects) no longer shows a "Fatal Error" dialog; it now retries in the background with escalating delays and opens Settings only for invalid credentials
- Fixed a cross-thread race where the UI could observe the readings list mid-merge
- Authentication now rejects empty/all-zero account and session IDs
- Password is only saved to Credential Manager after authentication succeeds (a typo'd password no longer overwrites a working one)
- Popup positioning now uses true per-monitor DPI (fixes wrong placement on mixed-DPI multi-monitor setups)
- Threshold boundary values (e.g. exactly 70 or 180 mg/dL) now classify as in-range, matching macOS and Linux

### Fixed (Linux)
- "Install Update" no longer accumulates duplicate click handlers across daily update checks (one click could trigger multiple installs)
- Overlay click-to-dismiss now actually works
- Reduced idle CPU usage (RunLoop bridge timer 10 ms → 50 ms)
- SIGTERM/SIGINT handlers are now async-signal-safe
- Updater now parses appcast items individually and picks the highest version instead of relying on file order
- Autostart .desktop Exec path is quoted (fixes paths containing spaces)
- Monochrome tray icon fallback color is now legible on light panels

### Fixed (KDE Plasma)
- Polls now fetch only new readings and merge into local history instead of re-downloading up to 90 days of data every 5 minutes
- A failed login or session refresh now schedules a retry instead of silently stopping polling (credential errors excluded, to avoid account lockout)

### Changed (all platforms)
- Dexcom HTTP 500 responses are now classified via the response body: expired sessions and wrong credentials are distinguished from transient server faults, which are retried instead of being reported as "invalid credentials"
- Polling backs off exponentially (30s → 300s) while no new readings arrive, instead of retrying every 30 seconds
- Reading history is persisted off the UI thread

## [1.8.0] - 2026-04-02

### Added (KDE Plasma)
- **KDE Plasma 6 widget** — native Plasmoid showing real-time Dexcom CGM glucose readings in the panel
- **Compact panel view** — glucose value, trend arrow, and delta displayed in the panel bar
- **Popup with glucose chart** — interactive chart with 3h/6h/12h/24h range selector and hoverable data points with tooltips
- **Time in Range** — colored bar with low/in-range/high percentages and 2d/7d/14d/30d/90d day range selector
- **GMI (Glucose Management Indicator)** — calculated from available readings with data quality indicator
- **Refresh countdown** — live countdown timer showing next data refresh
- **Plasma notifications** — configurable alerts for high/low/urgent glucose levels with 15-minute cooldown
- **Settings page** — configure Dexcom credentials, region (US/EU/JP/AU), units (mg/dL or mmol/L), and alert thresholds
- **Packaging** — `package.sh` script, install.sh integration with KDE detection, custom DexBar icon

## [1.7.0] - 2026-03-18

### Changed (Linux)
- **Migrated from GTK3 to GTK4** — all UI components updated to GTK4 APIs (event controllers, draw functions, child management)
- **Replaced libayatana-appindicator3 with D-Bus StatusNotifierItem** — tray icon now uses GDBus directly with libdbusmenu-glib for the menu, removing the GTK3-only appindicator dependency
- **Wayland overlay support** — StatusOverlay uses gtk4-layer-shell for proper positioning on Wayland compositors
- Updated dependencies: `libgtk-4-dev`, `libdbusmenu-glib-dev`, `libgtk4-layer-shell-dev` (replaces `libgtk-3-dev`, `libayatana-appindicator3-dev`)

### Fixed (Linux)
- Fixed check button state not being read/written correctly (GTK4 `GtkCheckButton` is no longer a `GtkToggleButton` subclass)

## [1.6.0] - 2026-03-18

### Added (Windows)
- **Windows support** — native WPF system tray app with the same features as the macOS and Linux versions
- **Inno Setup installer** — `DexBarSetup.exe` with Start Menu shortcuts, optional desktop shortcut, optional launch-at-startup
- **Auto-update** — checks `appcast-windows.xml` every 4 hours; balloon notification with one-click install
- **Glucose chart** — custom-rendered chart with 3h/6h/12h/24h range selector
- **Time in Range** — stacked bar with 2d/7d/14d/30d/90d range selector and GMI display
- **Modern tray icon** — auto-fitted glucose number with rounded background badge
- **Dark theme settings** — tabbed settings window (Account, Display, Alerts, About, Disclaimer)

### Changed
- Release workflow now builds a Windows installer (Inno Setup) instead of a standalone zip

### Fixed
- Fixed FluentWindow backdrop crash (`ExtendsContentIntoTitleBar` error) by migrating to plain WPF Window
- Fixed popup window instantly closing on tray icon click (deactivation guard)
- Fixed chart not rendering (`UserControl.OnRender` drawing behind template background)

## [1.5.2] - 2026-03-13

### Fixed
- Fixed Linux release workflow: commit changes before `git pull --rebase` to avoid unstaged changes error

## [1.5.1] - 2026-03-13

### Fixed
- Fixed update for macOS showing invalid signature.

## [1.5.0] - 2026-03-12

### Added (Linux)
- **Linux support** — new `dexbar` app for Linux desktops using GTK3 and the StatusNotifierItem (SNI) tray protocol; tested on KDE Plasma 6
- **Linux status popup** — "Show Status" in the tray menu opens a full popup matching the macOS style: large colored glucose value with status badge and timestamps, glucose chart with 3h/6h/12h/24h range selector (Cairo-drawn), Time in Range stacked bar with 2d/7d/14d/30d/90d range selector, GMI with data-span warning, and Refresh / Check for Updates / Settings / Quit action buttons
- **Linux tray icon** — displays current glucose value, SVG path trend arrow, and delta; colored by glucose range
- **Linux settings window** — tabbed GTK3 UI (Account, Display, Alerts, About); Colored Tray Icon toggle, unit, refresh interval, launch-at-login; password field shows a placeholder when a saved password exists
- **Linux credential storage** — passwords stored in the system keyring via libsecret (falls back to UserDefaults); no need to re-enter credentials between restarts
- **Linux notifications** — glucose alerts via libnotify
- **Linux autostart** — launch-at-login via systemd user service or XDG autostart entry
- **Linux auto-update** — checks on launch and daily; one-click in-place install from the tray menu; binary replaced atomically and process restarts automatically
- **Linux wake-from-sleep recovery** — re-authenticates after sleep with up to three retries (3 s, 5 s, 10 s) to allow the network to reconnect before showing an error

### Changed
- Shared networking and model code extracted into a `DexBarCore` Swift package library used by both the macOS and Linux apps
- Linux default install location is `~/.local/bin` (no sudo required); pass `--system` to `install.sh` for `/usr/local/bin`

## [1.4.3] - 2026-03-10

### Fixed
- App now re-authenticates automatically when the Dexcom session expires after an extended sleep, instead of looping in an error state until manually refreshed
- Added a brief delay on system wake before attempting a refresh, giving macOS and Linux time to reconnect to the network

## [1.4.2] - 2026-03-09

### Added
- Menu bar shows a warning triangle (⚠) when the Dexcom Share API is unreachable (e.g. 504 errors)

## [1.4.1] - 2026-03-08

### Changed
- Time in Range panel redesigned: "Time in Range: XX%" now appears as a clear headline with the day-range picker on its own row below
- Disclaimer tab moved to the end of Settings (after Updates, before About)

## [1.4.0] - 2026-03-08

### Added
- **Time in Range panel** — new section in the popover showing a stacked low/in-range/high bar and percentages; uses an independent 2d/7d/14d/30d/90d time range picker separate from the chart
- **GMI (Glucose Management Indicator)** — estimated HbA1c % displayed alongside TiR stats; shows a warning and actual data span when fewer than 14 days of history are available
- **Persistent reading history** — readings are now saved to disk on every refresh and restored on launch, allowing TiR and GMI stats to accumulate up to 90 days of history
- **Shaded in-range band on chart** — the target glucose zone is now filled with a subtle tinted band in addition to the existing threshold lines
- **Menu bar style options** — new setting in Display to choose between Value & Arrow (default), Compact, Value Only, or Arrow Only
- **Focus/DND override for urgent alerts** — new toggle in Alerts to make Urgent High and Urgent Low notifications break through macOS Focus and Do Not Disturb

## [1.3.3] - 2026-03-06

### Fixed
- Sparkle no longer offers a spurious update when already on the latest version

## [1.3.2] - 2026-03-05

### Fixed
- Version number in the About tab now updates automatically on each release

## [1.3.1] - 2026-03-05

### Added
- About tab in Settings showing the current app version and a link to the GitHub repository

## [1.3.0] - 2026-03-05

### Fixed
- Blood sugar reading no longer fails to update after waking the laptop — the app now refreshes immediately on system wake
- Session expiry (e.g. after an overnight sleep) now silently re-authenticates using stored credentials instead of requiring a manual reconnect
- Eliminated 429 rate-limit errors when clicking Connect by preventing concurrent authentication requests
- 429 responses from Dexcom now trigger a full refresh-interval backoff instead of a rapid 30-second retry

## [1.2.0] - 2026-03-01

### Added
- Launch at login setting (Settings → Display → General)
- Test notification buttons for each alert type (Settings → Alerts → Test Notifications)

### Fixed
- Notifications were never firing — notification permission was not being requested at app launch

## [1.1.0] - 2026-03-01

### Added
- New app icon

## [1.0.0] - 2026-02-28

### Added
- Initial release
- Real-time blood glucose readings from Dexcom CGM displayed in the macOS menu bar
- Automatic refresh every 5 minutes
- Support for mmol/L and mg/dL units
- Trend arrows showing glucose direction
- macOS notifications for configurable high/low thresholds and rapid rise/fall alerts
- Sparkle-based automatic in-app updates
