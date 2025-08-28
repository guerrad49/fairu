#!/bin/bash

set -euo pipefail

# Load helper functions
source "/Users/david_guerra/Programming/bash/functions.sh"

# Text formatting.
bold=$(tput bold)
normal=$(tput sgr0)

usage() 
{
   echo "Usage: fairu [-d <directory>] [-e <image|video>] [-m <name|creation>]" 1>&2
   echo "             [-o <outfile>] [-i <infile>] [-p <prefix>] [-s <start>]"
   echo ""
   echo "${bold}Description${normal}"
   echo "    Some descripion.."
   echo ""
   echo "    ${bold}-d${normal}    The directory to search. Default is pwd."
   echo "    ${bold}-e${normal}    File type extensions. Defaults to images/videos."
   echo "    ${bold}-m${normal}    Method for sorting files."
   echo "    ${bold}-o${normal}    Write results to outfile."
   echo "    ${bold}-i${normal}    Read paths from infile."
   echo "    ${bold}-p${normal}    Rename files with prefix."
   echo "    ${bold}-s${normal}    Renumber files given starting value. Default is 1."
   exit 1
}

DIR=$(pwd)
IMG_EXT=("heic" "HEIC" "png" "PNG" "jpg" "JPG")
VID_EXT=("mov" "MOV" "mp4" "MP4")
EXTS=("${IMG_EXT[@]}" "${VID_EXT[@]}")
PREFIX="file"
START=1

while getopts ":d:e:m:o:i:p:s:" arg; do
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
         ;;
      s)
         START=${OPTARG}
         ;;
      *)
         usage
         ;;
   esac
done

shift $((OPTIND-1))

# Sort files.
if [[ -n ${METHOD+x} ]]; then
   files=$(get_files_with_ext $DIR "${EXTS[@]}")
   results=$(printf "%s\n" "${files[@]}" | get_sorted_files $METHOD)

   if [[ -n ${OUTFILE+x} ]]; then
      echo "$results" > $OUTFILE
   else
      echo "$results"
   fi
fi

# Order files in a copy folder.
if [[ -n ${INFILE+x} ]]; then
   copy_ordered_files $INFILE $PREFIX $START
fi
