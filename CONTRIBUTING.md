# Contributing

Thanks for helping. This app deletes files, so the bar for correctness and safety is high — but the workflow is
simple.

## Setup

```sh
make setup   # points git at .githooks/
make check   # lint + tests; should pass on a fresh clone
```

You need Xcode 26+ on macOS 26+. There are no other dependencies: `swift-format` ships with Xcode.

## Workflow

1. Open or pick an issue first for anything larger than a small fix.
2. Branch from `main`: `feat/duplicate-finder`, `fix/simctl-parsing`, `docs/readme-setup`.
3. Keep pull requests focused — one feature or fix each.
4. Run `make check` and look at the screens you touched in light and dark mode (`make snapshots`).
5. Open a pull request using the template. CI runs lint, tests, a Release build and checks every commit message.

Pull requests are squash-merged, so the PR title becomes the commit on `main` and must be a Conventional Commit too.

## Commit messages

We use [Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/). The `commit-msg` hook enforces it.

```
<type>(<scope>): <description>

[optional body: what and why, wrapped at 72]

[optional footer: BREAKING CHANGE: …, Closes #123]
```

- Header at most 72 characters, imperative mood, lowercase, no trailing period.
- Blank line between header and body.
- `!` after the type or scope, or a `BREAKING CHANGE:` footer, marks a breaking change.

| Type | Use for |
|---|---|
| `feat` | New user-facing capability |
| `fix` | Bug fix |
| `perf` | Faster or lighter without behavior change |
| `refactor` | Code change that neither fixes nor adds |
| `test` | Tests only |
| `docs` | Documentation only |
| `build` | Xcode project, Makefile, toolchain |
| `ci` | GitHub Actions, hooks |
| `style` | Formatting only |
| `chore` | Anything else (housekeeping) |
| `revert` | Reverting a previous commit |

Scopes: `overview`, `cleanup`, `rules`, `files` (Large Files and Duplicates), `xcode`, `simulators`, `ides`, `packages`, `docker`, `design`,
`core`, `repo`.

```
feat(rules): add Flutter pub cache
fix(files): hash files whose size is not a multiple of the chunk
perf(cleanup): scan rules concurrently
docs: explain Full Disk Access
feat(docker)!: drop the "prune everything" action
```

## Git hooks

Installed by `make setup` from `.githooks/`:

| Hook | Checks |
|---|---|
| `pre-commit` | `swift-format lint --strict` on staged Swift files, JSON validity, no build output or `CLAUDE.local.md`, no files over 2 MB, no secrets or absolute `/Users/<name>/` paths |
| `commit-msg` | Conventional Commits header, length, blank line after the header |
| `pre-push` | `make check` (skip once with `SKIP_TESTS=1 git push`) |

`git commit --no-verify` exists for emergencies; CI runs the same checks, so it only postpones the failure.

## Code style

- `swift-format` with the repo's `.swift-format` (4-space indent, 120 columns). Run `make format`.
- Match the surrounding code: SwiftUI views stay small, state lives in `@Observable` stores, file-system and
  process work lives in `nonisolated` types under `Core/` or the feature folder.
- The target uses `MainActor` default isolation. Mark UI-free types `nonisolated` so they can run off the main
  thread, and do heavy work in detached tasks.
- Colors come from `Theme` only. Each section has one entity color used everywhere (sidebar, cards, charts);
  risk tones are reserved for risk. A new chart palette must pass a color-vision-deficiency check.
- User-facing strings are short and concrete: say what is removed and what happens after.

## Adding a cleanup rule

Add an object to `DevSpace/Resources/cleanup_rules.json`:

```json
{
  "id": "flutter-pub-cache",
  "section": "packages",
  "title": "Flutter pub cache",
  "detail": "Downloaded Dart packages. flutter pub get fetches them again.",
  "symbol": "shippingbox",
  "risk": "safe",
  "paths": ["~/.pub-cache/hosted"],
  "closeApps": ["com.google.android.studio"]
}
```

| Field | |
|---|---|
| `id` | Unique, kebab-case |
| `section` | `apps`, `xcode`, `ides` or `packages` |
| `symbol` | An SF Symbol name |
| `risk` | `safe` (rebuilt automatically, nothing lost), `probablySafe` (rebuilt, but a slow re-download or a minor loss), `review` (the user must decide per item) |
| `paths` | Folders whose **children** become selectable items. Start with `~/` or `$TMPDIR` |
| `namePrefixes` | Optional: only children whose names start with one of these |
| `excludePrefixes` | Optional: children owned by another rule, to avoid double counting |
| `closeApps` | Optional: bundle IDs the review sheet asks the user to quit first |

Before opening the PR:

- [ ] You checked the tool's documentation: the folder is a cache and is safe to delete at the chosen risk level.
- [ ] Nothing user-created lives there (projects, settings, credentials, local-only history).
- [ ] If the folder sits inside another rule's folder (for example `~/Library/Caches/<tool>`), add it to that
      rule's `excludePrefixes`.
- [ ] `make test` passes — `CleanupRuleTests` validates every rule.

## Tests

Swift Testing in `DevSpaceTests/`. Every bug fix gets a regression test; anything that decides **what may be
deleted** (rules, `SafeTrash`, scanners) must be covered. File-system tests work in a temporary sandbox folder — never
in the real home folder.
