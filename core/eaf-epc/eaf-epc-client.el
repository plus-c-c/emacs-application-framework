;;; eaf-epc-client.el --- EPC client/manager API  -*- lexical-binding: t; -*-

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

;; Client-side EPC manager: method registration, RPC calls, and session management.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'eaf-epc-deferred)
(require 'eaf-epc-connection)

(cl-defstruct eaf-epc-manager
  "Root object that holds all information related to an EPC activity.

`eaf-epc-start-epc' returns this object.

title          : instance name for displaying on the `eaf-epc-controller' UI
server-process : process object for the peer
commands       : a list of (prog . args)
port           : port number
connection     : eaf-epc-connection instance
methods        : alist of method (name . function)
sessions       : alist of session (id . deferred)
exit-hook      : functions for after shutdown EPC connection"
  title server-process commands port connection methods sessions exit-hooks)

(cl-defstruct eaf-epc-method
  "Object to hold serving method information.

name       : method name (symbol)   ex: 'test
task       : method function (function with one argument)
arg-specs  : arg-specs (one string) ex: \"(A B C D)\"
docstring  : docstring (one string) ex: \"A test function. Return sum of A,B,C and D\"
"
  name task docstring arg-specs)

(defvar eaf-epc-live-connections nil
  "[internal] A list of `eaf-epc-manager' objects.
those objects currently connect to the epc peer.
This variable is for debug purpose.")

(defun eaf-epc-stop-epc (mngr)
  "Disconnect the connection for the server."
  (let* ((proc (eaf-epc-manager-server-process mngr))
         (buf (and proc (process-buffer proc))))
    (eaf-epc-disconnect (eaf-epc-manager-connection mngr))
    (when proc
      (accept-process-output proc 0 eaf-epc-accept-process-timeout t))
    (when (and proc (equal 'run (process-status proc)))
      (kill-process proc))
    (when buf  (kill-buffer buf))
    (setq eaf-epc-live-connections (delete mngr eaf-epc-live-connections))
    ))

(defun eaf-epc-args (args)
  "[internal] If ARGS is an atom, return it. If list, return the cadr of it."
  (cond
   ((atom args) args)
   (t (cadr args))))

(defun eaf-epc-init-epc-layer (mngr)
  "[internal] Connect to the server program and return an eaf-epc-connection instance."
  (let* ((mngr mngr)
         (conn (eaf-epc-manager-connection mngr))
         (channel (eaf-epc-connection-channel conn)))
    ;; dispatch incoming messages with the lexical scope
    (cl-loop for (method . body) in
             `((call
                . (lambda (args)
                    (eaf-epc-log "SIG CALL: %S" args)
                    (apply 'eaf-epc-handler-called-method ,mngr (eaf-epc-args args))))
               (return
                . (lambda (args)
                    (eaf-epc-log "SIG RET: %S" args)
                    (apply 'eaf-epc-handler-return ,mngr (eaf-epc-args args))))
               (return-error
                . (lambda (args)
                    (eaf-epc-log "SIG RET-ERROR: %S" args)
                    (apply 'eaf-epc-handler-return-error ,mngr (eaf-epc-args args))))
               (epc-error
                . (lambda (args)
                    (eaf-epc-log "SIG EPC-ERROR: %S" args)
                    (apply 'eaf-epc-handler-epc-error ,mngr (eaf-epc-args args))))
               (methods
                . (lambda (args)
                    (eaf-epc-log "SIG METHODS: %S" args)
                    (eaf-epc-handler-methods ,mngr (caadr args))))
               ) do
             (eaf-epc-signal-connect channel method body))
    (push mngr eaf-epc-live-connections)
    mngr))

(defun eaf-epc-manager-send (mngr method &rest messages)
  "[internal] low-level message sending."
  (let* ((conn (eaf-epc-manager-connection mngr)))
    (eaf-epc-net-send conn (cons method messages))))

(defun eaf-epc-manager-get-method (mngr method-name)
  "[internal] Return a method object. If not found, return nil."
  (cl-loop for i in (eaf-epc-manager-methods mngr)
           if (eq method-name (eaf-epc-method-name i))
           do (cl-return i)))

(defun eaf-epc-handler-methods (mngr uid)
  "[internal] Return a list of information for registered methods."
  (let ((info
         (cl-loop for i in (eaf-epc-manager-methods mngr)
                  collect
                  (list
                   (eaf-epc-method-name i)
                   (or (eaf-epc-method-arg-specs i) "")
                   (or (eaf-epc-method-docstring i) "")))))
    (eaf-epc-manager-send mngr 'return uid info)))

(defun eaf-epc-handler-called-method (mngr uid name args)
  "[internal] low-level message handler for peer's calling."
  (let ((mngr mngr) (uid uid))
    (let* ((_methods (eaf-epc-manager-methods mngr))
           (method (eaf-epc-manager-get-method mngr name)))
      (cond
       ((null method)
        (eaf-epc-log "ERR: No such method : %s" name)
        (eaf-epc-manager-send mngr 'epc-error uid (format "EPC-ERROR: No such method : %s" name)))
       (t
        (condition-case err
            (let* ((f (eaf-epc-method-task method))
                   (ret (apply f args)))
              (cond
               ((eaf-deferred-object-p ret)
                (eaf-deferred-nextc ret
                  (lambda (xx) (eaf-epc-manager-send mngr 'return uid xx))))
               (t (eaf-epc-manager-send mngr 'return uid ret))))
          (error
           (eaf-epc-log "ERROR : %S" err)
           (eaf-epc-manager-send mngr 'return-error uid err))))))))

(defun eaf-epc-manager-remove-session (mngr uid)
  "[internal] Remove a session from the epc manager object."
  (cl-loop with ret = nil
           for pair in (eaf-epc-manager-sessions mngr)
           unless (eq uid (car pair))
           do (push pair ret)
           finally
           do (setf (eaf-epc-manager-sessions mngr) ret)))

(defun eaf-epc-handler-return (mngr uid args)
  "[internal] low-level message handler for normal returns."
  (let ((pair (assq uid (eaf-epc-manager-sessions mngr))))
    (cond
     (pair
      (eaf-epc-log "RET: id:%s [%S]" uid args)
      (eaf-epc-manager-remove-session mngr uid)
      (eaf-deferred-callback (cdr pair) args))
     (t ; error
      (eaf-epc-log "RET: NOT FOUND: id:%s [%S]" uid args)))))

(defun eaf-epc-handler-return-error (mngr uid args)
  "[internal] low-level message handler for application errors."
  (let ((pair (assq uid (eaf-epc-manager-sessions mngr))))
    (cond
     (pair
      (eaf-epc-log "RET-ERR: id:%s [%S]" uid args)
      (eaf-epc-manager-remove-session mngr uid)
      (eaf-deferred-errorback (cdr pair) (format "%S" args)))
     (t ; error
      (eaf-epc-log "RET-ERR: NOT FOUND: id:%s [%S]" uid args)))))

(defun eaf-epc-handler-epc-error (mngr uid args)
  "[internal] low-level message handler for epc errors."
  (let ((pair (assq uid (eaf-epc-manager-sessions mngr))))
    (cond
     (pair
      (eaf-epc-log "RET-EPC-ERR: id:%s [%S]" uid args)
      (eaf-epc-manager-remove-session mngr uid)
      (eaf-deferred-errorback (cdr pair) (list 'epc-error args)))
     (t ; error
      (eaf-epc-log "RET-EPC-ERR: NOT FOUND: id:%s [%S]" uid args)))))

(defun eaf-epc-call-deferred (mngr method-name args)
  "Call peer's method with args asynchronously. Return a deferred
object which is called with the result."
  (let ((uid (eaf-epc-uid))
        (sessions (eaf-epc-manager-sessions mngr))
        (d (eaf-deferred-new)))
    (push (cons uid d) sessions)
    (setf (eaf-epc-manager-sessions mngr) sessions)
    (eaf-epc-manager-send mngr 'call uid method-name args)
    d))

(defun eaf-epc-define-method (mngr method-name task &optional arg-specs docstring)
  "Define a method and return a deferred object which is called by the peer."
  (let* ((method (make-eaf-epc-method
                  :name method-name :task task
                  :arg-specs arg-specs :docstring docstring))
         (methods (cons method (eaf-epc-manager-methods mngr))))
    (setf (eaf-epc-manager-methods mngr) methods)
    method))

(defun eaf-epc-sync (mngr d)
  "Wrap deferred methods with synchronous waiting, and return the result.
If an exception is occurred, this function throws the error."
  (let ((result 'eaf-epc-nothing))
    (eaf-deferred-chain
     d
     (eaf-deferred-nextc it
       (lambda (x) (setq result x)))
     (eaf-deferred-error it
       (lambda (er) (setq result (cons 'error er)))))
    (while (eq result 'eaf-epc-nothing)
      (save-current-buffer
        (accept-process-output
         (eaf-epc-connection-process (eaf-epc-manager-connection mngr))
         0 eaf-epc-accept-process-timeout t)))
    (if (and (consp result) (eq 'error (car result)))
        (error (cdr result)) result)))

(defun eaf-epc-call-sync (mngr method-name args)
  "Call peer's method with args synchronously and return the result.
If an exception is occurred, this function throws the error."
  (eaf-epc-sync mngr (eaf-epc-call-deferred mngr method-name args)))

(defun eaf-epc-live-p (mngr)
  "Return non-nil when MNGR is an EPC manager object with a live
connection."
  (let ((proc (ignore-errors
                (eaf-epc-connection-process (eaf-epc-manager-connection mngr)))))
    (and (processp proc)
         ;; Same as `process-live-p' in Emacs >= 24:
         (memq (process-status proc) '(run open listen connect stop)))))

(provide 'eaf-epc-client)
;;; eaf-epc-client.el ends here
