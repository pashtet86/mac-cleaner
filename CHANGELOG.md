# Changelog

All notable changes are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). Entries are derived from Conventional Commits.

## [Unreleased]

### Added

- Overview with disk usage by category.
- Environments (Mac Health): installed Node, JDKs, Python, Ruby, Go, Gradle, Docker, Homebrew and more, graded
  against endoflife.date and nodejs.org security releases, with copyable update or removal commands.
- Files Inspector: drill-down treemap colored by deletion safety, with reasons; standard home folders can never be trashed.
- Sections and rules appear only when something was found on this Mac.
- CPU/SSD temperature and thermal state in the sidebar; "safe to clean" headline on Overview.
- App Caches, Xcode, IDEs and Packages & Toolchains pages driven by `cleanup_rules.json`.
- Simulators: runtimes, devices and orphaned devices via `simctl`.
- Docker: usage and an allowlist of prune actions; volumes are never removed.
- Large Files: size thresholds and file-kind breakdown.
- Duplicates: sampled + SHA-256 detection, hard links counted once, at least one copy always kept.
- Trash-only deletion with mandatory preview; scoped path policies.
- App icon; renamed to Disk Cleaner.
- `make dmg`: universal DMG, ad-hoc or Developer ID signed and notarized.
- Opt-in anonymous statistics: Cloudflare Worker + D1 in `telemetry/`, consent on Overview, toggle in Settings; off
  unless the build sets `TELEMETRY_ENDPOINT`.
- Applications: installed apps with size, last use, owner on multi-user Macs, and removal.
- Fan speed and disk fill in the sidebar.
- Security (Mac Health): SIP, Gatekeeper, FileVault and every launch agent and daemon with its signer; flags
  programs started from world-writable folders, unsigned code and leftovers of removed apps.
- Network (Mac Health): firewall and stealth mode, listening ports split into open-to-network and this-Mac-only.
- Overview alerts and sidebar badges for Security and Network findings.
- Automatic updates with Sparkle: daily background check, signed appcast, "Check for Updates" menu and Settings;
  `scripts/release.sh` publishes a version end to end.
- App version in the sidebar and Settings.
- Unit tests, git hooks, CI.
