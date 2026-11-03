// node tests/model.cjs — pure helpers of IslandModel.js (notes column).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'IslandModel.js'), 'utf8').replace('.pragma library', ''), ctx);
const n = (key, extra = {}) => ({ key, time: key, critical: false, low: false, actions: [], timeout: 0, ...extra });

// Completion cards are normal (DND-aware), with literal argv and click routing.
const done = a => Array.from(ctx.agentDoneCommand(a));
const trickyTitle = '--exec $(touch /tmp/not-executed) <b>preview</b>';
const command = done({ agent: 'Claude', title: trickyTitle, pane: 'pane with spaces' });
assert.equal(command[command.indexOf('-u') + 1], 'normal');
assert.ok(command.includes('Done · ' + trickyTitle));
assert.deepEqual(command.slice(-5), ['--exec', 'herdr', 'agent', 'focus', 'pane with spaces']);
assert.deepEqual(done({ pane: 'oc:test' }).slice(-3), ['--exec', 'xdg-open', 'http://127.0.0.1:18789/']);
assert.ok(!done({}).includes('--exec'), 'preview has no focus action');

// Run the real source handler with a fake clock: no startup/short-run/repeat
// notifications; one completion after a qualifying working → idle transition.
{
  const desktop = fs.readFileSync(path.join(__dirname, '..', 'sources', 'Desktop.qml'), 'utf8');
  const handler = desktop.split('  onAgentsChanged: {')[1].split('\n  // Working agents')[0].trim().slice(0, -1);
  let now = 100000;
  const completions = [];
  const state = { Date: { now: () => now }, agents: [], seen: {}, primed: false,
    agentDoneEnabled: true, fluxState: { herdr: {} }, syncActivity() {},
    island: { flash() {}, announceAgentDone(a) { completions.push(a); } } };
  const step = (status, elapsed) => {
    now += elapsed;
    state.agents = [{ pane: 'test:1', agent: 'Codex', status }];
    vm.runInNewContext(handler, state);
  };
  step('idle', 0);
  step('working', 0);
  step('idle', 1000);
  assert.equal(completions.length, 0);
  step('working', 0);
  step('idle', 20000);
  step('idle', 1000);
  assert.equal(completions.length, 1);
  state.agentDoneEnabled = false;
  step('working', 0);
  step('idle', 25000);
  assert.equal(completions.length, 1);
  state.agentDoneEnabled = true;
  // A long run that asked for a permission near its end still finishes.
  step('working', 0);
  step('blocked', 60000);
  step('working', 30000);
  step('idle', 5000);
  assert.equal(completions.length, 2);
  // ...but a lost observation in between starts the run over.
  step('working', 0);
  step('unknown', 1000);
  step('working', 0);
  step('idle', 5000);
  assert.equal(completions.length, 2);
}

// Live activity files: sanitised, counted by the island itself, coloured by phase.
{
  const T0 = 1793700000;
  const tesla = { title: 'Charging session', icon: '\u{f140b}', color: 'green', startedAt: T0, warnAt: T0 + 13500, endsAt: T0 + 14400, until: T0 + 86400, show: 'remaining' };
  const e = ctx.liveEntry('tesla-charge', tesla, T0 + 60);
  assert.equal(e.title, 'Charging session');
  assert.equal(ctx.liveText(e, T0), '4:00');
  assert.equal(ctx.liveText(e, T0 + 60), '3:59');
  assert.equal(ctx.liveText(e, T0 + 14400 - 47 * 60), '47m');
  assert.equal(ctx.liveText(e, T0 + 14400 - 30), '1m', 'remaining rounds up');
  assert.equal(ctx.liveText(e, T0 + 14400 + 6 * 60), '+6m');
  assert.deepEqual([T0, T0 + 13500, T0 + 14400].map(t => ctx.liveTone(e, t)), ['green', 'orange', 'red']);
  assert.equal(ctx.liveText(ctx.liveEntry('w', { show: 'elapsed', startedAt: T0 }, T0), T0 + 3720), '1:02', 'elapsed rounds down');
  assert.equal(ctx.liveText(ctx.liveEntry('v', { value: 'Backup 3/10' }, T0), T0), 'Backup 3/10');
  // nothing from a file reaches the island unchecked
  for (const [id, v] of [['../x', tesla], ['ok', null], ['ok', [1]], ['ok', { show: 'remaining' }], ['ok', { show: 'elapsed' }],
                         ['ok', { ...tesla, until: T0 - 1 }]])
    assert.equal(ctx.liveEntry(id, v, T0), null, JSON.stringify(id));
  const odd = ctx.liveEntry('odd', { title: 'x'.repeat(200), icon: '<b>long</b>', color: 'javascript:1', show: 'nope', value: 'v'.repeat(50) }, T0);
  assert.deepEqual([odd.title.length, odd.icon.length, odd.color, odd.show, odd.value.length], [60, 4, 'accent', 'value', 12]);
}

