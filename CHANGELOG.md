# Changelog

All notable changes to DexBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
