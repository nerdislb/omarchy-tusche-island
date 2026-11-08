# Island flavor handoff — strand G

Branch: `feat/looks-flavor-20261107`. Base: `d3dd40d`, installed base generation
`fd532671b76c700d`. No live configuration or session was modified. Nothing was pushed.
Implementation commit: `4168b04`; test/capture tooling commit: `0fbab03`.
Final payload generation: `e353b258a04e93a7` (also used in the final private
shell capture). Documentation and evidence do not enter the plugin payload.

The Round 2 contract was read from `omarchy-looks/docs/CONTRACT.md` and is unchanged.

## Behavior

`flavor` is independent of `look`. Accepted values: `""`, `funk`, `register`,
`umbra`, `tusche`; default `""`. Invalid IPC values return usage without saving.
Unknown stored values render as the empty flavor. `state` reports flavor and
working-agent count. Existing sources and completion detection remain authoritative.

- Umbra: static 1.5 px ice-to-corona ring, 6 px soft falloff, opacity 0.7, 300 ms
  fades while working and compact. The existing liquid SDF supplies its outline,
  including merges with minimal capsules and banners. One 900 ms flare per
  `doneSerial` event, anchored on the drawn capsule's upper-right arc.
- Tusche: supplied Hanko SVG at the right of an agent completion, scale
  1.45 → 0.96 → 1, rotation −8° → −3°, 260 ms. Ink circle starts at 20%,
  expands to 1.25 and disappears over 400 ms. The stamp stays with the surface.
- Funk: the main agent lead reads `● N ON AIR` in `#ff6b7d`, with no pulse.
  Minimal capsules retain their existing compact information. Completion titles
  start with `SIGNAL ·` in expanded and banner presentations.
- Register: four 2 px, 10 px corner marks, 3 px outside the drawn completion,
  settling over 90 ms. Expanded completion gets a 5 px top clearance so its
  upper marks remain on screen. Compact geometry is unchanged.

Reduced Motion uses opacity only; the ink growth is omitted. Flavor changes,
completion dismissal and hiding the stage stop transient effects. No recurring
animation or polling was added. Existing swell cleanup remains intact.

The two art files were copied byte-for-byte from the looks repository. No art
was edited or generated: responsive geometry and motion are QML/shader code,
so an exported vector timeline would not follow the live liquid shape. The
looks repository and its editable art sources remain untouched.

## Install — for Claude in the owner's session

These commands are instructions for the integrator; they were not run live.
The shell already uses `look: dynamic`, so no layout change is required.

```bash
cd ~/Data/Development/projects/tusche-island-looks-20261107
./dev-install.sh
omarchy-shell tusche-island set flavor umbra
omarchy-shell tusche-island state
```

`dev-install.sh` publishes an immutable generation and rescans plugins. It does
not restart the shell. Use `funk`, `register` or `tusche` instead of `umbra` as
needed. The extras layer can call this exact existing IPC setter directly.
To remove the flavor immediately, preserving the installed code:

```bash
omarchy-shell tusche-island set flavor ""
```

For a full code rollback, publish the base again from a detached worktree on
the data partition (choose a fresh destination if it already exists):

```bash
cd ~/Data/Development/projects/tusche-island-looks-20261107
omarchy-shell tusche-island set flavor ""
git worktree add --detach ~/Data/Development/projects/tusche-island-before-flavor-20261107 d3dd40d
cd ~/Data/Development/projects/tusche-island-before-flavor-20261107
./dev-install.sh
```

That restores the original code and its owned module URLs while preserving
other plugins, layout entries and options. No reset of the shared shell.json
and no shell restart are required. Old immutable generations are retained.

## Private demos and evidence

Use the demos only inside the disposable test session, never on the live desktop:

| IPC demo | Purpose |
|---|---|
| `demo agents` | Two working agents, UI preview only |
| `demo agents-waiting` | One blocked agent, UI preview only |
| `demo agentdone` | Expanded completion and one completion serial |
| `demo agentdone-banner` | Critical synthetic completion to exercise the real banner queue |
| `demo off` | Remove demo agents/HUD and restore actual source observations |
| `alert dismiss` / `note dismiss` | Clear the expanded completion / banner |

Demo agent observations never enter the source's completion detector or run
agent focus commands. Normal noncritical completions keep expanding the island;
the banner demo deliberately uses the existing critical-notification route.

Reproduce the full-shell evidence:

```bash
ISLAND_SRC="$PWD" python3 tools/flavor-evidence.py
```

