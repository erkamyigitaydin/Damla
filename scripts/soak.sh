#!/bin/zsh
# Memory soak for the built app (../Damla.app). Launches it with --debug on a copy of this user's data folder, drives
# it through the panel pages, the HUDs and a stream of copied screenshots, and samples its footprint meanwhile: a
# build that holds on to images or windows shows as a footprint that keeps climbing between the first and the last
# samples. It quits any running Damla first, and the copied screenshots replace whatever is on the clipboard.
# Usage: scripts/soak.sh [cycles]   (a cycle is about 16 s; the default 22 take some 8 minutes with the idle periods)
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
APP="${DAMLA_APP:-$PROJECT_DIR/../Damla.app}"
CYCLES=${1:-22}
WORK="$(mktemp -d "${TMPDIR:-/tmp}/Damla-soak.XXXXXX")"
SAMPLER=""
trap 'kill ${SAMPLER:-} 2>/dev/null; pkill -x Damla 2>/dev/null; true' EXIT

# A --debug command to the running app (see AppDelegate.debugCommand).
post() {
  osascript -l JavaScript -e 'ObjC.import("Foundation"); var a = $.NSProcessInfo.processInfo.arguments; var cmd = ObjC.unwrap(a.objectAtIndex(a.count - 1)); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("app.local.damla.debug", cmd, null, true); 0' -- "$1" >/dev/null
  sleep "${2:-0.7}"
}

# Twelve screenshot-sized PNGs: flat areas with noisy bands, so they stay under the 4 MB the clipboard history keeps.
mkdir -p "$WORK/img"
python3 - "$WORK/img" <<'PY'
import os, random, struct, sys, zlib
def png(path, w, h, seed):
    random.seed(seed)
    flat = bytes([(seed * 40 + 30) & 255, (seed * 90 + 60) & 255, (seed * 130 + 90) & 255]) * w
    raw = bytearray()
    for _ in range(h):
        row = bytearray(flat)
        for _ in range(3):
            a = random.randrange(0, w - 200) * 3; b = a + random.randrange(60, 200) * 3
            row[a:b] = os.urandom(b - a)
        raw += b"\x00" + row
    def chunk(t, d): c = t + d; return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
sizes = [(2560, 1440), (3024, 1964), (5120, 2880), (1800, 1200), (2560, 1600), (3456, 2234),
         (4480, 2520), (2048, 1536), (3840, 2160), (5120, 2880), (2880, 1800), (3024, 1890)]
for i, (w, h) in enumerate(sizes):
    png(os.path.join(sys.argv[1], f"shot{i}.png"), w, h, i)
PY

pkill -x Damla 2>/dev/null || true; sleep 1
export DAMLA_SUPPORT_DIR="$WORK/support"
cp -R "$HOME/Library/Application Support/Damla" "$DAMLA_SUPPORT_DIR"
"$APP/Contents/MacOS/Damla" --debug > "$WORK/app.log" 2>&1 &
sleep 4
PID="$(pgrep -x Damla | head -1)" || { echo "Damla did not start:"; cat "$WORK/app.log"; exit 1; }
SAMPLES="$WORK/samples.txt"
(
  echo "elapsed_s rss_mb footprint_mb cputime"
  start=$(date +%s)
  while kill -0 "$PID" 2>/dev/null; do
    rss=$(ps -o rss= -p "$PID" | tr -d ' '); cpu=$(ps -o cputime= -p "$PID" | tr -d ' ')
    fp=$(footprint -p "$PID" 2>/dev/null | grep -m1 -oE 'Footprint: *[0-9]+' | grep -oE '[0-9]+' || true)
    echo "$(( $(date +%s) - start )) $(( ${rss:-0} / 1024 )) ${fp:-?} ${cpu:-?}"
    sleep 5
  done
) >> "$SAMPLES" &
SAMPLER=$!
echo "Damla $PID started; 45 s idle, then $CYCLES cycles"
sleep 45
for i in $(seq 1 "$CYCLES"); do
  post open 1
  for tab in tab-home mixer-pane outputs tab-home tab-sound tab-files tab-clipboard tab-focus tab-agents tab-notifications tab-shortcuts tab-clipboard; do post "$tab"; done
  post close 1
  post hud-volume 0.4; post hud-brightness 0.4; post hud-airpods 1; post hud-battery 1
  osascript -e "set the clipboard to (read (POSIX file \"$WORK/img/shot$(( (i - 1) % 12 )).png\") as «class PNGf»)" >/dev/null 2>&1 || true
  sleep 1.2
  printf '\rcycle %d/%d' "$i" "$CYCLES"
done
echo; sleep 60
footprint -p "$PID" | head -14
echo; echo "Samples every 30 s (all in $SAMPLES):"
awk 'NR == 1 || NR % 6 == 2' "$SAMPLES"
