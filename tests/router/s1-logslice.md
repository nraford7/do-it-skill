# logslice

Build `logslice`, a command-line tool that prints the log entries from one or more log files that fall inside a time window.

## Constraints

- Python 3.11 or newer, standard library only. No third-party packages at runtime.
- Run from the repository root as:

  ```
  python3 -m logslice [--from TS] [--to TS] [--json] FILE [FILE ...]
  ```

  A single module `logslice.py` at the repository root is enough. A package `logslice/` with `__main__.py` is also fine.
- Include your own tests.

## Log format

A log file is a text file of lines separated by `\n`.

A line **starts a new entry** if and only if it begins (at column 0) with a timestamp of this exact form, followed by a space or by the end of the line:

```
YYYY-MM-DDTHH:MM:SS[.f]OFFSET
```

- `.f` is optional: a dot and 1 to 6 digits of fractional seconds.
- `OFFSET` is required: either `Z` (UTC) or `+HH:MM` / `-HH:MM`.
- Examples: `2024-03-01T10:00:00Z`, `2024-03-01T12:00:00.250+02:00`, `2024-02-29T23:30:00-05:00`.

Every other line is a **continuation line**. It belongs to the most recent entry above it in the same file (stack traces, wrapped messages, and so on). Continuation lines that appear before the first entry of a file are ignored.

An entry is its first line plus all of its continuation lines. An entry's time is the instant given by the timestamp on its first line.

Log files come from real systems. Different files, and different lines in one file, may use different UTC offsets. Files may contain bytes that are not valid UTF-8.

## Behaviour

- `--from TS`: keep entries whose time is at or after `TS` (inclusive). Optional; if omitted there is no lower bound.
- `--to TS`: keep entries whose time is strictly before `TS` (exclusive). Optional; if omitted there is no upper bound.
- `TS` uses the same timestamp form as above (offset required).
- An entry is either kept whole (all its lines) or dropped whole.
- Entries from all files are output together as one sequence, sorted by time (earliest first). Entries with the same instant keep the order of the file arguments, and within one file, their order in that file.
- Read files as UTF-8. Invalid byte sequences must not stop processing: decode them as Python's `errors="replace"` does (each becomes U+FFFD). Output is UTF-8.

### Text output (default)

For each kept entry, print its lines exactly as decoded, each followed by `\n` (also if the file's last line had no trailing newline). Nothing is printed between entries.

### JSON output (`--json`)

Print one JSON object per line (JSON Lines), one per kept entry, in the same order as text output. Each object has exactly these keys:

| Key | Type | Value |
|---|---|---|
| `file` | string | the file argument exactly as given on the command line |
| `line` | integer | 1-based line number of the entry's first line in that file |
| `timestamp` | string | the timestamp text exactly as it appears in the file |
| `utc` | string | the entry's time in UTC, formatted `YYYY-MM-DDTHH:MM:SS.ffffffZ` (always 6 fractional digits) |
| `text` | string | the entry's lines joined with `\n`, without a trailing newline |

## Errors and exit codes

| Exit code | Meaning |
|---|---|
| 0 | At least one entry was output, and every file was read. |
| 1 | No entry matched, and every file was read. |
| 2 | Usage error, or at least one file could not be read. |

- Usage errors: no FILE given, an unknown option, or a `--from`/`--to` value that is not a valid timestamp of the form above (including one with no offset), or `--from` later than `--to`. On a usage error, print a message to stderr, print nothing to stdout, and exit 2.
- A file that cannot be read (does not exist, is a directory, no permission): print one line `logslice: cannot read <FILE>: <reason>` to stderr, where `<FILE>` is the argument as given, and continue with the other files. Output the matching entries from the readable files as normal, then exit 2.
- Never print a Python traceback.

## Example

`app.log`:

```
2024-03-01T09:59:59Z starting
2024-03-01T10:00:00Z request failed
Traceback (most recent call last):
  File "app.py", line 3, in <module>
ValueError: bad input
2024-03-01T12:30:00+02:00 retry ok
2024-03-01T11:00:00Z shutting down
```

`python3 -m logslice --from 2024-03-01T10:00:00Z --to 2024-03-01T11:00:00Z app.log` prints:

```
2024-03-01T10:00:00Z request failed
Traceback (most recent call last):
  File "app.py", line 3, in <module>
ValueError: bad input
2024-03-01T12:30:00+02:00 retry ok
```

and exits 0.

## Scale

Used by a small on-call team (a handful of engineers) to pull incident windows out of service logs, a few times a week, on files up to a few hundred MB. Worst realistic loss if it is wrong: an engineer misses or misorders log lines during an incident review and draws a wrong conclusion about the cause, costing hours of debugging.
