;;; eaf-hook.el --- Advisory hooks  -*- lexical-binding: t; -*-

;; Forward declarations
(defvar eaf-find-file-ext-blacklist)
(defvar eaf-dired-advisor-enable)
(defvar eaf-find-file-advisor-enable)
(declare-function eaf-get-path-or-url "eaf" ())
(declare-function eaf-get-buffer-screenshot "eaf" ())

(defun eaf--scroll-other-window (orig-fun &optional arg &rest args)
  "When next buffer is `eaf-mode', do `eaf-scroll-up-or-next-page'."
  (other-window +1)
  (if (derived-mode-p 'eaf-mode)
      (progn
        (eaf-call-async "scroll_other_buffer" eaf--buffer-id "up"
                        (if arg "line" "page"))
        (other-window -1))
    (other-window -1)
    (apply orig-fun arg args)))
(advice-add 'scroll-other-window :around #'eaf--scroll-other-window)

(defun eaf--scroll-other-window-down (orig-fun &optional arg &rest args)
  "When next buffer is `eaf-mode', do `eaf-scroll-down-or-previous-page'."
  (other-window +1)
  (if (derived-mode-p 'eaf-mode)
      (progn
        (eaf-call-async "scroll_other_buffer" eaf--buffer-id "down"
                        (if arg "line" "page"))
        (other-window -1))
    (other-window -1)
    (apply orig-fun arg args)))
(advice-add 'scroll-other-window-down :around #'eaf--scroll-other-window-down)

(defun eaf--watch-other-window-internal (orig-fun &optional direction line
                                                  &rest args)
  "When next buffer is `eaf-mode', do `eaf-watch-other-window'."
  (other-window +1)
  (if (derived-mode-p 'eaf-mode)
      (progn
        (eaf-call-async "scroll_other_buffer" eaf--buffer-id
                        (if (string-equal direction "up") "up" "down")
                        (if line "line" "page"))
        (other-window -1))
    (other-window -1)
    (apply orig-fun direction line args)))
(advice-add 'watch-other-window-internal :around
            #'eaf--watch-other-window-internal)

(defun eaf--find-file (orig-fn file diredp &rest args)
  (let ((fn (if (commandp 'eaf-open)
                #'(lambda (file)
                    (eaf-open file))
              orig-fn))
        (ext (file-name-extension file)))
    ;; Open by EAF application if file extension match in `eaf-app-extensions-alist'.
    (if (eaf--find-file-ext-p ext)
        (cond
         ;; If file is svg, user choose open svg file by Emacs or EAF application.
         ((string-equal ext "svg")
          (if (y-or-n-p (format "Open '%s' with EAF? " file))
              (apply fn file nil)
            (find-file-literally file)))
         ;; If file is office, open by `eaf-open-office'.
         ((member ext '("docx" "doc" "ppt" "pptx" "xlsx" "xls"))
          (eaf-open-office file))
         ;; Open by EAF if not svg file.
         (t
          (apply fn file nil)))
      ;; Use `find-file' open file if file can not open by EAF.
      (if diredp
          ;; Open by dired if `diredp' is non-nil.
          (funcall orig-fn)
        ;; Open by EAF file manager if file is directory and user has install eaf-file-manager.
        (if (and (file-directory-p file)
                 (require 'eaf-file-manager nil t))
            (eaf-open-in-file-manager file)
          (apply orig-fn file args))))))

;; Make EAF as default app for supported extensions.
;; Use `eaf-open' in `find-file'
(defun eaf--find-file-advisor (orig-fn file &rest args)
  "Advisor of `find-file' that opens EAF supported file using EAF.

It currently identifies PDF, videos, images, and mindmap file extensions."
  (eaf--find-file orig-fn file nil args))
(advice-add #'find-file :around #'eaf--find-file-advisor)

;; Use `eaf-open' in `dired-find-file' and `dired-find-alternate-file'
(defun eaf--dired-find-file-advisor (orig-fn)
  "Advisor of `dired-find-file' and `dired-find-alternate-file' that opens EAF supported file using EAF.

It currently identifies PDF, videos, images, and mindmap file extensions."
  (dolist (file (dired-get-marked-files))
    (eaf--find-file orig-fn file t)))
(when eaf-dired-advisor-enable
  (advice-add #'dired-find-file :around #'eaf--dired-find-file-advisor)
  (advice-add #'dired-find-alternate-file :around #'eaf--dired-find-file-advisor))

(defun eaf--load-theme (&rest _ignores)
  (eaf-for-each-eaf-buffer
   (eaf-call-async "eval_function" eaf--buffer-id "update_theme" (key-description (this-command-keys-vector)))))
(advice-add #'load-theme :after #'eaf--load-theme)

(defun eaf--isearch-forward-advisor (orig-fun &optional arg &rest args)
  (if eaf-search-input-active-p
      (eaf-call-async "handle_search_forward" eaf-search-input-buffer-id eaf-search-input-callback-tag)
    (apply orig-fun arg args)))
(advice-add #'isearch-forward :around #'eaf--isearch-forward-advisor)
(when (and (ignore-errors (require 'swiper)) (featurep 'swiper))
  (advice-add #'swiper :around #'eaf--isearch-forward-advisor)
  (advice-add #'swiper-isearch :around #'eaf--isearch-forward-advisor))

(defun eaf--isearch-backward-advisor (orig-fun &optional arg &rest args)
  (if eaf-search-input-active-p
      (eaf-call-async "handle_search_backward" eaf-search-input-buffer-id eaf-search-input-callback-tag)
    (apply orig-fun arg args)))
(advice-add #'isearch-backward :around #'eaf--isearch-backward-advisor)
(when (and (ignore-errors (require 'counsel)) (featurep 'counsel))
  (advice-add #'counsel-minibuffer-history :around #'eaf--isearch-forward-advisor))

(provide 'eaf-hook)
;;; eaf-hook.el ends here
