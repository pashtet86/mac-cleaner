# Security

Disk Cleaner deletes files and runs developer tools, so a bug can cost someone their data. We treat the following
as security issues:

- anything that removes, moves or modifies files outside what the preview showed;
- a way to make a rule, scanner or tool invocation reach paths outside the allowed scope;
- command or argument injection into `ProcessRunner`;
- reading cloud folders, Keychains, Mail or Messages.

## Reporting

Please **do not open a public issue**. Use GitHub's private vulnerability reporting (Security → Report a
vulnerability) with steps to reproduce, the macOS version and the impact. Remove personal file names and machine
details from anything you attach.

You will get an acknowledgement within a few days. Fixes ship as a patch release with credit if you want it.

## Design principles

- Deletion only through `SafeTrash` → Trash, after an explicit preview.
- Path allowlist plus deny list, checked again at deletion time after resolving symlinks.
- External tools only with argument arrays and a fixed set of operations; identifiers validated.
- No network access by default. Builds made with a `TELEMETRY_ENDPOINT` can send opt-in, anonymous statistics
  (random install ID, versions, architecture, bytes cleaned per section) to our own Worker in `telemetry/` — never
  file names, paths, IP addresses, or the Mac's or user's name. The user decides on first launch and can change it in
  Settings.
- Future privileged operations (root) go through a separate `SMAppService` helper with an XPC allowlist and
  code-signature checks on the client — never by running scripts with `sudo`.
