#!/usr/bin/env bash
# Installs Flutter and builds the web bundle inside Netlify CI.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.32.4}"
FLUTTER_DIR="$HOME/flutter"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Cloning Flutter $FLUTTER_VERSION…"
  git clone https://github.com/flutter/flutter.git \
    --branch "$FLUTTER_VERSION" --depth 1 "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version
flutter config --no-analytics --no-cli-animations
flutter pub get
flutter build web --release
