# Mac Optimizer

A native macOS app that frees disk space safely — built for developers whose Macs fill up with Xcode
build products, simulators, SDKs, package caches and Docker images.

Everything it removes goes to the **Trash** after a **preview**, and every rule says what it deletes,
how risky that is and what happens next.

## Features

| Module | What it does |
|---|---|
| **Overview** | Disk usage split by category, with what is safe to clean right now |
| **App Caches** | `~/Library/Caches`, logs, Slack and updater downloads |
| **Large Files & Duplicates** | Files over 100 MB / 500 MB / 1 GB and byte-identical copies (size → sampled hash → SHA-256) |
| **Xcode** | DerivedData, previews, device support symbols, archives |
| **Simulators** | Runtimes and devices from `simctl`, including orphaned devices of removed runtimes |
| **IDEs** | Android Studio and the Android SDK (NDK, system images, build tools), JetBrains IDEs, VS Code / Cursor / Windsurf, Zed |
| **Packages & Toolchains** | npm, Yarn, Bun, pnpm, Metro, Expo, CocoaPods, Gradle, SwiftPM, Homebrew, Cargo, rustup, Maven, Go, pip, uv and more |
| **Docker** | Images, containers and build cache via the Docker CLI — volumes are never removed |

Coming next: security audit (launch agents, login items, code signatures) and network (listening ports, firewall).

## Safety model

- **Trash, not `rm`.** Deletion goes through `SafeTrash`, which uses `FileManager.trashItem`. You can put
  anything back until you empty the Trash.
- **Preview first.** Nothing is removed without a review sheet that lists the items and their sizes.
- **Scoped paths.** Cache rules can only touch `~` and `$TMPDIR`, and never Documents, Desktop, Pictures,
  Movies, Music, Keychains, Mail, Messages or cloud folders. Files you pick by hand may live in personal folders
  but never in `~/Library`.
- **No cloud traversal.** `~/Library/CloudStorage` and `~/Library/Mobile Documents` are never read, so
  online-only files are not downloaded.
- **No shell.** External tools (`xcrun simctl`, `docker`) run through `ProcessRunner` with argument arrays, from a
  fixed allowlist of operations; identifiers are validated first.
- **Risk levels.** Every rule is `safe`, `probablySafe` or `review`. Only `safe` items are preselected.

## Requirements

- macOS 26 or later
- Xcode 26 or later (to build)

The app is not sandboxed — the App Store sandbox cannot read other apps' caches — so it is distributed outside the
App Store. For complete results grant it **Full Disk Access** in System Settings → Privacy & Security; without it
macOS asks for Desktop, Documents and Downloads access the first time a scan reaches them.

## Getting started

```sh
git clone <repo-url> mac-optimizer
cd mac-optimizer
make setup   # installs git hooks
make run     # builds and launches the Debug app
```

Or open `MacOptimizer.xcodeproj` in Xcode and press ⌘R.

| Command | |
|---|---|
| `make build` / `make release` | Debug / Release build into `build/DerivedData` |
| `make test` | Unit tests (Swift Testing) |
| `make lint` / `make format` | `swift-format` check / fix, JSON validation |
| `make check` | Everything CI runs |
| `make snapshots` | Renders every screen in light and dark mode to `build/snapshots` |

## Project structure

```
MacOptimizer/
  App/            Entry point, navigation (AppSection), debug snapshots
  Design/         Theme tokens (colors, type), shared components
  Core/           ProcessRunner, DiskUsage, SafeTrash — UI-free, nonisolated
  Features/
    Cleanup/      Rule model, scanner, store and pages for every rule-based section
    Files/        Large files and duplicates
    Simulators/   simctl integration
    Docker/       Docker CLI integration
    Overview/
  Resources/
    cleanup_rules.json   Every cache rule: paths, risk, description, apps to quit
MacOptimizerTests/       Unit tests
scripts/                 Read-only shell audits the app grew out of
```

Folders are synchronized with the Xcode project: add a file on disk and it is part of the target.

## Adding a cleanup rule

Most contributions are a new entry in `MacOptimizer/Resources/cleanup_rules.json`. See
[CONTRIBUTING.md](CONTRIBUTING.md#adding-a-cleanup-rule) for the fields and the safety checklist.

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) — commits follow
[Conventional Commits](https://www.conventionalcommits.org), and git hooks check formatting, commit messages and
secrets locally. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

Not chosen yet.
