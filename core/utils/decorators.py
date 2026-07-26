#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from functools import wraps


def interactive(insert_or_do = False, msg_emacs = None, new_name = None):
    """
    Defines an interactive command invoked from Emacs.
    """
    def wrap(f, insert_or_do = insert_or_do, msg_emacs = msg_emacs, new_name = new_name):
        f.interactive = True
        f.insert_or_do = insert_or_do
        f.msg_emacs = msg_emacs
        f.new_name = new_name

        @wraps(f)
        def wrapped_f(*args, **kwargs):
            return f(*args, **kwargs)
        return wrapped_f

    # Support both @interactive and @interactive() as valid syntax.
    if callable(insert_or_do):
        return wrap(insert_or_do, insert_or_do = False, msg_emacs = None, new_name = None)
    else:
        return wrap


def abstract(f):
    """
    Add a `abstract` flag to a method,

    We don't use abs.abstractmethod cause we don't need strict
    implementation check.
    """
    f.abstract = True
    @wraps(f)
    def wrap(*args, **kwargs):
        return f(*args, **kwargs)
    return wrap
