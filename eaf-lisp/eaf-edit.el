;;; eaf-edit.el --- Edit buffer popup  -*- lexical-binding: t; -*-

;; Forward declarations
(defvar eaf--buffer-id)
(declare-function eaf--show-message "eaf" (format-string eaf-prefix logging))

(defvar eaf-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-t") #'eaf-edit-buffer-switch-to-org-mode)
    (define-key map (kbd "C-c C-k") #'eaf-edit-buffer-cancel)
    (define-key map (kbd "C-c C-c") #'eaf-edit-buffer-confirm)
    map))

(define-derived-mode eaf-edit-mode text-mode "EAF/edit"
  "The major mode to edit focus text input.")

(defvar-local eaf-edit-confirm-action nil)

(defvar eaf-edit-confirm-function-alist '())

(defun eaf-edit-buffer-popup (buffer-id buffer-template confirm-action text)
  (split-window-below -10)
  (other-window 1)
  (let ((edit-text-buffer (generate-new-buffer (format buffer-template eaf--buffer-app-name)))
        (buffer-app-name eaf--buffer-app-name))
    (with-current-buffer edit-text-buffer
      (eaf-edit-mode)
      (set (make-local-variable 'eaf--buffer-app-name) buffer-app-name)
      (set (make-local-variable 'eaf--buffer-id) buffer-id))
    (switch-to-buffer edit-text-buffer)
    (setq-local eaf-edit-confirm-action confirm-action)
    (eaf-edit-set-header-line)
    (insert text)
    ;; When text line number above
    (when (> (line-number-at-pos) 30)
      (goto-char (point-min)))))

(defun eaf-edit-set-header-line ()
  "Set header line."
  (setq header-line-format
        (substitute-command-keys
         (concat
          "\\<eaf-edit-mode-map>"
          " EAF/" eaf--buffer-app-name " EDIT: "
          "Confirm with `\\[eaf-edit-buffer-confirm]', "
          "Cancel with `\\[eaf-edit-buffer-cancel]'. "
          "Switch to org-mode with `\\[eaf-edit-buffer-switch-to-org-mode]'. "
          ))))

(defun eaf-edit-buffer-switch-to-org-mode ()
  "Switch to `org-mode' to edit table handily."
  (interactive)
  (let ((buffer-app-name eaf--buffer-app-name)
        (buffer-id eaf--buffer-id))
    (save-excursion
      (org-mode)
      (outline-show-all))

    (when (and (featurep 'olivetti)
               olivetti-mode)
      (setq-local olivetti-mode nil))

    (set (make-local-variable 'eaf--buffer-app-name) buffer-app-name)
    (set (make-local-variable 'eaf--buffer-id) buffer-id)
    (local-set-key (kbd "C-c C-c") 'eaf-edit-buffer-confirm)
    (local-set-key (kbd "C-c C-k") 'eaf-edit-buffer-cancel)
    (eaf-edit-set-header-line)))

(defun eaf-edit-buffer-confirm ()
  "Confirm input text and send the text to corresponding EAF app."
  (interactive)
  ;; Note: pickup buffer-id from buffer name and not restore buffer-id from buffer local variable.
  ;; Then we can switch edit buffer to any other mode, such as org-mode, to confirm buffer string.

  ;; Do confirm action.
  (let ((confirm-function (cdr (assoc eaf-edit-confirm-action eaf-edit-confirm-function-alist))))
    (if confirm-function
        (funcall confirm-function)
      (eaf-call-async "set_focus_text" eaf--buffer-id (eaf--encode-string (eaf-copy-to-clipboard (buffer-string))))))

  ;; Close confirm window.
  (kill-buffer)
  (delete-window))

(provide 'eaf-edit)
;;; eaf-edit.el ends here
