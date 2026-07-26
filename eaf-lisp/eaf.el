;;; eaf.el --- Emacs application framework  -*- lexical-binding: t; -*-

;; Filename: eaf.el
;; Description: Emacs application framework
;; Author: Andy Stewart <lazycat.manatee@gmail.com>
;; Maintainer: Andy Stewart <lazycat.manatee@gmail.com>
;; Copyright (C) 2018, Andy Stewart, all rights reserved.
;; Created: 2018-06-15 14:10:12
;; Version: 0.5
;; Last-Updated: Fri Apr  8 12:23:33 2022 (-0400)
;;           By: Mingde (Matthew) Zeng
;; URL: https://github.com/emacs-eaf/emacs-application-framework
;; Keywords:
;; Compatibility: emacs-version >= 27
;;
;; Features that might be required by this library:
;;
;; Please check README
;;

;;; This file is NOT part of GNU Emacs

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Emacs Application Framework
;;

;;; Installation:
;;
;; Please check README
;;

;;; Customize:
;;
;;
;;
;; All of the above can customize by:
;;      M-x customize-group RET eaf RET
;;

;;; Change log:
;;
;; 2018/06/15
;;      * First released.
;;

;;; Acknowledgements:
;;
;;
;;

;;; TODO
;;
;;
;;

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'map)
(require 'seq)
(require 'subr-x)
(require 'bookmark)

(declare-function straight--symlink-recursively "straight")

(define-obsolete-function-alias 'eaf-setq 'setq "Version 0.5, Commit d8abd23"
  "See https://github.com/emacs-eaf/emacs-application-framework/issues/734.
for more information.

In summary, the EAF's python applications can now access users' customized
variables with the get_emacs_var module, eliminating the need to store
them in `eaf-var-list' and thus, `eaf-setq' is no longer necessary.")

(defvar eaf-app-binding-alist '()
  "Mapping app names to keybinding variables.

Any new app should add the its name and the corresponding
keybinding variable to this list.")

(defvar eaf-app-module-path-alist '())

(defvar eaf-app-bookmark-handlers-alist '()
  "Mapping app names to bookmark handler functions.

A bookmark handler function is used as
`bookmark-make-record-function' and should follow its spec.")

(defvar eaf-app-bookmark-restore-alist '())


(defvar eaf-preview-display-function-alist '()
  "Preview display function.")

(defvar eaf-app-extensions-alist '()
  "Mapping app names to extension list variables.

A new app can use this to configure extensions which should
handled by it.")

(defvar eaf-app-hook-alist '()
  "Application running hook.")

(defvar eaf-build-dir (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))
(defvar eaf-source-dir eaf-build-dir)

;; Helper functions for generating the defcustom entry for the list of apps
(defun eaf--alist-to-defcustom-const (entry)
  "Map an alist for an app to an entry for the defcustom set"
  `(const :tag ,(cdr (assoc 'name entry)) ,(car entry)))

(defun eaf--json-to-defcustom-set ()
  "Generate the 'set choice for the defcustom entry"
  (let ((apps-alist
         (with-temp-buffer
           (insert-file-contents (concat eaf-build-dir "applications.json"))
           (goto-char 0)
           (json-parse-buffer :object-type 'alist))))
    (cons 'set (mapcar 'eaf--alist-to-defcustom-const (cdr apps-alist)))))

(defcustom eaf-apps-to-install nil
  "List of applications to install"
  :group 'eaf
  :type (eaf--json-to-defcustom-set))

(defun eaf-add-subdirs-to-load-path (search-dir)
  (interactive)
  (let* ((dir (file-name-as-directory search-dir)))
    (dolist (subdir
             (cl-remove-if
              #'(lambda (subdir)
                  (or
                   (not (file-directory-p (concat dir subdir)))
                   (member subdir '("." ".."
                                    "dist" "node_modules" "__pycache__"
                                    "RCS" "CVS" "rcs" "cvs" ".git" ".github"))))
              (directory-files dir)))
      (let ((subdir-path (concat dir (file-name-as-directory subdir))))
        (when (cl-some #'(lambda (subdir-file)
                           (and (file-regular-p (concat subdir-path subdir-file))
                                (member (file-name-extension subdir-file) '("el" "so" "dll"))))
                       (directory-files subdir-path))
          (add-to-list 'load-path subdir-path t))

        (eaf-add-subdirs-to-load-path subdir-path)))))

;; Add EAF app directories where .el exists to `load-path'.
(eaf-add-subdirs-to-load-path eaf-build-dir)

(require 'eaf-epc)

(defgroup eaf nil
  "Emacs Application Framework."
  :group 'applications)

(defcustom eaf-mode-hook '()
  "EAF mode hook."
  :type 'hook)

(defcustom eaf-mode-line-format mode-line-format
  "`mode-line-format' used by eaf-mode.")

(defcustom eaf-frame-title-format frame-title-format
  "`frame-title-format' used by eaf-mode.")

(defvar eaf-mode-map*
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-h m") #'eaf-describe-bindings)
    (define-key map (kbd "C-o") #'eaf-duplicate-current-buffer)
    (define-key map [remap describe-bindings] #'eaf-describe-bindings)
    (define-key map (kbd "C-c b") #'eaf-open-bookmark)
    (define-key map (kbd "C-c i") #'eaf-import-chrome-bookmarks)
    (define-key map (kbd "C-c e") #'eaf-open-external)
    (define-key map (kbd "C-h k") #'describe-key)
    (define-key map (kbd "C-h v") #'describe-variable)
    (define-key map (kbd "C-h f") #'describe-function)
    (define-key map (kbd "C-h V") #'apropos-variable)
    (define-key map (kbd "C-h F") #'apropos-function)
    (define-key map (kbd "M-0") #'eaf-get-buffer-screenshot)
    (define-key map (kbd "M-'") #'eaf-toggle-fullscreen)
    (define-key map (kbd "M-/") #'eaf-get-path-or-url)
    (define-key map (kbd "M-[") #'eaf-share-path-or-url)
    (define-key map (vector 'remap #'keyboard-quit) #'eaf-keyboard-quit)
    (define-key map (vector 'remap #'self-insert-command) #'eaf-send-key)
    (dolist (single-key '("RET" "DEL" "TAB" "SPC" "<backtab>" "<home>" "<end>" "<left>" "<right>" "<up>" "<down>" "<prior>" "<next>" "<delete>" "<backspace>" "<return>"))
      (define-key map (kbd single-key) #'eaf-send-key))
    map)
  "Keymap for default bindings available in all apps.")

(defvar eaf-mode-map nil
  "Keymap used by `eaf-mode'.

Don't modify this map directly.  To bind keys for all apps use
`eaf-mode-map*' and to bind keys for individual apps use
`eaf-bind-key'.")

(defvar eaf-server nil
  "The EAF Server.")


(defun eaf-describe-bindings ()
  "Like `describe-bindings' for EAF buffers."
  (interactive)
  (let ((emulation-mode-map-alists nil)
        (eaf-mode-map (current-local-map)))
    (call-interactively 'describe-mode)))

(defvar-local eaf--buffer-id nil
  "Internal id used by EAF app.")

(defvar-local eaf--buffer-url nil
  "EAF buffer-local URL.")

(defvar-local eaf--buffer-app-name nil
  "EAF buffer-local app-name.")

(defvar-local eaf--buffer-args nil
  "EAF buffer-local args.")

(defvar-local eaf--buffer-map-alist nil
  "EAF buffer-local map alist.")

(defvar-local eaf--buffer-map-alist-order 1
  "Order of EAF buffer-local map alist in `emulation-mode-map-alists'.")

(define-derived-mode eaf-mode fundamental-mode "EAF"
  "Major mode for Emacs Application Framework buffers.

This mode is used by all apps. The mode map `eaf-mode-map' is
created dynamically for each app and should not be changed
manually. See `eaf-bind-key' for customization of app bindings.

Within EAF buffers the variable `eaf--buffer-app-name' holds the
name of the current app. Each app can setup app hooks by using
`eaf-<app-name>-hook'. This hook runs after the app buffer has
been initialized."
  (if (require 'holo-layer nil t)
      ;; Don't show mode-line if `holo-layer' is installed.
      (setq-local mode-line-format nil)
    ;; Let eaf can set its mode-line and frame-title.
    (setq-local mode-line-format eaf-mode-line-format))

  (setq-local frame-title-format eaf-frame-title-format)
  ;; Split window combinations proportionally.
  (setq-local window-combination-resize t)
  ;; Disable cursor in eaf buffer.
  (setq-local cursor-type nil)

  (set (make-local-variable 'eaf--buffer-id) (eaf--generate-id))
  (setq-local bookmark-make-record-function #'eaf--bookmark-make-record)

  ;; Copy default value in case user already has bindings there
  (setq-local emulation-mode-map-alists
              (copy-alist (default-value 'emulation-mode-map-alists)))
  ;; Construct map alist
  (setq-local eaf--buffer-map-alist (list (cons t eaf-mode-map)))
  ;; Eanble mode map and make it the first priority
  (add-to-ordered-list
   'emulation-mode-map-alists
   'eaf--buffer-map-alist
   'eaf--buffer-map-alist-order)

  (add-hook 'kill-buffer-hook #'eaf--monitor-buffer-kill nil t)
  (add-hook 'kill-emacs-hook #'eaf--monitor-emacs-kill))

(defvar eaf-python-file (expand-file-name "eaf/__init__.py" (file-name-directory (directory-file-name (file-name-directory load-file-name)))))

(defvar eaf-server-port nil)


(defvar eaf-epc-process nil)

(defvar eaf-internal-process nil)
(defvar eaf-internal-process-prog nil)
(defvar eaf-internal-process-args nil)

(defvar eaf--first-start-app-buffers nil
  "Contains a list of '(buffer-url buffer-app-name buffer-args).")

(defvar eaf-last-frame-width 0)

(defvar eaf-last-frame-height 0)

(defcustom eaf-name "*eaf*"
  "Name of EAF buffer."
  :type 'string)

(defcustom eaf-python-command (if (memq system-type '(cygwin windows-nt ms-dos)) "python.exe" "python3")
  "The Python interpreter used to run eaf.py."
  :type 'string)

(defcustom eaf-config-location (expand-file-name (locate-user-emacs-file "eaf/"))
  "Directory where eaf will store configuration files."
  :type 'directory)

(defcustom eaf-marker-letters "ASDFHJKLWEOPCNM"
  ""
  :type 'string)

(defcustom eaf-marker-quit-keys " "
  ""
  :type 'string)

(defcustom eaf-marker-fontsize 11.5
  "Fontsize (px) of marker."
  :type 'number)

(defcustom eaf-buffer-background-color "#000000"
  ""
  :type 'string)

(defcustom eaf-webengine-show-hover-link nil
  ""
  :type 'boolean)

(defcustom eaf-find-file-ext-blacklist '("md" "org" "html" "htm" "epub")
  "A blacklist of extensions to avoid when opening `find-file' file using EAF."
  :type 'cons)

(defcustom eaf-proxy-host ""
  "Proxy Host used by EAF Browser."
  :type 'string)

(defcustom eaf-proxy-port ""
  "Proxy Port used by EAF Browser."
  :type 'string)

(defcustom eaf-proxy-type ""
  "Proxy Type used by EAF Browser.  The value is either \"http\" or \"socks5\"."
  :type 'string)

(defcustom eaf-webengine-default-zoom 1.0
  "Set the default zoom factor for EAF Browser."
  :type 'float)

(defcustom eaf-webengine-zoom-step 0.1
  "Set the zoom step factor for EAF Browser."
  :type 'float)

(defcustom eaf-webengine-scroll-step 400
  "Set the scroll step for EAF Browser, increase/decrease for bigger/smaller steps."
  :type 'float)

(defcustom eaf-webengine-pc-user-agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36"
  "Simulate a PC User-Agent for EAF Browser."
  :type 'string)

(defcustom eaf-webengine-phone-user-agent "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1"
  "Simulate a Phone User-Agent for EAF Browser."
  :type 'string)

(defcustom eaf-webengine-font-family ""
  "Set font family for EAF Browser."
  :type 'string)

(defcustom eaf-webengine-font-size 16
  "Set font size for EAF Browser."
  :type 'integer)

(defcustom eaf-webengine-fixed-font-family ""
  "Set fixed font family for EAF Browser."
  :type 'string)

(defcustom eaf-webengine-fixed-font-size 16
  "Set fixed font size for EAF Browser."
  :type 'integer)

(defcustom eaf-webengine-serif-font-family ""
  "Set serif font family for EAF Browser."
  :type 'string)

(defcustom eaf-webengine-enable-plugin t
  "If non-nil, enable QtWebEngine plugins for EAF Browser."
  :type 'boolean)

(defcustom eaf-webengine-enable-javascript t
  "If non-nil, enable javascript for EAF Browser."
  :type 'boolean)

(defcustom eaf-webengine-enable-javascript-access-clipboard t
  "If non-nil, enable javascript access user clipboard for EAF Browser."
  :type 'boolean)

(defcustom eaf-webengine-enable-scrollbar nil
  "If non-nil, enable scroll bar for EAF Browser."
  :type 'boolean)

(defcustom eaf-webengine-unknown-url-scheme-policy "AllowUnknownUrlSchemesFromUserInteraction"
  "Allowed options: DisallowUnknownUrlSchemes, AllowUnknownUrlSchemesFromUserInteraction, or AllowAllUnknownUrlSchemes."
  :type 'string)

(defcustom eaf-webengine-download-path "~/Downloads"
  "Set the download path for EAF Browser."
  :type 'string)

(defcustom eaf-enable-debug nil
  "If you got segfault error, please turn this option.
Then EAF will start by gdb, please send new issue with `*eaf*' buffer content when next crash."
  :type 'boolean)

(defcustom eaf-kill-process-after-last-buffer-closed nil
  "Kill eaf process when last eaf buffer closed, default is nil.

If you don't want EAF process exist when all EAF buffer closed, turn on this option.

Turn off this option will improve EAF new page creation speed."
  :type 'boolean)

(defcustom eaf-wm-name ""
  "The desktop name, set by function `eaf--get-current-desktop-name'."
  :type 'string)

(defcustom eaf-wm-focus-fix-wms
  `(
    "i3"                                ;i3
    "LG3D"                              ;QTile
    "Xpra"                              ;Windows WSL
    "EXWM"                              ;EXWM
    "Xfwm4"                             ;Xfce
    "wlroots wm" ;hyprland(may work in other Wayland compositors based on wlroots)
    )
  "Set mouse cursor to frame bottom in these wms, to make EAF receive input event.

EAF confirms that the desktop environment or window manager you can work includes:
KDE, Gnome2, Gnome3, Mate, Xfce, LXDE, Sway, i3, QTile, Xpra, EXWM.

In which, KDE, Gnome2, Gnome3, Mate, Xfce, LXDE, Sway works well default,
i3, QTile, Xpra, EXWM need move cursor to corner to get focus of Window manager.

If your window manager can't receive input event, you can try add `NAME' of command `wmctrl -m' to this list.

Please send PR if it works.
Please fill an issue if it still doesn't work."
  :type 'list)

(defcustom eaf-start-python-process-when-require t
  "Start EAF python process when require `eaf', default is turn on.

Turn on this option will improve start speed."
  :type 'boolean)

(defcustom eaf-byte-compile-apps nil
  "If this option turn on, EAF will byte-compile elisp code.")

(defcustom eaf-clean-duplicate-buffers t
  "Clean duplicate file manager buffers."
  :type 'boolean)

(defcustom eaf-goto-right-after-close-buffer nil
  "EAF will switch to right buffer after close current EAF buffer if this option is enable.

And you need re-implement `eaf-goto-right-tab' self."
  :type 'boolean)

(defcustom eaf-duplicate-buffer-survival-time 60
  "If file manager buffer not show in current frame, and existence time exceeds than 60 seconds,
EAF will remove the duplicate file manager buffer."
  :type 'integer)

(defcustom eaf-rebuild-buffer-after-crash t
  "Rebuild EAF buffer after it crash.

Turning on this option can quickly rebuild the buffer very conveniently, avoiding the current buffer crash and affecting other buffers.

Only turn off this option when you want investigate the cause of the crash."
  :type 'boolean)

(defcustom eaf-dired-advisor-enable t
  "Toggle to enable/disable the EAF advisor in dired.

When enabled, EAF will use eaf-file-manager to open file from dired."
  :type 'boolean)

(defvar eaf--monitor-configuration-p t
  "When this variable is non-nil, `eaf-monitor-configuration-change' executes.
This variable is used to open buffer in backend and avoid graphics blink.

EAF call python method `new_buffer' to create EAF application buffer.
EAF call python method `update_views' to create EAF application view.

Python process only create application view when Emacs window or buffer state change.")

(defvar eaf-fullscreen-p nil
  "When non-nil, EAF will intelligently hide modeline as necessray.")

(defvar eaf-buffer-title-format "%s")

(defvar-local eaf--bookmark-title nil)

(defmacro eaf-for-each-eaf-buffer (&rest body)
  "A syntactic sugar to loop through each EAF buffer and evaluat BODY.

Within BODY, `buffer' can be used to"
  `(dolist (buffer (eaf--get-eaf-buffers))
     (with-current-buffer buffer
       ,@body)))


(defun eaf-open-external ()
  "Command to open current path or url with external application."
  (interactive)
  (let ((path-or-url (eaf-get-path-or-url)))
    (cond ((memq system-type '(cygwin windows-nt ms-dos))
           (w32-shell-execute "open" path-or-url))
          ((eq system-type 'darwin)
           (shell-command (concat "open " (shell-quote-argument path-or-url))))
          ((eq system-type 'gnu/linux)
           (let ((process-connection-type nil))
             (start-process "" nil "xdg-open" path-or-url))))))

(defun eaf-call-async (method &rest args)
  "Call Python EPC function METHOD and ARGS asynchronously."
  (eaf-deferred-chain
    (eaf-epc-call-deferred eaf-epc-process (read method) args)))

(defun eaf-call-sync (method &rest args)
  "Call Python EPC function METHOD and ARGS synchronously."
  (eaf-epc-call-sync eaf-epc-process (read method) args))


(defvar eaf-start-process-hook nil)


(defun eaf--encode-string (str)
  "Encode string STR with UTF-8 coding using Base64."
  (base64-encode-string (encode-coding-string str 'utf-8)))


(defun eaf--generate-id ()
  "Randomly generate a seven digit id used for EAF buffers."
  (format "%04x-%04x-%04x-%04x-%04x-%04x-%04x"
          (random (expt 16 4))
          (random (expt 16 4))
          (random (expt 16 4))
          (random (expt 16 4))
          (random (expt 16 4))
          (random (expt 16 4))
          (random (expt 16 4))))

(defun eaf-execute-app-cmd (cmd &optional buf)
  "Execute app CMD.

If BUF is given it should be the EAF buffer for the command
otherwise it is assumed that the current buffer is the EAF
buffer."
  (with-current-buffer (or buf (current-buffer))
    (let ((this-command cmd))
      (call-interactively cmd))))

(defun eaf-copy-to-clipboard (string)
  (if (version< "29.0" emacs-version)
      (progn
        (kill-new string)
        string)
    (kill-new string)))

(defun eaf-get-path-or-url ()
  "Get the current file path or web URL.

When called interactively, copy to ‘kill-ring’."
  (interactive)
  (if (derived-mode-p 'eaf-mode)
      (if (called-interactively-p 'any)
          (message "%s" (eaf-copy-to-clipboard (eaf-call-sync "execute_function" eaf--buffer-id "get_url")))
        (eaf-call-sync "execute_function" eaf--buffer-id "get_url"))
    (user-error "This command can only be called in an EAF buffer!")))

(defun eaf-toggle-fullscreen ()
  "Toggle fullscreen."
  (interactive)
  (eaf-call-async "eval_function" eaf--buffer-id "toggle_fullscreen" (key-description (this-command-keys-vector))))

(defun eaf--enter-fullscreen-request ()
  "Entering fullscreen use Emacs frame's size."
  (message "[EAF] Enter fullscreen")
  (setq-local eaf-fullscreen-p t)
  (eaf-monitor-configuration-change)
  (when (and eaf-browser-fullscreen-move-cursor-corner
             (string= eaf--buffer-app-name "browser"))
    (eaf-call-async "eval_function" eaf--buffer-id "move_cursor_to_corner" (key-description (this-command-keys-vector)))))

(defun eaf--exit_fullscreen_request ()
  "Exit fullscreen."
  (message "[EAF] Exit fullscreen")
  (setq-local eaf-fullscreen-p nil)
  (eaf-monitor-configuration-change))

(defun eaf--make-py-proxy-function (fun)
  "Define elisp command which can call Python function string FUN."
  (let ((sym (intern (format "eaf-py-proxy-%s" fun))))
    (unless (fboundp sym)
      (defalias sym
        (lambda nil
          (interactive)
          ;; Ensure this is only called from EAF buffer
          (if (derived-mode-p 'eaf-mode)
              (eaf-call-async "eval_function" eaf--buffer-id fun (key-description (this-command-keys-vector)))
            (message "%s command can only be called in an EAF buffer!" sym)))
        (format
         "Proxy function to call \"%s\" on the Python side.

Use `eaf-execute-app-cmd' if you want to execute this command programmatically.
Please ONLY use `eaf-bind-key' and use the unprefixed command name (\"%s\")
to edit EAF keybindings!" fun fun)))
    sym))

(defun eaf--make-js-proxy-function (fun &optional args)
  "Define elisp command which can call JavaScript function string FUN."
  (let ((sym (intern (format "eaf-js-proxy-%s" fun))))
    (unless (fboundp sym)
      (defalias sym
        (lambda nil
          (interactive)
          (unless args
            (setq args ""))
          ;; Ensure this is only called from EAF buffer
          (when (derived-mode-p 'eaf-mode)
            (eaf-call-async "eval_js_function" eaf--buffer-id (string-trim-left fun "js_") args)
            ))
        (format
         "Proxy function to call \"%s\" on the JavaScript side.

Please ONLY use `eaf-bind-key' and use the unprefixed command name (\"%s\")
to edit EAF keybindings!" fun fun)))
    sym))

(defun eaf--gen-keybinding-map (keybinding &optional no-inherit-eaf-mode-map*)
  "Configure the `eaf-mode-map' from KEYBINDING, one of the eaf-.*-keybinding variables."
  (setq eaf-mode-map
        (let ((map (make-sparse-keymap)))
          (unless no-inherit-eaf-mode-map*
            (set-keymap-parent map eaf-mode-map*))
          (cl-loop for (key . fun) in (reverse keybinding)
                   do (define-key map (kbd key)
                                  (cond
                                   ;; If command is normal symbol, just call it directly.
                                   ((symbolp fun)
                                    fun)

                                   ;; If command is string and include - , it's elisp function, use `intern' build elisp function from function name.
                                   ((string-match "-" fun)
                                    (intern fun))

                                   ;; If command prefix with js_, call JavaScript function directly.
                                   ((string-prefix-p "js_" fun)
                                    (eaf--make-js-proxy-function fun))

                                   ;; If command is not built-in function and not include char '-'
                                   ;; it's command in python side, build elisp proxy function to call it.
                                   (t
                                    (eaf--make-py-proxy-function fun))
                                   ))
                   finally return map))))

(defun eaf--get-app-bindings (app-name)
  "Get the specified APP-NAME keybinding.

Every app has its name and the corresponding
keybinding variable to eaf-app-binding-alist."
  (symbol-value
   (cdr (assoc app-name eaf-app-binding-alist))))

(defun eaf--get-app-module-path (app-name)
  (symbol-value
   (cdr (assoc app-name eaf-app-module-path-alist))))

(defun eaf--get-app-hook (app-name)
  (funcall
   (cdr (assoc app-name eaf-app-hook-alist))))








(defun eaf-keyboard-quit ()
  "Wrap around `keyboard-quit' and signals a ‘quit’ condition to EAF applications."
  (interactive)
  (eaf-call-async "action_quit" eaf--buffer-id)
  (call-interactively 'keyboard-quit))

(defun eaf-send-key ()
  "Directly send key to EAF Python side."
  (interactive)
  (eaf-call-async "send_key" eaf--buffer-id (key-description (this-command-keys-vector))))

(defun eaf-send-key-sequence ()
  "Directly send key sequence to EAF Python side."
  (interactive)
  (eaf-call-async "send_key_sequence" eaf--buffer-id (key-description (this-command-keys-vector))))

(defmacro eaf-create-send-key-function (key &optional value)
  (let ((send-key-function (intern (format "eaf-send-%s-key" key))))
    `(defun ,send-key-function()
       (interactive)
       (eaf-call-async "send_key" eaf--buffer-id (or ,value (format "<%s>" ,key))))))

(defmacro eaf-create-send-sequence-function (key value)
  (let ((send-key-sequence-function (intern (format "eaf-send-%s-sequence" key))))
    `(defun ,send-key-sequence-function()
       (interactive)
       (eaf-call-async "send_key_sequence" eaf--buffer-id ,value))))

(eaf-create-send-key-function "left")
(eaf-create-send-key-function "right")
(eaf-create-send-key-function "down")
(eaf-create-send-key-function "up")
(eaf-create-send-key-function "escape")
(eaf-create-send-key-function "return" "RET")
(eaf-create-send-key-function "backspace" "DEL")

(eaf-create-send-sequence-function "ctrl-return" "C-RET")
(eaf-create-send-sequence-function "ctrl-delete" "C-<delete>")
(eaf-create-send-sequence-function "ctrl-backspace" "C-<backspace>")
(eaf-create-send-sequence-function "ctrl-left" "C-<left>")
(eaf-create-send-sequence-function "ctrl-right" "C-<right>")
(eaf-create-send-sequence-function "alt-backspace" "M-<backspace>")
(eaf-create-send-sequence-function "shift-return" "S-RET")

(defmacro eaf-bind-key (command key eaf-app-keybinding)
  "This function binds COMMAND to KEY in EAF-APP-KEYBINDING list.

Use this to bind keys for EAF applications.

COMMAND is a symbol of a regular Emacs command or a python app
command.  You can see a list of available commands by calling
`eaf-describe-bindings' in an EAF buffer.  The `eaf-proxy-' prefix
should be dropped for the COMMAND symbol.

KEY is a string representing a sequence of keystrokes and events.

EAF-APP-KEYBINDING is one of the `eaf-<app-name>-keybinding'
variables, where <app-name> can be obtained by checking the value
of `eaf--buffer-app-name' inside the EAF buffer."
  `(setf (map-elt ,eaf-app-keybinding ,key)
         ,(if (string-match "_" (symbol-name command))
              (symbol-name command)
            `(quote ,command))))


(defvar eaf-frame nil)


(defun eaf--update-modeline-icon ()
  "Update modeline icon if used"
  (when (and (ignore-errors (require 'all-the-icons)) (featurep 'eaf-all-the-icons))
    (declare-function eaf-all-the-icons-update-icon "eaf-all-the-icons.el")
    (eaf-all-the-icons-update-icon)))

(defun eaf-goto-left-tab ()
  "Go to left tab, you need re-implement this interface yourself."
  (interactive)
  (message "Go to left tab, you need re-implement eaf-goto-left-tab yourself."))

(defun eaf-goto-right-tab ()
  "Go to right tab, you need re-implement this interface yourself."
  (interactive)
  (message "Go to right tab, you need re-implement eaf-goto-right-tab yourself."))

(defun eaf-translate-text (text)
  "Translate selected TEXT."
  (message "You need re-implement eaf-translate-text yourself."))

(defun eaf--non-remote-default-directory ()
  "Return `default-directory' itself if is not part of remote, otherwise return $HOME."
  (if (or (file-remote-p default-directory)
          (not (file-accessible-directory-p default-directory)))
      (getenv "HOME")
    default-directory))

(defun eaf--get-app-for-extension (url)
  "Given the EXTENSION-NAME, loops through `eaf-app-extensions-alist', set and return `app-name'."
  (let ((extension-name (eaf-get-file-name-extension url))
        apps
        app)
    (dolist (app-extension eaf-app-extensions-alist)
      (when (member extension-name (symbol-value (cdr app-extension)))
        (add-to-list 'apps (car app-extension))))
    (if (= (length apps) 1)
        (car apps)
      (setq app (completing-read (format "Which app to open %s: " url) apps))
      (if (member app apps)
          app
        (error "Current application '%s' is not exists, please choose one application name from list %s" app apps)))))

;;;###autoload
(defun eaf-get-file-name-extension (file)
  "A wrapper around `file-name-extension' that downcases the extension of the FILE."
  (downcase (file-name-extension file)))

(defun eaf--translate-wsl-url-to-windows (path)
  "Translate from a WSL PATH to a Windows path."
  (replace-regexp-in-string "/mnt/\\([a-zA-Z]\\)" "\\1:" path))

;;;###autoload
(defun eaf-open (url &optional app-name args always-new)
  "Open an EAF application with URL, optional APP-NAME and ARGS.

Interactively, a prefix arg replaces ALWAYS-NEW, which means to open a new
 buffer regardless of whether a buffer with existing URL and APP-NAME exists.

By default, `eaf-open' will switch to buffer if corresponding url exists.
`eaf-open' always open new buffer if option OPEN-ALWAYS is non-nil.

When called interactively, URL accepts a file that can be opened by EAF."
  (interactive "G[EAF] EAF Open: ")
  ;; Try to set app-name along with url when calling INTERACTIVELY
  (when (and (not app-name) (file-exists-p url))
    ;; Expand file name.
    (setq url (expand-file-name url))

    ;; Add recentf list.
    (when (featurep 'recentf)
      (recentf-add-file url))

    ;; Adjust before open.
    (if (file-directory-p url)
        (setq app-name "file-manager")
      ;; Initialize url, app-name and args
      (setq app-name (eaf--get-app-for-extension url))
      (cond
       ((equal app-name "browser")
        (setq url (concat "file://" (if (equal system-type 'windows-nt) "/" "") url)))
       )))

  ;; Now that app-name should hopefully be set
  (unless app-name
    ;; Output error to user if app-name is empty string.
    (user-error (concat (if app-name (concat "[EAF/" app-name "] ") "[EAF] ")
                        (cond
                         ((not (or (string-prefix-p "/" url)
                                   (string-prefix-p "~" url))) "File %s cannot be opened.")
                         ((file-exists-p url) "File %s cannot be opened.")
                         (t "File %s does not exist.")))
                url))

  ;; Init arguments.
  (unless args (setq args ""))
  (setq always-new (or always-new current-prefix-arg))

  ;; Hooks are only added if not present already...
  (add-hook 'window-size-change-functions #'eaf-monitor-window-size-change)
  (add-hook 'window-configuration-change-hook #'eaf-monitor-configuration-change)

  ;; Open URL with EAF application
  (if (eaf-epc-live-p eaf-epc-process)
      (let (exists-eaf-buffer)
        ;; Try to open buffer           ; ;
        (catch 'found-eaf
          (eaf-for-each-eaf-buffer
           (when (and (string= eaf--buffer-url url)
                      (string= eaf--buffer-app-name app-name))
             (setq exists-eaf-buffer buffer)
             (throw 'found-eaf t))))

        ;; Switch to existing buffer,
        ;; if no match buffer found, call `eaf--open-internal'.
        (if (and exists-eaf-buffer
                 (not always-new))
            (progn
              (eaf--preview-display-buffer app-name exists-eaf-buffer)
              (message (concat "[EAF/" app-name "] " "Switch to %s") url))
          (eaf--open-internal url app-name args)
          (message (concat "[EAF/" app-name "] " "Opening %s") url)))

    ;; Record user input, and call `eaf--open-internal' after receive `start_finish' signal from server process.
    (unless eaf--first-start-app-buffers
      (push `(,url ,app-name ,args) eaf--first-start-app-buffers))

    ;; Start EAF process.
    (eaf-start-process)
    (message (concat "[EAF/" app-name "] " "Opening %s") url)))



;; Update and load the theme
(defun eaf-get-theme-mode ()
  (format "%s" (frame-parameter nil 'background-mode)))

(defun eaf-get-theme-background-color ()
  (format "%s" (frame-parameter nil 'background-color)))

(defun eaf-get-theme-foreground-color ()
  (format "%s" (frame-parameter nil 'foreground-color)))

(defun eaf--get-current-desktop-name ()
  "Get current desktop name by `wmctrl'."
  (if (string-empty-p eaf-wm-name)
      (if (executable-find "wmctrl")
          ;; Get desktop name by command `wmctrl -m'.
          (cl-second (split-string (cl-first (split-string (shell-command-to-string "wmctrl -m") "\n")) ": "))
        ;; Otherwise notify user and return emptry string.
        (message "You need install wmctrl to get the name of desktop.")
        "")
    eaf-wm-name))

(defvar eaf-is-member-of-focus-fix-wms
  (member (eaf--get-current-desktop-name) eaf-wm-focus-fix-wms))

(defun eaf--activate-emacs-win32-window()
  "Activate Emacs win32 window."
  (eaf-call-async "activate_emacs_win32_window" (frame-parameter nil 'name)))

(defvar eaf--emacs-program-name
  (string-trim
   (or
    (replace-regexp-in-string "\\." "-" (alist-get 'comm (process-attributes (emacs-pid))))
    "emacs"))
  "Name of Emacs.")

(defun eaf--activate-emacs-linux-window (&optional buffer_id)
  "Activate Emacs window by `wmctrl'."
  (let ((system-configuration-arguments (split-string system-configuration-features)))
    (if (or (member "LUCID" system-configuration-arguments)
            (member "ATHENA" system-configuration-arguments))
        (message "Please compile emacs use option --with-x-toolkit=gtk3, otherwise EAF can't focus emacs window expected.")
      (if eaf-is-member-of-focus-fix-wms
          ;; When switch app focus in WM, such as, i3 or qtile.
          ;; Emacs window cannot get the focus normally if mouse in EAF buffer area.
          ;;
          ;; So we move cursor to nearest screen border, triggering enter/leave
          ;; events that cause the WM to refocus Emacs.
	    (eaf-call-async "eval_function" (or eaf--buffer-id buffer_id) "move_cursor_to_nearest_border" (key-description (this-command-keys-vector)))

        ;; Activate the window by `wmctrl' when possible
        (if (executable-find "wmctrl")
            (shell-command-to-string (format "wmctrl -i -a $(wmctrl -lp | awk -vpid=$PID '$3==%s {print $1; exit}')" (emacs-pid)))
          (message "Please install wmctrl to active Emacs window."))))))

(defun eaf--activate-emacs-mac-window()
  "Activate Emacs macOS window."
  (shell-command-to-string "open -a emacs"))

(defun eaf-activate-emacs-window(&optional buffer_id)
  "Activate Emacs window."
  (cond
   ((or (memq system-type '(cygwin windows-nt ms-dos))
        (eaf--called-from-wsl-on-windows-p))
    (eaf--activate-emacs-win32-window))
   ((eq system-type 'darwin)
    (eaf--activate-emacs-mac-window))
   ((or (eq system-type 'gnu/linux)
        (eq system-type 'berkeley-unix))
    (eaf--activate-emacs-linux-window buffer_id))))


;;;;;;;;;;;;;;;;;;;; Utils ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun eaf-generate-keymap-doc (var)
  "This command use for generate keybindings document Wiki."
  (interactive "vEAF keybinding variable: ")
  (insert (format "### %s\n\n" (get var 'variable-documentation)))
  (insert "| Key   | Event   |\n")
  (insert "| :---- | :------ |\n")
  ;; NOTE: `standard-value' use for fetch origin value of keybinding variable.
  ;; Otherwise, developer's personal config will dirty document.
  (dolist (element (eval (car (get var 'standard-value))))
    (insert (format "| `%s` | %s |\n" (car element) (cdr element))))
  (insert "\n"))

(defun eaf--match-app-extension-p (ext)
  (cl-loop for app-extensions-alist in eaf-app-extensions-alist
           for extensions = (eval (cdr app-extensions-alist))
           when (member ext extensions)
           return t))

(defun eaf--buffer-file-p ()
  "Determine if the file opened at the current buffer be opened by EAF."
  (let ((ext (when (and buffer-file-name
                        (file-exists-p buffer-file-name))
               (file-name-extension buffer-file-name))))
    (and ext (eaf--match-app-extension-p (downcase ext)))))

(defun eaf-open-this-buffer ()
  "Try to open the current buffer using EAF, if possible."
  (interactive)
  (if (eaf--buffer-file-p)
      (eaf-open buffer-file-name)
    (user-error "[EAF] Current buffer is not supported by EAF!")))

(defun eaf--find-file-ext-p (ext)
  "Determine if file extension EXT can be opened by EAF directly by `find-file'.

You can configure a blacklist using `eaf-find-file-ext-blacklist'"
  (and ext
       (eaf--match-app-extension-p (downcase ext))
       (not (member ext eaf-find-file-ext-blacklist))))

(defun eaf-next-buffer-same-app ()
  "Switch to the next buffer of the same EAF app with the current buffer."
  (interactive)
  (let ((origin-buff (current-buffer)) (app-name mode-name)
        (new-buff nil) (finished nil))
    (while (not finished)
      (setq new-buff (next-buffer))
      (when (or (equal new-buff origin-buff) (equal app-name mode-name))
        (setq finished t)))))

(defun eaf-previous-buffer-same-app ()
  "Switch to the previous buffer of the same EAF app with the current buffer."
  (interactive)
  (let ((origin-buff (current-buffer)) (app-name mode-name)
        (new-buff nil) (finished nil))
    (while (not finished)
      (setq new-buff (previous-buffer))
      (when (or (equal new-buff origin-buff) (equal app-name mode-name))
        (setq finished t)))))

(defun eaf-share-path-or-url ()
  "Share the current file path or web URL as QRCode."
  (interactive)
  (if (ignore-errors (require 'eaf-airshare))
      (eaf-open (eaf-get-path-or-url) "airshare")
    (message "You should install EAF application 'airshare' first.")))

(defun eaf-open-devtool-page ()
  "Use EAF Browser to open the devtools page."
  (delete-other-windows)
  (split-window (selected-window) (round (* (nth 3 (eaf-get-window-allocation (selected-window))) 0.618)) nil t)
  (other-window 1)
  (eaf-open "about:blank" "browser" "devtools"))

;;;;;;;;;;;;;;;;;;;; Advice ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; FIXME: In the code below we should use `save-selected-window' (or even
;; better `with-selected-window') rather than (other-window +1) followed by
;; (other-window -1) since this is not always a no-op.

(defun eaf-ocr-buffer ()
  (interactive)
  (eaf-call-async "ocr_buffer" eaf--buffer-id))

(defun eaf-ocr-buffer-record (result)
  (kill-new result)
  (message "[EAF] Have paste OCR string to kill-ring."))

(defun eaf-get-buffer-screenshot ()
  (interactive)
  (eaf-call-async "screenshot_buffer" eaf--buffer-id))



(add-hook 'post-command-hook 'eaf-monitor-window-buffer-change)


(define-obsolete-function-alias 'eaf-install 'eaf-install-and-update
  "Please use M-x eaf-install-and-update instead.")


;; Load sub-modules after all functions are defined (avoids circular requires).
(require 'eaf-compat)
(require 'eaf-process)
(require 'eaf-window)
(require 'eaf-buffer)
(require 'eaf-edit)
(require 'eaf-bookmark)
(require 'eaf-hook)
(require 'eaf-install)

(provide 'eaf)

;;; eaf.el ends here
