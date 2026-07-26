;;; eaf-window.el --- Window management  -*- lexical-binding: t; -*-

;; Forward declarations
(defvar eaf--monitor-configuration-p)
(defvar eaf-emacs-frame)
(defvar eaf-epc-process)
(defvar eaf-fullscreen-p)
(defvar eaf-last-frame-width)
(defvar eaf-last-frame-height)
(defvar eaf--topmost-switch-to-python)
(defvar eaf--emacs-program-name)
(defvar eaf--last-visit-buffer)
(declare-function eaf-epc-live-p "eaf-epc" (mngr))
(declare-function eaf-call-async "eaf" (method &rest args))
(declare-function eaf-call-sync "eaf" (method &rest args))
(declare-function eaf-get-emacs-xid "eaf" (frame))
(declare-function eaf-emacs-running-in-wayland-native "eaf" ())
(declare-function eaf--on-hyprland-p "eaf" ())
(declare-function eaf--on-sway-p "eaf" ())
(declare-function eaf--on-unity-p "eaf" ())
(declare-function eaf--get-compositor-scale "eaf" ())
(declare-function eaf--clip-image "eaf" (window))
(declare-function eaf--display-image "eaf" (window))

(defun eaf-monitor-window-size-change (frame)
  "Delay some time and run `eaf-try-adjust-view-with-frame-size' to compare with Emacs FRAME size."
  (when (eaf-epc-live-p eaf-epc-process)
    (setq eaf-last-frame-width (frame-pixel-width frame))
    (setq eaf-last-frame-height (frame-pixel-height frame))
    (run-with-timer 1 nil (lambda () (eaf-try-adjust-view-with-frame-size frame)))))

(defun eaf-try-adjust-view-with-frame-size (frame)
  "Update EAF view once Emacs window size of the FRAME is changed."
  (unless (and (equal (frame-pixel-width frame) eaf-last-frame-width)
               (equal (frame-pixel-height frame) eaf-last-frame-height))
    (eaf-monitor-configuration-change)))

