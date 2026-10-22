# ADR 0003: Rewrite as a native Swift/SwiftUI macOS app distributed as a DMG

- **Status:** Accepted
- **Date:** 2026-10-21
- **Deciders:** Project owner
- **Builds on:** [ADR 0001](0001-photos-organizer-architecture.md) and
  [ADR 0002](0002-delete-action-and-folder-structure.md). It replaces their *implementation*
  decisions (language, UI toolkit, libraries, packaging). Their *behaviour* decisions still apply:
  naming, folder layouts, collisions and duplicates, copy by default, preview, Trash by default,
  confirmations, hidden-file rules and remembered settings.

## Context

ADR 0001 listed "packaging as a standalone macOS app" as a follow-up. The owner now wants to
install the tool like any other Mac app, from a `.dmg`.

### Forces

- The app is only used on macOS. Cross-platform support, the main reason for Qt, isn't needed.
- Bundling Python + PySide6 (PyInstaller or Briefcase) adds roughly 100–200 MB (ADR 0001,
  *Negative / risks*), is slow to start, and needs every native library re-signed for notarization.
- macOS already reads capture dates natively: ImageIO handles JPEG, PNG, TIFF, WebP, HEIC and
  the camera RAW formats Apple supports; AVFoundation reads QuickTime/MP4 metadata, including
  Apple's `com.apple.quicktime.creationdate`, which hachoir couldn't (ADR 0001, *Negative / risks*).
- The development machine has the Swift 6.1 **Command Line Tools only**, no Xcode.

## Decision

### 1. Swift 6 + SwiftUI, built with Swift Package Manager

- `Package.swift` with three targets, mirroring ADR 0001 §7:

  ```
  Sources/PhotosOrganizerCore/   # no SwiftUI/AppKit, unit-tested
    FileScanner.swift            # recursive scan → [FileEntry]          (was scanner.py)
    CaptureDate.swift            # capture date + DateSource             (was metadata.py)
    QuickTimeMovieHeader.swift   # mvhd creation time reader
    LocalDateTime.swift          # time-zone-free wall-clock date
    MediaTypes.swift             # photo / RAW / video extension sets
    Organizer.swift              # Action, FolderLayout, Status, Organizer (was organizer.py)
  Sources/PhotosOrganizer/       # SwiftUI app                          (was gui/*)
    PhotosOrganizerApp.swift, AppModel.swift, ContentView.swift, Dialogs.swift
  Tests/PhotosOrganizerCoreTests/  # swift-testing                       (was tests/*.py)
  ```

- SwiftPM instead of an Xcode project: it builds with the Command Line Tools alone, and the
  project stays plain text (no `.pbxproj` merge conflicts).
- Minimum macOS **14 (Sonoma)**, for the `@Observable` macro and SwiftUI `Table`.

**Alternatives considered**

- *Keep Python, bundle with PyInstaller/Briefcase*: least work, but a heavy, slow-starting bundle
  that is awkward to sign and notarize.
- *Xcode project*: the usual route for Mac apps, but needs a full Xcode install and is harder to
  review in diffs. It can be generated later if needed (Xcode opens `Package.swift` directly).
- *AppKit only*: more control over the table, but much more code than SwiftUI for this UI.

### 2. Metadata with Apple frameworks, no third-party dependencies

