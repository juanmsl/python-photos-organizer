"""Application entry point."""

from __future__ import annotations

import sys

from PySide6.QtWidgets import QApplication

from photos_organizer import __version__
from photos_organizer.gui.main_window import MainWindow


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("Photos Organizer")
    app.setOrganizationName("photos-organizer")
    app.setApplicationVersion(__version__)

    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
