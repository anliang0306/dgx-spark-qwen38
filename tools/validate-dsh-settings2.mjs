// Validate every edited settings section against DSH's own schemas.
// Sections checked: llm-pi-ai (provider profiles) and subagent-model-selection.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const DSH = 'C:/Users/anliang/AppData/Roaming/npm/node_modules/@deepseek-ai/dsh';
const NM = DSH + '/node_modules/@deepseek-ai';
const SETTINGS = 'C:/Users/anliang/.dsh/settings.yaml';

const require = createRequire(DSH + '/package.json');
const YAML = require('yaml');
const doc = YAML.parse(readFileSync(SETTINGS, 'utf8'));

let allOk = true;
const report = (label, fn) => {
  try {
    fn();
    console.log(`[PASS] ${label}`);
  } catch (e) {
    allOk = false;
    console.log(`[FAIL] ${label} -> ${e && e.message ? e.message : String(e)}`);
  }
};

// --- 1. llm-pi-ai provider profiles ---
const pi = await import(pathToFileURL(NM + '/dsh-llm-pi-ai/lib/index.js').href);
console.log('llm-pi-ai exports:', Object.keys(pi).filter((k) => /config|profile/i.test(k)).join(', '));
report('llm-pi-ai section', () => {
  if (typeof pi.Config !== 'function') throw new Error('Config not exported');
  pi.Config(doc['llm-pi-ai']);
});

// --- 2. subagent-model-selection ---
const ms = await import(pathToFileURL(NM + '/dsh-tool-subagent/lib/model-selection-settings.js').href);
const schema = ms.SUBAGENT_MODEL_SELECTION_SETTINGS_SCHEMA;
console.log('subagent-model-selection exports:', Object.keys(ms).filter((k) => /SCHEMA|NAMESPACE|name/i.test(k)).join(', '));
report('subagent-model-selection section', () => {
  if (typeof schema !== 'function') throw new Error('schema not callable');
  const out = schema(doc['subagent-model-selection']);
  console.log('        resolved:', JSON.stringify(out));
});

// --- 3. show what the provider resolves to ---
console.log('\nprovider section as parsed:');
console.log(JSON.stringify(doc['llm-pi-ai'], null, 2));

console.log('\nRESULT:', allOk ? 'ALL SECTIONS VALID' : 'AT LEAST ONE SECTION REJECTED');
process.exitCode = allOk ? 0 : 1;
