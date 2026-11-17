
  var current = null;

  // The page is asked what music plays once a scene that shows it plays: the app then starts
  // asking the players, which asks the user's leave for some. Each piece of news goes to the
  // scene playing then, and is kept for one that starts later.
  var mediaHeard = null;
  function hearMedia() {
    if (mediaHeard || typeof window.wallpaperRegisterMediaPropertiesListener !== 'function') return;
    mediaHeard = {};
    [['status', 'wallpaperRegisterMediaStatusListener'], ['properties', 'wallpaperRegisterMediaPropertiesListener'],
     ['thumbnail', 'wallpaperRegisterMediaThumbnailListener'], ['playback', 'wallpaperRegisterMediaPlaybackListener'],
     ['timeline', 'wallpaperRegisterMediaTimelineListener']].forEach(function (pair) {
      window[pair[1]](function (event) {
        mediaHeard[pair[0]] = event;
        if (current && current.media) current.media(pair[0], event);
      });
    });
  }
  function showsMedia(scene) {
    var files = (scene && scene.files) || {};
    return Object.keys(files).some(function (name) {
      return typeof files[name] === 'string' && /\$media|media(Status|Properties|Thumbnail|Playback|Timeline)Changed/.test(files[name]);
    });
  }

  // What the editor asks of the scene playing now.
  function ofCurrent(name) {
    return function () {
      return current && current[name] ? current[name].apply(current, arguments) : null;
    };
  }
  window.WallaeroEngine = {
    // Wallpaper Engine's own pictures as the player draws them, by name: for looking at them.
    builtinPicture: function (name) { return builtinPicture(name); },
    // Draws a scene on a canvas until told to stop. One scene plays at a time. `settings` are
    // the wallpaper's own, by the names the scene has for them, and `changes` what the app's
    // editor has changed of the scene.
    play: function (canvas, scene, settings, changes) {
      if (current) current.stop(current.canvas === canvas);
      notes = [];
      current = play(canvas, scene, settings, changes);
      current.canvas = canvas;
      if (showsMedia(scene)) {
        hearMedia();
        Object.keys(mediaHeard || {}).forEach(function (kind) { current.media(kind, mediaHeard[kind]); });
      }
      // For the editor, which then shows the scene's objects.
      document.dispatchEvent(new CustomEvent('wallaero:engine'));
      return current;
    },
    report: function () { return current && current.report ? current.report() : JSON.stringify({ notes: notes }); },
    loading: function () { return current && current.loading ? current.loading() : 0; },
    describe: ofCurrent('describe'),
    hit: ofCurrent('hit'),
    outline: ofCurrent('outline'),
    paintTexture: ofCurrent('paintTexture'),
    puppet: ofCurrent('puppet'),
    holdPuppet: ofCurrent('holdPuppet'),
    bones: ofCurrent('bones'),
    scriptReport: ofCurrent('scriptReport'),
    checkScript: checkScript,
    scriptDeclares: scriptDeclares,
    placeAt: ofCurrent('placeAt'),
    seek: ofCurrent('seek'),
    time: ofCurrent('time'),
    goTo: ofCurrent('goTo'),
    cameraView: ofCurrent('cameraView'),
    cameraPlacing: ofCurrent('cameraPlacing'),
    // How the editor looks at the scene: `free`, and its own eye for one in three dimensions.
    setView: function (said) {
      editorView = { free: !!(said && said.free), look: said && said.look ? said.look : null,
                     flat: said && Number(said.flat) > 0 ? Number(said.flat) : 0 };
      if (current && current.wake) current.wake();
      return true;
    },
    // Whether the editor holds the scene's time or lets it play on.
    holdClock: function (held) {
      editorClock.held = !!held;
      if (current && current.wake) current.wake();
      return editorClock.held;
    },
    // The translation of a shader alone, for whoever wants to see or check it.
    translate: translate,
    annotations: annotations,
    // The way a value changes over time, a script made ready and the settings it declares, a
    // refused shader mended and numbers read from a text: also for checking.
    curve: curveOf,
    curveValue: function (animation, seconds, base) {
      var curve = curveOf(animation);
      return curve ? curve(seconds, base) : null;
    },
    script: compileScript,
    mend: mend,
    mendPair: mendPair,
    numbers: numbers,
    settings: scriptSettings
  };
})();
