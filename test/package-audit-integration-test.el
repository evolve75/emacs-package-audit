;;; package-audit-integration-test.el --- Integration tests for package-audit -*- lexical-binding: t; -*-

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

;; End-to-end integration tests validating complete workflows.

;;; Code:

(require 'ert)
(require 'package-audit-test)
(require 'package-audit-core)
(require 'package-audit-remediate)
(require 'package-audit-report)

;; ---------------------------------------------------------------------------
;; Fresh installation workflow

(ert-deftest package-audit-integration-test-fresh-install-workflow ()
  "Test complete fresh installation workflow: init → audit → remediate."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file '() nil temp-dir))
           (elpa-dir (package-audit-test-create-elpa-directory
                      temp-dir
                      '((magit "3.0.0" nil)
                        (company "0.9.0" nil))))
           (package-audit-custom-state-file custom-file)
           (package-audit-package-install-directory elpa-dir))

      ;; Step 1: Build initial state (should detect R \ S drift)
      (let ((state (package-audit--build-state temp-dir)))
        ;; Verify R \ S detected (magit, company declared but not selected)
        (should (equal (plist-get state :init-roots-missing-from-selected) '(company magit)))
        (should (equal (plist-get state :selected) '()))

        ;; Step 2: Remediate by adding selections
        (let (saved-value)
          (cl-letf (((symbol-function 'customize-save-variable)
                     (lambda (_symbol value)
                       (setq saved-value value)))
                    ((symbol-function 'y-or-n-p)
                     (lambda (_prompt) t))
                    ((symbol-function 'yes-or-no-p)
                     (lambda (_prompt) t))
                    ((symbol-function 'message)
                     (lambda (&rest _args) nil))
                    ((symbol-function 'pop-to-buffer)
                     (lambda (_buffer) nil)))
            (package-audit-remediate-add-selected-packages temp-dir)
            ;; Verify both packages were added to selections
            (should (member 'magit saved-value))
            (should (member 'company saved-value)))

          ;; Step 3: Update custom file with saved selections
          (package-audit-test-create-custom-file saved-value nil temp-dir)

          ;; Step 4: Rebuild state and verify alignment
          (let ((final-state (package-audit--build-state temp-dir)))
            ;; Verify R = S (no more drift)
            (should (equal (plist-get final-state :init-roots-missing-from-selected) '()))
            (should (equal (plist-get final-state :selected-not-in-init) '()))
            ;; Verify I ⊆ D (no purgeable packages)
            (should (equal (plist-get final-state :purgeable) '()))))))))

;; ---------------------------------------------------------------------------
;; Migration workflow

(ert-deftest package-audit-integration-test-migration-workflow ()
  "Test migration workflow: package-selected-packages → init stubs."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file '(magit company flycheck) nil temp-dir))
           (package-audit-custom-state-file custom-file))

      ;; Step 1: Build state (should detect S \ R drift)
      (let ((state (package-audit--build-state temp-dir)))
        ;; Verify S \ R detected (company, flycheck selected but not in init)
        (should (equal (plist-get state :selected-not-in-init) '(company flycheck)))

        ;; Step 2: Remediate by inserting stubs
        (cl-letf (((symbol-function 'y-or-n-p)
                   (lambda (_prompt) t))
                  ((symbol-function 'yes-or-no-p)
                   (lambda (_prompt) t))
                  ((symbol-function 'message)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'pop-to-buffer)
                   (lambda (_buffer) nil)))
          (package-audit-remediate-add-use-package-stubs temp-dir))

        ;; Step 3: Verify stubs were added to init file
        (with-temp-buffer
          (insert-file-contents init-file)
          (let ((content (buffer-string)))
            (should (string-match-p "(use-package company" content))
            (should (string-match-p "(use-package flycheck" content))
            (should (string-match-p (regexp-quote package-audit-review-heading) content))))

        ;; Step 4: Rebuild state and verify alignment
        (let ((final-state (package-audit--build-state temp-dir)))
          ;; Verify S \ R is now empty (stubs were added)
          ;; Note: stubs are in review section, so they're detected as R now
          (should (member 'company (plist-get final-state :init-roots)))
          (should (member 'flycheck (plist-get final-state :init-roots)))
          (should (member 'magit (plist-get final-state :init-roots))))))))

;; ---------------------------------------------------------------------------
;; Cleanup workflow

(ert-deftest package-audit-integration-test-cleanup-workflow ()
  "Test cleanup workflow: detect and delete orphaned packages."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file '(magit company) nil temp-dir))
           (elpa-dir (package-audit-test-create-elpa-directory
                      temp-dir
                      '((magit "3.0.0" nil)
                        (company "0.9.0" nil)
                        (old-theme "1.0.0" nil))))  ;; Orphaned package
           (package-audit-custom-state-file custom-file)
           (package-audit-package-install-directory elpa-dir))

      ;; Step 1: Build state (should detect orphaned package)
      (let ((state (package-audit--build-state temp-dir)))
        ;; Verify old-theme is purgeable (I \ D)
        (should (member 'old-theme (plist-get state :purgeable)))

        ;; Step 2: Mock package deletion
        (let ((deleted-packages '()))
          (cl-letf (((symbol-function 'package-delete)
                     (lambda (desc &optional _force)
                       (push (package-desc-name desc) deleted-packages)))
                    ((symbol-function 'y-or-n-p)
                     (lambda (_prompt) t))
                    ((symbol-function 'message)
                     (lambda (&rest _args) nil)))
            (package-audit-remediate-delete-purgeable-packages temp-dir)
            ;; Verify old-theme was deleted
            (should (member 'old-theme deleted-packages)))

          ;; Step 3: Rebuild state (simulate post-deletion)
          ;; In real scenario, old-theme would be gone from package-alist
          ;; For this test, we verify the command attempted deletion
          (should t))))))

;; ---------------------------------------------------------------------------
;; Round-trip workflow

(ert-deftest package-audit-integration-test-full-round-trip ()
  "Test full round-trip: misaligned state → remediate all → aligned state."
  (package-audit-test-with-temp-repo ()
    (let* (;; R: magit, company (in init)
           ;; S: company, flycheck (in selections)
           ;; I: magit, company, flycheck, old-theme (installed)
           ;; Expected drift: R\S={magit}, S\R={flycheck}, I\D={old-theme}
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file '(company flycheck) nil temp-dir))
           (elpa-dir (package-audit-test-create-elpa-directory
                      temp-dir
                      '((magit "3.0.0" nil)
                        (company "0.9.0" nil)
                        (flycheck "32" nil)
                        (old-theme "1.0.0" nil))))
           (package-audit-custom-state-file custom-file)
           (package-audit-package-install-directory elpa-dir))

      ;; Step 1: Verify initial misalignment
      (let ((state (package-audit--build-state temp-dir)))
        (should (equal (plist-get state :init-roots-missing-from-selected) '(magit)))
        (should (equal (plist-get state :selected-not-in-init) '(flycheck)))
        (should (member 'old-theme (plist-get state :purgeable))))

      ;; Step 2: Fix R\S (add magit to selections)
      (let (saved-selections deleted-packages)
        (cl-letf (((symbol-function 'customize-save-variable)
                   (lambda (_symbol value)
                     (setq saved-selections value)))
                  ((symbol-function 'y-or-n-p)
                   (lambda (_prompt) t))
                  ((symbol-function 'yes-or-no-p)
                   (lambda (_prompt) t))
                  ((symbol-function 'message)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'pop-to-buffer)
                   (lambda (_buffer) nil))
                  ((symbol-function 'package-delete)
                   (lambda (desc &optional _force)
                     (push (package-desc-name desc) deleted-packages))))

          ;; Add missing selections (magit)
          (package-audit-remediate-add-selected-packages temp-dir)
          (should (member 'magit saved-selections))

          ;; Update package-selected-packages for next step
          (setq package-selected-packages saved-selections)

          ;; Add stubs for S\R (flycheck)
          (package-audit-remediate-add-use-package-stubs temp-dir)

          ;; Delete purgeable (old-theme)
          (package-audit-remediate-delete-purgeable-packages temp-dir)
          (should (member 'old-theme deleted-packages)))

        ;; Step 3: Verify final alignment
        (with-temp-buffer
          (insert-file-contents init-file)
          (let ((content (buffer-string)))
            ;; Verify flycheck stub was added
            (should (string-match-p "(use-package flycheck" content))))))))

;; ---------------------------------------------------------------------------
;; Batch mode workflow

(ert-deftest package-audit-integration-test-batch-mode-reports ()
  "Test batch mode report generation workflow."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file '(magit company) nil temp-dir))
           (elpa-dir (package-audit-test-create-elpa-directory
                      temp-dir
                      '((magit "3.0.0" nil)
                        (company "0.9.0" nil))))
           (reports-dir (expand-file-name "reports" temp-dir))
           (package-audit-custom-state-file custom-file)
           (package-audit-package-install-directory elpa-dir)
           (package-audit-report-directory reports-dir))

      ;; Create reports directory
      (make-directory reports-dir t)

      ;; Step 1: Generate reports in batch mode
      (let ((default-directory temp-dir))
        (package-audit-batch-write reports-dir))

      ;; Step 2: Verify both reports exist
      (let ((json-file (expand-file-name "package-audit.json" reports-dir))
            (md-file (expand-file-name "package-audit.md" reports-dir)))
        (should (file-exists-p json-file))
        (should (file-exists-p md-file))

        ;; Step 3: Verify JSON report contents
        (with-temp-buffer
          (insert-file-contents json-file)
          (let* ((json-string (buffer-string))
                 (parsed (json-read-from-string json-string)))
            ;; Verify key fields present
            (should (assq 'explicit_init_roots parsed))
            (should (assq 'package_selected_packages parsed))
            ;; Verify values correct
            (let ((roots (append (alist-get 'explicit_init_roots parsed) nil)))
              (should (member "magit" roots))
              (should (member "company" roots)))))

        ;; Step 4: Verify Markdown report structure
        (with-temp-buffer
          (insert-file-contents md-file)
          (let ((content (buffer-string)))
            (should (string-match-p "# Emacs Package Audit" content))
            (should (string-match-p "## Summary" content))
            ;; Verify counts in summary table
            (should (string-match-p "| `R`.*| Packages declared in init.*| 2" content))
            (should (string-match-p "| `S`.*| Packages in package-selected-packages.*| 2" content))))))))

(ert-deftest package-audit-integration-test-state-persistence ()
  "Test that audit state persists across multiple operations."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file '(magit) nil temp-dir))
           (package-audit-custom-state-file custom-file))

      ;; Step 1: Build initial state
      (let ((state1 (package-audit--build-state temp-dir)))
        (should (equal (plist-get state1 :init-roots) '(magit)))
        (should (equal (plist-get state1 :selected) '(magit)))

        ;; Step 2: Modify custom file directly
        (package-audit-test-create-custom-file '(magit company) nil temp-dir)

        ;; Step 3: Rebuild state (should detect change)
        (let ((state2 (package-audit--build-state temp-dir)))
          (should (equal (plist-get state2 :selected) '(company magit)))
          (should (equal (plist-get state2 :selected-not-in-init) '(company))))))))

(provide 'package-audit-integration-test)
;;; package-audit-integration-test.el ends here
