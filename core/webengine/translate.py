#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess

from core.utils import *
from PyQt6 import QtCore
from PyQt6.QtCore import QThread

class TranslateThread(QThread):

    fetch_result = QtCore.pyqtSignal(list)

    def __init__(self, texts):
        QThread.__init__(self)

        self.texts = texts

    def get_command_result(self, command_string):
        import subprocess
        process = subprocess.Popen(command_string, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.wait()
        result = process.stdout.readlines()
        return result

    def run(self):
        if self.texts is None:
            message_to_emacs("Not fetch words, please try agian.")
        else:
            separator = "<meta name='google' content='notranslate'/>"
            text = ''.join(list(map(lambda t: f"{separator}{t}\n", self.texts)))
            self.cache_file = tempfile.NamedTemporaryFile(mode="w", delete=False)
            self.cache_file_path = self.cache_file.name

            with open(self.cache_file_path, "w") as f:
                f.write(text)

            result = self.get_command_result("crow -t 'zh-CN' --j -e 'google' -f {}".format(self.cache_file_path))
            translation = json.loads(''.join(list(map(lambda b: b.decode("utf-8"), result))))["translation"]

            if os.path.exists(self.cache_file_path):
                os.remove(self.cache_file_path)

            if len(translation) > 0:
                translates = translation.split(separator)[1:]

                self.fetch_result.emit(translates)

