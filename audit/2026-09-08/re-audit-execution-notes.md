# 2026-09-08 client re-audit

Executed `audit/2026-09-08/repro.pl` against the current `fix/audit-2026-09-08` worktree copy.

- Environment: temporary `debian:bookworm` Docker container on `wsx`.
- Dependencies: Debian packages `perl`, `libprotocol-websocket-perl`, `libjson-rpc-common-perl`, `libio-socket-ssl-perl`, and `libio-socket-ip-perl`.
- Source mount: repository copy mounted read-only; no TrueNAS endpoint, credential, or ZFS command was used.
- Result: TAP plan `1..36`; all 36 assertions passed. Every `BUG:` assertion passing means the corresponding defect remains reproducible; the `control` assertion is a framing control.
- Stderr: three expected uninitialized-value warnings at `TrueNAS::Client.pm` lines 691 and 984 and `TrueNASPlugin.pm` line 322.
- Cleanup: temporary remote staging directory and one-shot container were removed after collection.

## Surface re-audit

- Executed `node audit/2026-09-08/surface-repro.cjs > audit/2026-09-08/reaudit-surface-results.tap` locally; exit code 0.
- The saved TAP is the script's unmodified stdout: `1..4`, four BUG assertions confirming the defects. It is not a rewritten test summary.
- The script uses extracted UI callbacks and command substitutes. Its `finally` removes the temporary directory; no real installation commands or remote resources were used.
