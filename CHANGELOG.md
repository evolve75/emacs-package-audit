# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.4] - 2026-03-31

### Added
- Comprehensive test suite with 114 tests covering all modules
- Test infrastructure with dynamic fixture generation and mock ELPA directories
- Integration tests for end-to-end workflows (fresh install, migration, cleanup, round-trip)
- UI tests for entry points and interactive commands
- Report generation tests for JSON and Markdown output
- Remediation operation tests with file I/O validation
- Core set operation tests (union, difference, intersection)
- Parsing tests for init.org and init.el file detection and use-package extraction
- Dependency closure computation tests
- State building integration tests
- Makefile targets for granular test execution (test-parse, test-core, test-report, test-remediate, test-ui, test-integration)
- GitHub Actions CI integration running tests across Emacs versions 27.1 through snapshot
- Tests workflow status badge in README

## [1.0.3] - 2026-03-30

### Changed
- Markdown report now only displays "Fix:" instructions when there are actual packages needing resolution in that category

## [1.0.2] - 2026-03-30

### Fixed
- Packages installed via `:vc` keyword are now correctly recognized as declared packages (not falsely marked as purgeable)

## [1.0.1] - 2026-03-30

### Fixed
- Custom file is now optional; falls back to live `package-selected-packages` variable for fresh Emacs installations
- Byte-compilation warnings for org-element functions (added proper declare-function declarations)
- Hydra byte-compilation error (wrapped defhydra in eval form)
- Package-lint warning about with-eval-after-load usage
- GitHub Actions CI workflow byte-compilation failures
- CHANGELOG extraction in release workflow (switched from awk to sed)

### Changed
- Improved markdown report template with clearer language and actionable fix instructions
- Moved MELPA availability note to start of Installation section in README
- Enhanced README documentation for edge cases and troubleshooting

## [1.0.0] - 2026-03-30

### Added
- Initial public release
- Set-theoretic package audit analysis using R, S, I, C, and D sets
- JSON and Markdown report generation
- Four remediation commands with confirmation:
  - Add missing selections to `package-selected-packages`
  - Generate `use-package` stubs for selected-but-undeclared packages
  - Delete definitively purgeable ELPA installations
  - Clean ignored non-package directories from ELPA tree
- Support for both init.org and init.el file formats
- Automatic init file detection (prefers init.org, falls back to user-init-file or init.el)
- Optional Hydra integration for interactive menu
- Comprehensive README with set theory documentation
- GPL-3.0-or-later license
- Installation instructions for use-package with :vc keyword
