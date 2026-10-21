## What and why

<!-- One or two sentences. Link the issue: Closes #123 -->

## How it was tested

<!-- Commands you ran, what you clicked through. -->

- [ ] `make check` passes (lint + tests)
- [ ] Checked the affected screens in light **and** dark mode (`make snapshots` helps)

## Safety checklist

Only when the change can delete, move or modify files, or runs an external tool:

- [ ] Deletion goes through `SafeTrash` (moves to the Trash, never `rm`)
- [ ] The user sees a preview with sizes before anything is removed
- [ ] New paths stay inside `~` or `$TMPDIR` and never touch personal folders or cloud folders
- [ ] External tools run through `ProcessRunner` with an argument array — no shell strings, no interpolation
- [ ] Identifiers passed to tools are validated (UUIDs, fixed allowlist of actions)
- [ ] Added or updated tests for the rule or operation

## Screenshots

<!-- Before / after, light and dark. Crop out personal file names. -->
