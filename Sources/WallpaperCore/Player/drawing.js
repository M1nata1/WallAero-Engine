  // Drawing: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeDrawing(ctx) {
    var gl = ctx.gl, flat = ctx.flat, showFilms = ctx.showFilms, general = ctx.general, inDepth = ctx.inDepth, objects = ctx.objects, things = ctx.things, motions = ctx.motions, tellAnimationEvents = ctx.tellAnimationEvents, serveScripts = ctx.serveScripts, tellNoMedia = ctx.tellNoMedia, put = ctx.put, FILL = ctx.FILL, freeLook = ctx.freeLook, activeCamera = ctx.activeCamera, pathLook = ctx.pathLook, standing = ctx.standing, refresh = ctx.refresh, isMoving = ctx.isMoving, isLively = ctx.isLively, look = ctx.look, glow = ctx.glow, resize = ctx.resize;
    // --- Drawing ----------------------------------------------------------

    ctx.frames = 0;

    var fadeWhite = null; // a white picture, darkened to black, for the camera's fade
    var keptWidth = 0; // the size of the picture kept from before, for a scene that does not clear it
    function draw() {
      gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.sceneTarget.framebuffer);
      gl.viewport(0, 0, ctx.sceneTarget.width, ctx.sceneTarget.height);
      gl.disable(gl.BLEND);
      // A scene may say not to clear what was drawn before, so that what moves leaves its trace
      // on the picture. The glow is added onto the picture, so with it the picture is cleared
      // all the same, as it is for the first frame.
      var keeps = general.clearenabled === false && !flag(general.bloom, false) && ctx.frames > 0 && ctx.sceneTarget.width === keptWidth;
      keptWidth = ctx.sceneTarget.width;
      if (!keeps) {
        gl.clearColor(ctx.clear[0], ctx.clear[1], ctx.clear[2], 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
      }
      ctx.surface = { target: ctx.sceneTarget, copy: ctx.copyTarget, width: ctx.sceneWidth, height: ctx.sceneHeight, left: 0, bottom: 0 };
      // In a scene in three dimensions, as Wallpaper Engine sorts it: first every model's parts
      // that hide what is behind them, then everything in the scene's order with the models'
      // parts that show through — else a glow drawn early hides, by its depth, the street
      // drawn after it.
      var passes = inDepth ? ['solid', 'through'] : [null];
      // What others take as a picture is made first: a planet's surface, a face in a frame.
      objects.forEach(function (object) {
        if (!object.makeComposite) return;
        object.makeComposite();
        gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.sceneTarget.framebuffer);
        gl.viewport(0, 0, ctx.sceneTarget.width, ctx.sceneTarget.height);
      });
      // What the scene has before its first model is drawn before any model, as the scene
      // orders it: a background over the whole screen does not then hide the models drawn
      // after it (3796846129's ToeJam and Earl).
      var drawn = objects.slice();
      var firstModel = drawn.findIndex(function (object) { return object.isModel; });
      ctx.before = inDepth && firstModel > 0 ? drawn.slice(0, firstModel) : [];
      if (before.length) passes = ['under'].concat(passes);
      passes.forEach(function (pass) {
        (pass === 'under' ? before : drawn).forEach(function (object) {
          // What a layer holds is drawn by that layer.
          if (object.heldBy) return;
          // A picture or a text standing in the world goes with the models, in the scene's
          // order: one laid on a stage before the dancers are is under their feet (3796846129).
          // What draws over what the scene shows so far stays with the rest.
          var flat = !!object.inWorld && !object.takesScene && !object.holds;
          if (pass === 'solid' && !object.isModel && !flat) return;
          if (pass === 'through' && (flat || before.indexOf(object) >= 0)) return;
          gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.sceneTarget.framebuffer);
          gl.viewport(0, 0, ctx.sceneTarget.width, ctx.sceneTarget.height);
          object.draw(pass === 'under' ? 'through' : pass);
        });
      });
      if (flag(general.bloom, false)) glow();
      // Dark for a moment while the camera goes from one of its paths to the next.
      var onPath = inDepth && !freeLook() ? pathLook(activeCamera()) : null;
      if (onPath && onPath.dark > 0) {
        fadeWhite = fadeWhite || flat(255, 255, 255, 255);
        gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.sceneTarget.framebuffer);
        gl.viewport(0, 0, ctx.sceneTarget.width, ctx.sceneTarget.height);
        put(fadeWhite.layers[0], FILL, [0, 0, 0, onPath.dark], 'translucent');
      }
      // Onto the canvas, turned over: the scene is kept with its top row first.
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, ctx.sceneTarget.framebuffer);
      gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
      gl.blitFramebuffer(0, 0, ctx.sceneTarget.width, ctx.sceneTarget.height, 0, ctx.sceneTarget.height, ctx.sceneTarget.width, 0, gl.COLOR_BUFFER_BIT, gl.NEAREST);
      ctx.frames++;
    }

    ctx.asked = 0;
    ctx.before = 0;

    function wake() {
      if (!ctx.asked && !ctx.stopped) ctx.asked = requestAnimationFrame(frame);
    }

    var testBegun = false;
    // How many times the editor or the settings have changed the scene (see `runScript`).
    ctx.editions = 0;
    function frame(now) {
      ctx.asked = 0;
      if (ctx.stopped) return;
      // In a test, once the first frame has made the scene's objects, nothing more is done
      // until their pictures are all in: how many frames that takes varies from run to run.
      if (testClock && testBegun && ctx.loading > 0) {
        wake();
        return;
      }
      testBegun = true;
      // The speed the app plays the wallpaper at; a long gap, as after a pause, counts as none.
      // Held by the editor, the scene's time stands.
      var host = window.__wallaeroHost;
      var passed = ctx.before && !editorClock.held ? Math.min(0.1, Math.max(0, (now - ctx.before) / 1000)) * ((host && host.rate) || 1) : 0;
      ctx.before = now;
      goOn(passed);
      // Drawn anew only when it would come out another picture: a scene whose scripts only
      // wait, or whose clock still shows the same minute, is left as it is. One the editor
      // holds changes only as it is changed.
      var moving = !editorClock.held && isMoving();
      var must = moving || ctx.redraw || ctx.dirty || ctx.loading > 0;
      ctx.redraw = false;
      ctx.dirty = false;
      if (must) draw();
      ctx.pointerBefore = ctx.pointer.slice();
      // A scene in which nothing moves is drawn once it is all there, and then left alone.
      if (moving || ctx.loading > 0 || ctx.redraw || ctx.dirty || (!editorClock.held && isLively())) {
        wake();
      } else {
        ctx.before = 0;
      }
    }

    // The scene goes on by a while, in seconds: its clock, its scripts, its animations, its
    // particles; what that makes of it is drawn after.
    function goOn(passed) {
      // Never nought for scripts, as in Wallpaper Engine: the first frame takes the one before
      // as long as a sixtieth (3737268876's camera works out `frametime * (1 / frametime)`).
      if (passed > 0) ctx.frameTime = passed;
      // By the editor's clock each frame draws its chances afresh from the moment it starts
      // at: what frames drawn while the scene stood (as its pictures came in, a number that
      // varies from run to run) took of them changes nothing of what comes after.
      if (editorClock.on) seedChance(Math.round(ctx.time * 1000) + 1);
      ctx.time += passed;
      if (testClock) testClock.at = ctx.time * 1000;
      // The editor's timeline shows every animation at the scene's moment; standing, at
      // the moment the editor shows it at.
      if (editorClock.on && passed > 0) ctx.timelineAt = ctx.time;
      holdFilms();
      resize();
      serveScripts();
      look(passed);
      if (showFilms()) ctx.dirty = true;
      // Animations move on; one that plays once stops at its end.
      motions.forEach(function (motion) {
        if (motion.leader || !motion.playing) return;
        motion.was = motion.at;
        motion.at += passed * motion.speed;
        var curve = motion.curve;
        if (curve.mode === 'single' && curve.frames > 0 && motion.at * curve.rate >= curve.frames) {
          motion.at = curve.frames / curve.rate;
          motion.playing = false;
        }
      });
      motions.slice().forEach(function (motion) {
        var lead = motion.leader || motion;
        if (lead.was !== undefined && lead.was !== lead.at) tellAnimationEvents(motion, lead.was, lead.at);
      });
      motions.forEach(function (motion) { if (!motion.leader) motion.was = undefined; });
      // A script may make a layer, or put one elsewhere, while the objects are gone through.
      things.slice().forEach(function (thing) { refresh(thing, false); });
      // A script nothing has asked for by now belongs to something that could not be made.
      ctx.scripts.slice().forEach(function (script) {
        if (script.made === undefined) script.made = null;
      });
      if (!ctx.mediaTold) tellNoMedia();
      objects.slice().forEach(function (object) {
        if (object.step && passed > 0 && standing(object).visible) object.step(passed);
      });
    }

    // Videos stand while the editor holds the scene, at the scene's moment, and play on with it.
    function holdFilms() {
      if (!editorClock.on) return;
      ctx.films.forEach(function (each) {
        var video = each.video;
        if (editorClock.held) {
          if (!video.paused) video.pause();
          var length = video.duration;
          var at = length > 0 && isFinite(length) ? ctx.time % length : 0;
          if (each.heldAt !== at) {
            each.heldAt = at;
            video.currentTime = at;
          }
        } else if (each.heldAt !== undefined) {
          each.heldAt = undefined;
          var started = video.play();
          if (started && started['catch']) started['catch'](function () {});
        }
      });
    }

    return { wake: wake, goOn: goOn, holdFilms: holdFilms };
  }

