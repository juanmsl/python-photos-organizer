"""Background workers so scanning and organizing never block the UI thread."""

from __future__ import annotations

from collections import Counter
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from photos_organizer.organizer import Action, FolderLayout, Organizer
from photos_organizer.scanner import FileEntry, scan_folder


class ScanWorker(QObject):
    finished = Signal(list)  # list[FileEntry]
    failed = Signal(str)

    def __init__(self, root: Path) -> None:
        super().__init__()
        self._root = root
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    @Slot()
    def run(self) -> None:
        try:
            entries = scan_folder(self._root, should_cancel=lambda: self._cancelled)
        except Exception as error:  # surfaced to the user, not swallowed
            self.failed.emit(str(error))
            return
        self.finished.emit(entries)


class OrganizeWorker(QObject):
    progress = Signal(int, int)       # done, total
    item_done = Signal(int, object)   # row, OrganizeResult
    finished = Signal(object, bool)   # Counter[Status], cancelled

    def __init__(
        self,
        rows: list[tuple[int, FileEntry]],
        output_dir: Path | None,
        action: Action,
        use_filesystem_fallback: bool,
        dry_run: bool,
        layout: FolderLayout,
        permanent_delete: bool,
    ) -> None:
        super().__init__()
        self._rows = rows
        self._organizer = Organizer(
            output_dir, action, use_filesystem_fallback, dry_run, layout, permanent_delete
        )
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    @Slot()
    def run(self) -> None:
        summary: Counter = Counter()
        total = len(self._rows)
        for done, (row, entry) in enumerate(self._rows, start=1):
            if self._cancelled:
                break
            result = self._organizer.process(entry.path)
            summary[result.status] += 1
            self.item_done.emit(row, result)
            self.progress.emit(done, total)
        self.finished.emit(summary, self._cancelled)
