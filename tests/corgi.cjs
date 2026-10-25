const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'IslandModel.js'), 'utf8').replace('.pragma library', ''), model);
const plain = x => JSON.parse(JSON.stringify(x));
const corgi = {available:true, agents:[{pane:'corgi:7',session:'same',status:'working',source:'corgi',focusScript:'/untrusted/evil.py'}]};
const flux = {herdr:{running:true,agents:[{pane:'legacy',session:'same'},{pane:'other'}]}};
assert.deepEqual(plain(model.desktopAgents(flux, {}, true, true, false, corgi, true)), [...flux.herdr.agents,...corgi.agents]);
assert.deepEqual(plain(model.desktopAgents({}, {}, true, false, false, corgi, true)), corgi.agents);
assert.deepEqual(plain(model.desktopAgents({herdr:{running:true,agents:[null]}}, {}, true, true, false)), []);
assert.deepEqual(plain(model.agentFocusCommand(corgi.agents[0])), []);
assert.deepEqual(plain(model.agentFocusCommand({pane:'corgi:7', focusScript:'/evil.py'}, '/local/helper.py')), []);
assert.deepEqual(plain(model.agentDoneCommand(corgi.agents[0], '/local/corgi-status.py')).slice(-4), ['python3','/local/corgi-status.py','--focus','7']);
assert.deepEqual(plain(model.desktopAgents({}, {}, true, false, false, corgi, false)), []);
assert.deepEqual(plain(model.agentFocusCommand(corgi.agents[0], '/local/corgi-status.py')), ['python3','/local/corgi-status.py','--focus','7']);
assert.deepEqual(plain(model.agentFocusCommand({...corgi.agents[0],pane:'corgi:7;bad'})), []);
// Exercise the real transition handler: a dropped source/reconnect never completes.
const desktop = fs.readFileSync(path.join(__dirname, '..', 'sources/Desktop.qml'), 'utf8');
const handler = desktop.split('  onAgentsChanged: {')[1].split('\n  // Working agents')[0].trim().slice(0,-1);
let now = 10000; const done = [];
const state = {Date:{now:()=>now},agents:[],seen:{},primed:false,agentDoneEnabled:true,
 fluxState:{},hermesState:{},corgiState:{available:true},syncActivity(){},island:{flash(){},announceAgentDone(a){done.push(a)}}};
const step = (agents, ms) => {now+=ms;state.agents=agents;vm.runInNewContext(handler,state)};
const a = status=>[{pane:'corgi:7',status}];
step(a('idle'),0); step(a('working'),0); step([],25000); step(a('idle'),0);
assert.equal(done.length,0);
step(a('working'),0); step(a('unknown'),25000); step(a('idle'),0);
assert.equal(done.length,0);
step(a('working'),0); step(a('idle'),25000); step(a('idle'),1000);
assert.equal(done.length,1);
assert.equal(model.sizeFor('activity-expanded',{agents:2,agentActivity:true}).h,160);
assert.equal(model.sizeFor('idle-expanded',{agents:2}).h,288);
for (const f of ['AgentList.qml','RequesterView.qml','ActivityExpanded.qml']) {
 const qml=fs.readFileSync(path.join(__dirname,'..','views',f),'utf8');
 assert.equal((qml.match(/\bText\s*\{/g)||[]).length,(qml.match(/textFormat:\s*Text.PlainText/g)||[]).length,f);
}
console.log('Corgi merge, focus, lifecycle, geometry and plain text tests ok');
