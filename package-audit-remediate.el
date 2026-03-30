;;; package-audit-remediate.el --- Remediation commands for package-audit -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Anupam Sengupta

;; Author: Anupam Sengupta <anupamsg@gmail.com>
;; Keywords: convenience, tools, maint
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Prompted remediation helpers driven by the current package audit state.

;;; Code:

(require 'package-audit-core)
(require 'package-audit-parse)
(require 'package-audit-report)

;; ---------------------------------------------------------------------------
;; Shared remediation helpers

(defun package-audit--state-symbol-list (state key)
  "Return symbol list stored at KEY in raw audit STATE."
  (copy-sequence (plist-get state key)))

(defun package-audit--format-package-list (packages)
  "Return PACKAGES formatted for prompts and messages."
  (mapconcat #'symbol-name packages ", "))

(defun package-audit--write-selected-packages (repo-root selected)
  "Persist SELECTED package roots to the custom state file for REPO-ROOT."
  (let ((custom-file (package-audit--custom-state-path repo-root))
        (package-selected-packages selected))
    ;; Rebind `custom-file' so package.el writes back to the audited repo.
    (let ((custom-file custom-file))
      (when (file-exists-p custom-file)
        (load custom-file 'noerror 'nomessage))
      (customize-save-variable 'package-selected-packages selected))))

(defun package-audit--review-heading-line (level title)
  "Return Org heading string for LEVEL and TITLE."
  (concat (make-string level ?*) " " title "\n"))

(defun package-audit--use-package-stub-block (packages)
  "Return an Org source block containing minimal `use-package' stubs for PACKAGES."
  (concat
   "#+BEGIN_SRC emacs-lisp\n"
   (mapconcat
    (lambda (package-name)
      (format "  (use-package %s\n    :ensure t)"
              (symbol-name package-name)))
    packages
    "\n\n")
   "\n#+END_SRC\n"))

(defun package-audit--find-review-section-end ()
  "Return end position of the existing review section, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^\\* %s$" (regexp-quote package-audit-review-heading))
           nil t)
      (or (and (re-search-forward "^\\* " nil t)
               (match-beginning 0))
          (point-max)))))

(defun package-audit--use-package-stub-elisp (packages)
  "Return elisp format `use-package' stubs for PACKAGES."
  (concat
   (mapconcat
    (lambda (package-name)
      (format "(use-package %s\n  :ensure t)"
              (symbol-name package-name)))
    packages
    "\n\n")
   "\n"))

(defun package-audit--find-el-review-section-end ()
  "Return end position of elisp review section, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^;;+ %s$" (regexp-quote package-audit-review-heading))
           nil t)
      (or (and (re-search-forward "^;;+ [A-Z]" nil t)
               (match-beginning 0))
          (point-max)))))

