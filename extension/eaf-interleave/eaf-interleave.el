;;; eaf-interleave.el --- Interleaving text books on EAF -*- lexical-binding: t -*-

;; Author: Sebastian Christ <rudolfo.christ@gmail.com>
;; URL: https://github.com/rudolfochrist/interleave
;; Version: 1.4.20161123-610
;; Fork: luhuaei <luhuaei@gmail.com>

;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; In the past, textbooks were sometimes published as 'interleaved'
;; editions.  That meant, each page was followed by a blank page and
;; ambitious students/scholars had the ability to take their notes
;; directly in their copy of the textbook.  Newton and Kant were
;; prominent representatives of this technique.

;; Nowadays textbooks (or lecture material) come in PDF format.  Although almost
;; every PDF Reader has the ability to add some notes to the PDF itself, it is
;; not as powerful as it could be.

;; This is what this minor mode tries to accomplish.  It presents your PDF side by
;; side to an [[http://orgmode.org][Org Mode]] buffer with your notes, narrowing
;; down to just those passages that are relevant to the particular page in the
;; document viewer.

;;; Usage:

;;; Code:

(require 'eaf-interleave-vars)
(require 'eaf-interleave-core)
(require 'eaf-interleave-eaf)

(provide 'eaf-interleave-sub)
;;; eaf-interleave.el ends here
