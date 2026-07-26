;;; eaf-epc-deferred.el --- Deferred task system for EAF-EPC  -*- lexical-binding: t; -*-

;; Copyright (C) 2011,2012,2013  Masashi Sakurai

;; Author: Masashi Sakurai <m.sakurai at kiwanami.net>
;; Keywords: lisp

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Deferred/promise task system for EAF-EPC.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defmacro eaf-deferred-chain (&rest elements)
  "Anaphoric function chain macro for deferred chains."
  (declare (debug (&rest form))
           (indent 0))
  `(let (it)
     ,@(cl-loop for i in elements
                collect
                `(setq it ,i))
     it))

(defvar eaf-deferred-debug nil
  "Debug output switch.")

(defvar eaf-deferred-debug-count 0
  "[internal] Debug output counter.")

(defun eaf-deferred-log (&rest args)
  "[internal] Debug log function."
  (when eaf-deferred-debug
    (with-current-buffer (get-buffer-create "*eaf-deferred-log*")
      (save-excursion
        (goto-char (point-max))
        (insert (format "%5i %s\n\n\n" eaf-deferred-debug-count (apply #'format args)))))
    (cl-incf eaf-deferred-debug-count)))

(defvar eaf-deferred-debug-on-signal nil
  "If non nil, the value `debug-on-signal' is substituted this
value in the `condition-case' form in deferred
implementations. Then, Emacs debugger can catch an error occurred
in the asynchronous tasks.")

(defmacro eaf-deferred-condition-case (var protected-form &rest handlers)
  "[internal] Custom condition-case. See the comment for
`eaf-deferred-debug-on-signal'."
  (declare (debug condition-case)
           (indent 1))
  `(let ((debug-on-signal
          (or debug-on-signal eaf-deferred-debug-on-signal)))
     (condition-case ,var
         ,protected-form
       ,@handlers)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Back end functions of deferred tasks

(defvar eaf-deferred-tick-time 0.001
  "Waiting time between asynchronous tasks (second).
The shorter waiting time increases the load of Emacs. The end
user can tune this parameter. However, applications should not
modify it because the applications run on various environments.")

(defvar eaf-deferred-queue nil
  "[internal] The execution queue of deferred objects.
See the functions `eaf-deferred-post-task' and `eaf-deferred-worker'.")

(defun eaf-deferred-post-task (d which &optional arg)
  "[internal] Add a deferred object to the execution queue
`eaf-deferred-queue' and schedule to execute.
D is a deferred object. WHICH is a symbol, `ok' or `ng'. ARG is
an argument value for execution of the deferred task."
  (let ((pack `(,d ,which . ,arg)))
    (push pack eaf-deferred-queue)
    (eaf-deferred-log "QUEUE-POST [%s]: %s" (length eaf-deferred-queue) pack)
    (run-at-time eaf-deferred-tick-time nil 'eaf-deferred-worker)
    d))

(defun eaf-deferred-worker ()
  "[internal] Consume a deferred task.
Mainly this function is called by timer asynchronously."
  (when eaf-deferred-queue
    (let* ((pack (car (last eaf-deferred-queue)))
           (d (car pack))
           (which (cadr pack))
           (arg (cddr pack)) value)
      (setq eaf-deferred-queue (nbutlast eaf-deferred-queue))
      (condition-case err
          (setq value (eaf-deferred-exec-task d which arg))
        (error
         (eaf-deferred-log "ERROR : %s" err)
         (message "deferred error : %s" err)))
      value)))

(cl-defstruct eaf-deferred-object
  (callback 'identity)
  (errorback 'eaf-deferred-resignal)
  (cancel 'eaf-deferred-default-cancel)
  next status value)

(defun eaf-deferred-resignal (err)
  "[internal] Safely resignal ERR as an Emacs condition.

If ERR is a cons (ERROR-SYMBOL . DATA) where ERROR-SYMBOL has an
`error-conditions' property, it is re-signaled unchanged. If ERR
is a string, it is signaled as a generic error using `error'.
Otherwise, ERR is formatted into a string as if by `print' before
raising with `error'."
  (cond ((and (listp err)
              (symbolp (car err))
              (get (car err) 'error-conditions))
         (signal (car err) (cdr err)))
        ((stringp err)
         (error "%s" err))
        (t
         (error "%S" err))))

(defun eaf-deferred-default-cancel (d)
  "[internal] Default canceling function."
  (eaf-deferred-log "CANCEL : %s" d)
  (setf (eaf-deferred-object-callback d) 'identity)
  (setf (eaf-deferred-object-errorback d) 'eaf-deferred-resignal)
  (setf (eaf-deferred-object-next d) nil)
  d)

(defun eaf-deferred-exec-task (d which &optional arg)
  "[internal] Executing deferred task. If the deferred object has
next deferred task or the return value is a deferred object, this
function adds the task to the execution queue.
D is a deferred object. WHICH is a symbol, `ok' or `ng'. ARG is
an argument value for execution of the deferred task."
  (eaf-deferred-log "EXEC : %s / %s / %s" d which arg)
  (when (null d) (error "eaf-deferred-exec-task was given a nil."))
  (let ((callback (if (eq which 'ok)
                      (eaf-deferred-object-callback d)
                    (eaf-deferred-object-errorback d)))
        (next-deferred (eaf-deferred-object-next d)))
    (cond
     (callback
      (eaf-deferred-condition-case err
        (let ((value (funcall callback arg)))
          (cond
           ((eaf-deferred-object-p value)
            (eaf-deferred-log "WAIT NEST : %s" value)
            (if next-deferred
                (eaf-deferred-set-next value next-deferred)
              value))
           (t
            (if next-deferred
                (eaf-deferred-post-task next-deferred 'ok value)
              (setf (eaf-deferred-object-status d) 'ok)
              (setf (eaf-deferred-object-value d) value)
              value))))
        (error
         (cond
          (next-deferred
           (eaf-deferred-post-task next-deferred 'ng err))
          (t
           (eaf-deferred-log "ERROR : %S" err)
           (message "deferred error : %S" err)
           (setf (eaf-deferred-object-status d) 'ng)
           (setf (eaf-deferred-object-value d) err)
           err)))))
     (t ; <= (null callback)
      (cond
       (next-deferred
        (eaf-deferred-exec-task next-deferred which arg))
       ((eq which 'ok) arg)
       (t                             ; (eq which 'ng)
        (eaf-deferred-resignal arg)))))))

(defun eaf-deferred-set-next (prev next)
  "[internal] Connect deferred objects."
  (setf (eaf-deferred-object-next prev) next)
  (cond
   ((eq 'ok (eaf-deferred-object-status prev))
    (setf (eaf-deferred-object-status prev) nil)
    (let ((ret (eaf-deferred-exec-task
                next 'ok (eaf-deferred-object-value prev))))
      (if (eaf-deferred-object-p ret) ret
        next)))
   ((eq 'ng (eaf-deferred-object-status prev))
    (setf (eaf-deferred-object-status prev) nil)
    (let ((ret (eaf-deferred-exec-task next 'ng (eaf-deferred-object-value prev))))
      (if (eaf-deferred-object-p ret) ret
        next)))
   (t
    next)))

(defun eaf-deferred-new (&optional callback)
  "Create a deferred object."
  (if callback
      (make-eaf-deferred-object :callback callback)
    (make-eaf-deferred-object)))

(defun eaf-deferred-callback (d &optional arg)
  "Start deferred chain with a callback message."
  (eaf-deferred-exec-task d 'ok arg))

(defun eaf-deferred-errorback (d &optional arg)
  "Start deferred chain with an errorback message."
  (declare (indent 1))
  (eaf-deferred-exec-task d 'ng arg))

(defun eaf-deferred-callback-post (d &optional arg)
  "Add the deferred object to the execution queue."
  (declare (indent 1))
  (eaf-deferred-post-task d 'ok arg))

(defun eaf-deferred-next (&optional callback arg)
  "Create a deferred object and schedule executing. This function
is a short cut of following code:
 (eaf-deferred-callback-post (eaf-deferred-new callback))."
  (let ((d (if callback
               (make-eaf-deferred-object :callback callback)
             (make-eaf-deferred-object))))
    (eaf-deferred-callback-post d arg)
    d))

(defun eaf-deferred-nextc (d callback)
  "Create a deferred object with OK callback and connect it to the given deferred object."
  (declare (indent 1))
  (let ((nd (make-eaf-deferred-object :callback callback)))
    (eaf-deferred-set-next d nd)))

(defun eaf-deferred-error (d callback)
  "Create a deferred object with errorback and connect it to the given deferred object."
  (declare (indent 1))
  (let ((nd (make-eaf-deferred-object :errorback callback)))
    (eaf-deferred-set-next d nd)))

(provide 'eaf-epc-deferred)
;;; eaf-epc-deferred.el ends here