// OpenCode sessions: merged when enabled, focused only through the island's
// own helper beside the Corgi one, with a literal session id.
{
  const oc = { available: true, agents: [{ pane: 'opencode:ses_e5fc7d404ffeXJ4n2FNaJPCb8A', source: 'opencode', agent: 'OpenCode', status: 'working' }] };
  const plainList = x => JSON.parse(JSON.stringify(x));
  assert.deepEqual(plainList(ctx.desktopAgents({}, {}, true, false, false, {}, false, oc, true)), oc.agents);
  assert.deepEqual(plainList(ctx.desktopAgents({}, {}, true, false, false, {}, false, oc, false)), []);
  assert.deepEqual(plainList(ctx.desktopAgents({}, {}, true, false, false, {}, false, { available: false, agents: oc.agents }, true)), []);
  const helper = '/plugins/island/generations/g/bin/corgi-status.py';
  assert.deepEqual(Array.from(ctx.agentFocusCommand(oc.agents[0], helper)),
    ['python3', '/plugins/island/generations/g/bin/opencode-status.py', '--focus', 'ses_e5fc7d404ffeXJ4n2FNaJPCb8A']);
  assert.deepEqual(Array.from(ctx.agentDoneCommand(oc.agents[0], helper)).slice(-4),
    ['python3', '/plugins/island/generations/g/bin/opencode-status.py', '--focus', 'ses_e5fc7d404ffeXJ4n2FNaJPCb8A']);
  for (const [agent, script] of [[oc.agents[0], ''], [oc.agents[0], '/evil.py'], [{ ...oc.agents[0], source: 'corgi' }, helper],
      [{ ...oc.agents[0], pane: 'opencode:ses_x; rm -rf ~' }, helper], [{ ...oc.agents[0], pane: 'opencode:../x' }, helper]])
    assert.deepEqual(Array.from(ctx.agentFocusCommand(agent, script)), [], JSON.stringify([agent.pane, agent.source, script]));
}

// FIFO: the oldest normal one is open, the rest wait in arrival order.
let q = ctx.noteQueue([n(3), n(1), n(2)]);
assert.equal(q.current.key, 1);
assert.deepEqual(q.waiting.map(e => e.key), [2, 3]);
// A critical one goes first and the open card waits (paused) behind it.
q = ctx.noteQueue([n(1), n(2), n(3, { critical: true })]);
assert.equal(q.current.key, 3);
assert.deepEqual(q.waiting.map(e => e.key), [1, 2]);
// Two criticals: the older one first, the other critical next in line.
q = ctx.noteQueue([n(1), n(4, { critical: true }), n(2, { critical: true })]);
assert.equal(q.current.key, 2);
assert.deepEqual(q.waiting.map(e => e.key), [4, 1]);
assert.equal(ctx.noteQueue([]).current, null);
// A waiting row pulled to the front opens next (before older ones).
const pulled = [n(1), n(2), n(3)];
pulled[2].order = ctx.frontOrder(pulled);
q = ctx.noteQueue(pulled);
assert.equal(q.current.key, 3);
assert.deepEqual(q.waiting.map(e => e.key), [1, 2]);

// Low without buttons is a line; with buttons or critical it is a card.
assert.equal(ctx.isLineNote(n(1, { low: true })), true);
assert.equal(ctx.isLineNote(n(1, { low: true, actions: [{ id: 'a' }] })), false);
assert.equal(ctx.isLineNote(n(1, { low: true, critical: true })), false);
assert.equal(ctx.isLineNote(n(1)), false);
assert.equal(ctx.isLineNote(n(1, { low: true, execArgv: '["omarchy-menu"]' })), false);

// Stand times: Omarchy's 8 s (low 5 s), a requested timeout up to 30 s even
// with a queue, 5 s with a queue otherwise, critical stays.
assert.equal(ctx.noteDuration(n(1), 0), 8000);
assert.equal(ctx.noteDuration(n(1, { low: true }), 0), 5000);
assert.equal(ctx.noteDuration(n(1, { timeout: 60000 }), 0), 30000);
assert.equal(ctx.noteDuration(n(1, { timeout: 12000 }), 2), 12000);
assert.equal(ctx.noteDuration(n(1), 2), 5000);
assert.equal(ctx.lineDuration(n(1)), 5000);
assert.equal(ctx.lineDuration(n(1, { timeout: 9000 })), 9000);
assert.equal(ctx.noteDuration(n(1, { critical: true }), 0), 0);
assert.equal(ctx.noteDuration(null, 0), 0);

