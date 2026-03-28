;;; package-audit-report.el --- Report rendering for package-audit -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Anupam Sengupta

;; Author: Anupam Sengupta <anupamsg@gmail.com>
;; Keywords: convenience, tools, maint
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Markdown, JSON, and file-output helpers for `package-audit'.

;;; Code:

(require 'json)
(require 'package-audit-core)

;; ---------------------------------------------------------------------------
;; Markdown rendering

(defun package-audit--markdown-bullets (items)
  "Render ITEMS as Markdown bullets."
  (if items
      (mapconcat (lambda (item) (format "- `%s`" item)) items "\n")
    "- None"))

(defun package-audit--markdown-package-vars (pairs)
  "Render package customization PAIRS as Markdown bullets."
  (if pairs
      (mapconcat
       (lambda (entry)
         (format "- `%s`: %s"
                 (car entry)
                 (mapconcat (lambda (var) (format "`%s`" var))
                            (cdr entry)
                            ", ")))
       pairs
       "\n")
    "- None"))

(defun package-audit--markdown-reasons (pairs packages)
  "Render dependency PAIRS for PACKAGES as Markdown bullets."
  (if packages
      (mapconcat
       (lambda (package-name)
         (format "- `%s`: retained via `%s`"
                 package-name
                 (or (alist-get package-name pairs nil nil #'string=)
                     "unknown")))
       packages
       "\n")
    "- None"))

(defun package-audit--markdown-set-heading (title expression json-key)
  "Return Markdown heading for TITLE with set EXPRESSION and JSON-KEY."
  (format "## %s (`%s`, JSON: `%s`)" title expression json-key))

(defun package-audit--markdown-gnupg-note (protected-dirs)
  "Return a Markdown note for PROTECTED-DIRS when `gnupg' is present."
  (when (member "gnupg" protected-dirs)
    (string-join
     '("> Note: `elpa/gnupg` was found and is intentionally protected."
       "> It is package.el's GnuPG home for package signature and trust state,"
       "> not an ELPA package directory, and package-audit will not suggest or delete it.")
     "\n")))

