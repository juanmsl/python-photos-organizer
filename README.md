# Photos Organizer

Desktop app (Python 3 + Qt/PySide6) that scans a folder recursively, lets you pick which file
types to include, and then copies or moves the matching files into an output folder, or deletes
them. Copied and moved files are renamed from their capture date:

```
<output>/YYYY/MM/YYYY-MM-DD-T-HH-MM-SS.ext        (default folder structure)
```

For example, a JPG taken on 6 Dec 2014 at 4:22 PM goes to `<output>/2014/12/2014-12-06-T-16-22-00.jpg`.

## Setup

Requires Python 3.11+.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"        # or: pip install -r requirements-dev.txt
```

## Run

```bash
photos-organizer               # installed entry point
# or
python -m photos_organizer
```

1. **Browse…** to choose the source folder. Every file under it (sub-folders included) is listed.
2. In **File types**, tick the extensions to process. Photo, RAW and video types are pre-selected.
3. Choose an **Output folder** and a **Folder structure**:

   | Folder structure | Example |
   |------------------|---------|
   | Year | `<output>/2014/2014-12-06-T-16-22-00.jpg` |
   | Year / Month (default) | `<output>/2014/12/2014-12-06-T-16-22-00.jpg` |
   | Year / Month / Day | `<output>/2014/12/06/2014-12-06-T-16-22-00.jpg` |

4. Pick an **Action**:
   - **Copy** (default): the originals stay where they are.
   - **Move**: asks for confirmation first.
   - **Delete matched files**: removes every file in the list. Files go to the **Trash** unless
     *Permanently (skip Trash)* is ticked. No output folder is needed, and you are always asked to
     confirm, with the default answer set to *No*.
5. **Preview** shows what would happen (destinations, or which files would be deleted) without
   touching anything. **Organize** / **Delete** carries it out.

## How the date is found

| File type | Source |
|-----------|--------|
| JPG, PNG, TIFF, WebP, HEIC/HEIF | EXIF `DateTimeOriginal` → `DateTimeDigitized` → `DateTime` (Pillow, then ExifRead) |
| RAW (CR2, CR3, NEF, ARW, DNG, ORF, RW2, RAF, …) | Same EXIF tags (ExifRead first, then Pillow) |
| Video (MP4, MOV, M4V, 3GP, AVI, MKV, …) | Container creation date (hachoir). MP4/MOV store it in UTC, so it is converted to your local time zone |
| Anything else / no metadata | File date (creation time on macOS, otherwise modification time), when *Use file date…* is ticked. Otherwise the file is skipped |

## Collisions and duplicates

- Different files with the same timestamp (for example burst shots) get a suffix: `2014-12-06-T-16-22-00-1.jpg`, `-2`, …
- A file whose content is byte-identical to one already at the destination is reported as
  *Duplicate (skipped)*, so running the app twice on the same folder won't create copies.
- Files already inside the output folder are never processed again.

## Tests

```bash
pytest
```

## Architecture decisions

See [`adrs/`](adrs/) for the reasoning behind the design.

## Project layout

```
src/photos_organizer/
  app.py              # QApplication entry point
  scanner.py          # recursive folder scan
  metadata.py         # EXIF / video date extraction
  organizer.py        # destination naming, folder layouts, collisions, copy/move/delete
  gui/main_window.py  # main window
  gui/file_table.py   # table model for the file list
  gui/workers.py      # background threads for scan/organize
tests/
```
