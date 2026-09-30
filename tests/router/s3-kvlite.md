# kvlite: a small persistent key-value server

Build `kvlite`, a small key-value server with a command-line client. It keeps string keys and string values, serves many clients at once over TCP, and never loses a write it has acknowledged.

## Constraints

- Python 3.11 or newer, **standard library only**. No third-party packages.
- The package is `kvlite` at the repository root. Everything runs from the repository root as `python3 -m kvlite ...`.
- Structure the code however you like. Only the command line, the network protocol, and the data-directory rules below are the contract.
- Include your own tests.

## Server

```
python3 -m kvlite serve --data-dir DIR [--host HOST] [--port PORT] [--compact-bytes N]
```

| Flag | Default | Meaning |
|---|---|---|
| `--data-dir DIR` | required | Directory for all persistent state. Create it (and parents) if it does not exist. |
| `--host HOST` | `127.0.0.1` | Address to listen on. |
| `--port PORT` | `7411` | TCP port to listen on. |
| `--compact-bytes N` | `4194304` | Log size threshold for automatic compaction (see Storage). |

- When the server is ready to accept connections it prints one line to stdout, `kvlite listening on HOST:PORT`, and flushes it.
- The server runs until it is killed. It must handle many client connections at the same time (at least 64 open connections). A slow or idle client must not block other clients.
- Only one server uses a given data directory at a time. You do not need to detect a second one.
- If the server cannot start (for example, the port is in use), it prints an error to stderr and exits with code 1.

## Protocol

Line-based JSON over TCP. The client sends requests and the server sends responses.

- Each request is one line: a JSON object encoded as UTF-8, terminated by a single `\n` byte.
- Each response is one line: a JSON object encoded as UTF-8, terminated by `\n`.
- A connection carries any number of requests. A client may send several requests without waiting (pipelining). The server answers the requests on one connection in the order it received them, one response per request.
- A line that is empty or contains only whitespace is ignored and gets no response.
- The **maximum request line length is 1048576 bytes** (1 MiB), not counting the terminating `\n`. See "Oversized requests".
- JSON strings may contain any escapes allowed by JSON. Non-ASCII characters may be sent raw (UTF-8) or as `\uXXXX` escapes; the server must accept both, and may use either in responses.

### Keys and values

- A key is a non-empty JSON string of at most 1024 bytes when encoded as UTF-8.
- A value is a JSON string. Its size is limited only by the maximum line length.
- Keys and values may contain any Unicode characters, including newlines, carriage returns, tabs, NUL, and non-BMP characters such as emoji. They must round-trip exactly, through restarts and compaction. (Strings containing unpaired surrogates may be rejected with `bad_request`.)

### Request and response common fields

- Every request has an `"op"` field (a string, case-sensitive).
- A request may have an `"id"` field with any JSON value. If present, the response contains `"id"` with the same value. Responses to lines that are not valid JSON objects, and to oversized lines, have no `"id"`.
- Success responses have `"ok": true` plus the fields listed per operation.
- Error responses have exactly this shape:

```json
{"ok": false, "error": "<code>", "message": "<human-readable text>"}
```

(plus `"id"` when applicable). Error codes:

| Code | When |
|---|---|
| `bad_request` | The line is not valid UTF-8, not valid JSON, not a JSON object, or a field is missing, has the wrong type, or is out of range. |
| `unknown_op` | `"op"` is a string but not one of the operations below. |
| `not_found` | `GET` of a key that does not exist. |
| `too_large` | The request line exceeds the maximum line length. |
| `internal` | Any unexpected server-side failure. |

After any error response the connection stays open and usable. Unknown extra fields in a request are ignored.

### Operations

**PING**: `{"op": "PING"}` returns `{"ok": true}`.

**GET**: `{"op": "GET", "key": K}`
- Found: `{"ok": true, "value": V}`.
- Missing: error `not_found`.

**PUT**: `{"op": "PUT", "key": K, "value": V, "ttl": T}` (`ttl` optional)
- Sets the key. Returns `{"ok": true}`.
- `ttl` is a number of seconds greater than 0 (integer or fractional). The key expires `ttl` seconds after the server receives the PUT. Without `ttl`, the key never expires, and any earlier expiry on that key is cleared.
- `ttl` of 0, negative, `null`, a boolean, or a non-number is `bad_request`.

**DELETE**: `{"op": "DELETE", "key": K}`
- Returns `{"ok": true, "deleted": true}` if the key existed, else `{"ok": true, "deleted": false}`.

