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
console.log('model tests ok');
