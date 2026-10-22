# fairu

A small bash tool for cleaning up photos and videos imported from a phone or
camera. It sorts files (by name or creation date) and renames them to a clean,
numbered sequence like `img_001.jpg`, `img_002.heic`, and so on.

Renaming is **collision-safe**: fairu never overwrites a file, and if it
detects a conflict it stops before changing anything.

## Requirements

- macOS (uses `stat -f`, which is the BSD/macOS form)
- The bash that ships with macOS (3.2) is fine

## Install

```bash
git clone <this-repo-url> fairu
cd fairu
chmod +x fairu.sh
```

Keep `fairu.sh` and `functions.sh` in the same folder. Run the tool as
`./fairu.sh` (or add an alias; avoid symlinking `fairu.sh`, since the script
looks for `functions.sh` next to itself).

## Quick start

Rename every image in a folder to `img_001`, `img_002`, ... in name order:

```bash
./fairu.sh -d /path/to/photos -e image -m name -p img
```

Not sure about the result? Add `-n` for a dry run. It prints the plan and
changes nothing:

```bash
./fairu.sh -d /path/to/photos -e image -m name -p img -n
```

## Options

| Flag | Argument          | Description                                    |
|------|-------------------|------------------------------------------------|
| `-d` | `<directory>`     | Directory to search (not recursive). Default: current directory. |
| `-e` | `image` / `video` | File type to match. Default: both.             |
| `-m` | `name` / `creation` | How to sort. `creation` is oldest to newest. |
| `-o` | `<outfile>`       | Write the sorted list of paths to a file.      |
| `-i` | `<infile>`        | Read paths from a file and rename them.        |
| `-p` | `<prefix>`        | New name prefix. With `-m`, sorts and renames in one step. Default: `file`. |
| `-s` | `<number>`        | Number of the first file. Default: `1`.        |
| `-c` | `<directory>`     | Copy into this directory instead of renaming in place. |
| `-n` |                   | Dry run: print `old -> new` and change nothing. |

Matched extensions:

- **image**: `heic`, `png`, `jpg` (upper or lower case)
- **video**: `mov`, `mp4` (upper or lower case)

New extensions are always lowercased (`IMG_1234.JPG` becomes `img_001.jpg`).
Numbers are zero-padded to at least 3 digits, and widen automatically if you
have more than 999 files.

## Two ways to use it

### One shot

Sort and rename in a single command by passing `-m` together with `-p`:

```bash
./fairu.sh -d ~/Pictures/trip -e image -m creation -p trip -s 1
```

Add `-o order.txt` if you also want to keep a record of the order used.

### Two steps (edit the order by hand)

1. Write the sorted list to a file:

   ```bash
   ./fairu.sh -d ~/Pictures/trip -e image -m name -o order.txt
   ```

2. Optionally open `order.txt` and reorder or delete lines. Each line is one
   file path.

3. Rename using that list:

   ```bash
   ./fairu.sh -i order.txt -p trip -s 1
   ```

Files are numbered in the order they appear in `order.txt`. Only files listed
in it are renamed.

### Copy instead of rename

If you want to be extra careful, copy the renamed files into a new folder and
leave the originals untouched:

```bash
./fairu.sh -d ~/Pictures/trip -m creation -p trip -c ~/Pictures/trip_sorted
```

## How it keeps your files safe

- **Checks first, changes second.** Before moving anything, fairu builds the
  full plan and aborts (changing nothing) if a new name would overwrite a file
  that is not part of the batch, or if the order file lists a file twice.
- **Two-phase rename.** Files are first moved to hidden temporary names
  (`.fairu_tmp_*`), then to their final names. Files in the batch can never
  overwrite each other, so you can safely renumber a folder that already
  contains `img_001`, `img_002`, ... with no need for a high starting number.
- **No-clobber moves.** Every move uses `mv -n` and is verified afterward.
- **Rollback.** If something fails while moving files aside, they are put back.
  If it fails later, fairu lists any files still under temporary names along
  with their original paths.

Missing files in an order file are skipped with a warning.

## Notes

- Only the top level of the directory is searched, not subfolders.
- Extension matching is case-sensitive, but both cases of each supported
  extension are included.
- `-m` and `-i` cannot be combined. Use `-m` with `-p` for one shot, or `-i`
  on its own for a prepared order file.
- If you pass `-s`, `-c` or `-n` without `-p` or `-i`, fairu prints a note
  because there is nothing to rename.

## Examples

```bash
# List images in name order (just prints the paths)
./fairu.sh -d ~/Pictures/import -e image -m name

# Rename videos by creation date, starting at 100
./fairu.sh -d ~/Movies/import -e video -m creation -p clip -s 100

# Preview, then do it for real
./fairu.sh -d ~/Pictures/import -m creation -p img -n
./fairu.sh -d ~/Pictures/import -m creation -p img
```
