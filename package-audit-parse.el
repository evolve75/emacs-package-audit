;;; package-audit-parse.el --- Init file parsing for package-audit -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Anupam Sengupta

;; Author: Anupam Sengupta <anupamsg@gmail.com>
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

;; Init file parsing helpers for extracting package roots from init.org
;; or init.el files.  Supports both Org-mode literate programming format
;; and plain Emacs Lisp format.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'subr-x)

;; Forward declarations for package-audit-core functions
(declare-function package-audit--repo-path "package-audit-core")
(declare-function package-audit--normalize-symbol-list "package-audit-core")
(declare-function package-audit--path-in-repo-p "package-audit-core")
(declare-function package-audit--read-forms "package-audit-core")
(declare-function package-audit--library-path "package-audit-core")

;; ---------------------------------------------------------------------------
;; Init source file detection

(defun package-audit--init-source-file-exists-p (repo-root filename)
  "Return non-nil when FILENAME exists as an init source in REPO-ROOT."
  (file-exists-p (package-audit--repo-path repo-root filename)))

(defun package-audit--detect-init-source-file (repo-root)
  "Return the init source filename for REPO-ROOT.
Prefers init.org when it exists.  Falls back to the basename of
`user-init-file' when init.org does not exist but the user-init-file
is located in REPO-ROOT.  Returns nil if neither is found."
  (cond
   ;; First preference: init.org
   ((package-audit--init-source-file-exists-p repo-root "init.org")
    "init.org")
   ;; Second preference: user-init-file if it's in this repo
   ((and user-init-file
         (file-exists-p user-init-file)
         (package-audit--path-in-repo-p user-init-file repo-root))
    (file-name-nondirectory user-init-file))
   ;; Fallback: check for literal init.el
   ((package-audit--init-source-file-exists-p repo-root "init.el")
    "init.el")
   (t nil)))

(defun package-audit--init-source-is-elisp-p (init-source)
  "Return non-nil if INIT-SOURCE is an Emacs Lisp file."
  (or (string-suffix-p ".el" init-source)
      (string-suffix-p ".emacs" init-source)
      (string-prefix-p ".emacs" (file-name-nondirectory init-source))))

;; ---------------------------------------------------------------------------
;; Generic elisp parsing primitives

(defun package-audit--read-elisp-forms (content)
  "Return top-level Emacs Lisp forms parsed from CONTENT."
  (with-temp-buffer
    (insert content)
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun package-audit--walk-form (form fn)
  "Call FN for each cons cell in FORM."
  (when (consp form)
    (funcall fn form)
    (package-audit--walk-form (car form) fn)
    (package-audit--walk-form (cdr form) fn)))

;; ---------------------------------------------------------------------------
;; use-package extraction logic

(defun package-audit--third-party-root-for-use-package (form repo-dir)
  "Return explicit third-party package root for `use-package' FORM."
  (when (and (consp form)
             (eq (car form) 'use-package)
             (symbolp (cadr form)))
    (let* ((package-name (cadr form))
           (plist (cddr form))
           (explicit-ensure (plist-member plist :ensure))
           (ensure (plist-get plist :ensure))
           (load-path-p (plist-member plist :load-path))
           (library-path (package-audit--library-path package-name)))
      (cond
       ;; `:ensure nil' and `:ensure' without a value are explicit opt-outs.
       ((and explicit-ensure (null ensure)) nil)
       ;; Literal `:ensure t' means the feature name is also the package root.
       ((eq ensure t) package-name)
       ;; Symbolic `:ensure' captures package aliases such as `tex' -> `auctex'.
       ((symbolp ensure) ensure)
       ;; Explicit load-path usage is treated as repo-local configuration.
       (load-path-p nil)
       ;; Libraries found inside the repo are first-party, not third-party roots.
       ((and library-path
             (not (string-match-p "/elpa/" library-path))
             (package-audit--path-in-repo-p library-path repo-dir))
        nil)
       ;; Non-ELPA libraries outside the repo are left to external provisioning.
       ((and library-path
             (not (string-match-p "/elpa/" library-path)))
        nil)
       ;; Fall back to the requested package name when the declaration is external.
       (t package-name)))))

;; ---------------------------------------------------------------------------
;; Format-specific parsers

(defun package-audit--explicit-init-roots-from-org (init-source repo-dir)
  "Return explicit third-party package roots from org INIT-SOURCE file."
  (with-temp-buffer
    (insert-file-contents init-source)
    (org-mode)
    (let (roots)
      (org-element-map (org-element-parse-buffer) 'src-block
        (lambda (block)
          (when (string= (org-element-property :language block) "emacs-lisp")
            (dolist (form (package-audit--read-elisp-forms
                           (org-element-property :value block)))
              (package-audit--walk-form
               form
               (lambda (cell)
                 (let ((root (package-audit--third-party-root-for-use-package
                              cell repo-dir)))
                   (when root
                     (push root roots)))))))))
      (package-audit--normalize-symbol-list roots))))

(defun package-audit--explicit-init-roots-from-el (init-source repo-dir)
  "Return explicit third-party package roots from elisp INIT-SOURCE file."
  (let (roots)
    (dolist (form (package-audit--read-forms init-source))
      (package-audit--walk-form
       form
       (lambda (cell)
         (let ((root (package-audit--third-party-root-for-use-package
                      cell repo-dir)))
           (when root
             (push root roots))))))
    (package-audit--normalize-symbol-list roots)))

;; ---------------------------------------------------------------------------
;; Public API

(defun package-audit--explicit-init-roots (init-source repo-dir)
  "Return explicit third-party package roots declared in INIT-SOURCE.
Supports both .org and .el file formats."
  (cond
   ((string-suffix-p ".org" init-source)
    (package-audit--explicit-init-roots-from-org init-source repo-dir))
   ((package-audit--init-source-is-elisp-p init-source)
    (package-audit--explicit-init-roots-from-el init-source repo-dir))
   (t
    (user-error "Unsupported init source file format: %s (expected .org or elisp)"
                init-source))))

(provide 'package-audit-parse)
;;; package-audit-parse.el ends here
