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

# ── checks ─────────────────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || die "DexBar requires macOS."

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
