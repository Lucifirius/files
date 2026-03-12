#!/usr/bin/env bash
# scan_empty_media.sh
# Scans movie/series folders and reports any that contain no video files.
# Usage: ./scan_empty_media.sh [movies_dir] [series_dir] ...
#        If no arguments given, prompts for directories interactively.

# ---------------------------------------------------------------------------
# Configuration – add/remove extensions as needed
# ---------------------------------------------------------------------------
VIDEO_EXTENSIONS=("mkv" "mp4" "avi" "mov" "wmv" "m4v" "ts" "m2ts" "mpg" "mpeg" "flv" "webm" "rmvb" "iso")

# Minimum file size in bytes to count as a real video (default: 50 MB)
# Avoids counting tiny sample/trailer files as the "main" video.
MIN_SIZE_BYTES=$((50 * 1024 * 1024))

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
build_find_args() {
    # Builds the -iname pattern list for find
    local args=()
    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        if [[ ${#args[@]} -gt 0 ]]; then
            args+=("-o")
        fi
        args+=("-iname" "*.${ext}")
    done
    echo "${args[@]}"
}

has_video_file() {
    local dir="$1"
    # Look for any video file recursively that meets the minimum size
    while IFS= read -r -d '' file; do
        local size
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
        if [[ "$size" -ge "$MIN_SIZE_BYTES" ]]; then
            return 0   # found one – directory is fine
        fi
    done < <(find "$dir" \( $(build_find_args) \) -type f -print0 2>/dev/null)
    return 1  # nothing found
}

scan_root() {
    local root="$1"
    local missing=()
    local total=0

    echo -e "\n${CYAN}${BOLD}Scanning:${RESET} ${root}"
    echo "──────────────────────────────────────────────────"

    # Each immediate sub-directory is treated as one "title" folder
    while IFS= read -r -d '' title_dir; do
        ((total++))
        if ! has_video_file "$title_dir"; then
            missing+=("$title_dir")
            echo -e "  ${RED}✗  MISSING VIDEO${RESET}  →  ${title_dir}"
        fi
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    if [[ $total -eq 0 ]]; then
        echo -e "  ${YELLOW}No sub-folders found in this directory.${RESET}"
    elif [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}✔  All ${total} folder(s) contain a video file.${RESET}"
    else
        echo -e "\n  ${YELLOW}${#missing[@]} of ${total} folder(s) have no qualifying video file.${RESET}"
    fi

    # Return missing list via a global so callers can accumulate totals
    MISSING_DIRS+=("${missing[@]}")
    TOTAL_SCANNED=$((TOTAL_SCANNED + total))
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
declare -a SCAN_ROOTS
declare -a MISSING_DIRS
TOTAL_SCANNED=0

# Collect directories from args or prompt
if [[ $# -gt 0 ]]; then
    SCAN_ROOTS=("$@")
else
    echo -e "${BOLD}No directories specified.${RESET}"
    echo "Enter the full paths to scan, one per line."
    echo "Press Enter on an empty line when done."
    echo ""
    while true; do
        read -rp "  Path: " p
        [[ -z "$p" ]] && break
        SCAN_ROOTS+=("$p")
    done
fi

if [[ ${#SCAN_ROOTS[@]} -eq 0 ]]; then
    echo -e "${RED}No directories provided. Exiting.${RESET}"
    exit 1
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Media Folder Video Scanner             ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo -e "  Min video size : $(( MIN_SIZE_BYTES / 1024 / 1024 )) MB"
echo -e "  Extensions     : ${VIDEO_EXTENSIONS[*]}"

# Validate and scan each root
for root in "${SCAN_ROOTS[@]}"; do
    if [[ ! -d "$root" ]]; then
        echo -e "\n${RED}Not a directory, skipping:${RESET} ${root}"
        continue
    fi
    scan_root "$root"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  SUMMARY${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════${RESET}"
echo -e "  Total folders scanned : ${TOTAL_SCANNED}"
echo -e "  Folders missing video : ${#MISSING_DIRS[@]}"

if [[ ${#MISSING_DIRS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}  Folders to investigate:${RESET}"
    for d in "${MISSING_DIRS[@]}"; do
        echo -e "    ${RED}•${RESET}  $d"
    done
    echo ""
    exit 1   # non-zero exit so the script can be used in pipelines/cron
fi

echo ""
exit 0
