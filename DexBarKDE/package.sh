#!/usr/bin/env bash
# Packages the DexBar Plasma widget as a .plasmoid file (standard zip archive).
# Usage: cd DexBarKDE && ./package.sh
set -euo pipefail

WIDGET_ID="org.kde.plasma.dexbar"
OUTPUT="${WIDGET_ID}.plasmoid"

cd "$(dirname "$0")"
rm -f "${OUTPUT}"

if command -v zip &>/dev/null; then
  (cd plasmoid && zip -r "../${OUTPUT}" . --exclude '*.DS_Store' --exclude '*/__pycache__/*')
else
  python3 -c "
import zipfile, os
with zipfile.ZipFile('${OUTPUT}', 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk('plasmoid'):
        for f in files:
            if f == '.DS_Store' or '__pycache__' in root:
                continue
            full = os.path.join(root, f)
            arc = os.path.relpath(full, 'plasmoid')
            zf.write(full, arc)
"
fi

echo "Created: ${OUTPUT}"
echo "Install: kpackagetool6 --install ${OUTPUT} --type Plasma/Applet"