The script derives from the supplied shell-shot and shader record workflows.
It launches `env -i`, creates HOME and XDG_RUNTIME_DIR under
`/tmp/island-flavor-*`, a private D-Bus, headless Umbriel and the real shell.
GLES tries `renderD129` first, then `renderD128`. Only bar and island worktree
plugins are installed into the temporary HOME. Source collectors are disabled;
preview agents supply the UI state. The copied theme and font inputs are read
only. All owned process groups are stopped and reaped and the temporary tree is
removed, including on failure. See `evidence/flavor/isolation.json` and
`cleanup.json` for the recorded paths, PIDs and cleanup result.

PNG series in [evidence/flavor](evidence/flavor/): each flavor plus the default
has idle, working, expanded completion at 90/180/260/400/650/1000/1500 ms,
banner at 180/400/650/1000/1500 ms, and a cleared state. Umbra also has minimal
capsule and merging-banner shots. Times in names are requested times from IPC
invocation; `captures.json` records actual capture start/completion times.
Images are native-resolution 660×310 crops from the 1920×1080 private output,
not mockups. The source theme was the owner's current Umbra palette.

## Verification

Use the shell source location from `isolation.json` as `OMARCHY_PATH` if it is
not the default. `QT_QPA_PLATFORMTHEME=basic` avoids the host GTK platform theme
trying to connect to a desktop during offscreen tests.

```bash
export OMARCHY_PATH="$HOME/Data/Development/projects/omarchy-umbriel-pixel-20261104"
export QT_QPA_PLATFORMTHEME=basic
node tests/model.cjs
node tests/flavor.cjs
node tests/corgi.cjs
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
python3 tests/motion_runtime.py
python3 tests/dynamic_runtime.py
python3 tests/flavor_runtime.py
python3 tests/flavor_default_pixels.py
/usr/lib/qt6/bin/qmllint --ignore-settings Island.qml sources/Desktop.qml \
  views/DynamicStage.qml views/DynamicAlert.qml views/DynamicNote.qml \
  views/LiquidShape.qml views/CompletionFlavor.qml
```

Passed: 33 Python tests; model, Corgi and new flavor cjs checks; four motion
scenes; liquid and clock runtime scenes including the mid-swell withdrawal
regression; new lifecycle scene covering settled corona, flare expiry, stamp
settling, dismissal, mid-animation flavor change, reduced motion, hidden-stage
cancellation and return to rest. The older runtime doubles were updated with
`gf()` to match the already-existing pixel-font interface.

`flavor_default_pixels.py` compares real Qt output with `d3dd40d`: compact,
minimal, expanded completion and banner resting states match pixel-for-pixel,
including alpha. It does not claim pixel identity for every intermediate
animation frame. Existing liquid timing/geometry assertions also pass.

`qmllint` exits 0. The new standalone decoration is warning-free. Existing
files retain contextual warnings: the same Commons import/type warnings as
base plus delegate-scope unqualified-access warnings (logs include the base
comparison). Shader rebuilt with Qt qsb for GLSL ES 100/120/150, HLSL 50 and
MSL 12; only GLES/OpenGL was exercised at runtime.

Known pre-existing failure: `node tests/hermes.cjs` expects the old direct
Hyprland focus argv; source already contains the Umbriel-aware wrapper. The
same assertion fails on untouched `d3dd40d` (`hermes-baseline.txt`). The Hermes
Python tests pass. This unrelated test was not rewritten.

Limits: no live-session install or validation, physical multi-monitor/HiDPI
hardware, Hyprland session, actual agent completion event, or compositor
fullscreen/screen-off cycle was exercised. Native-source completion selection
is covered by the existing model tests; rendering used IPC previews. Private
shell logs include unavailable PipeWire/Hyprland-service warnings, expected
without the owner's buses. There are no flavor QML exceptions or binding loops
in the final private-shell log. No new idle CPU benchmark was taken; runtime
checks verify that the stage clock and decoration animations stop at rest.

## Strand K — herdr-core event subscription (08 November 2026)

Implementation: `4c4dd7b`, continuing this branch from `1879de1`. New payload
generation: `edffac8c736634c7`; rollback payload: `e353b258a04e93a7`.
The contract, flavor behavior and settings are unchanged. No live files,
services, plugins, compositor or default core session were changed or started.

`--watch` now opens the Unix socket directly and sends plain-mode JSON-RPC
`events.subscribe {}`. It consumes the atomic snapshot, applies terminal fact
changes and replaces the records on `missed`. Duplicate/old sequences are
ignored; a sequence gap reconnects for a fresh snapshot. Every reconnect
starts a new sequence fence. Loss leaves a kept terminal live with no PID or
foreground; finish removes it from the displayed live list. Created/restarted
records replace earlier records, including reappearing remote terminals.

