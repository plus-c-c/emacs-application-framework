;;; eaf-interleave-vars.el --- Variables, constants and customizations for eaf-interleave -*- lexical-binding: t -*-

;;; Commentary:
;; Customizations, variables, constants and keymaps for eaf-interleave.

;;; Code:

(defcustom eaf-interleave-org-notes-dir-list '("~/org/interleave_notes" ".")
  "List of directories to look into when opening notes org from a pdf file.

The notes file is assumed to have the exact
same base name as the pdf file (just that the file extension is
.org instead of .pdf).

If the notes org file is not found, it is created in the
directory returned on doing `car' of this list (first element of
the list).

The notes file is searched in order from the first list element
till the last; the search is aborted once the file is found.

If a list element is \".\" or begins with \"./\", that portion is
replaced with the pdf directory name.  e.g. \".\" is interpreted
as \"/pdf/file/dir/\", \"./notes\" is interpreted as
\(/pdf/file/dir/notes/\"."
  :type '(repeat directory)
  :group 'eaf)

(defcustom eaf-interleave-split-direction 'vertical
  "Specify how to split the notes buffer."
  :type '(choice (const vertical)
                 (const horizontal))
  :group 'eaf)

(defcustom eaf-interleave-split-lines nil
  "Specify the number of lines the PDF buffer should be increased or decreased.

If nil both buffers are split equally.  If the number is positive,
the window is enlarged.  If the number is negative, the window is
shrunken.

If `eaf-interleave-split-direction' is 'vertical then the number is
taken as columns."
  :type '(choice integer
                 (const nil))
  :group 'eaf)

(defcustom eaf-interleave-disable-narrowing nil
  "Disable narrowing in notes/org buffer."
  :type 'boolean
  :group 'eaf)

(defvar eaf-interleave-org-buffer nil
  "Org notes buffer name.")

(defvar eaf-interleave--window-configuration nil
  "Variable to store the window configuration before interleave mode was enabled.")

(defconst eaf-interleave--page-note-prop "interleave_page_note"
  "The page note property string.")

(defconst eaf-interleave--url-prop "interleave_url"
  "The pdf property string.")

(defconst eaf-interleave--page-y-note-prop "interleave_page_y_note"
  "The page and Y-coordinate note property string.
Stores page and Y-percent (0-100) for line-level precision.")

(defvar eaf-interleave-mode-map (make-sparse-keymap)
  "Keymap while command `eaf-interleave-mode' is active in the org file buffer.")

(defvar eaf-interleave-app-mode-map (make-sparse-keymap)
  "Keymap while command `eaf-interleave-app-mode' is active.")

(provide 'eaf-interleave-vars)
;;; eaf-interleave-vars.el ends here
