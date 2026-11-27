// Every key of TheFishingLogDB that the code touches must be listed in World.lua as belonging to
// one world (WORLD_KEYS) or to the whole account (ACCOUNT_KEYS). A key in neither list would be
// shown to every world without anyone having decided that. Run from the repository root.
const fs = require('fs');
const path = require('path');
const root = path.resolve('.');
const world = fs.readFileSync(path.join(root, 'World.lua'), 'utf8');
function list(name) {
  const m = world.match(new RegExp('MF\\.' + name + '\\s*=\\s*\\{([^}]*)\\}'));
  if (!m) throw new Error('World.lua has no ' + name);
  return (m[1].replace(/--[^\n]*/g, '').match(/"([^"]+)"/g) || []).map(s => s.slice(1, -1));
}
const sorted = new Map();
for (const [name, kind] of [['WORLD_KEYS', 'world'], ['ACCOUNT_KEYS', 'account']]) {
  for (const key of list(name)) {
    if (sorted.has(key)) throw new Error(key + ' is listed twice in World.lua');
    sorted.set(key, kind);
  }
}
const files = fs.readFileSync(path.join(root, 'TheFishingLogTest.toc'), 'utf8').split(/\r?\n/)
  .filter(line => /\.lua\s*$/.test(line) && !line.startsWith('#') && !/^Libs/i.test(line)).map(line => line.trim());
const used = new Map();
function note(key, file) { if (!used.has(key)) used.set(key, file); }
for (const file of files) {
  // comments are skipped so a key named in prose doesn't count as a use
  const text = fs.readFileSync(path.join(root, file.replace(/\\/g, '/')), 'utf8').replace(/--[^\n]*/g, '');
  for (const m of text.matchAll(/\b(?:self|MF)\.db\.([A-Za-z_]\w*)/g)) note(m[1], file);
  // "local db = self.db" (or TheFishingLogDB) followed by db.key
  if (/\blocal\s+db\s*=\s*(?:(?:self|MF)\.db|TheFishingLogDB)\b/.test(text)) {
    for (const m of text.matchAll(/(?<![\w.])db\.([A-Za-z_]\w*)/g)) note(m[1], file);
  }
}
if (used.size < 40) throw new Error('only found ' + used.size + ' saved-data keys; the scan is broken');
const unsorted = [...used].filter(([key]) => !sorted.has(key)).map(([key, file]) => `${key} (${file})`).sort();
if (unsorted.length) { console.log('FAIL: sort these into WORLD_KEYS or ACCOUNT_KEYS in World.lua: ' + unsorted.join(', ')); process.exit(1); }
const unusedWorld = [...sorted].filter(([key, kind]) => kind === 'world' && !used.has(key)).map(([key]) => key);
console.log(`PASS: all ${used.size} saved-data keys used in ${files.length} files are sorted as world or account` +
  (unusedWorld.length ? `; listed as world but not seen in code: ${unusedWorld.join(' ')}` : ''));
