# Photos Organizer

Native macOS app (Swift + SwiftUI) that scans a folder recursively, lets you pick which file
types to include, and then copies or moves the matching files into an output folder, or deletes
them. Copied and moved files are renamed from their capture date:

```
<output>/YYYY/MM/YYYY-MM-DD-T-HH-MM-SS.ext        (default folder structure)
```

For example, a JPG taken on 6 Dec 2014 at 4:22 PM goes to `<output>/2014/12/2014-12-06-T-16-22-00.jpg`.

## Install

Open `PhotosOrganizer-<version>.dmg` and drag **Photos Organizer** to **Applications**.

Builds that aren't signed with a Developer ID are blocked by Gatekeeper the first time on other
Macs: right-click the app → **Open**, or allow it in *System Settings → Privacy & Security*.

Requires macOS 14 (Sonoma) or later.

## Use

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
| JPG, PNG, TIFF, WebP, HEIC/HEIF and RAW (CR2, CR3, NEF, ARW, DNG, ORF, RW2, RAF, …) | EXIF `DateTimeOriginal` → `DateTimeDigitized` → `DateTime` (ImageIO) |
| MOV, MP4, M4V, 3GP | Apple's creation date (local time where it was recorded), else the `mvhd` creation time, stored in UTC and converted to your time zone |
| Other videos (AVI, MKV, MTS, …) | Creation date, when AVFoundation can read the file |
| Anything else / no metadata | File date (the earlier of creation and modification time), when *Use file date…* is ticked. Otherwise the file is skipped |

## Collisions and duplicates

- Different files with the same timestamp (for example burst shots) get a suffix: `2014-12-06-T-16-22-00-1.jpg`, `-2`, …
- A file whose content is byte-identical to one already at the destination is reported as
  *Duplicate (skipped)*, so running the app twice on the same folder won't create copies.
- Files already inside the output folder are never processed again.

## Development

Needs Swift 6 (Xcode or just the Command Line Tools: `xcode-select --install`).

```bash
make run     # swift run PhotosOrganizer
make test    # swift test
make app     # dist/Photos Organizer.app
make dmg     # dist/PhotosOrganizer-<version>.dmg
```

The version comes from the `VERSION` file. Packaging options (environment variables):

| Variable | Effect |
|----------|--------|
| `SIGN_IDENTITY` | Codesign identity, e.g. `"Developer ID Application: Name (TEAMID)"`. Default `-` (ad-hoc). |
| `NOTARY_PROFILE` | `notarytool` keychain profile; notarizes and staples the DMG. |
| `UNIVERSAL=1` | Builds for Apple silicon and Intel (needs Xcode). |

`make icon` regenerates `packaging/AppIcon.icns` from `scripts/make-icon.swift`.

## Architecture decisions

See [`adrs/`](adrs/) for the reasoning behind the design. [ADR 0003](adrs/0003-native-swift-macos-app.md)
covers the move from Python/Qt to Swift.

## Project layout

```
Package.swift
Sources/PhotosOrganizerCore/       # no UI; unit-tested
  FileScanner.swift                # recursive folder scan
  CaptureDate.swift                # EXIF / video / file date extraction
  QuickTimeMovieHeader.swift       # MOV/MP4 mvhd creation time
  LocalDateTime.swift              # wall-clock date used for names
  Organizer.swift                  # destination naming, folder layouts, collisions, copy/move/delete
Sources/PhotosOrganizer/           # SwiftUI app
  PhotosOrganizerApp.swift         # entry point
  AppModel.swift                   # window state, scan/organize tasks, settings
  ContentView.swift                # main window, file-type filter, file table, log
  Dialogs.swift                    # folder pickers and confirmations
Tests/PhotosOrganizerCoreTests/
packaging/                         # Info.plist template and app icon
scripts/                           # build-app.sh, make-dmg.sh, make-icon.swift
```
