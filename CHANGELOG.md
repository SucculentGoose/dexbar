# Changelog

All notable changes to DexBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
