#!/bin/bash
# Usage: ./optimize.sh input.mp4 output.mp4
INPUT="$1"
OUTPUT="${2:-output.mp4}"
ffmpeg -i "$INPUT" \
  -c:v libx264 \
  -profile:v high \
  -level 4.0 \
  -pix_fmt yuv420p \
  -crf 23 \
  -preset slow \
  -vf scale=-2:720 \
  -r 24 \
  -c:a aac \
  -b:a 96k \
  -movflags +faststart \
  "$OUTPUT"
