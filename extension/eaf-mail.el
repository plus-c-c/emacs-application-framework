;;; eaf-mail.el --- Mail plugins -*- lexical-binding: t -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-mail/.
;;; Code:
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "eaf-mail" dir)))
(require 'eaf-mail-sub)
(provide 'eaf-mail)
;;; eaf-mail.el ends here
