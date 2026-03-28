;;; package-audit.el --- Interactive Emacs package audit entry point -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Anupam Sengupta

;; Author: Anupam Sengupta <anupamsg@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: convenience, tools, maint
;; SPDX-License-Identifier: GPL-3.0-or-later

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