API records are normalized exactly as hc 0.1.18's `cli/output.rs::short`:
agent = root `status.app`, otherwise argv[0]'s basename; where = `labels.where`;
status = root `status.state`. An explicitly empty app remains empty. The
existing filters, status mapping, field lengths, LIMIT, compact sorted JSON
and ASCII escaping are shared with `--once`. OSC terminal titles and
foreground folders do not change the displayed title/directory. Local records
retain numeric terminal order. With remote terminals, `machine.list {}` reads
configured machine order only when the set of represented remote machines
changes; terminal numbers sort within each group. Both methods exist in
`released.openrpc.json` for 0.1.18. No terminal output is read.

The collector emits changed lists/availability immediately and repeats the
current line every **3 seconds**. `Desktop.collectorStuck` expires a received
line after 8 seconds (first-line grace: 15 seconds), so using the core's
15-second heartbeat directly would cause restarts. This watchdog is unchanged.
The core heartbeat maintains connection health: an initial response has a
5-second deadline; 45 seconds without complete core messages forces a fresh
connection. Socket failure/EOF/protocol failure emits `available:false`, clears
displayed agents and retries after 1, 2, 4, 8, 16, then 30 seconds. Output
heartbeats continue during backoff. Watch mode never invokes `hc`, including
when the socket is missing and the executable is present. `--once` retains
`hc ls --json`; the entire `--focus` implementation is unchanged.

Endpoint resolution follows HC_SOCKET, the optional config `socket`, then
XDG_RUNTIME_DIR/herdr-core/<HC_SESSION-or-default>.sock. Without a runtime
override it uses an existing /run/user/<uid> directory, otherwise the XDG state
home. These are read-only path lookups; the collector does not create a core.

### Verification and evidence

See [event evidence](evidence/events/README.md), with raw measurements,
fixtures, output observations, test logs and cleanup records. Reproduce:

```bash
cd ~/Data/Development/projects/tusche-island-looks-20261107
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/events-evidence.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/events-reload-evidence.py
```

The real-core harness starts installed hc 0.1.18 in a private, foreground
`HC_SESSION=islandtest` core with its own HOME and every XDG directory under
`/tmp/island-events-*`. It calls `hc run --bg` with a script reporting OSC 7501
`state=working:app=island-fixture` and then `state=done:app=island-fixture`,
asserts both collector observations, records a real 15-second core heartbeat,
and compares the new event state with the unmodified `1879de1` collector's
output for the same API/CLI fixtures. It then measures both watch collectors
for at least 60 seconds against the same quiet private core. All temporary
processes and directories are cleaned up; no owner data is used.

The fake Unix-core tests cover snapshot/deltas, labels, missed snapshots,
sequence fences, batching/fragmentation, EOF/reconnect, RPC errors and gaps,
unchanged-output suppression, the 3-second heartbeat, missing socket with hc
present, numeric/machine ordering and LIMIT. Deterministic clock tests cover
the 30-second backoff cap and both silent-core deadlines. Fixture parity also
checks the state after status/label events, empty app, Unicode/truncation,
unknown status and argv fallback. All 46 Python tests pass. Model, Corgi and
flavor Node checks pass; Desktop.qml qmllint exits 0 with its existing eight
unqualified-access warnings.

The private reload harness starts headless Umbriel with `env -i`, private
HOME/XDG paths and GLES `renderD129`, then a minimal real Quickshell Loader
hosting the unchanged Desktop.qml. It changes between immutable source URLs:
the first collector PID ends, a new collector uses the second generation's
script path, and unloading leaves no collector. The shell's
`syncPanelEntries()` removes/recreates panel entries on a changed sourceUrl;
`Island.qml` owns Desktop.qml. Together these establish that the normal
publish/rescan URL change replaces the collector without restarting the shell.

Not exercised: installation/rescan in the owner's running shell, a full-shell
rescan roundtrip in the private fixture, physical displays, real remote cores,
or native backpressure sufficient to induce `missed`. Remote/missed behavior
is tested with the fake core. The default owner core was not queried.

### Install and rollback — Claude in the owner's session

These are integrator instructions; they were not run live. No shell restart
or flavor/options change is required:

```bash
cd ~/Data/Development/projects/tusche-island-looks-20261107
./dev-install.sh
omarchy-shell tusche-island state
```

The installer should report generation `edffac8c736634c7`. Publishing changes
the immutable entry-point URLs and rescans plugins, replacing the collector.
The state should report herdr-core availability/count matching the running
core. A quiet collector continues printing a line every 3 seconds.

To restore the live generation from before this strand, use a fresh detached
worktree directory on the data partition (do not reset this working branch):

```bash
cd ~/Data/Development/projects/tusche-island-looks-20261107
git worktree add --detach ~/Data/Development/projects/tusche-island-before-events-20261108 1879de1
cd ~/Data/Development/projects/tusche-island-before-events-20261108
./dev-install.sh
```

That payload was independently hashed as `e353b258a04e93a7`. It restores the
polling collector and keeps the existing flavors/settings. No shell restart
is needed for rollback either.
