#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
import sysconfig
from shutil import which

parser = argparse.ArgumentParser()
parser.add_argument("--install-core-deps", action="store_true",
                    help='only install/update core dependencies')
parser.add_argument("--ignore-core-deps", action="store_true",
                    help='ignore core dependencies')
parser.add_argument("--ignore-sys-deps", action="store_true",
                    help='ignore system dependencies')
parser.add_argument("--ignore-py-deps", action="store_true",
                    help='ignore python dependencies')
parser.add_argument("--ignore-node-deps", action="store_true",
                    help='ignore node dependencies')
args = parser.parse_args()

NPM_CMD = "npm.cmd" if sys.platform == "win32" else "npm"
PIP_CMD = "pip3" if which("pip3") else "pip"

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

script_path = os.path.dirname(os.path.realpath(__file__))

install_failed_sys = []
install_failed_pys = []
install_failed_npm_globals = []

def run_command(command, path=script_path, ensure_pass=True, get_result=False):
    print("[EAF] Running", ' '.join(command), "@", path)

    if not which(command[0]):
        return Exception(f"Not found command: {command[0]}")

    english_env = os.environ.copy()
    english_env['LC_ALL'] = 'C'

    if get_result:
        process = subprocess.Popen(command, env=english_env, stdin=subprocess.PIPE,
                                   universal_newlines=True, text=True, cwd=path,
                                   stdout=subprocess.PIPE)
    else:
        process = subprocess.Popen(command, env=english_env, stdin=subprocess.PIPE,
                                   universal_newlines=True, text=True, cwd=path)
    process.wait()
    if process.returncode != 0 and ensure_pass:
        raise Exception(process.returncode)
    if get_result:
        return process.stdout.readlines()
    else:
        return None

def prune_existing_sys_deps(deps_list):
    remove_deps = []
    for dep in deps_list:
        if "node" in dep and which("node"):
            remove_deps.append(dep)
        elif "npm" in dep and which("npm"):
            remove_deps.append(dep)
    return list(set(deps_list) - set(remove_deps))

def get_archlinux_aur_helper():
    command = None
    for helper in ["paru", "pacaur", "yay", "yaourt", "aura"]:
        if which(helper):
            command = helper
            break
    if command:
        return command
    else:
        print("Please install one of AUR's helper, such as 'pacaur', 'yay', 'yaourt', 'paru', etc.", file=sys.stderr)
        sys.exit(1)

def install_sys_deps(distro, deps_list):
    deps_list = prune_existing_sys_deps(deps_list)
    command = []
    if distro == 'dnf':
        command = ['sudo', 'dnf', '-y', 'install']
    elif distro == 'emerge':
        command = ['sudo', 'emerge', "--update"]
    elif distro == 'apt':
        command = ['sudo', 'apt', '-y', 'install']
    elif distro == 'pacman':
        aur_helper = get_archlinux_aur_helper()
        command = [aur_helper, '-Sy', '--noconfirm', '--needed']
    elif which("pkg"):
        command = ['doas', 'pkg', '-y', 'install']
    elif which("guix"):
        command = ['guix', 'install']
    elif which("nix"):
        command = ['nix', 'profile', 'install']
    elif which("zypper"):
        command = ['sudo', 'zypper', 'install','-y']
    command.extend(deps_list)
    try:
        run_command(command)
    except Exception as e:
        print("Error: {}".format(e))
        install_failed_sys.append(' '.join(command))

def install_py_deps(deps_list):
    if sys.prefix == sys.base_prefix:
        if get_distro() != "guix" and os.path.exists(os.path.join(sysconfig.get_path("stdlib", sysconfig.get_default_scheme() if hasattr(sysconfig, "get_default_scheme") else sysconfig._get_default_scheme()),"EXTERNALLY-MANAGED")):
            command = [PIP_CMD, 'install', '--user', '--break-system-packages', '-U']
        else:
            command = [PIP_CMD, 'install', '--user', '-U']
    else:
        command = [PIP_CMD, 'install', '-U']
    command.extend(deps_list)
    try:
        run_command(command)
    except Exception as e:
        print("Error:", e)
        install_failed_pys.append(' '.join(command))