(defun package-audit-render-markdown (data)
  "Render package audit DATA as Markdown."
  (let* ((counts (alist-get 'counts data))
         (custom-vars (alist-get 'selected_customize_variables data))
         (reasons (alist-get 'retained_dependency_reasons data))
         (protected-dirs (alist-get 'protected_non_package_elpa_directories data))
         (gnupg-note (or (package-audit--markdown-gnupg-note protected-dirs) "")))
    (string-join
     (list
      "# Emacs Package Audit"
      ""
      (format "Generated from `%s`, the configured custom state file, and installed package metadata."
              (expand-file-name package-audit-init-source-file
                                (alist-get 'repo_dir data)))
      ""
      "Set model reference: the sections below use the same `R`, `S`, `I`, `C`, and `D` notation described in `user-lisp/package-audit/README.md`."
      ""
      "## Summary"
      ""
      (format "- Explicit init roots: %s"
              (alist-get 'explicit_init_roots counts))
      (format "- Selected packages: %s"
              (alist-get 'package_selected_packages counts))
      (format "- Explicit init roots missing from package-selected-packages: %s"
              (alist-get 'explicit_init_roots_missing_from_package_selected counts))
      (format "- Selected but not explicit in init: %s"
              (alist-get 'selected_not_in_init counts))
      (format "- Selected and customize-only: %s"
              (alist-get 'selected_and_customize_only counts))
      (format "- Installed packages: %s"
              (alist-get 'installed_packages counts))
      (format "- Dependency-only retained installs: %s"
              (alist-get 'retained_dependency_only counts))
      (format "- Definitively purgeable installs: %s"
              (alist-get 'definitively_purgeable counts))
      ""
      (package-audit--markdown-set-heading
       "Explicit init roots missing from package-selected-packages"
       "R \\ S"
       "explicit_init_roots_missing_from_package_selected")
      ""
      (package-audit--markdown-bullets
       (alist-get 'explicit_init_roots_missing_from_package_selected data))
      ""
      (package-audit--markdown-set-heading
       "Selected But Not Explicit In init.org"
       "S \\ R"
       "selected_not_in_init")
      ""
      (package-audit--markdown-bullets
       (alist-get 'selected_not_in_init data))
      ""
      (package-audit--markdown-set-heading
       "Selected And Customize-Only"
       "(S \\ R) ∩ C"
       "selected_and_customize_only")
      ""
      (package-audit--markdown-bullets
       (alist-get 'selected_and_customize_only data))
      ""
      "## Package Customize Variables (`C` support map, JSON: `selected_customize_variables`)"
      ""
      (package-audit--markdown-package-vars custom-vars)
      ""
      (package-audit--markdown-set-heading
       "Dependency-Only Retained Installs"
       "closure((R ∪ S) ∩ I) \\ ((R ∪ S) ∩ I)"
       "retained_dependency_only")
      ""
      (package-audit--markdown-reasons
       reasons
       (alist-get 'retained_dependency_only data))
      ""
      (package-audit--markdown-set-heading
       "Definitively Purgeable Installs"
       "I \\ closure((R ∪ S) ∩ I)"
       "definitively_purgeable")
      ""
      (package-audit--markdown-bullets
       (alist-get 'definitively_purgeable data))
      ""
      "## Notable Gaps"
      ""
      "### Explicit roots missing from ELPA (`R \\ I`, JSON: `explicit_roots_missing_from_elpa`)"
      ""
      (package-audit--markdown-bullets
       (alist-get 'explicit_roots_missing_from_elpa data))
      ""
      "### Selected packages missing from ELPA (`S \\ I`, JSON: `selected_missing_from_elpa`)"
      ""
      (package-audit--markdown-bullets
       (alist-get 'selected_missing_from_elpa data))
      ""
      "### Protected non-package ELPA directories"
      ""
      (package-audit--markdown-bullets protected-dirs)
      ""
      gnupg-note
      ""
      "### Ignored non-package ELPA directories (not part of the `R`/`S`/`I` set model)"
      ""
      (package-audit--markdown-bullets
       (alist-get 'ignored_non_package_elpa_directories data))
      "")
     "\n")))

;; ---------------------------------------------------------------------------
;; Report output and cached file helpers

(defun package-audit--markdown-report-path ()
  "Return the cached Markdown report path."
  (plist-get package-audit--last-report-files :markdown))

(defun package-audit--json-report-path ()
  "Return the cached JSON report path."
  (plist-get package-audit--last-report-files :json))

(defun package-audit-write-report (output-dir &optional repo-root data)
  "Write package audit artifacts to OUTPUT-DIR for REPO-ROOT.
Optional DATA avoids rebuilding the report payload when already available."
  (let* ((resolved-root (file-name-as-directory
                         (expand-file-name (or repo-root default-directory))))
         (audit-data (or data (package-audit-build resolved-root)))
         (json-output (expand-file-name "package-audit.json" output-dir))
         (markdown-output (expand-file-name "package-audit.md" output-dir))
         (json-encoding-pretty-print t))
    (make-directory output-dir t)
    (with-temp-file json-output
      (insert (json-encode audit-data))
      (insert "\n"))
    (with-temp-file markdown-output
      (insert (package-audit-render-markdown audit-data)))
    (list :json json-output :markdown markdown-output)))

(defun package-audit--refresh-session (&optional repo-root output-dir open-markdown)
  "Refresh cached audit state for REPO-ROOT and OUTPUT-DIR.
When OPEN-MARKDOWN is non-nil, open the Markdown report after writing."
  (let* ((resolved-root (or repo-root (package-audit--resolve-repo-root)))
         (state (package-audit--build-state resolved-root))
         (data (package-audit--data-from-state resolved-root state))
         (resolved-output-dir
          (package-audit--report-output-directory resolved-root output-dir))
         (outputs (package-audit-write-report resolved-output-dir resolved-root data)))
    (package-audit--cache-state resolved-root state data outputs)
    (when open-markdown
      (package-audit-open-markdown-report))
    outputs))

(defun package-audit--open-report-file (path)
  "Open report file at PATH."
  (unless (and path (file-exists-p path))
    (user-error "No generated package-audit report is available"))
  (pop-to-buffer (find-file-noselect path)))

;;;###autoload
(defun package-audit-open-markdown-report ()
  "Open the cached Markdown report."
  (interactive)
  (package-audit--open-report-file (package-audit--markdown-report-path)))

;;;###autoload
(defun package-audit-open-json-report ()
  "Open the cached JSON report."
  (interactive)
  (package-audit--open-report-file (package-audit--json-report-path)))

;;;###autoload
(defun package-audit-batch-write (&optional output-dir)
  "Batch entry point for writing the package audit to OUTPUT-DIR."
  (let* ((repo-root (package-audit--resolve-repo-root default-directory))
         (outputs (package-audit--refresh-session repo-root output-dir nil)))
    (dolist (path (list (plist-get outputs :json)
                        (plist-get outputs :markdown)))
      (princ (format "%s\n" path)))))

(provide 'package-audit-report)
;;; package-audit-report.el ends here
