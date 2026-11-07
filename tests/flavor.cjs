// node tests/flavor.cjs — contract validation and real IPC setter behavior.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'IslandModel.js'), 'utf8').replace('.pragma library', ''), model);
assert.equal(model.defaultSettings.flavor, '');
for (const flavor of ['', 'funk', 'register', 'umbra', 'tusche']) assert.equal(model.flavor(flavor), flavor);
for (const unknown of [null, undefined, 'today', 'Funk', 'unknown']) assert.equal(model.flavor(unknown), '');
for (const flavor of ['', 'register', 'umbra', 'tusche']) {
  const lead = model.agentLead(2, flavor, false, '#ffd68f');
  assert.equal(lead.text, '2');
  assert.equal(lead.glyph, '\u{f06a9}');
  assert.equal(lead.tone, '#ffd68f');
  assert.equal(model.completionTitle('Agent finished', flavor), 'Agent finished');
}
assert.equal(model.agentLead(3, 'funk', false, 'yellow').text, '3 ON AIR');
assert.equal(model.agentLead(3, 'funk', false, 'yellow').tone, '#ff6b7d');
assert.equal(model.agentLead(3, 'funk', true, 'yellow').text, '3', 'minimal capsules retain their existing content');
assert.equal(model.completionTitle('Agent finished', 'funk'), 'SIGNAL · Agent finished');
for (const critical of [false, true]) {
  const entry = { summary: 'Agent finished', body: 'Done · Build', critical };
  assert.equal(model.isAgentCompletion(entry), true);
  assert.equal(model.isAlertNote(entry), !critical, 'critical completions keep banner routing');
}
assert.equal(model.isAgentCompletion({ summary: 'Agent finished', body: 'Unrelated' }), false);
assert.equal(model.isAgentCompletion({ summary: 'Build', body: 'Done · Build' }), false);
assert.equal(model.isAgentCompletion(null), false);

// Exercise the production IPC setter. Bad values must leave settings alone.
const source = fs.readFileSync(path.join(__dirname, '..', 'Island.qml'), 'utf8');
const setter = source.split('    function set(key: string, value: string): string {')[1].split('\n    // Sample notifications')[0];
const saved = [];
const sandbox = { Model: model, root: { saveSettings: update => saved.push(update) } };
vm.createContext(sandbox);
vm.runInContext('function set(key, value) {' + setter, sandbox);
for (const flavor of ['', 'funk', 'register', 'umbra', 'tusche']) {
  sandbox.set('flavor', flavor);
  assert.equal(saved.at(-1).flavor, flavor);
}
const count = saved.length;
assert.match(sandbox.set('flavor', 'today'), /^usage:/);
assert.equal(saved.length, count);
console.log('Flavor defaults, agent content, completion routing and IPC validation ok');