def install_npm_global_deps(deps_list):
    command = ["sudo", NPM_CMD, "install", "-g"]
    command.extend(deps_list)
    try:
        run_command(command)
    except Exception as e:
        print("Error:", e)
        install_failed_npm_globals.append(' '.join(command))

def install_npm_install(app_path_list):
    for app_path in app_path_list:
        command = [NPM_CMD, "install", "--force"]
        try:
            run_command(command, path=app_path)
        except Exception as e:
            print("Error:", e)

def install_npm_rebuild(app_path_list):
    for app_path in app_path_list:
        command = [NPM_CMD, "rebuild"]
        try:
            run_command(command, path=app_path)
        except Exception as e:
            print("Error:", e)

def install_vue_install(app_path_list):
    for app_path in app_path_list:
        command = [NPM_CMD, "install", "--force"]
        try:
            run_command(command, path=app_path)
        except Exception as e:
            print("Error:", e)
        command = [NPM_CMD, "run", "build"]
        try:
            run_command(command, path=app_path)
        except Exception as e:
            print("Error:", e)

def get_distro():
    distro = ""
    if sys.platform != "linux":
        pass
    elif which("dnf"):
        distro = "dnf"
    elif which("emerge"):
        distro = "emerge"
    elif which("apt"):
        distro = "apt"
    elif which("pacman"):
        distro = "pacman"
        aur_helper = get_archlinux_aur_helper()
        if (not args.ignore_core_deps and not args.ignore_sys_deps and not args.install_core_deps):
            try:
                run_command([aur_helper, '-Sy', '--noconfirm', '--needed'])
            except:
                print("Run command `{} -Sy --noconfirm --needed' failed.".format(aur_helper))
    elif which("pkg"):
        distro = "pkg"
    elif which("guix"):
        distro = "guix"
    elif which("zypper"):
        distro = "zypper"
    elif which("brew"):
        distro = "brew"
    elif which("nix"):
        distro = "nix"
    elif sys.platform == "linux":
        print("[EAF] Unsupported Linux distribution/package manager.")
        print(" Please see dependencies.json for list of dependencies.")
        if not (args.ignore_core_deps or args.ignore_sys_deps):
            sys.exit(1)

    return distro

def get_available_apps():
    with open(os.path.join(script_path, 'applications.json')) as f:
        info = json.load(f)
    apps = {}
    for app_name, app_spec_dict in info.items():
        if app_spec_dict["type"] == "app":
            apps[app_name] = app_spec_dict
    return apps

def get_installed_apps(app_dir):
    if not os.path.exists(app_dir):
        return []
    available = get_available_apps()
    apps_installed = [
        f
        for f in os.listdir(app_dir)
        if os.path.isdir(os.path.join(app_dir, f))
        if f not in ("__pycache__",)
        if f in available
    ]
    return apps_installed

def install_core_deps(distro, deps_dict):
    print("[EAF] Installing core dependencies")
    core_deps = []
    if not args.ignore_sys_deps and sys.platform == "linux":
        core_deps.extend(deps_dict[distro])
        if len(core_deps) > 0:
            install_sys_deps(distro, core_deps)
    if (not args.ignore_py_deps or sys.platform != "linux") and sys.platform in deps_dict["pip"]:
        distro = get_distro()
        if distro in deps_dict["pip"]:
            install_py_deps(deps_dict["pip"][distro])
        else:
            install_py_deps(deps_dict["pip"][sys.platform])

    print("[EAF] Finished installing core dependencies")

