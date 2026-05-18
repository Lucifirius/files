#!/bin/bash
# Usage: ./optimize.sh input.mp4 output.mp4

INPUT="$1"
OUTPUT="${2:-output.mp4}"

ffmpeg -i "$INPUT" \
  -c:v libx265 \
  -crf 24 \
  -preset slow \
  -x265-params "aq-mode=3:aq-strength=1.0" \
  -c:a aac \
  -b:a 128k \
  -movflags +faststart \
  "$OUTPUT"
