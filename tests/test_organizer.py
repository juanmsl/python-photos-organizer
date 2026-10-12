from datetime import datetime
from pathlib import Path

import pytest
from PIL import ExifTags, Image

from photos_organizer.metadata import DateSource, get_capture_date, parse_exif_datetime
from photos_organizer.organizer import Organizer, Status, TransferMode, build_destination
from photos_organizer.scanner import scan_folder


def make_jpeg(path: Path, taken_at: str | None, color: str = "red") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (8, 8), color)
    exif = Image.Exif()
    if taken_at:
        exif[ExifTags.IFD.Exif] = {ExifTags.Base.DateTimeOriginal: taken_at}
    image.save(path, exif=exif)
    return path


def test_build_destination_matches_requested_pattern():
    dest = build_destination(Path("/out"), datetime(2014, 12, 6, 16, 22, 0), ".JPG")
    assert dest == Path("/out/2014/12/2014-12-06-T-16-22-00.jpg")


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("2014:12:06 16:22:00", datetime(2014, 12, 6, 16, 22, 0)),
        (b"2014:12:06 16:22:00\x00", datetime(2014, 12, 6, 16, 22, 0)),
        ("2014-12-06T16:22:00", datetime(2014, 12, 6, 16, 22, 0)),
        ("0000:00:00 00:00:00", None),
        ("    :  :     :  :  ", None),
        (None, None),
    ],
)
def test_parse_exif_datetime(raw, expected):
    assert parse_exif_datetime(raw) == expected


def test_reads_exif_date(tmp_path):
    photo = make_jpeg(tmp_path / "a.jpg", "2014:12:06 16:22:00")
    assert get_capture_date(photo) == (datetime(2014, 12, 6, 16, 22, 0), DateSource.EXIF)


def test_falls_back_to_filesystem_date_only_when_enabled(tmp_path):
    photo = make_jpeg(tmp_path / "a.jpg", None)
    assert get_capture_date(photo, use_filesystem_fallback=False) == (None, None)
    assert get_capture_date(photo, use_filesystem_fallback=True)[1] is DateSource.FILESYSTEM


def test_copy_into_year_month_folders(tmp_path):
    source = make_jpeg(tmp_path / "in" / "nested" / "IMG_0001.JPG", "2014:12:06 16:22:00")
    result = Organizer(tmp_path / "out").process(source)

    assert result.status is Status.COPIED
    assert result.destination == tmp_path / "out" / "2014" / "12" / "2014-12-06-T-16-22-00.jpg"
    assert result.destination.exists()
    assert source.exists()


def test_move_removes_source(tmp_path):
    source = make_jpeg(tmp_path / "in" / "a.jpg", "2020:01:02 03:04:05")
    result = Organizer(tmp_path / "out", TransferMode.MOVE).process(source)
    assert result.status is Status.MOVED
    assert not source.exists()


def test_same_second_different_content_gets_suffix(tmp_path):
    first = make_jpeg(tmp_path / "in" / "a.jpg", "2014:12:06 16:22:00", "red")
    second = make_jpeg(tmp_path / "in" / "b.jpg", "2014:12:06 16:22:00", "blue")
    organizer = Organizer(tmp_path / "out")

    assert organizer.process(first).destination.name == "2014-12-06-T-16-22-00.jpg"
    assert organizer.process(second).destination.name == "2014-12-06-T-16-22-00-1.jpg"


def test_identical_file_is_reported_as_duplicate(tmp_path):
    first = make_jpeg(tmp_path / "in" / "a.jpg", "2014:12:06 16:22:00")
    copy = tmp_path / "in" / "copy-of-a.jpg"
    copy.write_bytes(first.read_bytes())

    for dry_run in (True, False):
        organizer = Organizer(tmp_path / f"out-{dry_run}", dry_run=dry_run)
        organizer.process(first)
        assert organizer.process(copy).status is Status.DUPLICATE


def test_dry_run_does_not_touch_disk(tmp_path):
    source = make_jpeg(tmp_path / "in" / "a.jpg", "2014:12:06 16:22:00")
    result = Organizer(tmp_path / "out", dry_run=True).process(source)
    assert result.status is Status.PLANNED
    assert not (tmp_path / "out").exists()


def test_no_date_is_skipped_without_fallback(tmp_path):
    source = make_jpeg(tmp_path / "in" / "a.jpg", None)
    result = Organizer(tmp_path / "out", use_filesystem_fallback=False).process(source)
    assert result.status is Status.NO_DATE


def test_scan_is_recursive_and_skips_hidden(tmp_path):
    make_jpeg(tmp_path / "a.jpg", None)
    make_jpeg(tmp_path / "sub" / "deeper" / "b.JPG", None)
    (tmp_path / ".DS_Store").write_text("x")
    (tmp_path / ".hidden").mkdir()
    (tmp_path / ".hidden" / "c.jpg").write_text("x")

    entries = scan_folder(tmp_path)
    assert [e.relative_path for e in entries] == ["a.jpg", str(Path("sub/deeper/b.JPG"))]
    assert {e.extension for e in entries} == {".jpg"}