(eval-when-compile
  (when (eaf-emacs-not-use-reparent-technology)
    (defvar eaf--topmost-switch-to-python nil
      "Record if Emacs should switch to Python process.")

    (defun eaf--topmost-focus-change ()
      "Manage Emacs's focus change."
      (let* ((front (cond ((eq system-type 'darwin)
                           (shell-command-to-string "app-frontmost --name"))
                          ((eaf--on-sway-p)
                           (if (executable-find "jq")
                               (shell-command-to-string "swaymsg -t get_tree | jq -r '..|try select(.focused == true).app_id'")
                             (message "Please install jq for swaywm support.")))
                          ((eaf--on-hyprland-p)
                           (or
                            (gethash "class" (json-parse-string (shell-command-to-string "hyprctl -j activewindow")))
                            ""))
                          ((eaf--on-unity-p)
                           (if (executable-find "xdotool")
                               (shell-command-to-string "xdotool getactivewindow getwindowname")
                             (message "Please install xdotool for Unity support.")))
                          (t
                           (require 'dbus)
                           (dbus-call-method :session "org.gnome.Shell" "/org/eaf/wayland" "org.eaf.wayland" "get_active_window" :timeout 1000))))
             (front-app-name (string-trim front)))
        (cond
         ((member front-app-name (list "Python" "python3"))
          (setq eaf--topmost-switch-to-python t))
         ((or (string-equal (replace-regexp-in-string "\\." "-" front)
                            eaf--emacs-program-name)
              (string-match-p (regexp-quote front-app-name)
                              eaf--emacs-program-name))
          (if eaf--topmost-switch-to-python
              (setq eaf--topmost-switch-to-python nil)
            (run-with-timer 0.1 nil #'eaf--topmost-focus-update)))
         (t (eaf--topmost-focus-out)))))

    (defun eaf--topmost-focus-update ()
      "Display new eaf buffers at front.
Views are already hidden by previous focus-out; just show visible ones."
      (when (frame-focus-state)
        (dolist (window (window-list (selected-frame)))
          (with-current-buffer (window-buffer window)
            (when (derived-mode-p 'eaf-mode)
              (eaf-call-async "show_buffer_view" eaf--buffer-id))))))

    (defun eaf--topmost-focus-out ()
      "Prepare the screenshot and hide all eaf buffers."
      (dolist (frame (frame-list))
        (dolist (window (window-list frame))
          (with-current-buffer (window-buffer window)
            (when (derived-mode-p 'eaf-mode)
              (eaf--clip-image window)
              (eaf-call-sync "hide_buffer_view" eaf--buffer-id))))))

    (defun eaf--clip-image (window)
      "Clip the image of the qwidget."
      (eaf-call-sync "clip_buffer" eaf--buffer-id)
      (eaf--display-image window))

    (defun eaf--display-image (window)
      "Display the image of qwidget in eaf buffer."
      (let ((image-path (concat eaf-config-location eaf--buffer-id ".jpeg")))
        (when (file-exists-p image-path)
          (clear-image-cache)
          (erase-buffer)
          (insert-image (create-image image-path 'jpeg nil
                                      :width (window-pixel-width window)
                                      :height (window-pixel-height window))))))

    (defun eaf--topmost-delete-frame-handler (frame)
      (eaf--topmost-focus-out))

    (defun eaf--topmost-clear-images-cache-handler ()
      "Clear all images when quitting Emacs."
      (when (file-exists-p eaf-config-location)
        (shell-command-to-string (concat "rm " eaf-config-location "*.jpeg"))))

    (add-hook 'kill-emacs-hook #'eaf--topmost-clear-images-cache-handler)

    (add-hook 'eaf-start-process-hook
              (lambda ()
                (add-function :after after-focus-change-function #'eaf--topmost-focus-change)
                (add-to-list 'move-frame-functions #'eaf-monitor-configuration-change)))

    (add-hook 'eaf-stop-process-hook
              (lambda ()
                (remove-function after-focus-change-function #'eaf--topmost-focus-change)
                (remove-hook 'move-frame-functions #'eaf-monitor-configuration-change)))

    (add-to-list 'delete-frame-functions #'eaf--topmost-delete-frame-handler)))

(defun eaf-monitor-configuration-change (&rest _)
  "EAF function to respond when detecting a window configuration change."
  (when (and eaf--monitor-configuration-p
             (eaf-epc-live-p eaf-epc-process)
             ;; When current frame is same with `eaf-emacs-frame'.
             (equal (window-frame) eaf-emacs-frame))
    (ignore-errors
      (let ((scale (eaf--get-compositor-scale))
            view-infos)
        (dolist (frame (frame-list))
          (dolist (window (window-list frame))
            (with-current-buffer (window-buffer window)
              (when (derived-mode-p 'eaf-mode)
                ;; When `eaf-fullscreen-p' is non-nil, and only the EAF window is present, use frame size
                (if (and eaf-fullscreen-p
                         (equal (length (cl-remove-if #'window-dedicated-p (window-list frame))) 1))
                    (push (format "%s:%s:%s:%s:%s:%s"
                                  eaf--buffer-id
                                  (eaf-get-emacs-xid frame)
                                  0 0
                                  (truncate (/ (frame-pixel-width frame) scale))
                                  (truncate (/ (frame-pixel-height frame) scale)))
                          view-infos)
                  (let* ((window-allocation (eaf-get-window-allocation window))
                         (window-divider-right-padding (if window-divider-mode window-divider-default-right-width 0))
                         (window-divider-bottom-padding (if window-divider-mode window-divider-default-bottom-width 0))
                         (titlebar-height (eaf--get-titlebar-height))
                         (frame-coordinate (eaf--get-frame-coordinate))
                         (frame-x (car frame-coordinate))
                         (frame-y (cadr frame-coordinate))
                         (x (+ (eaf--buffer-x-position-adjust frame) (nth 0 window-allocation)))
                         (y (+ (eaf--buffer-y-position-adjust frame) (nth 1 window-allocation)))
                         (w (nth 2 window-allocation))
                         (h (nth 3 window-allocation)))
                    (push (format "%s:%s:%s:%s:%s:%s"
                                  eaf--buffer-id
                                  (eaf-get-emacs-xid frame)
                                  (truncate (/ (+ x frame-x) scale))
                                  (truncate (/ (+ y titlebar-height frame-y) scale))
                                  (truncate (/ (- w window-divider-right-padding) scale))
                                  (truncate (/ (- h window-divider-bottom-padding) scale)))
                          view-infos)))))))
        (eaf-call-async "update_views" (mapconcat #'identity view-infos ","))))))

(defun eaf--split-number (string)
  (mapcar #'string-to-number (split-string string)))

(defun eaf--get-frame-coordinate ()
  "We need fetch Emacs coordinate to adjust coordinate of EAF if it running on system not support cross-process reparent technology.

Such as, wayland native, macOS etc."
  (if (eaf-emacs-running-in-wayland-native)
      (cond ((eaf--on-sway-p)
             (eaf--split-number (shell-command-to-string
				 (format "swaymsg -t get_tree | jq -r '..|try select(.pid == %d).deco_rect|.x,.y'" (emacs-pid)))))
            ((eaf--on-hyprland-p)
             (let ((clients (json-parse-string (shell-command-to-string "hyprctl -j clients")))
		   (coordinate))
               (dotimes (i (length clients))
		 (when (equal (gethash "pid" (aref clients i)) (emacs-pid))
		   (setq coordinate (gethash "at" (aref clients i)))))
               (list (aref coordinate 0) (aref coordinate 1))))
            (t
             (require 'dbus)
             (let* ((coordinate (eaf--split-number
				 (dbus-call-method :session "org.gnome.Shell" "/org/eaf/wayland" "org.eaf.wayland" "get_emacs_window_coordinate" :timeout 1000)
				 ","))
                    ;; HiDPI need except by `frame-scale-factor'.
                    (frame-x (truncate (/ (car coordinate) (frame-scale-factor))))
                    (frame-y (truncate (/ (cadr coordinate) (frame-scale-factor)))))
               (list frame-x frame-y))))
    (list 0 0)))

(defun eaf--get-titlebar-height ()
  "We need fetch height of window titlebar to adjust y coordinate of EAF when Emacs is not fullscreen."
  (cond ((eaf-emacs-running-in-wayland-native)
         (let ((is-fullscreen-p (memq (frame-parameter nil 'fullscreen) '(fullscreen fullboth))))
           (if is-fullscreen-p
               0
             ;; `32' is titlebar of Gnome3, we need change this value in other environment.
             (cond ((eaf--on-hyprland-p)
                    0)
                   ((eaf--on-sway-p)
                    (string-to-number (shell-command-to-string
                      (format "swaymsg -t get_tree | jq -r '..|try select(.pid == %d).deco_rect|.height'" (emacs-pid)))))
                   (t
                    32)))))
        (t
         0)))

(defvar eaf--last-visit-buffer nil)

(defun eaf-monitor-window-buffer-change ()
  ;; We record last visit time for EAF buffer.
  (when (derived-mode-p 'eaf-mode)
    (setq-local eaf--last-visit-time (current-time)))

  ;; Clean file manager buffer when buffer or window changed.
  (unless (eq (current-buffer)
              eaf--last-visit-buffer)
    (when eaf-clean-duplicate-buffers
      (eaf-clean-file-manager-buffers)))

  (unless (or (minibufferp)
              (string-equal (buffer-name) "*Messages*"))
    (setq eaf--last-visit-buffer (current-buffer))))

(provide 'eaf-window)
;;; eaf-window.el ends here
