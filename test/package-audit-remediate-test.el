;;; package-audit-remediate-test.el --- Tests for package-audit-remediate -*- lexical-binding: t; -*-

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

;; Tests for package-audit-remediate.el remediation commands.

;;; Code:

(require 'ert)
(require 'package-audit-test)
(require 'package-audit-core)
(require 'package-audit-remediate)

;; ---------------------------------------------------------------------------
;; Stub generation tests

(ert-deftest package-audit-remediate-test-org-stub-generation ()
  "Test org format use-package stub generation."
  (let* ((packages '(magit company))
         (result (package-audit--use-package-stub-block packages)))
    ;; Verify org block structure
    (should (string-match-p "^#\\+BEGIN_SRC emacs-lisp$" result))
    (should (string-match-p "^#\\+END_SRC$" result))
    ;; Verify use-package forms present
    (should (string-match-p "(use-package magit" result))
    (should (string-match-p ":ensure t)" result))
    (should (string-match-p "(use-package company" result))))

(ert-deftest package-audit-remediate-test-elisp-stub-generation ()
  "Test elisp format use-package stub generation."
  (let* ((packages '(magit company))
         (result (package-audit--use-package-stub-elisp packages)))
    ;; Verify use-package forms present
    (should (string-match-p "(use-package magit" result))
    (should (string-match-p ":ensure t)" result))
    (should (string-match-p "(use-package company" result))
    ;; Verify no org block markers
    (should-not (string-match-p "#\\+BEGIN_SRC" result))
    (should-not (string-match-p "#\\+END_SRC" result))))

(ert-deftest package-audit-remediate-test-stub-formatting ()
  "Test use-package stub indentation and formatting."
  (let* ((packages '(magit))
         (result (package-audit--use-package-stub-elisp packages)))
    ;; Verify proper indentation
    (should (string-match-p "(use-package magit\n  :ensure t)" result))))

(ert-deftest package-audit-remediate-test-review-heading ()
  "Test review heading generation."
  (let* ((result (package-audit--review-heading-line 1 "Review stubs")))
    (should (string-prefix-p "* " result))
    (should (string-match-p "Review stubs" result)))
  (let* ((result (package-audit--review-heading-line 2 "Subsection")))
    (should (string-prefix-p "** " result))))

;; ---------------------------------------------------------------------------
;; Section finding tests

(ert-deftest package-audit-remediate-test-find-org-review-section ()
  "Test finding existing org review section."
  (with-temp-buffer
    (insert "* Some heading\n")
    (insert "Content here\n")
    (insert "* " package-audit-review-heading "\n")
    (insert "Existing stubs\n")
    (insert "* Another heading\n")
    (let ((pos (package-audit--find-review-section-end)))
      (should pos)
      ;; Should point to start of "* Another heading"
      (should (= pos (- (point-max) (length "* Another heading\n")))))))

(ert-deftest package-audit-remediate-test-find-org-review-section-at-end ()
  "Test finding org review section when it's the last section."
  (with-temp-buffer
    (insert "* Some heading\n")
    (insert "* " package-audit-review-heading "\n")
    (insert "Existing stubs\n")
    (let ((pos (package-audit--find-review-section-end)))
      (should pos)
      ;; Should point to point-max
      (should (= pos (point-max))))))

(ert-deftest package-audit-remediate-test-find-org-review-section-none ()
  "Test finding org review section when none exists."
  (with-temp-buffer
    (insert "* Some heading\n")
    (insert "Content\n")
    (let ((pos (package-audit--find-review-section-end)))
      (should-not pos))))

(ert-deftest package-audit-remediate-test-find-el-review-section ()
  "Test finding existing elisp review section."
  (with-temp-buffer
    (insert ";;; Some comment\n")
    (insert "(setq foo 'bar)\n")
    (insert ";;; " package-audit-review-heading "\n")
    (insert ";; Existing stubs\n")
    (insert ";;; Another Section\n")
    (let ((pos (package-audit--find-el-review-section-end)))
      (should pos))))

(ert-deftest package-audit-remediate-test-find-el-review-section-none ()
  "Test finding elisp review section when none exists."
  (with-temp-buffer
    (insert ";;; Some comment\n")
    (insert "(setq foo 'bar)\n")
    (let ((pos (package-audit--find-el-review-section-end)))
      (should-not pos))))

;; ---------------------------------------------------------------------------
;; Helper function tests

(ert-deftest package-audit-remediate-test-format-package-list ()
  "Test package list formatting for display."
  (let* ((packages '(magit company flycheck))
         (result (package-audit--format-package-list packages)))
    (should (string-match-p "magit" result))
    (should (string-match-p "company" result))
    (should (string-match-p "flycheck" result))
    (should (string-match-p ", " result))))

(ert-deftest package-audit-remediate-test-state-symbol-list ()
  "Test extracting symbol list from state."
  (let* ((state '(:selected (magit company) :installed (magit company dash)))
         (selected (package-audit--state-symbol-list state :selected)))
    (should (equal selected '(magit company)))))

;; ---------------------------------------------------------------------------
;; Custom file operations tests

(ert-deftest package-audit-remediate-test-write-selected-packages-calls-customize ()
  "Test that write-selected-packages calls customize-save-variable."
  (package-audit-test-with-temp-repo ()
    (let* ((custom-file (package-audit-test-create-custom-file '(magit) nil temp-dir))
           (selected '(magit company))
           (called-with nil))
      ;; Mock customize-save-variable to capture call
      (cl-letf (((symbol-function 'customize-save-variable)
                 (lambda (symbol value)
                   (setq called-with (list symbol value)))))
        (package-audit--write-selected-packages temp-dir selected)
        ;; Verify customize-save-variable was called correctly
        (should (equal (car called-with) 'package-selected-packages))
        (should (equal (cadr called-with) '(magit company)))))))

(ert-deftest package-audit-remediate-test-write-selected-packages-with-existing ()
  "Test write-selected-packages with existing custom file."
  (package-audit-test-with-temp-repo ()
    (let* ((custom-file (package-audit-test-create-custom-file '(magit) nil temp-dir))
           (updated '(magit company flycheck))
           saved-value)
      ;; Mock customize-save-variable to capture the save
      (cl-letf (((symbol-function 'customize-save-variable)
                 (lambda (symbol value)
                   (setq saved-value value))))
        (package-audit--write-selected-packages temp-dir updated)
        ;; Verify the new value was passed to customize-save-variable
        (should (equal saved-value '(magit company flycheck)))))))

(ert-deftest package-audit-remediate-test-write-selected-packages-empty-list ()
  "Test write-selected-packages with empty package list."
  (package-audit-test-with-temp-repo ()
    (let* ((custom-file (package-audit-test-create-custom-file '(magit company) nil temp-dir))
           (empty '())
           saved-value)
      ;; Mock customize-save-variable
      (cl-letf (((symbol-function 'customize-save-variable)
                 (lambda (symbol value)
                   (setq saved-value value))))
        (package-audit--write-selected-packages temp-dir empty)
        ;; Verify empty list was saved
        (should (equal saved-value '()))))))

;; ---------------------------------------------------------------------------
;; Stub insertion tests

(ert-deftest package-audit-remediate-test-insert-stubs-org-new-section ()
  "Test inserting stubs into org file without existing review section."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-org-init init-forms temp-dir))
           (packages '(company flycheck)))
      (package-audit--insert-use-package-stubs-org temp-dir packages)
      ;; Verify file was modified
      (with-temp-buffer
        (insert-file-contents init-file)
        (let ((content (buffer-string)))
          ;; Verify review heading added
          (should (string-match-p (regexp-quote package-audit-review-heading) content))
          ;; Verify stubs added
          (should (string-match-p "(use-package company" content))
          (should (string-match-p "(use-package flycheck" content))
          ;; Verify org block structure
          (should (string-match-p "#\\+BEGIN_SRC emacs-lisp" content))
          (should (string-match-p "#\\+END_SRC" content)))))))

(ert-deftest package-audit-remediate-test-insert-stubs-el-new-section ()
  "Test inserting stubs into elisp file without existing review section."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (packages '(company flycheck)))
      (package-audit--insert-use-package-stubs-el temp-dir packages)
      ;; Verify file was modified
      (with-temp-buffer
        (insert-file-contents init-file)
        (let ((content (buffer-string)))
          ;; Verify review heading added
          (should (string-match-p (regexp-quote package-audit-review-heading) content))
          ;; Verify stubs added
          (should (string-match-p "(use-package company" content))
          (should (string-match-p "(use-package flycheck" content))
          ;; Verify no org block markers
          (should-not (string-match-p "#\\+BEGIN_SRC" content)))))))

(ert-deftest package-audit-remediate-test-insert-stubs-preserves-existing ()
  "Test that inserting stubs preserves existing file content."
  (package-audit-test-with-temp-repo ()
    (let* ((init-forms (list "(use-package magit\n  :ensure t)"
                             "(setq user-full-name \"Test User\")"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (packages '(company)))
      (package-audit--insert-use-package-stubs-el temp-dir packages)
      ;; Verify existing content preserved
      (with-temp-buffer
        (insert-file-contents init-file)
        (let ((content (buffer-string)))
          (should (string-match-p "(use-package magit" content))
          (should (string-match-p "user-full-name" content))
          (should (string-match-p "(use-package company" content)))))))

;; ---------------------------------------------------------------------------
;; Package deletion tests

(ert-deftest package-audit-remediate-test-delete-stale-directory-safety ()
  "Test that protected directories cannot be deleted."
  (package-audit-test-with-temp-repo ()
    ;; Trying to delete "archives" should error
    (should-error (package-audit--delete-stale-directory temp-dir "archives")
                  :type 'user-error)
    ;; Trying to delete "gnupg" should error
    (should-error (package-audit--delete-stale-directory temp-dir "gnupg")
                  :type 'user-error)))

(ert-deftest package-audit-remediate-test-delete-stale-directory-success ()
  "Test successful deletion of ignored directory."
  (package-audit-test-with-temp-repo ()
    (let* ((elpa-dir (package-audit-test-create-elpa-directory temp-dir '()))
           (stale-dir (expand-file-name "old-junk" elpa-dir))
           (package-audit-package-install-directory elpa-dir))
      ;; Create a stale directory
      (make-directory stale-dir t)
      (should (file-directory-p stale-dir))
      ;; Delete it
      (package-audit--delete-stale-directory temp-dir "old-junk")
      ;; Verify it's gone
      (should-not (file-exists-p stale-dir)))))

(ert-deftest package-audit-remediate-test-delete-package-mock ()
  "Test package deletion calls package.el correctly."
  (package-audit-test-with-temp-repo ()
    (let* ((elpa-dir (package-audit-test-create-elpa-directory
                      temp-dir
                      '((old-theme "1.0.0" nil))))
           (deleted-package nil))
      ;; Mock package-delete to capture the call
      (cl-letf (((symbol-function 'package-delete)
                 (lambda (desc &optional _force)
                   (setq deleted-package (package-desc-name desc)))))
        (let ((package-audit-package-install-directory elpa-dir))
          (package-audit--delete-package temp-dir 'old-theme)
          ;; Verify package-delete was called with correct package
          (should (eq deleted-package 'old-theme)))))))

(ert-deftest package-audit-remediate-test-delete-package-not-installed ()
  "Test error when trying to delete non-installed package."
  (package-audit-test-with-temp-repo ()
    (let* ((elpa-dir (package-audit-test-create-elpa-directory temp-dir '()))
           (package-audit-package-install-directory elpa-dir))
      ;; Trying to delete non-existent package should error
      (should-error (package-audit--delete-package temp-dir 'nonexistent)
                    :type 'user-error))))

;; ---------------------------------------------------------------------------
;; Interactive command tests

(ert-deftest package-audit-remediate-test-add-selected-packages-flow ()
  "Test add-selected-packages remediation command flow."
  (package-audit-test-with-temp-repo ()
    (let* ((init-packages '(magit company))
           (selected-packages '(company))  ;; magit missing from selections
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file selected-packages nil temp-dir))
           (saved-value nil))
      ;; Mock customize-save-variable, y-or-n-p, yes-or-no-p, message, and pop-to-buffer
      (cl-letf (((symbol-function 'customize-save-variable)
                 (lambda (symbol value)
                   (setq saved-value value)))
                ((symbol-function 'y-or-n-p)
                 (lambda (_prompt) t))
                ((symbol-function 'yes-or-no-p)
                 (lambda (_prompt) t))
                ((symbol-function 'message)
                 (lambda (&rest _args) nil))
                ((symbol-function 'pop-to-buffer)
                 (lambda (_buffer) nil)))
        (let ((package-audit-custom-state-file custom-file))
          (package-audit-remediate-add-selected-packages temp-dir)
          ;; Verify magit was added to saved selections
          (should (member 'magit saved-value))
          (should (member 'company saved-value)))))))

(ert-deftest package-audit-remediate-test-add-stubs-flow ()
  "Test add-use-package-stubs remediation command flow."
  (package-audit-test-with-temp-repo ()
    (let* ((init-packages '(magit))
           (selected-packages '(magit company))  ;; company missing from init
           (init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file selected-packages nil temp-dir)))
      ;; Mock y-or-n-p, yes-or-no-p, message, and pop-to-buffer
      (cl-letf (((symbol-function 'y-or-n-p)
                 (lambda (_prompt) t))
                ((symbol-function 'yes-or-no-p)
                 (lambda (_prompt) t))
                ((symbol-function 'message)
                 (lambda (&rest _args) nil))
                ((symbol-function 'pop-to-buffer)
                 (lambda (_buffer) nil)))
        (let ((package-audit-custom-state-file custom-file))
          (package-audit-remediate-add-use-package-stubs temp-dir)
          ;; Verify company stub was added to init file
          (with-temp-buffer
            (insert-file-contents init-file)
            (let ((content (buffer-string)))
              (should (string-match-p "(use-package company" content))
              (should (string-match-p (regexp-quote package-audit-review-heading) content)))))))))

(provide 'package-audit-remediate-test)
;;; package-audit-remediate-test.el ends here
