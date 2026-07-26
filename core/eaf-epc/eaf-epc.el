;;; eaf-epc.el --- EAF-EPC main entry point  -*- lexical-binding: t; -*-

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

;; Main entry point for the EAF-EPC package.
;; Requires all sub-modules: deferred, connection, client, server.

;;; Code:

(require 'eaf-epc-deferred)
(require 'eaf-epc-connection)
(require 'eaf-epc-client)
(require 'eaf-epc-server)

(provide 'eaf-epc)
;;; eaf-epc.el ends here
