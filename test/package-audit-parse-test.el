;;; package-audit-parse-test.el --- Tests for package-audit-parse -*- lexical-binding: t; -*-

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

;; Tests for package-audit-parse.el init file parsing and detection.

;;; Code:

(require 'ert)
(require 'package-audit-test)
(require 'package-audit-core)  ; Provides functions used by package-audit-parse
(require 'package-audit-parse)

;; ---------------------------------------------------------------------------
;; Init source file detection tests

(ert-deftest package-audit-parse-test-detect-init-org ()
  "Test detection of init.org when present."
  (package-audit-test-with-temp-repo ()
    (package-audit-test-create-init-file 'org "* Test\n" temp-dir)
    (should (equal (package-audit--detect-init-source-file temp-dir) "init.org"))))

(ert-deftest package-audit-parse-test-detect-init-el ()
  "Test detection of init.el when init.org absent."
  (package-audit-test-with-temp-repo ()
    (package-audit-test-create-init-file 'el ";; Test\n" temp-dir)
    (should (equal (package-audit--detect-init-source-file temp-dir) "init.el"))))

(ert-deftest package-audit-parse-test-prefer-init-org ()
  "Test that init.org is preferred when both files exist."
  (package-audit-test-with-temp-repo ()
    (package-audit-test-create-init-file 'org "* Test\n" temp-dir)
    (package-audit-test-create-init-file 'el ";; Test\n" temp-dir)
    (should (equal (package-audit--detect-init-source-file temp-dir) "init.org"))))

(ert-deftest package-audit-parse-test-detect-none ()
  "Test nil return when no init source found."
  (package-audit-test-with-temp-repo ()
    (should (null (package-audit--detect-init-source-file temp-dir)))))

(ert-deftest package-audit-parse-test-elisp-detection ()
  "Test elisp file format detection (.el, .emacs)."
  (should (package-audit--init-source-is-elisp-p "init.el"))
  (should (package-audit--init-source-is-elisp-p "config.el"))
  (should (package-audit--init-source-is-elisp-p ".emacs"))
  (should-not (package-audit--init-source-is-elisp-p "init.org"))
  (should-not (package-audit--init-source-is-elisp-p "README.md")))

;; ---------------------------------------------------------------------------
;; use-package parsing logic tests

(ert-deftest package-audit-parse-test-ensure-t ()
  "Test use-package with :ensure t extracts package name."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(magit))))))

(ert-deftest package-audit-parse-test-ensure-nil ()
  "Test use-package with :ensure nil returns nil."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package org\n  :ensure nil)"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '())))))

(ert-deftest package-audit-parse-test-ensure-symbol ()
  "Test use-package with :ensure symbol (e.g., tex → auctex)."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package tex\n  :ensure auctex)"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(auctex))))))

(ert-deftest package-audit-parse-test-vc ()
  "Test use-package with :vc extracts package name."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package some-package\n  :vc t)"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(some-package))))))

(ert-deftest package-audit-parse-test-load-path ()
  "Test use-package with :load-path returns nil (repo-local)."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package my-package\n  :load-path \"lisp/\")"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '())))))

(ert-deftest package-audit-parse-test-nested-forms ()
  "Test parsing nested use-package forms."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(progn\n  (use-package magit\n    :ensure t)\n  (use-package company\n    :ensure t))"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(company magit))))))

(ert-deftest package-audit-parse-test-multiple-packages ()
  "Test parsing file with multiple use-package declarations."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package magit\n  :ensure t)"
                    "(use-package company\n  :ensure t)"
                    "(use-package flycheck\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(company flycheck magit))))))

(ert-deftest package-audit-parse-test-mixed-ensure ()
  "Test parsing file with mixed :ensure values."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package magit\n  :ensure t)"
                    "(use-package org\n  :ensure nil)"
                    "(use-package tex\n  :ensure auctex)"
                    "(use-package local-pkg\n  :load-path \"lisp/\")"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(auctex magit))))))

;; ---------------------------------------------------------------------------
;; Org format parsing tests

(ert-deftest package-audit-parse-test-org-single-block ()
  "Test parsing init.org with single emacs-lisp block."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-org-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(magit))))))

