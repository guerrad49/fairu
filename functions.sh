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
    local files=()

    # Enable nullglob so unmatched patterns expand to nothing.
    shopt -s nullglob

    for ext in "${exts[@]}"; do
        for f in "$dir"/*."$ext"; do
            files+=("$f")
        done
    done

    shopt -u nullglob

    # Terminate early if no matches.
    if [[ ${#files[@]} -eq 0 ]]; then
        echo ""
        return 1
    fi

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
    shift
    local files=("$@")

    case "$method" in
        "name")
            # Sort by full path.
            printf "%s\n" "${files[@]}" | sort
            ;;
        "creation")
            for f in "${files[@]}"; do
                timestamp=$(stat -f "%B" "$f")
                # Print timestamp and file side-by-side.
                printf "%s %s\n" "$timestamp" "$f"
            done | sort -n | cut -d' ' -f2-
            ;;
        *)
            echo "Unknown sort method: $method" >&2
            return 1
            ;;
    esac
}

copy_ordered_files() {
    local order_file="$1"
    local prefix="$2"
    local start_index="$3"
    local idx=$start_index

    # Read the ordered file line by line.
    while IFS= read -r src_file; do
        [[ -z "$src_file" ]] || [[ ! -e "$src_file" ]] && continue

        local parent_dir=$(dirname "$src_file")
        local raw_ext="${src_file##*.}"
        local ext=$(echo "$raw_ext" | tr '[:upper:]' '[:lower:]')
        
        # The new formatted name.
        local dest_name
        printf -v dest_name "%s_%03d.%s" "$prefix" "$idx" "$ext"

        mv "$src_file" "$parent_dir/$dest_name"
        echo "Renamed: $src_file -> $parent_dir/$dest_name"

        ((idx++))
    done < "$order_file"
}
