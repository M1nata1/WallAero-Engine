#!/bin/bash
# Pictures of every scene of the corpus and the Workshop set at set moments, by both engines,
# compared pixel by pixel with the baseline; an HTML report of what differs.
#
#   scripts/compare.sh --baseline        take the baseline (notes/baseline/shots)
#   scripts/compare.sh [--name <run>]    take a run (notes/runs/<run>) and compare it
#
# Options:
#   --engines native,chromium   which engines (both by default)
#   --only <regex>              only scenes whose name matches (grep -E)
#   --library <folder>          the test library (notes/baseline/library by default)
#   --import                    build the test library anew from the corpus and the Workshop
#   --moments 0,1.5,5,12        the moments, in seconds, of the scene's own time
#   --timing <seconds>          how long to play for frame times and watts (4; 0 for none)
#   --size <w> <h>              the window, in points (640 360)
#   --screen <n>                the screen the windows open on (1, the external one)
#   --tolerance <n>             how far a channel may be off and still count as the same (3)
#   --app <path>                the app to run (build/WallAero Engine.app)
#   --against <folder>          compare with these shots instead of the baseline's
#   --fps <n>                   the scenes' frame rate while they play (30)
#   --full-speed                run the scenes at the Mac's normal priority; by default they run
#                               with the utility QoS clamp, so that the wallpaper on the desktop
#                               keeps its frames while a run goes on
#
# The scenes are played with the editor's clock (`--freeze`): chance and the date are the same
# each run, so two runs of one commit come out the same. What cannot (videos, sound) is listed
# with its reason in scripts/compare-exclusions.txt and kept apart in the report.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CORPUS="${HOME}/Documents/Personalization/Engine"
WORKSHOP="${HOME}/Documents/Personalization/Workshop/steamapps/workshop/content/431960"
APP="${ROOT}/build/WallAero Engine.app"
LIBRARY="${ROOT}/notes/baseline/library"
AGAINST="${ROOT}/notes/baseline/shots"
ENGINES="native,chromium"
ONLY=""
IMPORT=0
BASELINE=0
NAME=""
MOMENTS="0,1.5,5,12"
TIMING=4
WIDTH=640
HEIGHT=360
SCREEN=1
TOLERANCE=3
LONGEST=240   # seconds one scene may take before it is given up
FPS=30
POLITE=1

while [ $# -gt 0 ]; do
    case "$1" in
        --baseline) BASELINE=1 ;;
        --name) NAME="$2"; shift ;;
        --engines) ENGINES="$2"; shift ;;
        --only) ONLY="$2"; shift ;;
        --library) LIBRARY="$2"; shift ;;
        --import) IMPORT=1 ;;
        --moments) MOMENTS="$2"; shift ;;
        --timing) TIMING="$2"; shift ;;
        --size) WIDTH="$2"; HEIGHT="$3"; shift 2 ;;
        --screen) SCREEN="$2"; shift ;;
        --tolerance) TOLERANCE="$2"; shift ;;
        --app) APP="$2"; shift ;;
        --against) AGAINST="$2"; shift ;;
        --fps) FPS="$2"; shift ;;
        --full-speed) POLITE=0 ;;
        -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

BIN="${APP}/Contents/MacOS/WallAeroTestHost"
# Apps built before the test host (v3.8) took the tests themselves.
[ -x "${BIN}" ] || BIN="${APP}/Contents/MacOS/WallAeroEngine"
[ -x "${BIN}" ] || { echo "no app at ${APP}: run scripts/build.sh --native first" >&2; exit 1; }

# The Mac must keep 20 GB free; a run writes a few hundred megabytes, a library several gigabytes.
free_gb() { df -g / | awk 'NR == 2 { print $4 }'; }
if [ "$(free_gb)" -lt 25 ]; then
    echo "only $(free_gb) GB free; at least 25 are needed to start" >&2
    exit 1
fi

# The pixel comparer, built once.
TOOLS="${ROOT}/build/tools"
mkdir -p "${TOOLS}"
if [ ! -x "${TOOLS}/imgdiff" ] || [ "${ROOT}/scripts/tools/imgdiff.swift" -nt "${TOOLS}/imgdiff" ]; then
    swiftc -O -o "${TOOLS}/imgdiff" "${ROOT}/scripts/tools/imgdiff.swift" || exit 1
fi

