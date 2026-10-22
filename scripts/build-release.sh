#!/usr/bin/env bash
# Build the Fidelia Admin release: one signed universal APK and the Play bundle.
#
# Usage: scripts/build-release.sh <https api base> [extra flutter build args]
#   e.g. scripts/build-release.sh https://api.example.com --build-name=0.1.0 --build-number=7
#
# Dart obfuscation is on and the symbol maps are kept in build/symbols/ so a
# crash report can still be read. Archive that directory with the release.
set -euo pipefail

API_BASE="${1:-}"
if [ -z "$API_BASE" ]; then
  echo "usage: $0 <https api base url> [extra flutter build args]" >&2
  exit 2
fi
shift
case "$API_BASE" in
  https://*) ;;
  *) echo "error: API base must be https, got: $API_BASE" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."

if [ ! -f android/key.properties ]; then
  echo "warning: android/key.properties is missing; the build will be UNSIGNED." >&2
  echo "         See android/key.properties.example. Do not distribute unsigned builds." >&2
fi

# CI passes --build-name/--build-number, which override pubspec.yaml.
APP_VERSION="$(sed -n 's/^version: *//p' pubspec.yaml)"
BUILD_NAME="${APP_VERSION%%+*}"
BUILD_NUMBER="${APP_VERSION#*+}"
for arg in "$@"; do
  case "$arg" in
    --build-name=*) BUILD_NAME="${arg#*=}" ;;
    --build-number=*) BUILD_NUMBER="${arg#*=}" ;;
  esac
done
APP_VERSION="$BUILD_NAME+$BUILD_NUMBER"

flutter build apk --release \
  --obfuscate --split-debug-info="build/symbols/$APP_VERSION" \
  --dart-define=FIDELIA_API_BASE="$API_BASE" \
  --dart-define=FIDELIA_APP_VERSION="$APP_VERSION" \
  "$@"

# The same build as an app bundle, the format Google Play takes. Its own
# symbol map: an obfuscated build is only readable with the map it produced.
flutter build appbundle --release \
  --obfuscate --split-debug-info="build/symbols/$APP_VERSION/play" \
  --dart-define=FIDELIA_API_BASE="$API_BASE" \
  --dart-define=FIDELIA_APP_VERSION="$APP_VERSION" \
  "$@"

echo
echo "Artifacts:"
ls -la build/app/outputs/flutter-apk/app-release.apk
ls -la build/app/outputs/bundle/release/app-release.aab
echo
echo "Symbol maps (archive these, do not ship them): build/symbols/$APP_VERSION/"
