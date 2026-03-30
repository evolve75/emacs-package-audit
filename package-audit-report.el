;;; package-audit-report.el --- Report rendering for package-audit -*- lexical-binding: t; -*-

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

(defun package-audit--markdown-summary-table (counts)
  "Render COUNTS as a Markdown summary table."
  (let* ((headers '("Symbol / Expression" "Meaning" "Count"))
         (rows `(("`R`"
                  "Explicit init roots"
                  ,(number-to-string (alist-get 'explicit_init_roots counts)))
                 ("`S`"
                  "Selected packages"
                  ,(number-to-string (alist-get 'package_selected_packages counts)))
                 ("`R \\\\ S`"
                  "Explicit init roots missing from package-selected-packages"
                  ,(number-to-string
                    (alist-get 'explicit_init_roots_missing_from_package_selected counts)))
                 ("`S \\\\ R`"
                  "Selected packages not explicit in init"
                  ,(number-to-string (alist-get 'selected_not_in_init counts)))
                 ("`(S \\\\ R) ∩ C`"
                  "Selected and customize-only packages"
                  ,(number-to-string (alist-get 'selected_and_customize_only counts)))
                 ("`I`"
                  "Installed packages"
                  ,(number-to-string (alist-get 'installed_packages counts)))
                 ("`D \\\\ ((R ∪ S) ∩ I)`"
                  "Dependency-only retained installs"
                  ,(number-to-string (alist-get 'retained_dependency_only counts)))
                 ("`I \\\\ D`"
                  "Definitively purgeable installs"
                  ,(number-to-string (alist-get 'definitively_purgeable counts)))))
         (widths
          (cl-loop for col from 0 below (length headers)
                   collect (apply #'max
                                  (length (nth col headers))
                                  (mapcar (lambda (row)
                                            (length (nth col row)))
                                          rows)))))
    (string-join
     (append
      (list
       (concat "| "
               (mapconcat (lambda (entry)
                            (format (format "%%-%ds" (car entry)) (cdr entry)))
                          (cl-mapcar #'cons widths headers)
                          " | ")
               " |")
       (concat "| "
               (mapconcat (lambda (width)
                            (make-string width ?-))
                          widths
                          " | ")
               " |"))
      (mapcar
       (lambda (row)
         (concat "| "
                 (mapconcat (lambda (entry)
                              (format (format "%%-%ds" (car entry)) (cdr entry)))
                            (cl-mapcar #'cons widths row)
                            " | ")
                 " |"))
       rows))
     "\n")))

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

(defun package-audit--init-source-display-name (repo-root)
  "Return display name for the init source file in REPO-ROOT."
  (file-name-nondirectory (package-audit--init-source-path repo-root)))

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

(defun package-audit--markdown-metadata-table (expression json-key)
  "Return a one-row Markdown table for EXPRESSION and JSON-KEY."
  (let* ((headers (if expression
                      '("Set expression" "JSON key")
                    '("JSON key")))
         (values (if expression
                     (list (format "`%s`" expression)
                           (format "`%s`" json-key))
                   (list (format "`%s`" json-key))))
         (widths (cl-mapcar (lambda (header value)
                              (max (length header) (length value)))
                            headers values)))
    (string-join
     (list
      (concat "| "
              (mapconcat (lambda (entry)
                           (format (format "%%-%ds" (car entry)) (cdr entry)))
                         (cl-mapcar #'cons widths headers)
                         " | ")
              " |")
      (concat "| "
              (mapconcat (lambda (width)
                           (make-string width ?-))
                         widths
                         " | ")
              " |")
      (concat "| "
              (mapconcat (lambda (entry)
                           (format (format "%%-%ds" (car entry)) (cdr entry)))
                         (cl-mapcar #'cons widths values)
                         " | ")
              " |"))
     "\n")))

(defun package-audit--markdown-definitions-table ()
  "Return the Markdown definitions table with aligned plain-text columns."
  (let* ((headers '("Term" "Meaning"))
         (rows
          '(("Init root"
             "A third-party package root inferred from init declarations and counted in `R`.")
            ("Selected package"
             "A package root listed in `package-selected-packages` and counted in `S`.")
            ("Installed package"
             "A package currently present in the ELPA install tree and counted in `I`.")
            ("Customized package support (`C`)"
             "Package evidence inferred from Customize-owned variables, used to explain packages that may still be justified outside init declarations.")
            ("Dependency closure (`D`)"
             "The retained installed roots and every installed dependency reachable from them.")
            ("Protected non-package ELPA directory"
             "Package-manager state under `elpa/` that is intentionally preserved, such as `archives` or `gnupg`.")
            ("Ignored non-package ELPA directory"
             "A top-level `elpa/` directory that is not an installed package and is not on the protected list.")))
         (widths
          (cl-loop for col from 0 below (length headers)
                   collect (apply #'max
                                  (length (nth col headers))
                                  (mapcar (lambda (row)
                                            (length (nth col row)))
                                          rows)))))
    (string-join
     (append
      (list
       (concat "| "
               (mapconcat (lambda (entry)
                            (format (format "%%-%ds" (car entry)) (cdr entry)))
                          (cl-mapcar #'cons widths headers)
                          " | ")
               " |")
       (concat "| "
               (mapconcat (lambda (width)
                            (make-string width ?-))
                          widths
                          " | ")
               " |"))
      (mapcar
       (lambda (row)
         (concat "| "
                 (mapconcat (lambda (entry)
                              (format (format "%%-%ds" (car entry)) (cdr entry)))
                            (cl-mapcar #'cons widths row)
                            " | ")
                 " |"))
       rows))
     "\n")))

(defun package-audit--markdown-protected-dir-notes (protected-dirs)
  "Return Markdown notes for notable PROTECTED-DIRS."
  (string-join
   (delq nil
         (list
          (when (member "archives" protected-dirs)
            (string-join
             '("> Note: `elpa/archives` was found and is intentionally protected."
               "> It stores package.el archive index caches such as `archive-contents`,"
               "> not installed packages, and package-audit will not suggest or delete it.")
             "\n"))
          (when (member "gnupg" protected-dirs)
            (string-join
             '("> Note: `elpa/gnupg` was found and is intentionally protected."
               "> It is package.el's GnuPG home for package signature and trust state,"
               "> not an ELPA package directory, and package-audit will not suggest or delete it.")
             "\n"))))
   "\n\n"))

(defun package-audit-render-markdown (data &optional repo-root)
  "Render package audit DATA as Markdown.
Optional REPO-ROOT enables accurate init source file display."
  (let* ((counts (alist-get 'counts data))
         (custom-vars (alist-get 'selected_customize_variables data))
         (reasons (alist-get 'retained_dependency_reasons data))
         (protected-dirs (alist-get 'protected_non_package_elpa_directories data))
         (protected-dir-notes
          (or (package-audit--markdown-protected-dir-notes protected-dirs) ""))
         (init-display-name (package-audit--init-source-display-name repo-root)))
    (string-join
     (list
      "# Emacs Package Audit"
      ""
      (format "Generated from `%s`, the configured custom state file, and installed package metadata."
              init-display-name)
      ""
      "Set model reference: the sections below use the same `R`, `S`, `I`, `C`, and `D` notation described in `package-audit/README.md`."
      ""
      "## Summary"
      ""
      (package-audit--markdown-summary-table counts)
      ""
      "## Explicit init roots missing from package-selected-packages"
      ""
      (package-audit--markdown-metadata-table
       "R \\ S"
       "explicit_init_roots_missing_from_package_selected")
      ""
      "These are packages declared explicitly in init but not yet persisted in `package-selected-packages`."
      ""
      (package-audit--markdown-bullets
       (alist-get 'explicit_init_roots_missing_from_package_selected data))
      ""
      (format "## Selected But Not Explicit In %s" init-display-name)
      ""
      (package-audit--markdown-metadata-table
       "S \\ R"
       "selected_not_in_init")
      ""
      "These are selected package roots that do not currently have an explicit package declaration in init."
      ""
      (package-audit--markdown-bullets
       (alist-get 'selected_not_in_init data))
      ""
      "## Selected And Customize-Only"
      ""
      (package-audit--markdown-metadata-table
       "(S \\ R) ∩ C"
       "selected_and_customize_only")
      ""
      "These packages are absent from init but still appear justified by Customize-owned variables."
      ""
      (package-audit--markdown-bullets
       (alist-get 'selected_and_customize_only data))
      ""
      "## Package Customize Variables"
      ""
      (package-audit--markdown-metadata-table
       nil
       "selected_customize_variables")
      ""
      "This is the package-to-variable support map used to understand the `C` portion of the model rather than a standalone set."
      ""
      (package-audit--markdown-package-vars custom-vars)
      ""
      "## Dependency-Only Retained Installs"
      ""
      (package-audit--markdown-metadata-table
       "D \\ ((R ∪ S) ∩ I)"
       "retained_dependency_only")
      ""
      "These packages are retained only because they are dependencies of the installed retained roots, not because they are roots themselves."
      ""
      (package-audit--markdown-reasons
       reasons
       (alist-get 'retained_dependency_only data))
      ""
      "## Definitively Purgeable Installs"
      ""
      (package-audit--markdown-metadata-table
       "I \\ D"
       "definitively_purgeable")
      ""
      "These installed packages are outside the retained dependency closure and are the cleanest removal candidates."
      ""
      (package-audit--markdown-bullets
       (alist-get 'definitively_purgeable data))
      ""
      "## Notable Gaps"
      ""
      "### Explicit roots missing from ELPA"
      ""
      (package-audit--markdown-metadata-table
       "R \\ I"
       "explicit_roots_missing_from_elpa")
      ""
      "These are explicit init roots that are not currently installed in the ELPA package tree."
      ""
      (package-audit--markdown-bullets
       (alist-get 'explicit_roots_missing_from_elpa data))
      ""
      "### Selected packages missing from ELPA"
      ""
      (package-audit--markdown-metadata-table
       "S \\ I"
       "selected_missing_from_elpa")
      ""
      "These are selected packages that are not currently installed in the ELPA package tree."
      ""
      (package-audit--markdown-bullets
       (alist-get 'selected_missing_from_elpa data))
      ""
      "### Protected non-package ELPA directories"
      ""
      (package-audit--markdown-bullets protected-dirs)
      ""
      protected-dir-notes
      ""
      "### Ignored non-package ELPA directories (not part of the `R`/`S`/`I` set model)"
      ""
      (package-audit--markdown-bullets
      (alist-get 'ignored_non_package_elpa_directories data))
      ""
      "## Definitions"
      ""
      (package-audit--markdown-definitions-table)
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
      (insert (package-audit-render-markdown audit-data resolved-root)))
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
