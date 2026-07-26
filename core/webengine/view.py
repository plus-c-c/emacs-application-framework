#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import platform
import re
import threading
from urllib.parse import parse_qs, urlparse

from core.utils import *
from core.webengine.page import BrowserPage
from core.webengine.cookies import CookiesManager
from PyQt6 import QtCore
from PyQt6.QtCore import QEvent, QEventLoop, QPoint, QPointF, Qt, QThread, QTimer, QUrl, pyqtSlot
from PyQt6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile, QWebEngineSettings
from PyQt6.QtWebEngineWidgets import QWebEngineView
from PyQt6.QtWidgets import QApplication, QWidget

class BrowserView(QWebEngineView):

    translate_selected_text = QtCore.pyqtSignal(str)

    def __init__(self, profile, buffer_id):
        super(QWebEngineView, self).__init__(profile)

        self.installEventFilter(self)
        self.buffer_id = buffer_id
        self.is_button_press = False

        self.web_page = BrowserPage(profile)
        self.setPage(self.web_page)

        self.url_hovered = ""
        self.page().linkHovered.connect(self.link_hovered)
        self.page().quotaRequested.connect(lambda request: request.accept())
        self.page().fileSystemAccessRequested.connect(lambda request: request.accept())

        self.selectionChanged.connect(self.select_text_change)

        self.loadProgress.connect(self.load_fix_script)

        # Cookie init.
        self.cookies_manager = CookiesManager(self)

        self.search_term = ""

        self.buildin_js_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "js")

        self.marker_js_raw = None
        self.get_focus_text_js = None
        self.get_next_page_url_js = None
        self.set_focus_text_raw = None
        self.clear_focus_js = None
        self.dark_mode_js = None
        self.select_input_text_js = None
        self.get_selection_text_js = None
        self.focus_input_js = None
        self.immersive_translation_js = None
        self.immersive_translation_response_js = None

        self.simulated_wheel_event = False

        self.last_mouse_word = None
        self.last_mouse_word_timer = None

        self.thread_queue = []

        (self.default_zoom, self.zoom_step,
         self.show_hover_link, self.marker_letters,
         self.marker_fontsize, self.scroll_step) = get_emacs_vars(
            ["eaf-webengine-default-zoom",
             "eaf-webengine-zoom-step",
             "eaf-webengine-show-hover-link",
             "eaf-marker-letters",
             "eaf-marker-fontsize",
             "eaf-webengine-scroll-step"])

    def delete_all_cookies(self):
        self.cookies_manager.delete_all_cookies()

    def delete_cookie(self):
        self.cookies_manager.delete_cookie()

    def load_fix_script(self, progress):
        '''We need set environment variable QTWEBENGINE_CHROMIUM_FLAGS with --disable-web-security
to make EAF can load local html and avoid browser throw CORS error.

After set --disable-web-security, some website (such as github.com) will throw 'navigator.clipboard is undefined' error recursively.

So this function add some script to avoid website throw error recursively.

Note, we need hook this function to signal 'loadProgress', signal 'loadStarted' is not enough.'''
        if not self.url().toString().startswith("file:///"):
            self.eval_js("navigator.clipboard = {};")

    def read_js_content(self, js_file):
        ''' Read content of JavaScript(js) files.'''
        return open(os.path.join(self.buildin_js_dir, js_file), "r").read()

    def filter_url(self, url):
        ''' Filter url, avoid duplicate url for the same keyword.'''
        parsed = urlparse(url)
        qd = parse_qs(parsed.query, keep_blank_values=True)
        if parsed.netloc.startswith("www.google.com"):
            # Only save search parameters for Google, avoid duplicate url for same keyword.
            filtered = dict((k, v) for k, v in qd.items() if k.startswith("q"))
        else:
            filtered = dict((k, v) for k, v in qd.items())

        from urllib.parse import urlencode, urlunparse

        return urlunparse([
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parsed.params,
            urlencode(filtered, doseq=True), # query string
            parsed.fragment
        ])

    def filter_title(self, title):
        "If title is google url, we should drop this history, it's a temp redirect url."
        try:
            parsed = urlparse(title)
            if parsed.netloc.startswith("www.google.com"):
                return ""
            else:
                return title
        except Exception:
            return title

    def callback_text_search(self, found):
        ''' Callback of text search'''
        if self.search_term != "" and (not found):
            message_to_emacs("No ocurrence of \"" + self.search_term + "\" is found.", False)

    def clean_search_and_select(self):
        self.search_term = ""
        self.web_page.findText("")
        QTimer().singleShot(0, lambda : self.triggerPageAction(self.web_page.WebAction.Unselect))

    def clean_search(self):
        self.search_term = ""
        self.web_page.findText("")

    @PostGui()
    def _search_text(self, text, is_backward = False):
        self.search_term = text

        if is_backward:
            self.web_page.findText(self.search_term, self.web_page.FindFlag.FindBackward,
                                   self.callback_text_search)
        else:
            self.web_page.findText(self.search_term, resultCallback = self.callback_text_search)

    @interactive
    def search_text_forward(self):
        ''' Forward Search Text.'''
        self.buffer.send_input_message("Forward Search Text: ", "search_text_forward", "search")

    @interactive
    def search_text_backward(self):
        ''' Backward Search Text.'''
        self.buffer.send_input_message("Backward Search Text: ", "search_text_backward", "search")

    @PostGui()
    def action_quit(self):
        ''' Quit action.'''
        # Clean search selections if search text is not empty.
        self.clean_search_and_select()

        if self.buffer.caret_browsing_mode:
            if self.buffer.caret_browsing_mark_activated:
                self.buffer.caret_toggle_mark()
            else:
                self.buffer.caret_exit()

    def select_text_change(self):
        ''' Change selected text.'''
        # Not translate text if just exit caret mode.
        if self.buffer.caret_browsing_exit_flag:
            self.buffer.caret_browsing_exit_flag = False
            return

        # Only translate text when not in caret mode.
        if not self.buffer.caret_browsing_mode:
            modifiers = QApplication.keyboardModifiers()
            if modifiers == Qt.KeyboardModifier.ControlModifier and self.selectedText().strip() != "":
                self.translate_selected_text.emit(self.selectedText())

    def create_new_window(self):
        ''' Create new browser window.'''
        pass

    def createWindow(self, window_type):
        ''' Create new browser window.'''
        return self.create_new_window()

    def event(self, event):
        ''' Catch event.'''
        if event.type() == QEvent.Type.ChildAdded:
            obj = event.child()
            if isinstance(obj, QWidget):
                obj.installEventFilter(self)

        return QWebEngineView.event(self, event)

    def eventFilter(self, obj, event):
        ''' Handle event.'''
        # Debug event.
        # if event.type() != 1:
        #     import time
        #     print(time.time(), event.type(), self.rect())

        if event.type() in [QEvent.Type.MouseButtonPress]:
            self.is_button_press = True
        elif event.type() in [QEvent.Type.MouseButtonRelease]:
            self.is_button_press = False

        # Focus emacs buffer when user click view.
        event_type = [QEvent.Type.MouseButtonPress, QEvent.Type.MouseButtonRelease, QEvent.Type.MouseButtonDblClick]
        if platform.system() != "Darwin":
            event_type += [QEvent.Type.Wheel]

        if event.type() == QEvent.Type.MouseButtonRelease:
            self.buffer.is_focus()

        if event.type() in event_type:
            if self.simulated_wheel_event:
               self.simulated_wheel_event = False
            else:
                focus_emacs_buffer(self.buffer_id)

        if event.type() == QEvent.Type.MouseMove:
            modifiers = QApplication.keyboardModifiers()
            if modifiers == Qt.KeyboardModifier.ControlModifier:
                word = self.get_cursor_word(event.pos().x() / self.zoomFactor(), event.pos().y() / self.zoomFactor())
                if self.last_mouse_word != word:
                    self.last_mouse_word = word

                    if self.last_mouse_word is not None:
                        if self.last_mouse_word_timer is not None and self.last_mouse_word_timer.is_alive():
                            self.last_mouse_word_timer.cancel()

                        self.last_mouse_word_timer = threading.Timer(1, lambda : self.translate_cursor_word(word))
                        self.last_mouse_word_timer.start()

        if event.type() == QEvent.Type.MouseButtonPress:

            if platform.system() == "Darwin":
                eval_in_emacs('eaf-activate-emacs-window', [])

            if event.button() == Qt.MouseButton.ForwardButton:
                modifiers = QApplication.keyboardModifiers()
                if modifiers == Qt.KeyboardModifier.ControlModifier:
                    self.switch_to_next_webpage_buffer()
                else:
                    self.forward()

                event.accept()
                return True

            elif event.button() == Qt.MouseButton.BackButton:
                modifiers = QApplication.keyboardModifiers()
                if modifiers == Qt.KeyboardModifier.ControlModifier:
                    self.switch_to_previous_webpage_buffer()
                else:
                    self.back()

                event.accept()
                return True

            elif event.button() == Qt.MouseButton.LeftButton:
                modifiers = QApplication.keyboardModifiers()
                if modifiers == Qt.KeyboardModifier.ControlModifier and self.url_hovered:
                    self.open_url_background_buffer(self.url_hovered)
                    return True

            elif event.button() == Qt.MouseButton.MiddleButton:
                if self.url_hovered:
                    self.open_url_new_buffer_other_window(self.url_hovered)
                    return True


        if event.type() == QEvent.Type.Wheel:
            modifiers = QApplication.keyboardModifiers()
            if modifiers == Qt.KeyboardModifier.ControlModifier:
                if event.angleDelta().y() > 0:
                    self.zoom_in()
                else:
                    self.zoom_out()

        if event.type() == QEvent.Type.MouseButtonRelease and \
           event.button() in [Qt.MouseButton.ForwardButton,
                              Qt.MouseButton.BackButton]:
            event.accept()
            return True

        return super(QWebEngineView, self).eventFilter(obj, event)

    def translate_cursor_word(self, word):
        self.translate_selected_text.emit(word)

    def link_hovered(self, url):
        self.url_hovered = url

        if self.show_hover_link:
            if url:
                message_to_emacs(url, True, False)
            else:
                clear_emacs_message()

        return True

    def open_url(self, url):
        ''' Configure current url.'''
        self.setUrl(QUrl(url))

        eval_in_emacs('eaf-activate-emacs-window', [])

    def open_url_new_buffer(self, url):
        ''' Open url in a new tab.'''
        open_url_in_new_tab(url)

        eval_in_emacs('eaf-activate-emacs-window', [])

    def open_url_new_buffer_other_window(self, url):
        ''' Open url in a new tab.'''
        open_url_in_new_tab_other_window(url)

        eval_in_emacs('eaf-activate-emacs-window', [])

    def open_url_background_buffer(self, url):
        ''' Open url in background tab.'''
        open_url_in_background_tab(url)

        eval_in_emacs('eaf-activate-emacs-window', [])

    def switch_to_next_webpage_buffer(self):
        ''' Switch to next web page buffer.'''
        eval_in_emacs('eaf-next-buffer-same-app', [])

        eval_in_emacs('eaf-activate-emacs-window', [])

    def switch_to_previous_webpage_buffer(self):
        ''' Switch to previous web page buffer.'''
        eval_in_emacs('eaf-previous-buffer-same-app', [])

        eval_in_emacs('eaf-activate-emacs-window', [])

    @interactive(insert_or_do=True)
    def zoom_in(self):
        ''' Zoom in.'''
        self.setZoomFactor(min(5, self.zoomFactor() + self.zoom_step))
        if self.default_zoom == self.zoomFactor():
            self.buffer.zoom_data.delete_entry(urlparse(self.buffer.current_url).hostname)
        else:
            self.buffer.zoom_data.add_entry(urlparse(self.buffer.current_url).hostname, self.zoomFactor())

    @interactive(insert_or_do=True)
    def zoom_out(self):
        ''' Zoom out.'''
        self.setZoomFactor(max(0.25, self.zoomFactor() - self.zoom_step))
        if self.default_zoom == self.zoomFactor():
            self.buffer.zoom_data.delete_entry(urlparse(self.buffer.current_url).hostname)
        else:
            self.buffer.zoom_data.add_entry(urlparse(self.buffer.current_url).hostname, self.zoomFactor())

    @interactive(insert_or_do=True)
    def zoom_reset(self):
        ''' Reset the magnification.'''
        self.setZoomFactor(float(self.default_zoom))

    def eval_js(self, js):
        ''' Run JavaScript.'''
        try:
            self.web_page.runJavaScript(js)
        except:
            import traceback
            traceback.print_exc()

    def eval_js_file(self, js_file):
        ''' Run JavaScript from JS file.'''
        self.eval_js(self.read_js_content(js_file))

    def execute_js(self, js):
        ''' Execute JavaScript and get result.

        NOTE:
        Please use eval_js instead if JavaScript function haven't result return.
        Otherwise, execute_js will block EAF!!!
        '''
        return self.web_page.execute_javascript(js)

    def eval_js_function(self, *args):
        try:
            function_name = args[0]
            function_args = args[1:]

            format_string = ""

            for index, arg in enumerate(function_args):
                if isinstance(arg, str):
                    format_string += '\"{}\"'.format(arg)
                else:
                    format_string += '{}'.format(json.dumps(arg))

                if index != len(function_args) - 1:
                    format_string += ","

            format_string = function_name + "(" + format_string + ");"
            self.web_page.runJavaScript(format_string)
        except:
            import traceback
            traceback.print_exc()

    def scroll_wheel(self, x_offset, y_offset):
        from PyQt6.QtGui import QWheelEvent

        self.simulated_wheel_event = True

        pos = self.rect().center()
        global_pos = self.mapToGlobal(pos)

        event = QWheelEvent(
            QPointF(pos),
            QPointF(global_pos),
            QPoint(x_offset, y_offset),
            QPoint(x_offset, y_offset),
            Qt.MouseButton.NoButton,
            Qt.KeyboardModifier.NoModifier,
            Qt.ScrollPhase.NoScrollPhase,
            False
        )

        for widget in self.buffer.get_key_event_widgets():
            post_event(widget, event)

    @interactive(insert_or_do=True)
    def scroll_left(self):
        ''' Scroll to left side.'''
        self.scroll_wheel(-35, 0)

    @interactive(insert_or_do=True)
    def scroll_right(self):
        ''' Scroll to right side.'''
        self.scroll_wheel(35, 0)

    @interactive(insert_or_do=True)
    def scroll_up(self):
        ''' Scroll up.'''
        self.scroll_wheel(0, -self.scroll_step)

    @interactive(insert_or_do=True)
    def scroll_down(self):
        ''' Scroll down.'''
        self.scroll_wheel(0, self.scroll_step)

    @interactive
    def scroll_up_page(self):
        ''' Scroll page up.'''
        self.scroll_wheel(0, -self.rect().height())

    @interactive(insert_or_do=True)
    def scroll_down_page(self):
        ''' Scroll down a page.'''
        self.scroll_wheel(0, self.rect().height())

    @interactive(insert_or_do=True)
    def scroll_to_begin(self):
        ''' Scroll to the beginning.'''
        self.scroll_wheel(0, 1000000)

    @interactive(insert_or_do=True)
    def scroll_to_bottom(self):
        ''' Scroll to the bottom.'''
        self.scroll_wheel(0, -1000000)

    @interactive
    def insert_or_scroll_up_page(self):
        '''If input is focus send space key to insert space.
        If browser is fullscreen, send space key to play/pause video.

        Otherwise, scroll page up.
        '''
        if self.buffer.is_focus() or self.buffer.is_fullscreen:
            self.buffer.send_key(self.buffer.current_event_string)
        else:
            self.scroll_up_page()

            # Try scroll to next page if reach bottom, such as, access google.com
            if self.get_next_page_url_js is None:
                self.get_next_page_url_js = self.read_js_content("get_next_page_url.js")

            next_page_url = self.execute_js(self.get_next_page_url_js)
            if next_page_url and next_page_url != "":
                self.buffer.change_url(next_page_url)

    @interactive
    def get_selection_text(self):
        ''' Get the selected text.'''
        if self.get_selection_text_js is None:
            self.get_selection_text_js = self.read_js_content("get_selection_text.js")

        return self.execute_js(self.get_selection_text_js)

    @interactive(insert_or_do=True)
    def refresh_page(self):
        ''' Refresh the page.'''
        self.reload()

        if platform.system() == "Windows":
            eval_in_emacs('eaf-activate-emacs-window', [])

    @interactive(insert_or_do=True)
    def copy_text(self):
        ''' Copy selected text.'''
        self.triggerPageAction(self.web_page.WebAction.Copy)
        if self.buffer.caret_browsing_mode and self.buffer.caret_browsing_mark_activated:
            self.buffer.caret_exit()

    @interactive()
    def yank_text(self):
        ''' Paste selected text.'''
        self.triggerPageAction(self.web_page.WebAction.Paste)
        message_to_emacs("Yank selected text.")

    @interactive()
    def kill_text(self):
        ''' Cut selected text.'''
        self.triggerPageAction(self.web_page.WebAction.Cut)
        message_to_emacs("Kill selected text.")

    @interactive
    def undo_action(self):
        ''' Undo action.'''
        self.triggerPageAction(self.web_page.WebAction.Undo)

    @interactive
    def redo_action(self):
        ''' Redo action.'''
        self.triggerPageAction(self.web_page.WebAction.Redo)

    @interactive
    def exit_fullscreen(self):
        ''' Exit full screen.'''
        self.triggerPageAction(self.web_page.WebAction.ExitFullScreen)

    @interactive(insert_or_do=True)
    def view_source(self):
        ''' View source.'''
        self.triggerPageAction(self.web_page.WebAction.ViewSource)

    def select_all(self):
        ''' Select all text.'''
        # We need window focus before select all text.
        self.eval_js("window.focus()")
        self.triggerPageAction(self.web_page.WebAction.SelectAll)

    def select_input_text(self):
        ''' Select input text.'''
        if self.select_input_text_js is None:
            self.select_input_text_js = self.read_js_content("select_input_text.js")

        self.eval_js(self.select_input_text_js)

    @interactive
    def get_url(self):
        ''' Get current url.'''
        return self.url().toString().replace(" ", "%20")

    def load_marker_file(self):
        if self.marker_js_raw is None:
            self.marker_js_raw = self.read_js_content("marker.js")

        self.eval_js(self.marker_js_raw
                     .replace("%{marker_letters}", self.marker_letters)
                     .replace("%{marker_offset_x}", str(self.buffer.marker_offset_x()))
                     .replace("%{marker_offset_y}", str(self.buffer.marker_offset_y()))
                     .replace("%{marker_fontsize}", str(self.marker_fontsize)))

    def cleanup_links_dom(self):
        ''' Clean up links.'''
        self.load_marker_file()
        self.eval_js("Marker.cleanupLinks();")

    def get_link_markers(self):
        ''' Get link markers.'''
        self.load_marker_file()
        self.eval_js("Marker.generateMarker(Marker.generateClickMarkerList());")

    def get_text_markers(self):
        ''' Get visiable text markers.'''
        self.load_marker_file()
        self.eval_js("Marker.generateMarker(Marker.generateTextMarkerList());")

    def get_marker_link(self, marker):
        ''' Get marker's link.'''
        # print(self.execute_js("Marker.getMarkerSelector('%s')" % str(marker)))
        self.load_marker_file()
        link = self.execute_js("Marker.gotoMarker('%s', Marker.getMarkerAction)" % str(marker))
        self.cleanup_links_dom()
        if link is None or type(link).__name__ == "QVariant" or link.startswith("eaf::"):
            return False
        else:
            return link

    def _open_link(self, marker):
        ''' Jump to link according to marker.'''
        link = self.get_marker_link(marker)
        if link:
            self.open_url(link)

    def _open_link_new_buffer(self, marker):
        ''' Open the link at the marker in a new buffer.'''
        link = self.get_marker_link(marker)
        if link:
            self.open_url_new_buffer(link)

    def _open_link_new_buffer_other_window(self, marker):
        ''' Open the link at the marker in a new buffer in other window.'''
        link = self.get_marker_link(marker)
        if link:
            self.open_url_new_buffer_other_window(link)

    def _open_link_background_buffer(self, marker):
        ''' Open link at the marker in the background.'''
        link = self.get_marker_link(marker)
        if link:
            self.open_url_background_buffer(link)

    def _copy_link(self, marker):
        ''' Copy the link.'''
        link = self.get_marker_link(marker)
        if link:
            self.buffer.set_clipboard_text(link)
            message_to_emacs("Copied " + link)

    def get_code_markers(self):
        ''' Get the code markers.'''
        self.load_marker_file()
        self.eval_js("Marker.generateMarker(document.querySelectorAll('pre'))")

    def get_code_content(self, marker):
        ''' Get the code content according to marker.'''
        self.load_marker_file()
        content = self.execute_js("Marker.gotoMarker('%s', (e)=> e.textContent)" % str(marker))
        self.cleanup_links_dom()
        return content

    def _caret_at_line(self, marker):
        '''Enable caret by marker'''
        self.load_marker_file()
        self.eval_js("Marker.gotoMarker('%s', (e) => window.getSelection().collapse(e, 0))" % str(marker))
        self.cleanup_links_dom()

        markEnabled = self.execute_js("CaretBrowsing.markEnabled")
        # reset to clear caret state so the next sentence can be marked
        if markEnabled:
            self.eval_js("CaretBrowsing.shutdown();")

        self.buffer.caret_enable_mark()
        self.buffer.caret_next_sentence()
        self.buffer.caret_browsing_mode = True

        eval_in_emacs('eaf--toggle-caret-browsing', ["'t"])

    def copy_code_content(self, marker):
        ''' Copy the code content according to marker.'''
        content = self.get_code_content(marker)
        if content != "":
            self.buffer.set_clipboard_text(content)
            message_to_emacs("Copied code block!")

    def get_focus_text(self):
        ''' Get the focus text.'''
        if self.get_focus_text_js is None:
            self.get_focus_text_js = self.read_js_content("get_focus_text.js")

        return self.execute_js(self.get_focus_text_js)

    @interactive
    def set_focus_text(self, new_text):
        ''' Set the focus text.'''
        new_text = base64.b64decode(new_text).decode("utf-8")

        if self.set_focus_text_raw is None:
            self.set_focus_text_raw = self.read_js_content("set_focus_text.js")

        self.set_focus_text_js = self.set_focus_text_raw.replace("%{new_text_base64}", string_to_base64(new_text))
        self.eval_js(self.set_focus_text_js)

    @interactive(insert_or_do=True)
    def focus_input(self):
        ''' input in focus.'''
        if self.focus_input_js is None:
            self.focus_input_js = self.read_js_content("focus_input.js")

        self.eval_js(self.focus_input_js)
        eval_in_emacs('eaf-update-focus-state', [self.buffer_id, "'t"])

    def get_cursor_word(self, x, y):
        get_cursor_word_js = self.read_js_content("get_cursor_word.js").replace("%{mouse_x}", str(x)).replace("%{mouse_y}", str(y))
        return self.execute_js(get_cursor_word_js)

    @interactive
    def clear_focus(self):
        ''' Clear the focus.'''
        if self.clear_focus_js is None:
            self.clear_focus_js = self.read_js_content("clear_focus.js")

        self.eval_js(self.clear_focus_js)
        eval_in_emacs('eaf-update-focus-state', [self.buffer_id, "'nil"])

    @interactive(insert_or_do=True)
    def immersive_translation(self):
        if shutil.which("crow"):
            if self.immersive_translation_js is None:
                self.immersive_translation_js = self.read_js_content("immersive_translation.js")

            translate_list = self.execute_js(self.immersive_translation_js)
            thread = TranslateThread(translate_list)
            thread.fetch_result.connect(self.handle_immersive_translation_result)
            self.thread_queue.append(thread)
            thread.start()

            message_to_emacs("Translate...")
        else:
            message_to_emacs("Please install the translation tool 'crow' before experiencing immersive translation.")

    @PostGui()
    def handle_immersive_translation_result(self, translates):
        if self.immersive_translation_response_js is None:
            self.immersive_translation_response_js = self.read_js_content("immersive_translation_response.js")

        self.eval_js(self.immersive_translation_response_js.replace("%1", json.dumps(translates)))

        message_to_emacs("Translate done.")

    def init_dark_mode_js(self, module_path, selection_color="auto", dark_mode_theme="dark",
                          dark_mode_custom_theme={
                              "brightness": 100,
                              "constrast": 90,
                              "sepia": 10,
                              "mode": 0,
                              "darkSchemeBackgroundColor": "#242525",
                              "darkSchemeForegroundColor": "#00CE00"}):
        import json
        self.dark_mode_js = open(os.path.join(os.path.dirname(module_path), "node_modules", "darkreader", "darkreader.js")).read()

        if selection_color != "auto":
            self.dark_mode_js = self.dark_mode_js.replace("selectionColor: 'auto'", "selectionColor: '" + selection_color + "'")

        self.dark_mode_js += """DarkReader.setFetchMethod(window.fetch);\n"""

        if dark_mode_theme == "dark":
            dark_mode_custom_theme["mode"] = 1
        else: # light theme
            dark_mode_custom_theme["mode"] = 0

        self.dark_mode_js += """DarkReader.enable(%s);""" % json.dumps(dark_mode_custom_theme)



