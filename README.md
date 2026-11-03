# Tusche Island for Omarchy

The clock in the middle of Omarchy's bar becomes an island. It grows a live segment for whatever is happening: agents, media, timers, meetings, AI limits, the phone. A click opens its popup, and notifications can run as a column under it. The island takes the theme's material, including the ink bloom and dried rim on the Tusche & Papier Lavur themes it is made for. It is the companion of the [Tusche Bar](https://github.com/nerdislb/omarchy-tusche-bar) and also works on its own.

Based on [Arjun010011/omarchy-dynamic-island](https://github.com/Arjun010011/omarchy-dynamic-island) (commit `9d6e3f4e072a77b7b11086934b785b6d7f2518f7`), MIT licence retained.

![The island in the bar (Tusche Lavur)](docs/screenshots/bar-tusche-lavur.png)
![The island's popup with live activities](docs/screenshots/island-tusche-lavur.png)

## Requirements

- **Omarchy:** a recent version with the Quickshell shell (the dev line of early October 2026 or later).
- **Tools:** `git`, `jq` and `rsync`.
- **Optional:** OmaMail (calendar), Flux (phone) and Omarchy's agents. The island shows these sources only when they are there.

## Install

The easiest way is the whole look, which places the island in the clock's spot for you:

```sh
git clone https://github.com/nerdislb/omarchy-tusche-bar.git ~/src/omarchy-tusche-bar
~/src/omarchy-tusche-bar/setup/install.sh
```

Only the island:

```sh
git clone https://github.com/nerdislb/omarchy-tusche-island.git ~/src/omarchy-tusche-island
cd ~/src/omarchy-tusche-island && ./dev-install.sh
omarchy-shell shell rescanPlugins
omarchy plugin enable nerdibeard.tusche-island center --before omarchy.clock
omarchy plugin disable omarchy.clock      # the island is the clock
```

**Update:** `git pull && ./dev-install.sh`, then `omarchy restart shell`.

**Remove:** `omarchy plugin disable nerdibeard.tusche-island`, then `omarchy plugin enable omarchy.clock center`.

## In the bar

The plugin is both a `panel` (state and sources) and a `bar-widget`. With `nerdibeard.tusche-island` in the bar (in the clock's place; make it `bar.centerAnchor`) the island lives there:

- At rest the widget is the clock (`format`, default `HH:mm`).
- Anything live grows a tinted segment beside the time: working agents, timer/stopwatch (with a progress rule), music, a meeting about to start, recording, mic/camera, an agent waiting for you; announcements (agent done, limits, track change, charging) take the segment for a few seconds.
- Left click opens the island as a **native bar popup** (Omarchy card, border, gap and outside-click/Esc dismissal; it closes when another bar popup opens). Right click opens the calendar, middle click plays/pauses.
- Without the widget in the bar (and with a `plugins[]` entry instead) the island floats under the bar as its own strip; `barMode: false` forces that.

While the plugin is in the bar, the shell reads and writes its entry in `bar.layout`, so keep only that one entry (no second one in `plugins[]`).

### Dynamic look

With `"look": "dynamic"` in the island's entry (or `omarchy-shell tusche-island set look dynamic`) the island in a top bar becomes Apple's Dynamic Island: a true black, opaque capsule hanging from the bar, with a thin key line in the colour of what it shows. `"look": "classic"` (the default) keeps everything above. A bar at the bottom or the side keeps the classic look.

- **Compact**: a capsule about 36 px tall from 2 px under the screen's edge (it hangs below a 30 px bar), the status on the left in its colour (working agents in yellow with their count, a timer, music, a recording, the next meeting, a quiet line, a passing announcement) and the clock on the right, both halves balanced and as narrow as possible. The bar keeps the capsule's slot free; the bell stays beside it. Left click opens the island's popup (the capsule tucks into the bar meanwhile), right click the calendar, middle click plays/pauses.
- **Minimal**: up to two more live activities bud off beside the capsule as their own small capsules with live data (three in all); a click opens the island on that activity.
- **Expanded**: when an agent finishes, the battery runs low or a timer runs out, the capsule itself grows into a rounded island (470 px wide, 84 or 104 px tall) with the event, the clock and its actions (*Open* / *Later* for an agent, *+1 min* / *Dismiss* for a timer), then shrinks back. A click runs the first action, a right click dismisses; the pointer on it holds its time.
- **Banners**: every other notification pours out of the capsule as one liquid shape (a signed-distance shader): the capsule swells, the card falls out through a neck that lets go after about a third of a second, stretching as it falls and squashing as it lands; going, the neck tightens, the card shrinks into the capsule and the capsule gulps it. The queue stays as in the classic column (one open card, two waiting rows, `+N`), with the same clicks, actions, *Later*, hover pause, DND, inbox and IPC.
- **Motion**: Apple springs, "playful" as chosen on the Liquid Island prototype (cards damping 0.68, closing 0.80, the capsule's swell 0.58 and gulp 0.45); Reduced Motion cross-fades in place instead.

The island is drawn by its own layer-shell window per bar (`tusche-island-dynamic`, overlay layer, no exclusive zone) that takes input only on the capsules and the cards and goes away under a fullscreen window or while the bar is hidden. Notes and the expanded island appear on the monitor the notes latched to (the focused one), the compact capsule on every bar.

The look follows the running shell: Omarchy's popup colours and `BorderSurface` frame, the theme font, font scale and Reduced Motion.

## Notifications

With `notifications: true` the island takes over Omarchy's notification service (it disables `omarchy.notifications`, leaves a marker, and hands it back when the setting goes off or the plugin is removed). It keeps Omarchy's contract: the `notifications` IPC target (`dismissOne`, `dismissAll`, `invokeLast`, `showHistory`, `toggleDnd`, …), the DND state file and its exceptions (`omarchy-action` toasts and critical `notify-send`), `--exec` click commands, `replaces_id` updates in place.

In the bar, notifications roll out of the bar's bottom edge right under the island, as one column:

- **Normal**: exactly one open card (app name, summary, body, the sender's action buttons). Others wait under it as title rows (two, then `+N`) and move up when the open card leaves. Stand time 8 s (a sender's longer timeout up to 30 s), 5 s while others wait; the pointer on the column holds it. Click opens (default action / `--exec` / focus the app), right click or × dismisses, a waiting row clicked comes to the front.
- **Critical**: a requester (the sender's actions, **Later**, **Dismiss**) that pauses the open card until it is handled; Later puts it into the inbox.
- **Low** without buttons: no card, a still line in the island for a few seconds, then the inbox.
- **Bell** beside the clock: unread count; left click opens the inbox (Mark read, Clear all, do-not-disturb switch), right click toggles do not disturb.
- A 2 px line in the app's tone under the clock while a card hangs.

`noteStyle` sets the look without a theme material: `window` (a window head over Omarchy's card body, in the Omarchy frame), `bubble` (a speech bubble whose notch flows out of the bar) or `float` (a free card a few pixels under the bar with the windows' corners and no connector; the island marks it with a short line at its centre; each card grows out of the island's lower edge, or out of the card above it, like the Dynamic Island: its plate springs into place with at most 6 px of overshoot (response 0.38 s, damping 0.70), the text fades in late at its own size, and it shrinks back the same way without a bounce). With Omarchy's Reduced Motion cards fade instead of moving. Notifications appear on the focused monitor, under the island of that monitor's bar; the inbox and what is on screen survive a shell restart.

**Theme material.** With the Tusche Bar's `edge` option set to `theme` and a theme that ships `bar-material.json` (Tusche & Papier), notes and the island popup take the theme's card instead of `noteStyle`: the theme's frame with its hard ink shadow (Papier) or halo (Tusche), soft controls, no title bar; a critical note keeps its text in the theme's colours and carries one narrow signal stripe. On the Lavur themes (material `card.bloom`) notes bloom out of the bar instead, each its own sheet of wet paper (`views/InkSheet.qml`): ink fills it, the water clears it, and the pigment dries into a rim at its calm edge. The island follows theme switches.

**Frost / Smoke glass.** With the matching Tusche Bar glass themes, notes and
the Island popup use Bevel Lens glass without changing their frame geometry.
Glass and popup spring motion follow the Bar's independent `glass` and
`glassMotion` options. Reduced Motion suppresses travelling light and springs.
Shared material sources and shader/QSB must match the Bar; see its
`docs/glass-material.md` for capture boundaries and verification limitations.

**Failures.** A systemd unit (user or system) that fails, or a program that dumps core, is announced once as an ordinary notification in the urgent tone; a click opens the journal or the core dump details in a terminal. `failures: false` turns this off.

**Agent completions.** A working → idle transition after at least 20 seconds of work shows both the bar announcement and a normal notification popout. It uses the existing themed column, queue, hover pause and DND policy, without taking keyboard focus. Click to focus the agent (OpenClaw agents open the local Control UI). `agentDone: false` disables both completion announcements. Short status flickers and the initial agent snapshot remain silent; idle means the agent stopped working, not that its result passed verification.

## Desktop integration

The island shows what the rest of the desktop already knows instead of keeping its own copy. All links are **read-only**; nothing is written to or sent from them.

| Source | Shown as | Setting |
|---|---|---|
| OmaMail calendar cache `~/.cache/omamail/calendar-bar.json` (iCloud/CalDAV, same as the bar clock) | next meeting, month view, "starting now" toast | `omamail` |
| Flux daemon socket `$XDG_RUNTIME_DIR/flux/fluxd.sock` (`subscribe` only) | working herdr/OpenClaw agents as a live activity; "Done" toast and notification popout after ≥20 s of work; an agent waiting for you | `flux`, `agents`, `agentDone`, `attention` |
| Flux paired phone | battery in the opened island; one low-battery HUD per discharge | `phone` |
| Omarchy agent usage `~/.local/state/omarchy/agents/usage/<id>.json` | HUD when a limit crosses 90 %, reaches 100 % or resets; tightest limit in the opened island | `aiLimits`, `aiProviders` |

Extra `.ics` feeds work too (`calendars`, or **+** in the calendar view).

## Settings

Settings live in the island's entry in `~/.config/omarchy/shell.json` (in `bar.layout` while it is in the bar). The island writes the missing ones with their defaults, so values can be changed in place.

| Setting | Default | Meaning |
|---|---|---|
| `format` | `"HH:mm"` | the clock in the bar |
| `idle` | `"auto"` | resting island: `auto` only when it has something the bar does not show (agents, a meeting within 12 h, a limit ≥ 90 %, low battery, all-day events, DND), `pill` always, `hidden` never |
| `idleFace` | `"ticker"` | `ticker` (glances), `clock` or `none` |
| `notifications` | `false` | take over Omarchy's notifications (see above) |
| `noteStyle` | `"window"` | `window`, `bubble` or `float` (the former value `workbench` reads as `window`) |
| `look` | `"classic"` | `dynamic`: the island as a black capsule hanging from a top bar, notes pouring out of it (see *Dynamic look*); `classic`: the clock with a live segment |
| `inbox` | `true` | keep missed notifications in the inbox |
| `osd` | `false` | take over Omarchy's on-screen display (volume, brightness, … as island HUDs) |
| `volume`, `brightness` | `false` | HUDs for volume and brightness changes |
| `charging`, `trackChange`, `recording`, `mic`, `camera`, `bluetooth`, `calendar` | `true` | the matching activities and HUDs |
| `omamail`, `flux`, `agents`, `agentDone`, `phone`, `aiLimits` | `true` | desktop integration (see above) |
| `aiProviders` | `["claude", "codex", "antigravity"]` | usage files to read |
| `attention`, `failures` | `true` (not written) | an agent waiting for you; failed units and core dumps |
| `calendars` | `[]` | extra `.ics` links |
| `calendarLeadMinutes` | `15` | how early a meeting shows |
| `holidays` | `"off"` | `auto` (from the timezone) or a country code |
| `weekStart` | `"monday"` | first day in the month view |
| `timerSound` | `true` | a sound when the timer runs out |
| `mediaLingerSeconds` | `30` | how long paused music stays |
| `visualizerColor` | `"accent"` | `accent` or `artwork` |
| `textFont` | `"theme"` | a font family for words; `theme` uses the theme font |
| `barMode` | `true` | `false` forces the floating island |
| `monitor`, `layer`, `scale`, `topMargin`, `clockFormat`, `expandOnHover`, `reserveSpace`, `keybind` | `"primary"`, `"top"`, `1`, Omarchy's gap, `"HH:mm"`, `false`, `false`, `false` | the floating island: monitor (`focused` or a name), layer (`overlay`), size, gap under the bar, its clock, open on hover, keep a strip free (`keybind`, e.g. `"SUPER + ALT + I"`, toggles it) |

## IPC

Target `tusche-island`, e.g. `omarchy-shell tusche-island state`:

- `expand`, `collapse`, `toggle`, `calendar`, `show '<json>'`, `toast <title> <body> <icon> <color>`
- `set noteStyle window|bubble|float`, `set notifications true|false`, `set look dynamic|classic`
- `note open|dismiss|later|next|action:<id>` (the column's buttons, for keybinds), `markRead`
- `alert open|later|dismiss|again` (the expanded dynamic island's buttons, for keybinds)
- `timer 25m [label]`, `timerToggle`, `timerCancel`, `stopwatch start|pause|toggle|reset`
- `activity <id> '<json>'`, `endActivity <id> [message]`, `activities` (live activities for scripts; see `UPSTREAM.md`)
- `addCalendar <link>`, `removeCalendar <link>`, `addCalendarFromClipboard`, `refreshCalendar`
- `reserveSpace on|off|toggle`, `state`, `ping`; `state` carries a `companion` object (`unread`, `alerts`, `dnd`, `blocked`, `working`, `doneSerial`: counts and a counter that moves when an agent finishes) that the Tusche Bar's Omi focus seal reads while the bar is hidden
- Previews: `demo media|paused|recording|mic|split|expanded|volume|brightness|charging|lowbattery|timerdone|track|notification|inbox|timer|stopwatch|activity|calendar|calendar-view|camera|device|outputs|toast|off`, `noteDemo mail|chat|phone|low|critical|actions|burst|story|many`, `attentionDemo on|off`, `agentDoneDemo`, `failureDemo [unit]`, `flash`

## Develop

Run `./dev-install.sh` after every edit (it copies the working tree to `~/.config/omarchy/plugins/nerdibeard.tusche-island` and validates it; the shell hot-reloads it), `node tests/model.cjs` for the model tests, `python3 tests/motion_runtime.py` for the springs (the island's shape, view swap, do-not-disturb switch and output list in a real offscreen Qt) and `python3 tests/dynamic_runtime.py [--shots DIR]` for the dynamic look (pour, neck, gulp, minimal and expanded island, stacked notes, input region and Reduced Motion in a real Qt with OpenGL under `xvfb-run`; `--shots` saves screenshots). The liquid shader is built with `/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 -o views/shaders/liquid.frag.qsb views/shaders/liquid.frag`. `UPSTREAM.md` holds the original activity and scripting documentation; read its plugin ID and `dynamic-island` IPC target as `nerdibeard.tusche-island` and `tusche-island`. Its Apple styling and takeover defaults do not apply here.

## Licence

MIT (`LICENSE`), based on [omarchy-dynamic-island](https://github.com/Arjun010011/omarchy-dynamic-island) by Arjun010011 and contributors.

### Hermes turn status

The existing desktop source can also observe local Hermes Desktop/TUI turn
markers (`hermes: true`, alongside `agents: true`). `hermesHome` selects one
Hermes home; otherwise `HERMES_HOME` or `~/.hermes` is used. It reads only local
turn markers and optional session titles, never sends prompts or credentials,
and opens the existing Hermes window on a user-initiated focus action. Unknown,
stale or dead writer identities never earn a working badge. Missing/broken
observability does not announce completion. Disable `hermes` to stop its
collector; Flux and other agent sources remain independent.

Checks: `node tests/hermes.cjs` and
`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_hermes_status.py'`.


### Corgi status

Corgi is read locally through `corgi list --json` every two seconds while
`agents` and `corgi` are enabled (both default to true). No runtime is started,
no terminal output is read, and no network request is made. Only current panes
are counted; Corgi conversation history is excluded. Working agents appear in
the bar, input requests use the existing attention view, and the expanded
activity/idle panel lists agent tasks and states. Click a row or the attention
view's Open button to select its pane in an unambiguous attached viewer.
A unique terminal window titled Corgi is raised when available. Multiple viewers
in the same workspace are left unchanged rather than guessing a destination.

The collector times out failed snapshots and clears unavailable sources without
announcing completion. Existing completion notifications reflect a transition
back to idle after at least 20 seconds of observed work, not proof of success.
Set `corgi: false` in the Island's bar entry to stop the collector independently
of Flux, Hermes and the other Island sources. You can also use
`omarchy-shell tusche-island set corgi false` (or `true`) locally.

### OpenCode status

OpenCode sessions come from the running OpenCode V2 service while `agents` and
`opencode` are enabled (both default to true). `bin/opencode-status.py` reads
the service's registration (`~/.local/state/opencode/service.json`, a loopback
URL only) and subscribes to its event stream for just the events that change a
session's state: a run starting and ending, permission requests, questions and
renames. It never starts the service and reads no prompts or messages; only
session ids, titles and directories reach the island. A session is working
while a run is in progress, blocked while it waits for a permission or an
answer (subagents report to their top session), idle after a run succeeded.
Failed or stopped runs are never announced as finished. After a reconnect the
collector takes what runs now; events during a gap are missed by the service's
contract. Open raises the OpenCode terminal titled `OC | <session title>`, else
the only OpenCode window; it never guesses between several.

A run counts from its start: waiting for a permission or an answer in between
does not restart the 20 seconds a completion needs (for every agent source).
Set `opencode: false` to stop the collector.

Check: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_opencode_status.py'`.
