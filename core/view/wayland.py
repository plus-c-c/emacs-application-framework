#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright (C) 2018 Andy Stewart
#
# Author:     Andy Stewart <lazycat.manatee@gmail.com>
# Maintainer: Andy Stewart <lazycat.manatee@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import subprocess

from core.utils import current_desktop, get_emacs_func_cache_result, get_emacs_var

reinput = None

if current_desktop in ["sway", "Hyprland"] and get_emacs_func_cache_result("eaf-emacs-running-in-wayland-native", []):
    build_dir = get_emacs_var("eaf-build-dir")
    reinput_file = build_dir + "reinput/reinput"
    pid = get_emacs_func_cache_result("emacs-pid", [])
    reinput = subprocess.Popen(f"{reinput_file} {pid}", stdin=subprocess.PIPE, shell=True)

def focus():
    reinput.stdin.write("1\n".encode("utf-8"))
    reinput.stdin.flush()

def lose_focus():
    reinput.stdin.write("0\n".encode("utf-8"))
    reinput.stdin.flush()