**CAS** (compare-and-swap): `{"op": "CAS", "key": K, "expected": E, "value": V, "ttl": T}` (`ttl` optional)
- `expected` is required. It is a string, or `null` meaning "the key must not exist".
- If the current value equals `expected` (or the key does not exist and `expected` is `null`), the server sets the key to `value` (with `ttl` as for PUT) and returns `{"ok": true, "swapped": true}`.
- Otherwise it changes nothing and returns `{"ok": true, "swapped": false, "current": C}`, where `C` is the current value, or `null` if the key does not exist.
- The compare and the swap are one atomic step with respect to all other operations from all clients.

**SCAN**: `{"op": "SCAN", "prefix": P, "limit": N, "after": A}` (all three optional)
- Returns the keys that start with `prefix` (default `""`, meaning all keys), sorted in ascending order by Unicode code point (Python's default `str` ordering), as `{"ok": true, "items": [{"key": K, "value": V}, ...]}`.
- If `after` is given, only keys strictly greater than `after` are returned. This allows paging.
- At most `limit` items are returned. `limit` is an integer from 1 to 1000; the default is 100. Out of range or non-integer is `bad_request`.

**COMPACT**: `{"op": "COMPACT"}` runs a compaction (see Storage) and returns `{"ok": true}` when it has finished.

### Expiry

A key whose expiry time has passed does not exist, for every operation: GET, DELETE, CAS, SCAN, and after a restart. Expiry times are wall-clock times: a key given `"ttl": 60` at 12:00:00 expires at 12:01:00, even if the server restarted at 12:00:30.

### Oversized requests

If a request line is longer than 1048576 bytes (not counting the `\n`), the server must not process it. It reads and discards the rest of that line up to and including the next `\n`, then sends the error `too_large`. The connection stays open, and the server continues with the next line. The server must not hold the whole oversized line in memory. A line of exactly 1048576 bytes is valid.

## Storage, durability and recovery

- All state lives in the data directory. The server keeps the live data in memory and rebuilds it from disk on startup.
- The data directory contains an append-only log named **`kvlite.log`**. Every change (PUT, successful CAS, DELETE of an existing key) is appended to the end of `kvlite.log`. You may keep other files in the data directory (for example a snapshot), and you choose the record format.
- **Durability:** the server sends the response to a change only after the change is written to `kvlite.log` and the file has been flushed and `fsync`ed. If the server is killed at any moment (for example with `kill -9`, or by power loss), every change that was acknowledged must be present after restart. A change that was not yet acknowledged may be present or absent after the crash.
- **Recovery:** on startup the server rebuilds its state from the data directory. It must start and recover after being killed at any moment, including partway through appending a record.
- **Compaction** rewrites the stored state so that overwritten, deleted and expired entries no longer take space. It runs automatically whenever `kvlite.log` is at least `--compact-bytes` bytes **and** at least twice the size the live data would take in a freshly compacted log. It also runs on the `COMPACT` request. Clients may keep reading and writing while compaction happens (writes may wait briefly). Compaction must never lose or corrupt data, and a crash during compaction must leave a recoverable data directory.

## Command-line client

```
python3 -m kvlite get KEY [--host HOST] [--port PORT]
python3 -m kvlite put KEY VALUE [--ttl SECONDS] [--host HOST] [--port PORT]
python3 -m kvlite delete KEY [--host HOST] [--port PORT]
python3 -m kvlite cas KEY VALUE (--expected OLD | --absent) [--ttl SECONDS] [--host HOST] [--port PORT]
python3 -m kvlite scan [--prefix P] [--limit N] [--after K] [--host HOST] [--port PORT]
```

Options come after the subcommand name, in any order relative to the positional arguments. `--host` and `--port` default to `127.0.0.1` and `7411`. Each command opens one connection, sends one request, prints the result and exits.

| Command | Success (exit 0), stdout | Other outcomes |
|---|---|---|
| `get` | the value exactly, followed by one `\n` | key missing: exit 1, nothing on stdout |
| `put` | `OK\n` | |
| `delete` | `OK\n` | key did not exist: exit 1, nothing on stdout |
| `cas` | `OK\n` | not swapped: exit 1, nothing on stdout |
| `scan` | one line per item: the JSON object `{"key": K, "value": V}`, in server order | |

- `cas` needs exactly one of `--expected OLD` or `--absent` (`--absent` sends `"expected": null`).
- Usage errors, or an error response from the server: message on stderr, exit 2.
- Cannot connect to the server: message on stderr, exit 3.
- Messages for non-zero exits go to stderr, never stdout.

## Scale

An internal configuration and feature-flag store for one small engineering team: 5 to 20 services hold 10 to 60 connections, a few hundred requests per second at peak, under 100 MB of live data, run on one machine. Worst realistic loss if it is wrong: acknowledged flag or config changes lost or corrupted after a crash or a restart, so services run on stale settings until someone notices and re-applies them from memory or from chat history (hours of on-call time, possible brief customer-facing misbehaviour). It holds no money and no personal data.
