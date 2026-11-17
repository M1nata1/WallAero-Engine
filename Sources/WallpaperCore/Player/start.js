// WallAero Engine: the player of Wallpaper Engine's own scenes.
// Generated and rewritten when the app updates.
//
// A scene of Wallpaper Engine's is a list of objects on a canvas: pictures, each with a chain of
// effects drawn by shaders; particles; sounds. The scene's own files say all of it — they lie in
// the table the page loads before this script — and this draws them with WebGL. The shaders are
// the scene's own, written in Wallpaper Engine's dialect of GLSL; they are translated to the
// GLSL this browser compiles the way Wallpaper Engine itself does it on phones. What a scene
// leaves to Wallpaper Engine — the headers its shaders include, the textures it names without
// bringing them — is made here.
(function () {
  'use strict';

  // What the player has to say of the scene: what it left out, and why.
  var notes = [];
  function note(text) {
    if (notes.length < 100 && notes.indexOf(text) < 0) notes.push(text);
  }

  // The editor's clock: in the editor the scene's time is the timeline's. The scene then
  // stands still unless the editor plays it (`held`), and goes to the moment the editor
  // names; what comes by chance comes the same each time it plays from the start, so that
  // a moment looks the same however it was come to.
  var editorClock = { on: window.__wallaeroEditorClock === true, held: window.__wallaeroEditorClock === true };
  // For a test that must come out the same each time it runs (`--freeze`): the date the
  // scene is told is a fixed one, `window.__wallaeroTestEpoch` milliseconds, on by the scene's
  // own time; and the editor's steps to a moment are never cut short by how long they take.
  var realNow = Date.now;
  var testClock = typeof window.__wallaeroTestEpoch === 'number' ? { epoch: window.__wallaeroTestEpoch, at: 0 } : null;
  if (testClock) {
    var RealDate = Date;
    var TestDate = function () {
      if (!(this instanceof TestDate)) return new RealDate(testClock.epoch + testClock.at).toString();
      if (arguments.length === 0) return new RealDate(testClock.epoch + testClock.at);
      return new (Function.prototype.bind.apply(RealDate, [null].concat(Array.prototype.slice.call(arguments))))();
    };
    TestDate.prototype = RealDate.prototype;
    TestDate.now = function () { return testClock.epoch + testClock.at; };
    TestDate.UTC = RealDate.UTC;
    TestDate.parse = RealDate.parse;
    window.Date = TestDate;
    Date = TestDate;
  }
  var unseeded = Math.random;
  // How the editor looks at the scene: through its camera, as the wallpaper shows it, or
  // freely — a flat scene whole, without the camera's moves, zoom, shake or parallax; one in
  // three dimensions from where the editor has its own eye (`look`: eye, center, up).
  // `flat`: half the height seen, for one in three dimensions looked at flat, without
  // perspective, as Unity's 2D view does.
  var editorView = { free: false, look: null, flat: 0 };
  // `key` gives another sequence for each moment (see `goOn`).
  function seedChance(key) {
    var state = (0x2545F491 ^ Math.imul(key | 0, 0x9E3779B1)) | 0;
    Math.random = function () {
      state = (state + 0x6D2B79F5) | 0;
      var t = Math.imul(state ^ (state >>> 15), 1 | state);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

