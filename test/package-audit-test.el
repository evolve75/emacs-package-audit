;;; package-audit-test.el --- Test utilities for package-audit -*- lexical-binding: t; -*-

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

;; Test utilities, helpers, and fixtures for package-audit test suite.
;; Provides functions for creating temporary test repositories, mock
;; package structures, and assertion helpers.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; ---------------------------------------------------------------------------
;; Path and fixture helpers

(defconst package-audit-test-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing package-audit test files.")

(defconst package-audit-test-source-directory
  (expand-file-name ".." package-audit-test-directory)
  "Directory containing package-audit source files.")

(defun package-audit-test-fixture-path (relative-path)
  "Return absolute path to fixture at RELATIVE-PATH."
  (expand-file-name relative-path
                    (expand-file-name "fixtures" package-audit-test-directory)))

;; ---------------------------------------------------------------------------
;; Temporary repository helpers

(defmacro package-audit-test-with-temp-repo (bindings &rest body)
  "Execute BODY in a temporary repository context.
BINDINGS is a list of (VAR VALUE) pairs where VAR will be bound to VALUE.
A temporary directory is created and bound to `temp-dir'.
The directory is automatically cleaned up after BODY completes."
  (declare (indent 1))
  `(let* ((temp-dir (make-temp-file "package-audit-test-" t))
          ,@bindings)
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p temp-dir)
         (delete-directory temp-dir t)))))

;; ---------------------------------------------------------------------------
;; Init file creation helpers

