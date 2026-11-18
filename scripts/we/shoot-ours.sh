#!/bin/bash
# Pictures of the same scenes as the app draws them, as Wallpaper Engine's are taken: the test
# machine's 1280 x 800 screen, 25 seconds in, the pointer in the middle.
#
#   scripts/we/shoot-ours.sh <plan.tsv> <library> <out folder> [app]
#
# The plan is shoot-we.sh's; the library is the test library its third column is in.
set -u
PLAN="$1"; LIBRARY="$2"; OUT="$3"
APP="${4:-build/WallAero Engine.app}"
BIN="$APP/Contents/MacOS/WallAeroTestHost"
mkdir -p "$OUT"
while IFS=$'\t' read -r name folder library how; do
    [ -n "$name" ] || continue
    [ -f "$OUT/$name.png" ] && continue
    perl -e 'alarm shift; exec @ARGV' 120 taskpolicy -c utility "$BIN" --native-test "$LIBRARY/$library" "$OUT/$name.png" \
        --after 25 --size 1280 800 --screen 1 --pointer-at 0 640 400 >/dev/null 2>&1 || echo "$name: not drawn"
done < "$PLAN"
