# dirsync: one-way directory sync CLI

Build `dirsync`, a command-line tool that makes a TARGET directory mirror a SOURCE directory. It is one-way: SOURCE is never modified. Use Python 3.11+ and the standard library only (no third-party packages at runtime; pytest is fine for your own tests).

## Entry point

Run from the repository root:

```
python3 -m dirsync SOURCE TARGET [--config FILE] [--dry-run] [--json] [--delete] [--checksum]
```

The package must be importable as `dirsync` from the repository root (a `dirsync/` package directory with a `__main__.py`). Structure the code inside it however you like.

| Flag | Meaning |
|---|---|
| `--config FILE` | Load include/exclude patterns from a JSON config file (see Config). |
| `--dry-run` | Compute and report every change, but write, create or delete nothing. |
| `--json` | Print the change report as JSON (see Report) instead of text. |
| `--delete` | Also remove target entries that do not exist in SOURCE. |
| `--checksum` | Detect changed files by comparing contents instead of size and mtime. |

## What gets synced

- Both trees are walked recursively. Paths in reports are relative to SOURCE or TARGET, use `/` as the separator, and have no leading `./`.
- Entries are regular files, symbolic links, and directories. Anything else in SOURCE (FIFOs, sockets, device files) is not copied; it is reported under `skipped` with reason `unsupported`.
- **Regular files** are copied with their contents, permission bits and modification time. After a successful sync, running dirsync again with no changes in SOURCE must report no changes.
- **Symbolic links** are copied as links: the target gets a symlink with exactly the same link text (as returned by `os.readlink`). dirsync never follows symlinks, in SOURCE or in TARGET. It never reads, writes or deletes anything outside the SOURCE and TARGET trees. A symlink to a directory is copied as a symlink and is not descended into. Dangling symlinks are copied too.
- **Directories** are created in TARGET as needed to hold synced entries. Empty source directories do not need to be reproduced. Directories themselves never appear in the report.
- TARGET is created (with parents) if it does not exist, except in `--dry-run`.
- SOURCE and TARGET may themselves be given as symlinks to directories, or as relative paths; they are resolved first.
- SOURCE and TARGET must not overlap. If, after resolving symlinks and `..`, they are the same directory or either one is inside the other, dirsync exits 2 without touching anything.

## Change detection

For each in-scope SOURCE file or symlink, compare it with the entry at the same relative path in TARGET:

- Missing in TARGET: **created**.
- Present but a different type (for example a regular file in SOURCE and a symlink or directory in TARGET): **updated**, reason `type`. The target entry is replaced; a target directory in that position is removed with its contents, which are not listed separately.
- Both symlinks, different link text: **updated**, reason `link`. Symlink mtimes are ignored.
- Both regular files, default mode: **updated** with reason `size` if the sizes differ, otherwise reason `mtime` if the modification times differ (compared at 1 millisecond precision). The target is updated regardless of which one is newer.
- Both regular files, `--checksum` mode: **updated** with reason `content` if the contents differ (in this mode the reason is always `content`, even when the sizes differ). Files with identical contents are unchanged, whatever their mtimes.
- Otherwise the entry is unchanged and is only counted.

If SOURCE has a directory where TARGET has a non-directory (file, symlink or other), that target entry is removed and listed under **deleted**, even without `--delete`, and a real directory is created in its place.

With `--delete`, every in-scope TARGET file, symlink or other non-directory whose relative path does not exist in SOURCE is removed and listed under **deleted**. Afterwards, any TARGET directory that is now empty, does not exist as a directory in SOURCE, and is not excluded is removed too (silently). Without `--delete`, extra target entries are left alone and not reported.

## Config

`--config FILE` names a JSON file containing one object with these optional keys:

```json
{
  "include": ["docs/**", "*.md"],
  "exclude": ["*.tmp", ".git", "build/cache"]
}
```

Each value must be a list of non-empty strings. Any other key, a value of the wrong type, a missing or unreadable file, or invalid JSON is a config error (exit 2).

