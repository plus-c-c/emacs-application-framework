;;; eaf-epc-server.el --- EPC server implementation  -*- lexical-binding: t; -*-

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

;; TCP server for accepting EPC client connections.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'eaf-epc-deferred)
(require 'eaf-epc-connection)
(require 'eaf-epc-client)

(defvar eaf-epc-server-client-processes nil
  "[internal] A list of ([process object] . [`eaf-epc-manager' instance]).
When the server process accepts the client connection, the
`eaf-epc-manager' instance is created and stored in this variable
`eaf-epc-server-client-processes'. This variable is used for the management
purpose.")

(cl-defstruct eaf-epc-server name process port connect-function)

(defvar eaf-epc-server-processes nil
  "[internal] A list of ([process object] . [`eaf-epc-server' instance]).
This variable is used for the management purpose.")

(defun eaf-epc-server-get-manager-by-process (proc)
  "[internal] Return the eaf-epc-manager instance for the PROC."
  (cl-loop for (pp . mngr) in eaf-epc-server-client-processes
           if (eql pp proc)
           do (cl-return mngr)
           finally return nil))

(defun eaf-epc-server-accept (process)
  "[internal] Initialize the process and return eaf-epc-manager object."
  (eaf-epc-log "EAF-EPC-SERVER- >> Connection accept: %S" process)
  (let* ((connection-id (eaf-epc-uid))
         (connection-name (format "eaf-epc con %s" connection-id))
         (channel (list connection-name nil))
         (connection (make-eaf-epc-connection
                      :name connection-name
                      :process process
                      :buffer (process-buffer process)
                      :channel channel)))
    (eaf-epc-log "EAF-EPC-SERVER- >> Connection establish")
    (set-process-coding-system process 'binary 'binary)
    (set-process-filter process
                        (lambda (p m)
                          (eaf-epc-process-filter connection p m)))
    (set-process-query-on-exit-flag process nil)
    (set-process-sentinel process
                          (lambda (p e)
                            (eaf-epc-process-sentinel connection p e)))
    (make-eaf-epc-manager :server-process process :port t
                          :connection connection)))

(defun eaf-epc-server-sentinel (process message connect-function)
  "[internal] Process sentinel handler for the server process."
  (eaf-epc-log "EAF-EPC-SERVER- SENTINEL: %S %S" process message)
  (let ((mngr (eaf-epc-server-get-manager-by-process process)))
    (cond
     ;; new connection
     ((and (string-match "open" message) (null mngr))
      (condition-case err
          (let ((mngr (eaf-epc-server-accept process)))
            (push (cons process mngr) eaf-epc-server-client-processes)
            (eaf-epc-init-epc-layer mngr)
            (when connect-function (funcall connect-function mngr))
            mngr)
        ('error
         (eaf-epc-log "EAF-EPC-SERVER- Protocol error: %S" err)
         (eaf-epc-log "EAF-EPC-SERVER- ABORT %S" process)
         (delete-process process))))
     ;; ignore
     ((null mngr) nil )
     ;; disconnect
     (t
      (let ((pair (assq process eaf-epc-server-client-processes)) _d)
        (when pair
          (eaf-epc-log "EAF-EPC-SERVER- DISCONNECT %S" process)
          (eaf-epc-stop-epc (cdr pair))
          (setq eaf-epc-server-client-processes
                (assq-delete-all process eaf-epc-server-client-processes))
          ))
      nil))))

(defun eaf-epc-server-start (connect-function &optional port)
  "Start TCP Server and return the main process object."
  (let*
      ((connect-function connect-function)
       (name (format "EAF EPC Server %s" (eaf-epc-uid)))
       (buf (eaf-epc-make-procbuf (format " *%s*" name)))
       (main-process
        (make-network-process
         :name name
         :buffer buf
         :family 'ipv4
         :server t
         :host "127.0.0.1"
         :service (or port t)
         :noquery t
         :sentinel
         (lambda (process message)
           (eaf-epc-server-sentinel process message connect-function)))))
    (push (cons main-process
                (make-eaf-epc-server
                 :name name :process main-process
                 :port (process-contact main-process :service)
                 :connect-function connect-function))
          eaf-epc-server-processes)
    main-process))

(provide 'eaf-epc-server)
;;; eaf-epc-server.el ends here