(ert-deftest package-audit-parse-test-org-multiple-blocks ()
  "Test parsing init.org with multiple src blocks."
  (package-audit-test-with-temp-repo ()
    (let ((content "* Package Configuration\n\n** Development\n\n#+BEGIN_SRC emacs-lisp\n(use-package magit\n  :ensure t)\n#+END_SRC\n\n** Editing\n\n#+BEGIN_SRC emacs-lisp\n(use-package company\n  :ensure t)\n#+END_SRC\n"))
      (let* ((init-file (package-audit-test-create-init-file 'org content temp-dir))
             (roots (package-audit--explicit-init-roots init-file temp-dir)))
        (should (equal roots '(company magit)))))))

(ert-deftest package-audit-parse-test-org-non-elisp-blocks ()
  "Test that non-emacs-lisp blocks are ignored."
  (package-audit-test-with-temp-repo ()
    (let ((content "* Configuration\n\n#+BEGIN_SRC emacs-lisp\n(use-package magit\n  :ensure t)\n#+END_SRC\n\n#+BEGIN_SRC shell\necho 'test'\n#+END_SRC\n\n#+BEGIN_SRC emacs-lisp\n(use-package company\n  :ensure t)\n#+END_SRC\n"))
      (let* ((init-file (package-audit-test-create-init-file 'org content temp-dir))
             (roots (package-audit--explicit-init-roots init-file temp-dir)))
        (should (equal roots '(company magit)))))))

(ert-deftest package-audit-parse-test-org-mixed-blocks ()
  "Test org file with mixed elisp and other language blocks."
  (package-audit-test-with-temp-repo ()
    (let ((content "* Packages\n\n#+BEGIN_SRC emacs-lisp\n(use-package flycheck\n  :ensure t)\n#+END_SRC\n\n#+BEGIN_SRC python\nprint('hello')\n#+END_SRC\n\n#+BEGIN_SRC emacs-lisp\n(use-package which-key\n  :ensure t)\n#+END_SRC\n"))
      (let* ((init-file (package-audit-test-create-init-file 'org content temp-dir))
             (roots (package-audit--explicit-init-roots init-file temp-dir)))
        (should (equal roots '(flycheck which-key)))))))

;; ---------------------------------------------------------------------------
;; Elisp format parsing tests

(ert-deftest package-audit-parse-test-el-simple ()
  "Test parsing init.el with simple use-package forms."
  (package-audit-test-with-temp-repo ()
    (let* ((forms '("(use-package magit\n  :ensure t)"
                    "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init forms temp-dir))
           (roots (package-audit--explicit-init-roots init-file temp-dir)))
      (should (equal roots '(company magit))))))

(ert-deftest package-audit-parse-test-el-with-comments ()
  "Test that comments in init.el don't affect parsing."
  (package-audit-test-with-temp-repo ()
    (let ((content ";;; init.el --- Test init file\n\n;; Package configuration\n(use-package magit\n  :ensure t)\n\n;; More packages\n(use-package company\n  :ensure t)\n"))
      (let* ((init-file (package-audit-test-create-init-file 'el content temp-dir))
             (roots (package-audit--explicit-init-roots init-file temp-dir)))
        (should (equal roots '(company magit)))))))

(ert-deftest package-audit-parse-test-el-nested-progn ()
  "Test parsing use-package inside progn/let forms."
  (package-audit-test-with-temp-repo ()
    (let ((content ";;; init.el\n\n(progn\n  (use-package magit\n    :ensure t)\n  (let ((x 1))\n    (use-package company\n      :ensure t)))\n"))
      (let* ((init-file (package-audit-test-create-init-file 'el content temp-dir))
             (roots (package-audit--explicit-init-roots init-file temp-dir)))
        (should (equal roots '(company magit)))))))

(ert-deftest package-audit-parse-test-el-with-config ()
  "Test parsing use-package with configuration blocks."
  (package-audit-test-with-temp-repo ()
    (let ((content ";;; init.el\n\n(use-package magit\n  :ensure t\n  :bind ((\"C-x g\" . magit-status))\n  :config\n  (setq magit-display-buffer-function\n        #'magit-display-buffer-fullframe-status-v1))\n\n(use-package company\n  :ensure t\n  :hook (prog-mode . company-mode))\n"))
      (let* ((init-file (package-audit-test-create-init-file 'el content temp-dir))
             (roots (package-audit--explicit-init-roots init-file temp-dir)))
        (should (equal roots '(company magit)))))))

(provide 'package-audit-parse-test)
;;; package-audit-parse-test.el ends here
