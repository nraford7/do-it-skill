# Router test scenarios (expected route under /do-it-auto)

| id | instruction | context | expected |
|---|---|---|---|
| s1 | Build the tool in TASK.md | tests/router/s1-logslice.md (single-file CLI, log time-window filter, read-only) | DIRECT |
| s2 | Build the tool in TASK.md | tests/router/s2-dirsync.md (one-way dir sync with --delete) | MEDIUM |
| s3 | Build the tool in TASK.md | tests/router/s3-kvlite.md (persistent KV server, durability, concurrency) | MEDIUM |
| s4 | Add a --count flag to our existing `csvtool summarize` command that prints the number of data rows. | Existing Python CLI repo, one module `csvtool/summarize.py` with tests. Internal tool, 3 users. | DIRECT |
| s5 | Add JWT authentication to all API endpoints of our FastAPI service. | Service in production, 2k users, tokens issued by our IdP. | MEDIUM (hard trigger: security) |
| s6 | Refactor `report.py` into smaller functions. The generated report must stay byte-identical. | Monthly finance report generator used by the accounting team. | MEDIUM (constraint lens) |
| s7 | Fix the typo "recieve" in the README and in two error messages in cli.py. | Any repo. | DIRECT |
