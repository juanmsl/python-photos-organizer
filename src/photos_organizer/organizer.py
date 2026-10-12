"""Compute destinations and copy/move files into ``<output>/YYYY/MM/YYYY-MM-DD-T-HH-MM-SS.ext``."""

from __future__ import annotations

import filecmp
import shutil
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import Path

from photos_organizer.metadata import DateSource, get_capture_date

FILENAME_FORMAT = "%Y-%m-%d-T-%H-%M-%S"


class TransferMode(StrEnum):
    COPY = "copy"
    MOVE = "move"


class Status(StrEnum):
    PLANNED = "Planned"
    COPIED = "Copied"
    MOVED = "Moved"
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


def build_destination(output_dir: Path, taken_at: datetime, extension: str, index: int = 0) -> Path:
    """``<output>/2014/12/2014-12-06-T-16-22-00.jpg``; ``index`` > 0 adds ``-1``, ``-2``... for same-second shots."""
    stem = taken_at.strftime(FILENAME_FORMAT)
    if index:
        stem = f"{stem}-{index}"
    return output_dir / f"{taken_at:%Y}" / f"{taken_at:%m}" / f"{stem}{extension.lower()}"


class Organizer:
    """Processes files one at a time, keeping track of names already used in this run."""

    def __init__(
        self,
        output_dir: Path,
        mode: TransferMode = TransferMode.COPY,
        use_filesystem_fallback: bool = True,
        dry_run: bool = False,
    ) -> None:
        self.output_dir = output_dir
        self.mode = mode
        self.use_filesystem_fallback = use_filesystem_fallback
        self.dry_run = dry_run
        # destination -> source it was assigned to, so dry runs detect collisions too.
        self._reserved: dict[Path, Path] = {}

    def process(self, source: Path) -> OrganizeResult:
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
            if self.mode is TransferMode.MOVE:
                shutil.move(source, destination)
                status = Status.MOVED
            else:
                shutil.copy2(source, destination)  # copy2 keeps timestamps
                status = Status.COPIED
            self._reserved[destination] = destination  # source may be gone after a move
            return OrganizeResult(source, status, taken_at, date_source, destination)
        except OSError as error:
            return OrganizeResult(source, Status.ERROR, message=str(error))

    def _resolve_destination(self, source: Path, taken_at: datetime) -> tuple[Path, Path | None]:
        """Return ``(free_destination, None)`` or ``(_, existing_identical_file)``."""
        index = 0
        while True:
            candidate = build_destination(self.output_dir, taken_at, source.suffix, index)
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
