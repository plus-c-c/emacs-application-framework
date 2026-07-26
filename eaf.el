;;; eaf.el --- Emacs application framework (loader)  -*- lexical-binding: t; -*-

;;; Commentary:
;; This file loads the split EAF modules from eaf-lisp/.

;;; Code:
(let ((dir (expand-file-name "eaf-lisp"
                             (file-name-directory
                              (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path dir)
  (require 'eaf))

(provide 'eaf)
;;; eaf.el ends here
