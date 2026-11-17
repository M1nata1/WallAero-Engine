  // Values that change: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeChangingValues(ctx) {
    var live = ctx.live;
    // --- Values that change -----------------------------------------------
    //
    // Where an object is, how large, how see-through, what it says: each is read through a
    // `live` value, which knows what stands behind it. One with an animation or a script is
    // read every frame, one with a setting of the wallpaper when the settings change, and
    // one with nothing behind it never again: what a script has made of it meanwhile stays.

    ctx.things = [];         // everything of the scene that has a place: pictures, texts, particles
    ctx.motions = [];        // the animations of values, each with how far it has played
    ctx.timelineAt = null;   // the moment the editor's timeline shows, in seconds, while it does
    ctx.scripts = [];        // the scripts that are running
    ctx.timers = [];         // what the scripts asked to be called later
    ctx.shared = {};         // what the scripts keep for one another
    ctx.stored = {};         // what they keep for themselves
    ctx.dirty = true;        // something that shows has changed since the last frame drawn
    ctx.pressed = false;     // the mouse button
    ctx.audioBuffers = [];   // the sound, as the scripts asked for it

    function same(first, second) {
      if (!Array.isArray(first) || !Array.isArray(second)) return first === second;
      if (first.length !== second.length) return false;
      for (var i = 0; i < first.length; i++) {
        if (first[i] !== second[i]) return false;
      }
      return true;
    }


    // A value of a kind this does not know, kept for the script behind it: the script runs,
    // and what it does to the scene by itself shows.
    function liveOfAnyKind(raw, owner) {
      var value = raw.value;
      if (typeof value === 'boolean') return live(raw, 0, value, owner, 'flag');
      if (typeof value === 'number') return live(raw, 1, 0, owner);
      var parts = typeof value === 'string' ? value.trim().split(/\s+/) : [];
      if (!parts.length || !parts.every(function (part) { return part !== '' && isFinite(Number(part)); })) return live(raw, 0, '', owner, 'text');
      return live(raw, Math.min(4, parts.length), 0, owner);
    }

    return { same: same, liveOfAnyKind: liveOfAnyKind };
  }

