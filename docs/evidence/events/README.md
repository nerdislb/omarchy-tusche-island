# herdr-core event collector evidence

Implementation commit: `4c4dd7b`, based on `1879de1` (live generation
`e353b258a04e93a7`). New payload: `edffac8c736634c7`. No live installation.
The measured collector SHA-256 is `629f4678196bd07f084f378fd68dc3183bbc76c00d04dedfa251b0096b5bb3c8`.

## Idle comparison

Both collectors ran simultaneously against the same quiet private hc 0.1.18
core, with one live terminal reporting done. Durations are at least 60 seconds.
The old source is read directly from `1879de1`; the new source hash is checked
before and after the run. Python subprocess audit events count Popen starts
and record argv/timing. `resource.getrusage` measures collector and reaped-child
CPU separately, including Python startup/imports. One CPU at 100% means one
fully occupied logical CPU; these are cumulative CPU times, not power readings.

| Measurement | Polling base | Event subscription |
|---|---:|---:|
| Wall seconds | 60.149 | 60.086 |
| Collector CPU seconds | 0.171472 | 0.095105 |
| Child CPU seconds | 0.109980 | 0.000000 |
| Total CPU seconds | 0.281452 | 0.095105 |
| Total one-CPU utilization | 0.468% | 0.158% |
| hc process starts | 40 | 0 |
| Collector output lines | 20 | 20 |

This is one paired run under normal host load. The small CPU numbers vary
with scheduling/startup cost; the direct result is zero watch-mode subprocess
starts while keeping the same output heartbeat. It is not a rendering or
whole-desktop energy benchmark.

## Real-core smoke and parity

`tools/events-evidence.py` creates a private HOME and all XDG directories under
`/tmp/island-events-*`, launches a foreground `hc serve` with a saved PID and
`HC_SESSION=islandtest`, then calls `hc run --bg` with a Python script emitting
OSC 7501 reports (`state=working:app=island-fixture`, then `state=done:app=island-fixture`).
It observes working then idle through the collector subscription and compares
an actual API snapshot with `hc ls --json` transformed by the original collector:
serialized bytes match. API/CLI fixtures and collector observations are stored
in `measurement.json`. Only the private core is queried or stopped.

The core's real heartbeat arrived after 15.001 seconds;
the collector's independent watchdog heartbeat remains 3 seconds. The raw log
is `native-run.txt`. Private-process stderr is retained in `stderr.txt`.
`cleanup.json` records reaped top-level PIDs and removal of the temporary tree.

## Socket and lifecycle tests

`python-tests.txt`: all 46 Python tests pass. `collector-tests.txt`: all 16
collector tests pass, including a real Unix-socket fake core. The fake peer
exercises snapshot/events/missed, old sequence rejection and gap recovery,
RPC errors, fragmented/batched JSON lines, EOF/reconnect, unchanged suppression,
3-second heartbeat, missing endpoint with an executable hc trap, machine order
and labels. Clock-controlled tests check capped exponential backoff and silent
handshake/core deadlines. The fixture parity test covers both an initial
snapshot and state after status/labels events. Long text, Unicode, empty app,
argv fallback, LIMIT and numeric insertion order are covered.

`model.txt`, `corgi.txt`, `flavor.txt`, `qmllint.txt` and `verification.json`
record additional checks. Qmllint exits 0 with the existing eight unqualified
access warnings. The original and new focus function sources are identical.

`tools/events-reload-evidence.py` creates another private HOME/XDG runtime,
launches `env -i` headless Umbriel using GLES renderD129 (renderD128 fallback),
then real Quickshell with a minimal Loader hosting Desktop.qml. All other
sources are disabled. A nonexistent private core socket keeps this test away
from real cores. Two immutable source paths exercise the same Loader replacement
that shell.syncPanelEntries triggers when the install changes sourceUrl.
`reload.json` records old/new collector argv/PIDs: replacement ends the old
process and starts the new script path; unload leaves no collectors. This is
a focused lifecycle probe, not a full-shell plugin rescan test. Logs and cleanup
records are retained alongside it.

## Reproduction

Run from this worktree:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/events-evidence.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/events-reload-evidence.py
```

The harnesses overwrite this directory's raw logs, fixtures and JSON results.
No physical-display/live-shell installation, real remote core, or actual native
queue overflow was exercised. Remote ordering and missed snapshots use the
fake peer. See `docs/HANDOFF-flavor.md` for install and exact rollback commands.
