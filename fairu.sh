#!/bin/bash

set -euo pipefail

# Load helper functions (located next to this script).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

# Text formatting (tput can fail when there's no terminal).
bold=$(tput bold 2>/dev/null || true)
normal=$(tput sgr0 2>/dev/null || true)

usage()
{
   {
   echo "Usage: fairu [-d <directory>] [-e <image|video>] [-m <name|creation>]"
   echo "             [-o <outfile>] [-i <infile>] [-p <prefix>] [-s <start>]"
   echo "             [-c <copy_dir>] [-n]"
   echo ""
   echo "${bold}Description${normal}"
   echo "    Sort and renumber image/video files. Can run in two steps"
   echo "    (write an order file, then rename from it) or in one shot"
   echo "    (sort and rename)."
   echo "    Renaming is collision-safe: nothing is overwritten, and nothing is"
   echo "    changed if a conflict is detected."
   echo ""
   echo "    ${bold}-d${normal}    The directory to search. Default is pwd."
   echo "    ${bold}-e${normal}    File type: image or video. Default: both."
   echo "    ${bold}-m${normal}    Method for sorting files."
   echo "    ${bold}-o${normal}    Write sorted results to outfile."
   echo "    ${bold}-i${normal}    Read paths from infile and rename them."
   echo "    ${bold}-p${normal}    Rename files with prefix. With -m, sorts and"
   echo "          renames in one shot."
   echo "    ${bold}-s${normal}    Renumber from this value. Default is 1."
   echo "    ${bold}-c${normal}    Copy renamed files into <copy_dir>"
   echo "          instead of renaming in place."
   echo "    ${bold}-n${normal}    Dry run: print old -> new plan only."
   echo ""
   echo "${bold}Examples${normal}"
   echo "    Two steps:  fairu -d ~/pics -e image -m name -o order"
   echo "                fairu -i order -p img -s 300"
   echo "    One shot:   fairu -d ~/pics -e image -m name -p img -s 300"
   echo "    Preview:    fairu -d ~/pics -m creation -p img -n"
   echo "    Safe copy:  fairu -d ~/pics -m creation -p img -c ~/pics_sorted"
   } 1>&2
   exit 1
}

DIR=$(pwd)
IMG_EXT=("heic" "HEIC" "png" "PNG" "jpg" "JPG")
VID_EXT=("mov" "MOV" "mp4" "MP4")
EXTS=("${IMG_EXT[@]}" "${VID_EXT[@]}")
PREFIX="file"
START=1
METHOD=""
OUTFILE=""
INFILE=""
COPY_DIR=""
DRY_RUN=0
PREFIX_SET=0
START_SET=0

while getopts ":d:e:m:o:i:p:s:c:n" arg; do
   case "${arg}" in
      d)
         DIR=${OPTARG}
         ;;
      e)
         case "$OPTARG" in
            image) EXTS=("${IMG_EXT[@]}") ;;
            video) EXTS=("${VID_EXT[@]}") ;;
            *)
               echo "Unknown -e value: $OPTARG" >&2
               usage
               ;;
         esac
         ;;
      m)
         METHOD=${OPTARG}
         ;;
      o)
         OUTFILE=${OPTARG}
         ;;
      i)
         INFILE=${OPTARG}
         ;;
      p)
         PREFIX=${OPTARG}
         PREFIX_SET=1
         ;;
      s)
         START=${OPTARG}
         START_SET=1
         ;;
      c)
         COPY_DIR=${OPTARG}
         ;;
      n)
         DRY_RUN=1
         ;;
      *)
         usage
         ;;
   esac
done

shift $((OPTIND-1))

# ---- Validate options -------------------------------------------------------
if [[ ! "$START" =~ ^[0-9]+$ ]]; then
   echo "Error: -s must be a non-negative integer (got: $START)" >&2
   exit 1
fi

if [[ -n "$METHOD" && "$METHOD" != "name" && "$METHOD" != "creation" ]]; then
   echo "Unknown -m value: $METHOD" >&2
   usage
fi

if [[ -z "$METHOD" && -z "$INFILE" ]]; then
   usage
fi

if [[ -n "$METHOD" && -n "$INFILE" ]]; then
   echo "Error: -m and -i can't be combined. Use -m with -p for one-shot" >&2
   echo "       mode, or -i on its own to rename from an existing order" >&2
   echo "       file." >&2
   exit 1
fi

# Remove the temporary order file (one-shot mode without -o) on exit.
ORDER_TMP=""
cleanup()
{
   if [[ -n "$ORDER_TMP" ]]; then
      rm -f "$ORDER_TMP"
   fi
}
trap cleanup EXIT

DO_RENAME=0
ORDER_FILE=""

# ---- Sort files -------------------------------------------------------------
if [[ -n "$METHOD" ]]; then
   if [[ ! -d "$DIR" ]]; then
      echo "Error: not a directory: $DIR" >&2
      exit 1
   fi

   files=()
   while IFS= read -r f; do
      if [[ -n "$f" ]]; then
         files+=("$f")
      fi
   done < <(get_files_with_ext "$DIR" "${EXTS[@]}" || true)

   if [[ ${#files[@]} -eq 0 ]]; then
      echo "No matching files found in $DIR" >&2
      exit 1
   fi

   results=$(get_sorted_files "$METHOD" "${files[@]}")

   # -p turns this into a one-shot sort + rename.
   if [[ $PREFIX_SET -eq 1 ]]; then
      DO_RENAME=1
   fi

   if [[ -n "$OUTFILE" ]]; then
      printf '%s\n' "$results" > "$OUTFILE"
      ORDER_FILE="$OUTFILE"
   elif [[ $DO_RENAME -eq 1 ]]; then
      ORDER_TMP=$(mktemp)
      printf '%s\n' "$results" > "$ORDER_TMP"
      ORDER_FILE="$ORDER_TMP"
   else
      printf '%s\n' "$results"
   fi
fi

# ---- Rename from an order file (two-step flow) ------------------------------
if [[ -n "$INFILE" ]]; then
   if [[ ! -r "$INFILE" ]]; then
      echo "Error: can't read order file: $INFILE" >&2
      exit 1
   fi
   ORDER_FILE="$INFILE"
   DO_RENAME=1
fi

if [[ $DO_RENAME -eq 1 ]]; then
   rename_ordered_files "$ORDER_FILE" "$PREFIX" "$START" \
                        "$DRY_RUN" "$COPY_DIR" || exit 1
elif [[ $START_SET -eq 1 || -n "$COPY_DIR" || $DRY_RUN -eq 1 ]]; then
   echo "Note: -s/-c/-n have no effect without renaming." >&2
   echo "      Add -p (or use -i) to rename." >&2
fi