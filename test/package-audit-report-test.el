;;; package-audit-report-test.el --- Tests for package-audit-report -*- lexical-binding: t; -*-

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

;; Tests for package-audit-report.el report generation and rendering.

;;; Code:

(require 'ert)
(require 'json)
(require 'package-audit-test)
(require 'package-audit-core)
(require 'package-audit-report)

;; ---------------------------------------------------------------------------
;; Basic markdown rendering tests

(ert-deftest package-audit-report-test-markdown-bullets-with-items ()
  "Test markdown bullet rendering with items."
  (let* ((items '("magit" "company" "flycheck"))
         (result (package-audit--markdown-bullets items)))
    (should (string-match-p "- `magit`" result))
    (should (string-match-p "- `company`" result))
    (should (string-match-p "- `flycheck`" result))))

(ert-deftest package-audit-report-test-markdown-bullets-empty ()
  "Test markdown bullet rendering with no items."
  (let* ((result (package-audit--markdown-bullets '())))
    (should (equal result "- None")))
  (let* ((result (package-audit--markdown-bullets nil)))
    (should (equal result "- None"))))

(ert-deftest package-audit-report-test-markdown-package-vars ()
  "Test markdown package variable rendering."
  (let* ((pairs '((magit . (magit-display-buffer-function magit-log-margin))
                  (company . (company-idle-delay))))
         (result (package-audit--markdown-package-vars pairs)))
    (should (string-match-p "- `magit`:" result))
    (should (string-match-p "`magit-display-buffer-function`" result))
    (should (string-match-p "`magit-log-margin`" result))
    (should (string-match-p "- `company`:" result))
    (should (string-match-p "`company-idle-delay`" result))))

(ert-deftest package-audit-report-test-markdown-package-vars-empty ()
  "Test markdown package variable rendering with no variables."
  (let* ((result (package-audit--markdown-package-vars '())))
    (should (equal result "- None")))
  (let* ((result (package-audit--markdown-package-vars nil)))
    (should (equal result "- None"))))

;; ---------------------------------------------------------------------------
;; JSON generation tests

(ert-deftest package-audit-report-test-json-structure-complete ()
  "Test JSON report contains all expected keys."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit company))
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (package-audit-custom-state-file custom-file))
      (let* ((state (package-audit--build-state temp-dir))
             (data (package-audit--data-from-state temp-dir state))
             (json-string (json-encode data))
             (parsed (json-read-from-string json-string)))
        ;; Verify top-level keys exist
        (should (assq 'repo_dir parsed))
        (should (assq 'counts parsed))
        (should (assq 'explicit_init_roots parsed))
        (should (assq 'package_selected_packages parsed))
        (should (assq 'installed_packages parsed))
        (should (assq 'definitively_purgeable parsed))
        ;; Verify counts object has expected keys
        (let ((counts (alist-get 'counts parsed)))
          (should (assq 'explicit_init_roots counts))
          (should (assq 'package_selected_packages counts))
          (should (assq 'installed_packages counts)))))))

(ert-deftest package-audit-report-test-json-values-correct ()
  "Test JSON report values match audit data."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit company))
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (package-audit-custom-state-file custom-file))
      (let* ((state (package-audit--build-state temp-dir))
             (data (package-audit--data-from-state temp-dir state))
             (json-string (json-encode data))
             (parsed (json-read-from-string json-string)))
        ;; Verify explicit_init_roots contains magit and company
        (let ((roots (append (alist-get 'explicit_init_roots parsed) nil)))
          (should (member "magit" roots))
          (should (member "company" roots)))
        ;; Verify package_selected_packages contains magit and company
        (let ((selected (append (alist-get 'package_selected_packages parsed) nil)))
          (should (member "magit" selected))
          (should (member "company" selected)))
        ;; Verify counts are correct
        (let ((counts (alist-get 'counts parsed)))
          (should (= (alist-get 'explicit_init_roots counts) 2))
          (should (= (alist-get 'package_selected_packages counts) 2)))))))

(ert-deftest package-audit-report-test-json-valid-format ()
  "Test JSON report is valid JSON."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit))
           (init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (package-audit-custom-state-file custom-file))
      (let* ((state (package-audit--build-state temp-dir))
             (data (package-audit--data-from-state temp-dir state))
             (json-string (json-encode data)))
        ;; Verify it's valid JSON (no parse error)
        (should (json-read-from-string json-string))
        ;; Verify it's a string
        (should (stringp json-string))
        ;; Verify it starts with {
        (should (string-prefix-p "{" json-string))))))

(ert-deftest package-audit-report-test-markdown-structure ()
  "Test markdown report has expected structure."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit company))
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (package-audit-custom-state-file custom-file))
      (let* ((state (package-audit--build-state temp-dir))
             (data (package-audit--data-from-state temp-dir state))
             (markdown (package-audit-render-markdown data temp-dir)))
        ;; Verify main heading
        (should (string-match-p "# Emacs Package Audit" markdown))
        ;; Verify summary section
        (should (string-match-p "## Summary" markdown))
        ;; Verify definitions section
        (should (string-match-p "## Definitions" markdown))
        ;; Verify it's a string
        (should (stringp markdown))))))

(ert-deftest package-audit-report-test-batch-write ()
  "Test batch report writing to file."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit))
           (init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (reports-dir (expand-file-name "reports" temp-dir))
           (package-audit-custom-state-file custom-file)
           (package-audit-report-directory reports-dir)
           (inhibit-message t))
      ;; Create reports directory
      (make-directory reports-dir t)
      ;; Write batch reports (set default-directory as function resolves repo-root internally)
      (let ((default-directory temp-dir))
        (package-audit-batch-write reports-dir))
      ;; Verify files were created
      (should (file-exists-p (expand-file-name "package-audit.json" reports-dir)))
      (should (file-exists-p (expand-file-name "package-audit.md" reports-dir)))
      ;; Verify JSON file contains valid JSON
      (let ((json-content (with-temp-buffer
                            (insert-file-contents (expand-file-name "package-audit.json" reports-dir))
                            (buffer-string))))
        (should (json-read-from-string json-content))))))

(provide 'package-audit-report-test)
;;; package-audit-report-test.el ends here
