#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from core.utils import eval_in_emacs, get_emacs_var, message_to_emacs
from PyQt6.QtCore import QThread

OCR_ADJUST_DICT = {
    " ,": ",",
    "一一一": " ── "
}

class OCRThread(QThread):

    def __init__(self, image_path):
        QThread.__init__(self)

        self.image_path = image_path

    def adjust_ocr(self, ocr_string):
        for char in OCR_ADJUST_DICT:
            ocr_string = ocr_string.replace(char, OCR_ADJUST_DICT[char])

        return ocr_string

    def run(self):
        try:
            message_to_emacs("Use PaddleOCR analyze screenshot, it's need few seconds to analyze...")
            import os
            python_command = get_emacs_var("eaf-python-command")
            command_string = "{} paddle_ocr.py {}".format(python_command, self.image_path)
            cwd = os.path.join(os.path.dirname(__file__), "..", "core")

            import subprocess
            process = subprocess.Popen(command_string, cwd=cwd, shell=True, text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            process.wait()
            string = process.stdout.readlines()[-1]    # type: ignore

            eval_in_emacs("eaf-ocr-buffer-record", [self.adjust_ocr(string)])
        except:
            import traceback
            traceback.print_exc()

            message_to_emacs("Use EasyOCR analyze screenshot, it's need few seconds to analyze...")

            try:
                import easyocr
                reader = easyocr.Reader(['ch_sim','en'])
                result = reader.readtext(self.image_path)
                string = ''.join(list(map(lambda r: r[1], result)))
                eval_in_emacs("eaf-ocr-buffer-record", [self.adjust_ocr(string)])
            except:
                import traceback
                traceback.print_exc()

                message_to_emacs("Please use pip3 install PaddleOCR or EasyOCR first.")

        import os
        os.remove(self.image_path)
