import assert from 'node:assert/strict';
import fs from 'node:fs';
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
const domains = JSON.parse(fs.readFileSync(new URL('config/claude-privacy-domains.json', root), 'utf8'));
assert.equal(domains.schemaVersion, 1);
assert.equal(new Set(domains.domainSuffixes).size, 6);
assert.deepEqual([...domains.domainSuffixes].sort(), ['anthropic.com','claude.ai','claude.com','claude.app','claudeusercontent.com','claudemcpcontent.com'].sort());
assert(domains.domainSuffixes.every(d => /^[a-z0-9]+(?:[.-][a-z0-9]+)*\.[a-z]+$/.test(d)));
console.log('JavaScript routing, composition, and domain schema assertions passed.');
