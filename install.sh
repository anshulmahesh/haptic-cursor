#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Menu Magnet Haptic Profiles.app"
EXEC="MenuMagnetHapticProfiles"
BUNDLE_ID="com.menumagnet.hapticprofiles.v2"
DEST_ROOT="$HOME/Applications"
DEST="$DEST_ROOT/$APP_NAME"
WORK="$(mktemp -d "${TMPDIR:-/tmp/}mm-haptic-profiles.XXXXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'ERROR: This installer requires macOS.' >&2; exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'ERROR: Apple Command Line Tools are required. Run: xcode-select --install' >&2; exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD="$WORK/$APP_NAME"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"
cp "$ROOT/Info.plist" "$BUILD/Contents/Info.plist"

printf '\n[1/7] Compile new app BEFORE changing current installation…\n'
xcrun swiftc -O -swift-version 5 -parse-as-library \
  -sdk "$SDK" -module-name MenuMagnetHapticProfiles \
  "$ROOT/Sources/App.swift" \
  "$ROOT/Sources/Window.swift" \
  "$ROOT/Sources/HapticEngine.swift" \
  "$ROOT/Sources/AXScanner.swift" \
  "$ROOT/Sources/Profiles.swift" \
  "$ROOT/Sources/EntryLogic.swift" \
  "$ROOT/Sources/EnhancedHapticBridge.swift" \
  -framework Cocoa -framework SwiftUI -framework ApplicationServices -framework QuartzCore \
  -o "$BUILD/Contents/MacOS/$EXEC"
chmod +x "$BUILD/Contents/MacOS/$EXEC"
# Private actuator helper is a separate process so any private ABI crash remains isolated.
xcrun clang -O2 -Wall -Wextra -std=c11 \
  "$ROOT/Sources/ActuatorHelper.c" -framework CoreFoundation \
  -o "$BUILD/Contents/Resources/MenuMagnetActuator"
chmod +x "$BUILD/Contents/Resources/MenuMagnetActuator"
# Produce a real macOS .icns from the supplied multi-resolution iconset.
/usr/bin/iconutil -c icns "$ROOT/Assets/AppIcon.iconset" -o "$BUILD/Contents/Resources/AppIcon.icns"
test -s "$BUILD/Contents/Resources/AppIcon.icns"

printf '\n[2/7] Sign and verify the new app…\n'
/usr/bin/codesign --force --sign - --timestamp=none "$BUILD/Contents/Resources/MenuMagnetActuator"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$BUILD"
/usr/bin/codesign --verify --strict "$BUILD"
/usr/bin/codesign --verify --strict "$BUILD/Contents/Resources/MenuMagnetActuator"
/usr/bin/plutil -lint "$BUILD/Contents/Info.plist"
test -x "$BUILD/Contents/MacOS/$EXEC"

printf '\n[3/7] Quit known prior Menu Magnet processes…\n'
for proc in MenuMagnetNative MenuMagnetBoundaryLab MenuMagnetHapticTester MenuMagnetHapticProfiler MenuMagnetHapticProfiles; do
  /usr/bin/pkill -x "$proc" >/dev/null 2>&1 || true
done
sleep 0.4

# Bundle identifiers of releases authored for this project.
# Do not reset the current com.menumagnet.hapticprofiles.v2 identity on updates.
old_ids=(
  'com.menumagnet.native'
  'com.menumagnet.boundarylab'
  'com.menumagnet.haptictester.v1'
)

printf '\n[4/7] Reset only OLD app permission decisions…\n'
WARNINGS=0
for id in "${old_ids[@]}"; do
  for service in Accessibility ListenEvent; do
    # Targeted tccutil reset, never global. Some macOS versions refuse to reset
    # unregistered / already deleted apps; the installer must report this.
    if output="$(/usr/bin/tccutil reset "$service" "$id" 2>&1)"; then
      echo "Reset requested: $service / $id"
    else
      echo "NOTICE: macOS did not reset $service / $id: $output"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
