;;; eaf-interleave-eaf.el --- EAF integration functions -*- lexical-binding: t -*-

;;; Commentary:
;; PDF viewer and browser integration with EAF.

;;; Code:

(require 'eaf-interleave-vars)

;; utils
(defun eaf-interleave--open-pdf (pdf-file-name)
  "Use EAF PdfViewer open this pdf-file-name document."
  (eaf-open pdf-file-name)
  (add-hook 'eaf-pdf-viewer-hook 'eaf-interleave-app-mode))

(defun eaf-interleave--open-web-url (url)
  "Use EAF Browser open current note web address"
  (eaf-open-browser url)
  (add-hook 'eaf-browser-hook 'eaf-interleave-app-mode))

(defun eaf-interleave--find-buffer (url)
  "find EAF buffer base url"
  (let (current-buffer)
    (catch 'find-buffer
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
          (when (and
                 (derived-mode-p 'eaf-mode)
                 (equal eaf--buffer-url url))
            (setq current-buffer buffer)
            (throw 'find-buffer t)))))
    current-buffer))

(defun eaf-interleave--kill-buffer (url)
  "Kill the current converter process and buffer."
  (let ((buffer (eaf-interleave--find-buffer url)))
    (kill-buffer buffer)))

(defun eaf-interleave--pdf-viewer-current-page (url)
  "get current page index."
  (let ((id (buffer-local-value 'eaf--buffer-id (eaf-interleave--find-buffer url))))
    (string-to-number (eaf-call-sync "execute_function" id "current_page"))))

(defun eaf-interleave--pdf-viewer-goto-page (url page)
  "goto page"
  (let ((id (buffer-local-value 'eaf--buffer-id (eaf-interleave--find-buffer url))))
    (eaf-call-async "handle_input_response" id "jump_page" page)))

(defun eaf-interleave--pdf-viewer-current-page-y (url)
  "Get current page and Y-coordinate as 'page:y' string."
  (let ((id (buffer-local-value 'eaf--buffer-id (eaf-interleave--find-buffer url))))
    (eaf-call-sync "execute_function" id "current_scroll_info")))

(defun eaf-interleave--pdf-viewer-goto-page-y (url page-y)
  "Jump to specific page and Y-coordinate. page-y format: 'page:y_percent'"
  (let ((id (buffer-local-value 'eaf--buffer-id (eaf-interleave--find-buffer url))))
    (eaf-call-async "handle_input_response" id "goto_page_and_y_percent" page-y)))

(defun eaf-interleave--ensure-buffer-window (buffer)
  "If BUFFER don't display, will use other window display"
  (if (get-buffer-window buffer)
      nil
    (eaf-interleave--select-split-function)
    (switch-to-buffer buffer)))

(defun eaf-interleave--parse-current-dir (dir url)
  "If dir is '.' or begins with './', replace the '.' or './' with the current url name"
  (replace-regexp-in-string
   "^\\(\\.$\\|\\./\\).*"
   (file-name-directory url)
   dir nil nil 1))

(defun eaf-interleave--find-match-org (dir-list url)
  "Find corresponding org file base url on dir list"
  (let ((org-file (concat (file-name-base url) ".org"))
        path)
    (catch 'break
      (dolist (dir dir-list)
        (setq dir (eaf-interleave--parse-current-dir dir url))
        (setq path (locate-file org-file (list dir)))
        (when path
          ;; return the first match
          (throw 'break path))))
    path))

(defun eaf-interleave--ensure-org-file-exist (dir-list file-name)
  "If the org file directory exist return this path, else created directory."
  (let ((default-dir (nth 0 dir-list)))
    (if dir-list
        (progn
          (unless (file-exists-p default-dir)
            (make-directory default-dir))
          (expand-file-name file-name default-dir))
      (read-file-name "Path for org file: " "~/"))))

(provide 'eaf-interleave-eaf)
;;; eaf-interleave-eaf.el ends here
