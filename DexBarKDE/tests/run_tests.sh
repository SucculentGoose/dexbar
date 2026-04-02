#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
qmltestrunner -input tst_dexcom.qml
