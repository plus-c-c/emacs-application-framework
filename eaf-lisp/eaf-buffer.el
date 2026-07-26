;;; eaf-buffer.el --- Buffer lifecycle management  -*- lexical-binding: t; -*-

;; Forward declarations
(defvar eaf--buffer-id)
(defvar eaf--buffer-url)
(defvar eaf--buffer-app-name)
(defvar eaf--buffer-args)
(defvar eaf-epc-process)
(defvar eaf--first-start-app-buffers)
(defvar eaf-last-frame-width)
(defvar eaf-last-frame-height)
(defvar eaf-name)
(defvar eaf-clean-duplicate-buffers)
(defvar eaf-duplicate-buffer-survival-time)
(defvar eaf-goto-right-after-close-buffer)
(defvar eaf-rebuild-buffer-after-crash)
(declare-function eaf-epc-live-p "eaf-epc" (mngr))
(declare-function eaf-call-async "eaf" (method &rest args))
(declare-function eaf-call-sync "eaf" (method &rest args))
(declare-function eaf-get-emacs-xid "eaf" (frame))
(declare-function eaf--generate-id "eaf" ())
(declare-function eaf--open-internal "eaf" (url app-name args))
(declare-function eaf--preview-display-buffer "eaf" (app-name buffer))
(declare-function eaf--bookmark-make-record "eaf" ())
(declare-function eaf--get-compositor-scale "eaf" ())

