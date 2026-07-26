#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os

import sexpdata


epc_client = None

def init_epc_client(emacs_server_port):
    from epc.client import EPCClient

    global epc_client

    if epc_client is None:
        try:
            epc_client = EPCClient(("127.0.0.1", emacs_server_port), log_traceback=True)
        except ConnectionRefusedError:
            import traceback
            traceback.print_exc()

def close_epc_client():
    global epc_client

    if epc_client is not None:
        epc_client.close()


def handle_arg_types(arg):
    if isinstance(arg, str) and arg.startswith("'"):
        arg = sexpdata.Symbol(arg.partition("'")[2])

    return sexpdata.Quoted(arg)

def eval_in_emacs(method_name, args):
    global epc_client

    args = [sexpdata.Symbol(method_name)] + list(map(handle_arg_types, args))    # type: ignore
    sexp = sexpdata.dumps(args)

    epc_client.call("eval-in-emacs", [sexp])    # type: ignore


def get_emacs_func_result(method_name, args):
    global epc_client

    args = [sexpdata.Symbol(method_name)] + list(map(handle_arg_types, args))    # type: ignore
    sexp = sexpdata.dumps(args)

    result = epc_client.call_sync("get-emacs-func-result", [sexp])    # type: ignore
    return result if result != [] else False

def get_app_dark_mode(app_dark_mode_var):
    app_dark_mode = get_emacs_var(app_dark_mode_var)
    return (app_dark_mode == "force" or \
            app_dark_mode is True or \
            (app_dark_mode == "follow" and \
             get_emacs_theme_mode() == "dark"))

def get_emacs_theme_mode():
    return get_emacs_func_result("eaf-get-theme-mode", [])

def get_emacs_theme_background():
    return get_emacs_func_result("eaf-get-theme-background-color", [])

def get_emacs_theme_foreground():
    return get_emacs_func_result("eaf-get-theme-foreground-color", [])

def message_to_emacs(message, prefix=True, logging=True):
    eval_in_emacs('eaf--show-message', [message, prefix, logging])

def clear_emacs_message():
    eval_in_emacs('eaf--clear-message', [])

def set_emacs_var(var_name, var_value):
    eval_in_emacs('eaf--set-emacs-var', [var_name, var_value])

def open_url_in_background_tab(url):
    eval_in_emacs('eaf-open-browser-in-background', [url])

def duplicate_page_in_new_tab(url):
    eval_in_emacs('eaf-browser--duplicate-page-in-new-tab', [url])

def open_url_in_new_tab(url):
    eval_in_emacs('eaf-open-browser', [url])

def open_url_in_new_tab_same_window(url, current_url):
    eval_in_emacs("eaf-open-browser-same-window", [url, current_url])

def open_url_in_new_tab_other_window(url):
    eval_in_emacs('eaf-open-browser-other-window', [url])

def translate_text(text):
    eval_in_emacs('eaf-translate-text', [text])

def input_message(buffer_id, message, callback_tag, input_type, input_content, completion_list):
    eval_in_emacs('eaf--input-message', [buffer_id, message, callback_tag, input_type, input_content, completion_list])

def focus_emacs_buffer(buffer_id):
    eval_in_emacs('eaf-focus-buffer', [buffer_id])

def atomic_edit(buffer_id, focus_text):
    eval_in_emacs('eaf--atomic-edit', [buffer_id, focus_text])

def convert_emacs_bool(symbol_value, symbol_is_boolean):
    if symbol_is_boolean == "t":
        return symbol_value is True
    else:
        return symbol_value

def get_emacs_vars(args):
    global epc_client

    return list(map(lambda result: convert_emacs_bool(result[0], result[1]) if result != [] else False, epc_client.call_sync("get-emacs-vars", args))) # type: ignore

def get_emacs_var(var_name):
    global epc_client

    (symbol_value, symbol_is_boolean) = epc_client.call_sync("get-emacs-var", [var_name]) # type: ignore

    return convert_emacs_bool(symbol_value, symbol_is_boolean)

emacs_config_dir = ""

def get_emacs_config_dir():
    global emacs_config_dir

    if emacs_config_dir == "":
        emacs_config_dir = os.path.join(os.path.expanduser(get_emacs_var("eaf-config-location")), '')

    if not os.path.exists(emacs_config_dir):
        os.makedirs(emacs_config_dir)

    return emacs_config_dir

emacs_func_cache_dict = {}

def get_emacs_func_cache_result(func_name, func_args):
    global emacs_func_cache_dict

    if func_name in emacs_func_cache_dict:
        return emacs_func_cache_dict[func_name]
    else:
        result = get_emacs_func_result(func_name, func_args)
        emacs_func_cache_dict[func_name] = result

        return result