// Unread: entries without the flag (old inbox files) count as unread.
assert.equal(ctx.unreadCount([{ unread: true }, { unread: false }, {}]), 2);

// Alerts: unread critical entries and our own failure notifications only.
assert.equal(ctx.alertCount([{ unread: true, critical: true }, { unread: false, critical: true }, { app: 'systemd' }, { app: 'coredump', unread: true },
  { app: 'mail' }, { app: 'systemd', unread: false }, null, undefined, {}]), 3);
assert.equal(ctx.alertCount(undefined), 0);
// The IPC state carries the counts the bar's companion reads.
{
  const island = fs.readFileSync(path.join(__dirname, '..', 'Island.qml'), 'utf8');
  const block = island.split('companion: {')[1].split('},')[0];
  for (const key of ['unread', 'alerts', 'dnd', 'blocked', 'working', 'doneSerial'])
    assert.ok(new RegExp('\\b' + key + ':').test(block), 'companion.' + key);
  assert.ok(/function announceAgentDone\(agent\) \{\n\s+doneSerial\+\+/.test(island), 'every completion bumps doneSerial');
}

// Defaults the plugin writes into its shell.json entry.
assert.equal(ctx.defaultSettings.noteStyle, 'window');
// noteStyle: "window", "bubble" or "float"; the window's former name and anything unknown read as "window".
assert.equal(ctx.noteStyle('bubble'), 'bubble');
assert.equal(ctx.noteStyle('float'), 'float');
assert.equal(ctx.noteStyle('Float'), 'window');
assert.equal(ctx.noteStyle('window'), 'window');
assert.equal(ctx.noteStyle('workbench'), 'window');
assert.equal(ctx.noteStyle(undefined), 'window');

// The bar's options: the Tusche Bar's plugins[] entry first, the bar's former id as a fallback.
const bar = (plugins) => ctx.barOptions({ plugins });
assert.equal(bar([{ id: 'nerdibeard.tusche-bar', options: { edge: 'theme' } }]).edge, 'theme');
assert.equal(bar([{ id: 'nerdibeard.amiga-bar', options: { edge: 'theme' } }]).edge, 'theme');
assert.equal(bar([{ id: 'nerdibeard.amiga-bar', options: { edge: 'theme' } },
                  { id: 'nerdibeard.tusche-bar', options: { edge: 'none' } }]).edge, 'none');
assert.equal(bar([{ id: 'nerdibeard.tusche-bar' }, { id: 'nerdibeard.amiga-bar', options: { edge: 'theme' } }]).edge, undefined);
assert.equal(bar([{ id: 'someone.else', options: { edge: 'theme' } }]).edge, undefined);
assert.equal(ctx.barOptions({}).edge, undefined);
assert.equal(ctx.defaultSettings.notifications, false);

// Lavur bloom (frame round 03.10.2026, recommendation 6): every note is its own sheet of wet paper –
// no shared tide-line layer, no scallops, no shared gooey layer.
{
  const col = fs.readFileSync(path.join(__dirname, '..', 'NotificationColumn.qml'), 'utf8');
  assert.doesNotMatch(col, /scallop|rimShapes|wetCount/, 'no tide-line layer, scallops or shared ink mask');
  assert.match(col, /InkSheet \{\n\s*id: sheet\n/, 'one sheet per note');
  assert.match(col, /sheet\.parent = bloomArea/, 'the sheets live in the bloom area');
  assert.match(col, /neck: slot\.index === 0/, 'only the first note flares up into the bar');
  assert.match(col, /visible: !!slot\.matHalo && slot\.height > 0 && !column\.bloom/, 'a sheet brings its own halo');
  for (const f of ['InkSheet.qml', 'shaders/gauss.frag.qsb', 'shaders/bloomcut.frag.qsb', 'shaders/restink.frag.qsb', 'shaders/halo.frag.qsb', 'shaders/wetink.frag.qsb'])
    assert.ok(fs.existsSync(path.join(__dirname, '..', 'views', f)), f);
}

// Dynamic look (hybrid design 29.10.2026): a setting, classic by default.
assert.equal(ctx.defaultSettings.look, 'classic');
assert.equal(ctx.look('dynamic'), 'dynamic');
for (const v of ['classic', 'Dynamic', '', undefined, 'window']) assert.equal(ctx.look(v), 'classic');
// An agent's completion notification expands the island instead of a banner;
// nothing else does (a low line, a critical request, an ordinary note).
{
  const argv = Array.from(ctx.agentDoneCommand({ agent: 'Claude', title: 'Liquid Island' }));
  const note = { app: argv[2], glyph: argv[6], summary: argv[7], body: argv[8], critical: false };
  assert.equal(ctx.isAlertNote(note), true);
  assert.equal(ctx.alertSubtitle(note), 'Liquid Island · Claude');
  assert.equal(ctx.isAlertNote({ ...note, critical: true }), false);
  assert.equal(ctx.isAlertNote({ app: 'WhatsApp', summary: 'Sarah', body: 'Hallo', glyph: '' }), false);
  assert.equal(ctx.isAlertNote({ app: 'Claude Code', summary: 'Agent fertig', body: 'nbtiles', glyph: argv[6] }), false);
  assert.equal(ctx.isAlertNote(null), false);
  // restored after a restart (no glyph kept): still the completion by its text
  assert.equal(ctx.isAlertNote({ app: 'Codex', summary: 'Agent finished', body: 'Done · x', glyph: '' }), true);
}
// WCAG luminance for the island's text on black.
assert.ok(Math.abs(ctx.luminance('#ffffff') - 1) < 1e-9 && ctx.luminance('#000') === 0);
assert.ok(ctx.luminance('#efeaf6') > 0.8 && ctx.luminance('#ff110e18') < 0.01);
assert.equal(ctx.luminance('nope'), 0);

// The dynamic island's motion maths (views/Liquid.js, on GlassMath.step).
{
  const lctx = {};
  vm.createContext(lctx);
  const glass = fs.readFileSync(path.join(__dirname, '..', 'views', 'GlassMath.js'), 'utf8').replace('.pragma library', '');
  vm.runInContext('var GlassMath = (function () {' + glass + '; return { step, omega, settled }; })();', lctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'views', 'Liquid.js'), 'utf8')
    .replace('.pragma library', '').replace(/^\.import .*$/m, ''), lctx);
  const L = lctx;
  // compact: halves balanced, as narrow as possible; the clock alone sits in the middle
  assert.equal(L.compactWidth(0, 40, 16, 12), 72);
  assert.equal(L.compactWidth(30, 40, 16, 12), 124);          // the board's capsule: robot + "2" | 21:58
  assert.equal(L.compactWidth(55, 40, 16, 12), 154);
  assert.equal(L.compactWidth(200, 40, 16, 12), 284);        // a long status no longer centres
  // squash and stretch: +16 % falling, -10 % landing at most
  assert.equal(L.stretch(1e6, 1), 0.16);
  assert.equal(L.stretch(-1e6, 1), -0.10);
  assert.ok(Math.abs(L.stretch(260, 1) - 0.1) < 1e-9);
  // springs: "Verspielt" overshoots and lands exactly; a timed fade lands on time; placing is at once
  const card = L.spring(0); L.go(card, 100, L.tune.cardResponse, L.tune.cardDamping);
  let peak = 0, frames = 0;
  while (L.tick(card, 1 / 60) && frames < 600) { peak = Math.max(peak, card.x); frames++; }
  assert.equal(card.x, 100); assert.equal(card.moving, false);
  assert.ok(peak > 103 && peak < 108, 'card overshoot ' + peak);
  const fade = L.spring(0, 0.002); L.fade(fade, 1, L.tune.fade); frames = 0;
  while (L.tick(fade, 1 / 60)) frames++;
  assert.equal(fade.x, 1); assert.ok(frames >= 8 && frames <= 10, 'fade frames ' + frames);
  const now = L.spring(0); L.go(now, 50, 0.4, 0.7, true);
  assert.equal(now.x, 50); assert.equal(now.moving, false);
  const gulp = L.spring(120); L.kick(gulp, 380); assert.equal(gulp.moving, true);
  let wide = 120; while (L.tick(gulp, 1 / 60)) wide = Math.max(wide, gulp.x);
  assert.ok(wide > 124 && gulp.x === 120, 'gulp ' + wide);
}
for (const f of ['shaders/liquid.frag', 'shaders/liquid.frag.qsb', 'LiquidShape.qml', 'DynamicStage.qml', 'DynamicNote.qml', 'DynamicAlert.qml', 'NoteRows.qml'])
  assert.ok(fs.existsSync(path.join(__dirname, '..', 'views', f)), f);
// No version-sensitive caps in the dynamic island's text (sentence case).
for (const f of ['DynamicNote.qml', 'DynamicAlert.qml', 'DynamicStage.qml'])
  assert.doesNotMatch(fs.readFileSync(path.join(__dirname, '..', 'views', f), 'utf8'), /toUpperCase|font\.capitalization/, f);
console.log('model tests ok');
