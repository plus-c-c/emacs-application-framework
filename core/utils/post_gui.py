#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from PyQt6.QtCore import QObject, pyqtSignal


class PostGui(QObject):

    through_thread = pyqtSignal(object, object)

    def __init__(self, inclass=True):
        super(PostGui, self).__init__()
        self.through_thread.connect(self.on_signal_received)
        self.inclass = inclass

    def __call__(self, func):
        self._func = func

        from functools import wraps

        @wraps(func)
        def obj_call(*args, **kwargs):
            self.emit_signal(args, kwargs)
        return obj_call

    def emit_signal(self, args, kwargs):
        self.through_thread.emit(args, kwargs)

    def on_signal_received(self, args, kwargs):
        try:
            if self.inclass:
                obj, args = args[0], args[1:]
                self._func(obj, *args, **kwargs)
            else:
                self._func(*args, **kwargs)
        except Exception:
            import traceback
            traceback.print_exc()
