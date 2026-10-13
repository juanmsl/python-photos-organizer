"""Compute destinations and copy/move files into ``<output>/YYYY/MM/YYYY-MM-DD-T-HH-MM-SS.ext``,
or delete the matched files."""

from __future__ import annotations

import filecmp
import shutil
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import Path

from send2trash import send2trash

from photos_organizer.metadata import DateSource, get_capture_date

FILENAME_FORMAT = "%Y-%m-%d-T-%H-%M-%S"


class Action(StrEnum):
    COPY = "copy"
    MOVE = "move"
    DELETE = "delete"


class FolderLayout(StrEnum):
    YEAR = "year"
    YEAR_MONTH = "year/month"
    YEAR_MONTH_DAY = "year/month/day"

    @property
    def label(self) -> str:
        return {
            FolderLayout.YEAR: "Year (YYYY)",
            FolderLayout.YEAR_MONTH: "Year / Month (YYYY/MM)",
            FolderLayout.YEAR_MONTH_DAY: "Year / Month / Day (YYYY/MM/DD)",
        }[self]

    def folders(self, taken_at: datetime) -> tuple[str, ...]:
        parts = (f"{taken_at:%Y}", f"{taken_at:%m}", f"{taken_at:%d}")
        return parts[: {FolderLayout.YEAR: 1, FolderLayout.YEAR_MONTH: 2, FolderLayout.YEAR_MONTH_DAY: 3}[self]]


class Status(StrEnum):
    PLANNED = "Planned"
    COPIED = "Copied"
    MOVED = "Moved"
    TRASHED = "Moved to Trash"
    DELETED = "Deleted"
    DUPLICATE = "Duplicate (skipped)"
    NO_DATE = "No date (skipped)"
    ERROR = "Error"


@dataclass(slots=True)
class OrganizeResult:
    source: Path
    status: Status
    date: datetime | None = None
    date_source: DateSource | None = None
    destination: Path | None = None
    message: str = ""


def build_destination(
    output_dir: Path,
    taken_at: datetime,
    extension: str,
    index: int = 0,
    layout: FolderLayout = FolderLayout.YEAR_MONTH,
) -> Path:
    """``<output>/2014/12/2014-12-06-T-16-22-00.jpg``; ``index`` > 0 adds ``-1``, ``-2``... for same-second shots."""
    stem = taken_at.strftime(FILENAME_FORMAT)
    if index:
        stem = f"{stem}-{index}"
    return output_dir.joinpath(*layout.folders(taken_at), f"{stem}{extension.lower()}")


class Organizer:
    """Processes files one at a time, keeping track of names already used in this run.

    With ``Action.DELETE`` no metadata is read and ``output_dir`` is ignored: each file is sent
    to the system Trash, or removed for good when ``permanent_delete`` is set.
    """

    def __init__(
        self,
        output_dir: Path | None,
        action: Action = Action.COPY,
        use_filesystem_fallback: bool = True,
        dry_run: bool = False,
        layout: FolderLayout = FolderLayout.YEAR_MONTH,
        permanent_delete: bool = False,
    ) -> None:
        if action is not Action.DELETE and output_dir is None:
            raise ValueError("output_dir is required to copy or move files")
        self.output_dir = output_dir
        self.action = action
        self.use_filesystem_fallback = use_filesystem_fallback
        self.dry_run = dry_run
        self.layout = layout
        self.permanent_delete = permanent_delete
        # destination -> source it was assigned to, so dry runs detect collisions too.
        self._reserved: dict[Path, Path] = {}

    def process(self, source: Path) -> OrganizeResult:
        if self.action is Action.DELETE:
            return self._delete(source)
        try:
            taken_at, date_source = get_capture_date(source, self.use_filesystem_fallback)
            if taken_at is None:
                return OrganizeResult(source, Status.NO_DATE, message="No EXIF/metadata date found")

            destination, duplicate_of = self._resolve_destination(source, taken_at)
            if duplicate_of is not None:
                return OrganizeResult(
                    source, Status.DUPLICATE, taken_at, date_source, duplicate_of,
                    message="Identical file already in output",
                )

            if self.dry_run:
                return OrganizeResult(source, Status.PLANNED, taken_at, date_source, destination)

            destination.parent.mkdir(parents=True, exist_ok=True)
            if self.action is Action.MOVE:
                shutil.move(source, destination)
                status = Status.MOVED
            else:
                shutil.copy2(source, destination)  # copy2 keeps timestamps
                status = Status.COPIED
            self._reserved[destination] = destination  # source may be gone after a move
            return OrganizeResult(source, status, taken_at, date_source, destination)
        except OSError as error:
            return OrganizeResult(source, Status.ERROR, message=str(error))

    def _delete(self, source: Path) -> OrganizeResult:
        if self.dry_run:
            message = "Will be deleted permanently" if self.permanent_delete else "Will be moved to Trash"
            return OrganizeResult(source, Status.PLANNED, message=message)
        try:
            if self.permanent_delete:
                source.unlink()
                return OrganizeResult(source, Status.DELETED, message="Deleted permanently")
            send2trash(source)
            return OrganizeResult(source, Status.TRASHED, message="Moved to Trash")
        except Exception as error:  # send2trash raises its own TrashPermissionError / OSError
            return OrganizeResult(source, Status.ERROR, message=str(error))

    def _resolve_destination(self, source: Path, taken_at: datetime) -> tuple[Path, Path | None]:
        """Return ``(free_destination, None)`` or ``(_, existing_identical_file)``."""
        index = 0
        while True:
            candidate = build_destination(self.output_dir, taken_at, source.suffix, index, self.layout)
            other = self._reserved.get(candidate)
            if other is None and candidate.exists():
                other = candidate
            if other is None:
                self._reserved[candidate] = source
                return candidate, None
            if _same_content(source, other):
                return candidate, candidate
            index += 1


def _same_content(a: Path, b: Path) -> bool:
    try:
        return filecmp.cmp(a, b, shallow=False)
    except OSError:
        return False
