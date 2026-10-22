# ADR 0001: Photos Organizer architecture and core decisions

- **Status:** Accepted. Implementation superseded by [ADR 0003](0003-native-swift-macos-app.md) (Swift rewrite); the behaviour decisions still apply.
- **Date:** 2026-10-11
- **Deciders:** Project owner

## Context

Personal photo and video libraries pile up across many folders (phone exports, camera cards,
backups) with names that say nothing useful (`IMG_0001.JPG`, `DSC_1234.NEF`, `VID_...mp4`).
We want a local tool that brings them into one predictable structure based on **when each
file was captured**.

### Requirements

1. An **interactive desktop app** written in **Python 3**.
2. The user selects a **source folder**. Every file in it, **including all sub-folders**, is listed.
3. The user can **filter by file extension**.
4. Matching files are written to a separate **output folder**, renamed from their
   **EXIF/metadata capture date** with the pattern `yyyy-MM-dd-T-hh-mm-ss` (24-hour clock).
5. Each file goes inside a **year folder and a month folder**:

   ```
   <output>/YYYY/MM/YYYY-MM-DD-T-HH-MM-SS.ext
   ```

   Example: a JPG taken on 6 Dec 2014 at 4:22 PM → `<output>/2014/12/2014-12-06-T-16-22-00.jpg`.

### Forces and constraints

- Libraries mix formats: JPEG, PNG, TIFF, WebP, **HEIC** (iPhone), camera **RAW** (CR2, CR3,
  NEF, ARW, DNG, ORF, RW2, RAF…) and **videos** (MP4, MOV, 3GP, AVI, MKV…). No single Python
  library reads capture dates from all of them.
- Folders can hold tens of thousands of files, so the UI must stay responsive while it scans,
  reads metadata and copies files.
- Losing photos is unacceptable. The default behaviour must not destroy or overwrite anything.
- Some files have no usable metadata (screenshots, messaging-app exports, stripped EXIF).
- Two different files can share the same capture second (burst shots), and the tool may be
  run several times over the same libraries.
- Development machine: macOS, Python 3.14 (via pyenv).

## Decision

### 1. UI toolkit: Qt via PySide6 (`PySide6-Essentials`)

- Native-looking, mature desktop UI with a real table/model view, which suits listing large
  numbers of files, plus first-class threading (`QThread`).
- PySide6 is the official Qt for Python binding (LGPL).
- We depend on **`PySide6-Essentials`** (QtCore/QtGui/QtWidgets) rather than the full `PySide6`
  meta-package. The full package also installs WebEngine, PDF and other add-ons we don't use.

**Alternatives considered**

- *Tkinter*: no extra dependency, but a weak table widget and dated look; poor fit for large lists.
- *PyQt6*: equivalent capability, but GPL/commercial licensing.
- *Web UI (Flask/Electron-style)*: heavier and not a "desktop app" in the requested sense.

### 2. Metadata extraction: one library per media family

| Media | Library | Tags / field used |
|-------|---------|-------------------|
| JPEG, PNG, TIFF, WebP | **Pillow** (fallback: ExifRead) | `DateTimeOriginal` → `DateTimeDigitized` → `DateTime` |
| HEIC / HEIF | **Pillow + pillow-heif** (registers a HEIF opener for Pillow) | same EXIF tags |
| RAW formats | **ExifRead** (fallback: Pillow) | same EXIF tags |
| Videos | **hachoir** | `date_time_original`, then `creation_date` |

- All of these are pure Python or ship wheels, so no external binaries are needed
  (no `exiftool`, no `ffmpeg`).
- EXIF dates are parsed with a lenient regex (`YYYY:MM:DD HH:MM:SS`, also `-` / `T`
  separators, trailing NUL bytes). Values with a year before 1900 are rejected. This catches
  blank dates such as `0000:00:00 00:00:00`.
