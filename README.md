# DevSpace

A native macOS app that frees disk space safely — built for developers whose Macs fill up with Xcode
build products, simulators, SDKs, package caches and Docker images.

Everything it removes goes to the **Trash** after a **preview**, and every rule says what it deletes,
how risky that is and what happens next.

## Features

| Module | What it does |
|---|---|
| **Overview** | Disk usage split by category, with what is safe to clean right now |
| **Files Inspector** | A treemap of any folder in your home: open folders to go deeper, see sizes, select files and folders to remove. Every tile is colored by how safe it is to delete — rebuildable, likely safe, review, your files, protected — with the reason |
| **App Caches** | `~/Library/Caches`, logs, Slack and updater downloads |
| **Large Files** | Files over 100 MB / 500 MB / 1 GB, grouped into videos, installers & disk images, archives |
| **Duplicates** | Byte-identical copies over 1 / 10 / 100 MB (size → sampled hash → SHA-256); hard links count once |
| **Xcode** | DerivedData, previews, device support symbols, archives |
| **Simulators** | Runtimes and devices from `simctl`, including orphaned devices of removed runtimes |
| **IDEs** | Android Studio and the Android SDK (NDK, system images, build tools), JetBrains IDEs, VS Code / Cursor / Windsurf, Zed |
| **Packages & Toolchains** | npm, Yarn, Bun, pnpm, Metro, Expo, CocoaPods, Gradle, SwiftPM, Homebrew, Cargo, rustup, Maven, Go, pip, uv and more |
| **Docker** | Images, containers and build cache via the Docker CLI — volumes are never removed |
| **Temperatures** | Hottest CPU core, SSD and the macOS thermal state, pinned to the bottom of the sidebar |

Coming next: security audit (launch agents, login items, code signatures) and network (listening ports, firewall).

## Safety model

- **Trash, not `rm`.** Deletion goes through `SafeTrash`, which uses `FileManager.trashItem`. You can put
  anything back until you empty the Trash.
- **Preview first.** Nothing is removed without a review sheet that lists the items and their sizes.
- **Scoped paths.** Cache rules can only touch `~` and `$TMPDIR`, and never Documents, Desktop, Pictures,
  Movies, Music, Keychains, Mail, Messages or cloud folders. Files you pick by hand may live in personal folders
  but never in `~/Library`.
- **No cloud or media-library traversal.** `~/Library/CloudStorage` and `~/Library/Mobile Documents` are never
  read, so online-only files are not downloaded. File scans also skip `~/Music` and `~/Movies/TV` — the Music and
  TV libraries are behind the "Media & Apple Music" privacy prompt and hold no developer data.
- **No shell.** External tools (`xcrun simctl`, `docker`) run through `ProcessRunner` with argument arrays, from a
  fixed allowlist of operations; identifiers are validated first.
- **Risk levels.** Every rule is `safe`, `probablySafe` or `review`. Only `safe` items are preselected.

Temperatures come from IOKit's HID sensor service, a private API (the one Stats and iStat Menus use). It is loaded at
runtime; if a macOS update removes it, the sidebar falls back to the public thermal state.

## Requirements

- macOS 26 or later
- Xcode 26 or later (to build)

The app is not sandboxed — the App Store sandbox cannot read other apps' caches — so it is distributed outside the
App Store. For complete results grant it **Full Disk Access** in System Settings → Privacy & Security; without it
macOS asks for Desktop, Documents and Downloads access the first time a scan reaches them.

## Getting started

```sh
git clone <repo-url> devspace
cd devspace
make setup   # installs git hooks
make run     # builds and launches the Debug app
```

Or open `DevSpace.xcodeproj` in Xcode and press ⌘R.

| Command | |
|---|---|
| `make build` / `make release` | Debug / Release build into `build/DerivedData` |
| `make test` | Unit tests (Swift Testing) |
| `make lint` / `make format` | `swift-format` check / fix, JSON validation |
| `make check` | Everything CI runs |
| `make snapshots` | Renders every screen in light and dark mode to `build/snapshots` |

## Sharing a test build

```sh
make dmg   # → build/dist/DevSpace-<version>.dmg, universal (Apple Silicon + Intel)
```

Testers need macOS 26 or later. They open the DMG and drag **DevSpace** onto **Applications**.

**Ad-hoc build (default).** It is not signed with a Developer ID, so Gatekeeper blocks the first launch. The tester
allows it once:

1. Open DevSpace from Applications. macOS says it cannot verify the developer — click **Done**.
2. Open System Settings → Privacy & Security, scroll to *Security*, click **Open Anyway** next to DevSpace, and
   confirm with your password.

Share the SHA-256 printed by `make dmg` so the tester can check the download with `shasum -a 256 <file>`.

**Signed and notarized build.** With a *Developer ID Application* certificate (paid Apple Developer Program), the app
opens without warnings:

```sh
xcrun notarytool store-credentials devspace-notary --apple-id <apple-id> --team-id <TEAMID>   # once
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=devspace-notary make dmg
```

`store-credentials` asks for an app-specific password and keeps it in your keychain; never put it in the repository.

## Project structure

```
DevSpace/
  App/            Entry point, navigation (AppSection), debug snapshots
  Design/         Theme tokens (colors, type), shared components
  Core/           ProcessRunner, DiskUsage, SafeTrash — UI-free, nonisolated
  Features/
    Cleanup/      Rule model, scanner, store and pages for every rule-based section
    Files/        Large Files and Duplicates pages, shared scanner
    Simulators/   simctl integration
    Docker/       Docker CLI integration
    Overview/
  Resources/
    cleanup_rules.json   Every cache rule: paths, risk, description, apps to quit
DevSpaceTests/       Unit tests
scripts/                 Read-only shell audits the app grew out of
```

Folders are synchronized with the Xcode project: add a file on disk and it is part of the target.

## Adding a cleanup rule

Most contributions are a new entry in `DevSpace/Resources/cleanup_rules.json`. See
[CONTRIBUTING.md](CONTRIBUTING.md#adding-a-cleanup-rule) for the fields and the safety checklist.

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) — commits follow
[Conventional Commits](https://www.conventionalcommits.org), and git hooks check formatting, commit messages and
secrets locally. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

Not chosen yet.
