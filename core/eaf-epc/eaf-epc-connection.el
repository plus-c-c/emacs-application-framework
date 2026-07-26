;;; eaf-epc-connection.el --- EPC network connection and protocol  -*- lexical-binding: t; -*-

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

;; Network connection layer for EAF-EPC protocol.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'eaf-epc-deferred)

(defvar eaf-epc-debug nil)

(defun eaf-epc-log (&rest args)
  (when eaf-epc-debug
    (with-current-buffer (get-buffer-create "*eaf-epc-log*")
      (buffer-disable-undo)
      (goto-char (point-max))
      (insert (apply 'format args) "\n\n\n"))))

(defun eaf-epc-make-procbuf (name)
  "[internal] Make a process buffer."
  (let ((buf (get-buffer-create name)))
    (with-current-buffer buf
      (set (make-local-variable 'kill-buffer-query-functions) nil)
      (erase-buffer) (buffer-disable-undo))
    buf))

(defvar eaf-epc-uid 1)

(defun eaf-epc-uid ()
  (cl-incf eaf-epc-uid))

(defvar eaf-epc-accept-process-timeout 150
  "Asynchronous timeout time. (msec)")

(put 'epc-error 'error-conditions '(error epc-error))
(put 'epc-error 'error-message "EPC Error")

(cl-defstruct eaf-epc-connection
  "Set of information for network connection and event handling.

name    : Connection name. This name is used for process and buffer names.
process : Connection process object.
buffer  : Working buffer for the incoming data.
channel : Event channels for incoming messages."
  name process buffer channel)

(defun eaf-epc-connect (host port)
  "[internal] Connect the server, initialize the process and
return eaf-epc-connection object."
  (eaf-epc-log ">> Connection start: %s:%s" host port)
  (let* ((connection-id (eaf-epc-uid))
         (connection-name (format "eaf-epc con %s" connection-id))
         (connection-buf (eaf-epc-make-procbuf (format "*%s*" connection-name)))
         (connection-process
          (open-network-stream connection-name connection-buf host port))
         (channel (list connection-name nil))
         (connection (make-eaf-epc-connection
                      :name connection-name
                      :process connection-process
                      :buffer connection-buf
                      :channel channel)))
    (eaf-epc-log ">> Connection establish")
    (set-process-coding-system  connection-process 'binary 'binary)
    (set-process-filter connection-process
                        (lambda (p m)
                          (eaf-epc-process-filter connection p m)))
    (set-process-sentinel connection-process
                          (lambda (p e)
                            (eaf-epc-process-sentinel connection p e)))
    (set-process-query-on-exit-flag connection-process nil)
    connection))

(defun eaf-epc-process-sentinel (connection process msg)
  (eaf-epc-log "!! Process Sentinel [%s] : %S : %S"
               (eaf-epc-connection-name connection) process msg)
  (eaf-epc-disconnect connection))

(defun eaf-epc-net-send (connection sexp)
  (let* ((msg (encode-coding-string
               (concat (eaf-epc-prin1-to-string sexp) "\n") 'utf-8-unix))
         (string (concat (format "%06x" (length msg)) msg))
         (proc (eaf-epc-connection-process connection)))
    (eaf-epc-log ">> SEND : [%S]" string)
    (process-send-string proc string)))

(defun eaf-epc-disconnect (connection)
  (let ((process (eaf-epc-connection-process connection))
        (buf (eaf-epc-connection-buffer connection))
        (name (eaf-epc-connection-name connection)))
    (eaf-epc-log "!! Disconnect [%s]" name)
    (when process
      (set-process-sentinel process nil)
      (delete-process process)
      (when (get-buffer buf) (kill-buffer buf)))
    (eaf-epc-log "!! Disconnected finished [%s]" name)))

(defun eaf-epc-process-filter (connection process message)
  (eaf-epc-log "INCOMING: [%s] [%S]" (eaf-epc-connection-name connection) message)
  (with-current-buffer (eaf-epc-connection-buffer connection)
    (goto-char (point-max))
    (insert message)
    (eaf-epc-process-available-input connection process)))

(defun eaf-epc-signal-connect (channel event-sym &optional callback)
  "Append an observer for EVENT-SYM of CHANNEL and return a deferred object.
If EVENT-SYM is `t', the observer receives all signals of the channel.
If CALLBACK function is given, the deferred object executes the
CALLBACK function asynchronously. One can connect subsequent
tasks to the returned deferred object."
  (let ((d (if callback
               (eaf-deferred-new callback)
             (eaf-deferred-new))))
    (push (cons event-sym d)
          (cddr channel))
    d))

(defun eaf-epc-signal-send (channel event-sym &rest args)
  "Send a signal to CHANNEL. If ARGS values are given,
observers can get the values by following code:

  (lambda (event)
    (destructuring-bind
     (event-sym (args))
     event ... ))
"
  (let ((observers (cddr channel))
        (event (list event-sym args)))
    (cl-loop for i in observers
             for name = (car i)
             for d = (cdr i)
             if (or (eq event-sym name) (eq t name))
             do (eaf-deferred-callback-post d event))))

(defun eaf-epc-process-available-input (connection process)
  "Process all complete messages that have arrived from Lisp."
  (with-current-buffer (process-buffer process)
    (while (eaf-epc-net-have-input-p)
      (let ((event (eaf-epc-net-read-or-lose process))
            (ok nil))
        (eaf-epc-log "<< RECV [%S]" event)
        (unwind-protect
            (condition-case err
                (progn
                  (apply 'eaf-epc-signal-send
                         (cons (eaf-epc-connection-channel connection) event))
                  (setq ok t))
              ('error (eaf-epc-log "MsgError: %S / <= %S" err event)))
          (unless ok
            (eaf-epc-process-available-input connection process)))))))

(defun eaf-epc-net-have-input-p ()
  "Return true if a complete message is available."
  (goto-char (point-min))
  (and (>= (buffer-size) 6)
       (>= (- (buffer-size) 6) (eaf-epc-net-decode-length))))

(defun eaf-epc-net-read-or-lose (_process)
  (condition-case error
      (eaf-epc-net-read)
    (error
     (debug 'error error)
     (error "net-read error: %S" error))))

(defun eaf-epc-net-read ()
  "Read a message from the network buffer."
  (goto-char (point-min))
  (let* ((length (eaf-epc-net-decode-length))
         (start (+ 6 (point)))
         (end (+ start length))
         _content)
    (cl-assert (cl-plusp length))
    (prog1 (save-restriction
             (narrow-to-region start end)
             (read (decode-coding-string
                    (buffer-string) 'utf-8-unix)))
      (delete-region (point-min) end))))

(defun eaf-epc-net-decode-length ()
  "Read a 24-bit hex-encoded integer from buffer."
  (string-to-number (buffer-substring-no-properties (point) (+ (point) 6)) 16))

(defun eaf-epc-prin1-to-string (sexp)
  "Like `prin1-to-string' but don't octal-escape non-ascii characters.
This is more compatible with the CL reader."
  (with-temp-buffer
    (let (print-escape-nonascii
          print-escape-newlines
          print-length
          print-level)
      (prin1 sexp (current-buffer))
      (buffer-string))))

(provide 'eaf-epc-connection)
;;; eaf-epc-connection.el ends here
