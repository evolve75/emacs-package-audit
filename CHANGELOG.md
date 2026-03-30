# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
