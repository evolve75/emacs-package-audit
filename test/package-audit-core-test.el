;;; package-audit-core-test.el --- Tests for package-audit-core -*- lexical-binding: t; -*-

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

;; Tests for package-audit-core.el set operations and state building.

;;; Code:

(require 'ert)
(require 'package-audit-test)
(require 'package-audit-core)

;; ---------------------------------------------------------------------------
;; Symbol list normalization tests

(ert-deftest package-audit-core-test-normalize-symbol-list ()
  "Test symbol list normalization: dedup, sort, symbols-only."
  (let ((input '(magit company magit flycheck company))
        (expected '(company flycheck magit)))
    (should (equal (package-audit--normalize-symbol-list input) expected))))

(ert-deftest package-audit-core-test-normalize-empty ()
  "Test normalization of empty list."
  (should (equal (package-audit--normalize-symbol-list '()) '()))
  (should (equal (package-audit--normalize-symbol-list nil) '())))

(ert-deftest package-audit-core-test-normalize-mixed-types ()
  "Test normalization filters out non-symbols."
  (let ((input '(magit "company" flycheck 42))
        (expected '(flycheck magit)))
    (should (equal (package-audit--normalize-symbol-list input) expected))))

(ert-deftest package-audit-core-test-normalize-sorting ()
  "Test normalization sorts alphabetically."
  (let ((input '(zzz aaa mmm bbb))
        (expected '(aaa bbb mmm zzz)))
    (should (equal (package-audit--normalize-symbol-list input) expected))))

;; ---------------------------------------------------------------------------
;; Symbol union tests

(ert-deftest package-audit-core-test-symbol-union ()
  "Test union of two symbol lists."
  (let ((left '(magit company))
        (right '(flycheck company))
        (expected '(company flycheck magit)))
    (should (equal (package-audit--symbol-union left right) expected))))

(ert-deftest package-audit-core-test-symbol-union-empty ()
  "Test union with empty sets."
  (let ((left '(magit company))
        (empty '()))
    (should (equal (package-audit--symbol-union left empty) '(company magit)))
    (should (equal (package-audit--symbol-union empty left) '(company magit)))
    (should (equal (package-audit--symbol-union empty empty) '()))))

(ert-deftest package-audit-core-test-symbol-union-overlap ()
  "Test union with overlapping elements."
  (let ((left '(magit company flycheck))
        (right '(company flycheck which-key))
        (expected '(company flycheck magit which-key)))
    (should (equal (package-audit--symbol-union left right) expected))))

(ert-deftest package-audit-core-test-symbol-union-identical ()
  "Test union of identical sets."
  (let ((set '(magit company flycheck)))
    (should (equal (package-audit--symbol-union set set) '(company flycheck magit)))))

;; ---------------------------------------------------------------------------
;; Symbol difference tests

(ert-deftest package-audit-core-test-symbol-difference ()
  "Test difference (left minus right)."
  (let ((left '(magit company flycheck))
        (right '(company which-key))
        (expected '(flycheck magit)))
    (should (equal (package-audit--symbol-difference left right) expected))))

(ert-deftest package-audit-core-test-symbol-difference-empty ()
  "Test difference with empty sets."
  (let ((left '(magit company))
        (empty '()))
    (should (equal (package-audit--symbol-difference left empty) '(company magit)))
    (should (equal (package-audit--symbol-difference empty left) '()))
    (should (equal (package-audit--symbol-difference empty empty) '()))))

(ert-deftest package-audit-core-test-symbol-difference-no-overlap ()
  "Test difference with disjoint sets."
  (let ((left '(magit company))
        (right '(flycheck which-key))
        (expected '(company magit)))
    (should (equal (package-audit--symbol-difference left right) expected))))

(ert-deftest package-audit-core-test-symbol-difference-identical ()
  "Test difference of identical sets results in empty set."
  (let ((set '(magit company flycheck)))
    (should (equal (package-audit--symbol-difference set set) '()))))

(ert-deftest package-audit-core-test-symbol-difference-subset ()
  "Test difference when left is subset of right."
  (let ((left '(magit company))
        (right '(magit company flycheck)))
    (should (equal (package-audit--symbol-difference left right) '()))))

;; ---------------------------------------------------------------------------
;; Symbol intersection tests

(ert-deftest package-audit-core-test-symbol-intersection ()
  "Test intersection of two symbol lists."
  (let ((left '(magit company flycheck))
        (right '(company flycheck which-key))
        (expected '(company flycheck)))
    (should (equal (package-audit--symbol-intersection left right) expected))))

(ert-deftest package-audit-core-test-symbol-intersection-empty ()
  "Test intersection with empty sets."
  (let ((left '(magit company))
        (empty '()))
    (should (equal (package-audit--symbol-intersection left empty) '()))
    (should (equal (package-audit--symbol-intersection empty left) '()))
    (should (equal (package-audit--symbol-intersection empty empty) '()))))

(ert-deftest package-audit-core-test-symbol-intersection-disjoint ()
  "Test intersection of disjoint sets."
  (let ((left '(magit company))
        (right '(flycheck which-key)))
    (should (equal (package-audit--symbol-intersection left right) '()))))

(ert-deftest package-audit-core-test-symbol-intersection-identical ()
  "Test intersection of identical sets."
  (let ((set '(magit company flycheck)))
    (should (equal (package-audit--symbol-intersection set set)
                   '(company flycheck magit)))))

(ert-deftest package-audit-core-test-symbol-intersection-subset ()
  "Test intersection when one is subset of other."
  (let ((left '(magit company))
        (right '(magit company flycheck)))
    (should (equal (package-audit--symbol-intersection left right)
                   '(company magit)))))

;; ---------------------------------------------------------------------------
;; Custom state reading tests

(ert-deftest package-audit-core-test-read-custom-state-with-file ()
  "Test reading custom state from existing custom.el."
  (package-audit-test-with-temp-repo ()
    (let* ((selected-packages '(magit company flycheck))
           (custom-file (package-audit-test-create-custom-file selected-packages nil temp-dir))
           (state (package-audit--read-custom-state custom-file)))
      (should (equal (plist-get state :selected) '(company flycheck magit)))
      (should (equal (plist-get state :variables) '())))))

(ert-deftest package-audit-core-test-read-custom-state-no-file ()
  "Test fallback to live package-selected-packages variable."
  (package-audit-test-with-temp-repo ()
    (let* ((nonexistent-file (expand-file-name "nonexistent.el" temp-dir))
           (package-selected-packages '(magit company))
           (state (package-audit--read-custom-state nonexistent-file)))
      (should (equal (plist-get state :selected) '(company magit)))
      (should (equal (plist-get state :variables) '())))))

(ert-deftest package-audit-core-test-read-custom-state-empty-file ()
  "Test reading custom file with no package-selected-packages."
  (package-audit-test-with-temp-repo ()
    (let* ((custom-file (package-audit-test-create-custom-file nil nil temp-dir))
           (state (package-audit--read-custom-state custom-file)))
      (should (equal (plist-get state :selected) '()))
      (should (equal (plist-get state :variables) '())))))

(ert-deftest package-audit-core-test-read-custom-variables ()
  "Test extraction of customize variables."
  (package-audit-test-with-temp-repo ()
    (let* ((selected-packages '(magit company))
           (variables '((magit-display-buffer-function . magit-display-buffer-fullframe-status-v1)
                        (company-idle-delay . 0.2)))
           (custom-file (package-audit-test-create-custom-file selected-packages variables temp-dir))
           (state (package-audit--read-custom-state custom-file)))
      (should (equal (plist-get state :selected) '(company magit)))
      (package-audit-test-assert-symbol-list-equal
       '(company-idle-delay magit-display-buffer-function)
       (plist-get state :variables)))))

(ert-deftest package-audit-core-test-read-custom-mixed ()
  "Test custom file with both selections and variables."
  (package-audit-test-with-temp-repo ()
    (let* ((selected-packages '(flycheck which-key rainbow-delimiters))
           (variables '((flycheck-disabled-checkers . '(emacs-lisp-checkdoc))
                        (which-key-idle-delay . 0.5)
                        (rainbow-delimiters-max-face-count . 9)))
           (custom-file (package-audit-test-create-custom-file selected-packages variables temp-dir))
           (state (package-audit--read-custom-state custom-file)))
      (should (equal (plist-get state :selected) '(flycheck rainbow-delimiters which-key)))
      (package-audit-test-assert-symbol-list-equal
       '(flycheck-disabled-checkers rainbow-delimiters-max-face-count which-key-idle-delay)
       (plist-get state :variables)))))

;; ---------------------------------------------------------------------------
;; Dependency closure tests

(ert-deftest package-audit-core-test-dependency-closure-simple ()
  "Test closure with simple linear chain: A → B → C."
  (let* ((roots '(pkg-a))
         (deps '((pkg-a pkg-b)
                 (pkg-b pkg-c)
                 (pkg-c)))
         (result (package-audit--dependency-closure roots deps))
         (closure (plist-get result :closure))
         (reasons (plist-get result :reasons)))
    (should (equal closure '(pkg-a pkg-b pkg-c)))
    (should (equal reasons '((pkg-b . pkg-a) (pkg-c . pkg-b))))))

(ert-deftest package-audit-core-test-dependency-closure-branching ()
  "Test closure with branching: A → B, A → C."
  (let* ((roots '(pkg-a))
         (deps '((pkg-a pkg-b pkg-c)
                 (pkg-b)
                 (pkg-c)))
         (result (package-audit--dependency-closure roots deps))
         (closure (plist-get result :closure))
         (reasons (plist-get result :reasons)))
    (should (equal closure '(pkg-a pkg-b pkg-c)))
    (should (equal reasons '((pkg-b . pkg-a) (pkg-c . pkg-a))))))

(ert-deftest package-audit-core-test-dependency-closure-diamond ()
  "Test closure with diamond: A → B, A → C, B → D, C → D."
  (let* ((roots '(pkg-a))
         (deps '((pkg-a pkg-b pkg-c)
                 (pkg-b pkg-d)
                 (pkg-c pkg-d)
                 (pkg-d)))
         (result (package-audit--dependency-closure roots deps))
         (closure (plist-get result :closure))
         (reasons (plist-get result :reasons)))
    (should (equal closure '(pkg-a pkg-b pkg-c pkg-d)))
    ;; pkg-d should be attributed to whichever of pkg-b or pkg-c was processed first
    (should (= (length reasons) 3))))

(ert-deftest package-audit-core-test-dependency-closure-empty ()
  "Test closure with no dependencies."
  (let* ((roots '(pkg-a pkg-b))
         (deps '((pkg-a)
                 (pkg-b)))
         (result (package-audit--dependency-closure roots deps))
         (closure (plist-get result :closure))
         (reasons (plist-get result :reasons)))
    (should (equal closure '(pkg-a pkg-b)))
    (should (equal reasons '()))))

(ert-deftest package-audit-core-test-dependency-closure-reasons ()
  "Test that dependency reasons are tracked correctly."
  (let* ((roots '(pkg-a pkg-b))
         (deps '((pkg-a pkg-x pkg-y)
                 (pkg-b pkg-z)
                 (pkg-x)
                 (pkg-y)
                 (pkg-z)))
         (result (package-audit--dependency-closure roots deps))
         (closure (plist-get result :closure))
         (reasons (plist-get result :reasons)))
    (should (equal closure '(pkg-a pkg-b pkg-x pkg-y pkg-z)))
    ;; Verify each dependency has a reason
    (should (assq 'pkg-x reasons))
    (should (assq 'pkg-y reasons))
    (should (assq 'pkg-z reasons))
    ;; Verify reasons point to roots
    (should (eq (alist-get 'pkg-x reasons) 'pkg-a))
    (should (eq (alist-get 'pkg-y reasons) 'pkg-a))
    (should (eq (alist-get 'pkg-z reasons) 'pkg-b))))

(ert-deftest package-audit-core-test-dependency-closure-complex ()
  "Test closure with complex multi-level dependencies."
  (let* ((roots '(magit))
         (deps '((magit dash git-commit magit-section transient with-editor)
                 (git-commit with-editor)
                 (with-editor compat)
                 (magit-section dash)
                 (transient compat)
                 (dash)
                 (compat)))
         (result (package-audit--dependency-closure roots deps))
         (closure (plist-get result :closure)))
    (should (equal closure '(compat dash git-commit magit magit-section transient with-editor)))))

(provide 'package-audit-core-test)
;;; package-audit-core-test.el ends here
