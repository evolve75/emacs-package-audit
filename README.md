# package-audit

**package-audit** helps you maintain a clean, intentional Emacs package configuration by analyzing the relationship between what you've declared in your init file via `use-package` blocks, what's marked as selected in `package-selected-packages`, and what's actually installed in your ELPA directory.

## Why Use package-audit?

Over time, Emacs package installations can drift from your declared intent:

- **Orphaned packages**: Packages installed but no longer referenced in your config
- **Missing declarations**: Packages you use but haven't explicitly declared
- **Selection drift**: Packages installed but not in `package-selected-packages`
- **Leftover experiments**: Package directories from trials you've abandoned
- **Dependency clutter**: Understanding which packages are dependencies vs. direct choices

`package-audit` makes these problems visible through comprehensive reports and provides **automated remediation** to bring your configuration back into alignment.

## What Can You Fix?

The package offers four remediation commands:

1. **Add missing selections**: Sync explicit init declarations to `package-selected-packages`
2. **Add missing declarations**: Generate `use-package` stubs for selected-but-undeclared packages
3. **Delete orphaned packages**: Remove definitively purgeable ELPA installations
4. **Clean ignored directories**: Remove non-package directories from your ELPA tree

All remediation commands use prompted confirmation by default, showing you exactly what will change before applying it.

## Installation

### From GitHub (recommended)

Since `package-audit` requires Emacs 30.1, you can use the built-in `:vc` keyword (introduced in Emacs 29) to install directly from GitHub:

```elisp
(use-package package-audit
  :vc (:fetcher github :repo "evolve75/emacs-package-audit"))
```

