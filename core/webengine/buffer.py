#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import base64
import json
import os
import pathlib
import platform
import shutil
import tempfile
import threading
import urllib.parse
from urllib.parse import urlparse

from core.buffer import Buffer
from core.utils import *
from core.webengine.view import BrowserView
from core.webengine.profile import webengine_profile
from core.webengine.zoom import ZoomSizeDb
from PyQt6 import QtCore
from PyQt6.QtCore import QEvent, QEventLoop, QPoint, QPointF, Qt, QThread, QTimer, QUrl, pyqtSlot
from PyQt6.QtWebChannel import QWebChannel
from PyQt6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile, QWebEngineScript, QWebEngineSettings
from PyQt6.QtWebEngineWidgets import QWebEngineView
from PyQt6.QtWidgets import QApplication

class BrowserBuffer(Buffer):

    close_page = QtCore.pyqtSignal(str)
    open_devtools_tab = QtCore.pyqtSignal(object)

    def __init__(self, buffer_id, url, arguments, fit_to_view):
        Buffer.__init__(self, buffer_id, url, arguments, fit_to_view)

        self.profile = self._create_buffer_profile(buffer_id)

        self.add_widget(BrowserView(self.profile, buffer_id))

        self.url = url

        self.config_dir = get_emacs_config_dir()
        self.page_closed = False

        self.zoom_data = ZoomSizeDb(os.path.join(os.path.dirname(self.config_dir), "browser", "zoom_data.db"))

        (self.pc_user_agent,
         self.phone_user_agent,
         self.font_family,
         self.fixed_font_family,
         self.serif_font_family,
         self.font_size,
         self.fixed_font_size,
         self.enable_plugin,
         self.enable_javascript,
         self.enable_javascript_access_clipboard,
         self.enable_scrollbar,
         self.unknown_url_scheme_policy,
         self.download_path,
         self.default_zoom,
         self.zoom_step) = get_emacs_vars(
             ["eaf-webengine-pc-user-agent",
              "eaf-webengine-phone-user-agent",
              "eaf-webengine-font-family",
              "eaf-webengine-fixed-font-family",
              "eaf-webengine-serif-font-family",
              "eaf-webengine-font-size",
              "eaf-webengine-fixed-font-size",
              "eaf-webengine-enable-plugin",
              "eaf-webengine-enable-javascript",
              "eaf-webengine-enable-javascript-access-clipboard",
              "eaf-webengine-enable-scrollbar",
              "eaf-webengine-unknown-url-scheme-policy",
              "eaf-webengine-download-path",
              "eaf-webengine-default-zoom",
              "eaf-webengine-zoom-step"])

        self.profile.setHttpUserAgent(self.pc_user_agent)
        self._device_mode = "pc"

        self.caret_js_ready = False
        self.caret_browsing_mode = False
        self.caret_browsing_exit_flag = True
        self.caret_browsing_mark_activated = False
        self.caret_browsing_search_text = ""
        self.is_dark_mode_enabled = self.dark_mode_is_enabled()

        self.input_mode = False

        self.current_url = ""
        self.request_url = ""

        self.buffer_widget.web_page.windowCloseRequested.connect(self.close_buffer)
        self.buffer_widget.web_page.fullScreenRequested.connect(self.handle_fullscreen_request)
        self.buffer_widget.web_page.pdfPrintingFinished.connect(self.notify_print_message)
        self.buffer_widget.web_page.featurePermissionRequested.connect(self.permission_requested) # enable camera permission
        self.buffer_widget.titleChanged.connect(self.change_title)
        self.profile.downloadRequested.connect(self.handle_download_request)

        self.settings = self.buffer_widget.settings()
        try:

            if self.font_family:
                for ff in (
                        self.settings.FontFamily.StandardFont,
                        self.settings.FontFamily.CursiveFont,
                        self.settings.FontFamily.FantasyFont,
                        self.settings.FontFamily.PictographFont):
                    self.settings.setFontFamily(ff, self.font_family)

            if self.fixed_font_family:
                self.settings.setFontFamily(self.settings.FontFamily.FixedFont, self.fixed_font_family)

            if self.serif_font_family:
                for ff in (
                        self.settings.FontFamily.SerifFont,
                        self.settings.FontFamily.SansSerifFont):
                    self.settings.setFontFamily(ff, self.serif_font_family)

            self.settings.setFontSize(QWebEngineSettings.FontSize.DefaultFontSize, self.font_size)
            self.settings.setFontSize(QWebEngineSettings.FontSize.DefaultFixedFontSize, self.fixed_font_size)

            self.settings.setAttribute(QWebEngineSettings.WebAttribute.LocalStorageEnabled, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.FullScreenSupportEnabled, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.DnsPrefetchEnabled, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.FocusOnNavigationEnabled, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessRemoteUrls, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.AllowRunningInsecureContent, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.AllowGeolocationOnInsecureOrigins, True)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.PlaybackRequiresUserGesture, False)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.PluginsEnabled, self.enable_plugin)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.JavascriptEnabled, self.enable_javascript)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.JavascriptCanAccessClipboard, self.enable_javascript_access_clipboard)
            self.settings.setAttribute(QWebEngineSettings.WebAttribute.ShowScrollBars, self.enable_scrollbar)

            if self.unknown_url_scheme_policy == "DisallowUnknownUrlSchemes":
                self.settings.setUnknownUrlSchemePolicy(self.settings.UnknownUrlSchemePolicy.DisallowUnknownUrlSchemes)
            elif self.unknown_url_scheme_policy == "AllowUnknownUrlSchemesFromUserInteraction":
                self.settings.setUnknownUrlSchemePolicy(self.settings.UnknownUrlSchemePolicy.AllowUnknownUrlSchemesFromUserInteraction)
            elif self.unknown_url_scheme_policy == "AllowAllUnknownUrlSchemes":
                self.settings.setUnknownUrlSchemePolicy(self.settings.UnknownUrlSchemePolicy.AllowAllUnknownUrlSchemes)

        except Exception:
            import traceback
            traceback.print_exc()

        self.build_all_methods(self.buffer_widget)
        self.build_all_methods(self)

        # Reset with HiDPI.
        self.buffer_widget.zoom_reset()

        # Build webchannel object.
        QtCore.qInstallMessageHandler(self.filter_instant_message)
        self.channel = QWebChannel()
        self.channel.registerObject("pyobject", self)
        self.buffer_widget.web_page.setWebChannel(self.channel)

    def add_widget(self, widget):
        super(BrowserBuffer, self).add_widget(widget)
        # Set web page background.
        if hasattr(self.buffer_widget, "web_page"):
            self.init_web_page_background()

    @staticmethod
    def _create_buffer_profile(buffer_id):
        """Create a per-buffer QWebEngineProfile isolated from other buffers."""
        profile = QWebEngineProfile('eaf-' + buffer_id)
        profile.setPersistentCookiesPolicy(
            QWebEngineProfile.PersistentCookiesPolicy.ForcePersistentCookies)
        profile.setHttpCacheType(QWebEngineProfile.HttpCacheType.DiskHttpCache)
        # Inject dark-scheme override (same as shared profile).
        dark_script = QWebEngineScript()
        dark_script.setName("eaf-dark-scheme")
        dark_script.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentReady)
        dark_script.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld)
        dark_script.setRunsOnSubFrames(True)
        dark_script.setSourceCode("""
(function() {
    var orig = window.matchMedia;
    window.matchMedia = function(q) {
        var r = orig.call(window, q);
        if (q === '(prefers-color-scheme: dark)') {
            try { Object.defineProperty(r, 'matches', { get: function() { return true; } }); } catch(e) {}
        }
        return r;
    };
})();
""")
        profile.scripts().insert(dark_script)
        return profile

    def fetch_marker_callback(self):
        try:
            return list(map(lambda x: x.lower(),
                            self.buffer_widget.execute_js("Array.from(document.getElementsByClassName(\"eaf-marker\")).map(function(e) { return e.id });")))
        except Exception:
            return None

    def filter_instant_message(self, *args):
        # Disable QWebChannel warnings.
        if not args[-1].endswith('value updates in HTML will be broken!'):
            print("".join(list(map(str, args[2:]))))

    def permission_requested(self, frame, feature):
        self.buffer_widget.web_page.setFeaturePermission(frame, feature, QWebEnginePage.PermissionPolicy.PermissionGrantedByUser)

    def notify_print_message(self, file_path, success):
        ''' Notify the print as pdf message.'''
        if success:
            try:
                # Try to rename pdf file with title if title exists and title does not contain invalid file char.
                # Otherwise use host name (web pages) or filepath (local files) if title include invalid file char.
                if self.title:
                    title_path = os.path.join(os.path.expanduser(self.download_path), "{}.pdf".format(self.title))
                    os.rename(file_path, title_path)
                else:
                    title_path = file_path
                message_to_emacs("Successfully saved current webpage as '{}'.".format(title_path))
            except Exception:
                message_to_emacs("Successfully saved current webpage as '{}'.".format(file_path))
        else:
            message_to_emacs("Failed to save current webpage as '{}'.".format(file_path))

    def notify_monolith_message(self, download_path, file_path, title, retcode):
        ''' Notify the save as html message.'''
        if retcode == 0:
            title_path = os.path.join(os.path.expanduser(download_path), "{}.html".format(title))
            try:
                os.rename(file_path, title_path)
                message_to_emacs("Successfully saved current webpage as '{}'.".format(title_path))
            except Exception:
                message_to_emacs("Successfully saved current webpage as '{}'.".format(file_path))
        else:
            message_to_emacs("Failed to save current page as single file.")

    def dark_mode_is_enabled(self):
        ''' Return bool of whether dark mode is enabled.'''
        return False

    def dark_mode_js_load(self, progress):
        # is_dark_mode_enabled use for toggle dark mode.
        if self.is_dark_mode_enabled and self.dark_mode_is_enabled() and (self.buffer_widget.dark_mode_js is not None) and progress < 100:
            self.buffer_widget.eval_js(self.buffer_widget.dark_mode_js)

    def handle_fullscreen_request(self, request):
        ''' Handle fullscreen request.'''
        if request.toggleOn():
            self.enter_fullscreen_request.emit()
        else:
            self.exit_fullscreen_request.emit()

        request.accept()

    def should_skip_download_item(self, download_item):
        return download_item.page() != self.buffer_widget.web_page

    def handle_download_request(self, download_item):
        ''' Handle download request.'''
        if self.should_skip_download_item(download_item):
            return

        download_data = download_item.url().toString()

        if download_data.startswith("data:image/"):
            image_path = os.path.join(os.path.expanduser(self.download_path), "image.png")
            touch(image_path)
            with open(image_path, "wb") as f:
                b64bytes = download_data.split(",")[1].encode("utf-8")
                f.write(base64.b64decode(b64bytes))

            message_to_emacs("Save image: " + image_path)
        else:
            if hasattr(self, "try_start_aria2_daemon"):
                self.try_start_aria2_daemon()

                from core.pyaria2 import Jsonrpc

                download_url = download_item.url().toString()
                jsonrpc = Jsonrpc('127.0.0.1', 6800)
                jsonrpc.addUris(download_url)

                message_to_emacs("Downloading: " + download_url)

    def _save_as_pdf(self):
        parsed = urlparse(self.url)
        if parsed.netloc:
            pdf_filename = "{}.pdf".format(parsed.netloc)
        else:
            pdf_filename = "{}.pdf".format(os.path.basename(parsed.path))
        pdf_path = os.path.join(os.path.expanduser(self.download_path), pdf_filename)
        message_to_emacs("Saving as pdf...")
        self.buffer_widget.web_page.printToPdf(pdf_path)

    @interactive(insert_or_do=True)
    def save_as_pdf(self):
        ''' Request to save as pdf.'''
        self.send_input_message("Save current webpage as PDF?", "save_as_pdf", "yes-or-no")

    def _save_as_single_file(self):
        from functools import partial

        parsed = urlparse(self.url)
        file_path = os.path.join(os.path.expanduser(self.download_path), "{}.html".format(parsed.netloc))
        message_to_emacs("Saving as single file...")
        args = ["monolith", self.url, "-o", file_path]
        handler = partial(self.notify_monolith_message, self.download_path, file_path, self.title)
        call_and_check_code(args, handler)

    @interactive(insert_or_do=True)
    def save_as_single_file(self):
        ''' Request to save current webpage as single html file.'''
        import shutil
        if shutil.which("monolith") is None:
            message_to_emacs("Executable monolith not in PATH")
        else:
            self.send_input_message("Save current webpage as single html file?", "save_as_single_file", "yes-or-no")

    def _save_as_screenshot(self):
        screenshot_path = os.path.join(os.path.expanduser(self.download_path), "{}.png".format(self.title))
        message_to_emacs("Save as screenshot at {}".format(screenshot_path))
        self.buffer_widget.grab().save(screenshot_path, b'PNG')

    @interactive(insert_or_do=True)
    def save_as_screenshot(self):
        ''' Request to save current webpage as screenshot.'''
        self.send_input_message("Save current webpage as screenshot?", "save_as_screenshot", "yes-or-no")

    def destroy_buffer(self):
        ''' Destroy the buffer.'''
        # Record close page.
        self.close_page.emit(self.buffer_widget.get_url())

        # Load blank page to stop video playing, such as youtube.com.
        self.buffer_widget.setUrl(QUrl("about:blank"))

        if self.buffer_widget is not None:
            # NOTE: We need delete QWebEnginePage manual, otherwise QtWebEngineProcess won't quit.
            self.buffer_widget.web_page.deleteLater()
            self.buffer_widget.deleteLater()

    def get_key_event_widgets(self):
        ''' Send key event to QWebEngineView's focusProxy widget.'''
        # We need send key event to QWebEngineView's focusProxy widget, not QWebEngineView.
        return [self.buffer_widget.focusProxy()]

    @PostGui()
    def scroll_other_buffer(self, scroll_direction, scroll_type):
        ''' Scroll.'''
        if scroll_type == "page":
            if scroll_direction == "up":
                self.scroll_up_page()
            else:
                self.scroll_down_page()
        else:
            if scroll_direction == "up":
                self.scroll_up()
            else:
                self.scroll_down()

    @PostGui()
    def handle_input_response(self, callback_tag, result_content):
        ''' Handle input message.'''
        result_content = str(result_content)
        if callback_tag == "search_text_forward":
            self.buffer_widget._search_text(result_content)
        elif callback_tag == "search_text_backward":
            self.buffer_widget._search_text(result_content, True)
        elif callback_tag == "caret_search_text_forward":
            self._caret_search_text(result_content)
        elif callback_tag == "caret_search_text_backward":
            self._caret_search_text(result_content, True)
        elif callback_tag == "caret_at_line":
            self.buffer_widget._caret_at_line(result_content.strip())
        elif callback_tag == "open_link" or callback_tag == "select_marker_text":
            self.buffer_widget._open_link(result_content.strip())
        elif callback_tag == "open_link_new_buffer":
            self.buffer_widget._open_link_new_buffer(result_content.strip())
        elif callback_tag == "open_link_new_buffer_other_window":
            self.buffer_widget._open_link_new_buffer_other_window(result_content.strip())
        elif callback_tag == "jump_link_background_buffer":
            self.buffer_widget._open_link_background_buffer(result_content.strip())
        elif callback_tag == "copy_link":
            self.buffer_widget._copy_link(result_content.strip())
        elif callback_tag == "eval_js_file":
            self.buffer_widget.eval_js_file(result_content)
        elif callback_tag == "eval_js":
            self.buffer_widget.eval_js(result_content)
        elif callback_tag == "save_as_pdf":
            self._save_as_pdf()
        elif callback_tag == "save_as_single_file":
            self._save_as_single_file()
        elif callback_tag == "save_as_screenshot":
            self._save_as_screenshot()
        elif callback_tag == "edit_url":
            self.buffer_widget.open_url(result_content)
        elif callback_tag == "copy_code":
            self.buffer_widget.copy_code_content(result_content.strip())
        else:
            return False
        return True

    @PostGui()
    def cancel_input_response(self, callback_tag):
        ''' Cancel input message.'''
        if callback_tag == "open_link" or \
           callback_tag == "open_link_new_buffer" or \
           callback_tag == "open_link_new_buffer_other_window" or \
           callback_tag == "jump_link_background_buffer" or \
           callback_tag == "select_marker_text" or \
           callback_tag == "caret_at_line" or \
           callback_tag == "copy_link" or \
           callback_tag == "copy_code" or \
           callback_tag == "edit_url":
            self.buffer_widget.cleanup_links_dom()
        elif callback_tag == "search_text_forward" or callback_tag == "search_text_backward":
            self.buffer_widget.clean_search_and_select()

    @PostGui()
    def handle_search_forward(self, callback_tag):
        if callback_tag == "search_text_forward" or callback_tag == "search_text_backward":
            self.buffer_widget._search_text(self.buffer_widget.search_term)

    @PostGui()
    def handle_search_backward(self, callback_tag):
        if callback_tag == "search_text_forward" or callback_tag == "search_text_backward":
            self.buffer_widget._search_text(self.buffer_widget.search_term, True)

    @PostGui()
    def handle_search_finish(self, callback_tag):
        if callback_tag == "search_text_forward" or callback_tag == "search_text_backward":
            self.buffer_widget.clean_search()

    def caret_toggle_browsing(self):
        ''' Init caret browsing.'''
        if self.caret_js_ready:
            if self.caret_browsing_mode:
                self.buffer_widget.eval_js("CaretBrowsing.shutdown();")
                message_to_emacs("Caret browsing deactivated.")
                self.caret_browsing_mode = False
            else:
                self.buffer_widget.eval_js("CaretBrowsing.setInitialCursor();")
                message_to_emacs("Caret browsing activated.")
                self.caret_browsing_mode = True

        eval_in_emacs('eaf--toggle-caret-browsing', ["'t" if self.caret_browsing_mode else "'nil"])

    def caret_exit(self):
        ''' Exit caret browsing.'''
        if self.caret_browsing_mode:
            # Avoid popup tranlsate tips when exit caret mode.
            self.caret_browsing_exit_flag = True

            self.caret_toggle_browsing()

    @interactive
    def caret_next_sentence(self):
        ''' Switch to next line in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('forward', 'sentence');")

    @interactive
    def caret_previous_sentence(self):
        ''' Switch to previous line in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('backward', 'sentence');")

    @interactive
    def caret_next_line(self):
        ''' Switch to next line in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('forward', 'line');")

    @interactive
    def caret_previous_line(self):
        ''' Switch to previous line in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('backward', 'line');")

    @interactive
    def caret_next_character(self):
        ''' Switch to next character in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('forward', 'character');")

    @interactive
    def caret_previous_character(self):
        ''' Switch to previous character in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('backward', 'character');")

    @interactive
    def caret_next_word(self):
        ''' Switch to next word in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('forward', 'word');")

    @interactive
    def caret_previous_word(self):
        ''' Switch to previous word in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('backward', 'word');")

    @interactive
    def caret_to_bottom(self):
        ''' Switch to next word in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('forward', 'documentboundary');")

    @interactive
    def caret_to_top(self):
        ''' Switch to previous word in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.move('backward', 'documentboundary');")

    @interactive
    def caret_rotate_selection(self):
        ''' Rotate selection.'''
        if self.caret_browsing_mode:
            if self.caret_browsing_mark_activated:
                self.buffer_widget.eval_js("CaretBrowsing.rotateSelection();")

    @interactive
    def caret_enable_mark(self):
        ''' Toggle mark in caret browsing.'''
        if self.caret_browsing_mode:
            self.caret_browsing_mark_activated = True
            if not self.buffer_widget.execute_js("CaretBrowsing.markEnabled"):
                self.buffer_widget.eval_js("CaretBrowsing.toggleMark();")
                message_to_emacs("Caret Mark set")
        else:
            message_to_emacs("Not in Caret Browsing mode!")

    @interactive
    def caret_toggle_mark(self):
        ''' Toggle mark in caret browsing.'''
        if self.caret_browsing_mode:
            self.buffer_widget.eval_js("CaretBrowsing.toggleMark();")
            if self.buffer_widget.execute_js("CaretBrowsing.markEnabled"):
                self.caret_browsing_mark_activated = True
                message_to_emacs("Caret Mark set")
            else:
                self.caret_browsing_mark_activated = False
                message_to_emacs("Caret Mark deactivated")

    @interactive
    def caret_clear_search(self):
        ''' Clear search text in caret browsing.'''
        if self.caret_browsing_mode:
            if self.caret_browsing_mark_activated:
                self.caret_browsing_search_text = ""
                message_to_emacs("Cleared caret search text.")

    @interactive
    def caret_search_forward(self):
        ''' Search Text forward in caret browsing.'''
        if self.caret_browsing_mode:
            if self.caret_browsing_mark_activated:
                if self.caret_browsing_search_text == "":
                    self.send_input_message("Forward Search Text and Select: ", "caret_search_text_forward")
                else:
                    self._caret_search_text(self.caret_browsing_search_text)

    @interactive
    def caret_search_backward(self):
        ''' Search Text backward in caret browsing.'''
        if self.caret_browsing_mode:
            if self.caret_browsing_mark_activated:
                if self.caret_browsing_search_text == "":
                    self.send_input_message("Backward Search Text and Select: ", "caret_search_text_backward")
                else:
                    self._caret_search_text(self.caret_browsing_search_text,True)

    def _caret_search_text(self, text, is_backward = False):
        if self.caret_browsing_search_text != text:
            self.caret_browsing_search_text = text
        if is_backward:
            if not self.buffer_widget.execute_js("window.find('"+text+"',false,true)"):
                message_to_emacs("Unable to find more, please try forward search.")
        else:
            if not self.buffer_widget.execute_js("window.find('"+text+"')"):
                message_to_emacs("Unable to find more, please try backward search.")

    @interactive
    def caret_translate_text(self):
        self.translate_text()

    @interactive(insert_or_do=True)
    def translate_text(self):
        if self.buffer_widget.selectedText().strip() != "":
            self.buffer_widget.translate_selected_text.emit(self.buffer_widget.selectedText())

    def copy_text(self):
        ''' Copy selected text.'''
        self.buffer_widget.copy_text()
        message_to_emacs("Copied selected text.")

    @interactive
    def copy_code(self):
        ''' Copy code.'''
        self.buffer_widget.get_code_markers()
        self.send_input_message("Copy code: ", "copy_code", "marker")

    @interactive(insert_or_do=True)
    def select_text(self):
        ''' Select Text.'''
        self.buffer_widget.get_text_markers()
        self.send_input_message("Select Text: ", "select_marker_text", "marker")

    @interactive(insert_or_do=True)
    def caret_at_line(self):
        self.buffer_widget.get_text_markers()
        self.send_input_message("Toggle Caret Browsing at Line: ", "caret_at_line", "marker")

    @interactive(insert_or_do=True)
    def open_link(self):
        ''' Open Link through a marker.'''
        self.buffer_widget.get_link_markers()
        self.send_input_message("Open Link: ", "open_link", "marker")

    @interactive(insert_or_do=True)
    def open_link_new_buffer(self):
        ''' Open Link in New Buffer.'''
        self.buffer_widget.get_link_markers()
        self.send_input_message("Open Link in New Buffer: ", "open_link_new_buffer", "marker")

    @interactive(insert_or_do=True)
    def open_link_new_buffer_other_window(self):
        ''' Open Link in New Buffer in Other Window.'''
        self.buffer_widget.get_link_markers()
        self.send_input_message("Open Link in New Buffer in Other Window: ", "open_link_new_buffer_other_window", "marker")

    @interactive(insert_or_do=True)
    def open_link_background_buffer(self):
        ''' Open Link in Background Buffer.'''
        self.buffer_widget.get_link_markers()
        self.send_input_message("Open Link in Background Buffer: ", "jump_link_background_buffer", "marker")

    @interactive
    def copy_link(self):
        ''' Copy link.'''
        self.buffer_widget.get_link_markers()
        self.send_input_message("Copy link: ", "copy_link", "marker")

    @interactive(insert_or_do=True)
    def edit_url(self):
        ''' Edit link.'''
        self.send_input_message("Edit link: ", "edit_url", "string", self.url)

    def reset_default_zoom(self):
        ''' Reset default magnification.'''
        if hasattr(self, "buffer_widget"):
            result = self.zoom_data.get_entry(urlparse(self.url).hostname)
            zoom_factor = self.default_zoom
            for row in result:
                zoom_factor = float(row[0])

            self.buffer_widget.setZoomFactor(float(zoom_factor))

    def atomic_edit(self):
        ''' Edit the focus text.'''
        text = self.buffer_widget.get_focus_text()
        if text is not None:
            atomic_edit(self.buffer_id, text)
        else:
            self.buffer_widget.focus_input()

            # try again:
            text = self.buffer_widget.get_focus_text()
            if text is not None:
                atomic_edit(self.buffer_id, text)
            else:
                message_to_emacs("No active input element.")

    @interactive
    def switch_to_input_mode(self):
        self.input_mode = not self.input_mode

        if self.input_mode:
            message_to_emacs("Enable input mode.")
        else:
            message_to_emacs("Disable input mode.")

    def is_focus(self):
        ''' Return bool of whether the buffer is focused.'''
        if self.input_mode:
            return True
        else:
            input_focus = (self.buffer_widget.get_focus_text() is not None) or self.url.startswith("devtools://")

            eval_in_emacs("eaf-update-focus-state", [self.buffer_id, input_focus])

            return input_focus

    @interactive(insert_or_do=True)
    def duplicate_page(self):
        duplicate_page_in_new_tab(self.url)

    @interactive(insert_or_do=True)
    def open_browser(self):
        ''' Open browser.'''
        eval_in_emacs('call-interactively', ['\'eaf-open-browser-with-history'])

    def select_all_or_input_text(self):
        ''' Select all or input text.'''
        if self.is_focus():
            self.buffer_widget.select_input_text()
        else:
            self.buffer_widget.select_all()

    @interactive()
    def eval_js_file(self):
        ''' Eval JS file.'''
        self.send_input_message("Eval JS file: ", "eval_js_file", "file")

    @interactive()
    def eval_js(self):
        ''' Eval JS interactively.'''
        self.send_input_message("Eval JS: ", "eval_js")

    @interactive()
    def open_devtools(self):
        ''' Open dev-tool page.'''
        self.open_devtools_tab.emit(self.buffer_widget.web_page)

    @interactive(insert_or_do=True)
    def toggle_device(self):
        ''' Toggle device.'''
        if self._device_mode == "pc":
            self.profile.setHttpUserAgent(self.phone_user_agent)
            self._device_mode = "phone"
            self.set_aspect_ratio(2.0 / 3)
        else:
            self.profile.setHttpUserAgent(self.pc_user_agent)
            self._device_mode = "pc"
            self.set_aspect_ratio(0)

        self.refresh_page()

    @interactive
    def toggle_dark_mode(self):
        self.is_dark_mode_enabled = not self.is_dark_mode_enabled

        self.buffer_widget.reload()

    @interactive(insert_or_do=True)
    def history_forward(self):
        self.buffer_widget.history().forward()

        if platform.system() == "Windows":
            eval_in_emacs('eaf-activate-emacs-window', [])

    @interactive(insert_or_do=True)
    def history_backward(self):
        self.buffer_widget.history().back()

        if platform.system() == "Windows":
            eval_in_emacs('eaf-activate-emacs-window', [])

    @interactive(insert_or_do=True)
    def download_youtube_video(self):
        ''' Download Youtube Video.'''
        self.download_youtube_file()

    @interactive(insert_or_do=True)
    def download_youtube_audio(self):
        ''' Download Youtube Audio.'''
        self.download_youtube_file(True)

    def download_youtube_file(self, only_audio=False):
        ''' Download Youtube File.'''
        url = self.buffer_widget.get_url()
        if url.startswith("https://www.youtube.com"):
            import shutil

            if shutil.which("yt-dlp"):
                download_path = "{}/%(title)s-%(id)s.%(ext)s".format(os.path.expanduser(self.download_path))

                yt_dlp_args = ["yt-dlp"]
                if self.proxy_string != "":
                    yt_dlp_args.append("--proxy")
                    yt_dlp_args.append(self.proxy_string)
                yt_dlp_args.append(url)
                yt_dlp_args.append("-o")
                yt_dlp_args.append(download_path)

                file_type = "video"
                if only_audio:
                    yt_dlp_args.append("-x")
                    file_type = "audio"

                popen_and_call(yt_dlp_args, lambda : message_to_emacs("Downloaded: {0}".format(url)))

                message_to_emacs("Downloading {0}: {1}".format(file_type, url))
            else:
                message_to_emacs("Please install yt-dlp to use this feature.")
        else:
            message_to_emacs("Only videos from YouTube can be downloaded for now.")

    @PostGui()
    def eval_js_function(self, function_name, function_arguments):
        ''' Eval JavaScript function.'''
        if function_arguments == "":
            self.buffer_widget.eval_js('''{}()'''.format(to_camel_case(function_name)))
        else:
            self.buffer_widget.eval_js('''{}({})'''.format(to_camel_case(function_name), function_arguments))

    def execute_js_function(self, function_name, function_arguments):
        ''' Execute JavaScript function and return result.'''
        if function_arguments == "":
            return self.buffer_widget.execute_js('''{}()'''.format(to_camel_case(function_name)))
        else:
            return self.buffer_widget.execute_js('''{}({})'''.format(to_camel_case(function_name), function_arguments))

    @PostGui()
    def eval_js_code(self, js_code):
        ''' Eval JavaScript code.'''
        self.buffer_widget.eval_js(js_code)

    def execute_js_code(self, js_code):
        ''' Execute JavaScript code and return result.'''
        return self.buffer_widget.execute_js(js_code)

    def init_app(self):
        pass

    def load_index_html(self, app_file, index_dir="dist", join_path=False):
        self.buffer_widget.loadFinished.connect(self.init_app)

        self.index_file_dir = os.path.join(os.path.dirname(app_file), index_dir)
        self.index_file = os.path.join(self.index_file_dir, "index.html")

        with open(self.index_file, "r") as f:
            html = self.convert_index_html(f.read(), self.index_file_dir, join_path)
            self.buffer_widget.setHtml(html, QUrl("file://"))

    def convert_index_html(self, index_file_content, dist_dir, join_path):
        '''
        Convert path to absolute path and change body background.
        '''
        import lxml.html as LH

        base_dir = pathlib.Path(dist_dir)
        base_url = base_dir.as_uri()
        root = LH.fromstring(index_file_content)
        for el in root.iter('link'):
            if join_path:
                el.attrib['href'] = os.path.join(base_url, el.attrib["href"])
            else:
                el.attrib['href'] = "{}{}".format(base_url, el.attrib['href'])
        for el in root.iter('script'):
            if "src" in el.attrib:
                if join_path:
                    el.attrib['src'] = os.path.join(base_url, el.attrib['src'])
                else:
                    el.attrib['src'] = "{}{}".format(base_url, el.attrib['src'])
                el.attrib['type'] = "text/javascript"
        for el in root.iter('body'):
            el.attrib['style'] = "background: {}; color: {}".format(self.theme_background_color, self.theme_foreground_color)

        return LH.tostring(root, encoding=str)

    @QtCore.pyqtSlot(str, list)
    def eval_emacs_function(self, function_name, function_arguments):
        eval_in_emacs(function_name, function_arguments)

    def init_web_page_background(self):
        # Web page background follow Emacs's background.
        self.buffer_widget.web_page.setBackgroundColor(self.background_color)

    @interactive(insert_or_do=True)
    def change_url(self, url):
        # _change_url use PostGui make sure change url in main thread.
        self._change_url(url)

    @PostGui()
    def load_url_with_agent(self, url, agent):
        self.set_agent(agent)

        self.change_url(url)

    def set_agent(self, agent):
        if agent == "pc" and self._device_mode == "phone":
            self.profile.setHttpUserAgent(self.pc_user_agent)
            self._device_mode = "pc"
        elif agent == "phone" and self._device_mode == "pc":
            self.profile.setHttpUserAgent(self.phone_user_agent)
            self._device_mode = "phone"

    @PostGui()
    def _change_url(self, url):
        self.buffer_widget.stop()
        self.buffer_widget.setUrl(QUrl(url))

    def marker_offset_x(self):
        return 0

    def marker_offset_y(self):
        return 0

    @pyqtSlot(int)
    def update_progress(self, progress):
        ''' Update the Progress Bar.'''
        self.dark_mode_js_load(progress)

    @interactive
    def update_theme(self):
        self.theme_mode = get_emacs_theme_mode()
        self.theme_foreground_color = get_emacs_theme_foreground()
        self.theme_background_color = get_emacs_theme_background()
        self.buffer_widget.eval_js("document.body.style.background = '{}'; document.body.style.color = '{}'".format(
            self.theme_background_color, self.theme_foreground_color))


