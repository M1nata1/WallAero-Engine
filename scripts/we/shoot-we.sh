#!/bin/bash
# Pictures of scenes as Wallpaper Engine draws them, in the Windows test machine.
#
#   scripts/we/shoot-we.sh <plan.tsv> <out folder> [name regex]
#
# The plan has a line a scene: <name>\t<folder in C:\WS>\t<library folder>\t<how>. Each scene is
# opened with WE's command line on the plain magenta desktop, and pictured once it covers the
# desktop and has played 15 seconds more, with the pointer in the middle of the screen. A scene
# pictured already is left alone: WE does not change, so its pictures are taken once.
#
# The machine must be running with WE started (`win.sh run`). It is slow there: WE runs under
# x64 emulation with Direct3D in software, a scene takes one to four minutes to load.
set -u
PLAN="$1"; OUT="$2"; ONLY="${3:-.}"
VD="${WALLAERO_VM_FOLDER:-$HOME/Documents/Virtual Desktop}"
WIN="$VD/win.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
WE='C:\WallpaperEngine\wallpaper64.exe'
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
SHOT="$(mktemp -d)/screen.png"

screen() { "$WIN" shot "$SHOT" >/dev/null && python3 "$HERE/we.py" screen "$SHOT"; }
magenta() { screen | awk '/magenta/ { print $2 }'; }

while IFS=$'\t' read -r name folder library how; do
    [ -n "$name" ] || continue
    echo "$name" | grep -Eq -- "$ONLY" || continue
    [ -f "$OUT/$name.png" ] && continue
    "$WIN" gui "$WE -control closeWallpaper -monitor 0" >/dev/null
    for _ in $(seq 1 20); do [ "$(magenta)" -ge 12 ] 2>/dev/null && break; sleep 3; done
    python3 -I "$VD/vnc.py" vnc://127.0.0.1:5901 move 640 400 >/dev/null 2>&1
    "$WIN" gui "$WE -control openWallpaper -file C:\\WS\\$folder\\project.json" >/dev/null
    started=$(date +%s); loaded=0
    while [ $(( $(date +%s) - started )) -lt 240 ]; do
        sleep 5
        said="$(screen)"
        if echo "$said" | grep -q window; then
            # WE's own window, opened as it started again: Cancel.
            "$WIN" click 1082 717 >/dev/null; continue
        fi
        if echo "$said" | grep -q dialog; then
            # WE fell over and restarted behind its Safe Start dialog: OK, and wait on.
            "$WIN" click 763 276 >/dev/null; continue
        fi
        if [ "$(echo "$said" | awk '/magenta/ { print $2 }')" -le 4 ]; then loaded=1; break; fi
    done
    if [ "$loaded" -eq 0 ]; then echo "$name: not drawn by WE in 4 minutes"; continue; fi
    sleep 15
    if screen | grep -q window; then "$WIN" click 1082 717 >/dev/null; sleep 10; fi
    "$WIN" shot "$OUT/$name.png" >/dev/null
    if screen | grep -Eq 'window|dialog'; then rm -f "$OUT/$name.png"; echo "$name: covered by WE's window"; continue; fi
    echo "$name: $(( $(date +%s) - started )) s"
done < "$PLAN"
