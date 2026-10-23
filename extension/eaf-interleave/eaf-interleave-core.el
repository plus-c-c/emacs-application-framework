;;; eaf-interleave-core.el --- Core navigation and note management -*- lexical-binding: t -*-

;;; Commentary:
;; Navigation, note management and display logic for eaf-interleave.

;;; Code:

(require 'org)
(require 'org-element)
(require 'eaf-interleave-vars)

;;;###autoload
(define-minor-mode eaf-interleave-mode
  "Interleaving your text books since 2015.

In the past, textbooks were sometimes published as 'interleaved' editions.
That meant, each page was followed by a blank page and the ambitious student/
scholar had the ability to take their notes directly in their copy of the
textbook. Newton and Kant were prominent representatives of this technique.

Nowadays textbooks (or lecture material) come in PDF format. Although almost
every PDF Reader has the ability to add some notes to the PDF itself, it is
not as powerful as it could be.

This is what this minor mode tries to accomplish. It presents your PDF side by
pppside to an [[http://orgmode.org][Org Mode]] buffer with your notes, narrowing
down to just those passages that are relevant to the particular page in the
document viewer.

The split direction is determined by the customizable variable
`eaf-interleave-split-direction'. When `eaf-interleave-mode' is invoked
with a prefix argument the inverse split direction is used
e.g. if `eaf-interleave-split-direction' is 'vertical the buffer is
split horizontally."
  :keymap eaf-interleave-mode-map
  (if eaf-interleave-mode
      (setq eaf-interleave-org-buffer (current-buffer))
    ;; Disable the corresponding minor mode in the PDF file too.
    (setq eaf-interleave-org-buffer nil)))

;;;###autoload
(define-minor-mode eaf-interleave-app-mode
  "Interleave view for the EAF app."
  :keymap eaf-interleave-app-mode-map)

;;; functions
;; interactive
(defun eaf-interleave-sync-current-note ()
  "Sync EAF buffer on current note"
  (interactive)
  (let ((url (org-entry-get-with-inheritance eaf-interleave--url-prop)))
    (cond ((and (string-prefix-p "/" url) (string-suffix-p "pdf" url t))
           (eaf-interleave-sync-pdf-page-current))
          ((string-prefix-p "http" url)
           (eaf-interleave-sync-browser-url-current))))
  )

(defun eaf-interleave-sync-pdf-page-current ()
  "Open PDF page and Y-coordinate for currently visible notes.
Uses page:y_percent for line-level precision when available."
  (interactive)
  (let* ((page-y (org-entry-get-with-inheritance eaf-interleave--page-y-note-prop))
         (pdf-page (org-entry-get-with-inheritance eaf-interleave--page-note-prop))
         (pdf-url (org-entry-get-with-inheritance eaf-interleave--url-prop))
         (buffer (eaf-interleave--find-buffer pdf-url)))
    (if buffer
        (progn
          (eaf-interleave--display-buffer buffer)
          (cond
           (page-y
            (with-current-buffer buffer
              (eaf-interleave--pdf-viewer-goto-page-y pdf-url page-y)))
           (pdf-page
            (with-current-buffer buffer
              (eaf-interleave--pdf-viewer-goto-page pdf-url pdf-page)))))
      (eaf-interleave--select-split-function)
      (eaf-interleave--open-pdf pdf-url)
      )))

(defun eaf-interleave-sync-next-note ()
  "Move to the next set of notes.
This shows the next notes and synchronizes the PDF to the right page number."
  (interactive)
  (eaf-interleave--switch-to-org-buffer)
  (widen)
  (org-forward-heading-same-level 1)
  (eaf-interleave--narrow-to-subtree)
  (org-show-subtree)
  (org-cycle-hide-drawers t)
  (eaf-interleave-sync-current-note))

(defun eaf-interleave-add-note ()
  "Add note for the EAF buffer.

If there are already notes for this url, jump to the notes
buffer."
  (interactive)
  (if (derived-mode-p 'eaf-mode)
      (cond ((equal eaf--buffer-app-name "pdf-viewer")
             (eaf-interleave--pdf-add-note))
            ((equal eaf--buffer-app-name "browser")
             (eaf-interleave--browser-add-note)))
    ))

(defun eaf-interleave-add-file-url ()
  "Add a new url on note if the property is none, else modify current url."
  (interactive)
  (let ((url (read-file-name "Please specify path: " nil nil t)))
    (org-entry-put (point) eaf-interleave--url-prop url)))

(defun eaf-interleave-sync-previous-note ()
  "Move to the previous set of notes.
This show the previous notes and synchronizes the PDF to the right page number."
  (interactive)
  (eaf-interleave--switch-to-org-buffer)
  (widen)
  (eaf-interleave--goto-parent-headline eaf-interleave--page-note-prop)
  (org-backward-heading-same-level 1)
  (eaf-interleave--narrow-to-subtree)
  (org-show-subtree)
  (org-cycle-hide-drawers t)
  (eaf-interleave-sync-current-note))

(defun eaf-interleave-open-notes-file ()
  "Find current EAF url corresponding note files if it exists."
  (interactive)
  (if (derived-mode-p 'eaf-mode)
      (cond ((equal eaf--buffer-app-name "pdf-viewer")
             (eaf-interleave--open-notes-file-for-pdf))
            ((equal eaf--buffer-app-name "browser")
             (eaf-interleave--open-notes-file-for-browser))))
  )

(defun eaf-interleave-quit ()
  "Quit interleave mode."
  (interactive)
  (with-current-buffer eaf-interleave-org-buffer
    (widen)
    (goto-char (point-min))
    (when (eaf-interleave--headlines-available-p)
      (org-overview))
    (eaf-interleave-mode 0)))

;;;###autoload
(defun eaf-interleave--open-notes-file-for-pdf ()
  "Open the notes org file for the current pdf file if it exists.
Else create it. It is assumed that the notes org file will have
the exact same base name as the pdf file (just that the notes
file will have a .org extension instead of .pdf)."
  (let ((org-file (concat (file-name-base eaf--buffer-url) ".org")))
    (eaf-interleave--open-notes-file-for-app org-file)))

(defun eaf-interleave--open-notes-file-for-browser ()
  "Find current open interleave-mode org file, if exists, else
will create new org file with URL. It is assumed that the notes
org file will have the exact sam base name as the url domain."
  (unless (buffer-live-p eaf-interleave-org-buffer)
    (let* ((domain (url-domain (url-generic-parse-url eaf--buffer-url)))
           (org-file (concat domain ".org")))
      (eaf-interleave--open-notes-file-for-app org-file))))

(defun eaf-interleave--open-notes-file-for-app (org-file)
  "Open the notes org file for the current url if it exists.
Else create it."
  (let ((org-file-path (eaf-interleave--find-match-org eaf-interleave-org-notes-dir-list eaf--buffer-url))
        (buffer (eaf-interleave--find-buffer eaf--buffer-url)))
    ;; Create the notes org file if it does not exist
    (unless org-file-path
      (setq org-file-path (eaf-interleave--ensure-org-file-exist eaf-interleave-org-notes-dir-list org-file)))
    ;; Open the notes org file and enable `eaf-interleave-mode'
    (find-file org-file-path)
    (eaf-interleave-mode)
    (eaf-interleave--select-split-function)
    (switch-to-buffer buffer)
    ))

(defun eaf-interleave--select-split-function ()
  "Determine which split function to use.

This returns either `split-window-below' or `split-window-right'
based on a combination of `current-prefix-arg' and
`eaf-interleave-split-direction'."
  (let ()
    (delete-other-windows)
    (if (string= eaf-interleave-split-direction "vertical")
        (split-window-right)
      (split-window-below))
    (when (integerp eaf-interleave-split-lines)
      (if (eql eaf-interleave-split-direction 'horizontal)
          (enlarge-window eaf-interleave-split-lines)
        (enlarge-window-horizontally eaf-interleave-split-lines)))
    ))

(defun eaf-interleave--page-y-close-p (a b &optional tolerance)
  "Return non-nil when page-y strings A and B are on the same line.
TOLERANCE is a percentage of the page height (default 2.0)."
  (let* ((a-parts (split-string a ":"))
         (b-parts (split-string b ":"))
         (a-page (car a-parts))
         (b-page (car b-parts))
         (a-y (string-to-number (or (cadr a-parts) "0")))
         (b-y (string-to-number (or (cadr b-parts) "0"))))
    (and (equal a-page b-page)
         (<= (abs (- a-y b-y)) (or tolerance 2.0)))))

(defun eaf-interleave--go-to-page-note (url page &optional page-y)
  "Look up notes for the current PDF PAGE, optionally at PAGE-Y.

PAGE-Y is a \"page:y_percent\" string.  When it is non-nil, a
note is considered a match only when it is on the same page and
within a small vertical tolerance.  This lets multiple notes on one
page point at different lines.

If `eaf-interleave-disable-narrowing' is non-nil then the buffer gets
re-centered to the page heading.

It (possibly) narrows the subtree when found."
  (with-current-buffer eaf-interleave-org-buffer
    (widen)
    (let ((position
           (catch 'found
             (org-map-entries
              (lambda ()
                (let ((note-url (org-entry-get-with-inheritance
                                 eaf-interleave--url-prop))
                      (note-page (org-entry-get-with-inheritance
                                  eaf-interleave--page-note-prop))
                      (note-page-y (org-entry-get-with-inheritance
                                    eaf-interleave--page-y-note-prop)))
                  (when (and (string= note-url url)
                             (string= note-page (number-to-string page))
                             (or (null page-y)
                                 (and note-page-y
                                      (eaf-interleave--page-y-close-p
                                       page-y note-page-y))))
                    (throw 'found (point)))))))))
      (when (integer-or-marker-p position)
        (goto-char position)
        (org-back-to-heading t)
        (eaf-interleave--narrow-to-subtree)
        (org-show-subtree)
        (org-cycle-hide-drawers t)
        (point)))))

(defun eaf-interleave--narrow-to-subtree (&optional force)
  "Narrow buffer to the current subtree.

If `eaf-interleave-disable-narrowing' is non-nil this
function does nothing.

When FORCE is non-nil `eaf-interleave-disable-narrowing' is
ignored."
  (when (and (not (org-before-first-heading-p))
             (or (not eaf-interleave-disable-narrowing)
                 force))
    (org-narrow-to-subtree)))

(defun eaf-interleave--switch-to-org-buffer (&optional insert-newline-maybe position)
  "Switch to the notes buffer.

Inserts a newline into the notes buffer if INSERT-NEWLINE-MAYBE
is non-nil.
If POSITION is non-nil move point to it."
  (if (derived-mode-p 'eaf-mode)
      (switch-to-buffer-other-window eaf-interleave-org-buffer)
    (switch-to-buffer eaf-interleave-org-buffer))
  (when (integerp position)
    (goto-char position))
  (when insert-newline-maybe
    (save-restriction
      (when eaf-interleave-disable-narrowing
        (eaf-interleave--narrow-to-subtree t))
      (goto-char (point-max)))
    ;; Expand again. Sometimes the new content is outside the narrowed
    ;; region.
    (org-show-subtree)
    (redisplay)
    ;; Insert a new line if not already on a new line
    (when (not (looking-back "^ *" (line-beginning-position)))
      (org-return))))

(defun eaf-interleave--insert-heading-respect-content ()
  "Create a new heading in the notes buffer.

Adjust the level of the new headline according to the
PARENT-HEADLINE.

Return the position of the newly inserted heading."
  (org-insert-heading-respect-content)
  (let* ((parent-level 0 )
         (change-level (if (> (org-element-property :level (org-element-at-point))
                              (1+ parent-level))
                           #'org-promote
                         #'org-demote)))
    (while (/= (org-element-property :level (org-element-at-point))
               (1+ parent-level))
      (funcall change-level)))
  (point))

(defun eaf-interleave--create-new-note (url &optional title page-y)
  "Create a new headline for current EAF url.
PAGE-Y is a string in format 'page:y_percent' (e.g. '5:32.5')."
  (let (new-note-position)
    (with-current-buffer eaf-interleave-org-buffer
      (save-excursion
        (widen)
        (setq new-note-position (eaf-interleave--insert-heading-respect-content))
        (org-set-property eaf-interleave--url-prop url)
        (when title
          (insert (format "Notes for %s" title)))
        (when page-y
          (let* ((parts (split-string page-y ":"))
                 (page (car parts))
                 (y-pct (cadr parts)))
            (org-set-property eaf-interleave--page-note-prop page)
            (org-set-property eaf-interleave--page-y-note-prop page-y)))
        (eaf-interleave--narrow-to-subtree)
        (org-cycle-hide-drawers t)))
    (eaf-interleave--switch-to-org-buffer t new-note-position)))

(defun eaf-interleave-sync-browser-url-current ()
  "Sync current note url for browser"
  (let* ((web-url (org-entry-get-with-inheritance eaf-interleave--url-prop))
        (buffer (eaf-interleave--find-buffer web-url)))
    (if buffer
        (eaf-interleave--display-buffer buffer)
      (eaf-interleave--select-split-function)
      (eaf-interleave--open-web-url web-url))))

(defun eaf-interleave--display-buffer (buffer)
  "Use already used window display buffer"
  (eaf-interleave--narrow-to-subtree)
  (display-buffer-reuse-mode-window buffer '(("mode" . "eaf-interleave-app-mode")))
  (eaf-interleave--ensure-buffer-window buffer))

(defun eaf-interleave--goto-parent-headline (property)
  "Traverse the tree until the parent headline.

Consider a headline with property PROPERTY as parent headline."
  (catch 'done
    (if (and (eql (org-element-type (org-element-at-point)) 'headline)
             (org-entry-get (point) property))
        (org-element-at-point)
      (condition-case nil
          (org-up-element)
        ('error
         (throw 'done nil)))
      (eaf-interleave--goto-parent-headline property))))

(defun eaf-interleave--pdf-add-note ()
  "EAF pdf-viewer-mode add note"
  (let* ((page-y (eaf-interleave--pdf-viewer-current-page-y eaf--buffer-url))
         (page (string-to-number (car (split-string page-y ":"))))
         (position (eaf-interleave--go-to-page-note
                    eaf--buffer-url page page-y)))
    (if position
        (eaf-interleave--switch-to-org-buffer t position)
      (eaf-interleave--create-new-note eaf--buffer-url eaf--buffer-app-name page-y)))
  )

(defun eaf-interleave--browser-add-note ()
  "EAF browser add note"
  (eaf-interleave--create-new-note eaf--buffer-url eaf--buffer-app-name))

(defun eaf-interleave--headlines-available-p ()
  "True if there are headings in the notes buffer."
  (save-excursion
    (re-search-forward "^\* .*" nil t)))

(provide 'eaf-interleave-core)
;;; eaf-interleave-core.el ends here
