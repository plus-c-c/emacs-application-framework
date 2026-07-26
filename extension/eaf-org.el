;;; eaf-org.el --- Emacs application framework  -*- lexical-binding: t; -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-org/.
;;; Code:
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "eaf-org" dir)))
(require 'eaf-org-sub)
(provide 'eaf-org)
;;; eaf-org.el ends here
