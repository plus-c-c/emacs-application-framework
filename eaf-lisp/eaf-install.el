;;; eaf-install.el --- Package installation  -*- lexical-binding: t; -*-

;; Forward declarations
(defvar eaf-build-dir)
(defvar eaf-source-dir)
(defvar eaf-python-command)

;;;###autoload
(defun eaf-install-and-update (&rest apps)
  "Interactively run `install-eaf.py' to install/update EAF apps.

For a full `install-eaf.py' experience, refer to `--help' and run in a terminal."
  (interactive)
  (let* ((default-directory eaf-source-dir)
         (output-buffer (generate-new-buffer "*EAF installation*"))
         (apps (or apps eaf-apps-to-install))
         (proc
          (progn
            (async-shell-command (concat
                                  eaf-python-command " install-eaf.py"
                                  (when (and apps (> (length apps) 0)) " --install ")
                                  (mapconcat 'symbol-name apps " "))
                                 output-buffer)
            (get-buffer-process output-buffer))))
    (if (process-live-p proc)
        (set-process-sentinel proc #'eaf--post-install-sentinel)
      (eaf--post-install))))

(defun eaf-record-log ()
  (interactive)
  (message "\nBelow is EAF log:\n %s" (with-current-buffer eaf-name (buffer-string))))

(defun eaf--post-install-sentinel (process string-signal)
  (when (memq (process-status process) '(exit signal))
    (message "Running post install")
    (eaf--post-install)
    (shell-command-sentinel process string-signal)))

(defun eaf--symlink-directory (old new)
  (if (fboundp 'straight--symlink-recursively)
      (straight--symlink-recursively old new)
    (make-symbolic-link old new)))

(defun eaf--post-install ()
  ;; If user use Straight package manager, then `eaf-source-dir' is not equal `eaf-build-dir'
  (when (not (string= eaf-source-dir eaf-build-dir))
    (message "Symlinking app directory")
    (eaf--symlink-directory
     (expand-file-name "app" eaf-source-dir)
     (expand-file-name "app" eaf-build-dir)))

  (when eaf-byte-compile-apps
    (message "Byte-compiling")
    (byte-recompile-directory eaf-build-dir 0))

  (message "Updating load path")
  (eaf-add-subdirs-to-load-path eaf-build-dir)
  (message "Done"))

(provide 'eaf-install)
;;; eaf-install.el ends here