| Media | Reader | Fields, in order |
|-------|--------|------------------|
| Photos and RAW | **ImageIO** (`CGImageSourceCopyPropertiesAtIndex`) | EXIF `DateTimeOriginal` → `DateTimeDigitized` → TIFF `DateTime` |
| MOV, MP4, M4V, 3GP, 3G2 | **AVFoundation**, then our **`mvhd` reader** | `com.apple.quicktime.creationdate` (local time as recorded) → `moov/mvhd` creation time (UTC → computer's time zone) |
| Other videos (AVI, MKV, MTS, WMV, MPG…) | **AVFoundation** | asset creation date, when AVFoundation can open the file |
| Anything else / nothing found | File system | earlier of creation and modification date (fallback, optional) |

- The lenient EXIF date regex, the "year ≥ 1900" rule for EXIF and the "year ≥ 1970" rule for
  videos are unchanged.
- **Dates are `LocalDateTime`** (year … second, no time zone), the equivalent of Python's naive
  `datetime`. Names and folders come from these components directly, so DST or time-zone rules
  can't shift a photo by an hour.
- **Improvement over ADR 0001:** iPhone videos are now named from the local time *where they were
  recorded* (Apple's creation date carries its own offset), not from UTC converted with the
  current machine's zone. Videos without that tag keep the old behaviour.
- The `mvhd` reader walks box headers with `FileHandle`, so multi-GB videos are never loaded
  into memory. It's ours (about 70 lines) because AVFoundation doesn't reliably expose `mvhd`
  for files without Apple metadata.

### 3. Same behaviour, native building blocks

| ADR 0001/0002 decision | Python | Swift |
|------------------------|--------|-------|
| Copy keeps timestamps | `shutil.copy2` | `FileManager.copyItem` |
| Move (also across volumes) | `shutil.move` | `FileManager.moveItem` |
| Byte-identical duplicates | `filecmp.cmp(shallow=False)` | `FileManager.contentsEqual` |
| Delete to Trash | Send2Trash | `FileManager.trashItem` (injectable, so tests never touch the real Trash) |
| Permanent delete | `Path.unlink()` | `FileManager.removeItem` |
| Remembered settings | `QSettings` | `UserDefaults`, same keys (`output_dir`, `action`, `layout`, `fallback`, `source_dir`); *Permanently* is still never saved |
| Delete confirmation, default **No** | `QMessageBox` | `NSAlert` with Return mapped to *No* (SwiftUI alerts can't choose the default button) |

### 4. Concurrency replaces QThread workers

- `Organizer` is an **actor**: file I/O and metadata reads run off the main thread, and its
  "names already used in this run" table can't be raced.
- The scan runs in a detached task. *Cancel* cancels the task, and the scanner and the organize
  loop check `Task.isCancelled`, so cancellation stays cooperative.
- `AppModel` is `@MainActor @Observable`. Results reach the table in **batches every 100 ms**
  instead of once per file, so large runs don't re-render the table thousands of times.
- The ADR 0001 rule about lambdas and Qt threads no longer applies; Swift 6's strict concurrency
  checking now catches that class of bug at compile time.

### 5. Packaging: `.app` bundle and `.dmg` from shell scripts

- `scripts/build-app.sh` builds in release mode and assembles `dist/Photos Organizer.app`
  (`Info.plist` from `packaging/`, icon, version from `VERSION`, build number from the commit count).
- `scripts/make-dmg.sh` creates `dist/PhotosOrganizer-<version>.dmg` with `hdiutil`, containing the
  app and an *Applications* shortcut for drag-to-install.
- **Signing:** ad-hoc by default (`SIGN_IDENTITY=-`). With a *Developer ID Application* identity
  the scripts enable the hardened runtime and timestamps; with `NOTARY_PROFILE` set, the DMG is
  notarized and stapled with `notarytool`.
- The app is **not sandboxed**: it must read and write arbitrary folders and volumes the user
  picks. `Info.plist` declares usage descriptions for Desktop, Documents, Downloads, removable
  and network volumes, which macOS shows the first time those are accessed.
- The icon is generated by `scripts/make-icon.swift` and committed as `packaging/AppIcon.icns`.
- `make build | test | run | app | dmg | icon | clean` wraps the common commands.

## Consequences

### Positive

- The app is installed from a DMG like any Mac app. It is about **2 MB** compressed (vs. an
  estimated 100–200 MB with bundled Python + Qt) and starts instantly.
- No third-party dependencies at all. HEIC and RAW support comes with macOS and improves with OS
  updates.
- iPhone video names now use the time zone the video was recorded in.
- The core is still UI-free and covered by the same test cases (ported to swift-testing), plus new
  ones for the `mvhd` reader, invalid dates and the `-N` suffix without an extension.

### Negative / risks

- **macOS only, 14+.** Windows/Linux support (implicitly possible with Qt) is gone.
- **Ad-hoc–signed builds trigger Gatekeeper** on other Macs ("cannot verify the developer"): users
  must right-click → *Open* or allow it in *System Settings → Privacy & Security*. Distributing to
  others properly needs an Apple Developer account for Developer ID signing and notarization.
- **Video coverage changed.** hachoir read AVI and MKV headers; AVFoundation usually can't open
  those, so they now fall back to the file date (or are skipped without the fallback). MP4/MOV,
  by far the most common, are better covered than before.
- **RAW coverage follows Apple's RAW support.** Very new cameras may lack a date until macOS
  supports them (ExifRead used to read EXIF from almost any TIFF-based RAW).
- Without Xcode, builds are for the host architecture only (`UNIVERSAL=1` needs Xcode), so the
  DMG built on Apple silicon doesn't run on Intel Macs.
- The Python version and its tests are removed; ADR 0001/0002 remain the reference for the
  behaviour.

### Follow-ups (not yet decided)

- Developer ID signing + notarization in CI (for example GitHub Actions on a macOS runner).
- Universal (arm64 + x86_64) builds.
- A fallback EXIF parser for RAW formats ImageIO can't read, or an optional `exiftool` backend
  (already in ADR 0001's follow-ups) for AVI/MKV.
- Auto-update (for example Sparkle).
- A headless CLI target reusing `PhotosOrganizerCore` (ADR 0001's follow-up, now a few lines with SwiftPM).
