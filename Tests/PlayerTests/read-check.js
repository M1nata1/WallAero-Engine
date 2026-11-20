'use strict';
// Compares what the app reads of each scene's JSON files (written by WallpaperEngineReadCheck)
// with the files as written, as the player parses them:  node read-check.js <library> <read folder>
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const [library, readFolder] = process.argv.slice(2);
function parse(text) {
  try { return JSON.parse(text); } catch (e) {
    try { return JSON.parse(text.replace(/,(\s*[}\]])/g, '$1')); } catch (again) { return undefined; }
  }
}
let scenes = 0, files = 0, differ = 0, unread = 0;
for (const name of fs.readdirSync(readFolder)) {
  const folder = path.join(library, 'Web', name.replace(/\.json$/, ''), 'engine');
  let table;
  if (fs.existsSync(path.join(folder, 'files.json'))) table = JSON.parse(fs.readFileSync(path.join(folder, 'files.json'), 'utf8'));
  else table = JSON.parse(fs.readFileSync(path.join(folder, 'files.js'), 'utf8').replace(/^window\.wallaeroEngineScene = /, '').replace(/;\s*$/, ''));
  const read = JSON.parse(fs.readFileSync(path.join(readFolder, name), 'utf8'));
  scenes++;
  for (const file of Object.keys(table.files)) {
    if (!file.endsWith('.json')) continue;
    const written = parse(table.files[file]);
    if (!(file in read)) { if (written !== undefined) { unread++; console.log('not read but readable:', name, file); } continue; }
    files++;
    try { assert.deepStrictEqual(JSON.parse(read[file]), written); } catch (e) { differ++; console.log('differs:', name, file); }
  }
}
console.log(`${scenes} scenes, ${files} JSON files read, ${differ} differ, ${unread} readable files not read`);
process.exit(differ || unread ? 1 : 0);