# --- The test library: each archive of the corpus and each Workshop scene, added as the app adds
# them. The manifest names each scene and says where it lies in the library.
MANIFEST="${LIBRARY}/manifest.tsv"
if [ "${IMPORT}" = 1 ] || [ ! -f "${MANIFEST}" ]; then
    echo "building the test library in ${LIBRARY}"
    rm -rf "${LIBRARY}.new"
    mkdir -p "${LIBRARY}.new"
    : > "${LIBRARY}.new/manifest.tsv"
    add() { # <name> <source>
        local folders
        folders=$(perl -e 'alarm shift; exec @ARGV' 600 "${BIN}" --import-test "${LIBRARY}.new" "$2" 2>&1 | sed -n 's/^  folder: //p')
        local index=0
        while IFS= read -r folder; do
            [ -n "${folder}" ] || continue
            [ -f "${folder}/engine/files.js" ] || continue   # a scene; pages and videos are not compared
            local name="$1"
            [ "${index}" -gt 0 ] && name="$1-${index}"
            printf '%s\t%s\n' "${name}" "${folder#${LIBRARY}.new/}" >> "${LIBRARY}.new/manifest.tsv"
            index=$((index + 1))
        done <<< "${folders}"
        echo "  $1: ${index} scene(s)"
    }
    for archive in "${CORPUS}"/*; do
        [ -f "${archive}" ] || continue
        stem="$(basename "${archive}")"
        stem="${stem%.*}"
        add "${stem%_VSTHEMES-ORG}" "${archive}"
    done
    for folder in "${WORKSHOP}"/*; do
        [ -d "${folder}" ] || continue
        add "ws-$(basename "${folder}")" "${folder}"
    done
    rm -rf "${LIBRARY}"
    mv "${LIBRARY}.new" "${LIBRARY}"
    echo "$(wc -l < "${MANIFEST}" | tr -d ' ') scenes in the test library"
fi

# --- Where this run goes.
COMMIT="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- Sources || echo '+')"
if [ "${BASELINE}" = 1 ]; then
    OUT="${AGAINST}"
    rm -rf "${OUT}"
else
    [ -n "${NAME}" ] || NAME="$(date +%Y%m%d-%H%M%S)-${COMMIT}"
    OUT="${ROOT}/notes/runs/${NAME}"
fi
mkdir -p "${OUT}"
printf 'commit\t%s\ndate\t%s\nmoments\t%s\nsize\t%sx%s\nfps\t%s\npolite\t%s\n' "${COMMIT}" "$(date)" "${MOMENTS}" "${WIDTH}" "${HEIGHT}" \
    "${FPS}" "${POLITE}" > "${OUT}/run.tsv"

# --- The pictures.
total=$(grep -cE "${ONLY:-.}" "${MANIFEST}" || true)
done_count=0
started=$(date +%s)
while IFS=$'\t' read -r name folder; do
    [ -n "${name}" ] || continue
    if [ -n "${ONLY}" ] && ! echo "${name}" | grep -qE "${ONLY}"; then continue; fi
    done_count=$((done_count + 1))
    for engine in ${ENGINES//,/ }; do
        dir="${OUT}/${engine}/${name}"
        mkdir -p "${dir}"
        case "${engine}" in
            native) mode=--native-test ;;
            chromium) mode=--engine-test ;;
            *) echo "unknown engine ${engine}" >&2; exit 2 ;;
        esac
        polite=""
        [ "${POLITE}" = 1 ] && polite="taskpolicy -c utility"
        ${polite} perl -e 'alarm shift; exec @ARGV' "${LONGEST}" "${BIN}" "${mode}" "${LIBRARY}/${folder}" "${dir}/shot.png" \
            --freeze "${MOMENTS}" --timing "${TIMING}" --fps "${FPS}" --size "${WIDTH}" "${HEIGHT}" --screen "${SCREEN}" > "${dir}/shot.log" 2>&1
        status=$?
        [ "${status}" = 0 ] || echo "exit ${status}" >> "${dir}/shot.log"
    done
    printf '\r  %d / %d scenes, %d s' "${done_count}" "${total}" "$(( $(date +%s) - started ))"
done < "${MANIFEST}"
echo

if [ "${BASELINE}" = 1 ]; then
    echo "baseline taken: ${OUT}"
    exit 0
fi

# --- The comparison.
RESULTS="${OUT}/results.tsv"
: > "${RESULTS}"
pairs="${OUT}/pairs.tsv"
: > "${pairs}"
for engine in ${ENGINES//,/ }; do
    for expected in "${AGAINST}/${engine}"/*/shot-t*.png; do
        [ -f "${expected}" ] || continue
        name="$(basename "$(dirname "${expected}")")"
        if [ -n "${ONLY}" ] && ! echo "${name}" | grep -qE "${ONLY}"; then continue; fi
        file="$(basename "${expected}")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${engine}" "${name}" "${file}" "${expected}" "${OUT}/${engine}/${name}/${file}" \
            "${OUT}/${engine}/${name}/diff-${file}" >> "${pairs}"
    done
done
cut -f4-6 "${pairs}" | "${TOOLS}/imgdiff" --tolerance "${TOLERANCE}" | paste "${pairs}" - | cut -f1-3,7- > "${RESULTS}"
rm -f "${pairs}"

python3 -I "${ROOT}/scripts/tools/compare-report.py" "${OUT}" "${AGAINST}" "${ROOT}/scripts/compare-exclusions.txt"
