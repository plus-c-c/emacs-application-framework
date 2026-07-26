;;; eaf-all-the-icons.el --- Emacs application framework -*- lexical-binding: t -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-all-the-icons/.
;;; Code:
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "eaf-all-the-icons" dir)))
(require 'eaf-all-the-icons-sub)
(provide 'eaf-all-the-icons)
;;; eaf-all-the-icons.el ends here
