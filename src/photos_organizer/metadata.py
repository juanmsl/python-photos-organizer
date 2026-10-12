"""Extract the capture date of photos and videos.

Lookup order:
  * Photos: EXIF ``DateTimeOriginal`` -> ``DateTimeDigitized`` -> ``DateTime``
    (Pillow first, ExifRead as fallback; ExifRead first for RAW files).
  * Videos: container creation date via hachoir. QuickTime-based formats (MP4/MOV)
    store it in UTC, so it is converted to the computer's local time zone.
  * Optional fallback: the file-system date (creation time on macOS, otherwise
    modification time).
"""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from enum import StrEnum
from pathlib import Path

import exifread
from hachoir.core import config as hachoir_config
from hachoir.metadata import extractMetadata
from hachoir.parser import createParser
from PIL import ExifTags, Image

try:
    from pillow_heif import register_heif_opener

    register_heif_opener()
except ImportError:  # pragma: no cover - optional at runtime
    pass

hachoir_config.quiet = True
logging.getLogger("exifread").setLevel(logging.ERROR)

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".jpe", ".png", ".tif", ".tiff", ".heic", ".heif", ".webp"}
RAW_EXTENSIONS = {".cr2", ".cr3", ".nef", ".nrw", ".arw", ".srf", ".sr2", ".dng", ".orf", ".rw2", ".raf", ".pef", ".srw"}
VIDEO_EXTENSIONS = {".mp4", ".m4v", ".mov", ".3gp", ".3g2", ".avi", ".mkv", ".mts", ".m2ts", ".wmv", ".mpg", ".mpeg"}
QUICKTIME_EXTENSIONS = {".mp4", ".m4v", ".mov", ".3gp", ".3g2"}
MEDIA_EXTENSIONS = IMAGE_EXTENSIONS | RAW_EXTENSIONS | VIDEO_EXTENSIONS

# EXIF tag ids, most reliable first.
_PIL_EXIF_TAGS = (
    ExifTags.Base.DateTimeOriginal,
    ExifTags.Base.DateTimeDigitized,
)
_EXIFREAD_TAGS = ("EXIF DateTimeOriginal", "EXIF DateTimeDigitized", "Image DateTime")
_EXIF_DATE_RE = re.compile(r"(\d{4})[:\-/](\d{2})[:\-/](\d{2})[ T](\d{2}):(\d{2}):(\d{2})")
_MIN_YEAR = 1900  # QuickTime "zero" dates decode as 1904-01-01; EXIF blanks as 0000:00:00


class DateSource(StrEnum):
    EXIF = "EXIF"
    VIDEO = "Video metadata"
    FILESYSTEM = "File date"


def parse_exif_datetime(value: object) -> datetime | None:
    """Parse EXIF-style dates such as ``"2014:12:06 16:22:00"``."""
    if value is None:
        return None
    if isinstance(value, bytes):
        value = value.decode("ascii", errors="ignore")
    match = _EXIF_DATE_RE.search(str(value))
    if not match:
        return None
    try:
        parsed = datetime(*(int(part) for part in match.groups()))
    except ValueError:
        return None
    return parsed if parsed.year >= _MIN_YEAR else None


def _date_from_pillow(path: Path) -> datetime | None:
    try:
        with Image.open(path) as image:
            exif = image.getexif()
    except Exception:
        return None
    if not exif:
        return None
    exif_ifd = exif.get_ifd(ExifTags.IFD.Exif)
    for tag in _PIL_EXIF_TAGS:
        if parsed := parse_exif_datetime(exif_ifd.get(tag)):
            return parsed
    return parse_exif_datetime(exif.get(ExifTags.Base.DateTime))


def _date_from_exifread(path: Path) -> datetime | None:
    try:
        with path.open("rb") as handle:
            tags = exifread.process_file(handle, details=False)
    except Exception:
        return None
    for key in _EXIFREAD_TAGS:
        if key in tags and (parsed := parse_exif_datetime(str(tags[key]))):
            return parsed
    return None


def _date_from_video(path: Path) -> datetime | None:
    try:
        parser = createParser(str(path))
        if parser is None:
            return None
        with parser:
            metadata = extractMetadata(parser)
    except Exception:
        return None
    if metadata is None:
        return None

    for key in ("date_time_original", "creation_date"):
        if not metadata.has(key):
            continue
        value = metadata.get(key)
        if not isinstance(value, datetime) or value.year < 1970:
            continue
        if path.suffix.lower() in QUICKTIME_EXTENSIONS:
            # QuickTime stores UTC; show the time as it was on the user's clock.
            value = value.replace(tzinfo=timezone.utc).astimezone().replace(tzinfo=None)
        return value.replace(microsecond=0, tzinfo=None)
    return None


def _date_from_filesystem(path: Path) -> datetime | None:
    try:
        stat = path.stat()
    except OSError:
        return None
    timestamp = stat.st_mtime
    birth = getattr(stat, "st_birthtime", None)  # macOS / BSD / Windows (3.12+)
    if birth:
        timestamp = min(timestamp, birth)
    return datetime.fromtimestamp(timestamp).replace(microsecond=0)


def get_capture_date(
    path: Path, use_filesystem_fallback: bool = True
) -> tuple[datetime | None, DateSource | None]:
    """Return ``(datetime, source)`` for ``path``, or ``(None, None)`` if no date was found."""
    extension = path.suffix.lower()

    if extension in VIDEO_EXTENSIONS:
        if found := _date_from_video(path):
            return found, DateSource.VIDEO
    else:
        readers = (
            (_date_from_exifread, _date_from_pillow)
            if extension in RAW_EXTENSIONS
            else (_date_from_pillow, _date_from_exifread)
        )
        for reader in readers:
            if found := reader(path):
                return found, DateSource.EXIF

    if use_filesystem_fallback and (found := _date_from_filesystem(path)):
        return found, DateSource.FILESYSTEM
    return None, None


def is_media_extension(extension: str) -> bool:
    return extension.lower() in MEDIA_EXTENSIONS


__all__ = [
    "DateSource",
    "IMAGE_EXTENSIONS",
    "MEDIA_EXTENSIONS",
    "RAW_EXTENSIONS",
    "VIDEO_EXTENSIONS",
    "get_capture_date",
    "is_media_extension",
    "parse_exif_datetime",
]
