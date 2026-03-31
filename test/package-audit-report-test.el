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

(ert-deftest package-audit-report-test-markdown-summary-table ()
  "Test markdown summary table rendering."
  (let* ((counts '((explicit_init_roots . 5)
                   (package_selected_packages . 4)
                   (explicit_init_roots_missing_from_package_selected . 1)
                   (selected_not_in_init . 2)
                   (selected_and_customize_only . 1)
                   (installed_packages . 10)
                   (retained_dependency_only . 3)
                   (definitively_purgeable . 2)))
         (result (package-audit--markdown-summary-table counts)))
    ;; Verify table structure
    (should (string-match-p "| Set.*| Description.*| Count.*|" result))
    (should (string-match-p "| -.*| -.*| -.*|" result))
    ;; Verify content
    (should (string-match-p "`R`" result))
    (should (string-match-p "`S`" result))
    (should (string-match-p "`I`" result))
    (should (string-match-p "5" result))
    (should (string-match-p "10" result))))

(ert-deftest package-audit-report-test-markdown-metadata-table-with-expression ()
  "Test metadata table with set expression."
  (let* ((result (package-audit--markdown-metadata-table "R \\ S" "missing_from_selected")))
    ;; Verify table structure
    (should (string-match-p "| Set expression.*| JSON key.*|" result))
    (should (string-match-p "| -.*| -.*|" result))
    ;; Verify content
    (should (string-match-p "`R \\\\ S`" result))
    (should (string-match-p "`missing_from_selected`" result))))

(ert-deftest package-audit-report-test-markdown-metadata-table-no-expression ()
  "Test metadata table without set expression."
  (let* ((result (package-audit--markdown-metadata-table nil "some_key")))
    ;; Verify table structure (single column)
    (should (string-match-p "| JSON key.*|" result))
    (should (string-match-p "| -.*|" result))
    ;; Verify content
    (should (string-match-p "`some_key`" result))
    ;; Verify no set expression column
    (should-not (string-match-p "Set expression" result))))

(ert-deftest package-audit-report-test-markdown-definitions-table ()
  "Test static definitions table rendering."
  (let* ((result (package-audit--markdown-definitions-table)))
    ;; Verify table structure
    (should (string-match-p "| Term.*| Meaning.*|" result))
    (should (string-match-p "| -.*| -.*|" result))
    ;; Verify key definitions present
    (should (string-match-p "Init root" result))
    (should (string-match-p "Selected package" result))
    (should (string-match-p "Installed package" result))
    (should (string-match-p "Dependency closure" result))
    (should (string-match-p "Protected ELPA directory" result))))