**Pattern syntax.** Patterns match relative paths with `/` separators.
- `*` matches any run of characters except `/`. `?` matches one character except `/`. `[abc]`, `[a-z]` and `[!abc]` are character classes (they never match `/`).
- `**` as a whole path segment matches zero or more whole segments (`docs/**/*.md` matches `docs/a.md` and `docs/x/y/a.md`).
- A leading or trailing `/` in a pattern is ignored.
- A pattern **without** `/` is tested against each single component of the path. `*.tmp` matches `a.tmp` and `x/y/a.tmp`; `.git` matches `.git/config` and `sub/.git/HEAD`.
- A pattern **with** `/` is tested against the full relative path and against each of its ancestor directory paths. `build/cache` matches `build/cache` and `build/cache/x/y.o`, but not `src/build/cache`.

**Scope.** A path is excluded if it matches any `exclude` pattern. If `include` is non-empty, a path is included only if it matches at least one `include` pattern; if `include` is missing or empty, everything is included. `exclude` wins over `include`. A path is **in scope** if it is included and not excluded. The same rules apply to paths in SOURCE and in TARGET. Out-of-scope paths are outside dirsync's job entirely: they are never copied, updated or deleted, and never reported.

## Errors and partial failure

- If one entry fails (for example, a source file that cannot be read, or a target path that cannot be written or removed), dirsync reports it under `skipped` with reason `error`, leaves that path alone, and carries on with the rest of the run.
- If a source directory cannot be listed, it is reported under `skipped` with reason `error`, and nothing under that path in TARGET is deleted.
- A dry run does not open source files, except to compare contents in `--checksum` mode. So a dry run may list as created a file that the real run later reports as an error.

## Exit codes (frozen)

| Code | Meaning |
|---|---|
| 0 | Success: TARGET is in sync, or all changes were applied (or, with `--dry-run`, computed). `unsupported` skips do not affect the exit code. |
| 1 | Partial failure: the run completed but at least one `skipped` entry has reason `error`. |
| 2 | Usage or config error, detected before any change is made: bad arguments, SOURCE missing, not a directory or not listable, TARGET exists but is not a directory, SOURCE and TARGET overlap, invalid config. |

For exit 2 caused by anything other than argument parsing, print one line starting with `dirsync: error: ` to stderr and print nothing to stdout. Argument-parsing errors may use the standard argparse usage message.

## Report

Changes are always grouped into four lists: `created`, `updated`, `deleted`, `skipped`. Within each list, entries are sorted by their `path` string in plain code-point order (Python's default `str` ordering applied to the whole relative path).

### JSON (`--json`)

stdout contains exactly one JSON object and nothing else:

```json
{
  "dry_run": false,
  "checksum": false,
  "delete": true,
  "created":  [{"path": "docs/a b.md", "kind": "file"}],
  "updated":  [{"path": "link", "kind": "symlink", "reason": "link"}],
  "deleted":  [{"path": "old.txt", "kind": "file"}],
  "skipped":  [{"path": "secret.key", "reason": "error", "detail": "Permission denied"}],
  "unchanged": 12
}
```

- The top-level keys are exactly those shown. Entry objects have exactly the keys shown for their list.
- `kind` is `file` or `symlink` in `created` and `updated`, and `file`, `symlink` or `other` in `deleted`.
- `updated.reason` is one of `size`, `mtime`, `content`, `type`, `link`.
- `skipped.reason` is `unsupported` or `error`. `detail` is a free-form human-readable string.
- `unchanged` is the number of in-scope SOURCE files and symlinks that needed no change.
- In a dry run the report is the one the real run would produce (subject to the note under Errors), with `"dry_run": true`.

### Text (default)

One line per entry, lists in the order created, updated, deleted, skipped, each list sorted as above:

```
created docs/a b.md
updated link (link)
deleted old.txt
skipped secret.key (error)
```

Then a final summary line:

```
1 created, 1 updated, 1 deleted, 1 skipped, 12 unchanged
```

In a dry run the summary line ends with ` (dry run)`. Error details may go to stderr.

## Deliverables

- The `dirsync` package in the repository root.
- Your own tests.
- A short README section or docstring on usage.

**Scale:** a personal and small-team tool. It syncs project folders, photo libraries and backup copies of up to about 50,000 files, a few times a day, run by hand or from cron. The worst realistic loss if it is wrong is a `--delete` run that removes files the user excluded or that live outside TARGET, destroying a working copy that may have no other backup.
