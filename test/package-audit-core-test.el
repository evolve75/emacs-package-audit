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

(provide 'package-audit-core-test)
;;; package-audit-core-test.el ends here
