const fs = require('fs');
const path = require('path');
const parser = require('./lua-parser/node_modules/luaparse');
const root = path.resolve('.');
let count = 0;
function walk(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes:true})) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) { if (entry.name !== 'tests' && !entry.name.startsWith('.')) walk(file); }
    else if (entry.name.endsWith('.lua')) {
      try { parser.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''), {luaVersion:'5.1'}); }
      catch (err) { throw new Error(`${file}: ${err.message}`); }
      count++;
    }
  }
}
walk(root);
const files = fs.readFileSync(path.join(root, 'TheFishingLogTest.toc'),'utf8').split(/\r?\n/).filter(line=>line && !line.startsWith('#'));
for (const file of files) if (!fs.existsSync(path.join(root, file))) throw new Error(`Missing TOC file: ${file}`);
if (files.indexOf('Rework\\AnglerPortrait.lua') > files.indexOf('Rework\\Journal.lua')) throw new Error('Portrait must load before journal');
console.log(`PASS: ${count} Lua files parse as Lua 5.1; all ${files.length} TOC entries exist and portrait loads before journal`);
