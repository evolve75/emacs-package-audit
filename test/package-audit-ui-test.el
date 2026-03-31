;;; package-audit-ui-test.el --- Tests for package-audit-ui -*- lexical-binding: t; -*-

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

;; Tests for package-audit-ui.el interactive commands and entry points.

;;; Code:

(require 'ert)
(require 'package-audit-test)
(require 'package-audit-core)
(require 'package-audit-ui)

;; ---------------------------------------------------------------------------
;; Entry point tests

(ert-deftest package-audit-ui-test-show-operations-no-hydra ()
  "Test show-operations without Hydra loaded."
  (let ((hydra-available (featurep 'hydra)))
    (when hydra-available
      ;; Unload hydra temporarily for this test
      (unload-feature 'hydra t))
    (unwind-protect
        (let ((message-log-max nil)
              (inhibit-message t)
              captured-message)
          ;; Capture message output
          (cl-letf (((symbol-function 'message)
                     (lambda (format-string &rest args)
                       (setq captured-message (apply #'format format-string args)))))
            (package-audit-show-operations)
            ;; Verify fallback message is shown
            (should (stringp captured-message))
            (should (string-match-p "Hydra is unavailable" captured-message))
            (should (string-match-p "package-audit-refresh" captured-message))))
      ;; Reload hydra if it was available
      (when hydra-available
        (require 'hydra nil t)))))

(ert-deftest package-audit-ui-test-run-generates-reports ()
  "Test that package-audit-run generates reports."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit company))
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (reports-dir (expand-file-name "reports" temp-dir))
           (package-audit-custom-state-file custom-file)
           (package-audit-report-directory reports-dir)
           (inhibit-message t))
      ;; Mock show-operations to avoid interactive menu
      (cl-letf (((symbol-function 'package-audit-show-operations)
                 (lambda () nil)))
        (package-audit-run temp-dir reports-dir)
        ;; Verify reports were created
        (should (file-exists-p (expand-file-name "package-audit.json" reports-dir)))
        (should (file-exists-p (expand-file-name "package-audit.md" reports-dir)))))))

(ert-deftest package-audit-ui-test-refresh-regenerates-reports ()
  "Test that package-audit-refresh regenerates reports."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit company))
           (init-forms (list "(use-package magit\n  :ensure t)"
                             "(use-package company\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (reports-dir (expand-file-name "reports" temp-dir))
           (package-audit-custom-state-file custom-file)
           (package-audit-report-directory reports-dir)
           (inhibit-message t))
      ;; Mock show-operations and yes-or-no-p (for file reread prompt)
      (cl-letf (((symbol-function 'package-audit-show-operations)
                 (lambda () nil))
                ((symbol-function 'yes-or-no-p)
                 (lambda (_prompt) t)))
        ;; First run
        (package-audit-run temp-dir reports-dir)
        (should (file-exists-p (expand-file-name "package-audit.json" reports-dir)))
        ;; Refresh (mocked yes-or-no-p prevents stdin blocking)
        (package-audit-refresh temp-dir reports-dir)
        ;; Verify reports still exist after refresh
        (should (file-exists-p (expand-file-name "package-audit.json" reports-dir)))
        (should (file-exists-p (expand-file-name "package-audit.md" reports-dir)))))))

(ert-deftest package-audit-ui-test-open-markdown-report ()
  "Test opening markdown report caches path correctly."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit))
           (init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (reports-dir (expand-file-name "reports" temp-dir))
           (package-audit-custom-state-file custom-file)
           (package-audit-report-directory reports-dir)
           (inhibit-message t)
           (opened-file nil))
      ;; Generate reports first
      (cl-letf (((symbol-function 'package-audit-show-operations)
                 (lambda () nil)))
        (package-audit-run temp-dir reports-dir))
      ;; Mock pop-to-buffer to capture the opened file
      (cl-letf (((symbol-function 'pop-to-buffer)
                 (lambda (buffer)
                   (when (bufferp buffer)
                     (setq opened-file (buffer-file-name buffer))))))
        (package-audit-open-markdown-report)
        ;; Verify markdown report path was cached and used
        (should (stringp opened-file))
        (should (string-suffix-p "package-audit.md" opened-file))
        (should (file-exists-p opened-file))))))

(ert-deftest package-audit-ui-test-open-json-report ()
  "Test opening JSON report caches path correctly."
  (package-audit-test-with-temp-repo ()
    (let* ((packages '(magit))
           (init-forms (list "(use-package magit\n  :ensure t)"))
           (init-file (package-audit-test-create-el-init init-forms temp-dir))
           (custom-file (package-audit-test-create-custom-file packages nil temp-dir))
           (reports-dir (expand-file-name "reports" temp-dir))
           (package-audit-custom-state-file custom-file)
           (package-audit-report-directory reports-dir)
           (inhibit-message t)
           (opened-file nil))
      ;; Generate reports first
      (cl-letf (((symbol-function 'package-audit-show-operations)
                 (lambda () nil)))
        (package-audit-run temp-dir reports-dir))
      ;; Mock pop-to-buffer to capture the opened file
      (cl-letf (((symbol-function 'pop-to-buffer)
                 (lambda (buffer)
                   (when (bufferp buffer)
                     (setq opened-file (buffer-file-name buffer))))))
        (package-audit-open-json-report)
        ;; Verify JSON report path was cached and used
        (should (stringp opened-file))
        (should (string-suffix-p "package-audit.json" opened-file))
        (should (file-exists-p opened-file))))))

(ert-deftest package-audit-ui-test-open-report-error-when-none ()
  "Test error when trying to open report that doesn't exist."
  (let ((package-audit--last-report-files nil))
    (should-error (package-audit-open-markdown-report)
                  :type 'user-error)
    (should-error (package-audit-open-json-report)
                  :type 'user-error)))

(provide 'package-audit-ui-test)
;;; package-audit-ui-test.el ends here