(ert-deftest package-audit-report-test-markdown-protected-dir-notes-archives ()
  "Test protected directory notes for archives."
  (let* ((result (package-audit--markdown-protected-dir-notes '("archives"))))
    ;; Verify archives note present
    (should (string-match-p "elpa/archives" result))
    (should (string-match-p "package index caches" result))
    ;; Verify gnupg note absent
    (should-not (string-match-p "gnupg" result))))

(ert-deftest package-audit-report-test-markdown-protected-dir-notes-gnupg ()
  "Test protected directory notes for gnupg."
  (let* ((result (package-audit--markdown-protected-dir-notes '("gnupg"))))
    ;; Verify gnupg note present
    (should (string-match-p "elpa/gnupg" result))
    (should (string-match-p "signature verification" result))
    ;; Verify archives note absent
    (should-not (string-match-p "archives" result))))

(ert-deftest package-audit-report-test-markdown-protected-dir-notes-both ()
  "Test protected directory notes for both archives and gnupg."
  (let* ((result (package-audit--markdown-protected-dir-notes '("archives" "gnupg"))))
    ;; Verify both notes present
    (should (string-match-p "elpa/archives" result))
    (should (string-match-p "elpa/gnupg" result))))

(ert-deftest package-audit-report-test-markdown-protected-dir-notes-empty ()
  "Test protected directory notes with no protected dirs."
  (let* ((result (package-audit--markdown-protected-dir-notes '())))
    ;; Verify empty result
    (should (equal result ""))))

(ert-deftest package-audit-report-test-markdown-reasons ()
  "Test dependency reason rendering."
  (let* ((pairs '(("dash" . "magit")
                  ("s" . "magit")
                  ("f" . "projectile")))
         (packages '("dash" "s" "f"))
         (result (package-audit--markdown-reasons pairs packages)))
    ;; Verify all packages present
    (should (string-match-p "- `dash`: retained via `magit`" result))
    (should (string-match-p "- `s`: retained via `magit`" result))
    (should (string-match-p "- `f`: retained via `projectile`" result))))

(ert-deftest package-audit-report-test-markdown-reasons-empty ()
  "Test dependency reason rendering with no packages."
  (let* ((result (package-audit--markdown-reasons '() '())))
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

;; ---------------------------------------------------------------------------
;; Comprehensive report generation tests

(ert-deftest package-audit-report-test-json-edge-cases-empty-lists ()
  "Test JSON encoding handles empty lists correctly."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit))
           (init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (elpa-dir (package-audit-test-create-elpa-directory
                      temp-dir
                      '((magit "3.0.0" nil)))))
      (let ((package-audit-custom-state-file custom-file)
            (package-audit-package-install-directory elpa-dir))
        (let* ((state (package-audit--build-state temp-dir))
               (data (package-audit--data-from-state temp-dir state))
               (json-string (json-encode data))
               (parsed (json-read-from-string json-string)))
          ;; In aligned state with ELPA directory, these should be empty
          (should (equal (append (alist-get 'explicit_init_roots_missing_from_package_selected parsed) nil) '()))
          (should (equal (append (alist-get 'selected_not_in_init parsed) nil) '()))
          (should (equal (append (alist-get 'definitively_purgeable parsed) nil) '())))))))

(ert-deftest package-audit-report-test-markdown-full-content ()
  "Test full markdown report contains all expected sections."
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
        ;; Verify all major sections present
        (should (string-match-p "# Emacs Package Audit" markdown))
        (should (string-match-p "## Summary" markdown))
        (should (string-match-p "## Declared in init but not in package-selected-packages" markdown))
        (should (string-match-p "## Selected but not declared in" markdown))
        (should (string-match-p "## Selected but only configured via Customize" markdown))
        (should (string-match-p "## Customized variables by package" markdown))
        (should (string-match-p "## Packages installed as dependencies" markdown))
        (should (string-match-p "## Orphaned packages" markdown))
        (should (string-match-p "## Definitions" markdown))))))

(ert-deftest package-audit-report-test-markdown-with-drift ()
  "Test markdown report with package drift."
  (package-audit-test-with-temp-repo ()
    (let* ((init-packages '(magit company))
           (selected-packages '(company flycheck))
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file selected-packages nil temp-dir))
           (package-audit-custom-state-file custom-file))
      (let* ((state (package-audit--build-state temp-dir))
             (data (package-audit--data-from-state temp-dir state))
             (markdown (package-audit-render-markdown data temp-dir)))
        ;; Verify drift is reported
        (should (string-match-p "magit" markdown))  ;; In R \ S
        (should (string-match-p "flycheck" markdown))  ;; In S \ R
        ;; Verify fix instructions present
        (should (string-match-p "package-audit-remediate-add-selected-packages" markdown))
        (should (string-match-p "package-audit-remediate-add-use-package-stubs" markdown))))))

(ert-deftest package-audit-report-test-json-full-structure ()
  "Test JSON report contains all expected top-level and nested keys."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit))
           (init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (package-audit-custom-state-file custom-file))
      (let* ((state (package-audit--build-state temp-dir))
             (data (package-audit--data-from-state temp-dir state))
             (json-string (json-encode data))
             (parsed (json-read-from-string json-string)))
        ;; Verify all top-level keys
        (should (assq 'repo_dir parsed))
        (should (assq 'explicit_init_roots parsed))
        (should (assq 'package_selected_packages parsed))
        (should (assq 'explicit_init_roots_missing_from_package_selected parsed))
        (should (assq 'selected_not_in_init parsed))
        (should (assq 'selected_and_customize_only parsed))
        (should (assq 'selected_customize_variables parsed))
        (should (assq 'installed_packages parsed))
        (should (assq 'retained_dependency_only parsed))
        (should (assq 'retained_dependency_reasons parsed))
        (should (assq 'definitively_purgeable parsed))
        (should (assq 'explicit_roots_missing_from_elpa parsed))
        (should (assq 'selected_missing_from_elpa parsed))
        (should (assq 'protected_non_package_elpa_directories parsed))
        (should (assq 'ignored_non_package_elpa_directories parsed))
        (should (assq 'counts parsed))
        ;; Verify counts has all expected keys
        (let ((counts (alist-get 'counts parsed)))
          (should (assq 'explicit_init_roots counts))
          (should (assq 'package_selected_packages counts))
          (should (assq 'explicit_init_roots_missing_from_package_selected counts))
          (should (assq 'selected_not_in_init counts))
          (should (assq 'installed_packages counts))
          (should (assq 'retained_dependency_only counts))
          (should (assq 'definitively_purgeable counts)))))))

(provide 'package-audit-report-test)
;;; package-audit-report-test.el ends here
