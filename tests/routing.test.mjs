import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const source = fs.readFileSync(new URL('Script.js', root), 'utf8');
const context = vm.createContext({});
vm.runInContext(source, context);
const input = { proxies: [{ name: 'TestNode', type: 'ss' }], 'proxy-groups': [{ name: 'Proxy', type: 'select', proxies: ['TestNode'] }], rules: ['MATCH,Proxy'] };
const output = context.main(structuredClone(input));
const names = ['UnityGlobal', 'UnityWeb', 'UnityHub', 'UnityEditor', 'UnityDownload', 'UnityChina', 'NvidiaServices', 'NvidiaDownload', 'SteamCommunity', 'SteamMainland', 'SteamDownload', 'BilibiliVideo'];
assert.deepEqual(Array.from(output['proxy-groups'].filter(g => names.includes(g.name)), g => g.name).sort(), names.sort());
for (const name of ['NvidiaServices','NvidiaDownload','SteamMainland','SteamDownload','BilibiliVideo']) {
  assert.equal(output['proxy-groups'].find(g => g.name === name).proxies[0], 'DIRECT');
}
assert.equal(output['proxy-groups'].find(g => g.name === 'UnityChina').proxies[0], 'REJECT');
for (const name of ['UnityWeb','UnityHub','UnityEditor','UnityDownload']) assert.equal(output['proxy-groups'].find(g => g.name === name).proxies[0], 'UnityGlobal');
assert(output.rules.indexOf('DOMAIN-SUFFIX,download.nvidia.cn,NvidiaDownload') < output.rules.indexOf('DOMAIN-SUFFIX,nvidia.cn,NvidiaServices'));
assert(output.rules.indexOf('DOMAIN-SUFFIX,download.nvidia.com,NvidiaDownload') < output.rules.indexOf('DOMAIN-SUFFIX,nvidia.com,NvidiaServices'));
assert.deepEqual(JSON.parse(JSON.stringify(context.main(output))), JSON.parse(JSON.stringify(output)));
const composition = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[2], 'utf8'), composition);
const combined = composition.main(structuredClone(input), 'Owner');
assert.equal(combined.owner, true);
assert.equal(combined.ownerProfile, 'Owner');
assert.deepEqual(JSON.parse(JSON.stringify(combined['proxy-groups'])), JSON.parse(JSON.stringify(output['proxy-groups'])));

// A full subscription already contains business selectors, including UnityWeb.
// Check every selectable edge, not only the first/default choice.
function assertAcyclicGroups(config) {
  const groups = new Map(config['proxy-groups'].map(group => [group.name, group]));
  assert.equal(groups.size, config['proxy-groups'].length, 'group names must be unique');
  const terminals = new Set(['DIRECT', 'REJECT', ...config.proxies.map(proxy => proxy.name)]);
  const completed = new Set();
  const visit = (name, path = []) => {
    if (terminals.has(name)) return;
    assert(groups.has(name), `unresolved group/proxy: ${name}`);
    assert(!path.includes(name), `proxy group cycle: ${[...path, name].join(' -> ')}`);
    if (completed.has(name)) return;
    for (const next of groups.get(name).proxies) visit(next, [...path, name]);
    completed.add(name);
  };
  for (const name of groups.keys()) visit(name);
}
const complete = JSON.parse(fs.readFileSync(new URL('tests/fixtures/complete-business-groups.json', root), 'utf8'));
assert.equal(complete['proxy-groups'].length, 24);
assertAcyclicGroups(complete);
const legacyBytes = fs.readFileSync(new URL('tests/fixtures/legacy-routing-v1.5.0.js.txt', root));
assert.equal(createHash('sha256').update(legacyBytes).digest('hex'), '276675aeac79a9bbc2b002700628f389b03f5d8deec1f42772609ac83cecc9c7');
const legacyContext = vm.createContext({});
vm.runInContext(legacyBytes.toString('utf8'), legacyContext);
assert.throws(() => assertAcyclicGroups(legacyContext.main(structuredClone(complete))),
  /proxy group cycle: UnityGlobal -> UnityWeb -> UnityGlobal/,
  'public v1.5.0 reproduces the old global-script/new-subscription cycle');
for (const orderedInput of [complete, { ...complete, 'proxy-groups': [...complete['proxy-groups']].reverse() }]) {
  const routed = context.main(structuredClone(orderedInput));
  assertAcyclicGroups(routed);
  assert.equal(routed['proxy-groups'].length, 24);
  const parent = routed['proxy-groups'].find(group => group.name === 'UnityGlobal');
  assert(!parent.proxies.some(name => names.includes(name)), 'UnityGlobal must exclude all managed business selectors');
  assert.equal(routed['proxy-groups'].find(group => group.name === 'UnityWeb').proxies[0], 'UnityGlobal');
  for (const unmanaged of orderedInput['proxy-groups'].filter(group => !names.includes(group.name))) {
    assert.deepEqual(routed['proxy-groups'].find(group => group.name === unmanaged.name), unmanaged);
  }
  const rerouted = context.main(structuredClone(routed));
  assertAcyclicGroups(rerouted);
  assert.deepEqual(JSON.parse(JSON.stringify(rerouted)), JSON.parse(JSON.stringify(routed)));
  const composed = composition.main(structuredClone(orderedInput), 'FullSubscription');
  assertAcyclicGroups(composed);
  assert.equal(composed.ownerProfile, 'FullSubscription');
  assert.deepEqual(JSON.parse(JSON.stringify(composed['proxy-groups'])), JSON.parse(JSON.stringify(routed['proxy-groups'])));
}
console.log('24-group subscription regression passed: legacy cycle reproduced; current, repeated, reordered and composed graphs are acyclic.');
const domains = JSON.parse(fs.readFileSync(new URL('config/claude-privacy-domains.json', root), 'utf8'));
assert.equal(domains.schemaVersion, 1);
assert.equal(new Set(domains.domainSuffixes).size, 6);
assert.deepEqual([...domains.domainSuffixes].sort(), ['anthropic.com','claude.ai','claude.com','claude.app','claudeusercontent.com','claudemcpcontent.com'].sort());
assert(domains.domainSuffixes.every(d => /^[a-z0-9]+(?:[.-][a-z0-9]+)*\.[a-z]+$/.test(d)));
console.log('JavaScript routing, composition, and domain schema assertions passed.');
