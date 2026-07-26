#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import threading


def popen_and_call(popen_args, on_exit):
    """
    Runs the given args in a subprocess.Popen, and then calls the function
    on_exit when the subprocess completes.
    on_exit is a callable object, and popen_args is a list/tuple of args that
    would give to subprocess.Popen.
    """
    def run_in_thread(on_exit, popen_args):
        import subprocess

        try:
            proc = subprocess.Popen(popen_args,
                                    stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
            proc.wait()
        except OSError:
            import traceback
            traceback.print_exc()
        on_exit()
        return

    thread = threading.Thread(target=run_in_thread, args=(on_exit, popen_args))
    thread.start()
    # returns immediately after the thread starts
    return thread

def call_and_check_code(popen_args, on_exit):
    """
    Runs the given args in a subprocess.Popen, and then calls the function
    on_exit when the subprocess completes.
    on_exit is a callable object, and popen_args is a list/tuple of args that
    would give to subprocess.Popen.
    """
    def run_in_thread(on_exit, popen_args):
        import subprocess

        retcode = subprocess.call(popen_args,
                                  stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT)
        on_exit(retcode)
        return

    thread = threading.Thread(target=run_in_thread, args=(on_exit, popen_args))
    thread.start()
    # returns immediately after the thread starts
    return thread