(defun package-audit-test-create-init-file (type content &optional repo-dir)
  "Create init file of TYPE with CONTENT in REPO-DIR.
TYPE should be 'org or 'el.
CONTENT is a string containing the file content.
REPO-DIR defaults to `default-directory'.
Returns the absolute path to the created file."
  (let* ((repo-dir (or repo-dir default-directory))
         (filename (pcase type
                     ('org "init.org")
                     ('el "init.el")
                     (_ (error "Invalid init file type: %s" type))))
         (filepath (expand-file-name filename repo-dir)))
    (with-temp-file filepath
      (insert content))
    filepath))

(defun package-audit-test-create-org-init (use-package-forms &optional repo-dir)
  "Create init.org with USE-PACKAGE-FORMS in REPO-DIR.
USE-PACKAGE-FORMS is a list of strings, each representing a use-package form.
Returns the absolute path to the created file."
  (let ((content (concat "* Package Configuration\n\n"
                         "#+BEGIN_SRC emacs-lisp\n"
                         (mapconcat #'identity use-package-forms "\n\n")
                         "\n#+END_SRC\n")))
    (package-audit-test-create-init-file 'org content repo-dir)))

(defun package-audit-test-create-el-init (use-package-forms &optional repo-dir)
  "Create init.el with USE-PACKAGE-FORMS in REPO-DIR.
USE-PACKAGE-FORMS is a list of strings, each representing a use-package form.
Returns the absolute path to the created file."
  (let ((content (concat ";;; init.el --- Test init file\n\n"
                         (mapconcat #'identity use-package-forms "\n\n")
                         "\n")))
    (package-audit-test-create-init-file 'el content repo-dir)))

;; ---------------------------------------------------------------------------
;; Custom file creation helpers

(defun package-audit-test-create-custom-file (selected-packages &optional variables repo-dir)
  "Create custom.el with SELECTED-PACKAGES and VARIABLES in REPO-DIR.
SELECTED-PACKAGES is a list of package symbols.
VARIABLES is an optional alist of (variable . value) pairs.
REPO-DIR defaults to `default-directory'.
Returns the absolute path to the created file."
  (let* ((repo-dir (or repo-dir default-directory))
         (filepath (expand-file-name "custom.el" repo-dir))
         (selected-form (when selected-packages
                          (format "'(package-selected-packages '%s)"
                                  (mapcar #'symbol-name selected-packages))))
         (variable-forms (mapcar (lambda (pair)
                                   (format "'(%s %s)"
                                           (car pair)
                                           (if (symbolp (cdr pair))
                                               (format "'%s" (cdr pair))
                                             (format "%S" (cdr pair)))))
                                 variables))
         (all-forms (delq nil (cons selected-form variable-forms))))
    (with-temp-file filepath
      (insert ";;; custom.el --- Test custom file\n\n")
      (when all-forms
        (insert "(custom-set-variables\n")
        (insert " " (mapconcat #'identity all-forms "\n "))
        (insert ")\n")))
    filepath))

;; ---------------------------------------------------------------------------
;; Mock package descriptor helpers

(defun package-audit-test-mock-package-desc (name version &optional deps)
  "Create a mock package descriptor for NAME with VERSION and DEPS.
NAME is a symbol representing the package name.
VERSION is a version string like \"1.0.0\".
DEPS is a list of (DEP-NAME DEP-VERSION) pairs.
Returns a package-desc structure."
  (require 'package)
  (let* ((version-list (version-to-list version))
         (reqs (mapcar (lambda (dep)
                         (list (car dep) (version-to-list (cadr dep))))
                       (or deps '()))))
    (package-desc-create
     :name name
     :version version-list
     :reqs reqs
     :summary (format "Mock package %s" name)
     :kind 'tar)))

(defun package-audit-test-create-package-alist (package-specs)
  "Create a mock package-alist from PACKAGE-SPECS.
PACKAGE-SPECS is a list of (NAME VERSION DEPS) triples.
Returns an alist suitable for binding to `package-alist'."
  (mapcar (lambda (spec)
            (let ((name (nth 0 spec))
                  (version (nth 1 spec))
                  (deps (nth 2 spec)))
              (list name (package-audit-test-mock-package-desc name version deps))))
          package-specs))

;; ---------------------------------------------------------------------------
;; Mock ELPA directory helpers

(defun package-audit-test-create-elpa-directory (repo-dir package-specs)
  "Create mock ELPA directory structure in REPO-DIR for PACKAGE-SPECS.
PACKAGE-SPECS is a list of (NAME VERSION) or (NAME VERSION DEPS) triples.
DEPS is an optional list of (DEP-NAME DEP-VERSION) pairs.
Creates directories matching package.el naming conventions.
Returns the path to the created elpa directory."
  (let ((elpa-dir (expand-file-name "elpa" repo-dir)))
    (make-directory elpa-dir t)
    (dolist (spec package-specs)
      (let* ((name (nth 0 spec))
             (version (nth 1 spec))
             (deps (nth 2 spec))
             (dir-name (format "%s-%s" name version))
             (pkg-dir (expand-file-name dir-name elpa-dir)))
        (make-directory pkg-dir t)
        ;; Create package descriptor file (required by package.el)
        (with-temp-file (expand-file-name (format "%s-pkg.el" name) pkg-dir)
          (insert (format "(define-package \"%s\" \"%s\"\n" name version)
                  (format "  \"Mock package %s\"\n" name)
                  (if deps
                      (format "  '%s)\n" deps)
                    "  nil)\n")))
        ;; Create a minimal package file
        (with-temp-file (expand-file-name (format "%s.el" name) pkg-dir)
          (insert (format ";;; %s.el --- Mock package\n" name)
                  (format "(provide '%s)\n" name)))))
    elpa-dir))

;; ---------------------------------------------------------------------------
;; Assertion helpers

(defun package-audit-test-assert-symbol-list-equal (expected actual &optional message)
  "Assert that EXPECTED and ACTUAL symbol lists are equal.
Comparison is order-independent.  Both lists are sorted before comparison.
MESSAGE is an optional failure message."
  (let ((expected-sorted (sort (copy-sequence expected)
                               (lambda (a b)
                                 (string< (symbol-name a) (symbol-name b)))))
        (actual-sorted (sort (copy-sequence actual)
                             (lambda (a b)
                               (string< (symbol-name a) (symbol-name b))))))
    (should (equal expected-sorted actual-sorted))))

(defun package-audit-test-assert-string-list-equal (expected actual &optional message)
  "Assert that EXPECTED and ACTUAL string lists are equal.
Comparison is order-independent.  Both lists are sorted before comparison.
MESSAGE is an optional failure message."
  (let ((expected-sorted (sort (copy-sequence expected) #'string<))
        (actual-sorted (sort (copy-sequence actual) #'string<)))
    (should (equal expected-sorted actual-sorted))))

;; ---------------------------------------------------------------------------
;; Test data generators

(defun package-audit-test-use-package-form (package-name &rest options)
  "Generate a use-package form string for PACKAGE-NAME with OPTIONS.
OPTIONS is a plist of use-package keywords and values.
Example: (package-audit-test-use-package-form 'magit :ensure t :bind ...)
Returns a string containing the use-package form."
  (let ((ensure (plist-get options :ensure))
        (vc (plist-get options :vc))
        (load-path (plist-get options :load-path)))
    (concat
     (format "(use-package %s" package-name)
     (when ensure
       (format "\n  :ensure %s" (if (eq ensure t) "t" ensure)))
     (when vc
       "\n  :vc t")
     (when load-path
       (format "\n  :load-path \"%s\"" load-path))
     ")")))

(provide 'package-audit-test)
;;; package-audit-test.el ends here
