#!/usr/bin/env bash
# watermark.sh - overlay image watermark onto video(s) or image(s)
# Usage:
#   ./watermark.sh input watermark [output] [-p position] [-s scale] [-m margin]
#                  [-a opacity] [-b] [-x vx] [-y vy] [-t] [-g grid] [-q pad]
#
# Positional:
#   input      video/image file, or directory for batch mode
#   watermark  watermark image (png with alpha recommended)
#   output     output file/dir (optional, default: watermarked_<input>)
#
# Flags (all optional):
#   -p  position: tl tr bl br center (default: br; ignored on images when -t is set)
#   -s  watermark scale as fraction of main width, e.g. 0.15 = 15% (default: 0.15)
#   -m  margin px from edge (default: 10)
#   -a  opacity 1-100 (%, default: 50)
#   -b  DVD-logo bounce mode (videos only)
#   -x  bounce speed x, px/sec (default: 120)
#   -y  bounce speed y, px/sec (default: 90)
#   -t  tile watermark as a repeating pattern (images only; default: single position)
#   -g  pattern grid COLSxROWS for images, only used with -t (default: 4x4)
#   -q  pattern padding px between tiles, only used with -t (default: 20)
#
# Watermark size/position always derive from each input's actual decoded
# width/height at run time (ffmpeg scale2ref) - works on any resolution,
# no hardcoded dimensions needed. Default: images and videos both place the
# watermark at a single position (-p); add -b to bounce video, -t to tile image.
# Batch mode: pass input as a directory to process every video/image inside it.

set -euo pipefail

POSITION="br"
SCALE="0.15"
MARGIN="10"
OPACITY="50"
BOUNCE=0
VX="120"
VY="90"
TILE=0
GRID="4x4"
PAD="20"

usage() { grep '^#' "$0" | sed 's/^#//'; exit 1; }

[[ $# -lt 2 ]] && usage
INPUT="$1"; WATERMARK="$2"; shift 2

OUTPUT=""
if [[ $# -gt 0 && "$1" != -* ]]; then
  OUTPUT="$1"; shift
fi

while getopts "p:s:m:a:x:y:g:q:bth" opt; do
  case "$opt" in
    p) POSITION="$OPTARG" ;;
    s) SCALE="$OPTARG" ;;
    m) MARGIN="$OPTARG" ;;
    a) OPACITY="$OPTARG" ;;
    b) BOUNCE=1 ;;
    x) VX="$OPTARG" ;;
    y) VY="$OPTARG" ;;
    t) TILE=1 ;;
    g) GRID="$OPTARG" ;;
    q) PAD="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

[[ -f "$WATERMARK" ]] || { echo "Error: watermark not found: $WATERMARK"; exit 1; }
command -v ffmpeg >/dev/null || { echo "Error: ffmpeg not installed"; exit 1; }
command -v ffprobe >/dev/null || { echo "Error: ffprobe not installed"; exit 1; }

[[ "$OPACITY" =~ ^[0-9]+$ ]] && (( OPACITY >= 1 && OPACITY <= 100 )) || { echo "Error: -a must be an integer 1-100"; exit 1; }
OPACITY_FRAC="$(awk -v p="$OPACITY" 'BEGIN{printf "%.4f", p/100}')"

case "$POSITION" in
  tl) STATIC_XY="${MARGIN}:${MARGIN}" ;;
  tr) STATIC_XY="main_w-overlay_w-${MARGIN}:${MARGIN}" ;;
  bl) STATIC_XY="${MARGIN}:main_h-overlay_h-${MARGIN}" ;;
  br) STATIC_XY="main_w-overlay_w-${MARGIN}:main_h-overlay_h-${MARGIN}" ;;
  center) STATIC_XY="(main_w-overlay_w)/2:(main_h-overlay_h)/2" ;;
  *) echo "Error: invalid position '$POSITION' (tl|tr|bl|br|center)"; exit 1 ;;
esac

# DVD-bounce: triangle wave via mod/abs, clamped inside margins, overlay
# re-evaluates x/y every frame automatically since exprs contain t.
BOUNCE_XW="(main_w-overlay_w-2*${MARGIN})"
BOUNCE_YH="(main_h-overlay_h-2*${MARGIN})"
BOUNCE_X="${MARGIN}+abs(mod(t*${VX},2*${BOUNCE_XW})-${BOUNCE_XW})"
BOUNCE_Y="${MARGIN}+abs(mod(t*${VY},2*${BOUNCE_YH})-${BOUNCE_YH})"

