#!/bin/bash
# Prepares Chromium (Chromium Embedded Framework) for the app in build/cef:
#
#   build/cef/Chromium Embedded Framework.framework   for Apple Silicon and Intel in one
#   build/cef/WallAero Engine Helper.app               the helper Chromium starts its processes with
#   build/licenses                                     CEF's license and the credits of Chromium's parts
#
# The same folder becomes the app's Contents/Frameworks (scripts/build.sh), and a binary started
# from .build (swift run, the helper modes) finds Chromium there too.
#
#   scripts/cef.sh <helper binary>             both processors
#   scripts/cef.sh --native <helper binary>    only this Mac's, for development
#
# The framework is downloaded once from CEF's own builds and kept in ~/Library/Caches.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="154.0.34+g14c5a08+chromium-154.0.8037.98"
# The archives' SHA-1, as CEF publishes them.
SHA1_arm64="b7081f6609e5edccf07be96b5d7977329fbe1bdf"
SHA1_x86_64="51d90349e24360b8e0daecc2d026ad150c620db5"
PLATFORM_arm64="macosarm64"
PLATFORM_x86_64="macosx64"

APP_NAME="WallAero Engine"
BUNDLE_ID="com.fadevec.WallAeroEngine"
FRAMEWORK="Chromium Embedded Framework.framework"
OUT="build/cef"
CACHE="$HOME/Library/Caches/WallAeroEngine-build/cef/$VERSION"

ARCHS=(arm64 x86_64)
if [ "${1:-}" = "--native" ]; then
    ARCHS=("$(uname -m)")
    shift
fi
HELPER_BINARY="${1:?the helper binary (WallAeroHelper) to put into the helper apps}"

# Downloads and unpacks one processor's framework; prints where it is.
fetch() {
    local arch="$1"
    local platform_var="PLATFORM_$arch" sha_var="SHA1_$arch"
    local platform="${!platform_var}" sha="${!sha_var}"
    local name="cef_binary_${VERSION}_${platform}_minimal"
    local archive="$CACHE/$name.tar.bz2"
    mkdir -p "$CACHE"
    if [ ! -d "$CACHE/$name" ]; then
        if [ ! -f "$archive" ] || [ "$(shasum -a 1 "$archive" | cut -d' ' -f1)" != "$sha" ]; then
            echo "→ Downloading Chromium for ${arch}…" >&2
            local url="https://cef-builds.spotifycdn.com/${name//+/%2B}.tar.bz2"
            # CEF's servers break off long downloads now and then; carry on where they stopped.
            for _ in $(seq 1 30); do
                curl -fsSL -C - --retry 3 -o "$archive" "$url" && break || sleep 2
            done
            if [ "$(shasum -a 1 "$archive" | cut -d' ' -f1)" != "$sha" ]; then
                echo "The Chromium download for $arch is not the one expected" >&2
                rm -f "$archive"
                exit 1
            fi
        fi
        echo "→ Unpacking Chromium for ${arch}…" >&2
        tar -xjf "$archive" -C "$CACHE" "$name/Release" "$name/CREDITS.html" "$name/LICENSE.txt"
    fi
    echo "$CACHE/$name/Release/$FRAMEWORK"
}

FIRST="$(fetch "${ARCHS[0]}")"
rm -rf "$OUT"
mkdir -p "$OUT"
# The licenses of CEF and of every part of Chromium, which go into the app with it.
mkdir -p build/licenses
cp "$(dirname "$(dirname "$FIRST")")/LICENSE.txt" "build/licenses/CEF LICENSE.txt"
cp "$(dirname "$(dirname "$FIRST")")/CREDITS.html" "build/licenses/Chromium CREDITS.html"
echo "→ Putting Chromium together…"
cp -R "$FIRST" "$OUT/"
# Only the languages the app has: Chromium's own words never show on a wallpaper.
find "$OUT/$FRAMEWORK/Resources" -maxdepth 1 -name "*.lproj" ! -name "en.lproj" ! -name "ru.lproj" -exec rm -rf {} +

for arch in "${ARCHS[@]:1}"; do
    OTHER="$(fetch "$arch")"
    # Each program of the framework holds both processors' code.
    while IFS= read -r -d '' file; do
        relative="${file#"$OUT/$FRAMEWORK/"}"
        if file -b "$file" | grep -q "Mach-O"; then
            lipo -create "$file" "$OTHER/$relative" -output "$file.universal"
            mv "$file.universal" "$file"
        fi
    done < <(find "$OUT/$FRAMEWORK" -type f -print0)
    # The parts of the framework only one processor has (its JavaScript engine's start-up picture).
    for extra in "$OTHER/Resources/"*.bin; do
        [ -e "$OUT/$FRAMEWORK/Resources/$(basename "$extra")" ] || cp "$extra" "$OUT/$FRAMEWORK/Resources/"
    done
done

echo "→ Making the helper app…"
# Chromium starts its processes of every kind (pages, graphics, sound, the network) from it.
for kind in ""; do
    name="$APP_NAME Helper$kind"
    suffix="$(echo "$kind" | tr -d ' ()' | tr '[:upper:]' '[:lower:]')"
    identifier="$BUNDLE_ID.helper${suffix:+.$suffix}"
    helper="$OUT/$name.app"
    mkdir -p "$helper/Contents/MacOS"
    cp "$HELPER_BINARY" "$helper/Contents/MacOS/$name"
    cat > "$helper/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>$name</string>
	<key>CFBundleExecutable</key>
	<string>$name</string>
	<key>CFBundleIdentifier</key>
	<string>$identifier</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSFileQuarantineEnabled</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<string>1</string>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST
done

echo "✓ $OUT"
