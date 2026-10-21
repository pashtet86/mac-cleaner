# Changelog

All notable changes are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). Entries are derived from Conventional Commits.

## [Unreleased]

### Added

- Overview with disk usage by category.
- App Caches, Xcode, IDEs and Packages & Toolchains pages driven by `cleanup_rules.json`.
- Simulators: runtimes, devices and orphaned devices via `simctl`.
- Docker: usage and an allowlist of prune actions; volumes are never removed.
- Large Files & Duplicates: size thresholds, sampled + SHA-256 duplicate detection, hard links counted once.
- Trash-only deletion with mandatory preview; scoped path policies.
- Unit tests, git hooks, CI.
