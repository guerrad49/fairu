#!/bin/bash

# NOTE: Written to work with the bash 3.2 that ships with macOS (no mapfile,
# no associative arrays, careful with empty arrays under `set -u`).

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
#   Prints a newline-separated list of matching file paths. Prints nothing
#   and returns 1 if there are no matches.
#
# Notes:
#   - Matching is case-sensitive ("txt" will not match "TXT").
#   - Globbing is protected with `nullglob` so unmatched patterns expand to
#     nothing.
#
# Examples:
#   get_files_with_ext /path/to/dir txt md
#   get_files_with_ext ./ jpg png
#
get_files_with_ext() {
    local dir="$1"
    shift   # Remove directory argument, now only extensions left.
    local exts=("$@")
    local files=()
    local ext f

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
        return 1
    fi

    printf "%s\n" "${files[@]}"
}

# get_sorted_files
#
# Description:
#   Sort a list of file paths according to a chosen method.
#
# Usage:
#   get_sorted_files <method> <file1> [file2 ...]
#
# Arguments:
#   method      Sorting method to use. One of:
#                  - "name"     : Sort alphabetically by path
#                  - "creation" : Sort by creation date (oldest -> newest),
#                                 using macOS `stat -f %B` (birth time).
#   files       One or more file paths.
#
# Output:
#   Prints a newline-separated list of sorted file paths.
#
# Examples:
#   get_sorted_files name a.jpg b.jpg
#   get_sorted_files creation "${files[@]}"
#
get_sorted_files() {
    local method="$1"
    shift

    if [[ $# -eq 0 ]]; then
        return 0
    fi

    local files=("$@")
    local f timestamp

    case "$method" in
        "name")
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

# rename_ordered_files
#
# Description:
#   Rename (or copy) the files listed in an order file to <prefix>_<NNN>.<ext>,
#   numbered in the order they appear, starting at <start>.
#
#   Safety:
#     1. Everything is validated BEFORE any file is touched. The run aborts
#        (changing nothing) if a target name would overwrite a file that is
#        not part of the batch, or if the order file lists a file twice.
#     2. In-place renames are done in two phases: every file is first moved to
#        a hidden temporary name, then moved to its final name. Files in the
#        batch can therefore never clobber each other, so there is no need for
#        a "high starting value" first pass.
#     3. Moves use `mv -n` (no-clobber) and are verified afterwards.
#
# Usage:
#   rename_ordered_files <order_file> <prefix> <start> [dry_run] [copy_dir]
#
# Arguments:
#   order_file  File with one path per line, in the desired order.
#   prefix      Prefix for the new names.
#   start       Number for the first file.
#   dry_run     1 = only print the plan, change nothing. Default 0.
#   copy_dir    If set, copy files into this directory (created if needed)
#               and leave the originals untouched, instead of renaming.
#
# Notes:
#   - Extensions are lowercased.
#   - Numbers are zero-padded to at least 3 digits (more if the batch needs it).
#   - Missing files in the order file are skipped with a warning.
#
rename_ordered_files() {
    local order_file="$1"
    local prefix="$2"
    local start_index=$((10#$3))
    local dry_run="${4:-0}"
    local copy_dir="${5:-}"

    # ---- Read the order file ------------------------------------------------
    local srcs=() line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            continue
        fi
        if [[ ! -f "$line" ]]; then
            echo "Warning: skipping (not found): $line" >&2
            continue
        fi
        srcs+=("$line")
    done < "$order_file"

    local count=${#srcs[@]}
    if [[ $count -eq 0 ]]; then
        echo "No files to process." >&2
        return 1
    fi

    # ---- Reject duplicate entries -------------------------------------------
    local dups
    dups=$(printf '%s\n' "${srcs[@]}" | sort | uniq -d)
    if [[ -n "$dups" ]]; then
        echo "Error: the order file lists these files more than once:" >&2
        echo "$dups" | sed 's/^/  /' >&2
        return 1
    fi

    # ---- Build the plan -----------------------------------------------------
    local last=$((start_index + count - 1))
    local width=${#last}
    if [[ $width -lt 3 ]]; then
        width=3
    fi

    local dests=()
    local i src base ext dir name
    for ((i = 0; i < count; i++)); do
        src="${srcs[$i]}"
        base="${src##*/}"
        ext=""
        if [[ "$base" == *.* ]]; then
            ext=".$(printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]')"
        fi

        if [[ -n "$copy_dir" ]]; then
            dir="${copy_dir%/}"
        else
            dir=$(dirname "$src")
        fi

        printf -v name "%s_%0${width}d%s" "$prefix" $((start_index + i)) "$ext"
        dests+=("$dir/$name")
    done

    # ---- Pre-flight: look for collisions with files outside the batch -------
    # Files are identified by device:inode so that case-insensitive
    # filesystems (the macOS default) don't cause false alarms.
    local src_ids s
    src_ids=$(for s in "${srcs[@]}"; do stat -f '%d:%i' "$s"; done)

    local conflicts=() d id
    for ((i = 0; i < count; i++)); do
        d="${dests[$i]}"
        if [[ -e "$d" ]]; then
            if [[ -n "$copy_dir" ]]; then
                conflicts+=("$d")
            else
                id=$(stat -f '%d:%i' "$d")
                if ! grep -qxF -- "$id" <<< "$src_ids"; then
                    conflicts+=("$d")
                fi
            fi
        fi
    done

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "Error: these targets already exist and are not part of" >&2
        echo "this batch:" >&2
        printf '  %s\n' "${conflicts[@]}" >&2
        echo "Nothing was changed. Pick a different prefix/start value" >&2
        echo "or move those files." >&2
        return 1
    fi

    local verb="Renamed" past="renamed"
    if [[ -n "$copy_dir" ]]; then
        verb="Copied"
        past="copied"
    fi

    # ---- Dry run ------------------------------------------------------------
    if [[ "$dry_run" == "1" ]]; then
        for ((i = 0; i < count; i++)); do
            echo "${srcs[$i]} -> ${dests[$i]}"
        done
        echo "Dry run: $count file(s) would be $past. No files were changed."
        return 0
    fi

    # ---- Copy mode ----------------------------------------------------------
    if [[ -n "$copy_dir" ]]; then
        if ! mkdir -p "$copy_dir"; then
            echo "Error: could not create $copy_dir" >&2
            return 1
        fi
        for ((i = 0; i < count; i++)); do
            if ! cp -p -n "${srcs[$i]}" "${dests[$i]}" \
                || [[ ! -f "${dests[$i]}" ]]; then
                echo "Error: failed to copy" \
                     "${srcs[$i]} -> ${dests[$i]}" >&2
                return 1
            fi
            echo "$verb: ${srcs[$i]} -> ${dests[$i]}"
        done
        return 0
    fi

    # ---- In-place: phase 1, move everything to unique temporary names -------
    local tmps=() tmp j
    for ((i = 0; i < count; i++)); do
        tmp="$(dirname "${srcs[$i]}")/.fairu_tmp_$$_$i"
        if [[ -e "$tmp" ]] || ! mv -n "${srcs[$i]}" "$tmp" \
            || [[ ! -e "$tmp" ]]; then
            echo "Error: could not move ${srcs[$i]} aside. Rolling back." >&2
            for ((j = 0; j < i; j++)); do
                mv -n "${tmps[$j]}" "${srcs[$j]}" || true
            done
            return 1
        fi
        tmps+=("$tmp")
    done

    # ---- In-place: phase 2, move temporary names to final names -------------
    for ((i = 0; i < count; i++)); do
        if ! mv -n "${tmps[$i]}" "${dests[$i]}" || [[ -e "${tmps[$i]}" ]]; then
            echo "Error: failed to move ${tmps[$i]} -> ${dests[$i]}" >&2
            echo "These files are still under temporary names:" >&2
            for ((j = i; j < count; j++)); do
                echo "  ${tmps[$j]}  (originally ${srcs[$j]})" >&2
            done
            return 1
        fi
        echo "$verb: ${srcs[$i]} -> ${dests[$i]}"
    done
}