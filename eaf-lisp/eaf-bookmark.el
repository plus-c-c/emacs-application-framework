;;; eaf-bookmark.el --- Bookmark support  -*- lexical-binding: t; -*-

;; Forward declarations
(defvar eaf--buffer-app-name)
(defvar eaf-app-bookmark-handlers-alist)
(defvar eaf-app-bookmark-restore-alist)

(defun eaf--bookmark-make-record ()
  "Create a EAF bookmark.

The bookmark will try to recreate EAF buffer session.
For now only EAF browser app is supported."
  (let ((handler (cdr
                  (assoc eaf--buffer-app-name
                         eaf-app-bookmark-handlers-alist))))
    (when handler
      (funcall handler))))

(defun eaf--bookmark-restore (bookmark)
  "Restore EAF buffer according to BOOKMARK."
  (let ((app (cdr (assq 'eaf-app bookmark))))
    (funcall (cdr (assoc app eaf-app-bookmark-restore-alist)) bookmark)))

;;;###autoload
(defun eaf-open-bookmark ()
  "Command to open or create EAF bookmarks with completion."
  (interactive)
  (bookmark-maybe-load-default-file)
  (let* ((bookmarks (cl-remove-if-not
                     (lambda (entry)
                       (bookmark-prop-get entry 'eaf-app))
                     bookmark-alist))
         (names (mapcar #'car bookmarks))
         (cand (completing-read "EAF Bookmarks: " bookmarks)))
    (cond ((member cand names)
           (bookmark-jump cand))
          (t
           (unless (derived-mode-p 'eaf-mode)
             (message "This command can only be called in an EAF buffer!"))
           ;; create new one for current buffer with provided name
           (bookmark-set cand)))))

(defvar eaf--existing-bookmarks nil
  "Existing bookmarks in Emacs.
A hashtable, key is url and value is title.")

(defun eaf--load-existing-bookmarks()
  "Load existing bookmarks."
  (let ((bookmarks (make-hash-table :test 'equal)))
    (dolist (bm bookmark-alist)
      (let* ((name (car bm))
             (file (bookmark-get-filename name)))
        (puthash file name bookmarks)))
    bookmarks))

(provide 'eaf-bookmark)
;;; eaf-bookmark.el ends here
