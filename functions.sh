#!/bin/bash

# get_files_with_ext
#
# Description:
#   List all files in a given directory that match one or more file extensions.
#   This function searches only the top-level directory (non-recursive).
#
# Usage:
#   get_files_with_ext <directory> <ext1> [ext2 ...]
#
# Arguments:
#   directory   The directory to search in.
#   exts        One or more file extensions to match (without the dot).
#
# Output:
#   Prints a newline-separated list of matching file paths.
#
# Notes:
#   - Matching is case-sensitive ("txt" will not match "TXT").
#   - If no files are found for a given extension, nothing is printed.
#   - Globbing is protected with `nullglob` so unmatched patterns expand to nothing.
#
# Examples:
#   get_files_with_ext /path/to/dir txt md
#       → lists all .txt and .md files in /path/to/dir
#
#   get_files_with_ext ./ jpg png
#       → lists all .jpg and .png files in the current directory
#
get_files_with_ext() {
    local dir="$1"
    shift   # Remove directory argument, now only extensions left.
    local exts=("$@")

    shopt -s nullglob
    local files=()

    echo "here"
    for ext in "${exts[@]}"; do
        # Use globbing for extensions.
        for f in "$dir"/*."$ext"; do
            # Avoid returning the literal pattern if no match.
            [[ -e "$f" ]] && files+=("$f")
        done
    done

    # Terminate early if no matches.
    # if [[ ${#files[@]} -eq 0 ]]; then
    #     echo "No files with given extensions found."
    #     exit 1
    # fi

    shopt -u nullglob
    printf "%s\n" "${files[@]}"
}

# get_sorted_files
#
# Description:
#   List files in a given directory with specified extensions, then sort them
#   according to a chosen method. This function builds on `get_files_with_ext`.
#
# Usage:
#   get_sorted_files_with_ext <method> <ext1> [ext2 ...]
#
# Arguments:
#   method      Sorting method to use. One of:
#                  - "name"     : Sort alphabetically by filename only
#                  - "creation" : Sort by creation date (oldest → newest),
#                                 using macOS `GetFileInfo -d`.
#   extN        One or more file extensions to match (without the dot).
#
# Output:
#   Prints a newline-separated list of sorted file paths.
#
# Notes:
#   - Requires `GetFileInfo` (part of Xcode Command Line Tools) for "creation".
#   - Dates are reformatted internally so sorting is chronological.
#   - Sorting by creation is ascending by default (oldest → newest).
#
# Examples:
#   get_sorted_files_with_ext /path/to/dir name txt md
#   get_sorted_files_with_ext /path/to/dir creation pdf
#
get_sorted_files() {
    local method="$1"

    case "$method" in
        name)
            # Sort by full path.
            awk -F/ '{print $0}' | sort
            ;;
        creation)
            while IFS= read -r f; do
                rawDate=$(GetFileInfo -d "$f")
                # Convert MM/DD/YYYY HH:MM:SS to YYYY-MM-DD HH:MM:SS
                sortableDate=$(date -j -f "%m/%d/%Y %H:%M:%S" "$rawDate" +"%Y-%m-%d %H:%M:%S")
                echo "$f $sortableDate"
            done | sort -k 2,3 | cut -d " " -f 1-3
            ;;
        *)
            echo "Unknown sort method: $method" >$2
            return 1
            ;;
    esac
}

copy_ordered_files() {
    local paths=$(cat "$1")
    local prefix="$2"
    local start="$3"

    # Determine format from number of lines in file.    
    lineCount=$(grep -c ^ <<< "$paths")
    numFormat="%03d"
    if [[ $lineCount -gt 999 ]]; then
        numFormat="%04d"
    fi

    # Make and get the copy directory.
    firstPath=$(echo "$paths" | head -n 1)
    parentDir=$(dirname "$firstPath")
    copyDir="${parentDir}_COPY"
    mkdir -p "$copyDir"

    for path in $paths; do
        file=$(basename "$path")
        # lowercase="${file,,}"
        ext=$(echo ${file#*.} | awk '{print tolower($0)}')
        newName=$(echo "${prefix}_$(printf ${numFormat} $start).$ext")
        cp "$path" "${copyDir}/${newName}"
        let start=start+1
    done
}