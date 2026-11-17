  // Scripts: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeSceneScripts(ctx) {
    var gl = ctx.gl, workshopAsset = ctx.workshopAsset, covers = ctx.covers, films = ctx.films, general = ctx.general, inDepth = ctx.inDepth, objects = ctx.objects, changed = ctx.changed, bands = ctx.bands, things = ctx.things, shared = ctx.shared, audioBuffers = ctx.audioBuffers, cameraLook = ctx.cameraLook, view = ctx.view, standing = ctx.standing, spot = ctx.spot, stale = ctx.stale, listen = ctx.listen;
    // --- Scripts ------------------------------------------------------------

    var scale180 = 180 / Math.PI;

    // A value as a script takes it, and back.
    function toScript(script, value) {
      if (script.kind !== 'numbers') return value;
      var by = script.unit === 'degrees' ? scale180 : 1;
      if (script.count === 1) return value[0] * by;
      if (script.count === 2) return new Vec2(value[0] * by, value[1] * by);
      if (script.count === 4) return new Vec4(value[0], value[1], value[2], value[3]);
      return new Vec3(value[0] * by, value[1] * by, value[2] * by);
    }

    function fromScript(script, result, before) {
      if (result === undefined || result === null) return before;
      if (script.kind === 'text') return String(result);
      if (script.kind === 'flag') return !!result;
      var by = script.unit === 'degrees' ? 1 / scale180 : 1;
      if (typeof result === 'number') return isFinite(result) ? before.map(function () { return result * by; }) : before;
      if (typeof result === 'string') return numbers(result, script.count, before);
      var list = [result.x, result.y, result.z, result.w];
      return before.map(function (old, index) { return typeof list[index] === 'number' && isFinite(list[index]) ? list[index] * by : old; });
    }

    function call(script, name, argument, second) {
      var wanted = script.made && script.made[name];
      if (!wanted || script.failures > 3) return undefined;
      try {
        return wanted(argument, second);
      } catch (error) {
        script.failures = (script.failures || 0) + 1;
        note('a script of “' + (script.owner ? script.owner.name : 'the scene') + '” fails: ' + error.message);
        ctx.scriptErrors[script.said.script] = { message: error.message, line: scriptLine(error), during: name };
        return undefined;
      }
    }

    // Makes a script ready: it is read, and its `init` run. All of them are made ready as the
    // scene starts, in the scene's order and before any of them is run for a frame — one may
    // keep in `shared` what others then use (3737268876's camera, `shared.camera`).
    function readyScript(script, current) {
      if (script.made === undefined) {
        script.made = null;
        try {
          script.made = compileScript(script.said.script,
            ['engine', 'thisScene', 'thisLayer', 'thisObject', 'input', 'shared', 'console', 'localStorage', 'renderContext',
             'createScriptProperties', 'Vec2', 'Vec3', 'Vec4', 'Mat3', 'Mat4',
             'MediaPlaybackEvent', 'MediaPropertiesEvent', 'MediaThumbnailEvent', 'MediaStatusEvent', 'MediaTimelineEvent'],
            [engineObject, sceneObject, layerObject(script.owner),
             script.animationLayer ? script.animationLayer() :
               (script.subject && script.owner ? effectObject(script.owner, script.subject) : layerObject(script.owner)),
             inputObject, shared, consoleObject, storageObject, lenient({}),
             scriptSettings(script.said.scriptproperties), Vec2, Vec3, Vec4, Mat3, Mat4,
             MEDIA_PLAYBACK, lenient({}), lenient({}), lenient({}), lenient({})]);
        } catch (error) {
          note('a script of “' + (script.owner ? script.owner.name : 'the scene') + '” cannot be read: ' + error.message);
          ctx.scriptErrors[script.said.script] = { message: error.message, line: scriptLine(error) };
        }
        if (script.made) {
          var first = call(script, 'init', toScript(script, current));
          script.quiet = first === undefined;
          current = fromScript(script, first, current);
          call(script, 'applyUserProperties', engineObject.userProperties);
        }
      }
      return current;
    }

    // What went wrong with scripts and what they wrote, for the editor: errors by the text
    // of the script, each once.
    ctx.scriptErrors = {};
    ctx.scriptLog = [];

    // Gives a script's value for this frame.
    function runScript(script, current) {
      current = readyScript(script, current);
      if (script.made && script.made.update) {
        // By the editor's clock a script is run once a moment, until the editor or the
        // settings change something: frames drawn while the scene stands, as many as it takes
        // its pictures to come in, would each take it on a step (a twinkle, a smoothing, a
        // value it adds to its own last) where no time has gone by.
        if (editorClock.on && script.ranAt === ctx.time && script.ranFor === ctx.editions) return script.ranTo;
        var answer = call(script, 'update', toScript(script, current));
        // One that gives nothing back has done its work on the scene by itself.
        script.quiet = answer === undefined;
        current = fromScript(script, answer, current);
        if (editorClock.on) {
          script.ranAt = ctx.time;
          script.ranFor = ctx.editions;
          script.ranTo = current;
        }
      }
      return current;
    }

    // A color or the like among the wallpaper's settings, as scripts get it.
    function forScripts(value) {
      if (typeof value === 'string' && /^\s*-?[\d.]+(\s+-?[\d.]+){2}\s*$/.test(value)) return new Vec3(value);
      return value;
    }

    var engineObject = lenient({
      AUDIO_RESOLUTION_16: 16, AUDIO_RESOLUTION_32: 32, AUDIO_RESOLUTION_64: 64,
      get frametime() { return ctx.frameTime; },
      get runtime() { return ctx.time; },
      get timeOfDay() {
        var now = new Date();
        return (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400;
      },
      get canvasSize() { return new Vec2(ctx.sceneWidth, ctx.sceneHeight); },
      get screenResolution() { return new Vec2(ctx.canvas.width, ctx.canvas.height); },
      get userProperties() {
        var result = {};
        Object.keys(properties).forEach(function (name) { result[name] = forScripts(properties[name]); });
        return result;
      },
      isPortrait: function () { return ctx.sceneHeight > ctx.sceneWidth; },
      isLandscape: function () { return ctx.sceneWidth >= ctx.sceneHeight; },
      isDesktopDevice: function () { return true; },
      isMobileDevice: function () { return false; },
      isWallpaper: function () { return true; },
      isScreensaver: function () { return false; },
      isRunningInEditor: function () { return false; },
      openUserShortcut: function () { return false; },
      registerAsset: function (file) { return file; },
      // The sound the Mac plays, in as many bands as asked for; filled anew every frame.
      registerAudioBuffers: function (resolution) {
        var size = resolution === 16 || resolution === 32 ? resolution : 64;
        var buffers = { left: new Float32Array(size), right: new Float32Array(size), average: new Float32Array(size) };
        audioBuffers.push(buffers);
        listen();
        return buffers;
      },
      setTimeout: function (callback, delay) { return later(callback, delay, false); },
      setInterval: function (callback, delay) { return later(callback, delay, true); },
      // What setTimeout and setInterval give back stops what they started.
      clearTimeout: function (handle) { if (typeof handle === 'function') handle(); },
      clearInterval: function (handle) { if (typeof handle === 'function') handle(); }
    });

    // Calls a script back after a while of the scene's own time, which stands still while
    // the wallpaper is paused. What is given back stops it.
    function later(callback, delay, again) {
      var timer = { callback: callback, every: Math.max(0, Number(delay) || 0) / 1000, again: again, at: 0 };
      timer.at = ctx.time + timer.every;
      ctx.timers.push(timer);
      return function () { ctx.timers = ctx.timers.filter(function (each) { return each !== timer; }); };
    }

    function written(list) {
      ctx.scriptLog.push(Array.prototype.map.call(list, function (part) {
        return part && typeof part === 'object' ? (part.x !== undefined ? part.toString() : JSON.stringify(part)) : String(part);
      }).join(' '));
      if (ctx.scriptLog.length > 200) ctx.scriptLog.shift();
    }
    var consoleObject = {
      log: function () {
        written(arguments);
        if (window.console) window.console.log.apply(window.console, arguments);
      },
      error: function () {
        written(arguments);
        note('a script says: ' + Array.prototype.join.call(arguments, ' '));
      }
    };

    var storageObject = {
      LOCATION_GLOBAL: 'global', LOCATION_SCREEN: 'screen',
      get: function (name) { return ctx.stored[name]; },
      set: function (name, value) { ctx.stored[name] = value; },
      'delete': function (name) { return delete ctx.stored[name]; },
      clear: function () { ctx.stored = {}; }
    };

    var inputObject = {
      // Where the pointer is in the scene, as the camera sees it.
      get cursorWorldPosition() {
        var seen = view(), cx = ctx.sceneWidth / 2, cy = ctx.sceneHeight / 2;
        return new Vec3(cx + seen.x + (ctx.pointer[0] * ctx.sceneWidth - cx) / seen.zoom, cy + seen.y + ((1 - ctx.pointer[1]) * ctx.sceneHeight - cy) / seen.zoom, 0);
      },
      get cursorScreenPosition() { return new Vec2(ctx.pointer[0] * ctx.canvas.width, ctx.pointer[1] * ctx.canvas.height); },
      get cursorLeftDown() { return ctx.pressed; }
    };

    var standsFor = new WeakMap(); // the object of the scene behind what a script has of it

    // An effect of an object as scripts see it: to be switched on and off, its settings
    // changed and the animations of its settings steered.
    function effectObject(thing, effect) {
      if (!effect.forScripts) {
        effect.forScripts = lenient({
          get name() { return effect.name; },
          get visible() { return !!effect.shown.now; },
          set visible(value) {
            if (effect.shown.now === !!value) return;
            effect.shown.now = !!value;
            stale(thing);
          },
          getMaterialCount: function () { return effect.passes.length; },
          setMaterialProperty: function (name, value) {
            var list = typeof value === 'number' ? [value, value, value, value] : (value ? [value.x, value.y, value.z, value.w] : []);
            effect.passes.forEach(function (pass) {
              (pass.values || []).forEach(function (each) {
                if (each.material !== name || !each.live) return;
                each.live.now = each.live.now.map(function (old, index) { return typeof list[index] === 'number' && isFinite(list[index]) ? list[index] : old; });
                stale(thing);
              });
            });
          },
          // The animation of one of its settings, by name; with none named, the first.
          getAnimation: function (wanted) {
            var found = null;
            effect.passes.forEach(function (pass) {
              (pass.values || []).forEach(function (each) {
                var motion = each.live && each.live.motion;
                if (motion && !motion.leader && !found && (wanted === undefined || motion.called === wanted)) found = motion;
              });
            });
            return found ? steered(found) : unsteered();
          }
        });
      }
      return effect.forScripts;
    }

    // An object of the scene as its scripts see it: what they read is what shows, and what
    // they set shows from the next frame on.
    function layerObject(thing) {
      if (!thing) return lenient({});
      if (thing.forScripts) return thing.forScripts;
      var object = {};
      function numbersOf(name, key, Vector, by) {
        Object.defineProperty(object, name, {
          enumerable: true,
          get: function () {
            var now = thing.state[key];
            return Vector === Vec2 ? new Vec2(now[0] * by, now[1] * by) : new Vec3(now[0] * by, now[1] * by, now[2] * by);
          },
          set: function (value) {
            var list = typeof value === 'number' ? [value, value, value] : [value.x, value.y, value.z];
            thing.state[key] = thing.state[key].map(function (old, index) {
              return typeof list[index] === 'number' && isFinite(list[index]) ? list[index] / by : old;
            });
            ctx.dirty = true;
          }
        });
      }
      function plainOf(name, get, set) {
        Object.defineProperty(object, name, { enumerable: true, get: get, set: function (value) { set(value); ctx.dirty = true; } });
      }
      numbersOf('origin', 'origin', Vec3, 1);
      numbersOf('scale', 'scale', Vec3, 1);
      numbersOf('angles', 'angles', Vec3, scale180);
      numbersOf('color', 'color', Vec3, 1);
      numbersOf('parallaxDepth', 'parallax', Vec2, 1);
      plainOf('alpha', function () { return thing.state.alpha[0]; }, function (value) { thing.state.alpha = [Number(value) || 0]; });
      plainOf('visible', function () { return thing.state.visible; }, function (value) { thing.state.visible = !!value; });
      plainOf('name', function () { return thing.name; }, function () {});
      plainOf('text', function () { return thing.state.text; }, function (value) { thing.state.text = String(value); });
      plainOf('pointsize', function () { return (thing.state.pointsize || [0])[0]; }, function (value) {
        if (Number(value) > 0) thing.state.pointsize = [Number(value)];
      });
      if (thing.own) {
        // How a text looks, which a script may change as well as what it says.
        ['font', 'padding', 'horizontalalign', 'verticalalign', 'opaquebackground', 'backgroundcolor',
         'limitrows', 'maxrows', 'limitwidth', 'maxwidth', 'anchor', 'limituseellipsis', 'outline', 'outlinecolor',
         'outlinethickness', 'dropshadow', 'dropshadowcolor', 'dropshadowoffset', 'dropshadowsize', 'dropshadowopacity',
         'blur', 'blursize', 'spacing'].forEach(function (name) {
          plainOf(name, function () {
            var now = thing.own[name] !== undefined ? thing.own[name] : plain(thing.said[name]);
            if (/color$/.test(name)) return new Vec3(String(now === undefined ? '0 0 0' : now));
            if (name === 'dropshadowoffset' || name === 'spacing') return new Vec2(String(now === undefined ? '0 0' : now));
            return now;
          }, function (value) {
            thing.own[name] = value && typeof value === 'object' ? String(value) : value;
          });
        });
      }
      Object.defineProperty(object, 'size', { enumerable: true, get: function () {
        return new Vec2(thing.size ? thing.size[0] : 0, thing.size ? thing.size[1] : 0);
      } });
      object.getParent = function () { return thing.parent !== undefined && find(thing.parent) ? layerObject(find(thing.parent)) : null; };
      object.getChildren = function () {
        return things.filter(function (each) { return each.parent !== undefined && String(each.parent) === String(thing.id); }).map(layerObject);
      };
      // Hung on another layer, or on none: what it is placed from changes, not where it is said to be.
      object.setParent = function (wanted) {
        var parent = wanted === null || wanted === undefined ? null : find(wanted);
        if (parent === thing) return false;
        thing.parent = parent ? parent.id : undefined;
        changed();
        return true;
      };
      object.isPlaying = function () { return true; };
      if (thing.particles) {
        // Particles made at once, as many as said, where the system makes them.
        object.emitParticles = function (count) { if (thing.emitNow) thing.emitNow(Math.max(0, Math.round(Number(count) || 0))); };
        // A system of particles as its scripts steer it: how many, how fast, how large; where
        // its points are; whether it goes on making particles.
        var override = function () { return thing.said.instanceoverride || (thing.said.instanceoverride = {}); };
        ['count', 'rate', 'size', 'alpha', 'lifetime', 'speed'].forEach(function (name) {
          Object.defineProperty(object.instanceValues || (object.instanceValues = {}), name, {
            enumerable: true,
            get: function () { return number(override()[name], 1); },
            set: function (value) { override()[name] = Number(value); thing.settle(); ctx.dirty = true; }
          });
        });
        Object.defineProperty(object.instanceValues, 'colorn', {
          enumerable: true,
          get: function () { var c = thing.recolorGiven || [1, 1, 1]; return new Vec3(c[0], c[1], c[2]); },
          set: function (value) { override().colorn = String(value); thing.settle(); ctx.dirty = true; }
        });
        object.instanceValues.setControlPointPosition = function (index, value) {
          override()['controlpoint' + Math.round(Number(index) || 0)] = value && typeof value === 'object' ? [value.x, value.y, value.z || 0] : value;
          ctx.dirty = true;
        };
        object.instanceValues.getControlPointPosition = function (index) {
          var at = thing.pointAt(Math.round(Number(index) || 0));
          return new Vec3(at[0], at[1], at[2]);
        };
        object.instanceValues.play = function () { thing.emitting = true; };
        object.instanceValues.pause = function () { thing.emitting = false; };
        object.instanceValues.stop = function () { thing.emitting = false; thing.particles = []; ctx.dirty = true; };
        object.instanceValues.isPlaying = function () { return thing.emitting !== false; };
        [0, 1, 2, 3, 4, 5, 6, 7].forEach(function (index) {
          Object.defineProperty(object.instanceValues, 'controlpoint' + index, {
            enumerable: true,
            get: function () { return object.instanceValues.getControlPointPosition(index); },
            set: function (value) { object.instanceValues.setControlPointPosition(index, value); }
          });
        });
        object.instance = lenient(object.instanceValues);
        delete object.instanceValues;
      }
      if (thing.sound) {
        // A sound, to be started, stopped and made louder or softer.
        ['play', 'stop', 'pause', 'isPlaying'].forEach(function (name) { object[name] = thing.sound[name]; });
        plainOf('volume', function () { return thing.state.volume[0]; }, function (value) {
          thing.state.volume = [Number(value) || 0];
          thing.settle();
        });
      }
      object.getEffectCount = function () { return thing.effects ? thing.effects.length : 0; };
      // An effect of the object, by its name or its number: to be switched on and off, and
      // its settings changed.
      object.getEffect = function (wanted) {
        var effects = thing.effects || [];
        var effect = typeof wanted === 'number' ? effects[wanted] : effects.filter(function (each) { return each.name === wanted; })[0];
        return effect ? effectObject(thing, effect) : null;
      };
      object.getAnimationLayerCount = function () { return thing.puppet ? thing.puppet.layers.length : 0; };
      object.getMaterial = unsteered;
      // The layers of animation of a picture that bends, and its bones.
      object.getAnimationLayer = function (wanted) {
        var layer = thing.puppet && thing.puppet.findLayer(wanted);
        return layer ? thing.puppet.scriptLayer(layer) : unsteered();
      };
      object.createAnimationLayer = function (animation, config) {
        var layer = thing.puppet && thing.puppet.addLayer(animation, config, false);
        return layer ? thing.puppet.scriptLayer(layer) : unsteered();
      };
      object.playSingleAnimation = function (animation, config) {
        var layer = thing.puppet && thing.puppet.addLayer(animation, config, true);
        return layer ? thing.puppet.scriptLayer(layer) : unsteered();
      };
      object.destroyAnimationLayer = function (wanted) {
        var layer = thing.puppet && thing.puppet.findLayer(wanted);
        return layer ? thing.puppet.removeLayer(layer) : false;
      };
      function boneOf(wanted) { return thing.puppet ? thing.puppet.boneIndex(wanted) : -1; }
      object.getBoneCount = function () { return thing.puppet ? thing.puppet.bones.length : 0; };
      object.getBoneIndex = function (name) { return boneOf(name); };
      object.getBoneParentIndex = function (wanted) {
        var index = boneOf(wanted);
        return index >= 0 ? thing.puppet.bones[index].parent : -1;
      };
      // A bone's place as a 4×4 matrix, from a 2D one.
      function toMat4(two) { return new Mat4([two[0], two[1], 0, 0, two[2], two[3], 0, 0, 0, 0, 1, 0, two[4], two[5], 0, 1]); }
      function fromMat4(matrix) {
        var m = matrix && matrix.m ? matrix.m : [];
        return [m[0], m[1], m[4], m[5], m[12], m[13]];
      }
      function setFromTwo(index, two) {
        var scaleX = Math.sqrt(two[0] * two[0] + two[1] * two[1]), scaleY = Math.sqrt(two[2] * two[2] + two[3] * two[3]);
        thing.puppet.setLocal(index, { origin: [two[4], two[5]], angle: Math.atan2(two[1], two[0]), scale: [scaleX, scaleY] });
      }
      object.getLocalBoneTransform = function (wanted) {
        var index = boneOf(wanted);
        var bone = index >= 0 ? thing.puppet.bones[index] : null;
        return bone ? toMat4(bone.now || bone.rest) : new Mat4();
      };
      object.setLocalBoneTransform = function (wanted, matrix) {
        var index = boneOf(wanted);
        if (index >= 0) setFromTwo(index, fromMat4(matrix));
      };
      object.getBoneTransform = function (wanted) {
        var index = boneOf(wanted);
        return index >= 0 ? toMat4(thing.puppet.worldOf(index)) : new Mat4();
      };
      object.setBoneTransform = function (wanted, matrix) {
        var index = boneOf(wanted);
        if (index < 0) return;
        // Taken back to its parent's own terms.
        var parent = thing.puppet.bones[index].parent;
        var two = fromMat4(matrix);
        setFromTwo(index, parent >= 0 ? ctx.joined(ctx.undone(thing.puppet.worldOf(parent)), two) : two);
      };
      object.getLocalBoneAngles = function (wanted) {
        var pose = thing.puppet ? thing.puppet.localPose(boneOf(wanted)) : null;
        return new Vec3(0, 0, pose ? pose[2] * scale180 : 0);
      };
      object.setLocalBoneAngles = function (wanted, angles) {
        var index = boneOf(wanted);
        if (index >= 0) thing.puppet.setLocal(index, { angle: (typeof angles === 'number' ? angles : (angles && angles.z) || 0) / scale180 });
      };
      object.getLocalBoneOrigin = function (wanted) {
        var pose = thing.puppet ? thing.puppet.localPose(boneOf(wanted)) : null;
        return new Vec3(pose ? pose[0] : 0, pose ? pose[1] : 0, 0);
      };
      object.setLocalBoneOrigin = function (wanted, origin) {
        var index = boneOf(wanted);
        if (index >= 0 && origin) thing.puppet.setLocal(index, { origin: [origin.x || 0, origin.y || 0] });
      };
      // Bones that sway by themselves may be pushed — one by its name or number, or all of
      // them — and stilled. Shapes blended into others are not played: a script asking of
      // them finds none.
      object.applyBonePhysicsImpulse = function (wanted, moving, turning) {
        if (!thing.puppet || !thing.puppet.pushSway) return;
        var index = wanted === undefined || wanted === null ? -1 : boneOf(wanted);
        if (index < 0 && wanted !== undefined && wanted !== null) return;
        var by = moving && typeof moving === 'object' ? [Number(moving.x) || 0, Number(moving.y) || 0] : [0, 0];
        var spin = turning && typeof turning === 'object' ? (Number(turning.z) || 0) / scale180 : (Number(turning) || 0) / scale180;
        thing.puppet.pushSway(index, by, spin);
      };
      object.resetBonePhysicsSimulation = function (wanted) {
        if (!thing.puppet || !thing.puppet.resetSway) return;
        var index = wanted === undefined || wanted === null ? -1 : boneOf(wanted);
        thing.puppet.bones.forEach(function (bone, at) { if (index < 0 || at === index) thing.puppet.resetSway(bone); });
      };
      object.getBlendShapeIndex = function () { return -1; };
      object.getBlendShapeWeight = function () { return 0; };
      object.setBlendShapeWeight = function () {};
      // The points of a picture that bends that other objects hang on.
      function attachment(wanted) {
        if (!thing.puppet || !thing.puppet.attachment) return null;
        return thing.puppet.attachment(typeof wanted === 'number' ? (thing.puppet.attachmentNames || [])[wanted] : wanted);
      }
      object.getAttachmentIndex = function (name) { return thing.puppet && thing.puppet.attachmentNames ? thing.puppet.attachmentNames.indexOf(name) : -1; };
      object.getAttachmentOrigin = function (wanted) { var at = attachment(wanted); return new Vec3(at ? at[4] : 0, at ? at[5] : 0, 0); };
      object.getAttachmentAngles = function (wanted) { var at = attachment(wanted); return new Vec3(0, 0, at ? Math.atan2(at[1], at[0]) * scale180 : 0); };
      object.getAttachmentMatrix = function (wanted) { var at = attachment(wanted); return at ? toMat4(at) : new Mat4(); };
      // Where the object is on the scene, as a matrix.
      object.getTransformMatrix = function () { return new Mat4(standing(thing, true).matrix); };
      object.getVideoTexture = function () { return videoObject(thing); };
      object.getTextureAnimation = function () { return sheetObject(thing); };
      // An animation of one of the object's values, by the name the scene gives it.
      object.getAnimation = function (wanted) {
        var found = motionOf(thing, wanted);
        return found ? steered(found) : unsteered();
      };
      thing.forScripts = lenient(object);
      standsFor.set(thing.forScripts, thing);
      return thing.forScripts;
    }

    // The video an object shows, as a script steers it; nothing to steer for one that shows none.
    function videoObject(thing) {
      var film = thing.picture && thing.picture.film && thing.picture.film.video ? thing.picture.film : null;
      if (!film) {
        films.forEach(function (each) { if (!film && each.users.indexOf(thing) >= 0) film = each; });
      }
      if (!film) return unsteered();
      var video = film.video;
      return lenient({
        play: function () { var started = video.play(); if (started && started['catch']) started['catch'](function () {}); },
        pause: function () { video.pause(); },
        stop: function () { video.pause(); video.currentTime = 0; changed(); },
        isPlaying: function () { return !video.paused && !video.ended; },
        getCurrentTime: function () { return video.currentTime; },
        setCurrentTime: function (seconds) { video.currentTime = Math.max(0, Number(seconds) || 0); changed(); },
        get duration() { return isFinite(video.duration) ? video.duration : 0; },
        get rate() { return video.playbackRate; },
        set rate(value) { video.playbackRate = Math.max(0, Number(value) || 0); },
        // Called each time the video comes to its end, also as it starts over.
        addEndedCallback: function (callback) { if (typeof callback === 'function') (film.ended || (film.ended = [])).push(callback); }
      });
    }

    // The animation of an object's texture — pictures one after another in one texture — as a
    // script steers it: played, paused, stopped and put on a frame.
    function sheetObject(thing) {
      var picture = thing.picture;
      if (!picture || !picture.frames || !picture.frames.length) return unsteered();
      var sheet = thing.sheet || (thing.sheet = { playing: true, at: 0, rate: 1 });
      function frameStart(index) {
        var at = 0;
        for (var i = 0; i < Math.min(index, picture.frames.length); i++) at += Math.max(picture.frames[i][1], 0.001);
        return at;
      }
      function frameNow() {
        var at = sheetTime(thing), total = frameStart(picture.frames.length);
        at = total > 0 ? at % total : 0;
        for (var i = 0; i < picture.frames.length; i++) {
          at -= Math.max(picture.frames[i][1], 0.001);
          if (at < 0) return i;
        }
        return 0;
      }
      return lenient({
        get frameCount() { return picture.frames.length; },
        get rate() { return sheet.rate; },
        set rate(value) { sheet.at = sheetTime(thing); sheet.since = ctx.time; sheet.rate = Number(value) || 0; },
        play: function () { sheet.at = sheetTime(thing); sheet.since = ctx.time; sheet.playing = true; changed(); },
        pause: function () { sheet.at = sheetTime(thing); sheet.playing = false; changed(); },
        stop: function () { sheet.at = 0; sheet.playing = false; changed(); },
        isPlaying: function () { return sheet.playing; },
        getFrame: function () { return frameNow(); },
        setFrame: function (index) { sheet.at = frameStart(Math.max(0, Math.round(Number(index) || 0))); sheet.since = ctx.time; changed(); }
      });
    }

    // The time an object's animated texture is at: the scene's own, unless a script steers it.
    function sheetTime(thing) {
      var sheet = thing && thing.sheet;
      if (!sheet) return ctx.time;
      if (sheet.since === undefined) sheet.since = ctx.time;
      return sheet.playing ? sheet.at + (ctx.time - sheet.since) * sheet.rate : sheet.at;
    }

    // Parts of an object a script may steer that are not played — the animation of a puppet,
    // a video — take what they are told and do nothing with it.
    function unsteered() {
      var nothing = lenient({ visible: true, rate: 1, isPlaying: function () { return true; }, getFrame: function () { return 0; },
                              getAnimation: function () { return nothing; } });
      return nothing;
    }

    // How many times a moment of an animation is passed from one frame to another, on a
    // clock of frames that runs on past its end every `period`. A start at nought counts the
    // moment at nought, as the animation is on it then.
    function passings(moment, period, from, to) {
      if (from === 0) from = -1e-6;
      return Math.floor((to - moment) / period) - Math.floor((from - moment) / period);
    }

    // The scripts of an object are told of the moments of its animation that have gone by,
    // with what the value of a script bound to a value is, which it may answer with another.
    // Wallpaper Engine's documentation says only that they are told as an animation passes
    // a frame: that a loop tells them each time round and a mirror on the way back too is
    // taken to go with it.
    function tellAnimationEvents(motion, before, after) {
      var curve = motion.curve;
      if (!curve.events.length || ctx.timelineAt !== null) return;
      var length = curve.frames, from = before * curve.rate, to = after * curve.rate;
      curve.events.forEach(function (event) {
        var times;
        if (curve.mode === 'single' || !(length > 0)) {
          times = (from === 0 ? event.frame >= 0 : event.frame > from) && event.frame <= to ? 1 : 0;
        } else if (curve.mode === 'mirror') {
          times = passings(event.frame, length * 2, from, to);
          if (event.frame > 0 && event.frame < length) times += passings(length * 2 - event.frame, length * 2, from, to);
        } else {
          times = passings(event.frame, length, from, to);
        }
        while (times-- > 0) {
          ctx.scripts.slice().forEach(function (script) {
            if (script.owner !== motion.owner || !script.made || !script.made.animationEvent) return;
            var value = script.value, current = value ? value.now : undefined;
            var answer = call(script, 'animationEvent', { name: event.name, frame: event.frame }, value ? toScript(script, current) : undefined);
            if (value && answer !== undefined) value.now = fromScript(script, answer, current);
          });
        }
      });
    }

    // The animation of one of an object's values that goes by a name; with no name, its first.
    function motionOf(thing, wanted) {
      var found = null;
      Object.keys(thing.lives).forEach(function (name) {
        var motion = thing.lives[name].motion;
        if (motion && !motion.leader && !found && (wanted === undefined || motion.called === wanted)) found = motion;
      });
      return found;
    }

    // An animation as scripts steer it: played, paused and stopped. One that has run to its
    // end plays from its start.
    function steered(found) {
      if (!found.forScripts) {
        found.forScripts = lenient({
          get name() { return found.called; },
          get fps() { return found.curve.rate; },
          get frameCount() { return found.curve.frames; },
          get duration() { return found.curve.frames / found.curve.rate; },
          get rate() { return found.speed; },
          set rate(value) { found.speed = Number(value) || 0; },
          play: function () {
            if (found.curve.mode === 'single' && found.at * found.curve.rate >= found.curve.frames) found.at = 0;
            found.playing = true;
            found.started = true;
            changed();
          },
          pause: function () { found.playing = false; },
          stop: function () {
            found.playing = false;
            found.started = false;
            found.at = 0;
            changed();
          },
          isPlaying: function () { return found.playing; },
          getFrame: function () { return found.at * found.curve.rate; },
          setFrame: function (frame) {
            found.at = Math.max(0, Number(frame) || 0) / found.curve.rate;
            found.started = true;
            changed();
          }
        });
      }
      return found.forScripts;
    }

    function find(wanted) {
      if (wanted && typeof wanted === 'object') return standsFor.get(wanted) || (things.indexOf(wanted) >= 0 ? wanted : null);
      var named = things.filter(function (thing) { return thing.name === wanted; })[0];
      return named || things.filter(function (thing) { return thing.id !== undefined && String(thing.id) === String(wanted); })[0] ||
             (typeof wanted === 'number' ? things[wanted] || null : null);
    }

    var made = 0; // how many layers the scripts have made

    var sceneObject = lenient({
      // An animation by its name, whichever object it belongs to.
      getAnimation: function (wanted) {
        for (var i = 0; i < things.length; i++) {
          var found = motionOf(things[i], wanted);
          if (found) return steered(found);
        }
        return unsteered();
      },
      getLayer: function (wanted) { return find(wanted) ? layerObject(find(wanted)) : null; },
      getLayerByID: function (wanted) { return find(wanted) ? layerObject(find(wanted)) : null; },
      getLayerCount: function () { return things.length; },
      enumerateLayers: function () { return things.map(layerObject); },
      getLayerIndex: function (wanted) { return things.indexOf(find(wanted)); },
      // What the scene says of a layer, as it was before anything changed it.
      getInitialLayerConfig: function (wanted) { return find(wanted) ? find(wanted).said : null; },
      // A layer made while the scene plays, above the others: from the name of a picture's
      // model, or from what an object of a scene is described by.
      createLayer: function (config) {
        var said = {};
        if (typeof config === 'string') {
          said.image = config;
        } else {
          Object.keys(config || {}).forEach(function (name) {
            var value = config[name];
            // A place, a size or a color may come as a script has them, not as a scene writes them.
            said[name] = value && typeof value === 'object' && typeof value.x === 'number' ? String(value) : value;
          });
        }
        // A script of a workshop item names its assets as the item has them, without where
        // Wallpaper Engine keeps the item's: `models/bar.json` for
        // `models/workshop/2652493753/bar.json` (3800075350's sixty-four bars).
        ['image', 'particle', 'model'].forEach(function (kind) {
          if (typeof said[kind] === 'string') said[kind] = workshopAsset(said[kind]);
        });
        made++;
        if (said.id === undefined || ctx.byId[String(said.id)]) said.id = 'made ' + made;
        var thing;
        try {
          thing = ctx.add(said);
        } catch (error) {
          note('a layer a script makes cannot be made: ' + error.message);
          return lenient({});
        }
        ctx.settleIn(thing);
        changed();
        return layerObject(thing);
      },
      destroyLayer: function (wanted) {
        var thing = find(wanted);
        if (!thing) return false;
        [objects, things].forEach(function (list) {
          if (list.indexOf(thing) >= 0) list.splice(list.indexOf(thing), 1);
        });
        if (thing.heldBy) thing.heldBy.held = thing.heldBy.held.filter(function (each) { return each !== thing; });
        if (thing.id !== undefined && ctx.byId[String(thing.id)] === thing) delete ctx.byId[String(thing.id)];
        ctx.scripts = ctx.scripts.filter(function (script) { return script.owner !== thing; });
        if (thing.sound) thing.sound.stop();
        changed();
        return true;
      },
      // Puts a layer at another place in the order the layers are drawn in, the first lowest.
      sortLayer: function (wanted, index) {
        var thing = find(wanted);
        var to = Math.round(Number(index));
        if (!thing || !isFinite(to)) return false;
        [objects, things].forEach(function (list) {
          var from = list.indexOf(thing);
          if (from < 0) return;
          list.splice(from, 1);
          list.splice(Math.max(0, Math.min(list.length, to)), 0, thing);
        });
        changed();
        return true;
      },
      // Where the camera looks and how near: a script may move it about the scene and zoom in.
      getCameraTransforms: function () {
        if (inDepth) {
          var look = cameraLook();
          return { eye: new Vec3(look.eye[0], look.eye[1], look.eye[2]), center: new Vec3(look.center[0], look.center[1], look.center[2]),
                   up: new Vec3(look.up[0], look.up[1], look.up[2]), zoom: ctx.camera.zoom };
        }
        var x = ctx.sceneWidth / 2 + ctx.camera.x, y = ctx.sceneHeight / 2 + ctx.camera.y;
        return { eye: new Vec3(x, y, 1), center: new Vec3(x, y, 0), up: new Vec3(0, 1, 0), zoom: ctx.camera.zoom };
      },
      setCameraTransforms: function (transforms) {
        var said = transforms || {};
        if (inDepth) {
          // In three dimensions the eye is put where the script says, looking where it says.
          var now = cameraLook();
          function three(value, before) {
            return value && isFinite(value.x) && isFinite(value.y) && isFinite(value.z) ? [Number(value.x), Number(value.y), Number(value.z)] : before;
          }
          ctx.scriptedLook = { eye: three(said.eye, now.eye), center: three(said.center, now.center), up: three(said.up, now.up) };
          ctx.dirty = true;
          return;
        }
        var at = said.center || said.eye;
        if (at && typeof at.x === 'number') {
          ctx.camera.x = at.x - ctx.sceneWidth / 2;
          ctx.camera.y = at.y - ctx.sceneHeight / 2;
        }
        if (typeof said.zoom === 'number' && said.zoom > 0) ctx.camera.zoom = said.zoom;
        ctx.dirty = true;
      },
      get camerafade() { return flag(general.camerafade, true); },
      set camerafade(value) { general.camerafade = !!value; },
      // How wide a scene in three dimensions is seen.
      get fov() { return number(general.perspectiveoverridefov, number(general.fov, 50)); },
      set fov(value) { if (Number(value) > 0) { general.perspectiveoverridefov = Number(value); ctx.dirty = true; } },
      get bloom() { return flag(general.bloom, false); },
      set bloom(value) { general.bloom = !!value; ctx.dirty = true; },
      get bloomstrength() { return number(general.bloomstrength, 2); },
      set bloomstrength(value) { general.bloomstrength = Number(value); ctx.dirty = true; },
      get bloomthreshold() { return number(general.bloomthreshold, 0.65); },
      set bloomthreshold(value) { general.bloomthreshold = Number(value); ctx.dirty = true; },
      get clearcolor() { return new Vec3(ctx.clear[0], ctx.clear[1], ctx.clear[2]); },
      set clearcolor(value) { ctx.clear = [value.x, value.y, value.z]; ctx.dirty = true; },
      get cameraparallax() { return flag(general.cameraparallax, false); },
      set cameraparallax(value) { general.cameraparallax = !!value; ctx.dirty = true; }
    });

    // Runs what the scripts asked to be called later, and fills the sound they listen to.
    function serveScripts() {
      ctx.timers.slice().forEach(function (timer) {
        if (ctx.time < timer.at) return;
        if (timer.again) timer.at = ctx.time + Math.max(timer.every, 0.001);
        else ctx.timers = ctx.timers.filter(function (each) { return each !== timer; });
        try {
          timer.callback();
        } catch (error) {
          note('a script fails in what it asked to be called for later: ' + error.message);
        }
      });
      audioBuffers.forEach(function (buffers) {
        var size = buffers.left.length;
        var left = bands(size, false), right = bands(size, true);
        for (var i = 0; i < size; i++) {
          buffers.left[i] = left[i];
          buffers.right[i] = right[i];
          buffers.average[i] = (left[i] + right[i]) / 2;
        }
      });
    }

    // Tells the scripts of something that happened to the scene as a whole.
    function tellScripts(name, argument) {
      var plainObject = argument && typeof argument === 'object' && Object.getPrototypeOf(argument) === Object.prototype;
      ctx.scripts.slice().forEach(function (script) {
        // Each its own copy of what happened: a script that writes into it changes it for no other.
        call(script, name, plainObject ? Object.assign({}, argument) : argument);
      });
    }

    // What music plays, as the page hears of it: each kind of news as it last came. The
    // scripts are told at first that nothing plays, the way Wallpaper Engine tells them — a
    // scene made to put its music widget away then does — and then of what does, once they
    // are ready, and of every change after.
    ctx.mediaTold = false;
    var mediaNews = {};
    function tellNoMedia() {
      ctx.mediaTold = true;
      var none = new Vec3(0, 0, 0);
      tellScripts('mediaStatusChanged', { enabled: false });
      tellScripts('mediaPlaybackChanged', { state: MEDIA_PLAYBACK.PLAYBACK_STOPPED });
      tellScripts('mediaPropertiesChanged', { title: '', artist: '', subTitle: '', albumTitle: '', albumArtist: '', genres: '', contentType: '' });
      tellScripts('mediaThumbnailChanged', { hasThumbnail: false, primaryColor: none, secondaryColor: none, tertiaryColor: none,
                                             textColor: new Vec3(1, 1, 1), highContrastColor: new Vec3(1, 1, 1) });
      tellScripts('mediaTimelineChanged', { position: 0, duration: 0 });
      ['status', 'properties', 'thumbnail', 'playback', 'timeline'].forEach(function (kind) {
        if (mediaNews[kind]) hearOfMedia(kind, mediaNews[kind]);
      });
    }

    // A color as a page is told it, "rgb(255, 128, 0)", as scripts take it.
    function colorOfText(text) {
      var parts = /(\d+(?:\.\d+)?)\D+(\d+(?:\.\d+)?)\D+(\d+(?:\.\d+)?)/.exec(String(text || '')) || [0, 0, 0, 0];
      return new Vec3(Number(parts[1]) / 255, Number(parts[2]) / 255, Number(parts[3]) / 255);
    }

    function hearOfMedia(kind, event) {
      mediaNews[kind] = event;
      if (kind === 'thumbnail') showCover(event.thumbnail || '');
      if (!ctx.mediaTold) return;
      if (kind === 'status') tellScripts('mediaStatusChanged', { enabled: !!event.enabled });
      if (kind === 'properties') tellScripts('mediaPropertiesChanged', event);
      if (kind === 'playback') tellScripts('mediaPlaybackChanged', { state: Number(event.state) || 0 });
      if (kind === 'timeline') tellScripts('mediaTimelineChanged', { position: Number(event.position) || 0, duration: Number(event.duration) || 0 });
      if (kind === 'thumbnail') {
        tellScripts('mediaThumbnailChanged', { hasThumbnail: !!event.thumbnail, primaryColor: colorOfText(event.primaryColor),
                                               secondaryColor: colorOfText(event.secondaryColor), tertiaryColor: colorOfText(event.tertiaryColor),
                                               textColor: colorOfText(event.textColor), highContrastColor: colorOfText(event.highContrastColor) });
      }
      changed();
    }

    // The cover that came becomes the one shown, and the one shown till now the one before it.
    function showCover(address) {
      if (address === covers.shown) return;
      covers.shown = address;
      var before = covers.before.layers[0];
      covers.before.layers[0] = covers.now.layers[0];
      covers.before.width = covers.now.width;
      covers.before.height = covers.now.height;
      covers.now.layers[0] = before;
      function drawn() {
        covers.now.film.users.forEach(stale);
        covers.before.film.users.forEach(stale);
        changed();
      }
      var layer = covers.now.layers[0];
      if (!address) {
        gl.bindTexture(gl.TEXTURE_2D, layer.texture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
        layer.width = layer.height = covers.now.width = covers.now.height = 1;
        drawn();
        return;
      }
      var image = new Image();
      image.onload = function () {
        if (ctx.stopped || covers.shown !== address) return;
        gl.bindTexture(gl.TEXTURE_2D, layer.texture);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
        layer.width = covers.now.width = image.naturalWidth;
        layer.height = covers.now.height = image.naturalHeight;
        drawn();
      };
      image.src = address;
    }

    // Tells the scripts what the mouse did. A script hears of it when the pointer is over the
    // object it belongs to.
    function tellPointer(kind) {
      var world = inputObject.cursorWorldPosition;
      ctx.scripts.slice().forEach(function (script) {
        var made = script.made;
        var thing = script.owner;
        if (!made || !thing || !thing.state || !thing.size || thing.solid === false) return;
        var own = spot(thing, world.x, world.y);
        var over = !!own;
        var event = { worldPosition: world, localPosition: own ? new Vec3(own[0], own[1], 0) : new Vec3(0, 0, 0) };
        if (over !== !!script.over) {
          script.over = over;
          call(script, over ? 'cursorEnter' : 'cursorLeave', event);
        }
        if (!over && !(kind === 'up' && script.held)) return;
        if (kind === 'move') call(script, 'cursorMove', event);
        if (kind === 'down') {
          script.held = true;
          call(script, 'cursorDown', event);
        }
        if (kind === 'up') {
          call(script, 'cursorUp', event);
          if (script.held && over) call(script, 'cursorClick', event);
          script.held = false;
        }
      });
    }

    return { readyScript: readyScript, runScript: runScript, forScripts: forScripts, sheetTime: sheetTime, tellAnimationEvents: tellAnimationEvents, serveScripts: serveScripts, tellScripts: tellScripts, tellNoMedia: tellNoMedia, hearOfMedia: hearOfMedia, tellPointer: tellPointer };
  }

