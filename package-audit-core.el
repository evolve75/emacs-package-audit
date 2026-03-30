;;; package-audit-core.el --- Core set operations for package-audit -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Anupam Sengupta

;; Author: Anupam Sengupta <anupamsg@gmail.com>
;; Keywords: convenience, tools, maint
;; SPDX-License-Identifier: GPL-3.0-or-later

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

;; Core helpers for building the set-based package audit state.

;;; Code:

(require 'cl-lib)
(require 'package)
(require 'package-audit-parse)
(require 'subr-x)

;; ---------------------------------------------------------------------------
;; User options and cached state

(defgroup package-audit nil
  "Audit package intent, selection, and installation state."
  :group 'tools
  :prefix "package-audit-")

(defcustom package-audit-init-source-file "init.org"
  "Init source file relative to the repository root.

This variable is deprecated in favor of automatic detection.
The system now automatically detects the init source file with this precedence:
  1. init.org (if it exists)
  2. The file specified by `user-init-file' (if in the repo)
  3. init.el (as a fallback)

For backward compatibility, this variable is still used as the
default in documentation, but the actual file used is determined
by `package-audit--detect-init-source-file'."
  :type 'file
  :group 'package-audit)

(defcustom package-audit-custom-state-file nil
  "Custom state file path.
Contains package-selected-packages and Customize variables.
When nil (the default), uses `custom-file' if set, otherwise falls back
to \"customizations/emacs-custom.el\" relative to repository root."
  :type '(choice (const :tag "Use custom-file or default" nil)
                 (file :tag "Custom file path"))
  :group 'package-audit)

(defcustom package-audit-package-install-directory nil
  "Package install directory.
Where package.el stores installed packages.
When nil (the default), uses `package-user-dir'."
  :type '(choice (const :tag "Use package-user-dir" nil)
                 (directory :tag "Custom directory path"))
  :group 'package-audit)

(defcustom package-audit-report-directory
  (expand-file-name "reports" user-emacs-directory)
  "Default report directory for generated package-audit reports.

When absolute, reports are written there directly.  Relative override values
passed at runtime are still resolved against the audited repository root."
  :type 'directory
  :group 'package-audit)

(defcustom package-audit-review-heading "Package Audit Review"
  "Top-level heading used for generated review stubs in the init source."
  :type 'string
  :group 'package-audit)

(defcustom package-audit-review-subheading "Generated use-package stubs"
  "Subheading used for generated `use-package' stubs in the init source."
  :type 'string
  :group 'package-audit)

(defcustom package-audit-protected-elpa-directories '("archives" "gnupg")
  "Non-package directories under the ELPA tree that should never be deleted.

These directories are package-manager state rather than install candidates.
For example, `gnupg' is package.el's GnuPG home for package signature data."
  :type '(repeat string)
  :group 'package-audit)

(defcustom package-audit-repo-root user-emacs-directory
  "Repository root for package-audit operations.

This is the starting directory from which package-audit searches upward
to locate the repository root by finding marker files.  The init source
is detected automatically (preferring init.org, then `user-init-file',
then init.el), and must be accompanied by the custom state file configured
via `package-audit-custom-state-file'.

Defaults to `user-emacs-directory' which resolves the canonical Emacs
configuration directory even when accessed via symlink.

Most users should not need to customize this value."
  :type 'directory
  :group 'package-audit)

(defvar package-audit--last-repo-root nil
  "Repository root used for the latest cached package audit state.")

(defvar package-audit--last-state nil
  "Latest cached raw package audit state.")

(defvar package-audit--last-data nil
  "Latest cached package audit report data.")

(defvar package-audit--last-report-files nil
  "Latest cached report file plist with keys `:json' and `:markdown'.")

;; ---------------------------------------------------------------------------
;; Repository path helpers

(defun package-audit--repo-path (repo-root relative-path)
  "Expand RELATIVE-PATH within REPO-ROOT."
  (expand-file-name relative-path repo-root))

(defun package-audit--init-source-path (repo-root)
  "Return the detected init source path for REPO-ROOT.
Prefers init.org when both init.org and init.el exist."
  (let ((detected (package-audit--detect-init-source-file repo-root)))
    (unless detected
      (user-error "No init source file (init.org or %s) found in %s"
                  (if user-init-file (file-name-nondirectory user-init-file) "init.el")
                  repo-root))
    (package-audit--repo-path repo-root detected)))

(defun package-audit--custom-state-path (repo-root)
  "Return the configured custom state path for REPO-ROOT."
  (let ((custom-path (or package-audit-custom-state-file
                         custom-file
                         "customizations/emacs-custom.el")))
    (if (file-name-absolute-p custom-path)
        custom-path
      (package-audit--repo-path repo-root custom-path))))

(defun package-audit--package-install-path (repo-root)
  "Return the configured package install path for REPO-ROOT."
  (let ((install-dir (or package-audit-package-install-directory
                         package-user-dir)))
    (if (file-name-absolute-p install-dir)
        install-dir
      (package-audit--repo-path repo-root install-dir))))

(defun package-audit--report-output-directory (repo-root &optional output-dir)
  "Return report output directory for REPO-ROOT and optional OUTPUT-DIR."
  (let ((target (or output-dir package-audit-report-directory)))
    (if (file-name-absolute-p target)
        target
      (expand-file-name target repo-root))))

(defun package-audit--resolve-repo-root (&optional directory)
  "Return repository root for DIRECTORY or `package-audit-repo-root'.

Searches upward from the starting directory to find the repository root
by locating marker files.  The init source can be init.org or the file
specified by `user-init-file', with init.org preferred when both exist.
The custom state file location is configured via `package-audit-custom-state-file'.

If DIRECTORY is provided, uses it as the starting point.  Otherwise,
uses `package-audit-repo-root' (which defaults to `user-emacs-directory')."
  (let ((start (file-name-as-directory
                (expand-file-name (or directory package-audit-repo-root)))))
    (or (locate-dominating-file
         start
         (lambda (candidate)
           (and (package-audit--detect-init-source-file candidate)
                (file-exists-p (package-audit--custom-state-path candidate)))))
        (user-error "Could not locate a package-audit repo root from %s (looked for init.org or %s alongside %s)"
                    start
                    (if user-init-file (file-name-nondirectory user-init-file) "init.el")
                    package-audit-custom-state-file))))

(defun package-audit--cache-state (repo-root state data &optional report-files)
  "Cache package audit STATE, DATA, and REPORT-FILES for REPO-ROOT."
  (setq package-audit--last-repo-root repo-root
        package-audit--last-state state
        package-audit--last-data data
        package-audit--last-report-files report-files))

;; ---------------------------------------------------------------------------
;; Low-level parsing helpers

(defun package-audit--read-forms (file)
  "Return a list of top-level forms read from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun package-audit--quote-payload (entry)
  "Return quoted payload for custom ENTRY, or nil when absent."
  (when (and (consp entry)
             (eq (car entry) 'quote)
             (consp (cdr entry)))
    (cadr entry)))

(defun package-audit--normalize-symbol-list (items)
  "Return ITEMS normalized as a sorted unique list of symbols."
  (sort (delete-dups (cl-remove-if-not #'symbolp (copy-sequence items)))
        (lambda (left right)
          (string< (symbol-name left) (symbol-name right)))))

(defun package-audit--read-custom-state (custom-file)
  "Return selected packages and custom variable payloads from CUSTOM-FILE."
  (let (selected variables)
    (dolist (form (package-audit--read-forms custom-file))
      (when (and (consp form) (eq (car form) 'custom-set-variables))
        (dolist (entry (cdr form))
          (let* ((payload (package-audit--quote-payload entry))
                 (variable (and (consp payload) (car payload))))
            (cond
             ((not (consp payload)) nil)
             ((eq variable 'package-selected-packages)
              ;; Preserve package.el's selected-package roots as a symbol set.
              (let ((value (cadr payload)))
                (setq selected
                      (package-audit--normalize-symbol-list
                       (if (and (consp value) (eq (car value) 'quote))
                           (cadr value)
                         value)))))
             ((symbolp variable)
              ;; Track Customize-backed variables so we can identify
              ;; packages still justified only by custom-file state.
              (push variable variables)))))))
    (list :selected selected
          :variables (package-audit--normalize-symbol-list variables))))

;; ---------------------------------------------------------------------------
;; Package-root inference helpers

(defun package-audit--library-path (library)
  "Locate LIBRARY and return its absolute path when available."
  (let ((lib-name (cond
                   ((symbolp library) (symbol-name library))
                   ((stringp library) library))))
    (when lib-name
      (ignore-errors (locate-library lib-name)))))

(defun package-audit--path-in-repo-p (path repo-dir)
  "Return non-nil when PATH is inside REPO-DIR."
  (let ((true-path (file-name-as-directory (file-truename path)))
        (true-repo (file-name-as-directory (file-truename repo-dir))))
    (string-prefix-p true-repo true-path)))

;; ---------------------------------------------------------------------------
;; Set helpers and package metadata helpers

(defun package-audit--symbol-intersection (left right)
  "Return sorted symbol intersection of LEFT and RIGHT."
  (package-audit--normalize-symbol-list
   (cl-remove-if-not (lambda (item) (memq item right)) left)))

(defun package-audit--symbol-difference (left right)
  "Return sorted symbol difference LEFT minus RIGHT."
  (package-audit--normalize-symbol-list
   (cl-remove-if (lambda (item) (memq item right)) left)))

(defun package-audit--symbol-union (left right)
  "Return sorted symbol union of LEFT and RIGHT."
  (package-audit--normalize-symbol-list
   (append left right)))

(defun package-audit--with-package-context (repo-root fn)
  "Call FN with package.el scoped to REPO-ROOT."
  (let ((user-emacs-directory (file-name-as-directory repo-root))
        (package-user-dir (package-audit--package-install-path repo-root))
        package-alist
        package-archive-contents
        package--initialized)
    ;; Restrict package.el to the target install tree before reading metadata.
    (package-initialize)
    (funcall fn)))

(defun package-audit--installed-package-alist (repo-root)
  "Return installed package metadata for REPO-ROOT."
  (package-audit--with-package-context
   repo-root
   (lambda ()
     (cl-loop for entry in package-alist
              for package-name = (car entry)
              for desc = (cadr entry)
              when desc
              collect (cons package-name desc)))))

(defun package-audit--package-dir-map (installed)
  "Return a package-dir map from INSTALLED package metadata."
  (cl-loop for (package-name . desc) in installed
           for dir = (ignore-errors (package-desc-dir desc))
           when dir
           collect (cons package-name (file-name-as-directory (file-truename dir)))))

(defun package-audit--package-for-file (file dir-map)
  "Return installed package that owns FILE using DIR-MAP."
  (when (and file (file-exists-p file))
    (let* ((true-file (file-truename file))
           best-match
           (best-length 0))
      (dolist (entry dir-map best-match)
        (when (string-prefix-p (cdr entry) true-file)
          (let ((dir-length (length (cdr entry))))
            (when (> dir-length best-length)
              (setq best-length dir-length
                    best-match (car entry)))))))))

(defun package-audit--selected-prefix-package (variable selected)
  "Return a selected package whose name prefixes VARIABLE."
  (let ((variable-name (symbol-name variable)))
    (cl-find-if
     (lambda (package-name)
       (let ((prefix (symbol-name package-name)))
         (and (string-prefix-p prefix variable-name)
              (or (= (length prefix) (length variable-name))
                  (eq (aref variable-name (length prefix)) ?-)))))
     (sort (copy-sequence selected)
           (lambda (left right)
             (> (length (symbol-name left))
                (length (symbol-name right))))))))

(defun package-audit--variable-package (variable dir-map selected)
  "Return installed package providing custom VARIABLE."
  (or
   (cl-loop for library in (get variable 'custom-loads)
            for file = (package-audit--library-path library)
            for package-name = (package-audit--package-for-file file dir-map)
            when package-name
            return package-name)
   (let ((file (ignore-errors (symbol-file variable 'defvar))))
     (package-audit--package-for-file file dir-map))
   (package-audit--selected-prefix-package variable selected)))

(defun package-audit--custom-package-map (variables dir-map selected)
  "Return package-to-variable map for custom VARIABLES."
  (let ((table (make-hash-table :test #'eq)))
    (dolist (variable variables)
      (let ((package-name (package-audit--variable-package variable dir-map selected)))
        (when package-name
          ;; Group Customize-owned variables by package so the report stays compact.
          (puthash package-name
                   (cons variable (gethash package-name table))
                   table))))
    (let (result)
      (maphash
       (lambda (package-name package-vars)
         (push (cons package-name
                     (package-audit--normalize-symbol-list package-vars))
               result))
       table)
      (sort result
            (lambda (left right)
              (string< (symbol-name (car left))
                       (symbol-name (car right))))))))

(defun package-audit--installed-package-names (installed)
  "Return normalized installed package names from INSTALLED."
  (package-audit--normalize-symbol-list (mapcar #'car installed)))

(defun package-audit--installed-direct-deps (installed)
  "Return an alist of installed package direct dependencies from INSTALLED."
  (let ((installed-names (package-audit--installed-package-names installed)))
    (cl-loop for (package-name . desc) in installed
             collect
             (cons package-name
                   (cl-remove-if-not
                    (lambda (dependency)
                      (memq dependency installed-names))
                    (mapcar #'car (package-desc-reqs desc)))))))

(defun package-audit--dependency-closure (roots deps)
  "Return dependency closure for ROOTS using DEPS."
  (let ((pending (copy-sequence roots))
        (seen (copy-sequence roots))
        reasons)
    (while pending
      (let ((package-name (pop pending)))
        (dolist (dependency (alist-get package-name deps))
          (unless (memq dependency seen)
            ;; Track both the closure and the root that retained each dependency.
            (push dependency seen)
            (push dependency pending)
            (push (cons dependency package-name) reasons)))))
    (list :closure (package-audit--normalize-symbol-list seen)
          :reasons (sort reasons
                         (lambda (left right)
                           (string< (symbol-name (car left))
                                    (symbol-name (car right))))))))

(defun package-audit--non-package-elpa-dirs (repo-root installed)
  "Return install directories in REPO-ROOT that are not tracked packages."
  (let* ((install-dir (package-audit--package-install-path repo-root))
         (installed-dir-names
          (mapcar (lambda (entry)
                    (file-name-nondirectory
                     (directory-file-name
                      (package-desc-dir (cdr entry)))))
                  installed))
         extra-dirs)
    (when (file-directory-p install-dir)
      (dolist (path (directory-files install-dir t directory-files-no-dot-files-regexp))
        (when (file-directory-p path)
          (let ((name (file-name-nondirectory path)))
            (unless (or (member name package-audit-protected-elpa-directories)
                        (member name installed-dir-names))
              (push name extra-dirs))))))
    (sort extra-dirs #'string<)))

(defun package-audit--protected-elpa-dirs-present (repo-root)
  "Return protected ELPA directories currently present for REPO-ROOT."
  (let ((install-dir (package-audit--package-install-path repo-root))
        present)
    (when (file-directory-p install-dir)
      (dolist (dir-name package-audit-protected-elpa-directories)
        (when (file-directory-p (expand-file-name dir-name install-dir))
          ;; Preserve configured order so report notes stay predictable.
          (push dir-name present))))
    (nreverse present)))

;; ---------------------------------------------------------------------------
;; Audit state construction

(defun package-audit--build-state (repo-root)
  "Build raw package audit state for REPO-ROOT."
  (let* ((init-source (package-audit--init-source-path repo-root))
         (custom-file (package-audit--custom-state-path repo-root))
         (custom-state (package-audit--read-custom-state custom-file))
         (selected (plist-get custom-state :selected))
         (custom-variables (plist-get custom-state :variables))
         (installed (package-audit--installed-package-alist repo-root))
         (installed-names (package-audit--installed-package-names installed))
         (dir-map (package-audit--package-dir-map installed))
         (init-roots (package-audit--explicit-init-roots init-source repo-root))
         (custom-package-map (package-audit--custom-package-map
                              custom-variables dir-map selected))
         (custom-only-packages
          (package-audit--symbol-intersection
           (mapcar #'car custom-package-map)
           selected))
         (init-roots-missing-from-selected
          (package-audit--symbol-difference init-roots selected))
         (selected-not-in-init
          (package-audit--symbol-difference selected init-roots))
         (selected-and-customize-only
          (package-audit--symbol-intersection selected-not-in-init custom-only-packages))
         (deps (package-audit--installed-direct-deps installed))
         (retained-roots
          (package-audit--symbol-intersection
           (package-audit--symbol-union init-roots selected)
           installed-names))
         (closure-data (package-audit--dependency-closure retained-roots deps))
         (retained-closure (plist-get closure-data :closure))
         (dependency-reasons (plist-get closure-data :reasons))
         (retained-dependencies
          (package-audit--symbol-difference retained-closure retained-roots))
         (purgeable
          (package-audit--symbol-difference installed-names retained-closure))
         (protected-elpa-directories
          (package-audit--protected-elpa-dirs-present repo-root)))
    (list
     :selected selected
     :custom-variables custom-variables
     :installed installed
     :installed-names installed-names
     :dir-map dir-map
     :init-roots init-roots
     :custom-package-map custom-package-map
     :custom-only-packages custom-only-packages
     :init-roots-missing-from-selected init-roots-missing-from-selected
     :selected-not-in-init selected-not-in-init
     :selected-and-customize-only selected-and-customize-only
     :dependency-reasons dependency-reasons
     :retained-dependencies retained-dependencies
     :purgeable purgeable
     :explicit-roots-missing-from-elpa
     (package-audit--symbol-difference init-roots installed-names)
     :selected-missing-from-elpa
     (package-audit--symbol-difference selected installed-names)
     :protected-elpa-directories
     protected-elpa-directories
     :ignored-non-package-elpa-directories
     (package-audit--non-package-elpa-dirs repo-root installed))))

(defun package-audit--symbol-strings (symbols)
  "Return SYMBOLS as a list of strings."
  (mapcar #'symbol-name symbols))

(defun package-audit--vars-to-strings (variables)
  "Return VARIABLES as a list of strings."
  (mapcar #'symbol-name variables))

(defun package-audit--json-pairs (pairs)
  "Return PAIRS with string keys and JSON-ready values."
  (mapcar (lambda (entry)
            (cons (symbol-name (car entry))
                  (package-audit--vars-to-strings (cdr entry))))
          pairs))

(defun package-audit--reason-pairs (pairs)
  "Return dependency reason PAIRS with string keys and values."
  (mapcar (lambda (entry)
            (cons (symbol-name (car entry))
                  (symbol-name (cdr entry))))
          pairs))

(defun package-audit--data-from-state (repo-root state)
  "Build report data for REPO-ROOT from raw audit STATE."
  (let* ((init-roots (plist-get state :init-roots))
         (selected (plist-get state :selected))
         (selected-not-in-init (plist-get state :selected-not-in-init))
         (selected-and-customize-only
          (plist-get state :selected-and-customize-only))
         (installed-names (plist-get state :installed-names))
         (retained-dependencies (plist-get state :retained-dependencies))
         (purgeable (plist-get state :purgeable))
         (init-roots-missing-from-selected
          (plist-get state :init-roots-missing-from-selected)))
    `((repo_dir . ,repo-root)
      (explicit_init_roots . ,(package-audit--symbol-strings init-roots))
      (package_selected_packages . ,(package-audit--symbol-strings selected))
      (explicit_init_roots_missing_from_package_selected
       . ,(package-audit--symbol-strings init-roots-missing-from-selected))
      (selected_not_in_init . ,(package-audit--symbol-strings selected-not-in-init))
      (selected_and_customize_only
       . ,(package-audit--symbol-strings selected-and-customize-only))
      (selected_customize_variables
       . ,(package-audit--json-pairs (plist-get state :custom-package-map)))
      (installed_packages . ,(package-audit--symbol-strings installed-names))
      (retained_dependency_only
       . ,(package-audit--symbol-strings retained-dependencies))
      (retained_dependency_reasons
       . ,(package-audit--reason-pairs (plist-get state :dependency-reasons)))
      (definitively_purgeable . ,(package-audit--symbol-strings purgeable))
      (explicit_roots_missing_from_elpa
       . ,(package-audit--symbol-strings
           (plist-get state :explicit-roots-missing-from-elpa)))
      (selected_missing_from_elpa
       . ,(package-audit--symbol-strings
           (plist-get state :selected-missing-from-elpa)))
      (protected_non_package_elpa_directories
       . ,(plist-get state :protected-elpa-directories))
      (ignored_non_package_elpa_directories
       . ,(plist-get state :ignored-non-package-elpa-directories))
      (counts
       . ((explicit_init_roots . ,(length init-roots))
          (package_selected_packages . ,(length selected))
          (explicit_init_roots_missing_from_package_selected
           . ,(length init-roots-missing-from-selected))
          (selected_not_in_init . ,(length selected-not-in-init))
          (selected_and_customize_only . ,(length selected-and-customize-only))
          (installed_packages . ,(length installed-names))
          (retained_dependency_only . ,(length retained-dependencies))
          (definitively_purgeable . ,(length purgeable)))))))

(defun package-audit-build (repo-root)
  "Build package audit report data for REPO-ROOT."
  (package-audit--data-from-state repo-root
                                  (package-audit--build-state repo-root)))

(defun package-audit--ensure-state (&optional repo-root)
  "Return cached or freshly built audit state for REPO-ROOT."
  (let ((resolved-root (or repo-root (package-audit--resolve-repo-root))))
    (if (and package-audit--last-state
             (equal resolved-root package-audit--last-repo-root))
        package-audit--last-state
      (let* ((state (package-audit--build-state resolved-root))
             (data (package-audit--data-from-state resolved-root state)))
        (package-audit--cache-state resolved-root state data package-audit--last-report-files)
        state))))

(provide 'package-audit-core)
;;; package-audit-core.el ends here
