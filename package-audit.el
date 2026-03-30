;;; package-audit.el --- Interactive Emacs package audit entry point -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Anupam Sengupta

;; Author: Anupam Sengupta <anupamsg@gmail.com>
;; Version: 1.0.0
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/evolve75/emacs-package-audit
;; Keywords: convenience, tools, maint
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `package-audit' analyzes package intent, selected packages, installed
;; packages, and dependency closure.  Load this entry file to enable the
;; batch and interactive command surface exposed by the package.

;;; Code:

(defconst package-audit--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing the `package-audit' package sources.")

(unless (member package-audit--directory load-path)
  (add-to-list 'load-path package-audit--directory))

(require 'package-audit-core)
(require 'package-audit-report)
(require 'package-audit-remediate)
(require 'package-audit-ui)

(provide 'package-audit)
;;; package-audit.el ends here
