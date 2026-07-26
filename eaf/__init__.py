#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys

_eaf_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _eaf_root not in sys.path:
    sys.path.insert(0, _eaf_root)

from eaf.core import EAF
from eaf.ocr import OCRThread

__all__ = ["EAF", "OCRThread"]

if __name__ == "__main__":
    import signal
    import platform
    from PyQt6.QtWidgets import QApplication

    proxy_string = ""

    emacs_width = emacs_height = 0

    destroy_view_list = []

    hardware_acceleration_args = []
    if platform.system() != "Windows":
        hardware_acceleration_args += [
            "--ignore-gpu-blocklist",
            "--enable-gpu-rasterization",
            "--enable-native-gpu-memory-buffers"]

    app = QApplication(sys.argv + hardware_acceleration_args)
    app.setApplicationName("eaf.py")

    eaf = EAF(sys.argv[1:])

    signal.signal(signal.SIGINT, signal.SIG_DFL)
    sys.exit(app.exec())