- **Video time zone:** QuickTime-based containers (MP4, MOV, M4V, 3GP) store creation time in
  **UTC**, so we convert it to the computer's local time zone. Dates before 1970 are rejected
  as "unset" (QuickTime's zero date decodes as 1904-01-01).

**Alternative considered:** shelling out to `exiftool`. It would be the most complete reader,
but it adds a Perl/binary dependency the user must install separately. We may revisit this if
format coverage becomes a problem.

### 3. Date fallback when metadata is missing

- Optional and **on by default** (checkbox *"Use file date when there is no EXIF/metadata date"*).
- Uses the file-system date: the earlier of creation time (`st_birthtime`, available on macOS)
  and modification time.
- When the fallback is off, files without a metadata date are **skipped** and reported as
  *No date (skipped)*.
- The UI shows each file's **Date source** (`EXIF`, `Video metadata`, `File date`), so the user
  can see which dates are trustworthy.

### 4. Naming, collisions and duplicates

- File name: `strftime("%Y-%m-%d-T-%H-%M-%S")` plus the **original extension in lower case**.
  `.JPG` becomes `.jpg`, and `.jpeg` stays `.jpeg`; extensions are not converted to each other.
- **Same timestamp, different content:** a numeric suffix is added, as in
  `2014-12-06-T-16-22-00-1.jpg`, `-2`, …
- **Byte-identical content** (`filecmp.cmp(shallow=False)`) already at the destination, or
  already assigned earlier in the same run: reported as *Duplicate (skipped)*. This makes
  re-running the tool on the same sources idempotent.
- Files that already live inside the output folder are excluded, so the tool never reprocesses
  its own output. The output folder may not be the same as the source folder.

### 5. Safety: copy by default, move is opt-in

- **Copy** (`shutil.copy2`, which preserves timestamps) is the default and leaves the sources untouched.
- **Move** must be selected explicitly and asks for confirmation before it starts.
- **Preview (dry run)** computes every date and destination without writing anything to disk.
- Nothing is ever overwritten; collisions always get a suffix or are skipped as duplicates.

### 6. Scanning

- Recursive `os.walk`, results sorted by relative path.
- Hidden files and folders (names starting with `.`) are skipped. This also removes macOS noise
  such as `.DS_Store` and `._*` AppleDouble files.
- The extension filter is built from the extensions actually found, with a count for each.
  Known photo, RAW and video extensions are pre-selected, and the *All / None / Media* buttons
  change the selection quickly.

### 7. Architecture: core logic separated from the UI

```
src/photos_organizer/
  scanner.py          # recursive scan → FileEntry list           (no Qt)
  metadata.py         # capture date + DateSource                 (no Qt)
  organizer.py        # destination naming, collisions, copy/move (no Qt)
  app.py              # QApplication entry point
  gui/main_window.py  # window, actions, settings (QSettings)
  gui/file_table.py   # QAbstractTableModel for the file list
  gui/workers.py      # ScanWorker / OrganizeWorker running in QThreads
tests/test_organizer.py
```

- The core modules don't import Qt, so they can be unit-tested with pytest and reused later
  (for example by a CLI).
- `Organizer` processes one file at a time and returns an `OrganizeResult` (status, date,
  date source, destination, message). That makes progress reporting, cancellation and per-row
  status in the UI straightforward.
- Long-running work runs in **worker objects moved to a `QThread`**. Workers communicate only
  through signals. UI controls are disabled while a worker runs, and *Cancel* is cooperative.
- **Threading rule:** worker signals must be connected to **bound methods of objects that live
  in the UI thread**, never to `lambda`s. PySide6 runs a lambda slot directly in the emitting
  (worker) thread. When an early version updated the progress bar from a lambda, the app
  segfaulted.
- The last output folder, transfer mode and fallback option are remembered in `QSettings`.

### 8. Packaging and tooling

- `pyproject.toml` (setuptools, `src/` layout), `requires-python >= 3.11` (we use `StrEnum`).
- GUI entry point `photos-organizer` → `photos_organizer.app:main`; also runnable with
  `python -m photos_organizer`.
- `requirements.txt` / `requirements-dev.txt` mirror the dependencies for pip-only workflows.
- Tests use **pytest**. Fixtures generate JPEGs with real EXIF through Pillow, so no binary test
  assets need to be committed.

## Consequences

### Positive

- One self-contained `pip install` covers photos, HEIC, RAW and common video formats, with no
  external tools.
- The default behaviour is safe: copy, never overwrite, dry-run preview, duplicates detected.
  Re-running the tool is harmless.
- The UI stays responsive on large libraries, and each file's outcome is visible in the table.
- The core logic is testable without a display. It was verified by 16 unit tests and a headless
  (`QT_QPA_PLATFORM=offscreen`) end-to-end run.

### Negative / risks

- **Video time zones are approximate.** UTC is converted using the *current machine's* time zone
  rules, so videos recorded while travelling can be off by the zone difference. Apple's
  `com.apple.quicktime.creationdate` (local time plus offset) is not read by hachoir.
- **EXIF dates carry no time zone.** Photos keep the camera clock's wall time; a wrongly set camera
  clock produces wrong names.
- **The file-system fallback can be misleading.** Copies and downloads reset dates. That is why the
  fallback is labelled in the UI and can be turned off.
- Duplicate detection compares full contents, which costs extra I/O only when names collide.
- Metadata coverage depends on Pillow, ExifRead and hachoir. Unusual RAW or video variants may come
  back with no date.
- Qt adds roughly 100–200 MB to the environment and to any future bundled app.

### Follow-ups (not yet decided)

- Optional `exiftool` backend for better coverage and time-zone-aware video dates.
- Configurable naming pattern and folder layout.
- A headless CLI that reuses `scanner` / `organizer`.
- Packaging as a standalone macOS app (for example PyInstaller or Briefcase).
- Content-hash duplicate detection across the whole output, not just on name collisions.
