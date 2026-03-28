# package-audit

`package-audit` analyzes the relationship between declared package
intent, selected packages, installed packages, and dependency closure.
It is designed to be useful both as an interactive Emacs package and
as a batch report generator.

This directory keeps the package implementation and its package-facing
documentation together.

## Package Layout

- `package-audit.el`: package entry file
- `package-audit-core.el`: set construction and audit-state logic
- `package-audit-report.el`: Markdown/JSON report generation
- `package-audit-remediate.el`: prompted remediation helpers
- `package-audit-ui.el`: interactive entrypoints and optional Hydra menu

## Core Sets

- `R`: explicit third-party package roots inferred from `<init-source-file>`
- `S`: `package-selected-packages` from `<custom-state-file>`
- `I`: installed package-manager packages
- `C`: selected packages that still own Customize-only variables
- `D`: dependency closure of retained roots

`R` is not “all `use-package` forms”. It is the normalized third-party
package-root set produced by `package-audit--third-party-root-for-use-package`.
That means built-ins and repo-local packages are excluded, literal
`:ensure t` keeps the package symbol, and symbolic `:ensure` records the
ensured package name.

## Derived Report Sets

The audit reports these set differences and intersections directly:

| Meaning                                            | Expression                             | JSON key                                            |
|----------------------------------------------------|----------------------------------------|-----------------------------------------------------|
| Explicit init roots missing from selected packages | `R \ S`                                | `explicit_init_roots_missing_from_package_selected` |
| Selected packages not explicit in init             | `S \ R`                                | `selected_not_in_init`                              |
| Selected packages justified only by Customize      | `(S \ R) ∩ C`                          | `selected_and_customize_only`                       |
| Dependency-only retained installs                  | `closure((R ∪ S) ∩ I) \ ((R ∪ S) ∩ I)` | `retained_dependency_only`                          |
| Definitively purgeable installs                    | `I \ closure((R ∪ S) ∩ I)`             | `definitively_purgeable`                            |
| Explicit roots missing from ELPA                   | `R \ I`                                | `explicit_roots_missing_from_elpa`                  |
| Selected packages missing from ELPA                | `S \ I`                                | `selected_missing_from_elpa`                        |

The audit also emits `selected_customize_variables`, which is a
package-to-variable map rather than a set.

The Markdown report headings include these same expressions so the
human-readable output maps directly back to the set model.

`ignored_non_package_elpa_directories` is intentionally outside the set
algebra above. It reports extra top-level directories in the ELPA tree
that are not installed packages. Protected package-manager state
directories such as `gnupg` are reported separately and are never
offered for deletion.

## Intended Invariants

- Intent and selection should stay aligned: ideally `R = S`
- Installed packages should be justified by retained roots or their dependencies
- Anything in `I \ closure((R ∪ S) ∩ I)` is safe to review as cleanup candidate

The model intentionally allows temporary drift so the reports can show
what needs reconciliation instead of assuming a perfect state.

## Interactive Use

Load the package and invoke `M-x package-audit-run`.

That command:

- computes the current audit
- writes JSON and Markdown reports
- opens the generated Markdown report
- caches the latest audit snapshot for follow-up commands
- shows a Hydra menu when Hydra is available

Public interactive commands:

- `package-audit-run`
- `package-audit-refresh`
- `package-audit-open-markdown-report`
- `package-audit-open-json-report`
- `package-audit-remediate-add-selected-packages`
- `package-audit-remediate-add-use-package-stubs`
- `package-audit-remediate-delete-purgeable-packages`
- `package-audit-remediate-delete-ignored-directories`
- `package-audit-show-operations`

Remediation commands use prompted apply by default. They operate from
the latest audit snapshot and regenerate the reports after successful
changes.

## Batch Use

Use a native Emacs batch invocation when running the package outside a
repository-specific wrapper:

```sh
emacs -Q --batch \
  --directory <repo-root> \
  --load <repo-root>/user-lisp/package-audit/package-audit.el \
  --eval '(package-audit-batch-write "<output-dir>")'
```

This writes `package-audit.json` and `package-audit.md` into the chosen
output directory.

## Implementation Notes

- Parse `<init-source-file>` source blocks to build `R`
- Read `custom-set-variables` to build `S` and the custom-variable inventory
- Initialize package metadata from `<package-install-dir>` to build `I` and the dependency graph
- Compute report sections as normalized set operations over those core sets

## Report Outputs

- `package-audit.md` is the human-readable summary
- `package-audit.json` is the machine-readable snapshot for follow-up checks

## Packaging Notes

- Public interactive commands are marked with autoload cookies in source
- The package uses source metadata and split modules suitable for
  generated package/autoload artifacts
- Generated autoload or package archive files are build outputs rather
  than committed source files
