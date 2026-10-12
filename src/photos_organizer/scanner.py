"""Recursive folder scanning."""

from __future__ import annotations

import os
from collections import Counter
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class FileEntry:
    path: Path
    relative_path: str
    extension: str  # lower-case, including the dot (".jpg"); "" when the file has none
    size: int


def scan_folder(
    root: Path,
    include_hidden: bool = False,
    should_cancel: Callable[[], bool] | None = None,
) -> list[FileEntry]:
    """Return every file under ``root`` (including sub-folders), sorted by relative path.

    Hidden files and folders (names starting with ".") are skipped by default, which also
    drops macOS noise such as ``.DS_Store`` and ``._*`` AppleDouble files.
    """
    root = root.resolve()
    entries: list[FileEntry] = []

    for dirpath, dirnames, filenames in os.walk(root):
        if should_cancel and should_cancel():
            break
        if not include_hidden:
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        dirnames.sort()

        for name in sorted(filenames):
            if not include_hidden and name.startswith("."):
                continue
            path = Path(dirpath) / name
            try:
                size = path.stat().st_size
            except OSError:
                continue  # broken symlink, permission denied, ...
            entries.append(
                FileEntry(
                    path=path,
                    relative_path=str(path.relative_to(root)),
                    extension=path.suffix.lower(),
                    size=size,
                )
            )

    return entries


def count_extensions(entries: Iterable[FileEntry]) -> Counter[str]:
    return Counter(entry.extension for entry in entries)
