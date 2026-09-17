#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Install Xcode Command Line Tools first: xcode-select --install'
  exit 1
fi
bash build.sh
open "${TAPWALL_APP_PATH:-$HOME/Applications/TapWall.app}"
