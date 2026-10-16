#!/bin/bash
# Builds build/codecs/libWallAeroCodecs.dylib: the VP9 encoder of libvpx and the Opus encoder of
# libopus, for Apple Silicon and Intel. With them the app turns the videos of web wallpapers into
# WebM, which Chromium plays (it has no H.264).
#
#   scripts/codecs.sh            both processors
#   scripts/codecs.sh --native   only this Mac's, for development
#
# The sources are downloaded once and kept in ~/Library/Caches with what was built of them.
set -euo pipefail
cd "$(dirname "$0")/.."

VPX_VERSION="1.15.2"
VPX_SHA256="26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa"
OPUS_VERSION="1.5.2"
OPUS_SHA256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
MIN_MACOS="13.0"
OUT="build/codecs"
CACHE="$HOME/Library/Caches/WallAeroEngine-build/codecs"
JOBS="$(sysctl -n hw.ncpu)"

ARCHS=(arm64 x86_64)
if [ "${1:-}" = "--native" ]; then
    ARCHS=("$(uname -m)")
fi

# fetch <file> <url> <sha256>
fetch() {
    if [ ! -f "$1" ] || [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" != "$3" ]; then
        echo "→ Downloading $(basename "$1")…"
        curl -fsSL --retry 3 -o "$1" "$2"
        if [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" != "$3" ]; then
            echo "$(basename "$1") is not the one expected" >&2
            rm -f "$1"
            exit 1
        fi
    fi
}

mkdir -p "$CACHE"
fetch "$CACHE/libvpx-$VPX_VERSION.tar.gz" "https://github.com/webmproject/libvpx/archive/refs/tags/v$VPX_VERSION.tar.gz" "$VPX_SHA256"
fetch "$CACHE/opus-$OPUS_VERSION.tar.gz" "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" "$OPUS_SHA256"

# build_vpx <arch>: libvpx.a with the VP9 encoder only.
build_vpx() {
    local arch="$1" work="$CACHE/build-$arch/libvpx-$VPX_VERSION"
    [ -f "$work/libvpx.a" ] && return
    echo "→ Building the VP9 encoder for ${arch}…"
    rm -rf "$work"
    mkdir -p "$(dirname "$work")"
    tar -xzf "$CACHE/libvpx-$VPX_VERSION.tar.gz" -C "$(dirname "$work")"
    local target
    # Intel's version of the encoder's fast paths is written for an assembler macOS does not
    # come with; plain C does the same work, more slowly.
    if [ "$arch" = arm64 ]; then target=arm64-darwin22-gcc; else target=generic-gnu; fi
    (
        cd "$work"
        CC="clang -arch $arch -mmacosx-version-min=$MIN_MACOS" CXX="clang++ -arch $arch -mmacosx-version-min=$MIN_MACOS" \
        LD="clang -arch $arch" AR=ar \
        ./configure --target="$target" --disable-vp8 --disable-vp9-decoder --enable-vp9-encoder \
            --disable-examples --disable-tools --disable-docs --disable-unit-tests --disable-install-docs \
            --enable-pic --enable-runtime-cpu-detect --enable-multithread --disable-debug --as=auto >/dev/null
        make -j"$JOBS" >/dev/null 2>&1 || make
    )
}

# build_opus <arch>: libopus.a.
build_opus() {
    local arch="$1" work="$CACHE/build-$arch/opus-$OPUS_VERSION"
    [ -f "$work/libopus.a" ] && return
    echo "→ Building the Opus encoder for ${arch}…"
    rm -rf "$work"
    mkdir -p "$(dirname "$work")"
    tar -xzf "$CACHE/opus-$OPUS_VERSION.tar.gz" -C "$(dirname "$work")"
    (
        cd "$work"
        make -f Makefile.unix -j"$JOBS" libopus.a \
            CC="clang -arch $arch -mmacosx-version-min=$MIN_MACOS -fPIC -O2" >/dev/null
    )
}

rm -rf "$OUT"
mkdir -p "$OUT"
LIBS=()
for arch in "${ARCHS[@]}"; do
    build_vpx "$arch"
    build_opus "$arch"
    echo "→ Linking the codecs for ${arch}…"
    lib="$CACHE/build-$arch/libWallAeroCodecs.dylib"
    clang -arch "$arch" -mmacosx-version-min="$MIN_MACOS" -dynamiclib -o "$lib" \
        -install_name "@rpath/libWallAeroCodecs.dylib" \
        -Wl,-force_load,"$CACHE/build-$arch/libvpx-$VPX_VERSION/libvpx.a" \
        -Wl,-force_load,"$CACHE/build-$arch/opus-$OPUS_VERSION/libopus.a" -lc++
    LIBS+=("$lib")
done
lipo -create "${LIBS[@]}" -output "$OUT/libWallAeroCodecs.dylib"
echo "✓ $OUT/libWallAeroCodecs.dylib ($(lipo -archs "$OUT/libWallAeroCodecs.dylib"))"
