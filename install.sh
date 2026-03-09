#!/usr/bin/env bash
set -euo pipefail

REPO="SucculentGoose/dexbar"
APP_NAME="DexBar"
INSTALL_DIR="/Applications"

# ── colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BOLD}==> ${RESET}$*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
die()     { echo -e "${RED}✗ Error:${RESET} $*" >&2; exit 1; }

OS="$(uname)"

# ══════════════════════════════════════════════════════════════════════════════
# Linux install — compile from source
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$OS" == "Linux" ]]; then
  LINUX_INSTALL_DIR="/usr/local/bin"
  DESKTOP_DIR="/usr/share/applications"

  info "DexBar Linux — building from source"

  # ── check for Swift ──────────────────────────────────────────────────────────
  command -v swift >/dev/null 2>&1 || die "Swift not found. Install Swift 6.0+ from https://swift.org/download"
  SWIFT_VERSION=$(swift --version 2>&1 | head -1)
  info "Swift: $SWIFT_VERSION"

  # ── check / install system dependencies ─────────────────────────────────────
  MISSING_DEPS=()
  pkg-config --exists gtk+-3.0           2>/dev/null || MISSING_DEPS+=("libgtk-3-dev")
  pkg-config --exists ayatana-appindicator3-0.1 2>/dev/null \
    || pkg-config --exists appindicator3-0.1 2>/dev/null \
    || MISSING_DEPS+=("libayatana-appindicator3-dev")
  pkg-config --exists libsecret-1        2>/dev/null || MISSING_DEPS+=("libsecret-1-dev")
  pkg-config --exists libnotify          2>/dev/null || MISSING_DEPS+=("libnotify-dev")

  if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    warn "Missing system dependencies: ${MISSING_DEPS[*]}"
    info "Installing via apt…"
    sudo apt-get install -y "${MISSING_DEPS[@]}" \
      || die "apt install failed. Install manually:\n  sudo apt install ${MISSING_DEPS[*]}"
    success "Dependencies installed"
  else
    success "All system dependencies present"
  fi

  # ── build ────────────────────────────────────────────────────────────────────
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR"
  info "Building DexBarLinux (release) in: $SCRIPT_DIR"
  swift build -c release --product DexBarLinux \
    || die "Build failed. See output above."
  success "Build complete"

  # ── install binary ───────────────────────────────────────────────────────────
  BINARY="${SCRIPT_DIR}/.build/release/DexBarLinux"
  [[ -f "$BINARY" ]] \
    || die "Binary not found at: $BINARY\nCheck build output above for errors."
  info "Installing binary to ${LINUX_INSTALL_DIR}/dexbar…"
  if [[ -w "$LINUX_INSTALL_DIR" ]]; then
    cp "$BINARY" "${LINUX_INSTALL_DIR}/dexbar" \
      || die "Install failed."
  else
    sudo cp "$BINARY" "${LINUX_INSTALL_DIR}/dexbar" \
      || die "Install failed. Check permissions."
  fi
  success "Binary installed"

  # ── install .desktop file ────────────────────────────────────────────────────
  DESKTOP_FILE="${DESKTOP_DIR}/dexbar.desktop"
  DESKTOP_CONTENT="[Desktop Entry]
Type=Application
Name=DexBar
Comment=Dexcom glucose readings in your system tray
Exec=${LINUX_INSTALL_DIR}/dexbar
Icon=dialog-information
Categories=Utility;
StartupNotify=false"
  info "Installing .desktop file…"
  if [[ -w "$DESKTOP_DIR" ]]; then
    echo "$DESKTOP_CONTENT" > "$DESKTOP_FILE"
  else
    echo "$DESKTOP_CONTENT" | sudo tee "$DESKTOP_FILE" >/dev/null
  fi
  success ".desktop file installed"

  # ── done ─────────────────────────────────────────────────────────────────────
  success "DexBar installed to ${LINUX_INSTALL_DIR}/dexbar"
  echo ""
  echo -e "  Run now:      ${BOLD}dexbar &${RESET}"
  echo -e "  Enable autostart in DexBar Settings → Display → Launch at Login"
  echo ""
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# macOS install — download pre-built .app from GitHub Releases
# ══════════════════════════════════════════════════════════════════════════════

[[ "$OS" == "Darwin" ]] || die "Unsupported OS: $OS. Only macOS and Linux are supported."

SW_VERS=$(sw_vers -productVersion)
MAJOR=$(echo "$SW_VERS" | cut -d. -f1)
[[ "$MAJOR" -ge 14 ]] || die "DexBar requires macOS 14 (Sonoma) or later. You have $SW_VERS."

# ── fetch latest release ───────────────────────────────────────────────────────
info "Fetching latest release info…"
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
[[ -n "$VERSION" ]] || die "Could not determine latest version. Check your internet connection."

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ZIP_NAME}"

info "Installing ${APP_NAME} ${VERSION}…"

# ── download ───────────────────────────────────────────────────────────────────
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

info "Downloading ${ZIP_NAME}…"
curl -fL --progress-bar "$DOWNLOAD_URL" -o "${TMP_DIR}/${ZIP_NAME}" \
  || die "Download failed. Visit https://github.com/${REPO}/releases to download manually."

# ── install ────────────────────────────────────────────────────────────────────
info "Installing to ${INSTALL_DIR}…"
unzip -q "${TMP_DIR}/${ZIP_NAME}" -d "$TMP_DIR"

# Remove existing installation if present
if [[ -d "${INSTALL_DIR}/${APP_NAME}.app" ]]; then
  warn "Replacing existing ${APP_NAME}.app"
  rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
fi

mv "${TMP_DIR}/${APP_NAME}.app" "${INSTALL_DIR}/"

# ── done ───────────────────────────────────────────────────────────────────────
success "${APP_NAME} ${VERSION} installed to ${INSTALL_DIR}/${APP_NAME}.app"
echo ""
echo -e "  Launch with:  ${BOLD}open ${INSTALL_DIR}/${APP_NAME}.app${RESET}"
echo ""
info "Opening ${APP_NAME}…"
open "${INSTALL_DIR}/${APP_NAME}.app"
