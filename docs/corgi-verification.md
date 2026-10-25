# Corgi status verification · 2026-10-25

Installed locally on nerdbase2, source branch `feat/corgi-status-20261025`.
The baseline preserves the previously installed flat glass/motion files.

- Python tests: 13 passing (Hermes and Corgi); Corgi states, current panes only,
  timeouts/unavailability, bounds, unique viewer selection, closed pane rejection.
- Node suites: model.cjs, hermes.cjs and corgi.cjs pass. Coverage includes real
  lifecycle handler with a fake clock: no completion on loss/reconnect/unknown,
  one completion after a qualifying observed working-to-idle transition; focus
  argv, fixed local focus script, PlainText views and dynamic panel sizes.
- QML parser checks on changed QML and plugin validation pass.
- Live source: Corgi reports two current panes; Island receives both and shows
  the active task. Source disable clears Corgi observations with no completion;
  re-enable restores them. Existing Flux/Hermes/phone/calendar remain available.
- Native expanded popup captured and visually inspected. Focus helper selects
  pane 7 in viewer 1 and raises the existing Ghostty window titled Corgi; prior
  active desktop window restored afterward.
- Independent Claude Opus 5.5 review: concrete findings about focus-script trust,
  null filtering, closed panes, viewer validation, reconnect flashing and the
  close button addressed. Speculation that viewers is under result disproved by
  real CLI output and successful live focus. No session dedupe is performed:
  Flux does not expose the same identity in the observed snapshot.
- Scope: no physical mouse click or genuine blocked-agent dialog exercised;
  blocked mapping and focus routing verified with tests, existing requester reused.
  A real post-task completion is not awaited.

Recovery: restore only this plugin's manifest and installed-generation.json
from `~/.local/state/tusche-island-corgi/20261025-161150/`, then rescan plugins.
Do not restore the whole shell.json. The only config addition is `corgi: true`
on the existing Island bar entry. Old immutable generations are retained.
Source toggle: `omarchy-shell tusche-island set corgi false` / `true`.
