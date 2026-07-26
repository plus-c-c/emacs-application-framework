#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os

from core.utils import *
from PyQt6 import QtCore
from PyQt6.QtCore import QEvent, QEventLoop, QPoint, QPointF, Qt, QThread, QTimer, QUrl, pyqtSlot
from PyQt6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile, QWebEngineSettings
from PyQt6.QtWebEngineWidgets import QWebEngineView

class BrowserPage(QWebEnginePage):
    def __init__(self, profile):
        QWebEnginePage.__init__(self, profile)

    def execute_javascript(self, script_src):
        ''' Execute JavaScript.'''
        try:
            if hasattr(self, "loop") and self.loop.isRunning():
                # NOTE:
                #
                # Just return None is QEventLoop is busy, such as press 'j' key not release on webpage.
                # Otherwise will got error 'RecursionError: maximum recursion depth exceeded while calling a Python object'.
                #
                # And don't warry, API 'execute_javascript' is works well for programming purpse since we just call this interface occasionally.
                return None
            else:
                # Build event loop.
                self.loop = QEventLoop()

                # Run JavaScript code.
                self.runJavaScript(script_src, self.callback_js)

                # Execute event loop, and wait event loop quit.
                self.loop.exec()

                # Return JavaScript function result.
                return self.result
        except:
            import traceback
            traceback.print_exc()

            return None

    def callback_js(self, result):
        ''' Callback of JavaScript, call loop.quit to jump code after loop.exec.'''
        self.result = result
        self.loop.quit()

    def javaScriptConsoleMessage(self, level, message, line_number, source_id):
        # Only print JavaScript console message for EAF application.
        # don't print any console message from browser, print too much message will slow down Emacs.
        if self.url().toString() == "file:///":
            print("[JavaScript console]: " + message)