# scale2ref sizes watermark relative to each input's actual width (iw here
# resolves to the reference/main stream's width, so this auto-adapts to any
# resolution - confirmed empirically against this ffmpeg build).
build_filter() {
  local xy_expr="$1"
  local f="[1:v][0:v]scale2ref=w=iw*${SCALE}:h=ow/mdar[wm][base]"
  if [[ "$OPACITY" != "100" ]]; then
    f="${f};[wm]format=rgba,colorchannelmixer=aa=${OPACITY_FRAC}[wm]"
  fi
  echo "${f};[base][wm]overlay=${xy_expr}"
}
FILTER_STATIC="$(build_filter "$STATIC_XY")"
FILTER_BOUNCE="$(build_filter "x='${BOUNCE_X}':y='${BOUNCE_Y}'")"

# tiled pattern (images): scale wm small, loop it into N copies, tile filter
# arranges copies into COLSxROWS grid on transparent canvas, then a second
# scale2ref stretches that grid to the real main image size (w=iw:h=ih -
# same reference-resolves-to-main behavior as build_filter above) and overlay.
COLS="${GRID%x*}"
ROWS="${GRID#*x}"
[[ "$GRID" =~ ^[0-9]+x[0-9]+$ ]] || { echo "Error: -g must be COLSxROWS, e.g. 4x4"; exit 1; }
TILES=$((COLS * ROWS))
build_pattern_filter() {
  local f="[1:v]scale=iw*${SCALE}:-1,format=rgba"
  if [[ "$OPACITY" != "100" ]]; then
    f="${f},colorchannelmixer=aa=${OPACITY_FRAC}"
  fi
  f="${f}[wm0];[wm0]loop=loop=$((TILES - 1)):size=1:start=0,tile=layout=${COLS}x${ROWS}:padding=${PAD}:color=0x00000000@0.0[tiled]"
  f="${f};[tiled][0:v]scale2ref=w=iw:h=ih[tiled2][base]"
  echo "${f};[base][tiled2]overlay=0:0"
}
FILTER_PATTERN="$(build_pattern_filter)"

# auto-detect image vs video by decoded frame count, not file extension
is_image() {
  local nb
  nb="$(ffprobe -v error -select_streams v:0 -count_frames \
        -show_entries stream=nb_read_frames -of csv=p=0 "$1" 2>/dev/null || echo "")"
  [[ "$nb" == "1" ]]
}

run_one() {
  local in="$1"
  local out="$2"

  if is_image "$in"; then
    if [[ "$TILE" == "1" ]]; then
      ffmpeg -y -i "$in" -i "$WATERMARK" -filter_complex "$FILTER_PATTERN" -frames:v 1 -update 1 "$out"
    else
      ffmpeg -y -i "$in" -i "$WATERMARK" -filter_complex "$FILTER_STATIC" -frames:v 1 -update 1 "$out"
    fi
  elif [[ "$BOUNCE" == "1" ]]; then
    ffmpeg -y -i "$in" -i "$WATERMARK" -filter_complex "$FILTER_BOUNCE" -c:a copy "$out"
  else
    ffmpeg -y -i "$in" -i "$WATERMARK" -filter_complex "$FILTER_STATIC" -c:a copy "$out"
  fi
  echo "-> $out"
}

if [[ -d "$INPUT" ]]; then
  OUTDIR="${OUTPUT:-watermarked}"
  mkdir -p "$OUTDIR"
  shopt -s nullglob nocaseglob
  for f in "$INPUT"/*.{mp4,mov,mkv,avi,webm,jpg,jpeg,png,bmp,webp}; do
    base="$(basename "$f")"
    run_one "$f" "${OUTDIR}/${base}"
  done
else
  [[ -f "$INPUT" ]] || { echo "Error: input not found: $INPUT"; exit 1; }
  OUT="${OUTPUT:-watermarked_$(basename "$INPUT")}"
  run_one "$INPUT" "$OUT"
fi
