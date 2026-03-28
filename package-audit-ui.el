;;; package-audit-ui.el --- Interactive UI helpers for package-audit -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Anupam Sengupta

;; Author: Anupam Sengupta <anupamsg@gmail.com>
;; Keywords: convenience, tools, maint
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Interactive command entrypoints and optional Hydra integration.

;;; Code:

(require 'package-audit-core)
(require 'package-audit-report)
(require 'package-audit-remediate)

(defun package-audit--operations-message ()
  "Return fallback operations summary used when Hydra is unavailable."
  (string-join
   '("Hydra is unavailable. Available commands:"
     "`package-audit-refresh`"
     "`package-audit-open-markdown-report`"
     "`package-audit-open-json-report`"
     "`package-audit-remediate-add-selected-packages`"
     "`package-audit-remediate-add-use-package-stubs`"
     "`package-audit-remediate-delete-purgeable-packages`"
     "`package-audit-remediate-delete-ignored-directories`")
   " "))

;;;###autoload
(defun package-audit-show-operations ()
  "Show the package-audit operations menu or a fallback command summary."
  (interactive)
  (if (and (require 'hydra nil t)
           (fboundp 'package-audit-hydra/body))
      (package-audit-hydra/body)
    (message "%s" (package-audit--operations-message))))

;;;###autoload
(defun package-audit-refresh (&optional repo-root output-dir)
  "Regenerate package-audit reports for REPO-ROOT and OUTPUT-DIR."
  (interactive)
  (package-audit--refresh-session repo-root output-dir t)
  (package-audit-show-operations))

;;;###autoload
(defun package-audit-run (&optional repo-root output-dir)
  "Generate package-audit reports, open Markdown output, and show operations."
  (interactive)
  (package-audit-refresh repo-root output-dir))

(when (require 'hydra nil t)
  (defhydra package-audit-hydra (:color teal :hint nil)
    "
Package Audit
_g_: refresh report      _m_: open markdown    _j_: open json
_s_: add selected roots  _u_: add stubs        _p_: delete purgeable
_d_: delete stale dirs   _q_: quit
"
    ("g" package-audit-refresh)
    ("m" package-audit-open-markdown-report)
    ("j" package-audit-open-json-report)
    ("s" package-audit-remediate-add-selected-packages)
    ("u" package-audit-remediate-add-use-package-stubs)
    ("p" package-audit-remediate-delete-purgeable-packages)
    ("d" package-audit-remediate-delete-ignored-directories)
    ("q" nil "quit")))

(provide 'package-audit-ui)
;;; package-audit-ui.el ends here
