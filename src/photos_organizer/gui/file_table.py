"""Table model listing the files that match the selected extensions."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PySide6.QtCore import QAbstractTableModel, QModelIndex, Qt
from PySide6.QtGui import QColor

from photos_organizer.organizer import OrganizeResult, Status
from photos_organizer.scanner import FileEntry

_STATUS_COLORS = {
    Status.PLANNED: QColor("#2f6fdf"),
    Status.COPIED: QColor("#2e8b57"),
    Status.MOVED: QColor("#2e8b57"),
    Status.TRASHED: QColor("#7f8c8d"),
    Status.DELETED: QColor("#7f8c8d"),
    Status.DUPLICATE: QColor("#b8860b"),
    Status.NO_DATE: QColor("#b8860b"),
    Status.ERROR: QColor("#c0392b"),
}


def format_size(size: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024:
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


@dataclass(slots=True)
class FileRow:
    entry: FileEntry
    result: OrganizeResult | None = None


class FileTableModel(QAbstractTableModel):
    HEADERS = ("File", "Type", "Size", "Date taken", "Date source", "Status", "Destination")

    def __init__(self) -> None:
        super().__init__()
        self._rows: list[FileRow] = []
        self._output_dir: Path | None = None

    # -- data management -------------------------------------------------
    def set_entries(self, entries: list[FileEntry]) -> None:
        self.beginResetModel()
        self._rows = [FileRow(entry) for entry in entries]
        self.endResetModel()

    def entries(self) -> list[FileEntry]:
        return [row.entry for row in self._rows]

    def set_output_dir(self, output_dir: Path | None) -> None:
        self._output_dir = output_dir

    def clear_results(self) -> None:
        for row in self._rows:
            row.result = None
        if self._rows:
            self.dataChanged.emit(self.index(0, 3), self.index(len(self._rows) - 1, len(self.HEADERS) - 1))

    def set_result(self, row: int, result: OrganizeResult) -> None:
        self._rows[row].result = result
        self.dataChanged.emit(self.index(row, 0), self.index(row, len(self.HEADERS) - 1))

    # -- Qt model API ----------------------------------------------------
    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:  # noqa: B008, N802
        return 0 if parent.isValid() else len(self._rows)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:  # noqa: B008, N802
        return 0 if parent.isValid() else len(self.HEADERS)

    def headerData(self, section: int, orientation: Qt.Orientation, role: int = Qt.DisplayRole):  # noqa: N802
        if role == Qt.DisplayRole and orientation == Qt.Horizontal:
            return self.HEADERS[section]
        return None

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole):
        if not index.isValid():
            return None
        row = self._rows[index.row()]
        column = index.column()
        result = row.result

        if role == Qt.DisplayRole:
            match column:
                case 0:
                    return row.entry.relative_path
                case 1:
                    return row.entry.extension.lstrip(".").upper() or "—"
                case 2:
                    return format_size(row.entry.size)
                case 3:
                    return result.date.strftime("%Y-%m-%d %H:%M:%S") if result and result.date else ""
                case 4:
                    return str(result.date_source) if result and result.date_source else ""
                case 5:
                    return str(result.status) if result else ""
                case 6:
                    return self._display_destination(result)
        elif role == Qt.ForegroundRole and column == 5 and result:
            return _STATUS_COLORS.get(result.status)
        elif role == Qt.ToolTipRole:
            if column == 0:
                return str(row.entry.path)
            if result and result.message:
                return result.message
        elif role == Qt.TextAlignmentRole and column == 2:
            return int(Qt.AlignRight | Qt.AlignVCenter)
        return None

    def _display_destination(self, result: OrganizeResult | None) -> str:
        if not result:
            return ""
        if result.destination is None:
            return result.message
        if self._output_dir:
            try:
                return str(result.destination.relative_to(self._output_dir))
            except ValueError:
                pass
        return str(result.destination)
