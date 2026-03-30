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
  (let* ((headers '("Set" "Description" "Count"))
         (rows `(("`R`"
                  "Packages declared in init"
                  ,(number-to-string (alist-get 'explicit_init_roots counts)))
                 ("`S`"
                  "Packages in package-selected-packages"
                  ,(number-to-string (alist-get 'package_selected_packages counts)))
                 ("`R \\\\ S`"
                  "Declared in init but not selected"
                  ,(number-to-string
                    (alist-get 'explicit_init_roots_missing_from_package_selected counts)))
                 ("`S \\\\ R`"
                  "Selected but not declared in init"
                  ,(number-to-string (alist-get 'selected_not_in_init counts)))
                 ("`(S \\\\ R) ∩ C`"
                  "Selected but only via Customize"
                  ,(number-to-string (alist-get 'selected_and_customize_only counts)))
                 ("`I`"
                  "Packages currently installed"
                  ,(number-to-string (alist-get 'installed_packages counts)))
                 ("`D \\\\ ((R ∪ S) ∩ I)`"
                  "Installed as dependencies only"
                  ,(number-to-string (alist-get 'retained_dependency_only counts)))
                 ("`I \\\\ D`"
                  "Orphaned (safe to delete)"
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
          '(("Init root (`R`)"
             "A package you've declared with `use-package :ensure t` in your init file.")
            ("Selected package (`S`)"
             "A package listed in `package-selected-packages` (typically managed by package.el).")
            ("Installed package (`I`)"
             "A package currently present in your `elpa/` directory.")
            ("Customized package (`C`)"
             "A package whose variables you've configured via `M-x customize`. Helps explain packages selected but not declared in init.")
            ("Dependency closure (`D`)"
             "All selected packages plus every dependency they need, recursively.")
            ("Protected ELPA directory"
             "Package manager metadata under `elpa/` (like `archives` or `gnupg`) that should never be deleted.")
            ("Ignored ELPA directory"
             "A directory in `elpa/` that isn't recognized as a valid package and isn't protected metadata. May include backups, temp files, incomplete downloads, or old package versions that weren't cleaned up properly.")))
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
             '("> **Note:** `elpa/archives` contains package index caches (not installed packages)."
               "> This is package manager metadata and will never be suggested for deletion.")
             "\n"))
          (when (member "gnupg" protected-dirs)
            (string-join
             '("> **Note:** `elpa/gnupg` contains package signature verification data."
               "> This is package manager metadata and will never be suggested for deletion.")
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
      "The sections below use set notation (`R`, `S`, `I`, `C`, `D`) as described in the README."
      ""
      "## Summary"
      ""
      (package-audit--markdown-summary-table counts)
      ""
      "## Declared in init but not in package-selected-packages"
      ""
      (package-audit--markdown-metadata-table
       "R \\ S"
       "explicit_init_roots_missing_from_package_selected")
      ""
      "These packages are declared in your init file but aren't yet recorded in `package-selected-packages`."
      ""
      (if (alist-get 'explicit_init_roots_missing_from_package_selected data)
          "**Fix:** Run `M-x package-audit-remediate-add-selected-packages` to sync them.\n"
        "")
      (package-audit--markdown-bullets
       (alist-get 'explicit_init_roots_missing_from_package_selected data))
      ""
      (format "## Selected but not declared in %s" init-display-name)
      ""
      (package-audit--markdown-metadata-table
       "S \\ R"
       "selected_not_in_init")
      ""
      "These packages are in `package-selected-packages` but don't have a `use-package` declaration in your init file."
      ""
      (if (alist-get 'selected_not_in_init data)
          "**Fix:** Run `M-x package-audit-remediate-add-use-package-stubs` to generate declarations, or remove them from selections if unwanted.\n"
        "")
      (package-audit--markdown-bullets
       (alist-get 'selected_not_in_init data))
      ""
      "## Selected but only configured via Customize"
      ""
      (package-audit--markdown-metadata-table
       "(S \\ R) ∩ C"
       "selected_and_customize_only")
      ""
      "These packages aren't declared in init, but you've customized their variables via `M-x customize`. This may be intentional."
      ""
      (package-audit--markdown-bullets
       (alist-get 'selected_and_customize_only data))
      ""
      "## Customized variables by package"
      ""
      (package-audit--markdown-metadata-table
       nil
       "selected_customize_variables")
      ""
      "Shows which packages own the customization variables you've set. Helps explain why packages in the section above might still be needed."
      ""
      (package-audit--markdown-package-vars custom-vars)
      ""
      "## Packages installed as dependencies"
      ""
      (package-audit--markdown-metadata-table
       "D \\ ((R ∪ S) ∩ I)"
       "retained_dependency_only")
      ""
      "These packages were installed automatically as dependencies of your selected packages, not because you explicitly chose them."
      ""
      (package-audit--markdown-reasons
       reasons
       (alist-get 'retained_dependency_only data))
      ""
      "## Orphaned packages (safe to delete)"
      ""
      (package-audit--markdown-metadata-table
       "I \\ D"
       "definitively_purgeable")
      ""
      "These packages are installed but not needed by any of your selected packages. Safe to delete."
      ""
      (if (alist-get 'definitively_purgeable data)
          "**Fix:** Run `M-x package-audit-remediate-delete-purgeable-packages` to remove them.\n"
        "")
      (package-audit--markdown-bullets
       (alist-get 'definitively_purgeable data))
      ""
      "## Missing packages (not yet installed)"
      ""
      "### Declared in init but not installed"
      ""
      (package-audit--markdown-metadata-table
       "R \\ I"
       "explicit_roots_missing_from_elpa")
      ""
      "These packages are declared in your init file but not installed yet."
      ""
      (if (alist-get 'explicit_roots_missing_from_elpa data)
          "**Fix:** Run `M-x package-install` for each, or restart Emacs to trigger automatic installation.\n"
        "")
      (package-audit--markdown-bullets
       (alist-get 'explicit_roots_missing_from_elpa data))
      ""
      "### In package-selected-packages but not installed"
      ""
      (package-audit--markdown-metadata-table
       "S \\ I"
       "selected_missing_from_elpa")
      ""
      "These packages are in `package-selected-packages` but not installed yet."
      ""
      (if (alist-get 'selected_missing_from_elpa data)
          "**Fix:** Run `M-x package-install-selected-packages` to install them.\n"
        "")
      (package-audit--markdown-bullets
       (alist-get 'selected_missing_from_elpa data))
      ""
      "### Protected directories in elpa/"
      ""
      (package-audit--markdown-bullets protected-dirs)
      ""
      protected-dir-notes
      ""
      "### Extra directories in elpa/ (not packages)"
      ""
      "These are directories or files in your `elpa/` folder that aren't recognized as valid packages and aren't protected metadata."
      ""
      "Common causes: backup files (`.DS_Store`, `Thumbs.db`), incomplete downloads, corrupted package directories, or old package versions that weren't properly cleaned up."
      ""
      (if (alist-get 'ignored_non_package_elpa_directories data)
          "**Fix:** Run `M-x package-audit-remediate-delete-ignored-directories` to clean them up.\n"
        "")
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
