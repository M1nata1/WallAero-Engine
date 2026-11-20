  // What the app asks of a scene playing: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePlayerApi(ctx) {
    var files = ctx.files, pictures = ctx.pictures, gl = ctx.gl, json = ctx.json, materialPass = ctx.materialPass, texture = ctx.texture, general = ctx.general, inDepth = ctx.inDepth, unplaced = ctx.unplaced, objects = ctx.objects, changed = ctx.changed, forScripts = ctx.forScripts, tellScripts = ctx.tellScripts, hearOfMedia = ctx.hearOfMedia, nudged = ctx.nudged, buildPuppet = ctx.buildPuppet, cameraLook = ctx.cameraLook, activeCamera = ctx.activeCamera, view = ctx.view, standing = ctx.standing, spot = ctx.spot, merged = ctx.merged, refresh = ctx.refresh, color = ctx.color, isSet = ctx.isSet, hexOf = ctx.hexOf, changeOf = ctx.changeOf, amended = ctx.amended, amendGeneral = ctx.amendGeneral, skeleton = ctx.skeleton, canonical = ctx.canonical, follow = ctx.follow, isMoving = ctx.isMoving, isLively = ctx.isLively, wake = ctx.wake, goOn = ctx.goOn, holdFilms = ctx.holdFilms, sceneAt = ctx.sceneAt, pageAt = ctx.pageAt, lost = ctx.lost, restored = ctx.restored;
    ctx.player = {
      // `again` when the same canvas is about to be drawn on anew: what it has is then kept.
      stop: function (again) {
        if (ctx.stopped) return;
        tellScripts('destroy');
        ctx.stopped = true;
        // Chance as the page has it, no longer the editor's.
        Math.random = unseeded;
        if (ctx.asked) cancelAnimationFrame(ctx.asked);
        Object.keys(ctx.mice).forEach(function (name) { window.removeEventListener(name, ctx.mice[name], true); });
        window.removeEventListener('resize', changed);
        ctx.canvas.removeEventListener('webglcontextlost', lost);
        ctx.canvas.removeEventListener('webglcontextrestored', restored);
        ctx.players.forEach(function (each) { each.stop(); });
        ctx.films.forEach(function (each) {
          each.video.pause();
          each.video.removeAttribute('src');
          each.video.load();
          each.video.remove();
        });
        var lose = again ? null : gl.getExtension('WEBGL_lose_context');
        if (lose) lose.loseContext();
      },
      // The wallpaper's settings, by the names the scene has for them: those that are now set
      // to something else show at once.
      setProperties: function (settings) {
        ctx.editions++;
        var other = {};
        var any = false;
        Object.keys(settings || {}).forEach(function (name) {
          if (properties[name] === settings[name]) return;
          properties[name] = settings[name];
          other[name] = forScripts(settings[name]);
          any = true;
        });
        if (!any || ctx.stopped) return;
        ctx.clear = numbers(general.clearcolor, 3, defaults.general.clearcolor);
        ctx.things.slice().forEach(function (thing) { refresh(thing, true); });
        tellScripts('applyUserProperties', other);
        changed();
      },
      // What was made of the scene, for whoever looks into why it shows as it does.
      // How many of the scene's pictures and videos have yet to come.
      loading: function () { return ctx.loading; },
      report: function () {
        return JSON.stringify({
          scene: ctx.sceneWidth + '×' + ctx.sceneHeight, drawn: ctx.canvas.width + '×' + ctx.canvas.height, frames: ctx.frames,
          seconds: Math.round(ctx.time * 10) / 10, moving: isMoving(), lively: isLively(), loading: ctx.loading,
          scripts: ctx.scripts.filter(function (script) { return script.made; }).length + ' of ' + ctx.scripts.length,
          objects: objects.map(function (object) {
            return object.name + (standing(object).visible ? '' : ' (hidden)') +
                   (object.effects ? ' (' + object.effects.length + ' effects' +
                     (object.effects.some(function (effect) { return !effect.shown.now; })
                       ? ', ' + object.effects.filter(function (effect) { return !effect.shown.now; }).length + ' off' : '') +
                     (object.kept ? ', kept' : '') + ')' : '') +
                   (object.particles ? ' (' + object.particles.length + ' particles)' : '') +
                   (object.own ? ' (text “' + String(object.state.text).slice(0, 40) + '”)' : '');
          }),
          notes: notes
        }, null, 1);
      },
      // News of the music that plays, as the page is told it.
      media: function (kind, event) {
        if (!ctx.stopped) hearOfMedia(kind, event);
      },
      // What the editor has changed of the scene: what is now changed otherwise shows at once.
      // False when it cannot be shown without the scene being played anew.
      setChanges: function (next) {
        ctx.editions++;
        var text = JSON.stringify(next || {});
        if (ctx.stopped || text === JSON.stringify(ctx.changes)) return true;
        ctx.changes = JSON.parse(text);
        amendGeneral();
        var followed = ctx.things.slice().every(function (thing) {
          var original = isSet(thing.id) ? ctx.pristine.objects[String(thing.id)] : null;
          return !original || follow(thing, amended(original, changeOf(thing.id)));
        });
        changed();
        return followed;
      },
      // The scene as the editor now has it, its file written anew. What changed of the values
      // played as they change shows at once; false when anything else changed, which needs the
      // scene played anew from the new file.
      setDescription: function (text) {
        ctx.editions++;
        var next;
        try { next = JSON.parse(text); } catch (error) { return false; }
        if (ctx.stopped) return true;
        var nextObjects = Array.isArray(next && next.objects) ? next.objects : [];
        if (nextObjects.length !== ctx.pristine.order.length) return false;
        if (canonical(next.general || {}) !== canonical(ctx.pristine.general)) return false;
        for (var i = 0; i < nextObjects.length; i++) {
          var before = ctx.pristine.order[i] || {}, after = nextObjects[i] || {};
          if (String(before.id) !== String(after.id) || canonical(skeleton(before)) !== canonical(skeleton(after))) return false;
        }
        files['scene.json'] = text;
        ctx.pristine.order = nextObjects;
        nextObjects.forEach(function (object) {
          if (isSet(object.id)) ctx.pristine.objects[String(object.id)] = object;
        });
        var followed = ctx.things.slice().every(function (thing) {
          var object = isSet(thing.id) ? ctx.pristine.objects[String(thing.id)] : null;
          return !object || follow(thing, amended(object, changeOf(thing.id)));
        });
        changed();
        return followed;
      },
      // Has the animations show a moment, in seconds, whether they play or wait; with
      // nothing, they go on as they were.
      seek: function (seconds) {
        ctx.timelineAt = typeof seconds === 'number' && isFinite(seconds) ? seconds : null;
        ctx.things.slice().forEach(function (thing) { refresh(thing, true); });
        ctx.dirty = true;
        changed();
      },
      // The scene's moment, in seconds.
      time: function () { return ctx.time; },
      // What the scene's camera shows: of a flat scene the middle of what it shows, from
      // the scene's middle, and how near; of one in three dimensions where its eye is, what
      // it looks at, which way is up, and how wide it sees, up and down, in degrees; with
      // the camera object it is, if one, and whether that hangs on another.
      cameraView: function () {
        if (!inDepth) {
          var seen = view();
          return { depth: false, x: seen.x, y: seen.y, zoom: seen.zoom, width: ctx.sceneWidth, height: ctx.sceneHeight };
        }
        var look = cameraLook(), shot = activeCamera();
        var fov = (shot && number(plain(shot.state.fov ? shot.state.fov[0] : shot.said.fov), 0)) || number(general.perspectiveoverridefov, number(general.fov, defaults.general.fov));
        return { depth: true, eye: look.eye, center: look.center, up: look.up, fov: fov, scripted: !!ctx.scriptedLook,
                 camera: shot ? Number(shot.id) : null, hangs: !!(shot && shot.parent !== undefined) };
      },
      // Where a camera object without one to hang on stands, and how it is turned, to look
      // from an eye at a point, that way up: Wallpaper Engine's turns, x, then y, then z.
      cameraPlacing: function (eyeAt, center, up) {
        var forward = [center[0] - eyeAt[0], center[1] - eyeAt[1], center[2] - eyeAt[2]];
        function unit(v) { var l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; }
        function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
        var back = unit([-forward[0], -forward[1], -forward[2]]);
        var right = unit(cross(up, back));
        var top = cross(back, right);
        // Columns right, top, back: m[2] = −sin y, m[6] = cos y sin x, m[10] = cos y cos x.
        var y = Math.asin(Math.max(-1, Math.min(1, -right[2])));
        var x = Math.atan2(top[2], back[2]);
        var z = Math.atan2(right[1], right[0]);
        return { origin: eyeAt.slice(), angles: [x, y, z] };
      },
      // Looked at again: a frame drawn soon, the time between counted as none.
      wake: function () {
        ctx.before = 0;
        ctx.dirty = true;
        wake();
      },
      // Goes on to a moment of the scene, a thirtieth at a time, as it would have played up
      // to it, and shows it. A moment gone by cannot be come back to: false then, and the
      // scene has to be played anew from its start.
      goTo: function (seconds) {
        if (!(typeof seconds === 'number' && isFinite(seconds)) || ctx.stopped) return false;
        if (seconds < ctx.time - 1e-6) return false;
        var since = realNow();
        while (ctx.time < seconds - 1e-6) {
          goOn(Math.min(1 / 30, seconds - ctx.time));
          // A scene too heavy to go on so quickly gets there in bigger steps; not in a test,
          // which must step the same each time.
          if (!testClock && realNow() - since > 2000) goOn(Math.max(0, seconds - ctx.time));
        }
        ctx.timelineAt = ctx.time;
        holdFilms();
        ctx.things.slice().forEach(function (thing) { refresh(thing, true); });
        ctx.dirty = true;
        changed();
        return true;
      },
      // The scene for the editor: its objects as the scene has them, without the editor's
      // changes, which the editor knows, and what of them can be changed.
      describe: function () {
        return {
          width: ctx.sceneWidth, height: ctx.sceneHeight,
          parallax: flag(ctx.pristine.general.cameraparallax, false), parallaxAmount: number(ctx.pristine.general.cameraparallaxamount, 0.5),
          bloom: flag(ctx.pristine.general.bloom, false), bloomStrength: number(ctx.pristine.general.bloomstrength, 2),
          objects: ctx.pristine.order.filter(function (object) { return numbered(object.id); }).map(describeObject)
        };
      },
      // The object of the scene at a point of the page: the topmost there that shows. Layers
      // that put an effect over all under them are passed over: they would be everywhere.
      hit: function (pageX, pageY) {
        var at = sceneAt(pageX, pageY);
        for (var i = objects.length - 1; i >= 0; i--) {
          var thing = objects[i];
          if (!thing.size || !isSet(thing.id) || !ctx.pristine.objects[String(thing.id)] || thing.takesScene || thing.holds) continue;
          var stands = standing(thing);
          if (stands.visible && stands.alpha > 0.01 && spot(thing, at[0], at[1])) return numbered(thing.id) ? Number(thing.id) : null;
        }
        return null;
      },
      // Where an object is on the page: its middle and, if it has a size, the corners of its
      // rectangle from the top left one round.
      outline: function (id) {
        var thing = ctx.byId[String(id)];
        if (!thing) return null;
        var stands = standing(thing, true);
        var matrix = thing.shift ? nudged(stands.matrix, thing.shift[0], thing.shift[1]) : stands.matrix;
        function page(x, y) { return pageAt(matrix[0] * x + matrix[4] * y + matrix[12], matrix[1] * x + matrix[5] * y + matrix[13]); }
        var result = { middle: page(0, 0), visible: stands.visible };
        if (thing.size) {
          result.size = thing.size;
          var w = thing.size[0] / 2, h = thing.size[1] / 2;
          result.corners = [page(-w, h), page(w, h), page(w, -h), page(-w, -h)];
        }
        return result;
      },
      scriptReport: function () {
        var written = ctx.scriptLog;
        ctx.scriptLog = [];
        return { errors: ctx.scriptErrors, log: written };
      },
      // A picture given other bones and a mesh as it is edited, or none, before they are written.
      puppet: function (id, table, layers) {
        var thing = ctx.byId[String(id)];
        if (!thing) return false;
        var old = thing.puppet;
        thing.puppet = table ? buildPuppet(table, layers || [], thing.name, thing.backsCulled !== false, thing) : null;
        if (old) gl.deleteVertexArray(old.shape);
        if (thing.puppet) thing.moving = true;
        ctx.dirty = true;
        changed();
        return !table || !!thing.puppet;
      },
      // Bones held where the editor has them, each from its parent — place (2), turn, scale
      // (2), turns about x and y — or left to play again.
      holdPuppet: function (id, pose) {
        var thing = ctx.byId[String(id)];
        if (!thing || !thing.puppet) return false;
        thing.puppet.held = pose || null;
        thing.moving = true;
        ctx.dirty = true;
        changed();
        return true;
      },
      // Each bone of a picture as it stands, from the picture: six numbers to take a point of
      // it there.
      bones: function (id, atRest) {
        var thing = ctx.byId[String(id)];
        var puppet = thing && thing.puppet;
        return puppet ? puppet.bones.map(function (bone, index) { return atRest ? puppet.restOf(index) : puppet.worldOf(index); }) : null;
      },
      // A texture given new pixels as it is painted, four bytes each.
      paintTexture: function (name, width, pixels) {
        var stored = pictures[key(name)] || pictures['materials/' + key(name)];
        var made = stored && texture(name);
        if (!made || !made.ready || !made.layers.length) return false;
        gl.bindTexture(gl.TEXTURE_2D, made.layers[0].texture);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, pixels.length / 4 / width, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        if (stored.smooth !== false) gl.generateMipmap(gl.TEXTURE_2D);
        changed();
        return true;
      },
      // A point of the page in the coordinates an object's place is counted in: the scene's,
      // or those of the object it hangs on. An object moved by the pointer has its place move
      // by as much as this point does.
      placeAt: function (id, pageX, pageY) {
        var at = sceneAt(pageX, pageY);
        var thing = ctx.byId[String(id)];
        var parent = thing && isSet(thing.parent) ? ctx.byId[String(thing.parent)] : null;
        if (!parent || parent === thing) return at;
        var matrix = standing(parent, true).matrix;
        var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
        if (Math.abs(area) < 1e-9) return at;
        var dx = at[0] - matrix[12], dy = at[1] - matrix[13];
        return [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area];
      }
    };

    // Whether an object has a number the editor can know it by: scenes number their objects.
    function numbered(id) {
      return isSet(id) && String(id).trim() !== '' && isFinite(Number(id));
    }

    // A number for the editor: one that is none would not come through.
    function real(value, fallback) {
      return typeof value === 'number' && isFinite(value) ? value : (fallback || 0);
    }

    // Whether an animation or a script changes a value as the scene plays.
    function changesByItself(raw) {
      return !!(raw && typeof raw === 'object' && !Array.isArray(raw) && (typeof raw.script === 'string' || raw.animation));
    }

    function describeObject(object) {
      var kind = object.image ? 'image' : (object.particle ? 'particles' : (object.sound ? 'sound' :
                 (isSet(object.text) ? 'text' : (object.model ? 'model' : (object.light ? 'light' : 'group')))));
      var file = String(plain(object.image) || plain(object.particle) || '');
      var hangs = isSet(object.parent);
      var origin = numbers(object.origin, 3, unplaced(object));
      var scale = numbers(object.scale, 3, defaults.object.scale);
      var angles = numbers(object.angles, 3, defaults.object.angles);
      var result = {
        id: Number(object.id), kind: kind, parent: hangs && numbered(object.parent) ? Number(object.parent) : null,
        // Unnamed, an object goes by its file: "models/girl.json" is “girl”.
        name: String(plain(object.name) || file.replace(/^.*\//, '').replace(/\.[^.]*$/, '') || ''),
        isVisible: flag(object.visible, defaults.object.visible), x: real(origin[0]), y: real(origin[1]), scaleX: real(scale[0], 1), scaleY: real(scale[1], 1),
        rotation: real(-angles[2] * 180 / Math.PI), opacity: real(number(object.alpha, defaults.object.alpha) * 100, 100), color: hexOf(numbers(object.color, 3, defaults.object.color)),
        steered: ctx.FOLLOWED.filter(function (name) { return changesByItself(object[name]); }),
        effects: (Array.isArray(object.effects) ? object.effects : []).map(describeEffect)
      };
      if (kind === 'text') {
        var text = plain(object.text);
        result.text = isSet(text) ? String(text) : '';
        result.fontSize = real(number(object.pointsize, defaults.text.pointsize), 32);
      }
      if (kind === 'sound') result.volume = real(number(object.volume, defaults.sound.volume) * 100, 100);
      if (kind === 'particles') {
        var over = object.instanceoverride || {};
        result.particleCount = real(number(over.count, 1) * 100, 100);
        result.particleRate = real(number(over.rate, 1) * 100, 100);
        result.particleSpeed = real(number(over.speed, 1) * 100, 100);
        result.particleSize = real(number(over.size, 1) * 100, 100);
        result.particleLifetime = real(number(over.lifetime, 1) * 100, 100);
        result.particleOpacity = real(number(over.alpha, 1) * 100, 100);
        if (isSet(over.colorn)) result.particleColor = hexOf(color(over.colorn, 1));
        else if (isSet(over.color)) result.particleColor = hexOf(color(over.color, 255));
      }
      return result;
    }

    // An effect for the editor: its values, by the names its material gives them, each once
    // however many of its passes have it — as Wallpaper Engine's own editor shows them.
    // What a shader is with the effect's switches as they are set: whether it declares a name
    // then, and whether a value's `require`, the condition Wallpaper Engine shows it on, is met.
    var workingCache = {};
    function workingNames(vertex, fragment, said, ownCombos, pass) {
      var defines = {};
      Object.keys(said.combos).forEach(function (name) { defines[name] = said.combos[name]; });
      [ownCombos, pass && pass.combos].forEach(function (combos) {
        Object.keys(combos || {}).forEach(function (name) { defines[name] = number(combos[name], 0); });
      });
      var textures = (pass && pass.textures) || [];
      Object.keys(said.uniforms).forEach(function (name) {
        var slot = /^g_Texture(\d+)$/.exec(name), about = said.uniforms[name];
        if (slot && about && about.combo && textures[Number(slot[1])]) defines[about.combo] = 1;
      });
      var id = vertex.length + ':' + fragment.length + ':' + fragment.slice(0, 200) + JSON.stringify(defines);
      var text = workingCache[id];
      if (text === undefined) {
        try {
          text = preprocess(vertex, Object.assign({}, defines), files, {}) + '\n' + preprocess(fragment, Object.assign({}, defines), files, {});
        } catch (error) {
          text = null;
        }
        workingCache[id] = text;
      }
      return {
        present: function (name) { return text === null || new RegExp('\\b' + name + '\\b').test(text); },
        met: function (about) {
          var wanted = about.require && typeof about.require === 'object' ? about.require : {};
          return Object.keys(wanted).every(function (name) { return number(defines[name], 0) === number(wanted[name], 0); });
        }
      };
    }

    function describeEffect(use, place) {
      use = use || {};
      var fileName = String(plain(use.file) || '');
      var effect = json(fileName) || {};
      var values = [];
      var masks = [];
      var switches = [];
      var seen = {};
      (effect.passes || []).forEach(function (step, index) {
        if (step.command) return;
        var own = materialPass(step.material);
        var vertex = own ? files['shaders/' + key(own.shader) + '.vert'] : null;
        var fragment = own ? files['shaders/' + key(own.shader) + '.frag'] : null;
        if (typeof vertex !== 'string' || typeof fragment !== 'string') return;
        var said = annotations(vertex + '\n' + fragment + '\n' + headersOf(vertex + '\n' + fragment, files));
        var constants = merged(own.constantshadervalues, ((use.passes || [])[index] || {}).constantshadervalues);
        var works = workingNames(vertex, fragment, said, own.combos, (use.passes || [])[index]);
        Object.keys(said.switches).forEach(function (name) {
          var about = said.switches[name];
          if (!works.met(about)) return;
          var same = switches.filter(function (one) { return one.name === about.combo; })[0];
          if (same) { same.passes.push(index); return; }
          var given = ((use.passes || [])[index] || {}).combos;
          var ownCombos = own.combos || {};
          var now = given && isSet(given[about.combo]) ? given[about.combo] : (isSet(ownCombos[about.combo]) ? ownCombos[about.combo] : about['default']);
          var options = [];
          if (Array.isArray(about.options)) {
            options = about.options.map(function (option) {
              return option && typeof option === 'object' ? { label: String(option.label), value: number(option.value, 0) } : { label: String(option), value: number(option, 0) };
            });
          } else if (about.options && typeof about.options === 'object') {
            options = Object.keys(about.options).map(function (label) { return { label: label, value: number(about.options[label], 0) }; })
              .sort(function (a, b) { return a.value - b.value; });
          }
          switches.push({ name: String(about.combo), label: String(about.material), kind: String(about.type || 'options'), value: number(now, 0), options: options, passes: [index] });
        });
        Object.keys(said.uniforms).forEach(function (name) {
          // A map to paint, one for all the passes that take the same one.
          var about = said.uniforms[name];
          var slot = /^g_Texture(\d+)$/.exec(name);
          if (!slot || !about || !works.present(name) || !works.met(about) || !/^(opacitymask|flowmask|rgbmask|depth)$/.test(about.mode) || about.hidden === true) return;
          var label = String(about.label || about.material || 'ui_editor_properties_opacity_mask');
          var same = masks.filter(function (mask) { return mask.label === label && mask.slot === Number(slot[1]); })[0];
          if (same) { same.passes.push(index); return; }
          var starts = isSet(about.paintdefaultcolor) ? numbers(about.paintdefaultcolor, 1, 0)[0] : (about['default'] === 'util/black' ? 0 : 1);
          masks.push({ label: label, mode: about.mode, slot: Number(slot[1]), passes: [index], fill: Math.round(real(starts) * 255) });
        });
        Object.keys(said.uniforms).forEach(function (name) {
          var about = said.uniforms[name];
          var count = { 'float': 1, vec2: 2, vec3: 3, vec4: 4 }[said.types[name]];
          if (!about || !count || !isSet(about.material) || seen[about.material] || about.hidden === true) return;
          // The amount of a numbered layer goes with the layer's texture.
          var layer = /_(\d)$/.exec(String(about.label || ''));
          if (!works.met(about) || (layer && said.uniforms['g_Texture' + layer[1]] && !works.present('g_Texture' + layer[1]))) return;
          seen[about.material] = true;
          var raw = isSet(constants[about.material]) ? constants[about.material] : about['default'];
          var range = Array.isArray(about.range) && about.range.length === 2 ? about.range.map(Number) : null;
          values.push({
            name: String(about.material), label: String(about.label || about.material), count: count,
            value: numbers(raw, count, 0).map(function (part) { return real(part); }), isColor: about.type === 'color' && count >= 3,
            range: range && isFinite(range[0]) && isFinite(range[1]) && range[1] > range[0] ? range : null,
            isWhole: about['int'] === true, inDegrees: about.conversion === 'rad2deg', isSteered: changesByItself(raw)
          });
        });
      });
      return { id: place, name: String(plain(use.name) || effect.name || fileName.replace(/^effects\//, '').replace(/\/effect\.json$/, '')),
               isVisible: flag(use.visible, true), isSteered: changesByItself(use.visible), values: values, masks: masks, switches: switches };
    }

    return {};
  }

