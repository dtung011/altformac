#!/bin/sh
# Encodes a screen recording into the files the website uses.
#
#   scripts/make-promo.sh recording.mov [options]
#
#   --start S / --end S     trim (seconds in the recording)
#   --crop W:H:X:Y          crop every frame first, in recording pixels (e.g. to drop the macOS menu bar)
#   --freeze T1,T2,...      hold the frame at each time (seconds in the recording) so the HUD can be read
#   --hold S                how long each freeze lasts (default 1.2)
#   --hud-at S              also save the frame at that time to site/promo-hud.png ...
#   --hud-crop W:H:X:Y      ... cut to the HUD area, in recording pixels
#
# Writes site/promo.mp4 (H.264), site/promo.webm (VP9) and site/promo-poster.jpg, 1600 px wide, no audio.
# Needs ffmpeg, installed inside the repo's Python virtualenv (./venv), never globally:
#   scripts/setup-video-env.sh
# (override with FFMPEG=/path/to/ffmpeg)
set -e
cd "$(dirname "$0")/.."

IN="$1"; [ -n "$IN" ] && [ -f "$IN" ] || { echo "usage: $0 recording.mov [options]" >&2; exit 1; }
shift
START=0; END=""; CROP=""; FREEZE=""; HOLD=1.2; HUD_AT=""; HUD_CROP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --start) START="$2"; shift 2;;
    --end) END="$2"; shift 2;;
    --crop) CROP="$2"; shift 2;;
    --freeze) FREEZE="$2"; shift 2;;
    --hold) HOLD="$2"; shift 2;;
    --hud-at) HUD_AT="$2"; shift 2;;
    --hud-crop) HUD_CROP="$2"; shift 2;;
    *) echo "unknown option $1" >&2; exit 1;;
  esac
done

if [ -z "$FFMPEG" ]; then
  FFMPEG="$(venv/bin/python -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null)" || {
    echo "ffmpeg not found. Run scripts/setup-video-env.sh first." >&2; exit 1; }
fi

# Filter graph: crop -> cut into segments at each freeze time, clone the last frame of each
# segment for HOLD seconds -> join -> 30 fps -> scale. Cutting before the fps change keeps the exact
# frame shown at each freeze time. Freeze times are converted to the trimmed timeline.
PRE="null"; [ -n "$CROP" ] && PRE="crop=$CROP"
TIMES="$(echo "$FREEZE" | tr ',' ' ')"
N=0; for _ in $TIMES; do N=$((N + 1)); done
if [ "$N" -eq 0 ]; then
  GRAPH="[0:v]$PRE,fps=30,scale=1600:-2:flags=lanczos,format=yuv420p[v]"
else
  GRAPH="[0:v]$PRE,split=$((N + 1))"
  i=0; while [ $i -le $N ]; do GRAPH="$GRAPH[s$i]"; i=$((i + 1)); done
  GRAPH="$GRAPH;"
  PREV=0; i=0; JOIN=""
  for T in $TIMES; do
    R="$(awk "BEGIN{print $T - $START}")"
    GRAPH="$GRAPH[s$i]trim=start=$PREV:end=$R,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=$HOLD[c$i];"
    JOIN="$JOIN[c$i]"; PREV="$R"; i=$((i + 1))
  done
  GRAPH="$GRAPH[s$i]trim=start=$PREV,setpts=PTS-STARTPTS[c$i];$JOIN[c$i]concat=n=$((N + 1)):v=1:a=0,fps=30,scale=1600:-2:flags=lanczos,format=yuv420p[v]"
fi

TRIM="-ss $START"; [ -n "$END" ] && TRIM="$TRIM -to $END"

echo "==> mp4"
# shellcheck disable=SC2086
"$FFMPEG" -hide_banner -loglevel error -y $TRIM -i "$IN" -filter_complex "$GRAPH" -map "[v]" -an \
  -c:v libx264 -preset slow -crf 24 -movflags +faststart site/promo.mp4
echo "==> webm"
"$FFMPEG" -hide_banner -loglevel error -y -i site/promo.mp4 -an \
  -c:v libvpx-vp9 -crf 36 -b:v 0 -row-mt 1 site/promo.webm
echo "==> poster"
"$FFMPEG" -hide_banner -loglevel error -y -ss 1 -i site/promo.mp4 -frames:v 1 -q:v 3 site/promo-poster.jpg

OUT="site/promo.mp4 site/promo.webm site/promo-poster.jpg"
if [ -n "$HUD_AT" ]; then
  echo "==> hud still"
  HVF="null"; [ -n "$HUD_CROP" ] && HVF="crop=$HUD_CROP"
  "$FFMPEG" -hide_banner -loglevel error -y -ss "$HUD_AT" -i "$IN" -frames:v 1 -vf "$HVF" site/promo-hud.png
  OUT="$OUT site/promo-hud.png"
fi

# shellcheck disable=SC2086
ls -lh $OUT
