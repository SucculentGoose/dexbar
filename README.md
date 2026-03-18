> **Medical Disclaimer:** DexBar is an unofficial, personal convenience tool and is **not a medical device**. It is not intended to be used for medical decisions, treatment, or diagnosis. Always use your official Dexcom receiver, app, or other clinically approved methods to verify your blood glucose before making any medical decisions. Do not rely solely on this app.

# DexBar

A native menu bar / system tray app that displays real-time blood glucose readings from your Dexcom CGM via the Dexcom Share API. Available for **macOS**, **Linux**, and **Windows**.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Linux](https://img.shields.io/badge/Linux-GTK4-blue)
![Windows](https://img.shields.io/badge/Windows-10%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![.NET 8](https://img.shields.io/badge/.NET-8-purple)

## Features

- **Live readings** — displays your current blood sugar value and trend arrow in the menu bar (e.g. `94 →`)
- **Auto-refresh** — polls Dexcom every 5 minutes, timed to the actual reading timestamp so refreshes stay aligned even after manual refreshes
- **mg/dL or mmol/L** — toggle units in Settings
- **Configurable alerts** — native notifications (macOS notifications, Linux libnotify, Windows balloon tips) for:
  - High blood sugar (above a threshold you set)
  - Low blood sugar (below a threshold you set)
  - Rising fast (↑ ⇈)
  - Dropping fast (↓ ⇊)
- **Alert cooldowns** — same-type alerts won't repeat within 15 minutes
- **Secure credential storage** — username and password stored in macOS Keychain / Linux Secret Service / Windows settings
- **Auto-connect on launch** — reconnects automatically using saved credentials
- **Region support** — US, Outside US, and Japan Dexcom Share endpoints

## Requirements

- macOS 14 Sonoma or later
- A Dexcom account with [Share enabled](https://provider.dexcom.com/education-research/cgm-education-use/videos/setting-dexcom-share-and-follow) and at least one follower set up
- Xcode 15+ (to build from source)

## Getting Started

### Download (easiest)

**One-line install** — paste this in Terminal. No quarantine warnings, no Gatekeeper prompts:

```bash
curl -sL https://raw.githubusercontent.com/SucculentGoose/dexbar/main/install.sh | bash
```

The script downloads the latest release directly via `curl` (bypassing macOS quarantine), installs to `/Applications`, and launches the app.

<details>
<summary>Manual install instead</summary>

1. Go to the [Releases](../../releases) page and download the latest `DexBar-vX.X.X.zip`
2. Unzip and drag **DexBar.app** to your `/Applications` folder
3. **Bypass Gatekeeper:** Because DexBar is not notarized, macOS will show a *"damaged and can't be opened"* warning. Run this once in Terminal:
   ```bash
   xattr -cr /Applications/DexBar.app
   ```
4. Open DexBar from `/Applications` normally

</details>

### Build from source

1. Clone the repo:
   ```bash
   git clone https://github.com/your-username/dexbar.git
   cd dexbar
   ```

2. Generate the Xcode project (requires [xcodegen](https://github.com/yonaskolb/XcodeGen)):
   ```bash
   brew install xcodegen
   xcodegen generate
   ```

3. Open the project in Xcode:
   ```bash
   open DexBar.xcodeproj
   ```

4. Select your Team under **Signing & Capabilities**, then build and run (`⌘R`).

### First-time setup

1. Click the ![ECG flatline icon](docs/menu-bar-icon.png) icon in your menu bar
2. Click **Settings…**
3. Enter your Dexcom username, password, and region
4. Click **Connect**

Your credentials are saved to the macOS Keychain. From this point on, DexBar will connect automatically every time it launches.

## Settings

| Setting | Description |
|---|---|
| Username / Password | Your Dexcom Share account credentials |
| Region | US / Outside US / Japan |
| Units | mg/dL or mmol/L |
| Refresh interval | 1, 2, 5, 10, or 15 minutes |
| High alert threshold | Notify when BG exceeds this value |
| Low alert threshold | Notify when BG falls below this value |
| Rising fast alert | Notify on SingleUp or DoubleUp trend |
| Dropping fast alert | Notify on SingleDown or DoubleDown trend |

## How it works

DexBar uses the **Dexcom Share API** — the same service used by Dexcom's follower app. It requires your (or the patient's) Dexcom credentials, not a follower's credentials.

API endpoints used:
- `POST /General/AuthenticatePublisherAccount` — authenticates and returns an account ID
- `POST /General/LoginPublisherAccountById` — exchanges account ID + password for a session token
- `GET /Publisher/ReadPublisherLatestGlucoseValues` — fetches the latest glucose reading

> **Note:** Dexcom Stelo is not compatible with the Share service and is not supported.

## Project structure

```
dexbar/
├── Sources/
│   └── DexBarCore/                   # Shared library (macOS + Linux)
│       ├── Models/
│       │   └── GlucoseReading.swift  # Data model, trend enum, unit conversion
│       ├── Services/
│       │   └── DexcomService.swift   # Dexcom Share API client (async/await)
│       └── Shared/
│           └── CoreTypes.swift       # MonitorState, TiRStats, TimeRange enums
├── DexBar/                           # macOS app
│   └── Sources/
│       ├── DexBarApp.swift           # App entry point, MenuBarExtra
│       ├── Services/
│       │   └── KeychainService.swift # Secure credential storage (Keychain)
│       ├── Managers/
│       │   ├── GlucoseMonitor.swift  # Polling loop, alert evaluation
│       │   └── NotificationManager.swift  # macOS notification delivery
│       └── Views/
│           ├── MenuBarView.swift     # Popover UI
│           ├── SettingsView.swift    # Settings window
│           └── GlucoseChartView.swift
├── DexBarWindows/                    # Windows app (.NET 8 / WPF)
│   ├── Program.cs                    # Single-instance entry point
│   ├── App.xaml.cs                   # Application startup, tray setup
│   ├── TrayManager.cs               # NotifyIcon tray with glucose badge
│   ├── Controls/
│   │   └── GlucoseChartControl.xaml.cs  # Custom-rendered glucose chart
│   ├── Pages/                        # Settings tab pages
│   │   ├── AccountPage.xaml
│   │   ├── DisplayPage.xaml
│   │   ├── AlertsPage.xaml
│   │   ├── AboutPage.xaml
│   │   └── DisclaimerPage.xaml
│   ├── Services/
│   │   └── UpdateChecker.cs          # Auto-update via appcast XML
│   ├── Windows/
│   │   ├── PopupWindow.xaml          # Glucose status popup
│   │   └── SettingsWindow.xaml       # Tabbed settings window
│   ├── Themes/                       # WPF resource dictionaries
│   ├── installer.iss                 # Inno Setup installer script
│   └── DexBarWindows.csproj
└── DexBarLinux/                      # Linux app
    └── Sources/
        ├── main.swift                # Entry point (GLib main loop)
        ├── Managers/
        │   ├── GlucoseMonitorLinux.swift  # Polling loop, alert evaluation
        │   └── LinuxNotificationManager.swift  # libnotify notifications
        ├── Services/
        │   └── SecretServiceStorage.swift  # KDE Wallet / GNOME Keyring
        └── Views/
            ├── TrayIcon.swift        # D-Bus StatusNotifierItem tray icon
            ├── PopupWindow.swift     # GTK4 status popup
            ├── SettingsWindow.swift  # GTK4 settings window
            └── AutoStart.swift      # ~/.config/autostart/ management
```

---

## Linux

DexBar also runs on Linux as a system tray application. It is tested on **KDE Plasma 6** but works on any desktop environment that supports the StatusNotifierItem protocol (GNOME with AppIndicator extension, XFCE, etc.).

### Linux Requirements

- Swift 6.0+ — [swift.org/download](https://swift.org/download)
- GTK4: `libgtk-4-dev`
- System tray menu: `libdbusmenu-glib-dev`
- Wayland overlay: `libgtk4-layer-shell-dev`
- Credential storage: `libsecret-1-dev`
- Desktop notifications: `libnotify-dev`

### Linux Installation

```bash
# 1. Install system dependencies (Debian/Ubuntu/KDE Neon)
sudo apt install libgtk-4-dev libdbusmenu-glib-dev libgtk4-layer-shell-dev libsecret-1-dev libnotify-dev

# 2. Clone and build
git clone https://github.com/SucculentGoose/dexbar
cd dexbar
swift build -c release --product DexBarLinux

# 3. Install (user-local, no sudo needed)
mkdir -p ~/.local/bin
cp .build/release/DexBarLinux ~/.local/bin/dexbar
```

Or use the install script which does all of the above:

```bash
curl -fsSL https://raw.githubusercontent.com/SucculentGoose/dexbar/main/install.sh | bash
```

### Linux First Run

```bash
dexbar &
```

A tray icon appears in your system tray. Click it to open the menu, then choose **Show Status** to open the glucose popup or **Open Settings** to configure the app. In Settings → **Account**, enter your Dexcom credentials, choose your region, and click **Connect**.

Credentials are stored securely in KDE Wallet (or GNOME Keyring) via the Secret Service D-Bus API. On first run KDE Wallet may prompt you to create a wallet or unlock an existing one.

### Linux Features

- **Status popup** — macOS-style popup with a live glucose chart (3h/6h/12h/24h), Time in Range bar (2d–90d), GMI, and real-time countdown to the next reading
- **Auto-update** — checks for updates on launch and daily; one-click install from the tray menu
- **Credential storage** — passwords stored securely via the Secret Service D-Bus API (KDE Wallet / GNOME Keyring)



## Windows

DexBar runs on Windows as a system tray application built with WPF and .NET 8.

### Windows Requirements

- Windows 10 or later
- .NET 8 runtime (included in the self-contained installer)

### Windows Installation

Download `DexBarSetup-X.X.X.exe` from the [Releases](../../releases) page and run the installer. It includes options for:
- Start Menu shortcut
- Desktop shortcut (optional)
- Launch at Windows startup (optional)

### Build from Source

```bash
git clone https://github.com/SucculentGoose/dexbar
cd dexbar/DexBarWindows
dotnet publish -c Release -r win-x64 --self-contained
```

The published output is in `bin/Release/net8.0-windows/win-x64/publish/`. To build the installer, install [Inno Setup 6+](https://jrsoftware.org/isinfo.php) and run:

```bash
iscc installer.iss
```

### Windows First Run

After installing, launch DexBar from the Start Menu. A tray icon appears in the system tray notification area. Click it to open the glucose status popup. Right-click for the context menu, then choose **Settings** to configure the app. In Settings → **Account**, enter your Dexcom credentials, choose your region, and click **Connect**.

### Windows Features

- **Status popup** — click the tray icon to see a live glucose chart (3h/6h/12h/24h), Time in Range bar (2d–90d), GMI, and real-time countdown to the next reading
- **Auto-update** — checks for updates every 4 hours; balloon notification with one-click install
- **Modern tray icon** — glucose value rendered as a colored badge in the notification area
- **Dark theme** — settings window uses a dark theme with tabbed navigation

## Releasing a New Version

The release is fully automated via GitHub Actions — pushing a `VERSION` change to `main` triggers builds for all three platforms. Before merging, complete these steps:

### Pre-release checklist

1. **Bump the version** in all source files:
   - `VERSION` — the single source of truth
   - `project.yml` — `MARKETING_VERSION` (macOS)
   - `DexBarLinux/Sources/AppVersion.swift` — `AppVersion.current` (Linux)
   - `DexBarWindows/DexBarWindows.csproj` — `<Version>` (Windows)
   - `DexBarWindows/installer.iss` — `#define MyAppVersion` (Windows installer)

2. **Update `CHANGELOG.md`** — add a new `## [X.X.X] - YYYY-MM-DD` section at the top with Added/Changed/Fixed subsections. The release workflow extracts the first section as GitHub Release notes.

3. **Merge to `main`** — the release workflow triggers on any push to `main` that changes `VERSION`.

### What the release workflow does automatically

- **macOS:** Builds with xcodegen + xcodebuild, signs with Sparkle, creates `DexBar-vX.X.X.zip`, updates `appcast.xml`, creates the GitHub Release and git tag
- **Linux:** Builds with Swift, packages as `dexbar-linux-x86_64-vX.X.X.tar.gz`, updates `appcast-linux.xml`
- **Windows:** Builds with `dotnet publish`, creates `DexBarSetup-vX.X.X.exe` with Inno Setup, updates `appcast-windows.xml`

> **Note:** The workflow also stamps `project.yml` and `AppVersion.swift` during CI, so even if you forget to update them locally, the built artifacts will have the correct version. However, keeping them in sync in source avoids confusion.

### Do NOT manually update

- `appcast.xml`, `appcast-linux.xml`, `appcast-windows.xml` — these are updated automatically by the release workflow
- `DexBar.xcodeproj/project.pbxproj` — regenerated by xcodegen during CI

## License

MIT
