#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from PyQt6.QtGui import QClipboard
from PyQt6.QtWidgets import QApplication


def get_clipboard_text():
    ''' Get text from system clipboard.'''
    clipboard = QApplication.clipboard()
    text = clipboard.text()
    if text:
        return text

    if clipboard.supportsSelection():
        return clipboard.text(QClipboard.Mode.Selection)

    return ""

def set_clipboard_text(text):
    ''' Set text to system clipboard.'''
    clipboard = QApplication.clipboard()
    clipboard.setText(text)

    if clipboard.supportsSelection():
        clipboard.setText(text, QClipboard.Mode.Selection)
