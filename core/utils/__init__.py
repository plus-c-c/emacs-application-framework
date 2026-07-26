#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from core.utils.post_gui import PostGui
from core.utils.file import touch
from core.utils.network import get_free_port, is_port_in_use, get_local_ip
from core.utils.string import string_to_base64, to_camel_case
from core.utils.process import popen_and_call, call_and_check_code
from core.utils.clipboard import get_clipboard_text, set_clipboard_text
from core.utils.decorators import interactive, abstract
from core.utils.emacs import (
    epc_client,
    init_epc_client,
    close_epc_client,
    handle_arg_types,
    eval_in_emacs,
    get_emacs_func_result,
    get_app_dark_mode,
    get_emacs_theme_mode,
    get_emacs_theme_background,
    get_emacs_theme_foreground,
    message_to_emacs,
    clear_emacs_message,
    set_emacs_var,
    open_url_in_background_tab,
    duplicate_page_in_new_tab,
    open_url_in_new_tab,
    open_url_in_new_tab_same_window,
    open_url_in_new_tab_other_window,
    translate_text,
    input_message,
    focus_emacs_buffer,
    atomic_edit,
    convert_emacs_bool,
    get_emacs_vars,
    get_emacs_var,
    emacs_config_dir,
    get_emacs_config_dir,
    emacs_func_cache_dict,
    get_emacs_func_cache_result,
)
from core.utils.qt import current_desktop, post_event, get_qrcode_pixmap
