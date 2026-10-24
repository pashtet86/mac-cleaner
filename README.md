# Disk Cleaner

A native macOS app that frees disk space safely — built for developers whose Macs fill up with Xcode
build products, simulators, SDKs, package caches and Docker images.

Everything it removes goes to the **Trash** after a **preview**, and every rule says what it deletes,
how risky that is and what happens next.

## Features

| Module | What it does |
|---|---|
| **Overview** | Disk usage split by category, with what is safe to clean right now |
| **Files Inspector** | A treemap of any folder in your home: open folders to go deeper, see sizes, select files and folders to remove. Every tile is colored by how safe it is to delete — rebuildable, likely safe, review, your files, protected — with the reason |
| **Environments** | Developer tools graded against official release schedules — update now, soon, when convenient, up to date — with the exact command to copy |
| **App Caches** | `~/Library/Caches`, logs, Slack and updater downloads |
| **Large Files** | Files over 100 MB / 500 MB / 1 GB, grouped into videos, installers & disk images, archives |
| **Duplicates** | Byte-identical copies over 1 / 10 / 100 MB (size → sampled hash → SHA-256); hard links count once |
| **Xcode** | DerivedData, previews, device support symbols, archives |
| **Simulators** | Runtimes and devices from `simctl`, including orphaned devices of removed runtimes |
| **IDEs** | Android Studio and the Android SDK (NDK, system images, build tools), JetBrains IDEs, VS Code / Cursor / Windsurf, Zed |
| **Packages & Toolchains** | npm, Yarn, Bun, pnpm, Metro, Expo, CocoaPods, Gradle, SwiftPM, Homebrew, Cargo, rustup, Maven, Go, pip, uv and more |
| **Docker** | Images, containers and build cache via the Docker CLI — volumes are never removed |
| **Security** | SIP, Gatekeeper, FileVault; every launch agent and daemon with who signed it; leftovers and programs started from folders anyone can write to |
| **Network** | Firewall and stealth mode; which apps accept connections from other devices and which only from this Mac |
| **Temperatures** | Hottest CPU core, SSD and the macOS thermal state, pinned to the bottom of the sidebar |
| **Updates** | Checks once a day (Sparkle); a quiet "Update to x.y" line in the sidebar, signed updates only |

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
git clone <repo-url> macdiskcleaner
cd macdiskcleaner
make setup   # installs git hooks
make run     # builds and launches the Debug app
```

Or open `MacDiskCleaner.xcodeproj` in Xcode and press ⌘R.

| Command | |
|---|---|
| `make build` / `make release` | Debug / Release build into `build/DerivedData` |
| `make test` | Unit tests (Swift Testing) |
| `make lint` / `make format` | `swift-format` check / fix, JSON validation |
| `make check` | Everything CI runs |
| `make snapshots` | Renders every screen in light and dark mode to `build/snapshots` |

## Sharing a test build

```sh
make dmg   # → build/dist/DiskCleaner-<version>.dmg, universal (Apple Silicon + Intel)
```

Testers need macOS 26 or later. They open the DMG and drag **Disk Cleaner** onto **Applications**.

**Ad-hoc build (default).** It is not signed with a Developer ID, so Gatekeeper blocks the first launch. The tester
allows it once:

1. Open Disk Cleaner from Applications. macOS says it cannot verify the developer — click **Done**.
2. Open System Settings → Privacy & Security, scroll to *Security*, click **Open Anyway** next to Disk Cleaner, and
   confirm with your password.

Share the SHA-256 printed by `make dmg` so the tester can check the download with `shasum -a 256 <file>`.

**Signed and notarized build.** Release builds are signed with the team's *Developer ID Application* certificate.
Store notarization credentials once (it asks for an app-specific password from account.apple.com and keeps it in
the keychain), then build:

```sh
xcrun notarytool store-credentials macdiskcleaner-notary --apple-id <apple-id> --team-id <TEAMID>   # once
TELEMETRY_ENDPOINT=https://… make dmg-signed
```

`store-credentials` asks for an app-specific password and keeps it in your keychain; never put it in the repository.

## Releasing an update

Installed copies check `https://downloads.machealthapps.com/appcast.xml` once a day with
[Sparkle](https://sparkle-project.org). An update is installed only if its archive carries a valid EdDSA signature
for the public key in `Config/MacDiskCleaner-Info.plist` **and** the new app is signed with the same Developer ID.

One-time setup on the release Mac:

1. Notarization credentials — see above.
2. The update signing key, kept in the login Keychain:
   `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account com.machealthapps.diskcleaner`
   (prints the public key; it is already in Info.plist). **Back up the private key** with
   `generate_keys --account com.machealthapps.diskcleaner -x <file>` and store it in a password manager — without it
   no installed copy will accept another update.
3. `npx wrangler login` with access to the `mac-health-app` R2 bucket.

Each release:

```sh
# 1. Move the Unreleased notes in CHANGELOG.md under "## [1.1] - <date>"
scripts/release.sh 1.1
# 2. Commit the version bump and tag it (the script prints the commands)
```

`release.sh` sets the version and build number, builds a notarized DMG, turns the CHANGELOG section into release
notes, signs the DMG and updates the appcast, then — after you confirm — uploads `DiskCleaner-1.1.dmg`,
`DiskCleaner.dmg` (always the latest, for the website) and `appcast.xml` last. Users can turn automatic checks or
automatic installs off in Settings, or use **Disk Cleaner → Check for Updates**. Debug builds never update.

## Anonymous statistics (optional)

Off by default — a plain build has no endpoint and never touches the network. To learn how many people install
and use Disk Cleaner, deploy the Cloudflare Worker in [`telemetry/`](telemetry/README.md) and build with its URL:

```sh
TELEMETRY_ENDPOINT=https://devspace-telemetry.<account>.workers.dev make dmg
```

Users are asked once on first launch and can change their mind in Settings (⌘,). Only a random install ID, app and
macOS versions, architecture and bytes cleaned per section are sent.

## Project structure

```
MacDiskCleaner/
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
MacDiskCleanerTests/       Unit tests
scripts/                 Read-only shell audits the app grew out of
```

Folders are synchronized with the Xcode project: add a file on disk and it is part of the target.

## Adding a cleanup rule

Most contributions are a new entry in `MacDiskCleaner/Resources/cleanup_rules.json`. See
[CONTRIBUTING.md](CONTRIBUTING.md#adding-a-cleanup-rule) for the fields and the safety checklist.

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) — commits follow
[Conventional Commits](https://www.conventionalcommits.org), and git hooks check formatting, commit messages and
secrets locally. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

Not chosen yet.
