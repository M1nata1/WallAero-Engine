'use strict';
// Tests of the scene player's parts that do not draw: run with `node --test Tests/PlayerTests`
// (also from `swift test`, by PlayerScriptTests, where node is installed).
const test = require('node:test');
const assert = require('node:assert');
const { load, shaderFiles } = require('./player.js');

const engine = load();

test('the player loads and offers what the app calls', () => {
  for (const name of ['play', 'translate', 'mend', 'numbers']) {
    assert.strictEqual(typeof engine[name], 'function', name);
  }
});

test('the player answers what the app asks it, as PlayerBridge.swift names it', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const bridge = fs.readFileSync(path.join(__dirname, '../../Sources/WallpaperCore/PlayerBridge.swift'), 'utf8');
  const list = /public static let names: Set<String> = \[([^\]]*)\]/.exec(bridge);
  assert.ok(list, 'PlayerQueries.names is not found in PlayerBridge.swift');
  const names = list[1].match(/"[^"]+"/g).map((each) => JSON.parse(each)).sort();
  assert.deepStrictEqual(Object.keys(engine.api).sort(), names);
  for (const name of names) assert.strictEqual(typeof engine.api[name], 'function', name);
});

test('an animation without handles goes straight from moment to moment', () => {
  const loop = { c0: [{ frame: 0, value: 0 }, { frame: 30, value: 10 }], options: { fps: 30, length: 30, mode: 'loop' } };
  assert.deepStrictEqual([0, 0.25, 0.5, 0.75].map((t) => engine.api.curveValue(loop, t, [0])[0]), [0, 2.5, 5, 7.5]);
  // A loop starts over at its length.
  assert.strictEqual(engine.api.curveValue(loop, 1, [0])[0], 0);
  assert.strictEqual(engine.api.curveValue(loop, 1.5, [0])[0], 5);
});

test('an animation played once stays at its end', () => {
  const once = { c0: [{ frame: 0, value: 0 }, { frame: 30, value: 10 }], options: { fps: 30, length: 30, mode: 'single' } };
  assert.deepStrictEqual([0, 0.5, 1, 2].map((t) => engine.api.curveValue(once, t, [0])[0]), [0, 5, 10, 10]);
});

test('a relative animation adds to the value it is given', () => {
  const relative = { c0: [{ frame: 0, value: 0 }, { frame: 30, value: 10 }], options: { fps: 30, length: 30, mode: 'loop' }, relative: true };
  assert.deepStrictEqual([0, 0.5].map((t) => engine.api.curveValue(relative, t, [5])[0]), [5, 10]);
});

test('curves come out as the shared cases say (Tests/Fixtures/we-format/curves.json)', () => {
  // curves.js alone, as the app runs it for the editor (WallpaperEngineCurves.swift).
  const fs = require('fs');
  const path = require('path');
  const vm = require('vm');
  const page = {};
  vm.createContext(page);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', '..', 'Sources', 'WallpaperCore', 'Player', 'curves.js'), 'utf8'), page);
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'Fixtures', 'we-format', 'curves.json'), 'utf8'));
  for (const each of fixture.cases) {
    const curve = page.curveOf(fixture.animations[each.animation]);
    const got = 'frame' in each ? curve.atFrame(each.frame, each.base) : curve(each.seconds, each.base);
    got.forEach((value, index) => assert.ok(Math.abs(value - each.expected[index]) < 1e-6, `${each.animation} ${JSON.stringify(each)}: ${got}`));
    // The whole player works them out the same way.
    if ('seconds' in each) assert.deepStrictEqual(engine.api.curveValue(fixture.animations[each.animation], each.seconds, each.base), got);
  }
});

test('the table of values left unsaid is plain JSON, as the app reads it (WallpaperEngineDefaults.swift)', () => {
  const fs = require('fs');
  const path = require('path');
  const script = fs.readFileSync(path.join(__dirname, '..', '..', 'Sources', 'WallpaperCore', 'Player', 'defaults.js'), 'utf8');
  const start = script.indexOf('var defaults = ') + 'var defaults = '.length;
  const table = JSON.parse(script.slice(start, script.lastIndexOf(';')));
  assert.strictEqual(table.particles.operators.turbulence.speedmax, 200);
  assert.strictEqual(table.particles.emitter.rate, 5);
});

test('names are known as the shared cases say (Tests/Fixtures/we-format/names.json)', () => {
  const fs = require('fs');
  const path = require('path');
  const vm = require('vm');
  const page = {};
  vm.createContext(page);
  // values.js alone: it opens nothing and needs nothing.
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', '..', 'Sources', 'WallpaperCore', 'Player', 'values.js'), 'utf8'), page);
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'Fixtures', 'we-format', 'names.json'), 'utf8'));
  for (const each of fixture.cases) assert.strictEqual(page.key(each.name), each.key, each.name);
});

test('numbers are read from text, one number or none', () => {
  assert.deepStrictEqual(Array.from(engine.numbers('1 2', 3, 7)), [1, 2, 7]);
  assert.deepStrictEqual(Array.from(engine.numbers(4, 3, 0)), [4, 4, 4]);
  assert.deepStrictEqual(Array.from(engine.numbers(undefined, 2, 9)), [9, 9]);
});

test('a script is checked without being run', () => {
  assert.strictEqual(engine.api.checkScript('export function update(value) { return value + 1; }'), null);
  const refused = engine.api.checkScript('export function update( {');
  assert.ok(refused && typeof refused.message === 'string');
});

test('the settings a script declares are read', () => {
  const declared = engine.api.scriptDeclares('export var scriptProperties = createScriptProperties()' +
    '.addSlider({ name: "speed", label: "Speed", value: 2, min: 0, max: 5 }).finish();' +
    'export function update(v) { return v; }');
  // (made in the player's own context, so compared as JSON)
  assert.deepStrictEqual(JSON.parse(JSON.stringify(declared)), [{ name: 'speed', label: 'Speed', value: 2, min: 0, max: 5, kind: 'slider' }]);
});

test('Wallpaper Engine\'s own shaders are translated to GLSL ES 3.00', (t) => {
  const files = shaderFiles();
  if (!files) return t.skip('Wallpaper Engine is not installed in ~/Documents/Personalization/WallPaperEngine');
  let count = 0;
  for (const name of Object.keys(files)) {
    // The HLSL folder holds Direct3D's own, not shaders of scenes.
    if (!/\.(frag|vert)$/.test(name) || name.startsWith('shaders/HLSL/')) continue;
    const text = engine.translate(files[name], name.endsWith('.vert') ? 'vertex' : 'fragment', {}, files);
    assert.match(text, /^#version 300 es\n/, name);
    assert.match(text, /void main\s*\(/, name);
    count++;
  }
  assert.ok(count > 50, `only ${count} shaders found`);
});
