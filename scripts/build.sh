#!/bin/bash
# Builds "build/WallAero Engine.app" from the Swift package.
#
#   scripts/build.sh            universal app: Apple Silicon and Intel
#   scripts/build.sh --native   only for this Mac's processor; twice as fast, for development
#   scripts/build.sh --install  also copy the app to /Applications
#   scripts/build.sh --dist     also pack the app into dist/WallAeroEngine.zip, for a release on GitHub
#
# Chromium, which draws the web wallpapers, and the video encoders come from scripts/cef.sh and
# scripts/codecs.sh, run from here; they download what they need once.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="WallAero Engine"   # the bundle, as shown in Finder
EXECUTABLE="WallAeroEngine"  # the Swift product inside it; also names the archive
APP="build/$APP_NAME.app"
INSTALL=0
DIST=0
NATIVE=0
ARCH_FLAGS=(--arch arm64 --arch x86_64)

for argument in "$@"; do
    case "$argument" in
        --install) INSTALL=1 ;;
        --dist) DIST=1 ;;
        --native) NATIVE=1; ARCH_FLAGS=() ;;
        *) echo "Unknown option: $argument" >&2; exit 1 ;;
    esac
done

if [ "$DIST" -eq 1 ] && [ "$NATIVE" -eq 1 ]; then
    echo "--dist packs the universal app for every Mac; drop --native" >&2
    exit 1
fi

# CEF's C++ code names its own source files in its messages; they are named from the package,
# so that the app carries no path of the Mac it was built on.
PREFIX_MAP="-fmacro-prefix-map=$PWD/="
ARCH_FLAGS+=(-Xcc "$PREFIX_MAP" -Xcxx "$PREFIX_MAP")

echo "→ Compiling…"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

NATIVE_FLAG=()
if [ "$NATIVE" -eq 1 ]; then NATIVE_FLAG=(--native); fi
scripts/cef.sh ${NATIVE_FLAG[@]+"${NATIVE_FLAG[@]}"} "$BIN_DIR/WallAeroHelper"
scripts/codecs.sh ${NATIVE_FLAG[@]+"${NATIVE_FLAG[@]}"}

if [ ! -f Resources/AppIcon.icns ]; then
    echo "→ Drawing the icon…"
    swift scripts/make-icon.swift Resources/AppIcon.icns
fi

# Braces around the name: in a terminal with a UTF-8 locale the bash that comes with macOS takes
# the first byte of a character like "…" right after a name for a part of the name.
echo "→ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Frameworks"
cp -R build/cef/. "$APP/Contents/Frameworks/"
cp build/codecs/libWallAeroCodecs.dylib "$APP/Contents/Frameworks/"
# The licenses of what the app is made with besides its own code.
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSES"
cp build/licenses/* "$LICENSES/"
cp Sources/CCodecs/vpx/LICENSE "$LICENSES/libvpx LICENSE.txt"
cp Sources/CCodecs/vpx/PATENTS "$LICENSES/libvpx PATENTS.txt"
cp Sources/CCodecs/opus/COPYING "$LICENSES/Opus COPYING.txt"

# macOS goes by the SDK version stamped into the app: on macOS 26 an app stamped with an earlier
# SDK is drawn in the look of the earlier systems, whatever its code says. Some tools do not
# stamp the SDK they built with and leave the oldest macOS the app runs on in its place (seen
# with Swift 6.4 and the macOS 27 SDK: "sdk 13.0"). The app was built against the SDK the tools
# report, so that one is stamped in.
BINARY="$APP/Contents/MacOS/$EXECUTABLE"
stamp() { xcrun vtool -show-build "$BINARY" 2>/dev/null | awk -v key="$1" '$1 == key { print $2; exit }'; }
STAMPED_SDK="$(stamp sdk)"
OLDEST_OS="$(stamp minos)"
BUILT_WITH_SDK="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
if [ -n "$BUILT_WITH_SDK" ] && [ -n "$STAMPED_SDK" ] && [ "$STAMPED_SDK" = "$OLDEST_OS" ] && [ "$STAMPED_SDK" != "$BUILT_WITH_SDK" ]; then
    echo "→ Stamping the macOS $BUILT_WITH_SDK SDK (the tools left $STAMPED_SDK there)…"
    # The tool warns that the signature is no longer good; the app is signed right below.
    xcrun vtool -set-build-version macos "$OLDEST_OS" "$BUILT_WITH_SDK" -replace -output "$BINARY.stamped" "$BINARY" \
        2> >(grep -v "code signature will be invalid" >&2)
    mv "$BINARY.stamped" "$BINARY"
    chmod +x "$BINARY"
fi

echo "→ Signing (ad hoc)…"
sign() { codesign --force --sign - --timestamp=none "$1"; }
# From the inside out: each part is signed before what holds it.
FRAMEWORKS="$APP/Contents/Frameworks"
while IFS= read -r -d '' library; do sign "$library"; done \
    < <(find "$FRAMEWORKS/Chromium Embedded Framework.framework/Libraries" -name "*.dylib" -print0)
sign "$FRAMEWORKS/Chromium Embedded Framework.framework"
sign "$FRAMEWORKS/libWallAeroCodecs.dylib"
for helper in "$FRAMEWORKS/"*Helper*.app; do sign "$helper"; done
sign "$APP"

if [ "$DIST" -eq 1 ]; then
    echo "→ Packing dist/$EXECUTABLE.zip…"
    mkdir -p dist
    rm -f "dist/$EXECUTABLE.zip"
    # The signature lives in the bundle's files, so this Mac's extended attributes (provenance)
    # are left out; they would only add a __MACOSX folder to the archive.
    ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "dist/$EXECUTABLE.zip"
fi

if [ "$INSTALL" -eq 1 ]; then
    echo "→ Installing to /Applications…"
    if pgrep -x "$EXECUTABLE" >/dev/null; then
        osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || pkill -x "$EXECUTABLE" || true
        sleep 1
    fi
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    APP="/Applications/$APP_NAME.app"
fi

echo "✓ $APP"

# What macOS will go by, said aloud, so that nobody has to wonder why the same sources look
# different on two Macs.
STAMPED_SDK="$(xcrun vtool -show-build "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null | awk '$1 == "sdk" { print $2; exit }')"
if [ -n "$STAMPED_SDK" ]; then
    echo "  built with the macOS $STAMPED_SDK SDK"
    if [ "${STAMPED_SDK%%.*}" -lt 26 ]; then
        echo "! On macOS 26 this app will look as on earlier systems: the new look needs the macOS 26 SDK."
        echo "  Install Xcode 26 or later (or its Command Line Tools) and build again."
    fi
fi