The package will be submitted to MELPA in the future for simpler installation.

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/evolve75/emacs-package-audit.git
   ```

2. Add to your load path and require:
   ```elisp
   (add-to-list 'load-path "/path/to/emacs-package-audit")
   (require 'package-audit)
   ```

## Quick Start

After installation, run:

```elisp
M-x package-audit-run
```

This command:

- Computes the current audit state
- Writes JSON and Markdown reports to `<user-emacs-directory>/reports/` (e.g., `~/.config/emacs/reports/`)
- Opens the Markdown report in a buffer
- Caches the audit snapshot for follow-up remediation commands
- Shows an interactive Hydra menu (if Hydra is available)

From the report, you'll see exactly what's misaligned and can use the remediation commands to fix issues.

## Understanding Package Audit: A Set Theory Approach

`package-audit` models your package ecosystem as **five core sets** and computes alignment issues as set operations. This mathematical foundation ensures the analysis is precise, composable, and reproducible.

### Core Sets

| Symbol | Name                | Source                                     | Meaning                                                         |
|--------|---------------------|--------------------------------------------|-----------------------------------------------------------------|
| **R**  | Explicit init roots | Init file (`init.org` or `init.el`)        | Third-party packages you've declared with `use-package :ensure` |
| **S**  | Selected packages   | `package-selected-packages` in custom file | Packages marked as "intentionally installed"                    |
| **I**  | Installed packages  | ELPA directory                             | Packages physically present in `elpa/`                          |
| **C**  | Customized packages | Custom variables                           | Packages that own variables set via Customize                   |
| **D**  | Dependency closure  | Package metadata                           | All retained packages plus their transitive dependencies        |

#### What is R (Explicit Init Roots)?

`R` contains the **normalized third-party package roots** inferred from your init file's `use-package` declarations. The tool applies these rules:

- **Built-ins are excluded**: `(use-package org ...)` won't add `org` to `R` if it's built-in
- **Repo-local packages are excluded**: First-party packages locally installed in your config repo (e.g., in `user-lisp/` directory, not installed via `package-install`) don't count
- **`:ensure t` records the package name**: `(use-package magit :ensure t)` → `magit` ∈ R
- **Symbolic `:ensure` records the alias**: `(use-package tex :ensure auctex)` → `auctex` ∈ R
- **`:ensure nil` is an explicit opt-out**: Package won't be in `R` even if declared
- **`:load-path` declarations are excluded**: Local packages don't count as third-party

This means `R` represents **what you've explicitly told Emacs to install from package archives**, not just "every `use-package` form."

#### What is S (Selected Packages)?

`S` is the contents of `package-selected-packages`, which Emacs uses to distinguish between:

- **Directly installed packages** (in `S`): You explicitly chose these
- **Dependencies** (not in `S`): Automatically pulled in by package.el

When you run `M-x package-autoremove`, Emacs removes packages in `I \ closure(S ∩ I)` — anything installed but not needed by selected packages.

#### What is I (Installed Packages)?

`I` contains every package directory in your `elpa/` directory. This includes:

- Packages you explicitly installed
- Their dependencies
- Orphaned packages from previous configurations
- Packages installed manually or via experiments
- Older versions of packages (when package.el keeps multiple versions)

#### What is C (Customized Packages)?

`C` identifies packages that own Customize variables you've set via `M-x customize`. This helps explain packages in `S \ R` — they may be justified by Customize usage even if not declared in init.

#### What is D (Dependency Closure)?

`D = closure((R ∪ S) ∩ I)` — the transitive dependency closure of all retained packages. This set includes:

- Every package in `(R ∪ S) ∩ I` (your explicit choices that are installed)
- Every package those packages depend on
- Every package *those* dependencies depend on, recursively

Any package in `I \ D` has no dependency path to your retained roots, making it definitively purgeable.

### Intended Invariants

In a well-maintained configuration:

- **Intent and selection align**: `R = S`
  - Your init declarations match `package-selected-packages`
- **Installations are justified**: `I ⊆ D`
  - Every installed package is either retained or a dependency of one
- **No orphaned packages**: `I \ D = ∅`
  - Nothing installed is unreachable from your retained set

The model **intentionally allows drift** so the reports can surface what needs reconciliation rather than assuming a perfect state. Temporary misalignment is normal — the tool helps you see it and fix it.

## File Locations and Detection

### Init Source File

`package-audit` supports both **Org-mode literate programming** and **vanilla Emacs Lisp** configurations.

**Automatic detection precedence:**

1. `init.org` — Preferred for literate programming
2. `user-init-file` — The file Emacs actually loaded (e.g., `init.el`, `.emacs`)
3. `init.el` — Fallback for batch mode

**Examples:**

- Standard: `~/.config/emacs/init.el`
- Literate: `~/.config/emacs/init.org`
- Classic: `~/.emacs`
- Custom: Whatever `user-init-file` points to

When both `init.org` and `init.el` exist, `init.org` takes precedence. This supports configurations where `init.el` is generated from `init.org` via `org-babel-tangle`.

#### Org Format (init.org)

The tool extracts `use-package` declarations from `emacs-lisp` source blocks:

```org
* Package Configuration

** Development Tools

#+BEGIN_SRC emacs-lisp
  (use-package magit
    :ensure t
    :bind ("C-x g" . magit-status))

  (use-package company
    :ensure t
    :hook (prog-mode . company-mode))
#+END_SRC
```

#### Elisp Format (init.el)

The tool parses `use-package` declarations directly:

```elisp
;;; Package Configuration

;; Development Tools

(use-package magit
  :ensure t
  :bind ("C-x g" . magit-status))

(use-package company
  :ensure t
  :hook (prog-mode . company-mode))
```

Both formats produce the same `R` set: `{magit, company}`.

### Package Install Directory

The ELPA installation directory where `package.el` stores installed packages.

**Default behavior:** Uses the `package-user-dir` variable, which typically points to the `elpa/` directory in your Emacs configuration.

**Example locations:**

- Standard: `~/.config/emacs/elpa/` (typical `package-user-dir` value)
- Classic: `~/.emacs.d/elpa/`
- Custom: `~/my-config/packages/elpa/`

**Typical contents:**

```
elpa/
├── archives/           (package archive metadata)
├── gnupg/             (GPG keys for package signing)
├── magit-20260320.1234/
├── company-20260315.2100/
├── dash-20260301.900/  (dependency of magit)
└── ...
```

The tool scans this directory to build `I` (installed packages) and uses package metadata to compute dependency closures.

### Custom State File

The file where Emacs stores `custom-set-variables` output.

**Default behavior:** Uses the `custom-file` variable if set in your Emacs configuration. If `custom-file` is nil, falls back to `custom.el` in `<user-emacs-directory>`.

**Example paths:**
- `~/.config/emacs/custom.el` (if `custom-file` is set, or as fallback)

This file contains `package-selected-packages` and any Customize-set variables. The tool parses it to build `S` and `C`.

## Configuration

All customizable variables:

| Category                      | Variable                                   | Default                                             | Description                                                                                                                                                     |
|-------------------------------|--------------------------------------------|-----------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Repository and File Locations | `package-audit-repo-root`                  | `nil` (uses `user-emacs-directory`)                 | Starting directory for repository root detection. When nil, uses `<user-emacs-directory>`. Most users should not need to customize this.                        |
| Repository and File Locations | `package-audit-custom-state-file`          | `nil` (uses `custom-file`)                          | Custom state file path. When nil, uses `custom-file` if set, otherwise falls back to `"custom.el"` in `<user-emacs-directory>`. Contains `package-selected-packages` and Customize variables. |
| Repository and File Locations | `package-audit-package-install-directory`  | `nil` (uses `package-user-dir`)                     | Package install directory. When nil, uses `package-user-dir`. Can be set to a custom directory path (absolute or relative to repository root).                  |
| Report Output                 | `package-audit-report-directory`           | `(expand-file-name "reports" user-emacs-directory)` | Directory where JSON and Markdown reports are written. Can be absolute or relative. Relative paths are resolved against the audited repository root at runtime. |
| Remediation Headers           | `package-audit-review-heading`             | `"Package Audit Review"`                            | Top-level heading for generated review stubs in init file. For `.org` files: `* Package Audit Review`. For `.el` files: `;;; Package Audit Review`.             |
| Remediation Headers           | `package-audit-review-subheading`          | `"Generated use-package stubs"`                     | Subheading for generated use-package stubs. For `.org` files: `** Generated use-package stubs`. For `.el` files: `;;;; Generated use-package stubs`.            |
| Protected Directories         | `package-audit-protected-elpa-directories` | `'("archives" "gnupg")`                             | Non-package directories under ELPA that should never be deleted. These are package-manager state, not install candidates.                                       |

## Interactive Use

### Available Commands

The following commands are available. The Hydra key bindings are displayed after running `package-audit-run` (if Hydra is installed).

| Command                              | Key (Hydra) | Description                                               |
|--------------------------------------|-------------|-----------------------------------------------------------|
| `package-audit-run`                  | `r`         | Run full audit, write reports, open Markdown, cache state |
| `package-audit-refresh`              | `R`         | Refresh audit without opening report                      |
| `package-audit-open-markdown-report` | `m`         | Open latest Markdown report                               |
| `package-audit-open-json-report`     | `j`         | Open latest JSON report                                   |
| `package-audit-show-operations`      | `?`         | Show Hydra menu (if available)                            |

### Remediation Commands

All remediation commands operate on the cached audit state and regenerate reports after successful changes. These commands can be invoked:

- **Directly** via `M-x package-audit-remediate-<action>`
- **Via Hydra keys** after running `package-audit-run` (if Hydra is installed)

#### Add Missing Selections

```elisp
M-x package-audit-remediate-add-selected-packages
```

**What it fixes:** Packages in `R \ S` — declared in init but missing from `package-selected-packages`.

**Example:**

```
You have declared these packages in init.org but they're not in package-selected-packages:
  magit, company, flycheck

Add them to package-selected-packages? (y/n)
```

Selecting `y` updates `customizations/emacs-custom.el` to include these packages in `package-selected-packages`.

#### Add Missing Declarations

```elisp
M-x package-audit-remediate-add-use-package-stubs
```

**What it fixes:** Packages in `S \ R` — in `package-selected-packages` but not declared in init.

**Example:**

```
These packages are selected but not declared in init.org:
  rainbow-delimiters, which-key

Generate use-package stubs for them? (y/n)
```

Selecting `y` inserts stubs into your init file under the configured review heading:

**For init.org:**
```org
* Package Audit Review

** Generated use-package stubs

#+BEGIN_SRC emacs-lisp
  (use-package rainbow-delimiters
    :ensure t)

  (use-package which-key
    :ensure t)
#+END_SRC
```

**For init.el:**
```elisp
;;; Package Audit Review

;;;; Generated use-package stubs

(use-package rainbow-delimiters
  :ensure t)

(use-package which-key
  :ensure t)
```

**Note for literate configurations:** If you remediate `init.org`, the corresponding `init.el` file (if tangled from `init.org`) must be retangled manually using `org-babel-tangle`. This package intentionally does not auto-tangle to allow you to review remediation changes before regenerating the tangled output.

You can then edit these stubs to add configuration (hooks, bindings, etc.).

#### Delete Orphaned Packages

```elisp
M-x package-audit-remediate-delete-purgeable-packages
```

**What it fixes:** Packages in `I \ D` — definitively purgeable installations.

These packages have no dependency path to any retained root. They're safe to remove.

**Example:**

```
These installed packages are orphaned (not retained and not dependencies):
  old-theme-20250101.1200
  experimental-mode-20241215.800

Delete them? (y/n)
```

Selecting `y` removes the package directories from `elpa/`.

#### Clean Ignored Directories

```elisp
M-x package-audit-remediate-delete-ignored-directories
```

**What it fixes:** Non-package directories in `elpa/` (excluding protected directories).

**Example:**

```
These directories in elpa/ are not packages or protected state:
  backup/
  .DS_Store

Delete them? (y/n)
```

Protected directories (`archives`, `gnupg`) are never offered for deletion.

## Batch Use

Run package-audit from the command line or in CI pipelines:

```sh
emacs -Q --batch \
  --directory ~/.config/emacs \
  --load ~/.config/emacs/user-lisp/package-audit/package-audit.el \
  --eval '(package-audit-batch-write "~/audit-reports")'
```

**Arguments:**

- `--directory`: Ensures the package code is in the load path
- `--load`: Loads the package-audit entry point
- `--eval`: Calls `package-audit-batch-write` with output directory

**Output:**

- `~/audit-reports/package-audit.json` — Machine-readable audit data
- `~/audit-reports/package-audit.md` — Human-readable summary

**Note:** Batch mode only generates reports. It does not perform interactive remediation. Use the interactive commands to fix issues identified in the reports.

Use batch mode in pre-commit hooks, CI checks, or scheduled audits to track package configuration drift over time.

## Report Outputs

### Files Generated

| File                 | Format   | Purpose                                             |
|----------------------|----------|-----------------------------------------------------|
| `package-audit.md`   | Markdown | Human-readable summary with tables and explanations |
| `package-audit.json` | JSON     | Machine-readable data for programmatic analysis     |

### Default Location

**Interactive use:** `~/.config/emacs/reports/`

**Batch use:** Specified output directory (e.g., `~/audit-reports/`)

The default location is controlled by `package-audit-report-directory` (see Configuration section).

### Report Contents

#### Markdown Report (`package-audit.md`)

The Markdown report contains:

1. **Summary table**: Counts for all core and derived sets
2. **Explicit init roots missing from selected packages**: `R \ S`
3. **Selected but not explicit in init**: `S \ R`
4. **Selected and Customize-only**: `(S \ R) ∩ C` with variable mappings
5. **Dependency-only retained installs**: `D \ ((R ∪ S) ∩ I)` with dependency chains
6. **Definitively purgeable installs**: `I \ D`
7. **Explicit roots missing from ELPA**: `R \ I`
8. **Selected packages missing from ELPA**: `S \ I`
9. **Ignored non-package ELPA directories**: Extra directories in `elpa/`
10. **Set definitions table**: Reference glossary for all terms and symbols

Each section includes the set expression, JSON key, and explanation of what the packages represent.

#### JSON Report (`package-audit.json`)

The JSON report provides structured data suitable for:

- Programmatic analysis (scripts, CI checks)
- Historical tracking (commit the reports to track drift)
- Integration with other tools

**Top-level structure:**

```json
{
  "repo_dir": "/home/user/.config/emacs",
  "counts": {
    "explicit_init_roots": 42,
    "package_selected_packages": 45,
    "installed_packages": 68,
    "customize_only_selected": 2,
    "dependency_closure": 66,
    ...
  },
  "explicit_init_roots_missing_from_package_selected": ["magit", "company"],
  "selected_not_in_init": ["rainbow-delimiters", "which-key"],
  "selected_and_customize_only": ["custom-theme-pkg"],
  "selected_customize_variables": {
    "custom-theme-pkg": ["custom-theme-load-path", "custom-theme-directory"]
  },
  "retained_dependency_only": ["dash", "s", "f"],
  "retained_dependency_reasons": {
    "dash": "magit",
    "s": "magit",
    "f": "magit"
  },
  "definitively_purgeable": ["old-theme"],
  "explicit_roots_missing_from_elpa": [],
  "selected_missing_from_elpa": [],
  "ignored_non_package_elpa_directories": [],
  "protected_non_package_elpa_directories": ["archives", "gnupg"]
}
```

## Derived Report Sets

The audit computes these sets as **precise set operations** over the core sets. Each section in the reports corresponds to one of these derived sets.

### Explicit Init Roots Missing from Selected Packages

**Set expression:** `R \ S`

**JSON key:** `explicit_init_roots_missing_from_package_selected`

**What it means:** Packages you've declared in your init file with `use-package :ensure t`, but which are **not** in `package-selected-packages`.

**Why it happens:**

- You added a new `use-package` declaration but haven't installed the package yet
- You removed the package from `package-selected-packages` manually
- The package was installed before you started tracking selections

**How to fix:** Use `package-audit-remediate-add-selected-packages` to sync these to `package-selected-packages`.

**Example:**

```elisp
;; In init.el:
(use-package magit :ensure t)

;; But package-selected-packages doesn't include 'magit
;; Result: magit ∈ (R \ S)
```

### Selected But Not Explicit in Init

**Set expression:** `S \ R`

**JSON key:** `selected_not_in_init`

**What it means:** Packages in `package-selected-packages` but **not** declared in your init file.

**Why it happens:**

- You installed a package via `M-x package-install` but never added a `use-package` declaration
- You removed the `use-package` declaration but forgot to remove it from selections
- The package was installed for experimentation and not cleaned up

**How to fix:** Use `package-audit-remediate-add-use-package-stubs` to generate declarations, or manually remove them from `package-selected-packages`.

### Selected and Customize-Only

**Set expression:** `(S \ R) ∩ C`

**JSON key:** `selected_and_customize_only`

**What it means:** Packages in `S \ R` that are justified by Customize variable usage.

**Why it happens:**

- You configured a package entirely through `M-x customize`
- The package doesn't need init.el configuration beyond variable settings
- You prefer Customize over declarative config for certain packages

**How to fix:** This may be intentional. Review whether these packages should have `use-package` declarations or if Customize-only is appropriate.

**Example:**

```elisp
;; In customizations/emacs-custom.el:
(custom-set-variables
 '(package-selected-packages '(modus-themes ...))
 '(modus-themes-bold-constructs t))

;; No (use-package modus-themes ...) in init.el
;; Result: modus-themes ∈ ((S \ R) ∩ C)
```

### Dependency-Only Retained Installs

**Set expression:** `closure((R ∪ S) ∩ I) \ ((R ∪ S) ∩ I)`

Simplified as: `D \ ((R ∪ S) ∩ I)`

**JSON key:** `retained_dependency_only`

**What it means:** Packages that are **only** installed because they're dependencies of your retained packages. You didn't explicitly choose them.

**Why it's useful:**

- Understand what's pulled in transitively
- See which dependencies are shared across multiple packages
- Identify heavy dependency chains

**Example:**

```elisp
;; Your explicit choice:
(use-package magit :ensure t)

;; Magit depends on: dash, git-commit, magit-section, transient, with-editor
;; Those dependencies depend on: compat

;; Result: {dash, git-commit, magit-section, transient, with-editor, compat} ⊆ D \ ((R ∪ S) ∩ I)
```

The report includes `retained_dependency_reasons` showing which explicit package pulled in each dependency.

### Definitively Purgeable Installs

**Set expression:** `I \ closure((R ∪ S) ∩ I)`

Simplified as: `I \ D`

**JSON key:** `definitively_purgeable`

**What it means:** Packages installed but **not** reachable from any retained root. These are orphaned installations with no dependency path to your current configuration.

**Why it happens:**

- You removed a package from init and selections but didn't delete its directory
- You experimented with a package and abandoned it
- Package.el left behind cruft from previous configurations

**How to fix:** Use `package-audit-remediate-delete-purgeable-packages` to remove them.

**Example:**

```
# You used to have:
(use-package old-theme :ensure t)

# But you removed it from init and package-selected-packages
# The directory elpa/old-theme-20250101.1200/ still exists
# Result: old-theme ∈ (I \ D)
```

### Explicit Roots Missing from ELPA

**Set expression:** `R \ I`

**JSON key:** `explicit_roots_missing_from_elpa`

**What it means:** Packages declared in init but **not** installed.

**Why it happens:**

- You added a `use-package` declaration but haven't run `M-x package-install` yet
- The package was uninstalled manually
- Installation failed previously

**How to fix:** Run `M-x package-install` for each missing package, or restart Emacs to trigger automatic installation (if using `use-package` with `:ensure t`).

### Selected Packages Missing from ELPA

**Set expression:** `S \ I`

**JSON key:** `selected_missing_from_elpa`

**What it means:** Packages in `package-selected-packages` but not installed.

**Why it happens:**

- Similar to `R \ I` but based on selections rather than init declarations
- May indicate a broken installation or manual deletion

**How to fix:** Run `M-x package-install` or `M-x package-install-selected-packages`.

### Ignored Non-Package ELPA Directories

**Set expression:** Not a set operation; directory listing of `elpa/` minus package directories and protected directories.

**JSON key:** `ignored_non_package_elpa_directories`

**What it means:** Extra directories or files in `elpa/` that aren't packages and aren't protected package-manager state.

**Why it happens:**

- Backup files (`.DS_Store`, `Thumbs.db`)
- Editor temporary files
- Incomplete downloads or failed installations
- User-created directories

**How to fix:** Use `package-audit-remediate-delete-ignored-directories` to clean them up.

**Protected directories** (`archives`, `gnupg`) are reported separately and never offered for deletion.

## Implementation Notes

The package is structured in five modules:

- **package-audit-parse.el**: Init file parsing (org and elisp formats)
- **package-audit-core.el**: Set construction and audit state logic
- **package-audit-report.el**: Markdown and JSON report generation
- **package-audit-remediate.el**: Prompted remediation helpers
- **package-audit-ui.el**: Interactive entry points and Hydra menu

### Algorithm Overview

1. **Detect repository root** by searching upward for init file + custom file
2. **Parse init file** (org or elisp) to extract `use-package :ensure` declarations → `R`
3. **Read custom file** to extract `package-selected-packages` → `S` and Customize variables → `C`
4. **Scan ELPA directory** to enumerate installed packages → `I`
5. **Compute dependency closure** using package.el metadata → `D`
6. **Compute derived sets** as set operations (difference, intersection, closure)
7. **Generate reports** with normalized, sorted package lists

All set operations use **symbols** (not strings) to ensure consistent comparison. Results are sorted alphabetically for stable, diffable output.

## Package Layout

The package consists of 6 modules:

| File                            | Responsibility                       | Public API                                           |
|---------------------------------|--------------------------------------|------------------------------------------------------|
| `package-audit.el`              | Package entry point                  | Autoloads, requires                                  |
| `package-audit-parse.el`        | Init file parsing                    | Format detection, use-package extraction             |
| `package-audit-core.el`         | Set operations, state construction   | `package-audit-build`                                |
| `package-audit-report.el`       | Report generation                    | `package-audit-render-markdown`, batch commands      |
| `package-audit-remediate.el`    | Remediation commands                 | `package-audit-remediate-*` commands                 |
| `package-audit-ui.el`           | Interactive UI                       | `package-audit-run`, Hydra menu                      |

### Dependencies

- **Emacs 27.1+** (for `user-emacs-directory` and modern package.el)
- **org-mode** (for parsing `init.org` files; already included in Emacs)
- **Hydra** (optional; for interactive menu)

No external package dependencies beyond what's shipped with Emacs.

---

**For questions, issues, or contributions, see the project repository.**
