# DevSpace — notes for Claude Code

Native SwiftUI app (macOS 26+) that frees disk space safely. See README.md for features and CONTRIBUTING.md for
conventions. Machine-specific notes (audit results, decisions about this Mac) live in `CLAUDE.local.md`, which is
gitignored — never copy their contents into tracked files.

## Commands

- `make build` / `make run` / `make test` / `make lint` / `make format` / `make check`
- `make snapshots` renders every screen (light + dark) to `build/snapshots` from inside the app — use it to check UI
  without Screen Recording permission. `-snapshotFilesRoot <dir>` also runs a Large Files scan on that folder first.

## Invariants — do not break

- Nothing is deleted without explicit user confirmation and a preview of what and how much.
- Deletion only via `SafeTrash` (Trash), with the right `Policy`: `.caches` for rules, `.userFiles` for files the
  user picked. Never `rm -rf`, never `removeItem` on user data.
- Never traverse `~/Library/CloudStorage` or `~/Library/Mobile Documents`.
- External tools only via `ProcessRunner` with argument arrays and a fixed allowlist; validate identifiers.
- No personal data (file names, machine names, IPs, absolute `/Users/<name>` paths) in tracked files, tests or
  screenshots committed to the repo.
- `sudo` only for single, specific commands the user approves; root features go through a future privileged helper.

## Architecture

- `App/AppSection` drives navigation; each section has one entity color (`tint`) used in the sidebar, cards and
  charts. Risk tones (`sage`/`sand`/`clay`) are reserved for risk.
- Rule-based pages (`apps`, `xcode`, `ides`, `packages`) are data in `Resources/cleanup_rules.json`, rendered by
  `RulesPage`, scanned by `CleanupStore`.
- Default actor isolation is `MainActor`; UI-free types are `nonisolated` and heavy work runs in detached tasks.
  Forward cancellation explicitly to detached work.
- New chart colors must pass the data-viz palette validator for light (`#FFFFFF`) and dark (`#1E2024`) surfaces.

- `Core/ThermalSensors` uses private IOKit HID API via `dlsym`: keep every symbol optional and keep the
  `IOHIDEventSystemClient` alive as long as its services (released client → reads hang).

- Telemetry (`Core/Telemetry`, `telemetry/`) is opt-in and anonymous. Never add fields with paths, file names,
  host or user names; the Worker's strict Zod schema must reject anything not listed.

## Workflow

- Conventional Commits (enforced by `.githooks/commit-msg`). Commit only when asked.
- Every bug fix gets a regression test; tests touching the file system use a temporary sandbox folder.