(defun package-audit--insert-use-package-stubs-org (repo-root packages)
  "Insert `use-package' stubs for PACKAGES in org format init file."
  (let ((init-file (package-audit--init-source-path repo-root))
        (heading-text (package-audit--review-heading-line 1 package-audit-review-heading))
        (subheading-text (package-audit--review-heading-line 2 package-audit-review-subheading))
        (block (package-audit--use-package-stub-block packages)))
    (with-temp-buffer
      (insert-file-contents init-file)
      ;; Keep generated stubs in one review-focused section so manual
      ;; refinement work happens in one predictable place.
      (let ((section-end (package-audit--find-review-section-end)))
        (goto-char (or section-end (point-max)))
        (unless (bolp) (insert "\n"))
        (unless section-end
          (insert "\n" heading-text))
        (insert "\n" subheading-text "\n" block))
      (write-region nil nil init-file nil 'quiet))))

(defun package-audit--insert-use-package-stubs-el (repo-root packages)
  "Insert `use-package' stubs for PACKAGES in elisp format init file."
  (let ((init-file (package-audit--init-source-path repo-root))
        (heading-comment (format ";;; %s\n" package-audit-review-heading))
        (subheading-comment (format ";;;; %s\n\n" package-audit-review-subheading))
        (stubs (package-audit--use-package-stub-elisp packages)))
    (with-temp-buffer
      (insert-file-contents init-file)
      (let ((section-end (package-audit--find-el-review-section-end)))
        (goto-char (or section-end (point-max)))
        (unless (bolp) (insert "\n"))
        (unless section-end
          (insert "\n" heading-comment))
        (insert "\n" subheading-comment stubs))
      (write-region nil nil init-file nil 'quiet))))

(defun package-audit--insert-use-package-stubs (repo-root packages)
  "Insert minimal `use-package' stubs for PACKAGES in the init source for REPO-ROOT.
Formats stubs appropriately based on whether the init file is .org or elisp."
  (let ((init-file (package-audit--init-source-path repo-root)))
    (cond
     ((string-suffix-p ".org" init-file)
      (package-audit--insert-use-package-stubs-org repo-root packages))
     ((package-audit--init-source-is-elisp-p init-file)
      (package-audit--insert-use-package-stubs-el repo-root packages))
     (t
      (user-error "Unsupported init source file format: %s" init-file)))))

(defun package-audit--delete-package (repo-root package-name)
  "Delete PACKAGE-NAME from the package installation rooted at REPO-ROOT."
  (package-audit--with-package-context
   repo-root
   (lambda ()
     (let ((desc (cadr (assq package-name package-alist))))
       (unless desc
         (user-error "Package %s is not installed" package-name))
       (package-delete desc t)))))

(defun package-audit--delete-stale-directory (repo-root dir-name)
  "Delete ignored install directory DIR-NAME under REPO-ROOT."
  (when (member dir-name package-audit-protected-elpa-directories)
    ;; Never remove package-manager state directories like `gnupg',
    ;; even if a stale audit snapshot somehow hands us one.
    (user-error "Refusing to delete protected ELPA directory %s" dir-name))
  (let ((path (expand-file-name dir-name
                                (package-audit--package-install-path repo-root))))
    (unless (file-directory-p path)
      (user-error "Directory %s is no longer present" path))
    (delete-directory path t)))

;; ---------------------------------------------------------------------------
;; Interactive remediation commands

;;;###autoload
(defun package-audit-remediate-add-selected-packages (&optional repo-root)
  "Add explicit init roots missing from `package-selected-packages'."
  (interactive)
  (let* ((resolved-root (or repo-root (package-audit--resolve-repo-root)))
         (state (package-audit--ensure-state resolved-root))
         (missing (package-audit--state-symbol-list
                   state :init-roots-missing-from-selected)))
    (if (null missing)
        (message "No missing selected-package entries were found")
      (when (y-or-n-p
             (format "Add %s to the selected-package list? "
                     (package-audit--format-package-list missing)))
        (let ((new-selected
               (package-audit--symbol-union
                (package-audit--state-symbol-list state :selected)
                missing)))
          (package-audit--write-selected-packages resolved-root new-selected)
          (message "Added %d selected-package entr%s"
                   (length missing)
                   (if (= (length missing) 1) "y" "ies"))
          (package-audit--refresh-session resolved-root nil t))))))

;;;###autoload
(defun package-audit-remediate-add-use-package-stubs (&optional repo-root)
  "Insert minimal `use-package' review stubs for selected packages missing from init."
  (interactive)
  (let* ((resolved-root (or repo-root (package-audit--resolve-repo-root)))
         (state (package-audit--ensure-state resolved-root))
         (missing (package-audit--state-symbol-list state :selected-not-in-init)))
    (if (null missing)
        (message "No selected packages are missing from the init source")
      (when (y-or-n-p
             (format "Insert use-package stubs for %s? "
                     (package-audit--format-package-list missing)))
        (package-audit--insert-use-package-stubs resolved-root missing)
        (message "Inserted %d review stub%s into %s"
                 (length missing)
                 (if (= (length missing) 1) "" "s")
                 (package-audit--init-source-path resolved-root))
        (package-audit--refresh-session resolved-root nil t)))))

;;;###autoload
(defun package-audit-remediate-delete-purgeable-packages (&optional repo-root)
  "Delete definitively purgeable packages after confirming each one."
  (interactive)
  (let* ((resolved-root (or repo-root (package-audit--resolve-repo-root)))
         (state (package-audit--ensure-state resolved-root))
         (purgeable (package-audit--state-symbol-list state :purgeable))
         (deleted 0))
    (if (null purgeable)
        (message "No definitively purgeable packages were found")
      (dolist (package-name purgeable)
        (when (y-or-n-p (format "Delete purgeable package %s? " package-name))
          (package-audit--delete-package resolved-root package-name)
          (setq deleted (1+ deleted))))
      (if (> deleted 0)
          (progn
            (message "Deleted %d purgeable package%s"
                     deleted
                     (if (= deleted 1) "" "s"))
            (package-audit--refresh-session resolved-root nil t))
        (message "No purgeable packages were deleted")))))

;;;###autoload
(defun package-audit-remediate-delete-ignored-directories (&optional repo-root)
  "Delete ignored non-package install directories after confirming each one."
  (interactive)
  (let* ((resolved-root (or repo-root (package-audit--resolve-repo-root)))
         (state (package-audit--ensure-state resolved-root))
         (dirs (copy-sequence
                (plist-get state :ignored-non-package-elpa-directories)))
         (safe-dirs (cl-remove-if
                     (lambda (dir-name)
                       (member dir-name package-audit-protected-elpa-directories))
                     dirs))
         (deleted 0))
    (if (null safe-dirs)
        (message "No ignored install directories were found")
      (dolist (dir-name safe-dirs)
        (when (y-or-n-p (format "Delete ignored install directory %s? " dir-name))
          (package-audit--delete-stale-directory resolved-root dir-name)
          (setq deleted (1+ deleted))))
      (if (> deleted 0)
          (progn
            (message "Deleted %d ignored install director%s"
                     deleted
                     (if (= deleted 1) "y" "ies"))
            (package-audit--refresh-session resolved-root nil t))
        (message "No ignored install directories were deleted")))))

(provide 'package-audit-remediate)
;;; package-audit-remediate.el ends here
