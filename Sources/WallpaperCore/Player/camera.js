  // The camera, and how each thing stands now: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeCamera(ctx) {
    var isSet = ctx.isSet, seenPart = ctx.seenPart;
    // The editor's own eye on a scene in three dimensions, while it looks freely.
    function freeLook() {
      return ctx.inDepth && editorView.free && editorView.look ? editorView.look : null;
    }
    function cameraLook() {
      if (ctx.scriptedLook) return ctx.scriptedLook;
      var shot = activeCamera();
      if (shot) {
        var m = cameraMatrix(shot);
        return { eye: [m[12], m[13], m[14]], center: [m[12] - m[8], m[13] - m[9], m[14] - m[10]], up: [m[4], m[5], m[6]] };
      }
      var onScenePath = scenePathLook();
      if (onScenePath) return { eye: onScenePath.eye.slice(), center: onScenePath.center.slice(), up: onScenePath.up.slice() };
      var said = ctx.description.camera || {};
      var eye = numbers(said.eye, 3, 0), center = numbers(said.center, 3, 0), up = numbers(said.up, 3, 0);
      if (!said.eye) { eye = [0, 0, 1]; center = [0, 0, 0]; }
      if (!(up[0] || up[1] || up[2])) up = [0, 1, 0];
      return { eye: eye, center: center, up: up };
    }
    function eyePlace() {
      if (freeLook()) return freeLook().eye;
      if (ctx.inDepth && ctx.scriptedLook) return ctx.scriptedLook.eye;
      if (ctx.inDepth) {
        var shot = activeCamera();
        if (shot) { var m = cameraMatrix(shot); return [m[12], m[13], m[14]]; }
        if (scenePathLook()) return scenePathLook().eye;
        var eye = numbers((ctx.description.camera || {}).eye, 3, 0);
        return (ctx.description.camera || {}).eye ? eye : [0, 0, 1];
      }
      return [ctx.sceneWidth / 2, ctx.sceneHeight / 2, Math.max(ctx.sceneWidth, ctx.sceneHeight) * 4];
    }
    function activeCamera() {
      for (var index = ctx.things.length - 1; index >= 0; index--) {
        if (ctx.things[index].isCamera && showsAll(ctx.things[index])) return ctx.things[index];
      }
      return null;
    }
    function scenePathLook() {
      if (ctx.scenePaths === undefined) {
        ctx.scenePaths = [];
        var named = (ctx.description.camera || {}).paths;
        (Array.isArray(named) ? named : []).forEach(function (name) {
          var said;
          try { said = JSON.parse(ctx.files[key(String(name))]); } catch (error) { return; }
          (said && Array.isArray(said.paths) ? said.paths : []).forEach(function (path) {
            var keys = (Array.isArray(path && path.transforms) ? path.transforms : []).map(function (each) {
              return { at: number(each.timestamp, 0), eye: numbers(each.eye, 3, 0), center: numbers(each.center, 3, 0),
                       up: numbers(each.up, 3, 0), zoom: number(each.zoom, 1) };
            }).sort(function (a, b) { return a.at - b.at; });
            var seconds = number(path.duration, keys.length ? keys[keys.length - 1].at : 0);
            if (keys.length && seconds > 0) ctx.scenePaths.push({ keys: keys, seconds: seconds });
          });
        });
      }
      if (!ctx.scenePaths.length) return null;
      if (ctx.scenePaths.frame === ctx.frames) return ctx.scenePaths.look;
      var total = ctx.scenePaths.reduce(function (sum, path) { return sum + path.seconds; }, 0);
      var into = ((ctx.time % total) + total) % total, path = ctx.scenePaths[0];
      for (var index = 0; index < ctx.scenePaths.length; index++) {
        path = ctx.scenePaths[index];
        if (into < path.seconds || index === ctx.scenePaths.length - 1) break;
        into -= path.seconds;
      }
      var keys = path.keys, before = keys[0], after = keys[0];
      for (var at = 0; at < keys.length; at++) {
        after = keys[at];
        if (keys[at].at > into) break;
        before = keys[at];
      }
      var share = after.at > before.at ? Math.max(0, Math.min(1, (into - before.at) / (after.at - before.at))) : 0;
      function mix(a, b) { return [a[0] + (b[0] - a[0]) * share, a[1] + (b[1] - a[1]) * share, a[2] + (b[2] - a[2]) * share]; }
      var up = mix(before.up, after.up);
      if (!(up[0] || up[1] || up[2])) up = [0, 1, 0];
      ctx.scenePaths.frame = ctx.frames;
      ctx.scenePaths.look = { eye: mix(before.eye, after.eye), center: mix(before.center, after.center), up: up,
                          zoom: before.zoom + (after.zoom - before.zoom) * share };
      return ctx.scenePaths.look;
    }
    function pathLook(shot) {
      if (!shot || !shot.paths) return null;
      if (shot.pathFrame === ctx.frames && shot.pathLook) return shot.pathLook;
      var play = shot.pathPlay;
      if (!play || ctx.time < play.from) play = shot.pathPlay = { index: nextPath(shot, -1), from: ctx.time };
      for (var guard = 0; guard < 256; guard++) {
        var playing = shot.paths[play.index];
        if (!playing.ends || !(playing.seconds > 0) || ctx.time - play.from < playing.seconds) break;
        play.from += playing.seconds;
        play.index = nextPath(shot, play.index);
        play.changed = true;
      }
      var path = shot.paths[play.index], into = ctx.time - play.from;
      var eye = path.eye(into, [0, 0, 0]), center = path.center(into, [0, 0, -1]);
      var up = path.up ? path.up(into, [0, 1, 0]) : [0, 1, 0];
      if (!(up[0] || up[1] || up[2])) up = [0, 1, 0];
      var dark = 0;
      if (shot.paths.length > 1 && flag(ctx.general.camerafade, true)) {
        if (path.ends && path.seconds > 0) dark = Math.max(dark, 1 - (path.seconds - into) / ctx.PATH_FADE);
        if (play.changed) dark = Math.max(dark, 1 - into / ctx.PATH_FADE);
      }
      shot.pathFrame = ctx.frames;
      shot.pathLook = { eye: eye, center: center, up: up, fov: path.fov ? path.fov(into, [0])[0] : 0,
                        dark: Math.max(0, Math.min(1, dark)) };
      return shot.pathLook;
    }
    // Where a camera stands in the scene: on its path, if it has one, else where it is put.
    function cameraMatrix(shot) {
      var look = pathLook(shot);
      if (!look) return standing(shot, true).matrix;
      var seen = Mat4.lookAt(new Vec3(look.eye[0], look.eye[1], look.eye[2]), new Vec3(look.center[0], look.center[1], look.center[2]),
                             new Vec3(look.up[0], look.up[1], look.up[2])).m;
      var own = ctx.m4invert(seen);
      var parent = shot.parent !== undefined ? ctx.byId[String(shot.parent)] : null;
      return parent && parent !== shot ? ctx.m4mul(standing(parent, true).matrix, own) : own;
    }
    function view() {
      if (ctx.viewOnce.frame === ctx.frames) return ctx.viewOnce;
      // While the scene is being made, before scripts can move the camera, there is no frame yet.
      var moved = ctx.camera || { x: 0, y: 0, zoom: 1 };
      var x = moved.x, y = moved.y, zoom = moved.zoom * Math.max(0.01, number(ctx.general.zoom, 1)), fov = 0;
      for (var index = ctx.things.length - 1; index >= 0; index--) {
        var shot = ctx.things[index];
        if (!shot.isCamera || !showsAll(shot)) continue;
        var at = shot.state.origin || [0, 0, 0];
        x += at[0];
        y += at[1];
        zoom *= Math.max(0.01, number((shot.state.zoom || [1])[0], 1));
        fov = number(plain(shot.said.fov), 0);
        break;
      }
      ctx.viewOnce = { frame: ctx.frames, x: x, y: y, zoom: zoom, fov: fov };
      return ctx.viewOnce;
    }
    // One more value of an object that may change.
    function also(thing, name, value) {
      thing.lives[name] = value;
      thing.state[name] = value.now;
    }
    // Where an object stands on what it is drawn on — the scene, or the layer that holds it —
    // and whether it shows. One that hangs on another has its place, size and turn counted
    // from that one and is hidden with it; how see-through it is, is its own: scenes hang
    // what shows on layers that do not, to move it about. With `whole`, where it stands on
    // the scene whatever holds it: for telling what the pointer is over. `above` is whether
    // everything it hangs on shows.
    function standing(thing, whole, depth) {
      var state = thing.state;
      var matrix = ctx.matrixOf(state.origin, state.angles, state.scale);
      var alpha = Math.max(0, Math.min(1, state.alpha[0]));
      var above = true;
      var parent = thing.parent !== undefined && (depth || 0) < 64 ? ctx.byId[String(thing.parent)] : null;
      if (parent && parent !== thing) {
        var up = standing(parent, whole, (depth || 0) + 1);
        above = up.visible;
        // One that hangs on a point of a picture that bends — a head — goes where the point
        // is, and is placed from there.
        var name = thing.said ? plain(thing.said.attachment) : null;
        var point = typeof name === 'string' && name && parent.puppet && parent.puppet.attachment ? parent.puppet.attachment(name) : null;
        if (point) matrix = ctx.times([point[0], point[1], 0, 0, point[2], point[3], 0, 0, 0, 0, 1, 0, point[4], point[5], 0, 1], matrix);
        // One that hangs on a point of a model in three dimensions — a bone the model's
        // animation moves — goes with that bone.
        var held = !point && typeof name === 'string' && name && parent.attachmentMatrix ? parent.attachmentMatrix(name) : null;
        if (held) matrix = ctx.m4mul(held, matrix);
        // Drawn into the layer that holds it, an object is placed in that layer's own
        // coordinates; the layer's place is added when the layer is drawn.
        if (!parent.holds || whole) {
          // An object the scene gives no place stands, for what hangs on it, where Wallpaper
          // Engine puts it: at the scene's corner, not in its middle, where it is drawn — a
          // layer over the whole screen, say, whose pictures are placed by the scene's pixels.
          var base = up.matrix;
          if (!ctx.inDepth && parent.parent === undefined && !isSet(parent.said && parent.said.origin)) {
            base = base.slice();
            base[12] -= ctx.sceneWidth / 2;
            base[13] -= ctx.sceneHeight / 2;
          }
          matrix = ctx.times(base, matrix);
        }
      } else {
        // One anchored to a side of the screen keeps to that side where the screen shows less
        // of the scene than there is: it moves with the edge the scene is cut at.
        var anchor = key(String((thing.own && thing.own.anchor !== undefined ? thing.own.anchor : plain((thing.said || {}).anchor)) || 'none'));
        if (anchor !== 'none' && anchor !== '') {
          var seen = seenPart();
          matrix[12] += /left/.test(anchor) ? seen.left : (/right/.test(anchor) ? seen.right - ctx.sceneWidth : (seen.left + seen.right - ctx.sceneWidth) / 2);
          matrix[13] += /bottom/.test(anchor) ? seen.bottom : (/top/.test(anchor) ? seen.top - ctx.sceneHeight : (seen.bottom + seen.top - ctx.sceneHeight) / 2);
        }
        if (!editorView.free && ((ctx.eye && ctx.eye.on) || (ctx.shake && ctx.shake.on))) {
          // What hangs together moves with the pointer together, and shakes with the camera.
          var moved = ctx.shifted(thing);
          // In a scene in three dimensions the shake moves the picture, not the world: see
          // `viewProjection`.
          matrix[12] += moved[0] + (ctx.shake && !ctx.inDepth ? ctx.shake.x : 0);
          matrix[13] += moved[1] + (ctx.shake && !ctx.inDepth ? ctx.shake.y : 0);
        }
        var seen = ctx.inDepth || editorView.free ? { x: 0, y: 0, zoom: 1 } : view();
        if (seen.x || seen.y || seen.zoom !== 1) {
          // Where the camera is: the scene seen from there, nearer or further.
          var cx = ctx.sceneWidth / 2, cy = ctx.sceneHeight / 2;
          [0, 1, 4, 5].forEach(function (index) { matrix[index] *= seen.zoom; });
          matrix[12] = cx + (matrix[12] - cx - seen.x) * seen.zoom;
          matrix[13] = cy + (matrix[13] - cy - seen.y) * seen.zoom;
        }
      }
      return { matrix: matrix, alpha: alpha, above: above, visible: above && state.visible !== false };
    }
    // Where a point of the scene is on an object, in the object's own coordinates from its
    // middle; null if it is not on it. An object need not show for that — one that is hidden
    // serves as a place to click — but what it hangs on must.
    function spot(thing, x, y) {
      if (!thing.size) return null;
      var stands = standing(thing, true);
      if (!stands.above) return null;
      var matrix = thing.shift ? ctx.nudged(stands.matrix, thing.shift[0], thing.shift[1]) : stands.matrix;
      var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
      if (Math.abs(area) < 1e-9) return null;
      var dx = x - matrix[12], dy = y - matrix[13];
      var own = [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area];
      return Math.abs(own[0]) <= thing.size[0] / 2 && Math.abs(own[1]) <= thing.size[1] / 2 ? own : null;
    }
    // What was drawn of an object once and kept no longer holds.
    function stale(thing) {
      ctx.dirty = true;
      if (thing.kept) {
        ctx.release(thing.kept);
        thing.kept = null;
      }
    }
    // Whether an object and all it hangs on are shown, without working out where they are.
    function showsAll(thing) {
      for (var depth = 0; thing && depth < 64; depth++) {
        if (thing.state.visible === false) return false;
        thing = thing.parent !== undefined ? ctx.byId[String(thing.parent)] : null;
      }
      return true;
    }
    function nextPath(shot, after) {
      var count = shot.paths.length;
      if (count < 2) return 0;
      if (shot.pathOrder !== 'random') return after < 0 ? 0 : (after + 1) % count;
      ctx.pathLuck = (ctx.pathLuck * 1103515245 + 12345) % 2147483648;
      var pick = ctx.pathLuck % (after < 0 ? count : count - 1);
      return after >= 0 && pick >= after ? pick + 1 : pick;
    }
    return { freeLook: freeLook, cameraLook: cameraLook, eyePlace: eyePlace, activeCamera: activeCamera, scenePathLook: scenePathLook, pathLook: pathLook, cameraMatrix: cameraMatrix, view: view, also: also, standing: standing, spot: spot, stale: stale, showsAll: showsAll, nextPath: nextPath };
  }

