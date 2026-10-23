;;; eaf-all-the-icons.el --- Emacs application framework -*- lexical-binding: t; -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-all-the-icons/.
;;; Code:
(let* ((dir (file-name-directory (or load-file-name buffer-file-name)))
       (sub (expand-file-name "eaf-all-the-icons/eaf-all-the-icons.el" dir)))
  (when (file-exists-p sub)
    (load sub nil t)))
(provide 'eaf-all-the-icons)
;;; eaf-all-the-icons.el ends here
