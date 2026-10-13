# ADR 0002: Delete action and configurable folder structure

- **Status:** Accepted
- **Date:** 2026-10-13
- **Deciders:** Project owner
- **Builds on:** [ADR 0001](0001-photos-organizer-architecture.md). It extends decisions §4
  (naming), §5 (safety: copy by default, move is opt-in) and §7 (architecture); everything else
  in ADR 0001 still applies.

## Context

After the first version, two new needs came up:

1. **Delete the matched files.** Next to *Copy* and *Move*, the user wants an action that removes
   every file that matches the selected extensions, for example to clean out `.AAE` sidecars,
   `.THM` thumbnails or leftovers after a library has been organized.
2. **Choose how deep the folders go.** ADR 0001 always used `YYYY/MM`. Some libraries are better
   grouped only by year (few photos per month), others by day (events, heavy shooters).

### Forces

- Delete is the most dangerous operation in the app. ADR 0001 made safety a core principle:
  never overwrite, copy by default, preview first.
- Deleting doesn't need capture dates, an output folder, a folder structure or the date
  fallback. Reading metadata for files we're about to delete would only waste time.
- The `Organizer` core must stay Qt-free and unit-testable (ADR 0001 §7).
- The file-name pattern (`YYYY-MM-DD-T-HH-MM-SS.ext`) is unchanged; only the folders change.

## Decision

### 1. Three actions: `Action` replaces `TransferMode`

```python
class Action(StrEnum):
    COPY = "copy"
    MOVE = "move"
    DELETE = "delete"
```

- The UI shows three radio buttons under **Action:**: *Copy files (keep originals)*, *Move files*
  and *Delete matched files*. Copy is still the default.
- `TransferMode` was renamed to `Action`, because deleting isn't a transfer. QSettings now stores the
  choice under the `action` key. The old `mode` key is ignored, so users start again on Copy.

### 2. Delete goes to the Trash by default; permanent delete is opt-in

- **Default: move to the system Trash** using **[Send2Trash](https://pypi.org/project/Send2Trash/)**
  (new dependency). The user can recover files from the Trash/Recycle Bin, which covers the most
  likely mistake: a wrong extension filter.
- **Opt-in: "Permanently (skip Trash)"** checkbox, which uses `Path.unlink()`.
  - It is only visible while *Delete* is selected, it is cleared when the user switches to another
    action, and it is **never saved** in QSettings, so every session starts on the safer setting.
- **Confirmation is always required** before a real delete. The dialog shows the number of files
  and their total size, and its default button is **No**. Permanent delete uses a critical icon
  and states that it cannot be undone.
- **Preview works for delete:** it lists every file with *Planned*, plus "Will be moved to Trash"
  or "Will be deleted permanently", without touching anything.
- New statuses: `Status.TRASHED` ("Moved to Trash") and `Status.DELETED` ("Deleted"). Failures
  (permissions, volumes without a Trash, files already gone) are reported per file as `Status.ERROR`
  and never stop the run.
- In delete mode the organizer **does not read metadata** and has no output folder
  (`Organizer(output_dir=None, action=Action.DELETE)`). Copy and move still require an output
  folder; passing `None` raises `ValueError`.
- After a run that removed files from the source (move, trash or permanent delete), the source
  folder is rescanned automatically. This extends the rescan-after-move behaviour.
- The UI **disables** the output folder, the folder structure and the date-fallback controls while
  *Delete* is selected, and the main button reads **Delete** instead of **Organize**.

**Alternatives considered**

- *Permanent delete only (`os.remove`)*: simplest, but one wrong filter destroys photos with
  no way back. Rejected for the default.
- *Qt's `QFile.moveToTrash()`*: no extra dependency, but it would bring Qt into the core
  `organizer` module and break ADR 0001 §7. Send2Trash is small, pure Python and cross-platform.
- *Delete only files that were already copied (a "verify then delete" mode)*: useful, but a
  different feature. Kept as a follow-up; *Move* already covers "organize and remove the source".
- *Type the number of files to confirm*: stronger friction, but heavier than needed with Trash as
  the default. We can revisit it for permanent delete.

### 3. Configurable folder structure: `FolderLayout`

```python
class FolderLayout(StrEnum):
    YEAR = "year"                      # <output>/2014/2014-12-06-T-16-22-00.jpg
    YEAR_MONTH = "year/month"          # <output>/2014/12/2014-12-06-T-16-22-00.jpg   (default)
    YEAR_MONTH_DAY = "year/month/day"  # <output>/2014/12/06/2014-12-06-T-16-22-00.jpg
```

- Shown as a **Folder structure** drop-down, remembered in QSettings (`layout` key). The default
  stays **Year / Month**, so existing behaviour and ADR 0001's example are unchanged.
- `build_destination(..., layout=FolderLayout.YEAR_MONTH)` builds the path from
  `FolderLayout.folders(taken_at)`. The `Organizer` passes its layout through, so collision
  suffixes (`-1`, `-2`) and duplicate detection work the same in every layout.
- The output-folder placeholder shows a live example path for the selected layout.
- Only a fixed set of layouts is offered, not a free-form pattern. Every option is guaranteed
  to produce valid, sortable paths, and the UI stays simple.

### 4. Implementation notes

- `Organizer.__init__(output_dir, action, use_filesystem_fallback, dry_run, layout, permanent_delete)`.
  `OrganizeWorker` forwards the same parameters.
- `MainWindow` routes *Preview* / *Organize* to `_start_delete` or the copy/move path. Both
  share `_run_organize`, which starts the worker thread.
- **Qt pitfall found while building this:** `QComboBox.currentData()` returns a `StrEnum` item as
  a plain `str`, so `_layout()` wraps it in `FolderLayout(...)`.
- Tests grew from 16 to 25. They cover the three layouts, delete dry run, Trash (with
  `send2trash` monkeypatched, so the suite never touches the real Trash), permanent delete,
  per-file errors and the required output folder. A headless GUI run also checked both features
  from start to finish.

## Consequences

### Positive

- One app now handles both organizing and cleaning up a library, with the same extension filter
  and the same preview → confirm → run flow.
- Deletes are recoverable by default. Permanent delete takes three deliberate steps: choose
  Delete, tick *Permanently*, then answer Yes on a dialog whose default is No.
- Users can choose the grouping that fits their library without changing file names.
- Delete is fast on large folders because it skips metadata extraction.

### Negative / risks

- **Delete acts on every file in the list.** It doesn't check whether a file was organized first.
  A user who wants "organize, then delete the originals" should use *Move*.
- **The Trash is per volume.** On external drives and network shares, Send2Trash uses that
  volume's trash folder or may fail (for example on SMB shares without one). Failures show as
  per-file errors; the user can then opt into permanent delete.
- Files in the Trash still use disk space until the user empties it.
- Running the tool again with a **different layout** on the same output folder creates a second
  tree (for example `2014/12/...` and `2014/12/06/...`). Duplicate detection only compares the
  destination path for the current layout, so the same photo can exist in both trees.
- Adds a sixth runtime dependency (Send2Trash).

### Follow-ups (not yet decided)

- A "delete only if a verified copy exists in the output" option.
- Type-the-count confirmation for permanent delete of large selections.
- A tool to re-layout an existing output folder (for example from `YYYY/MM` to `YYYY/MM/DD`).
- Free-form naming/folder patterns (already listed in ADR 0001), now that layouts are an
  abstraction.