(defun eaf--create-buffer (url app-name args)
  "Create an EAF buffer given URL, APP-NAME, and ARGS."
  (eaf--gen-keybinding-map (eaf--get-app-bindings app-name))
  (let* ((eaf-buffer-name (if (equal (file-name-nondirectory url) "")
                              url
                            (file-name-nondirectory url)))
         (eaf-buffer (generate-new-buffer eaf-buffer-name))
         (url-directory (or (file-name-directory url) url)))
    (with-current-buffer eaf-buffer
      (eaf-mode)

      ;; Don't promt user when exist EAF python process.
      (setq-local confirm-kill-processes nil)

      (when (file-accessible-directory-p url-directory)
        (setq-local default-directory url-directory)

        ;; NOTE:
        ;; Don't set buffer `buffer-file-name' here.
        ;; Otherwise, markdown or org previewer will switch to EAF preview buffer instead open real file.
        )
      ;; `eaf-buffer-url' should record full path of url, otherwise `eaf-open' will open duplicate PDF tab for same url.
      (set (make-local-variable 'eaf--buffer-url) url)
      (set (make-local-variable 'eaf--buffer-app-name) app-name)
      (set (make-local-variable 'eaf--buffer-args) args)
      (run-hooks (intern (format "eaf-%s-hook" app-name)))
      (setq mode-name (concat "EAF/" app-name)))
    eaf-buffer))

(defun eaf--get-eaf-buffers ()
  "A function that return a list of EAF buffers."
  (cl-remove-if-not
   (lambda (buffer)
     (with-current-buffer buffer
       (derived-mode-p 'eaf-mode)))
   (buffer-list)))

(defun eaf--monitor-buffer-kill ()
  "A function monitoring when an EAF buffer is killed."
  (ignore-errors
    (eaf-call-async "kill_buffer" eaf--buffer-id))

  ;; Kill eaf process when last eaf buffer closed.
  ;; We need add timer to avoid the last web page kill when terminal is exited.
  (when eaf-kill-process-after-last-buffer-closed
    (run-at-time
     5 nil
     (lambda ()
       (when (equal (length (eaf--get-eaf-buffers)) 0)
         (eaf--kill-python-process))
       ))))

(defun eaf--monitor-emacs-kill ()
  "Function monitoring when Emacs is killed."
  (ignore-errors
    (when eaf-browser-continue-where-left-off
      (let* ((browser-restore-file-path
              (concat eaf-config-location
                      (file-name-as-directory "browser")
                      (file-name-as-directory "history")
                      "restore.txt"))
             (browser-urls ""))
        (write-region
         (dolist (buffer (eaf--get-eaf-buffers) browser-urls)
           (with-current-buffer buffer
             (when (equal eaf--buffer-app-name "browser")
               (setq browser-urls (concat eaf--buffer-url "\n" browser-urls)))))
         nil browser-restore-file-path)))
    (eaf-call-async "kill_emacs")))

(defun eaf-get-buffer (buffer-id)
  "Find the buffer given the BUFFER-ID."
  (catch 'found-eaf
    (eaf-for-each-eaf-buffer
     (when (string= eaf--buffer-id buffer-id)
       (throw 'found-eaf buffer))
     nil)))

(defun eaf-get-window-size-by-buffer-id (buffer-id)
  (let* ((buffer (eaf-get-buffer buffer-id))
         (allocation (when buffer
                       (eaf-get-window-allocation (get-buffer-window buffer))))
         (scale (eaf--get-compositor-scale)))
    (when allocation
      (list (nth 0 allocation)
            (nth 1 allocation)
            (truncate (/ (nth 2 allocation) scale))
            (truncate (/ (nth 3 allocation) scale))))))

(defun eaf-focus-buffer (buffer-id)
  "Focus the buffer given the BUFFER-ID."
  (let* ((buffer (eaf-get-buffer buffer-id))
         (window (if buffer (get-buffer-window buffer 'visible) nil)))
    (when window (select-window window) t)))

(defvar-local eaf-buffer-input-focus nil)
(defun eaf-update-focus-state (buffer-id state)
  (let ((buffer (eaf-get-buffer buffer-id)))
    (when buffer
      (with-current-buffer buffer
        (setq-local eaf-buffer-input-focus state)))))

(defun eaf--show-message (format-string eaf-prefix logging)
  "A wrapper around `message' that prepend [EAF/app-name] before FORMAT-STRING."
  (let* ((eaf-prefix (if (equal eaf-prefix "TRUE") t nil))
         (logging (if (equal logging "TRUE") t nil))
         (fmt (cond ((not eaf-prefix) "%s")
                    (eaf--buffer-app-name (concat "[EAF/" eaf--buffer-app-name "] %s"))
                    (t "[EAF] %s"))))
    (if logging (message fmt format-string)
      (let ((message-log-max nil))
        (message fmt format-string)))))

(defun eaf--clear-message ()
  "Clear Emacs' echo area ."
  (message nil))

(defun eaf--set-emacs-var (name value)
  "Set Lisp variable NAME with VALUE on the Emacs side."
  (set (intern name) value))

(defun eaf-request-kill-buffer (buffer-id)
  "Function for requesting to kill the given buffer with BUFFER-ID."
  (let* ((buffer (eaf-get-buffer buffer-id)))
    (when buffer
      (kill-buffer buffer)

      (when eaf-goto-right-after-close-buffer
        (eaf-goto-right-tab)))))

(defun eaf--first-start (eaf-epc-port)
  "Call `eaf--open-internal' upon receiving `start_finish' signal from server.

WEBENGINE-INCLUDE-PRIVATE-CODEC is only useful when app-name is video-player."
  ;; Record frame that start EAF.
  (setq eaf-emacs-frame (window-frame))

  ;; Make EPC process.
  (setq eaf-epc-process (make-eaf-epc-manager
                         :server-process eaf-internal-process
                         :commands (cons eaf-internal-process-prog eaf-internal-process-args)
                         :title (mapconcat 'identity (cons eaf-internal-process-prog eaf-internal-process-args) " ")
                         :port eaf-epc-port
                         :connection (eaf-epc-connect "127.0.0.1" eaf-epc-port)
                         ))
  (eaf-epc-init-epc-layer eaf-epc-process)

  (dolist (buffer-info eaf--first-start-app-buffers)
    (eaf--open-internal (nth 0 buffer-info) (nth 1 buffer-info) (nth 2 buffer-info)))
  (setq eaf--first-start-app-buffers nil))

(defun eaf--update-buffer-details (buffer-id title url)
  "Function for updating buffer details with its BUFFER-ID, TITLE and URL."
  (when (eaf--called-from-wsl-on-windows-p)
    (eaf-monitor-configuration-change))
  (when (and (> (length title) 0)
             ;; NOTE: When run eaf-browser, this function will be
             ;; called twice, buffer name will be changed twice too,
             ;; To prevent mode-line flickr, we do not change buffer
             ;; name when when title is equal url.
             (not (equal title url)))
    (catch 'found-eaf
      (dolist (window (window-list))
        (let ((buffer (window-buffer window)))
          (with-current-buffer buffer
            (when (and
                   (derived-mode-p 'eaf-mode)
                   (equal eaf--buffer-id buffer-id))
              (setq mode-name (concat "EAF/" eaf--buffer-app-name))
              (setq-local eaf--bookmark-title title)
              (setq-local eaf--buffer-url url)
              (rename-buffer (format eaf-buffer-title-format title) t)
              (eaf--update-modeline-icon)
              (throw 'found-eaf t))))))))

(defvar eaf-search-input-active-p nil)
(defvar eaf-search-input-buffer-id nil)
(defvar eaf-search-input-callback-tag nil)

(defun eaf--input-message (input-buffer-id interactive-string callback-tag interactive-type initial-content completion-list)
  "Handles input message INTERACTIVE-STRING on the Python side given INPUT-BUFFER-ID and CALLBACK-TYPE."
  (when (string-equal interactive-type "search")
    (setq eaf-search-input-active-p t)
    (setq eaf-search-input-buffer-id input-buffer-id)
    (setq eaf-search-input-callback-tag callback-tag))

  (let* ((input-message (eaf-read-input (concat "[EAF/" eaf--buffer-app-name "] " interactive-string) interactive-type initial-content completion-list)))
    (if input-message
        (eaf-call-async "handle_input_response" input-buffer-id callback-tag input-message)
      (eaf-call-async "cancel_input_response" input-buffer-id callback-tag))
    (setq eaf-search-input-active-p nil)))

(defun eaf-read-input (interactive-string interactive-type initial-content completion-list)
  "EAF's multi-purpose read-input function which read an INTERACTIVE-STRING with INITIAL-CONTENT, determines the function base on INTERACTIVE-TYPE."
  (condition-case nil
      (cond ((or (string-equal interactive-type "string")
                 (string-equal interactive-type "marker")
                 (string-equal interactive-type "search"))
             (read-string interactive-string initial-content))
            ((string-equal interactive-type "file")
             (expand-file-name (read-file-name interactive-string initial-content)))
            ((string-equal interactive-type "directory")
             (expand-file-name (read-directory-name interactive-string initial-content)))
            ((string-equal interactive-type "yes-or-no")
             (yes-or-no-p interactive-string))
            ((string-equal interactive-type "list")
             (completing-read interactive-string completion-list)))
    (quit nil)))

(defun eaf--open-internal (url app-name args)
  "Open an EAF application internally with URL, APP-NAME and ARGS."
  (let* ((buffer (eaf--create-buffer url app-name args)))
    (eaf--open-new-buffer buffer)))

(defun eaf--open-new-buffer (buffer)
  (with-current-buffer buffer
    (eaf-call-async "new_buffer"
                    eaf--buffer-id
                    (if (eaf--called-from-wsl-on-windows-p)
                        (eaf--translate-wsl-url-to-windows eaf--buffer-url)
                      eaf--buffer-url)
                    (eaf--get-app-module-path eaf--buffer-app-name)
                    eaf--buffer-args)

    ;; Run application's hook.
    (let ((app-hook (assoc eaf--buffer-app-name eaf-app-hook-alist)))
      (when app-hook
        (funcall (cdr app-hook))))

    (eaf--update-modeline-icon)
    (eaf--preview-display-buffer eaf--buffer-app-name buffer)))

(defun eaf--rebuild-buffer ()
  (if eaf-rebuild-buffer-after-crash
      (when (derived-mode-p 'eaf-mode)
        (eaf-restart-process)
        (eaf--open-new-buffer (current-buffer))
        (eaf-monitor-configuration-change))
    (when (get-buffer eaf-name)
      (message "Below is EAF log:\n %s"
               (with-current-buffer eaf-name
                 (buffer-string))))
    (eaf-stop-process)))

(defun eaf-duplicate-current-buffer ()
  "Duplicate the current EAF buffer in a new buffer.

So multiple EAF buffers visiting the same file do not sync with each other."
  (interactive)
  (when (derived-mode-p 'eaf-mode)
    (delete-other-windows)
    (split-window-horizontally)
    (other-window +1)
    (eaf-open eaf--buffer-url eaf--buffer-app-name eaf--buffer-args t)))

(defun eaf--preview-display-buffer (app-name buffer)
  "Display specified APP-NAME's app buffer in BUFFER."
  (let ((display-fun (or (cdr (assoc app-name
                                     eaf-preview-display-function-alist))
                         #'switch-to-buffer)))
    (funcall display-fun buffer)))

(defun eaf-split-preview-windows (url)
  "Function for spliting preview windows with specified URL."
  (delete-other-windows)
  (find-file url)
  (split-window-horizontally)
  (other-window +1))

(defun eaf--change-default-directory (buffer-id directory)
  "Change default directory to DIRECTORY."
  (let ((buffer (eaf-get-buffer buffer-id)))
    (when buffer
      (with-current-buffer buffer
        (when (file-accessible-directory-p (or (file-name-directory directory) directory))
          (setq-local default-directory directory))))))

(defun eaf-clean-file-manager-buffers ()
  (let ((now (current-time)))
    (eaf-for-each-eaf-buffer
     (when (and
            ;; Must be EAF file manager buffer.
            (string-equal eaf--buffer-app-name "file-manager")
            (boundp 'eaf--last-visit-time)
            ;; Not show in frame.
            (not (memq buffer (mapcar #'window-buffer (window-list))))
            ;; Found duplicate buffer.
            (eaf-has-duplicate-path-buffer-p buffer)
            ;; Existing time exceeds than `eaf-duplicate-buffer-survival-time'
            (> (float-time (time-subtract now eaf--last-visit-time)) eaf-duplicate-buffer-survival-time))
       ;; Just log in *messages* buffer silently, don't disturb users.
       (let ((inhibit-message t))
         (message "[EAF] Clean duplicate file manager buffer: %s" buffer))
       (kill-buffer buffer)))))

(defun eaf-has-duplicate-path-buffer-p (eaf-buffer)
  (cl-remove-if-not
   (lambda (buffer)
     (and
      (not (eq buffer eaf-buffer))
      (string-equal (with-current-buffer eaf-buffer eaf--buffer-url)
                    (with-current-buffer buffer eaf--buffer-url))))
   (eaf--get-eaf-buffers)))

(provide 'eaf-buffer)
;;; eaf-buffer.el ends here
