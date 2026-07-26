import time

from core.utils import *
from PyQt6.QtCore import QThread, pyqtSignal


class FetchMarkerInputThread(QThread):

    match_marker = pyqtSignal(str, str)

    def __init__(self, callback_tag, markers):
        QThread.__init__(self)

        self.callback_tag = callback_tag
        self.running_flag = True

        self.marker_quit_keys = get_emacs_var("eaf-marker-quit-keys") or ""
        self.markers = markers

    def run(self):
        while self.running_flag:
            if self.markers:
                minibuffer_input = get_emacs_func_result("minibuffer-contents-no-properties", [])

                marker_input_quit = minibuffer_input and len(minibuffer_input) > 0 and minibuffer_input[-1] in self.marker_quit_keys
                marker_input_finish = minibuffer_input in self.markers

                if marker_input_quit or marker_input_finish:
                    self.running_flag = False
                    eval_in_emacs('exit-minibuffer', [])
                    message_to_emacs("Quit marker selection." if marker_input_quit else "Marker selected.")

            time.sleep(0.1)

    def stop(self):
        self.running_flag = False


class FetchSearchInputThread(QThread):

    search_changed = pyqtSignal(str, str)
    search_finish = pyqtSignal(str)

    def __init__(self, callback_tag):
        QThread.__init__(self)

        self.search_string = ""
        self.callback_tag = callback_tag
        self.running_flag = True

    def run(self):
        while self.running_flag:
            in_minibuffer = get_emacs_func_result("minibufferp", [])

            if in_minibuffer:
                minibuffer_input = get_emacs_func_result("minibuffer-contents-no-properties", [])

                if minibuffer_input != self.search_string:
                    self.search_changed.emit(self.callback_tag, minibuffer_input)
                    self.search_string = minibuffer_input
            else:
                self.stop()

            time.sleep(0.1)

    def stop(self):
        self.search_finish.emit(self.callback_tag)
        self.running_flag = False
