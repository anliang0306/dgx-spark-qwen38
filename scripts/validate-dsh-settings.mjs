// Validate the edited settings.yaml against DSH's own pi-ai schema.
// Uses the shipped bundled module + the shipped `yaml` parser, so the answer is
// the same one the adapter would reach.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const DSH = 'C:/Users/anliang/AppData/Roaming/npm/node_modules/@deepseek-ai/dsh';
const PI = DSH + '/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js';
const SETTINGS = 'C:/Users/anliang/.dsh/settings.yaml';

const require = createRequire(DSH + '/package.json');
const YAML = require('yaml');

const mod = await import(pathToFileURL(PI).href);
console.log('relevant exports:', Object.keys(mod).filter((k) => /config|profile|resolve|assert/i.test(k)).join(', ') || '(none)');

const doc = YAML.parse(readFileSync(SETTINGS, 'utf8'));
const section = doc['llm-pi-ai'];
console.log('\nllm-pi-ai section as parsed:');
console.log(JSON.stringify(section, null, 2));

let ok = true;
try {
  const Config = mod.Config;
  if (typeof Config === 'function') {
    Config(section);
    console.log('\n[1] Config schema: PASS');
  } else {
    console.log('\n[1] Config schema: not exported as a callable; skipping');
  }
} catch (e) {
  ok = false;
  console.log('\n[1] Config schema: FAIL ->', e && e.message ? e.message : String(e));
}

try {
  if (typeof mod.resolveProfiles === 'function') {
    const m = mod.resolveProfiles(section.providers, 'strict');
    console.log('[2] resolveProfiles(strict): PASS');
    for (const [route, prof] of m) {
      console.log(`    route=${route} displayName=${prof.displayName} apiKeyEnv=${prof.apiKeyEnv}`);
      const errs = prof.modelErrors ? [...prof.modelErrors] : [];
      console.log(`    catalogError=${prof.catalogError ?? 'none'} modelErrors=${errs.length ? JSON.stringify(errs) : 'none'}`);
      for (const mm of prof.models ?? []) {
        console.log(`      model: id=${mm.id} name=${mm.name} ctx=${mm.contextWindow} out=${mm.maxTokens} input=${JSON.stringify(mm.input)}`);
      }
    }
  } else {
    console.log('[2] resolveProfiles: not exported');
  }
} catch (e) {
  ok = false;
  console.log('[2] resolveProfiles(strict): FAIL ->', e && e.message ? e.message : String(e));
}

console.log('\nRESULT:', ok ? 'settings section is VALID' : 'settings section is REJECTED');
process.exitCode = ok ? 0 : 1;