done

printf '\n[5/7] Uninstall known prior app bundles from standard Applications folders…\n'
mkdir -p "$DEST_ROOT"
known_ids=("${old_ids[@]}" "$BUNDLE_ID")
known_names=(
  'Menu Magnet Native.app' 'MenuMagnetNative.app'
  'Menu Magnet Boundary Lab.app' 'MenuMagnetBoundaryLab.app'
  'Menu Magnet Haptic Tester.app' 'MenuMagnetHapticTester.app'
  'Menu Magnet Haptic Profiler.app' 'MenuMagnetHapticProfiler.app'
  'Menu Magnet Haptic Profiles.app' 'MenuMagnetHapticProfiles.app'
)
for directory in "$HOME/Applications" /Applications; do
  for name in "${known_names[@]}"; do
    target="$directory/$name"
    [[ -d "$target" ]] || continue
    actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)"
    recognized=false
    for id in "${known_ids[@]}"; do
      if [[ "$actual_id" == "$id" ]]; then recognized=true; break; fi
    done
    if [[ "$recognized" != true ]]; then
      echo "NOTICE: Skipped unrecognized bundle: $target (ID: $actual_id)"
      WARNINGS=$((WARNINGS + 1))
      continue
    fi
    if [[ -w "$directory" && -w "$target" ]]; then
      /bin/rm -rf -- "$target"
    elif [[ "$directory" == /Applications ]]; then
      echo "Administrator approval required to remove $target"
      /usr/bin/sudo /bin/rm -rf -- "$target"
    else
      echo "ERROR: Cannot remove previous installation: $target" >&2
      exit 1
    fi
    [[ ! -e "$target" ]] || { echo "ERROR: Previous installation still exists: $target" >&2; exit 1; }
    echo "Uninstalled: $target"
  done
done

printf '\n[6/7] Install and verify replacement in ~/Applications…\n'
/usr/bin/ditto "$BUILD" "$DEST"
/usr/bin/codesign --verify --strict "$DEST"
test -x "$DEST/Contents/MacOS/$EXEC"
installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")"
[[ "$installed_id" == "$BUNDLE_ID" ]] || { echo "ERROR: Wrong installed bundle identity" >&2; exit 1; }

printf '\n[7/7] Launch replacement…\n'
/usr/bin/open "$DEST"
FOUND=false
for _ in 1 2 3 4 5 6; do
  if /usr/bin/pgrep -f "Contents/MacOS/$EXEC" >/dev/null 2>&1; then FOUND=true; break; fi
  sleep 1
done
if [[ "$FOUND" != true ]]; then
  echo "WARNING: App installed and verified but process launch not confirmed: $DEST" >&2
  exit 1
fi

# A process may briefly appear and then crash (as v3.0 did ~1.35s after launch).
# Keep the ZIP on the user's Mac unless the replacement survives initial startup.
echo 'Checking that the replacement remains running after startup…'
sleep 4
if ! /usr/bin/pgrep -f "Contents/MacOS/$EXEC" >/dev/null 2>&1; then
  echo 'ERROR: The new app terminated during the startup smoke check.' >&2
  echo 'The installer reports failure; leave the downloaded ZIP in place for diagnostics.' >&2
  exit 1
fi

echo "SUCCESS: Installed Menu Magnet Haptic Profiles v3.0.1"
echo "Location: $DEST"
echo "Accessibility identity: $BUNDLE_ID (preserved on version updates)"
if [[ "$WARNINGS" -gt 0 ]]; then
  echo "NOTICE: $WARNINGS permission reset/removal warning(s). Old entries may remain in System Settings."
  echo "To remove a stale row manually: System Settings > Privacy & Security > Accessibility or Input Monitoring, select old app entry, then remove it with minus (-), if available."
else
  echo 'Targeted old-app permission resets completed. macOS may still display cached rows; check System Settings if needed.'
fi
