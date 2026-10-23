;;; eaf-mail.el --- EAF eaf-mail extension -*- lexical-binding: t; -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-mail/.
;;; Code:
(let* ((dir (file-name-directory (or load-file-name buffer-file-name)))
       (sub (expand-file-name "eaf-mail/eaf-mail.el" dir)))
  (when (file-exists-p sub)
    (load sub nil t)))
(provide 'eaf-mail)
;;; eaf-mail.el ends here
