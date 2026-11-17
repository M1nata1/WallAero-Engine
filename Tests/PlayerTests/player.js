'use strict';
// The scene player as a page runs it, for tests: its files joined in order.txt's order and run
// with just enough of a page around it to load (nothing is drawn). Gives window.WallaeroEngine.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const folder = path.join(__dirname, '..', '..', 'Sources', 'WallpaperCore', 'Player');

function source() {
  return fs.readFileSync(path.join(folder, 'order.txt'), 'utf8').split('\n')
    .map((line) => line.trim()).filter((line) => line && !line.startsWith('#'))
    .map((name) => fs.readFileSync(path.join(folder, name), 'utf8')).join('');
}

function load(extra) {
  const page = Object.assign({ console }, extra || {});
  page.window = page;
  page.document = {
    createElement: () => ({ getContext: () => null, style: {}, addEventListener() {} }),
    addEventListener() {},
    body: { appendChild() {} },
  };
  vm.createContext(page);
  vm.runInContext(source(), page, { filename: 'engine.js' });
  return page.WallaeroEngine;
}

// Wallpaper Engine's own shaders, where it is installed beside the app's folder of work.
const weShaders = path.join(process.env.HOME || '', 'Documents', 'Personalization', 'WallPaperEngine', 'assets', 'shaders');

function shaderFiles() {
  if (!fs.existsSync(weShaders)) return null;
  const files = {};
  (function walk(dir, prefix) {
    for (const name of fs.readdirSync(dir)) {
      const full = path.join(dir, name);
      if (fs.statSync(full).isDirectory()) walk(full, prefix + name + '/');
      else files['shaders/' + prefix + name] = fs.readFileSync(full, 'utf8');
    }
  })(weShaders, '');
  return files;
}

module.exports = { load, source, shaderFiles };
