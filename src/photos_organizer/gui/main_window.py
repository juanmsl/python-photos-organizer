"""Main application window."""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QObject, QSettings, Qt, QThread
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import (
    QAbstractItemView,
    QButtonGroup,
    QCheckBox,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QRadioButton,
    QSplitter,
    QTableView,
    QVBoxLayout,
    QWidget,
)

from photos_organizer.gui.file_table import FileTableModel, format_size
from photos_organizer.gui.workers import OrganizeWorker, ScanWorker
from photos_organizer.metadata import is_media_extension
from photos_organizer.organizer import OrganizeResult, Status, TransferMode
from photos_organizer.scanner import FileEntry, count_extensions

_EXTENSION_ROLE = Qt.UserRole


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Photos Organizer")
        self.resize(1200, 760)

        self._settings = QSettings()
        self._all_entries: list[FileEntry] = []
        self._source_dir: Path | None = None
        self._thread: QThread | None = None
        self._worker: QObject | None = None
        self._rescan_after_worker = False

        self._model = FileTableModel()
        self._build_ui()
        self._restore_settings()
        self._update_buttons()

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        central = QWidget()
        layout = QVBoxLayout(central)

        # Source folder
        source_row = QHBoxLayout()
        source_row.addWidget(QLabel("Source folder:"))
        self.source_edit = QLineEdit(readOnly=True, placeholderText="Choose the folder that contains your photos/videos…")
        source_row.addWidget(self.source_edit, 1)
        self.source_button = QPushButton("Browse…")
        self.source_button.clicked.connect(self._choose_source)
        source_row.addWidget(self.source_button)
        self.rescan_button = QPushButton("Rescan")
        self.rescan_button.clicked.connect(self._start_scan)
        source_row.addWidget(self.rescan_button)
        layout.addLayout(source_row)

        # Extension filters | file table
        splitter = QSplitter(Qt.Horizontal)

        filter_box = QGroupBox("File types")
        filter_layout = QVBoxLayout(filter_box)
        self.extension_list = QListWidget()
        self.extension_list.itemChanged.connect(self._apply_filter)
        filter_layout.addWidget(self.extension_list)
        filter_buttons = QHBoxLayout()
        for label, handler in (
            ("All", lambda: self._check_extensions(lambda _ext: True)),
            ("None", lambda: self._check_extensions(lambda _ext: False)),
            ("Media", lambda: self._check_extensions(is_media_extension)),
        ):
            button = QPushButton(label)
            button.clicked.connect(handler)
            filter_buttons.addWidget(button)
        filter_layout.addLayout(filter_buttons)
        splitter.addWidget(filter_box)

        table_box = QWidget()
        table_layout = QVBoxLayout(table_box)
        table_layout.setContentsMargins(0, 0, 0, 0)
        self.table = QTableView()
        self.table.setModel(self._model)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.table.setAlternatingRowColors(True)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(22)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.Interactive)
        header.setStretchLastSection(True)
        for column, width in enumerate((340, 60, 80, 140, 110, 130)):
            self.table.setColumnWidth(column, width)
        table_layout.addWidget(self.table)
        self.selection_label = QLabel("No folder selected.")
        table_layout.addWidget(self.selection_label)
        splitter.addWidget(table_box)

        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setSizes([220, 980])
        layout.addWidget(splitter, 1)

        # Output options
        output_box = QGroupBox("Output")
        output_layout = QVBoxLayout(output_box)
        output_row = QHBoxLayout()
        output_row.addWidget(QLabel("Output folder:"))
        self.output_edit = QLineEdit(readOnly=True, placeholderText="Files will be placed in <output>/YYYY/MM/YYYY-MM-DD-T-HH-MM-SS.ext")
        output_row.addWidget(self.output_edit, 1)
        self.output_button = QPushButton("Browse…")
        self.output_button.clicked.connect(self._choose_output)
        output_row.addWidget(self.output_button)
        output_layout.addLayout(output_row)

        options_row = QHBoxLayout()
        self.copy_radio = QRadioButton("Copy files (keep originals)", checked=True)
        self.move_radio = QRadioButton("Move files")
        self._mode_group = QButtonGroup(self)
        self._mode_group.addButton(self.copy_radio)
        self._mode_group.addButton(self.move_radio)
        options_row.addWidget(self.copy_radio)
        options_row.addWidget(self.move_radio)
        options_row.addSpacing(20)
        self.fallback_check = QCheckBox("Use file date when there is no EXIF/metadata date", checked=True)
        options_row.addWidget(self.fallback_check)
        options_row.addStretch(1)

        self.preview_button = QPushButton("Preview")
        self.preview_button.setToolTip("Read the metadata and show where each file would go, without touching anything.")
        self.preview_button.clicked.connect(lambda: self._start_organize(dry_run=True))
        self.organize_button = QPushButton("Organize")
        self.organize_button.setDefault(True)
        self.organize_button.clicked.connect(lambda: self._start_organize(dry_run=False))
        self.cancel_button = QPushButton("Cancel")
        self.cancel_button.clicked.connect(self._cancel_worker)
        for button in (self.preview_button, self.organize_button, self.cancel_button):
            options_row.addWidget(button)
        output_layout.addLayout(options_row)
        layout.addWidget(output_box)

        self.progress = QProgressBar(textVisible=True)
        layout.addWidget(self.progress)

        self.log = QPlainTextEdit(readOnly=True, maximumBlockCount=2000)
        self.log.setFixedHeight(110)
        layout.addWidget(self.log)

        self.setCentralWidget(central)

    # ------------------------------------------------------------ settings
    def _restore_settings(self) -> None:
        output = self._settings.value("output_dir", "")
        if output and Path(output).is_dir():
            self.output_edit.setText(output)
            self._model.set_output_dir(Path(output))
        if self._settings.value("mode", TransferMode.COPY) == TransferMode.MOVE:
            self.move_radio.setChecked(True)
        self.fallback_check.setChecked(self._settings.value("fallback", True, type=bool))

    def _save_settings(self) -> None:
        if self._source_dir:
            self._settings.setValue("source_dir", str(self._source_dir))
        self._settings.setValue("output_dir", self.output_edit.text())
        self._settings.setValue("mode", str(self._mode()))
        self._settings.setValue("fallback", self.fallback_check.isChecked())

    # ------------------------------------------------------------- actions
    def _choose_source(self) -> None:
        start = str(self._source_dir or self._settings.value("source_dir", str(Path.home())))
        folder = QFileDialog.getExistingDirectory(self, "Select source folder", start)
        if folder:
            self._source_dir = Path(folder)
            self.source_edit.setText(folder)
            self._start_scan()

    def _choose_output(self) -> None:
        start = self.output_edit.text() or str(Path.home())
        folder = QFileDialog.getExistingDirectory(self, "Select output folder", start)
        if folder:
            self.output_edit.setText(folder)
            self._model.set_output_dir(Path(folder))
            self._model.clear_results()
            self._update_buttons()

    def _start_scan(self) -> None:
        if not self._source_dir or self._is_busy():
            return
        self._log(f"Scanning {self._source_dir} …")
        self.progress.setRange(0, 0)  # busy indicator
        worker = ScanWorker(self._source_dir)
        worker.finished.connect(self._on_scan_finished)
        worker.failed.connect(self._on_scan_failed)
        self._run_worker(worker)

    def _on_scan_finished(self, entries: list[FileEntry]) -> None:
        self._all_entries = entries
        self.progress.setRange(0, 1)
        self.progress.setValue(0)
        self._populate_extensions()
        self._apply_filter()
        self._log(f"Found {len(entries)} files.")

    def _on_scan_failed(self, message: str) -> None:
        self.progress.setRange(0, 1)
        QMessageBox.critical(self, "Scan failed", message)

    def _populate_extensions(self) -> None:
        previously_checked = self._checked_extensions() if self.extension_list.count() else None
        self.extension_list.blockSignals(True)
        self.extension_list.clear()
        for extension, count in sorted(count_extensions(self._all_entries).items()):
            label = extension.lstrip(".").upper() if extension else "(no extension)"
            item = QListWidgetItem(f"{label}  ({count})")
            item.setData(_EXTENSION_ROLE, extension)
            item.setFlags(item.flags() | Qt.ItemIsUserCheckable)
            checked = extension in previously_checked if previously_checked is not None else is_media_extension(extension)
            item.setCheckState(Qt.Checked if checked else Qt.Unchecked)
            self.extension_list.addItem(item)
        self.extension_list.blockSignals(False)

    def _check_extensions(self, predicate) -> None:
        self.extension_list.blockSignals(True)
        for i in range(self.extension_list.count()):
            item = self.extension_list.item(i)
            item.setCheckState(Qt.Checked if predicate(item.data(_EXTENSION_ROLE)) else Qt.Unchecked)
        self.extension_list.blockSignals(False)
        self._apply_filter()

    def _checked_extensions(self) -> set[str]:
        return {
            self.extension_list.item(i).data(_EXTENSION_ROLE)
            for i in range(self.extension_list.count())
            if self.extension_list.item(i).checkState() == Qt.Checked
        }

    def _apply_filter(self, *_args) -> None:
        selected = self._checked_extensions()
        filtered = [entry for entry in self._all_entries if entry.extension in selected]
        self._model.set_entries(filtered)
        total_size = sum(entry.size for entry in filtered)
        self.selection_label.setText(
            f"{len(filtered)} of {len(self._all_entries)} files selected ({format_size(total_size)})"
        )
        self._update_buttons()

    def _start_organize(self, dry_run: bool) -> None:
        output_text = self.output_edit.text()
        if not output_text:
            QMessageBox.information(self, "Output folder", "Please choose an output folder first.")
            return
        output_dir = Path(output_text).resolve()
        if self._source_dir and output_dir == self._source_dir.resolve():
            QMessageBox.warning(self, "Output folder", "The output folder must be different from the source folder.")
            return

        # Never re-process files that already live inside the output folder.
        rows = [
            (row, entry)
            for row, entry in enumerate(self._model.entries())
            if not entry.path.resolve().is_relative_to(output_dir)
        ]
        if not rows:
            QMessageBox.information(self, "Nothing to do", "No files match the selected file types.")
            return

        mode = self._mode()
        if not dry_run and mode is TransferMode.MOVE:
            answer = QMessageBox.question(
                self, "Move files",
                f"{len(rows)} files will be MOVED out of the source folder into:\n{output_dir}\n\nContinue?",
            )
            if answer != QMessageBox.Yes:
                return

        self._save_settings()
        self._model.set_output_dir(output_dir)
        self._model.clear_results()
        self.progress.setRange(0, len(rows))
        self.progress.setValue(0)
        action = "Previewing" if dry_run else ("Moving" if mode is TransferMode.MOVE else "Copying")
        self._log(f"{action} {len(rows)} files → {output_dir}")

        worker = OrganizeWorker(rows, output_dir, mode, self.fallback_check.isChecked(), dry_run)
        worker.item_done.connect(self._on_item_done)
        # Bound methods (not lambdas) so Qt queues these calls onto the UI thread.
        worker.progress.connect(self._on_progress)
        worker.finished.connect(self._on_organize_finished)
        self._run_worker(worker)

    def _on_progress(self, done: int, _total: int) -> None:
        self.progress.setValue(done)

    def _on_item_done(self, row: int, result: OrganizeResult) -> None:
        self._model.set_result(row, result)
        if result.status is Status.ERROR:
            self._log(f"ERROR {result.source}: {result.message}")

    def _on_organize_finished(self, summary, cancelled: bool) -> None:
        parts = ", ".join(f"{status}: {count}" for status, count in summary.items()) or "nothing processed"
        self._log(("Cancelled. " if cancelled else "Done. ") + parts)
        moved = summary.get(Status.MOVED, 0)
        if moved and self._source_dir:
            self._log("Files were moved; rescanning the source folder.")
            self._rescan_after_worker = True

    def _cancel_worker(self) -> None:
        if self._worker is not None:
            self._worker.cancel()
            self._log("Cancelling…")

    # -------------------------------------------------------------- threads
    def _run_worker(self, worker: QObject) -> None:
        thread = QThread(self)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.finished.connect(thread.quit)
        if hasattr(worker, "failed"):
            worker.failed.connect(thread.quit)
        thread.finished.connect(self._on_thread_finished)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        self._thread, self._worker = thread, worker
        self._update_buttons()
        thread.start()

    def _on_thread_finished(self) -> None:
        self._thread = self._worker = None
        self._update_buttons()
        if self._rescan_after_worker:
            self._rescan_after_worker = False
            self._start_scan()

    def _is_busy(self) -> bool:
        return self._thread is not None

    def _update_buttons(self) -> None:
        busy = self._is_busy()
        has_files = self._model.rowCount() > 0
        has_output = bool(self.output_edit.text())
        for widget in (self.source_button, self.output_button, self.extension_list,
                       self.copy_radio, self.move_radio, self.fallback_check):
            widget.setEnabled(not busy)
        self.rescan_button.setEnabled(not busy and self._source_dir is not None)
        self.preview_button.setEnabled(not busy and has_files and has_output)
        self.organize_button.setEnabled(not busy and has_files and has_output)
        self.cancel_button.setEnabled(busy)

    # ---------------------------------------------------------------- misc
    def _mode(self) -> TransferMode:
        return TransferMode.MOVE if self.move_radio.isChecked() else TransferMode.COPY

    def _log(self, message: str) -> None:
        self.log.appendPlainText(message)

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802
        if self._thread is not None:
            self._cancel_worker()
            self._thread.quit()
            self._thread.wait(5000)
        self._save_settings()
        super().closeEvent(event)
