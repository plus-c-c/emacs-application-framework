;;; eaf-interleave.el --- Interleaving text books on EAF -*- lexical-binding: t -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-interleave/.
;;; Code:
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "eaf-interleave" dir)))
(require 'eaf-interleave-sub)
(provide 'eaf-interleave)
;;; eaf-interleave.el ends here
