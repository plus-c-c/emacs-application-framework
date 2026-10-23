;;; eaf-org.el --- EAF eaf-org extension -*- lexical-binding: t; -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-org/.
;;; Code:
(let* ((dir (file-name-directory (or load-file-name buffer-file-name)))
       (sub (expand-file-name "eaf-org/eaf-org.el" dir)))
  (when (file-exists-p sub)
    (load sub nil t)))
(provide 'eaf-org)
;;; eaf-org.el ends here
