;;; eaf-process.el --- EPC server and process lifecycle  -*- lexical-binding: t; -*-

;; Forward declarations
(declare-function eaf--eval-in-emacs "eaf" (sexp-string))
(declare-function eaf--get-emacs-func-result "eaf" (sexp-string))
(declare-function eaf--get-emacs-var "eaf" (var-name))
(declare-function eaf--get-emacs-vars "eaf" (&rest vars))
(defvar eaf-server)
(defvar eaf-server-port)
(defvar eaf-epc-process)
(defvar eaf-internal-process)
(defvar eaf-internal-process-prog)
(defvar eaf-internal-process-args)
(defvar eaf-enable-debug)
(defvar eaf-python-file)
(defvar eaf-start-python-process-when-require)

(defun eaf--start-epc-server ()
  "Function to start the EPC server."
  (unless eaf-server
    (setq eaf-server
          (eaf-epc-server-start
           (lambda (mngr)
             (let ((mngr mngr))
               (eaf-epc-define-method mngr 'eval-in-emacs 'eaf--eval-in-emacs)
               (eaf-epc-define-method mngr 'get-emacs-func-result 'eaf--get-emacs-func-result)
               (eaf-epc-define-method mngr 'get-emacs-var 'eaf--get-emacs-var)
               (eaf-epc-define-method mngr 'get-emacs-vars 'eaf--get-emacs-vars)
               ))))
    (if eaf-server
        (setq eaf-server-port (process-contact eaf-server :service))
      (error "[EAF] eaf-server failed to start")))
  eaf-server)

(defun eaf--get-emacs-func-result (sexp-string)
  (eval (read sexp-string)))

(defun eaf--eval-in-emacs (sexp-string)
  (eval (read sexp-string))
  ;; Return nil to avoid epc error `Got too many arguments in the reply'.
  nil)

(defun eaf--get-emacs-var (var-name)
  (let* ((var-symbol (intern var-name))
         (var-value (symbol-value var-symbol))
         ;; We need convert result of booleanp to string.
         ;; Otherwise, python-epc will convert all `nil' to [] at Python side.
         (var-is-bool (prin1-to-string (booleanp var-value))))
    (list var-value var-is-bool)))

(defun eaf--get-emacs-vars (&rest vars)
  (mapcar #'eaf--get-emacs-var vars))

(defun get-emacs-face-foregrounds (&rest faces)
  (mapcar #'(lambda (face-name) (eaf-color-name-to-hex (face-attribute (intern face-name) :foreground nil 'default))) faces))

(defun eaf-color-int-to-hex (int)
  (substring (format (concat "%0" (int-to-string 4) "X") int) (- 2)))

(defun eaf-color-name-to-hex (color)
  (let ((components (x-color-values color)))
    (concat "#"
            (eaf-color-int-to-hex (nth 0 components))
            (eaf-color-int-to-hex (nth 1 components))
            (eaf-color-int-to-hex (nth 2 components)))))

(defun eaf-start-process ()
  "Start EAF process if it isn't started."
  (unless (eaf-epc-live-p eaf-epc-process)
    ;; start epc server and set `eaf-server-port'
    (eaf--start-epc-server)
    (let* ((eaf-args (append
                      (list eaf-python-file)
                      (eaf-get-render-size)
                      (list (number-to-string eaf-server-port))
                      ))
           environments)

      ;; Folow system DPI.
      (setq environments (eaf--build-process-environment))

      ;; Set process arguments.
      (if eaf-enable-debug
          (progn
            (setq eaf-internal-process-prog "gdb")
            (setq eaf-internal-process-args (append (list "-batch" "-ex" "run" "-ex" "bt" "--args" eaf-python-command) eaf-args)))
        (setq eaf-internal-process-prog eaf-python-command)
        (setq eaf-internal-process-args eaf-args))

      ;; Start python process.
      (let ((process-connection-type (not (eaf--called-from-wsl-on-windows-p)))
            (process-environment environments))
        (setq eaf-internal-process (apply 'start-process eaf-name eaf-name eaf-internal-process-prog eaf-internal-process-args)))
      (set-process-query-on-exit-flag eaf-internal-process nil)))

  ;; Run start process hooks.
  (run-hooks 'eaf-start-process-hook))

(run-with-idle-timer
 1 nil
 #'(lambda ()
     ;; Start EAF python process when load `eaf'.
     ;; It will improve start speed.
     (when eaf-start-python-process-when-require
       (eaf-start-process))))

(defvar eaf-stop-process-hook nil)

(defun eaf-kill-process (&optional restart)
  "Stop EAF process and kill all EAF buffers.

If RESTART is non-nil, cached URL and app-name will not be cleared."
  (interactive)

  ;; Run stop process hooks.
  (run-hooks 'eaf-stop-process-hook)

  (unless restart
    ;; Clear active buffers
    (setq eaf--first-start-app-buffers nil)
    ;; Remove all EAF related hooks since the EAF process is stopped.
    (remove-hook 'kill-buffer-hook #'eaf--monitor-buffer-kill)
    (remove-hook 'kill-emacs-hook #'eaf--monitor-emacs-kill)
    (remove-hook 'after-save-hook #'eaf--org-preview-monitor-buffer-save)
    (remove-hook 'kill-buffer-hook #'eaf--org-preview-monitor-kill)
    (remove-hook 'window-size-change-functions #'eaf-monitor-window-size-change)
    (remove-hook 'window-configuration-change-hook #'eaf-monitor-configuration-change))

  ;; Set `eaf-fullscreen-p'.
  (setq-local eaf-fullscreen-p nil)

  ;; Kill EAF-mode buffers.
  (let* ((eaf-buffers (eaf--get-eaf-buffers))
         (count (length eaf-buffers)))
    (dolist (buffer eaf-buffers)
      (kill-buffer buffer))

    ;; Just report to me when EAF buffer exists.
    (message "[EAF] Killed %s EAF buffer%s" count (if (> count 1) "s!" "!")))

  ;; Kill process after kill buffer, make application can save session data.
  (eaf--kill-python-process))

(defalias 'eaf-stop-process #'eaf-kill-process)

(defun eaf--kill-python-process ()
  "Kill EAF background python process."
  (interactive)
  (when (eaf-epc-live-p eaf-epc-process)
    ;; Cleanup before exit EAF server process.
    (eaf-call-async "cleanup")
    ;; Delete EAF server process.
    (eaf-epc-stop-epc eaf-epc-process)
    ;; Kill *eaf* buffer.
    (when (get-buffer eaf-name)
      (kill-buffer eaf-name))
    (message "[EAF] Process terminated.")))

(defun eaf--kill-devtools-buffers ()
  (dolist (buffer (eaf--get-eaf-buffers))
    (with-current-buffer buffer
      (when (string-prefix-p "DevTools - " (buffer-name buffer))
        (kill-buffer buffer)))))

(defun eaf-restart-process ()
  "Stop and restart EAF process."
  (interactive)
  ;; We need kill debug page first.
  (eaf--kill-devtools-buffers)

  ;; Record reset buffers to `eaf--first-start-app-buffers'.
  (setq eaf--first-start-app-buffers nil)
  (eaf-for-each-eaf-buffer
   (push `(,eaf--buffer-url ,eaf--buffer-app-name ,eaf--buffer-args) eaf--first-start-app-buffers))

  ;; Stop EAF process.
  (eaf-kill-process t)

  ;; Start EAF process, EAF will restore page in `eaf--first-start-app-buffers'.
  (eaf-start-process))

(provide 'eaf-process)
;;; eaf-process.el ends here