def install_app_deps(distro, deps_dict):
    print("[EAF] Installing application dependencies")

    app_dir = os.path.join(script_path, "app")
    apps_installed = get_installed_apps(app_dir)

    if len(apps_installed) == 0:
        print("[EAF] No applications found in app/ directory.")
        print("[EAF] Applications should be pre-installed in the app/ directory.")
        return

    print("[EAF] Found applications:", ", ".join(apps_installed))

    sys_deps = []
    py_deps = []
    npm_global_deps = []
    npm_install_apps = []
    vue_install_apps = []
    npm_rebuild_apps = []

    for app_name in apps_installed:
        app_path = os.path.join(app_dir, app_name)
        app_dep_path = os.path.join(app_path, 'dependencies.json')
        if os.path.exists(app_dep_path):
            with open(app_dep_path) as f:
                app_deps = json.load(f)
            if not args.ignore_sys_deps and sys.platform == "linux" and distro in app_deps:
                sys_deps.extend(app_deps[distro])
            if not args.ignore_py_deps and 'pip' in app_deps and sys.platform in app_deps['pip']:
                py_deps.extend(app_deps['pip'][sys.platform])
            if "npm_global" in app_deps:
                npm_global_deps.extend(app_deps["npm_global"])
            if not args.ignore_node_deps:
                if 'npm_install' in app_deps and app_deps['npm_install']:
                    npm_install_apps.append(app_path)
                if 'vue_install' in app_deps and app_deps['vue_install']:
                    vue_install_apps.append(app_path)
                if 'npm_rebuild' in app_deps and app_deps['npm_rebuild']:
                    npm_rebuild_apps.append(app_path)

    print("\n[EAF] Installing dependencies for the selected applications")
    if not args.ignore_sys_deps and sys.platform == "linux" and len(sys_deps) > 0:
        print("[EAF] Installing system dependencies")
        install_sys_deps(distro, sys_deps)
    if not args.ignore_py_deps and len(py_deps) > 0:
        print("[EAF] Installing python dependencies")
        install_py_deps(py_deps)
    if len(npm_global_deps) > 0:
        install_npm_global_deps(npm_global_deps)
    if not args.ignore_node_deps:
        if len(npm_install_apps) > 0:
            install_npm_install(npm_install_apps)
        if len(npm_rebuild_apps) > 0:
            install_npm_rebuild(npm_rebuild_apps)
        if len(vue_install_apps) > 0:
            install_vue_install(vue_install_apps)

    global install_failed_sys
    global install_failed_pys
    global install_failed_npm_globals
    if len(install_failed_sys) > 0:
        install_failed_sys = list(set(install_failed_sys))
        print_warning_message("\n[EAF] Installation FAILED for the following system dependencies:")
        for dep in install_failed_sys:
            print_warning_message(dep)
    if len(install_failed_pys) > 0:
        install_failed_pys = list(set(install_failed_pys))
        print_warning_message("\n[EAF] Installation FAILED for the following Python dependencies:")
        for dep in install_failed_pys:
            print_warning_message(dep)
    if len(install_failed_npm_globals) > 0:
        install_failed_npm_globals = list(set(install_failed_npm_globals))
        print_warning_message("\n[EAF] Installation FAILED for the following NPM dependencies:")
        for dep in install_failed_npm_globals:
            print_warning_message(dep)
    if len(install_failed_sys) + len(install_failed_pys) == 0:
        print("[EAF] Installation SUCCESS!")
    else:
        print("[EAF] Please rerun ./install-eaf.py with `--force`, or install them manually!")

def print_warning_message(message):
    print(bcolors.WARNING + message + bcolors.ENDC)

def main():
    try:
        distro = get_distro()
        with open(os.path.join(script_path, 'dependencies.json')) as f:
            deps_dict = json.load(f)

        if not args.install_core_deps:
            print("[EAF] ------------------------------------------")
            install_core_deps(distro, deps_dict)
            print("[EAF] ------------------------------------------")

        if not args.ignore_core_deps:
            print("[EAF] ------------------------------------------")
            install_app_deps(distro, deps_dict)
            print("[EAF] ------------------------------------------")

        current_desktop = os.getenv("XDG_CURRENT_DESKTOP") or os.getenv("XDG_SESSION_DESKTOP")
        if current_desktop in ["Hyprland", "sway"]:
            print("[EAF] Compiling reinput")
            subprocess.Popen("gcc reinput/main.c -o reinput/reinput `pkg-config --cflags --libs libinput libevdev libudev`",
                             shell=True)

        print("[EAF] install-eaf.py finished.\n")

    except KeyboardInterrupt:
        print("[EAF] install-eaf.py aborted!")
        sys.exit()

if __name__ == '__main__':
    main()
