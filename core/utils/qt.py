#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os

from PyQt6 import QtGui
from PyQt6.QtWidgets import QApplication


current_desktop = os.getenv("XDG_CURRENT_DESKTOP") or os.getenv("XDG_SESSION_DESKTOP")

def post_event(widget, event):
    try:
        QApplication.postEvent(widget, event)
    except:
        import traceback
        print("post_event error: " + traceback.format_exc())

def get_qrcode_pixmap(content):
    import tempfile

    import qrcode

    img = qrcode.make(content)
    temp_qrcode_file = tempfile.NamedTemporaryFile(mode="w", delete=False)
    temp_qrcode_file_path = temp_qrcode_file.name
    img.save(temp_qrcode_file_path)

    pixmap = QtGui.QPixmap(temp_qrcode_file_path)
    os.remove(temp_qrcode_file_path)

    return pixmap
