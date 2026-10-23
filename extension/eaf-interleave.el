;;; eaf-interleave.el --- Interleaving text books on EAF -*- lexical-binding: t; -*-
;;; Commentary:
;; Thin wrapper — real code lives in extension/eaf-interleave/.
;;; Code:
(let* ((dir (file-name-directory (or load-file-name buffer-file-name)))
       (sub (expand-file-name "eaf-interleave/eaf-interleave.el" dir)))
  (when (file-exists-p sub)
    (load sub nil t)))
(provide 'eaf-interleave)
;;; eaf-interleave.el ends here
