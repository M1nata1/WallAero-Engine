  // Changes made in the editor: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeEditor(ctx) {
    var isSet = ctx.isSet, files = ctx.files, gl = ctx.gl, json = ctx.json, compositeNamed = ctx.compositeNamed, films = ctx.films, description = ctx.description, general = ctx.general, unplaced = ctx.unplaced, objects = ctx.objects, audioBuffers = ctx.audioBuffers, same = ctx.same, buildModel = ctx.buildModel, buildLight = ctx.buildLight, merged = ctx.merged, byId = ctx.byId, placed = ctx.placed, standing = ctx.standing, stale = ctx.stale, buildImage = ctx.buildImage, buildText = ctx.buildText, buildParticles = ctx.buildParticles, buildSound = ctx.buildSound, scripted = ctx.scripted;
    // --- Changes made in the editor ------------------------------------------------------
    //
    // The app's editor changes a scene without touching its files: its changes come with the
    // scene and are put over what the scene says, before the scene is played and while it
    // plays. The scene as it came is kept, for a change that is taken back.

    ctx.changes = {};
    ctx.pristine = { general: merged(general, {}), objects: {}, order: ctx.all };
    ctx.all.forEach(function (object) {
      if (object.id !== undefined && object.id !== null) ctx.pristine.objects[String(object.id)] = object;
    });
    var generalChanged = {}; // the names of what the editor has changed of the scene as a whole


    // A value of the scene made another. What stood behind it — an animation, a script — goes
    // on from the new value; a setting of the wallpaper that stood behind it does no longer.
    function replaced(raw, value) {
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return value;
      var copy = merged(raw, { value: value });
      delete copy.user;
      return copy;
    }

    // A color as the editor gives it, "#FF8000", as the scene writes one: "1 0.50196 0".
    function colorText(hex) {
      var parts = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i.exec(String(hex || ''));
      if (!parts) return null;
      return [1, 2, 3].map(function (index) { return +(parseInt(parts[index], 16) / 255).toFixed(5); }).join(' ');
    }

    function hexOf(parts) {
      return '#' + parts.slice(0, 3).map(function (part) {
        return ('0' + Math.round(Math.max(0, Math.min(1, part)) * 255).toString(16)).slice(-2);
      }).join('').toUpperCase();
    }

    function changeOf(id) {
      var list = Array.isArray(ctx.changes.objects) ? ctx.changes.objects : [];
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].id) === String(id)) return list[i];
      }
      return null;
    }

    // An object of the scene with the editor's change put over it: a copy, or the object itself
    // when nothing of it is changed.
    function amended(object, change) {
      if (!change) return object;
      var copy = merged(object, {});
      function put(name, value) { copy[name] = replaced(object[name], value); }
      if (isSet(change.isVisible)) put('visible', !!change.isVisible);
      // The app sets `wallaeroStill` when it draws the picture for the lock screen; what the
      // editor keeps out of that picture is hidden there.
      if (window.wallaeroStill && change.showsOnLockScreen === false) put('visible', false);
      if (isSet(change.x) || isSet(change.y)) {
        var origin = numbers(object.origin, 3, unplaced(object));
        if (isSet(change.x)) origin[0] = Number(change.x);
        if (isSet(change.y)) origin[1] = Number(change.y);
        put('origin', origin.join(' '));
      }
      if (isSet(change.scaleX) || isSet(change.scaleY)) {
        var scale = numbers(object.scale, 3, 1);
        if (isSet(change.scaleX)) scale[0] = Number(change.scaleX);
        if (isSet(change.scaleY)) scale[1] = Number(change.scaleY);
        put('scale', scale.join(' '));
      }
      if (isSet(change.rotation)) {
        // The editor turns clockwise, as on the page; the scene counts the other way.
        var angles = numbers(object.angles, 3, 0);
        angles[2] = -Number(change.rotation) * Math.PI / 180;
        put('angles', angles.join(' '));
      }
      if (isSet(change.opacity)) put('alpha', Number(change.opacity) / 100);
      if (colorText(change.color)) put('color', colorText(change.color));
      if (isSet(change.text)) put('text', String(change.text));
      if (isSet(change.fontSize)) put('pointsize', Number(change.fontSize));
      if (isSet(change.volume)) put('volume', Number(change.volume) / 100);
      var over = null;
      [['particleCount', 'count'], ['particleRate', 'rate'], ['particleSpeed', 'speed'], ['particleSize', 'size'],
       ['particleLifetime', 'lifetime'], ['particleOpacity', 'alpha']].forEach(function (pair) {
        if (!isSet(change[pair[0]])) return;
        over = over || merged(object.instanceoverride, {});
        over[pair[1]] = replaced(over[pair[1]], Number(change[pair[0]]) / 100);
      });
      if (colorText(change.particleColor)) {
        over = over || merged(object.instanceoverride, {});
        over.colorn = replaced(over.colorn, colorText(change.particleColor));
      }
      if (over) copy.instanceoverride = over;
      if (Array.isArray(change.effects) && Array.isArray(object.effects)) {
        copy.effects = object.effects.map(function (use, place) {
          var own = change.effects.filter(function (each) { return each && each.id === place; })[0];
          return own && use ? amendedEffect(use, own) : use;
        });
      }
      return copy;
    }

    // An effect with the editor's change put over it. A value of the effect is changed in
    // each of its passes, as Wallpaper Engine's own editor does.
    function amendedEffect(use, change) {
      var copy = merged(use, {});
      if (isSet(change.isVisible)) copy.visible = replaced(use.visible, !!change.isVisible);
      var names = Object.keys(change.values || {});
      if (!names.length) return copy;
      var effect = json(String(plain(use.file) || '')) || {};
      var count = Math.max((effect.passes || []).length, (use.passes || []).length);
      copy.passes = [];
      for (var step = 0; step < count; step++) {
        var chosen = merged((use.passes || [])[step], {});
        var constants = merged(chosen.constantshadervalues, {});
        names.forEach(function (name) {
          var value = change.values[name];
          if (!Array.isArray(value) || !value.length) return;
          constants[name] = replaced(constants[name], value.length === 1 ? Number(value[0]) : value.map(Number).join(' '));
        });
        chosen.constantshadervalues = constants;
        copy.passes.push(chosen);
      }
      return copy;
    }

    // The scene as a whole: whether it moves with the pointer, whether what is bright glows.
    function amendGeneral() {
      [['parallax', 'cameraparallax'], ['parallaxAmount', 'cameraparallaxamount'], ['bloom', 'bloom'],
       ['bloomStrength', 'bloomstrength']].forEach(function (pair) {
        var value = ctx.changes[pair[0]];
        if (isSet(value)) {
          general[pair[1]] = replaced(ctx.pristine.general[pair[1]], typeof value === 'boolean' ? value : Number(value));
          generalChanged[pair[1]] = true;
        } else if (generalChanged[pair[1]]) {
          // Taken back: as the scene has it, whatever a script made of it meanwhile.
          if (pair[1] in ctx.pristine.general) general[pair[1]] = ctx.pristine.general[pair[1]];
          else delete general[pair[1]];
          delete generalChanged[pair[1]];
        }
      });
    }

    // The values of an object that are played as they change.
    ctx.FOLLOWED = ['origin', 'scale', 'angles', 'alpha', 'color', 'visible', 'text', 'pointsize', 'volume'];

    // An object without what is played as it changes — those values, its name, and of its
    // effects whether they show and their values: what stays the same while an object is only
    // moved, recolored or set otherwise.
    function skeleton(object) {
      var copy = merged(object, {});
      ctx.FOLLOWED.forEach(function (name) { delete copy[name]; });
      delete copy.name;
      copy.effects = (object.effects || []).map(function (use) {
        return { file: use && use.file, passes: ((use && use.passes) || []).map(function (pass) {
          return { combos: pass && pass.combos, textures: pass && pass.textures };
        }) };
      });
      return copy;
    }

    // A value as text with its keys in order, to tell whether two are the same.
    function canonical(value) {
      if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
      if (value && typeof value === 'object') {
        return '{' + Object.keys(value).sort().map(function (name) { return JSON.stringify(name) + ':' + canonical(value[name]); }).join(',') + '}';
      }
      return JSON.stringify(value === undefined ? null : value);
    }

    // Brings what is played of an object up to the object as the editor has changed it. False
    // when that cannot be done without playing the scene anew: something that was not made
    // ready because it was hidden is to show.
    function follow(thing, object) {
      if (thing.unmade && flag(object.visible, true)) return false;
      thing.said = object;
      ctx.FOLLOWED.forEach(function (name) {
        var value = thing.lives[name];
        if (!value || JSON.stringify(value.raw) === JSON.stringify(object[name])) return;
        value.raw = object[name];
        value.renew();
        var behind = value.raw && typeof value.raw === 'object' && !Array.isArray(value.raw) ? value.raw : null;
        value.bound = !!(behind && isSet(behind.user));
        // What a script makes of the value, it goes on making.
        if (value.script && value.script.made !== undefined) return;
        var next = value.read();
        if (!same(next, thing.state[name])) {
          thing.state[name] = next;
          ctx.dirty = true;
        }
      });
      var uses = object.effects || [];
      var made = {};
      (thing.effects || []).forEach(function (effect) { made[effect.place] = effect; });
      for (var place = 0; place < uses.length; place++) {
        var use = uses[place] || {};
        var effect = made[place];
        if (!effect) {
          if (thing.effectsOff && thing.effectsOff[place] && flag(use.visible, true)) return false;
          continue;
        }
        var touched = false;
        if (JSON.stringify(effect.shown.raw) !== JSON.stringify(use.visible)) {
          effect.shown.raw = use.visible;
          if (!(effect.shown.script && effect.shown.script.made !== undefined)) {
            var before = effect.shown.now;
            if (effect.shown.read() !== before) touched = true;
          }
        }
        effect.passes.forEach(function (pass) {
          if (!pass.own) return;
          var constants = merged(pass.own.constantshadervalues, ((use.passes || [])[pass.step] || {}).constantshadervalues);
          pass.values.forEach(function (value) {
            if (!value.live || value.material === undefined) return;
            var raw = constants[value.material] !== undefined ? constants[value.material] : value.fallback;
            if (JSON.stringify(raw) === JSON.stringify(value.live.raw)) return;
            value.live.raw = raw;
            value.live.renew();
            if (value.live.script && value.live.script.made !== undefined) return;
            var before = value.live.now;
            if (!same(value.live.read(), before)) touched = true;
          });
        });
        if (touched) stale(thing);
      }
      if (thing.settle) thing.settle();
      return true;
    }

    ctx.changes = merged(ctx.startingChanges, {});
    amendGeneral();
    ctx.all = ctx.all.map(function (object) {
      return isSet(object.id) ? amended(object, changeOf(object.id)) : object;
    });

    function idle() {}
    var hasChildren = {};
    // Objects others make use of — a picture particles are made over, say — are made even
    // when hidden.
    var usedByOthers = {};
    // The layers others take the finished picture of, by name — in the scene, or in the
    // materials of its models: made even while hidden.
    var composited = {};
    [JSON.stringify(description)].concat(Object.keys(files).filter(function (name) { return /\.json$/.test(name); }).map(function (name) { return files[name]; }))
      .forEach(function (text) {
        String(text).replace(/_rt_imagelayercomposite_(\d+)_[ab]/gi, function (whole, id) {
          composited[id] = usedByOthers[id] = true;
          return whole;
        });
      });
    ctx.all.forEach(function (object) {
      if (object.parent !== undefined && object.parent !== null) hasChildren[String(object.parent)] = true;
      (Array.isArray(object.dependencies) ? object.dependencies : []).forEach(function (need) {
        if (need && need.id !== undefined) usedByOthers[String(need.id)] = true;
      });
    });

    // Puts an object on the scene, above what is there.
    function add(object) {
      var hidden = object.visible === false;
      var make = object.image ? buildImage : (object.particle ? buildParticles : (object.sound ? buildSound :
                 (object.text !== undefined && object.text !== null ? buildText :
                 (object.model ? buildModel : (object.light ? buildLight : null)))));
      var thing = placed(object, String(plain(object.image) || plain(object.particle) || plain(object.model) ||
                                        (object.light ? 'light' : (object.sound ? 'sound' : (make ? 'text' : 'group')))));
      thing.draw = idle;
      objects.push(thing);
      if (composited[String(object.id)] && object.image) {
        thing.composite = compositeNamed('_rt_imagelayercomposite_' + object.id + '_a');
        thing.clampsUvs = flag(object.clampuvs, false);
      }
      // A layer made to put effects over others either takes what the scene shows under it or
      // holds the layers that hang on it, which are then drawn into it. The scene says which;
      // where it does not, the layer holds what hangs on it if anything does.
      if (object.image && /composelayer/.test(key(String(plain(object.image) || '')))) {
        var through = object.config && typeof object.config === 'object' ? plain(object.config.passthrough) : undefined;
        thing.holds = through === false || (through === undefined && hasChildren[String(object.id)] === true);
        thing.held = [];
      }
      // What is hidden for good is only there for what hangs on it to be hidden with it.
      if (hidden && !scripted && !usedByOthers[String(object.id)]) {
        thing.unmade = !!make;
        return thing;
      }
      if (!make) {
        // Something with only a place holds the objects that hang on it together; a camera
        // says where the scene is seen from.
        return thing;
      }
      function finish() {
        var built = null;
        try {
          // As the editor may have changed it meanwhile.
          built = make(thing.said, thing);
        } catch (error) {
          note('“' + thing.name + '”: ' + error.message);
        }
        if (!built) {
          thing.draw = idle;
          thing.step = null;
        }
        return built;
      }
      // Scripts run in Wallpaper Engine whether what carries them shows or not: a hidden layer
      // whose effect works out the time of day for the rest of the scene (3151551777's
      // "DAY-NIGHT") is made at once, for its scripts to run.
      var effectsScripted = /"script"\s*:/.test(JSON.stringify(object.effects || []));
      if (thing.state.visible || (!object.image && !object.particle && !object.model) || usedByOthers[String(object.id)] || effectsScripted) {
        finish();
      } else {
        // A picture that is hidden is made ready when it first shows: its files are not
        // loaded and its shaders not made for nothing.
        thing.draw = function () {
          if (!standing(thing).visible) return;
          thing.draw = idle;
          if (!finish()) return;
          gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.surface.target.framebuffer);
          gl.viewport(0, 0, ctx.surface.target.width, ctx.surface.target.height);
          thing.draw();
        };
      }
      return thing;
    }

    // Each object is drawn by the nearest layer above it that holds layers, if there is one.
    function settleIn(thing) {
      var up = thing;
      for (var depth = 0; depth < 64 && up.parent !== undefined; depth++) {
        up = byId[String(up.parent)];
        if (!up || up === thing) return;
        if (up.holds) {
          thing.heldBy = up;
          up.held.push(thing);
          return;
        }
      }
    }

    ctx.all.forEach(add);
    objects.forEach(settleIn);

    // Whether anything of the scene is another picture every frame.
    function isMoving() {
      if (ctx.shake.on) return true;
      return objects.some(function (object) {
        // What changes by itself over time, also whether the object shows.
        if (Object.keys(object.lives).some(function (name) {
          var value = object.lives[name];
          return value.changes && (!value.motion || (value.motion.leader || value.motion).playing);
        })) return true;
        if (!standing(object).visible) return false;
        return object.moving || (object.effects || []).some(function (effect) { return effect.shown.changes; });
      });
    }

    // Whether the scene has to be looked at every frame, though it may not have to be drawn:
    // a script that runs every frame, something it asked to be called for, the scene still
    // coming to rest after the pointer.
    function isLively() {
      return ctx.timers.length > 0 || audioBuffers.length > 0 || ctx.eye.settling || ctx.scripts.some(function (script) {
        return script.made === undefined || !!(script.made && script.made.update && !(script.failures > 3));
      }) || films.some(function (each) { return !each.video.paused && !each.video.ended && !each.video.error; });
    }

    return { hexOf: hexOf, changeOf: changeOf, amended: amended, amendGeneral: amendGeneral, skeleton: skeleton, canonical: canonical, follow: follow, add: add, settleIn: settleIn, isMoving: isMoving, isLively: isLively };
  }

