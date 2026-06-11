#!/usr/bin/env bash
# Composites the Ghostty terminal background (Monet's Japanese Footbridge at
# low opacity over the Catppuccin Mocha base) behind a vhs recording, so demo
# gifs match how the plugin actually looks in the author's terminal. vhs
# renders a solid theme background; this keys it out and overlays the result
# onto the painting — the same look Ghostty produces natively.
#
# Usage:  scripts/composite-demo-bg.sh <raw.mp4> <out.mp4> <out.gif>
#
# The raw mp4 must use the "Catppuccin Mocha" vhs theme (bg #1e1e2e).
set -euo pipefail

RAW=$1
OUT_MP4=$2
OUT_GIF=$3

IMAGE="$HOME/.config/assets/Japense Footbridge - Monet.jpeg"
BG=#1e1e2e
OPACITY=0.35

W=$(ffprobe -v error -select_streams v -show_entries stream=width -of csv=p=0 "$RAW")
H=$(ffprobe -v error -select_streams v -show_entries stream=height -of csv=p=0 "$RAW")

COMPOSITE="[1:v]scale=${W}:${H},format=rgba,colorchannelmixer=aa=${OPACITY}[art]; \
   color=c=${BG}:s=${W}x${H}:d=1[base]; \
   [base][art]overlay=format=auto[bg]; \
   [0:v]colorkey=${BG}:0.05:0.02[fg]; \
   [bg][fg]overlay=format=auto:shortest=1[out]"

ffmpeg -y -v error -i "$RAW" -loop 1 -i "$IMAGE" -filter_complex \
  "$COMPOSITE" -map "[out]" -c:v libx264 -crf 20 -pix_fmt yuv420p "$OUT_MP4"

# GIF goes straight from the raw recording in one pass: a lossy intermediate
# would add x264 noise to the static painting, defeating gif delta encoding.
ffmpeg -y -v error -i "$RAW" -loop 1 -i "$IMAGE" -filter_complex \
  "$COMPOSITE; [out]fps=20,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle[gif]" \
  -map "[gif]" "$OUT_GIF"

echo "wrote $OUT_MP4 + $OUT_GIF"
