;;; eaf-epc.el --- EAF-EPC compatibility wrapper  -*- lexical-binding: t; -*-

;;; Commentary:

;; Thin wrapper that adds the eaf-epc subdirectory to load-path
;; and loads the real eaf-epc package.  This preserves backward
;; compatibility for configurations that have the `core/' directory
;; on load-path.

;;; Code:

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "eaf-epc" dir)))

(require 'eaf-epc)

;;; eaf-epc.el ends here
