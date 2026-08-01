;;; eaf-compat.el --- Platform detection and geometry helpers  -*- lexical-binding: t; -*-

;; Forward declarations for eaf functions used here
(declare-function eaf-call-sync "eaf" (method &rest args))
(declare-function eaf-emacs-running-in-wayland-native "eaf" ())
(defvar eaf-python-command)
(defvar eaf-enable-debug)

(defun eaf--called-from-wsl-on-windows-p ()
  "Check whether eaf is called by Emacs on WSL and is running on Windows."
  (and (eq system-type 'gnu/linux)
       (string-match-p ".exe" eaf-python-command)))

(defun eaf-get-emacs-xid (frame)
  "Get Emacs FRAME xid."
  (if (eaf--called-from-wsl-on-windows-p)
      (eaf-call-sync "get_emacs_wsl_window_id")
    (frame-parameter frame 'window-id)))

(defun eaf-emacs-running-in-wayland-native ()
  (eq window-system 'pgtk))

(defun eaf--on-hyprland-p ()
  (string-equal (getenv "XDG_CURRENT_DESKTOP") "Hyprland"))

(defvar eaf--compositor-scale nil
  "Cached compositor scale factor (float).")

(defun eaf--get-compositor-scale ()
  "Return the compositor monitor scale factor (float), defaulting to 1.0."
  (or eaf--compositor-scale
      (setq eaf--compositor-scale
            (if (eaf--on-hyprland-p)
                (let ((json (shell-command-to-string "hyprctl -j monitors")))
                  (if (string-empty-p json) 1.0
                    (condition-case err
                        (let* ((monitors (json-parse-string json))
                               (scale-val (gethash "scale" (aref monitors 0))))
                          (string-to-number (format "%s" scale-val)))
                      (error 1.0))))
              1.0))))

(defun eaf--build-process-environment ()
  ;; Turn on DEBUG info when `eaf-enable-debug' is non-nil.
  (let ((environments (seq-filter
                       (lambda (var)
                         (and (not (string-match-p "QT_SCALE_FACTOR" var))
                              (not (string-match-p "QT_SCREEN_SCALE_FACTOR" var))))
                       process-environment)))
    (when eaf-enable-debug
      (add-to-list 'environments "QT_DEBUG_PLUGINS=1" t))

    (unless (eq system-type 'darwin)
      (add-to-list 'environments
                   (cond
                    ((eaf-emacs-running-in-wayland-native)
                     "QT_AUTO_SCREEN_SCALE_FACTOR=1")
                    (t
                     "QT_AUTO_SCREEN_SCALE_FACTOR=0"))
                   t)

      (let ((scale (eaf--get-compositor-scale)))
        ;; QT_FONT_DPI stays at 96 (default). Only QT_SCALE_FACTOR scales the DPR.
        ;; Setting both QT_FONT_DPI>96 AND QT_SCALE_FACTOR>1 causes DPR to multiply (e.g. 2*2=4).
        (add-to-list 'environments "QT_FONT_DPI=96" t)
        (add-to-list 'environments (format "QT_SCALE_FACTOR=%s" scale) t))

      ;; Fix CORS problem.
      (add-to-list 'environments "QTWEBENGINE_CHROMIUM_FLAGS=--disable-web-security" t)

      ;; Use XCB for input event transfer.
      ;; Only enable this option on Linux platform.
      (when (and (eq system-type 'gnu/linux)
                 (not (eaf-emacs-running-in-wayland-native)))
        (add-to-list 'environments "QT_QPA_PLATFORM=xcb" t)))
    environments))

(defun eaf-get-render-size ()
  "Get allocation for render application in backend.
We need calcuate render allocation to make sure no black border around render content.
Returns logical pixel dimensions (physical / compositor scale) for Qt."
  (let* ((scale (eaf--get-compositor-scale))
          ;; Both `window-inside-pixel-edges' and `window-pixel-edges' are frame-relative.
          ;; Use frame-relative coords to get header height (tab-line + header-line).
          (window-header-height (- (nth 1 (window-inside-pixel-edges)) (nth 1 (window-pixel-edges))))
         (width (frame-pixel-width))
         ;; Render height should minus mode-line height, minibuffer height, header height.
         (height (- (frame-pixel-height) (window-mode-line-height) (window-pixel-height (minibuffer-window)) window-header-height)))
    (mapcar (lambda (x) (format "%s" x)) (list (truncate (/ width scale)) (truncate (/ height scale))))))

(defun eaf-get-window-allocation (&optional window)
  "Get WINDOW allocation."
  (let* ((window-edges (window-pixel-edges window))
         (x (nth 0 window-edges))
         (y (+ (nth 1 window-edges)
               (if (version< emacs-version "27.0")
                   (window-header-line-height window)
                 (window-tab-line-height window))))
         (w (- (nth 2 window-edges) x))
         (h (- (nth 3 window-edges) (window-mode-line-height window) y)))
    (list x y w h)))

(defun eaf--frame-left (frame)
  "Return outer left position"
  (let ((left (frame-parameter frame 'left)))
    (if (listp left) (nth 1 left) left)))

(defun eaf--frame-top (frame)
  "Return outer top position."
  (let ((top (frame-parameter frame 'top)))
    (if (listp top) (nth 1 top) top)))

(defun eaf--frame-internal-height (frame)
  "Height of internal objects.
Including title-bar, menu-bar, offset depends on window system, and border."
  (let ((geometry (frame-geometry frame)))
    (+ (cdr (alist-get 'title-bar-size geometry))
       (cdr (alist-get 'tool-bar-size geometry)))))

(defun eaf--buffer-x-position-adjust (frame)
  "Adjust the x position of EAF buffers for macOS"
  (if (eq system-type 'darwin)
      (eaf--frame-left frame)
    0))

(defun eaf--buffer-y-position-adjust (frame)
  "Adjust the y position of EAF buffers for macOS"
  (if (eq system-type 'darwin)
      (+ (eaf--frame-top frame) (eaf--frame-internal-height frame))
    0))

(defun eaf-emacs-not-use-reparent-technology ()
  "When Emacs running in macOS、Wayland native or terminal environment,
we can't use 'cross-process reparent' technicality like we does in X11, XWayland or Windows.

In this situation, we use 'stay on top' technicality that show EAF window when Emacs get focus, hide EAF window when Emacs lost focus.

'Stay on top' technicality is not perfect like 'cross-process reparent' technicality,
provide at least one way to let everyone experience EAF. ;)"
  (or (eq system-type 'darwin)              ;macOS
      (eaf-emacs-running-in-wayland-native) ;Wayland native
      (not (display-graphic-p))             ;Terminal emulator
      ))

(defun eaf-emacs-running-in-wayland-native ()
  (eq window-system 'pgtk))

(defun eaf--on-hyprland-p ()
  (string-equal (getenv "XDG_CURRENT_DESKTOP") "Hyprland"))

(defun eaf--on-unity-p ()
  (string-equal (getenv "XDG_CURRENT_DESKTOP") "Unity"))

(defun eaf--on-sway-p ()
  (string-equal (getenv "XDG_SESSION_DESKTOP") "sway"))

(provide 'eaf-compat)
;;; eaf-compat.el ends here
