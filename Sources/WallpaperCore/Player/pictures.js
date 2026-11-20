  // Pictures: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePictures(ctx) {
    var freeLook = ctx.freeLook, cameraLook = ctx.cameraLook, eyePlace = ctx.eyePlace, activeCamera = ctx.activeCamera, scenePathLook = ctx.scenePathLook, pathLook = ctx.pathLook, cameraMatrix = ctx.cameraMatrix, view = ctx.view, also = ctx.also, standing = ctx.standing, spot = ctx.spot, stale = ctx.stale, showsAll = ctx.showsAll, nextPath = ctx.nextPath, files = ctx.files, puppets = ctx.puppets, json = ctx.json, materialPass = ctx.materialPass, compositeNamed = ctx.compositeNamed, flat = ctx.flat, shows = ctx.shows, chosenTexture = ctx.chosenTexture, texture = ctx.texture, release = ctx.release, description = ctx.description, general = ctx.general, inDepth = ctx.inDepth, unplaced = ctx.unplaced, screenLayer = ctx.screenLayer, buildPass = ctx.buildPass, things = ctx.things, same = ctx.same, live = ctx.live, liveOfAnyKind = ctx.liveOfAnyKind, times = ctx.times, matrixOf = ctx.matrixOf, nudged = ctx.nudged, buildPuppet = ctx.buildPuppet, m4mul = ctx.m4mul, m4invert = ctx.m4invert, isSet = ctx.isSet, seenPart = ctx.seenPart;
    // --- Pictures ---------------------------------------------------------

    function merged(first, second) {
      var result = {};
      [first, second].forEach(function (part) {
        Object.keys(part || {}).forEach(function (name) { result[name] = part[name]; });
      });
      return result;
    }

    // The frame of an animated texture that shows at a time: its place in the texture.
    function frameAt(picture, seconds) {
      var frames = picture.frames;
      if (!frames || !frames.length) return null;
      var total = 0;
      frames.forEach(function (frame) { total += Math.max(frame[1], 0.001); });
      var at = seconds % total;
      var chosen = frames[0];
      for (var i = 0; i < frames.length; i++) {
        at -= Math.max(frames[i][1], 0.001);
        if (at < 0) {
          chosen = frames[i];
          break;
        }
      }
      var layer = picture.layers[chosen[0]] || picture.layers[0];
      return { layer: layer, frame: [chosen[2] / layer.width, chosen[3] / layer.height,
                                     (chosen[4] || chosen[6]) / layer.width, (chosen[7] || chosen[5]) / layer.height] };
    }

    ctx.byId = {};

    // What every object with a place has: where it is, how large and how turned, how
    // see-through and of what tint, and whether it shows at all.
    function placed(object, otherName) {
      var hangs = object.parent !== undefined && object.parent !== null;
      var thing = { name: String(plain(object.name) || otherName || object.id || ''), id: object.id, parent: hangs ? object.parent : undefined,
                    said: object, state: {}, lives: {}, moving: false };
      // The mouse is told to an object unless the scene says it is not solid.
      thing.solid = flag(object.solid, defaults.object.solid);
      var given = numbers(object.size, 2, 0);
      if (given[0] > 0 && given[1] > 0) thing.size = given;
      thing.lives.origin = live(object.origin, 3, unplaced(object), thing);
      thing.lives.scale = live(object.scale, 3, defaults.object.scale, thing);
      thing.lives.angles = live(object.angles, 3, defaults.object.angles, thing, 'numbers', 'degrees');
      thing.lives.alpha = live(object.alpha, 1, defaults.object.alpha, thing);
      thing.lives.color = live(object.color, 3, defaults.object.color, thing);
      thing.lives.visible = live(object.visible, 0, defaults.object.visible, thing, 'flag');
      thing.state.parallax = numbers(object.parallaxDepth, 2, defaults.object.parallaxDepth);
      // A camera: where it looks from, against the middle of the scene, and how near.
      if (object.camera !== undefined && object.camera !== null) {
        thing.isCamera = true;
        thing.lives.zoom = live(object.zoom === undefined ? 1 : object.zoom, 1, 1, thing);
        thing.paths = cameraPathsOf(plain(object.path));
        thing.pathOrder = key(String(plain(object.queuemode) || defaults.object.queuemode)) === 'random' ? 'random' : 'sequential';
      }
      // Whatever else of it has a script behind it: the script is run for what it does.
      Object.keys(object).forEach(function (name) {
        var value = object[name];
        if (thing.lives[name] || name === 'text' || name === 'volume' || name === 'pointsize') return;
        if (value && typeof value === 'object' && typeof value.script === 'string') thing.lives['~' + name] = liveOfAnyKind(value, thing);
      });
      Object.keys(thing.lives).forEach(function (name) {
        thing.state[name] = thing.lives[name].now;
        // Animations of several values of an object that the scene has tied together play as one.
        var motion = thing.lives[name].motion;
        var leads = motion && motion.curve.follows ? thing.lives[motion.curve.follows] : null;
        if (leads && leads.motion && leads.motion !== motion) motion.leader = leads.motion;
      });
      if (object.id !== undefined) ctx.byId[String(object.id)] = thing;
      things.push(thing);
      return thing;
    }

    // Where the scene is seen from this frame, against its middle, and how near: the camera
    // of the scene that shows — of several, the last in the scene's list, as in Wallpaper
    // Engine — moved and zoomed further by a script and by the scene's own zoom.
    ctx.viewOnce = { frame: -1 };
    // The camera object the scene is seen through: the last one that shows.
    // Where the eye is, for how light glints: the camera of a scene in three dimensions, or in
    // front of the middle of a flat one.
    // Where the eye of a scene in three dimensions is, what it looks at and which way is up:
    // as a script has put it (`setCameraTransforms`), else its camera object's, else the
    // scene's own.
    ctx.scriptedLook = null;

    // A camera's paths, as Wallpaper Engine's editor keeps them beside the scene
    // (`scripts/camera_paths_<id>.json`): each a timeline of where the eye is, what it looks
    // at, which way is up and how wide it sees, in the space of what the camera hangs on.
    // The camera follows one path after another, in their order or at random as the camera
    // says (`queuemode`); a path that plays once gives way to the next when it ends, one
    // that loops or mirrors is followed for good.
    function cameraPathsOf(name) {
      if (typeof name !== 'string' || !name) return null;
      var text = files[key(name)], said;
      try { said = typeof text === 'string' ? JSON.parse(text) : null; } catch (error) { return null; }
      var paths = (said && Array.isArray(said.paths) ? said.paths : []).filter(function (path) {
        return path && path.visible !== false;
      }).map(function (path) {
        var options = path.options || {};
        function curve(channels) {
          if (Array.isArray(channels)) channels = { c0: channels };
          if (!channels || typeof channels !== 'object') return null;
          return curveOf({ c0: channels.c0, c1: channels.c1, c2: channels.c2, options: options });
        }
        var mode = String(options.mode || 'single').toLowerCase();
        var rate = Number(options.fps) > 0 ? Number(options.fps) : 30;
        return { eye: curve(path.eye), center: curve(path.center), up: curve(path.up), fov: curve(path.fov),
                 ends: mode === 'single', seconds: Math.max(0, Number(options.length) || 0) / rate };
      }).filter(function (path) { return path.eye && path.center; });
      return paths.length ? paths : null;
    }
    // The paths of the scene's own camera, as older scenes keep them (`camera.paths`: files of
    // `{paths: [{duration, transforms: [{timestamp, eye, center, up, zoom}]}]}`): played one
    // after another and over again, the eye going straight from one key to the next.
    
    // Chosen at random, the same way every time the scene plays, so that its pictures can
    // be compared; never the same path twice in a row when there is another.
    ctx.pathLuck = 7;
    // Where the active camera's path has it on this frame — eye, centre, up and how wide it
    // sees — and how dark the scene is while one path gives way to the next (`camerafade`);
    // null for a camera without paths.
    ctx.PATH_FADE = 0.35; // seconds of darkening on each side of a change of path (not measured)




    function wantsReading(value, all) {
      var script = value.script;
      return (all && value.bound) || value.changes || !!(script && (script.made === undefined || (script.made && script.made.update)));
    }

    // Brings an object up to date: every frame what an animation or a script changes, and
    // with `all` — the wallpaper's settings have changed — everything.
    function refresh(thing, all) {
      Object.keys(thing.lives).forEach(function (name) {
        var value = thing.lives[name];
        if (!wantsReading(value, all)) return;
        var script = value.script;
        // What a script has set by itself meanwhile is what it carries on from.
        if (script && script.made !== undefined) value.now = thing.state[name];
        var next = value.read();
        if (script && script.quiet) {
          value.now = thing.state[name];
          return;
        }
        if (!same(next, thing.state[name])) {
          thing.state[name] = next;
          ctx.dirty = true;
        }
      });
      (thing.effects || []).forEach(function (effect) {
        var touched = false;
        if (wantsReading(effect.shown, all)) {
          var before = effect.shown.now;
          if (effect.shown.read() !== before) touched = true;
        }
        effect.passes.forEach(function (pass) {
          (pass.lives || []).forEach(function (value) {
            if (!wantsReading(value, all)) return;
            var before = value.now;
            if (!same(value.read(), before)) touched = true;
          });
        });
        if (touched) stale(thing);
      });
      if (all && thing.settle) thing.settle();
    }


    // The effects on an object, each a list of passes ready to draw.
    function buildEffects(thing, object) {
      thing.effects = [];
      // Those not made ready because they were off, by their places.
      thing.effectsOff = {};
      (object.effects || []).forEach(function (use, place) {
        // One the scene has switched off for good is not made ready at all, unless the scene
        // has scripts, which may switch it on.
        if (use.visible === false && !ctx.scripted) {
          thing.effectsOff[place] = true;
          return;
        }
        var fileName = String(plain(use.file) || '');
        var what = '“' + thing.name + '”, effect ' + fileName.replace(/^effects\//, '').replace(/\/effect\.json$/, '');
        var effect = json(fileName);
        if (!effect) {
          note(what + ': not in the scene, left out');
          return;
        }
        var built = { name: String(plain(use.name) || effect.name || ''), place: place, passes: [],
                      shown: live(use.visible, 0, true, thing, 'flag'), targets: (effect.fbos || []).map(function (target) {
          // A target may be of a size of its own, whatever the layer's, and repeat past its
          // edges (3803482159's glitter: tiles of 256 by 256).
          return { name: key(target.name), scale: Math.max(1, number(target.scale, 1)), fit: Math.max(0, number(target.fit, 0)),
                   width: Math.max(0, number(target.width, 0)), height: Math.max(0, number(target.height, 0)),
                   repeats: key(String(plain(target.uvs) || '')) === 'repeat' };
        }) };
        // A script behind something of the effect has the effect for its object.
        if (built.shown.script) built.shown.script.subject = built;
        var whole = true;
        (effect.passes || []).forEach(function (step, index) {
          if (!whole) return;
          if (step.command) {
            if (step.command === 'copy') built.passes.push({ copy: true, target: key(step.target || ''), source: key(step.source || '') });
            return;
          }
          var chosen = (use.passes || [])[index] || {};
          var own = materialPass(step.material);
          if (!own) {
            whole = false;
            note(what + ': its material is not in the scene, left out');
            return;
          }
          // The textures by slot: what the scene puts there, else what the effect comes with.
          var names = [];
          var count = Math.max((own.textures || []).length, (chosen.textures || []).length);
          for (var slot = 0; slot < count; slot++) {
            var given = (chosen.textures || [])[slot];
            names[slot] = chosenTexture((chosen.usertextures || [])[slot]) || chosenTexture((own.usertextures || [])[slot]) ||
                          (given !== null && given !== undefined ? given : ((own.textures || [])[slot] || null));
          }
          var pass = buildPass(own.shader, merged(own.combos, chosen.combos),
                               merged(own.constantshadervalues, chosen.constantshadervalues), names, what, thing);
          if (!pass) {
            whole = false;
            return;
          }
          pass.target = step.target ? key(step.target) : null;
          // Which of the effect's passes it is, and its material's own: for values changed later.
          pass.step = index;
          pass.own = own;
          pass.binds = (step.bind || []).map(function (bind) { return { name: key(bind.name), slot: number(bind.index, 0) }; });
          // What is in each slot: a name the effect binds there, a texture, or what the slot
          // is said to hold when nothing is put there.
          pass.inputs = [];
          pass.slots.forEach(function (slot) {
            var bound = pass.binds.filter(function (bind) { return bind.slot === slot; })[0];
            var name = bound ? bound.name : (names[slot] || pass.defaults[slot] || null);
            if (name === null || name === undefined) {
              pass.inputs[slot] = slot === 0 ? { previous: true } : { picture: flat(255, 255, 255, 255) };
            } else if (key(name) === 'previous') {
              pass.inputs[slot] = { previous: true };
            } else if (compositeNamed(name)) {
              pass.inputs[slot] = { picture: compositeNamed(name) };
              // What it made is kept only while the layer it takes stays as it was.
              (thing.takesComposites = thing.takesComposites || []).push(compositeNamed(name));
            } else if (/^_rt_/.test(key(name)) || built.targets.some(function (target) { return target.name === key(name); })) {
              // A target of Wallpaper Engine's, or one of the effect's own, whatever its name:
              // `_coc`, `render_target`.
              pass.inputs[slot] = { target: key(name) };
              // An effect that looks at the scene under its layer shows another picture
              // whenever the scene does: what it made is not kept.
              if (key(name) === '_rt_fullframebuffer') thing.moving = true;
            } else {
              pass.inputs[slot] = { picture: shows(thing, texture(name)) };
            }
          });
          if (pass.moving) thing.moving = true;
          pass.values.forEach(function (value) {
            if (value.live && value.live.script) value.live.script.subject = built;
          });
          built.passes.push(pass);
        });
        // What an effect keeps from one frame to the next: a target it reads before it has
        // written it in the frame — the state of a simulation, ripples spreading from where the
        // pointer went. The rest it makes anew every frame.
        built.lasting = {};
        var written = {};
        built.passes.forEach(function (pass) {
          var reads = pass.copy ? [pass.source] : (pass.inputs || []).map(function (input) { return input && input.target; });
          reads.forEach(function (name) {
            if (name && !written[name] && built.targets.some(function (target) { return target.name === name; })) built.lasting[name] = true;
          });
          if (pass.target) written[pass.target] = true;
        });
        if (Object.keys(built.lasting).length) thing.moving = true;
        if (whole && built.passes.length) thing.effects.push(built);
      });
    }

    function buildImage(object, layer) {
      var modelName = String(plain(object.image) || '');
      var model = json(modelName);
      layer.kept = null;
      // A picture the scene gives no area — a size of nought — is not drawn: it is there for
      // what hangs on it, to be moved and shown together.
      if (object.size !== undefined && object.size !== null) {
        var area = numbers(object.size, 2, -1);
        if (area[0] === 0 || area[1] === 0) return null;
      }
      // Layers Wallpaper Engine has ready-made: one to put effects over others — it takes what
      // the scene shows under it, or holds the layers that hang on it — and one of a single
      // color, which a scene may also bring as a model of its own.
      if (/composelayer|fullscreenlayer|projectlayer/.test(key(modelName))) {
        // Told not to copy the background, it starts empty, and its effects make all it shows.
        // One that holds layers starts, unless told not to, with what the scene shows under it,
        // and they are drawn over that (2902406982's triangles show it through their clip).
        if (layer.holds) layer.copiesBackground = flag(object.copybackground, defaults.object.copybackground) !== false;
        if (!layer.holds && flag(object.copybackground, defaults.object.copybackground) === false) {
          layer.picture = flat(0, 0, 0, 0);
          layer.plain = true;
        } else if (!layer.holds) {
          layer.takesScene = true;
        }
      } else if (/solidlayer/.test(key(modelName)) || (model && (model.solidlayer === true || /solidlayer/.test(key(String(model.material || '')))))) {
        layer.picture = flat(255, 255, 255, 255);
        // One color all over: as large a picture as the layer is, as far as its effects can tell.
        layer.plain = true;
      } else if (!model) {
        note('“' + layer.name + '”: its model ' + modelName + ' is not in the scene');
        return null;
      }
      var base = (model && materialPass(model.material)) || {};
      layer.blending = key(base.blending || 'translucent');
      // In a scene in three dimensions a picture stands in the world, as large in its units as
      // it has pixels, and is seen through the camera; a layer of the whole screen stays on
      // it. Hidden behind what is nearer only if its material tests depth, as Wallpaper
      // Engine's solid layer that says so in its name does.
      layer.inWorld = inDepth && !screenLayer(object);
      layer.testsDepth = /depthtest/.test(key(modelName)) || key(String(base.depthtest || 'disabled')) === 'enabled';
      // An object may put pictures of its own in its material's slots, as an instance of it: a
      // square of one color given the cover of the music that plays.
      var instance = object.instance && typeof object.instance === 'object' ? object.instance : {};
      var given = (instance.textures || [])[0] || (base.textures || [])[0];
      var chosenPicture = chosenTexture((instance.usertextures || [])[0]) || chosenTexture((base.usertextures || [])[0]);
      if (chosenPicture) {
        layer.picture = shows(layer, texture(chosenPicture));
        layer.plain = false;
      } else if (given) {
        layer.picture = shows(layer, texture('materials/' + given));
      }
      if (!layer.picture && !layer.takesScene && !layer.holds) {
        note('“' + layer.name + '” has no picture');
        return null;
      }
      var size = numbers(object.size, 2, 0);
      if (!(size[0] > 0 && size[1] > 0)) {
        // As large as its picture, or as a frame of it where it is a sheet of frames.
        var sheet = layer.picture && layer.picture.frames && layer.picture.frames[0];
        var own = sheet ? [sheet[4], sheet[7]] : layer.picture && layer.picture.width > 1 ? [layer.picture.width, layer.picture.height] : [ctx.sceneWidth, ctx.sceneHeight];
        size = [number(model && model.width, 0) || own[0], number(model && model.height, 0) || own[1]];
      }
      layer.size = size;
      // Which point of the picture is at its place: its middle, the middle of a side, or a corner.
      var hangs = key(String(plain(object.alignment) || defaults.object.alignment));
      var aside = [/left/.test(hangs) ? size[0] / 2 : (/right/.test(hangs) ? -size[0] / 2 : 0),
                   /top/.test(hangs) ? -size[1] / 2 : (/bottom/.test(hangs) ? size[1] / 2 : 0)];
      if (aside[0] !== 0 || aside[1] !== 0) layer.shift = aside;
      layer.brightness = number(object.brightness, defaults.object.brightness);
      // Scenes of early versions say how see-through and how bright a picture is in its
      // material rather than on the object.
      var own = {};
      Object.keys(base.constantshadervalues || {}).forEach(function (name) { own[key(name)] = base.constantshadervalues[name]; });
      layer.materialAlpha = number(plain(own.alpha), 1);
      layer.brightness *= number(plain(own.brightness), 1);
      layer.blendMode = number(object.colorBlendMode, defaults.object.colorBlendMode);
      if (layer.picture && layer.picture.frames) layer.moving = true;
      // A picture lit by the scene's lights, through a map of which way its surface faces, or
      // showing what is behind it as a polished surface would: as its material says.
      var combos = merged(base.combos, instance.combos);
      var lighting = number(combos.LIGHTING, 0) === 1, reflecting = number(combos.REFLECTION, 0) === 1;
      if ((lighting || reflecting) && layer.picture) {
        var slot = function (index) {
          var name = (instance.textures || [])[index] || (base.textures || [])[index];
          return typeof name === 'string' && name ? shows(layer, texture('materials/' + name)) : null;
        };
        var normal = slot(1), masks = slot(2);
        // Without a normal map nothing is reflected, as in Wallpaper Engine.
        if (lighting || normal) layer.lit = {
          lighting: lighting, reflecting: reflecting && !!normal, normal: normal, masks: masks,
          metallic: number(plain(own.metallic), defaults.lit.metallic), roughness: number(plain(own.roughness), defaults.lit.roughness),
          reflectivity: number(plain(own.reflectivity), defaults.lit.reflectivity),
          emissive: numbers(plain(own.emissivecolor), 3, 1), glow: number(plain(own.emissivebrightness), 1),
          // Which of the four channels of the masks stand for what: as the material's combos
          // say, else as the masks' own file says (bits 20 to 23 of its flags), as with a
          // model — 3437487219's Milky Way glows by such a mask its material says nothing of.
          maps: ['METALLIC_MAP', 'ROUGHNESS_MAP', 'REFLECTION_MAP', 'EMISSIVE_MAP'].map(function (combo, index) {
            if (!masks) return 0;
            return (isSet(combos[combo]) ? number(combos[combo], 0) === 1 : ((masks.maps || 0) >> index & 1) === 1) ? 1 : 0;
          }),
          target: null
        };
        // Lights move, and what is behind a polished picture changes.
        if (layer.lit) layer.moving = true;
      }
      // A picture that bends, if its bones came with the scene and could be read.
      var bends = model && model.puppet ? puppets[key(model.puppet)] : null;
      if (bends) {
        layer.backsCulled = key(String(base.cullmode || 'normal')) !== 'nocull';
        layer.puppet = buildPuppet(bends, object.animationlayers, layer.name, layer.backsCulled, layer);
        if (layer.puppet && layer.puppet.moving) layer.moving = true;
      } else if (model && model.puppet) {
        note('“' + layer.name + '” is a picture that bends, but its bones could not be read; it is shown still');
      }
      buildEffects(layer, object);
      // What takes the scene under it changes whenever anything under it does.
      if (layer.takesScene) layer.moving = true;
      layer.draw = function () { ctx.drawImage(layer); };
      // Made ahead of the rest of the frame when others take its finished picture.
      // One that shows what lies under it is made in its turn: ahead, there is nothing under it yet.
      if (layer.composite && !layer.takesScene && !layer.copiesBackground) layer.makeComposite = function () { ctx.drawImage(layer, true); };
      return layer;
    }

    return { merged: merged, frameAt: frameAt, placed: placed, refresh: refresh, buildEffects: buildEffects, buildImage: buildImage };
  }

