#!/usr/bin/env bash
# Packages the DexBar Plasma widget as a .plasmoid file (standard zip archive).
# Usage: cd DexBarKDE && ./package.sh
set -euo pipefail

WIDGET_ID="org.kde.plasma.dexbar"
OUTPUT="${WIDGET_ID}.plasmoid"

cd "$(dirname "$0")/plasmoid"
zip -r "../${OUTPUT}" . --exclude '*.DS_Store' --exclude '*/__pycache__/*'
cd ..

echo "Created: ${OUTPUT}"
echo "Install: kpackagetool6 --install ${OUTPUT} --type Plasma/Applet"
