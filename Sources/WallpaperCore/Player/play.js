  // ------------------------------------------------------------------ the player

  function play(canvas, scene, settings, startingChanges) {
    // --- What the parts made by factories share with play (generated) ---
    var ctx = {
      get CHANNELS() { return CHANNELS; },
      get FILL() { return FILL; },
      get FOLLOWED() { return FOLLOWED; }, set FOLLOWED(value) { FOLLOWED = value; },
      get IDENTITY() { return IDENTITY; },
      get MAX_LIGHTS() { return MAX_LIGHTS; }, set MAX_LIGHTS(value) { MAX_LIGHTS = value; },
      get MOVING() { return MOVING; },
      get PATH_FADE() { return PATH_FADE; }, set PATH_FADE(value) { PATH_FADE = value; },
      get acquire() { return acquire; },
      get activeCamera() { return activeCamera; },
      get add() { return add; },
      get all() { return all; }, set all(value) { all = value; },
      get also() { return also; },
      get asked() { return asked; }, set asked(value) { asked = value; },
      get audioBuffers() { return audioBuffers; }, set audioBuffers(value) { audioBuffers = value; },
      get bands() { return bands; },
      get before() { return before; }, set before(value) { before = value; },
      get blendProgram() { return blendProgram; }, set blendProgram(value) { blendProgram = value; },
      get bound() { return bound; },
      get buildEffects() { return buildEffects; },
      get buildImage() { return buildImage; },
      get buildLight() { return buildLight; },
      get buildModel() { return buildModel; },
      get buildParticles() { return buildParticles; },
      get buildPass() { return buildPass; },
      get buildPuppet() { return buildPuppet; },
      get buildSound() { return buildSound; },
      get buildText() { return buildText; },
      get byId() { return byId; }, set byId(value) { byId = value; },
      get camera() { return camera; }, set camera(value) { camera = value; },
      get cameraLook() { return cameraLook; },
      get cameraMatrix() { return cameraMatrix; },
      get canvas() { return canvas; },
      get changed() { return changed; },
      get changes() { return changes; }, set changes(value) { changes = value; },
      get chosenTexture() { return chosenTexture; },
      get clear() { return clear; }, set clear(value) { clear = value; },
      get clipMaskProgram() { return clipMaskProgram; }, set clipMaskProgram(value) { clipMaskProgram = value; },
      get clippedProgram() { return clippedProgram; }, set clippedProgram(value) { clippedProgram = value; },
      get complaint() { return complaint; }, set complaint(value) { complaint = value; },
      get compositeNamed() { return compositeNamed; },
      get composites() { return composites; }, set composites(value) { composites = value; },
      get copyTarget() { return copyTarget; }, set copyTarget(value) { copyTarget = value; },
      get covers() { return covers; }, set covers(value) { covers = value; },
      get depthOf() { return depthOf; },
      get description() { return description; },
      get dirty() { return dirty; }, set dirty(value) { dirty = value; },
      get drawImage() { return drawImage; },
      get drawPass() { return drawPass; },
      get editions() { return editions; }, set editions(value) { editions = value; },
      get engineValue() { return engineValue; },
      get eye() { return eye; }, set eye(value) { eye = value; },
      get eyePlace() { return eyePlace; },
      get files() { return files; },
      get fillVertex() { return fillVertex; }, set fillVertex(value) { fillVertex = value; },
      get films() { return films; }, set films(value) { films = value; },
      get flat() { return flat; },
      get forgetTargets() { return forgetTargets; },
      get frameAt() { return frameAt; },
      get frameTime() { return frameTime; }, set frameTime(value) { frameTime = value; },
      get frames() { return frames; }, set frames(value) { frames = value; },
      get freeLook() { return freeLook; },
      get general() { return general; },
      get gl() { return gl; },
      get glow() { return glow; },
      get grabProgram() { return grabProgram; }, set grabProgram(value) { grabProgram = value; },
      get hearing() { return hearing; },
      get inDepth() { return inDepth; },
      get isLively() { return isLively; },
      get isMoving() { return isMoving; },
      get isSet() { return isSet; },
      get joined() { return joined; },
      get json() { return json; },
      get link() { return link; },
      get listen() { return listen; },
      get listening() { return listening; }, set listening(value) { listening = value; },
      get live() { return live; },
      get liveOfAnyKind() { return liveOfAnyKind; },
      get loading() { return loading; }, set loading(value) { loading = value; },
      get look() { return look; },
      get looksOf() { return looksOf; },
      get m4invert() { return m4invert; },
      get m4mul() { return m4mul; },
      get matrixOf() { return matrixOf; },
      get mediaTold() { return mediaTold; }, set mediaTold(value) { mediaTold = value; },
      get merged() { return merged; },
      get meshBlendProgram() { return meshBlendProgram; }, set meshBlendProgram(value) { meshBlendProgram = value; },
      get meshProgram() { return meshProgram; }, set meshProgram(value) { meshProgram = value; },
      get mice() { return mice; }, set mice(value) { mice = value; },
      get mix() { return mix; },
      get motions() { return motions; }, set motions(value) { motions = value; },
      get newTexture() { return newTexture; },
      get nextPath() { return nextPath; },
      get nudged() { return nudged; },
      get numbersOf() { return numbersOf; },
      get objects() { return objects; },
      get passBuffer() { return passBuffer; }, set passBuffer(value) { passBuffer = value; },
      get passShape() { return passShape; }, set passShape(value) { passShape = value; },
      get pathLook() { return pathLook; },
      get pathLuck() { return pathLuck; }, set pathLuck(value) { pathLuck = value; },
      get pictures() { return pictures; },
      get placeOf() { return placeOf; },
      get placeProgram() { return placeProgram; }, set placeProgram(value) { placeProgram = value; },
      get placed() { return placed; },
      get players() { return players; }, set players(value) { players = value; },
      get pointer() { return pointer; }, set pointer(value) { pointer = value; },
      get pointerBefore() { return pointerBefore; }, set pointerBefore(value) { pointerBefore = value; },
      get pointerSeen() { return pointerSeen; }, set pointerSeen(value) { pointerSeen = value; },
      get pressed() { return pressed; }, set pressed(value) { pressed = value; },
      get pristine() { return pristine; }, set pristine(value) { pristine = value; },
      get puppets() { return puppets; },
      get put() { return put; },
      get redraw() { return redraw; }, set redraw(value) { redraw = value; },
      get refresh() { return refresh; },
      get release() { return release; },
      get releaseRepeated() { return releaseRepeated; },
      get resize() { return resize; },
      get runScript() { return runScript; },
      get same() { return same; },
      get scale() { return scale; }, set scale(value) { scale = value; },
      get scene() { return scene; },
      get sceneAt() { return sceneAt; },
      get sceneHeight() { return sceneHeight; }, set sceneHeight(value) { sceneHeight = value; },
      get sceneLights() { return sceneLights; },
      get scenePathLook() { return scenePathLook; },
      get scenePaths() { return scenePaths; }, set scenePaths(value) { scenePaths = value; },
      get sceneTarget() { return sceneTarget; }, set sceneTarget(value) { sceneTarget = value; },
      get sceneVersion() { return sceneVersion; },
      get sceneWidth() { return sceneWidth; }, set sceneWidth(value) { sceneWidth = value; },
      get screenLayer() { return screenLayer; },
      get scriptErrors() { return scriptErrors; }, set scriptErrors(value) { scriptErrors = value; },
      get scriptLog() { return scriptLog; }, set scriptLog(value) { scriptLog = value; },
      get scripted() { return scripted; }, set scripted(value) { scripted = value; },
      get scriptedLook() { return scriptedLook; }, set scriptedLook(value) { scriptedLook = value; },
      get scripts() { return scripts; }, set scripts(value) { scripts = value; },
      get seenOnce() { return seenOnce; }, set seenOnce(value) { seenOnce = value; },
      get seenPart() { return seenPart; },
      get serveScripts() { return serveScripts; },
      get setUniform() { return setUniform; },
      get settleIn() { return settleIn; },
      get shake() { return shake; }, set shake(value) { shake = value; },
      get shared() { return shared; }, set shared(value) { shared = value; },
      get sheetFrames() { return sheetFrames; },
      get sheetTime() { return sheetTime; },
      get shifted() { return shifted; },
      get showFilms() { return showFilms; },
      get shownAt() { return shownAt; },
      get shows() { return shows; },
      get showsAll() { return showsAll; },
      get soundFiles() { return soundFiles; },
      get spectrum() { return spectrum; }, set spectrum(value) { spectrum = value; },
      get spot() { return spot; },
      get stale() { return stale; },
      get standing() { return standing; },
      get startingChanges() { return startingChanges; },
      get stopped() { return stopped; }, set stopped(value) { stopped = value; },
      get stored() { return stored; }, set stored(value) { stored = value; },
      get straightProgram() { return straightProgram; }, set straightProgram(value) { straightProgram = value; },
      get surface() { return surface; }, set surface(value) { surface = value; },
      get tellAnimationEvents() { return tellAnimationEvents; },
      get tellNoMedia() { return tellNoMedia; },
      get tellPointer() { return tellPointer; },
      get tellScripts() { return tellScripts; },
      get texture() { return texture; },
      get things() { return things; }, set things(value) { things = value; },
      get time() { return time; }, set time(value) { time = value; },
      get timelineAt() { return timelineAt; }, set timelineAt(value) { timelineAt = value; },
      get timers() { return timers; }, set timers(value) { timers = value; },
      get times() { return times; },
      get undone() { return undone; },
      get unplaced() { return unplaced; },
      get view() { return view; },
      get viewOnce() { return viewOnce; }, set viewOnce(value) { viewOnce = value; },
      get viewProjection() { return viewProjection; },
      get wake() { return wake; },
      get withLooks() { return withLooks; },
      get workshopAsset() { return workshopAsset; },
      get worldPlaceOf() { return worldPlaceOf; }
    };
    // --- end of what is shared ---
    if (editorClock.on) seedChance(); else Math.random = unseeded;
    properties = {};
    Object.keys(settings || {}).forEach(function (name) { properties[name] = settings[name]; });
    // The tables of a scene laid out before names were kept with their marks written as one
    // have them as the Mac wrote them, apart: they are known by their names as `key` gives them.
    function keyed(table) {
      var result = {};
      Object.keys(table || {}).forEach(function (name) { result[key(name)] = table[name]; });
      return result;
    }
    var files = keyed(scene && scene.files);
    SCRIPTS_SHARE_GLOBAL = Object.keys(files).some(function (name) {
      return typeof files[name] === 'string' && files[name].indexOf('globalThis') >= 0;
    });
    // Materials Wallpaper Engine has for its effects and a scene names without bringing them,
    // made here to the same purpose. Its compose pass puts the layer's picture over what the
    // scene shows under the layer, as much as the picture is not see-through, and leaves
    // nothing see-through (3794460976's refraction starts with one).
    var OWN_MATERIALS = {
      'materials/util/effectcomposebackground.json': '{"passes": [{"shader": "wallaero/composebackground", "blending": "normal", "textures": [null, "_rt_FullFrameBuffer"]}]}',
      'shaders/wallaero/composebackground.vert': [
        'uniform mat4 g_ModelViewProjectionMatrix;',
        'uniform mat4 g_EffectModelViewProjectionMatrix;',
        'attribute vec3 a_Position;',
        'attribute vec2 a_TexCoord;',
        'varying vec2 v_TexCoord;',
        'varying vec3 v_Under;',
        'void main() {',
        '  gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);',
        '  v_TexCoord = a_TexCoord;',
        '  v_Under = mul(vec4(a_Position, 1.0), g_EffectModelViewProjectionMatrix).xyw;',
        '}'
      ].join('\n'),
      'shaders/wallaero/composebackground.frag': [
        'varying vec2 v_TexCoord;',
        'varying vec3 v_Under;',
        'uniform sampler2D g_Texture0;',
        'uniform sampler2D g_Texture1;',
        'void main() {',
        '  vec4 own = texSample2D(g_Texture0, v_TexCoord);',
        '  vec4 under = texSample2D(g_Texture1, v_Under.xy / v_Under.z * 0.5 + 0.5);',
        '  gl_FragColor = vec4(mix(under.rgb, own.rgb, own.a), 1.0);',
        '}'
      ].join('\n')
    };
    Object.keys(OWN_MATERIALS).forEach(function (name) {
      if (typeof files[name] !== 'string') files[name] = OWN_MATERIALS[name];
    });
    var pictures = keyed(scene && scene.textures);
    var soundFiles = keyed(scene && scene.sounds);
    var puppets = keyed(scene && scene.puppets);
    var stopped = false;
    var gl = canvas.getContext('webgl2', { alpha: false, antialias: false, depth: false, stencil: false,
                                           premultipliedAlpha: false, preserveDrawingBuffer: false });
    if (!gl) {
      note('this Mac\'s web engine has no WebGL 2; the scene cannot be drawn');
      return { stop: function () {} };
    }
    // What is bound is kept here as it is bound. Asking the context for it makes the page wait
    // for the GPU's process to answer, and asked for every pass of every frame that adds up to
    // more than the frame has.
    var bound = { draw: null, read: null, viewport: [0, 0, canvas.width, canvas.height] };
    (function () {
      var bindFramebuffer = gl.bindFramebuffer, viewport = gl.viewport;
      gl.bindFramebuffer = function (target, framebuffer) {
        if (target === gl.FRAMEBUFFER || target === gl.DRAW_FRAMEBUFFER) bound.draw = framebuffer;
        if (target === gl.FRAMEBUFFER || target === gl.READ_FRAMEBUFFER) bound.read = framebuffer;
        return bindFramebuffer.call(gl, target, framebuffer);
      };
      gl.viewport = function (x, y, width, height) {
        bound.viewport = [x, y, width, height];
        return viewport.call(gl, x, y, width, height);
      };
    })();

    // A file of the scene that holds JSON. The files are written by programs, but by many
    // versions of them; one that does not parse is treated as missing.
    // A file as a scene names it, or as it lies among a workshop item's own: the same name
    // with `workshop/<the item>` after its first folder.
    function workshopAsset(name) {
      if (typeof files[key(name)] === 'string') return name;
      var parts = /^([^\/]+)\/(.+)$/.exec(key(name));
      if (!parts) return name;
      var found = Object.keys(files).filter(function (each) {
        return each.indexOf(parts[1] + '/workshop/') === 0 && each.slice(-(parts[2].length + 1)) === '/' + parts[2] &&
               /^\d+$/.test(each.slice(parts[1].length + 10, each.length - parts[2].length - 1));
      })[0];
      return found || name;
    }

    function json(name) {
      var text = files[key(name)];
      if (typeof text !== 'string') return null;
      try {
        return JSON.parse(text);
      } catch (error) {
        try {
          return JSON.parse(text.replace(/,(\s*[}\]])/g, '$1'));
        } catch (again) {
          note(name + ' cannot be read');
          return null;
        }
      }
    }

    // Programs: programs.js.
    var complaint;
    var programsPart = makePrograms(ctx);
    var link = programsPart.link;
    // Shapes: shapes.js.
    var passShape, passBuffer;
    makeShapes(ctx);
    // Textures: textures.js.
    var loading, composites, covers, films;
    var texturesPart = makeTextures(ctx);
    var compositeNamed = texturesPart.compositeNamed, newTexture = texturesPart.newTexture, looksOf = texturesPart.looksOf, sheetFrames = texturesPart.sheetFrames, flat = texturesPart.flat, shows = texturesPart.shows, showFilms = texturesPart.showFilms, chosenTexture = texturesPart.chosenTexture, texture = texturesPart.texture;
    // Pictures to draw into: targets.js.
    var targetsPart = makeTargets(ctx);
    var acquire = targetsPart.acquire, release = targetsPart.release, depthOf = targetsPart.depthOf, forgetTargets = targetsPart.forgetTargets;
    // --- The scene --------------------------------------------------------

    var description = json('scene.json') || {};
    var general = description.general || {};
    // The version of Wallpaper Engine's scene format the scene was saved in: some things are
    // drawn otherwise from one version on.
    var sceneVersion = number(description.version, 1);
    // A scene in three dimensions, seen through a camera that stands in it, rather than a
    // picture of so many pixels: there the scene's pixels and the camera's 2D offsets mean nothing.
    var inDepth = !general.orthogonalprojection;
    var projection = general.orthogonalprojection || {};
    var sceneWidth = number(projection.width, 0);
    var sceneHeight = number(projection.height, 0);
    // Where an object the scene does not place is: one that hangs on another, where that one
    // is; else the middle of the scene. In three dimensions, where the scene has no middle
    // but its world, at nought: a model (3737268876's sky and courtyard), a group, which
    // places what hangs on it in the world's units (3662790108's whole solar system), a
    // picture. A layer of the whole screen stays at its middle (3706286085's blur).
    function unplaced(object) {
      if (isSet(object.parent) || (inDepth && !screenLayer(object))) return 0;
      return [sceneWidth / 2, sceneHeight / 2, 0];
    }
    // A layer Wallpaper Engine lays over the whole screen, to put effects over what is under it.
    function screenLayer(object) {
      return /composelayer|fullscreenlayer|projectlayer/.test(key(String(plain(object.image) || '')));
    }
    var clear = numbers(general.clearcolor, 3, 0);
    var scale = 1;          // pixels drawn to a unit of the scene
    var sceneTarget = null; // the whole scene, as drawn so far
    var copyTarget = null;  // a copy of it, for what is blended with what lies under it
    var time = 0;
    var frameTime = 1 / 60;
    var pointer = [0.5, 0.5];
    var pointerSeen = false; // whether the pointer is over the wallpaper, as far as is known
    var pointerBefore = [0.5, 0.5];
    var spectrum = null;    // 64 bands left, 64 right, once a shader asks for the sound
    var objects = [];
    var redraw = true;      // something changed that a still scene has to be drawn again for

    function changed() {
      redraw = true;
      wake();
    }

    var IDENTITY = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    var MOVING = /^g_(Time|Frametime|Daytime|PointerPosition|PointerPositionLast|AudioSpectrum\d+(Left|Right))$/;

    function bands(count, right) {
      var values = new Float32Array(count);
      if (!spectrum) return values;
      var each = 64 / count;
      for (var i = 0; i < count; i++) {
        var sum = 0;
        for (var j = 0; j < each; j++) sum += spectrum[(right ? 64 : 0) + i * each + j] || 0;
        values[i] = sum / each;
      }
      return values;
    }

    // What Wallpaper Engine itself tells a shader, by the uniform's name.
    function engineValue(name, context) {
      switch (name) {
        case 'g_Time': return [time];
        case 'g_Frametime': return [frameTime];
        case 'g_Daytime': var now = new Date(); return [(now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400];
        case 'g_PointerPosition': return pointer;
        case 'g_PointerPositionLast': return pointerBefore;
        // Whether the mouse button is down.
        case 'g_PointerState': return [pressed ? 1 : 0, 0, pressed ? 1 : 0, 0];
        case 'g_TexelSize': return [1 / context.width, 1 / context.height];
        case 'g_TexelSizeHalf': return [0.5 / context.width, 0.5 / context.height];
        case 'g_Screen': return [sceneWidth, sceneHeight, sceneWidth / sceneHeight];
        case 'g_ParallaxPosition': return [0.5, 0.5];
        case 'g_Alpha': case 'g_UserAlpha': case 'g_Brightness': return [1];
        case 'g_Color': return [1, 1, 1];
        case 'g_Color4': return [1, 1, 1, 1];
        case 'g_EyePosition': return [0, 0, 1];
        case 'g_ViewUp': case 'g_OrientationUp': return [0, 1, 0];
        case 'g_ViewRight': case 'g_OrientationRight': return [1, 0, 0];
        case 'g_ViewForward': case 'g_OrientationForward': return [0, 0, -1];
      }
      var resolution = /^g_Texture(\d)Resolution$/.exec(name);
      if (resolution) return context.resolutions[Number(resolution[1])] || [1, 1, 1, 1];
      if (/^g_Texture\dRotation$/.test(name)) return [1, 0, 0, 1];
      if (/^g_Texture\dTranslation$/.test(name)) return [0, 0];
      var audio = /^g_AudioSpectrum(16|32|64)(Left|Right)$/.exec(name);
      if (audio) return bands(Number(audio[1]), audio[2] === 'Right');
      return null;
    }

    function setUniform(uniform, values) {
      var location = uniform.location;
      switch (uniform.type) {
        case gl.FLOAT:
          if (uniform.size > 1) gl.uniform1fv(location, new Float32Array(values).subarray(0, uniform.size));
          else gl.uniform1f(location, values[0]);
          break;
        case gl.FLOAT_VEC2: gl.uniform2f(location, values[0], values[1]); break;
        case gl.FLOAT_VEC3: gl.uniform3f(location, values[0], values[1], values[2]); break;
        case gl.FLOAT_VEC4: gl.uniform4f(location, values[0], values[1], values[2], values[3]); break;
        case gl.INT: case gl.BOOL: gl.uniform1i(location, values[0]); break;
      }
    }

    // A pass of an effect: effects.js.
    var effectsPart = makeEffects(ctx);
    var buildPass = effectsPart.buildPass, withLooks = effectsPart.withLooks, drawPass = effectsPart.drawPass;
    // `count` numbers, or with `kind` 'flag' a yes or no, or with 'text' a text. `unit`
    // 'degrees' is for angles: the scene writes them in radians, scripts count in degrees.
    function live(raw, count, fallback, owner, kind, unit) {
      var behind = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : null;
      var curve = behind ? curveOf(behind.animation) : null;
      var script = behind && typeof behind.script === 'string' ? { said: behind, owner: owner, kind: kind || 'numbers', count: count, unit: unit } : null;
      if (script) scripts.push(script);
      // What the scene says is `value.raw`: the editor may make it another while the scene plays.
      function base() {
        if (kind === 'text') {
          var text = plain(value.raw);
          return text === undefined || text === null ? '' : String(text);
        }
        if (kind === 'flag') return flag(value.raw, fallback);
        return numbers(value.raw, count, fallback);
      }
      // An animation plays from the scene's start, or waits for a script to play it; `at` is
      // how far it has played, in seconds. One that follows another plays as that one does.
      // Until one that waits has been played, the value stays as the scene gives it.
      function motionOf(made) {
        var result = { curve: made, called: made.called, at: 0, playing: !made.startsPaused, started: !made.startsPaused,
                       speed: 1, leader: null, owner: owner };
        motions.push(result);
        return result;
      }
      var motion = curve ? motionOf(curve) : null;
      // `bound`: a setting of the wallpaper stands behind it.
      var value = { raw: raw, changes: !!curve, motion: motion, script: script, bound: !!(behind && behind.user !== undefined && behind.user !== null) };
      value.now = base();
      if (script) script.value = value;
      // The editor has changed what the scene says: the animation behind it may be another.
      value.renew = function () {
        var said = value.raw && typeof value.raw === 'object' && !Array.isArray(value.raw) ? value.raw : null;
        var next = said ? curveOf(said.animation) : null;
        if (next && motion) {
          motion.curve = next;
          motion.called = next.called;
        } else if (next) {
          motion = motionOf(next);
        } else if (motion) {
          motions.splice(motions.indexOf(motion), 1);
          motion = null;
        }
        curve = next;
        value.motion = motion;
        value.changes = !!next;
      };
      value.read = function () {
        // A script carries on from what the value is; anything else starts from what the
        // scene says.
        var result = script && script.made !== undefined ? value.now : base();
        if (curve && timelineAt !== null) result = curve(timelineAt, result);
        else if (curve && (motion.leader || motion).started) result = curve((motion.leader || motion).at, result);
        if (script) result = runScript(script, result);
        value.now = result;
        return result;
      };
      return value;
    }
    // Values that change: changing-values.js.
    var things, motions, timelineAt, scripts, timers, shared, stored, dirty, pressed, audioBuffers;
    var changingValuesPart = makeChangingValues(ctx);
    var same = changingValuesPart.same, liveOfAnyKind = changingValuesPart.liveOfAnyKind;
    // Scripts: scene-scripts.js.
    var scriptErrors, scriptLog, mediaTold;
    var sceneScriptsPart = makeSceneScripts(ctx);
    var readyScript = sceneScriptsPart.readyScript, runScript = sceneScriptsPart.runScript, forScripts = sceneScriptsPart.forScripts, sheetTime = sceneScriptsPart.sheetTime, tellAnimationEvents = sceneScriptsPart.tellAnimationEvents, serveScripts = sceneScriptsPart.serveScripts, tellScripts = sceneScriptsPart.tellScripts, tellNoMedia = sceneScriptsPart.tellNoMedia, hearOfMedia = sceneScriptsPart.hearOfMedia, tellPointer = sceneScriptsPart.tellPointer;
    // Putting a picture on the scene: putting.js.
    var grabProgram, placeProgram, straightProgram, meshProgram, clipMaskProgram, clippedProgram, blendProgram, meshBlendProgram;
    makePutting(ctx);
    // --- Where things stand -------------------------------------------------------
    //
    // An object has a place, a size and a turn about each of the three axes, all counted from
    // the object it hangs on. They are kept as a matrix of four by four, column by column.
    // The scene is looked at from straight ahead and from far: depth shows only in how
    // something turned is foreshortened, and in where what lies behind it comes to stand.

    // What is being drawn on: the scene, or a layer that holds other layers. `left` and
    // `bottom` are where its lower left corner is, in the coordinates of what is drawn on it.
    var surface = null;

    // First `second`, then `first`.
    function times(first, second) {
      var result = new Array(16);
      for (var column = 0; column < 4; column++) {
        for (var row = 0; row < 4; row++) {
          result[column * 4 + row] = first[row] * second[column * 4] + first[4 + row] * second[column * 4 + 1] +
                                     first[8 + row] * second[column * 4 + 2] + first[12 + row] * second[column * 4 + 3];
        }
      }
      return result;
    }

    // Scaled, then turned about x, then about y, then about z, then moved.
    function matrixOf(origin, angles, scale) {
      var cx = Math.cos(angles[0]), sx = Math.sin(angles[0]);
      var cy = Math.cos(angles[1]), sy = Math.sin(angles[1]);
      var cz = Math.cos(angles[2]), sz = Math.sin(angles[2]);
      return [
        cz * cy * scale[0], sz * cy * scale[0], -sy * scale[0], 0,
        (cz * sy * sx - sz * cx) * scale[1], (sz * sy * sx + cz * cx) * scale[1], cy * sx * scale[1], 0,
        (cz * sy * cx + sz * sx) * scale[2], (sz * sy * cx - cz * sx) * scale[2], cy * cx * scale[2], 0,
        origin[0], origin[1], origin[2], 1
      ];
    }

    // The same, for something moved by (x, y) of its own before anything else.
    function nudged(matrix, x, y) {
      var result = matrix.slice();
      result[12] += matrix[0] * x + matrix[4] * y;
      result[13] += matrix[1] * x + matrix[5] * y;
      result[14] += matrix[2] * x + matrix[6] * y;
      return result;
    }

    // Where a rectangle lands on what is drawn on, as a matrix for the shader. `matrix` takes
    // the rectangle's own coordinates — from its middle, y up — to those of the surface.
    function placeOf(matrix, size) {
      var width = surface.width, height = surface.height;
      return new Float32Array([
        2 * matrix[0] * size[0] / width, -2 * matrix[1] * size[0] / height, 0,
        2 * matrix[4] * size[1] / width, -2 * matrix[5] * size[1] / height, 0,
        2 * (matrix[12] - surface.left) / width - 1, 1 - 2 * (matrix[13] - surface.bottom) / height, 1
      ]);
    }

    // Where a rectangle stands in a scene in three dimensions, as seen through the camera: a
    // matrix of four by four from its own coordinates, from its middle with y up. `tests`:
    // whether it is hidden behind what is nearer, as a material that tests depth asks.
    function worldPlaceOf(matrix, size, tests) {
      var sized = matrix.slice();
      [0, 1, 2].forEach(function (index) { sized[index] *= size[0]; sized[4 + index] *= size[1]; });
      var place = new Float32Array(times4(viewProjection(), sized));
      place.tests = !!tests;
      return place;
    }
    // Tells a program where to put what it draws: on the surface, or in the world.
    function placeIn(program, place) {
      var inWorld = place.length === 16;
      if (program.uniforms.u_InWorld) gl.uniform1i(program.uniforms.u_InWorld.location, inWorld ? 1 : 0);
      if (inWorld) gl.uniformMatrix4fv(program.uniforms.u_World.location, false, place);
      else gl.uniformMatrix3fv(program.uniforms.u_Place.location, false, place);
    }

    var CHANNELS = { rgba: 0, r8: 1, rg88: 2 };

    // The pixels of `onto` a rectangle placed by `place` covers, as x0, y0, x1, y1, with a
    // pixel to spare round it; null if it covers it all.
    function coveredBy(place, onto) {
      var low = [Infinity, Infinity], high = [-Infinity, -Infinity];
      [[-0.5, -0.5], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.5]].forEach(function (corner) {
        var x = place[0] * corner[0] + place[3] * corner[1] + place[6];
        var y = place[1] * corner[0] + place[4] * corner[1] + place[7];
        low = [Math.min(low[0], x), Math.min(low[1], y)];
        high = [Math.max(high[0], x), Math.max(high[1], y)];
      });
      var x0 = Math.max(0, Math.floor((low[0] + 1) / 2 * onto.width) - 1), y0 = Math.max(0, Math.floor((low[1] + 1) / 2 * onto.height) - 1);
      var x1 = Math.min(onto.width, Math.ceil((high[0] + 1) / 2 * onto.width) + 1), y1 = Math.min(onto.height, Math.ceil((high[1] + 1) / 2 * onto.height) + 1);
      if (!(x1 > x0 && y1 > y0)) return [0, 0, 1, 1];
      if (x0 === 0 && y0 === 0 && x1 === onto.width && y1 === onto.height) return null;
      return [x0, y0, x1, y1];
    }

    // Draws a texture onto whatever is bound, placed by `place`.
    // `how`: 'translucent', 'additive', 'normal' (as it is, over what is there) or a number,
    // one of the blend modes. `mesh`, if given, is drawn in place of the plain rectangle.
    function put(source, place, tint, how, mesh) {
      if (mesh && mesh.clips && mesh.clips.length && typeof how !== 'number' && clipMaskProgram && clippedProgram) {
        putClipped(source, place, tint, how, mesh);
        return;
      }
      var program = mesh ? meshProgram : placeProgram;
      var onto = surface.target;
      if (typeof how === 'number') {
        // What is under the picture is read from a copy of what it is drawn on.
        if (!surface.copy) surface.copy = acquire(onto.width, onto.height);
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, onto.framebuffer);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, surface.copy.framebuffer);
        // Only what lies under the picture: a small one copies a small part.
        var under = mesh || place.length === 16 ? null : coveredBy(place, onto);
        if (under) gl.blitFramebuffer(under[0], under[1], under[2], under[3], under[0], under[1], under[2], under[3], gl.COLOR_BUFFER_BIT, gl.NEAREST);
        else gl.blitFramebuffer(0, 0, onto.width, onto.height, 0, 0, onto.width, onto.height, gl.COLOR_BUFFER_BIT, gl.NEAREST);
        gl.bindFramebuffer(gl.FRAMEBUFFER, onto.framebuffer);
        program = mesh ? meshBlendProgram : blendProgram;
      }
      if (!program) return;
      gl.useProgram(program.program);
      if (typeof how === 'number') {
        gl.disable(gl.BLEND);
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, surface.copy.texture);
        gl.uniform1i(program.uniforms.u_Scene.location, 1);
        gl.uniform2f(program.uniforms.u_SceneSize.location, onto.width, onto.height);
        gl.uniform1i(program.uniforms.u_Mode.location, how);
      } else if (how === 'normal') {
        gl.disable(gl.BLEND);
      } else {
        gl.enable(gl.BLEND);
        if (how === 'additive') gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
        else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      }
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, source.texture);
      gl.uniform1i(program.uniforms.u_Texture.location, 0);
      placeIn(program, place);
      gl.uniform4fv(program.uniforms.u_Tint.location, tint);
      gl.uniform4fv(program.uniforms.u_Frame.location, source.frame || [0, 0, 1, 1]);
      gl.uniform1i(program.uniforms.u_Channels.location, CHANNELS[source.channels] || 0);
      if (source.sampler) gl.bindSampler(0, source.sampler);
      if (place.tests) {
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LEQUAL);
        gl.depthMask(false);
      }
      if (mesh) {
        gl.bindVertexArray(mesh.shape);
        gl.drawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_SHORT, 0);
        gl.bindVertexArray(null);
      } else {
        gl.bindVertexArray(passShape);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      }
      if (place.tests) {
        gl.disable(gl.DEPTH_TEST);
        gl.depthMask(true);
      }
      if (source.sampler) gl.bindSampler(0, null);
    }

    // A puppet drawn part by part, in its order: a part that shows only within others through
    // a mask of those others, drawn first as they are bent at the moment.
    function putClipped(source, place, tint, how, mesh) {
      var framebuffer = bound.draw;
      var view = bound.viewport.slice();
      var width = view[2], height = view[3];
      var clippedBy = {};
      mesh.clips.forEach(function (clip) { clippedBy[clip.part] = clip; });
      function useMesh(program) {
        gl.useProgram(program.program);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, source.texture);
        gl.uniform1i(program.uniforms.u_Texture.location, 0);
        placeIn(program, place);
        gl.uniform4fv(program.uniforms.u_Tint.location, tint);
        gl.uniform4fv(program.uniforms.u_Frame.location, source.frame || [0, 0, 1, 1]);
        gl.uniform1i(program.uniforms.u_Channels.location, CHANNELS[source.channels] || 0);
      }
      function blended(always) {
        if (how === 'normal' && !always) {
          gl.disable(gl.BLEND);
          return;
        }
        gl.enable(gl.BLEND);
        if (how === 'additive') gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
        else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      }
      function drawPart(index) {
        var part = mesh.parts[index];
        if (part && part[1] > 0) gl.drawElements(gl.TRIANGLES, part[1], gl.UNSIGNED_SHORT, part[0] * 2);
      }
      gl.bindVertexArray(mesh.shape);
      for (var index = 0; index < mesh.parts.length; index++) {
        var clip = clippedBy[index];
        if (!clip) {
          useMesh(meshProgram);
          blended(false);
          drawPart(index);
          continue;
        }
        var mask = acquire(width, height);
        gl.bindFramebuffer(gl.FRAMEBUFFER, mask.framebuffer);
        gl.viewport(0, 0, width, height);
        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT);
        gl.useProgram(clipMaskProgram.program);
        var byPicture = !!(clip.picture && clip.picture.ready && clip.picture.layers[0]);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, byPicture ? clip.picture.layers[0].texture : source.texture);
        gl.uniform1i(clipMaskProgram.uniforms.u_Texture.location, 0);
        gl.uniform1i(clipMaskProgram.uniforms.u_Alpha.location, byPicture ? 0 : 1);
        placeIn(clipMaskProgram, place);
        gl.enable(gl.BLEND);
        gl.blendEquation(gl.MAX);
        clip.masks.forEach(drawPart);
        gl.blendEquation(gl.FUNC_ADD);
        gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
        gl.viewport(view[0], view[1], view[2], view[3]);
        useMesh(clippedProgram);
        gl.activeTexture(gl.TEXTURE2);
        gl.bindTexture(gl.TEXTURE_2D, mask.texture);
        gl.uniform1i(clippedProgram.uniforms.u_Mask.location, 2);
        gl.uniform2f(clippedProgram.uniforms.u_MaskSize.location, width, height);
        blended(true);
        drawPart(index);
        gl.activeTexture(gl.TEXTURE0);
        release(mask);
      }
      gl.bindVertexArray(null);
    }

    // The whole of a target, as the matrix that fills it.
    var FILL = new Float32Array([2, 0, 0, 0, -2, 0, 0, 0, 1]);

    // Pictures that bend: puppets.js.
    var puppetsPart = makePuppets(ctx);
    var numbersOf = puppetsPart.numbersOf, joined = puppetsPart.joined, undone = puppetsPart.undone, buildPuppet = puppetsPart.buildPuppet;
    // Models in three dimensions: models.js.
    var MAX_LIGHTS;
    var modelsPart = makeModels(ctx);
    var sceneLights = modelsPart.sceneLights, viewProjection = modelsPart.viewProjection, m4mul = modelsPart.m4mul, m4invert = modelsPart.m4invert, buildModel = modelsPart.buildModel, buildLight = modelsPart.buildLight;
    // The editor's own eye on a scene in three dimensions, while it looks freely.
    function freeLook() {
      return inDepth && editorView.free && editorView.look ? editorView.look : null;
    }
    function cameraLook() {
      if (scriptedLook) return scriptedLook;
      var shot = activeCamera();
      if (shot) {
        var m = cameraMatrix(shot);
        return { eye: [m[12], m[13], m[14]], center: [m[12] - m[8], m[13] - m[9], m[14] - m[10]], up: [m[4], m[5], m[6]] };
      }
      var onScenePath = scenePathLook();
      if (onScenePath) return { eye: onScenePath.eye.slice(), center: onScenePath.center.slice(), up: onScenePath.up.slice() };
      var said = description.camera || {};
      var eye = numbers(said.eye, 3, 0), center = numbers(said.center, 3, 0), up = numbers(said.up, 3, 0);
      if (!said.eye) { eye = [0, 0, 1]; center = [0, 0, 0]; }
      if (!(up[0] || up[1] || up[2])) up = [0, 1, 0];
      return { eye: eye, center: center, up: up };
    }
    function eyePlace() {
      if (freeLook()) return freeLook().eye;
      if (inDepth && scriptedLook) return scriptedLook.eye;
      if (inDepth) {
        var shot = activeCamera();
        if (shot) { var m = cameraMatrix(shot); return [m[12], m[13], m[14]]; }
        if (scenePathLook()) return scenePathLook().eye;
        var eye = numbers((description.camera || {}).eye, 3, 0);
        return (description.camera || {}).eye ? eye : [0, 0, 1];
      }
      return [sceneWidth / 2, sceneHeight / 2, Math.max(sceneWidth, sceneHeight) * 4];
    }
    function activeCamera() {
      for (var index = things.length - 1; index >= 0; index--) {
        if (things[index].isCamera && showsAll(things[index])) return things[index];
      }
      return null;
    }
    function scenePathLook() {
      if (scenePaths === undefined) {
        scenePaths = [];
        var named = (description.camera || {}).paths;
        (Array.isArray(named) ? named : []).forEach(function (name) {
          var said;
          try { said = JSON.parse(files[key(String(name))]); } catch (error) { return; }
          (said && Array.isArray(said.paths) ? said.paths : []).forEach(function (path) {
            var keys = (Array.isArray(path && path.transforms) ? path.transforms : []).map(function (each) {
              return { at: number(each.timestamp, 0), eye: numbers(each.eye, 3, 0), center: numbers(each.center, 3, 0),
                       up: numbers(each.up, 3, 0), zoom: number(each.zoom, 1) };
            }).sort(function (a, b) { return a.at - b.at; });
            var seconds = number(path.duration, keys.length ? keys[keys.length - 1].at : 0);
            if (keys.length && seconds > 0) scenePaths.push({ keys: keys, seconds: seconds });
          });
        });
      }
      if (!scenePaths.length) return null;
      if (scenePaths.frame === frames) return scenePaths.look;
      var total = scenePaths.reduce(function (sum, path) { return sum + path.seconds; }, 0);
      var into = ((time % total) + total) % total, path = scenePaths[0];
      for (var index = 0; index < scenePaths.length; index++) {
        path = scenePaths[index];
        if (into < path.seconds || index === scenePaths.length - 1) break;
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
      scenePaths.frame = frames;
      scenePaths.look = { eye: mix(before.eye, after.eye), center: mix(before.center, after.center), up: up,
                          zoom: before.zoom + (after.zoom - before.zoom) * share };
      return scenePaths.look;
    }
    function pathLook(shot) {
      if (!shot || !shot.paths) return null;
      if (shot.pathFrame === frames && shot.pathLook) return shot.pathLook;
      var play = shot.pathPlay;
      if (!play || time < play.from) play = shot.pathPlay = { index: nextPath(shot, -1), from: time };
      for (var guard = 0; guard < 256; guard++) {
        var playing = shot.paths[play.index];
        if (!playing.ends || !(playing.seconds > 0) || time - play.from < playing.seconds) break;
        play.from += playing.seconds;
        play.index = nextPath(shot, play.index);
        play.changed = true;
      }
      var path = shot.paths[play.index], into = time - play.from;
      var eye = path.eye(into, [0, 0, 0]), center = path.center(into, [0, 0, -1]);
      var up = path.up ? path.up(into, [0, 1, 0]) : [0, 1, 0];
      if (!(up[0] || up[1] || up[2])) up = [0, 1, 0];
      var dark = 0;
      if (shot.paths.length > 1 && flag(general.camerafade, true)) {
        if (path.ends && path.seconds > 0) dark = Math.max(dark, 1 - (path.seconds - into) / PATH_FADE);
        if (play.changed) dark = Math.max(dark, 1 - into / PATH_FADE);
      }
      shot.pathFrame = frames;
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
      var own = m4invert(seen);
      var parent = shot.parent !== undefined ? byId[String(shot.parent)] : null;
      return parent && parent !== shot ? m4mul(standing(parent, true).matrix, own) : own;
    }
    function view() {
      if (viewOnce.frame === frames) return viewOnce;
      // While the scene is being made, before scripts can move the camera, there is no frame yet.
      var moved = camera || { x: 0, y: 0, zoom: 1 };
      var x = moved.x, y = moved.y, zoom = moved.zoom * Math.max(0.01, number(general.zoom, 1)), fov = 0;
      for (var index = things.length - 1; index >= 0; index--) {
        var shot = things[index];
        if (!shot.isCamera || !showsAll(shot)) continue;
        var at = shot.state.origin || [0, 0, 0];
        x += at[0];
        y += at[1];
        zoom *= Math.max(0.01, number((shot.state.zoom || [1])[0], 1));
        fov = number(plain(shot.said.fov), 0);
        break;
      }
      viewOnce = { frame: frames, x: x, y: y, zoom: zoom, fov: fov };
      return viewOnce;
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
      var matrix = matrixOf(state.origin, state.angles, state.scale);
      var alpha = Math.max(0, Math.min(1, state.alpha[0]));
      var above = true;
      var parent = thing.parent !== undefined && (depth || 0) < 64 ? byId[String(thing.parent)] : null;
      if (parent && parent !== thing) {
        var up = standing(parent, whole, (depth || 0) + 1);
        above = up.visible;
        // One that hangs on a point of a picture that bends — a head — goes where the point
        // is, and is placed from there.
        var name = thing.said ? plain(thing.said.attachment) : null;
        var point = typeof name === 'string' && name && parent.puppet && parent.puppet.attachment ? parent.puppet.attachment(name) : null;
        if (point) matrix = times([point[0], point[1], 0, 0, point[2], point[3], 0, 0, 0, 0, 1, 0, point[4], point[5], 0, 1], matrix);
        // One that hangs on a point of a model in three dimensions — a bone the model's
        // animation moves — goes with that bone.
        var held = !point && typeof name === 'string' && name && parent.attachmentMatrix ? parent.attachmentMatrix(name) : null;
        if (held) matrix = m4mul(held, matrix);
        // Drawn into the layer that holds it, an object is placed in that layer's own
        // coordinates; the layer's place is added when the layer is drawn.
        if (!parent.holds || whole) {
          // An object the scene gives no place stands, for what hangs on it, where Wallpaper
          // Engine puts it: at the scene's corner, not in its middle, where it is drawn — a
          // layer over the whole screen, say, whose pictures are placed by the scene's pixels.
          var base = up.matrix;
          if (!inDepth && parent.parent === undefined && !isSet(parent.said && parent.said.origin)) {
            base = base.slice();
            base[12] -= sceneWidth / 2;
            base[13] -= sceneHeight / 2;
          }
          matrix = times(base, matrix);
        }
      } else {
        // One anchored to a side of the screen keeps to that side where the screen shows less
        // of the scene than there is: it moves with the edge the scene is cut at.
        var anchor = key(String((thing.own && thing.own.anchor !== undefined ? thing.own.anchor : plain((thing.said || {}).anchor)) || 'none'));
        if (anchor !== 'none' && anchor !== '') {
          var seen = seenPart();
          matrix[12] += /left/.test(anchor) ? seen.left : (/right/.test(anchor) ? seen.right - sceneWidth : (seen.left + seen.right - sceneWidth) / 2);
          matrix[13] += /bottom/.test(anchor) ? seen.bottom : (/top/.test(anchor) ? seen.top - sceneHeight : (seen.bottom + seen.top - sceneHeight) / 2);
        }
        if (!editorView.free && ((eye && eye.on) || (shake && shake.on))) {
          // What hangs together moves with the pointer together, and shakes with the camera.
          var moved = shifted(thing);
          // In a scene in three dimensions the shake moves the picture, not the world: see
          // `viewProjection`.
          matrix[12] += moved[0] + (shake && !inDepth ? shake.x : 0);
          matrix[13] += moved[1] + (shake && !inDepth ? shake.y : 0);
        }
        var seen = inDepth || editorView.free ? { x: 0, y: 0, zoom: 1 } : view();
        if (seen.x || seen.y || seen.zoom !== 1) {
          // Where the camera is: the scene seen from there, nearer or further.
          var cx = sceneWidth / 2, cy = sceneHeight / 2;
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
      var matrix = thing.shift ? nudged(stands.matrix, thing.shift[0], thing.shift[1]) : stands.matrix;
      var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
      if (Math.abs(area) < 1e-9) return null;
      var dx = x - matrix[12], dy = y - matrix[13];
      var own = [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area];
      return Math.abs(own[0]) <= thing.size[0] / 2 && Math.abs(own[1]) <= thing.size[1] / 2 ? own : null;
    }
    // What was drawn of an object once and kept no longer holds.
    function stale(thing) {
      dirty = true;
      if (thing.kept) {
        release(thing.kept);
        thing.kept = null;
      }
    }
    // Whether an object and all it hangs on are shown, without working out where they are.
    function showsAll(thing) {
      for (var depth = 0; thing && depth < 64; depth++) {
        if (thing.state.visible === false) return false;
        thing = thing.parent !== undefined ? byId[String(thing.parent)] : null;
      }
      return true;
    }
    function nextPath(shot, after) {
      var count = shot.paths.length;
      if (count < 2) return 0;
      if (shot.pathOrder !== 'random') return after < 0 ? 0 : (after + 1) % count;
      pathLuck = (pathLuck * 1103515245 + 12345) % 2147483648;
      var pick = pathLuck % (after < 0 ? count : count - 1);
      return after >= 0 && pick >= after ? pick + 1 : pick;
    }
    // Pictures: pictures.js.
    var byId, scriptedLook, scenePaths, PATH_FADE, viewOnce, pathLuck;
    var picturesPart = makePictures(ctx);
    var merged = picturesPart.merged, frameAt = picturesPart.frameAt, placed = picturesPart.placed, refresh = picturesPart.refresh, buildEffects = picturesPart.buildEffects, buildImage = picturesPart.buildImage;
    // Texts: texts.js.
    var textsPart = makeTexts(ctx);
    var buildText = textsPart.buildText, shifted = textsPart.shifted, drawImage = textsPart.drawImage, releaseRepeated = textsPart.releaseRepeated;
    // Particles: particles.js.
    var particlesPart = makeParticles(ctx);
    var mix = particlesPart.mix, color = particlesPart.color, buildParticles = particlesPart.buildParticles;
    // Sounds: sounds.js.
    var players;
    var soundsPart = makeSounds(ctx);
    var buildSound = soundsPart.buildSound;
    // How much an emitter that answers the sound makes, from nought to all its rate: Wallpaper
    // Engine's audio response, worked out as its own pulse effect does it, which makes nothing
    // while nothing plays. Its mode is none, the left channel, the right one or both; it hears
    // the mean of the bands from `start` to `end` of sixteen, bass first, eased from the lower
    // bound of how loud they are to the upper, raised to the exponent that keeps the quiet
    // from counting much. Null for one that does not answer it.
    function hearing(emitter) {
      var mode = number(plain(emitter.audioprocessingmode), 0);
      if (!(mode >= 1 && mode <= 3)) return null;
      listen();
      var bounds = numbers(plain(emitter.audioprocessingbounds), 2, 0);
      if (!isSet(emitter.audioprocessingbounds)) bounds = [0.8, 1];
      var exponent = number(plain(emitter.audioprocessingexponent), 2);
      var start = Math.max(0, Math.min(15, Math.round(number(plain(emitter.audioprocessingfrequencystart), 0))));
      var end = Math.max(start, Math.min(15, Math.round(number(plain(emitter.audioprocessingfrequencyend), 1))));
      return function () {
        if (!spectrum) return 0;
        var left = bands(16, false), right = bands(16, true), sum = 0;
        for (var band = start; band <= end; band++) {
          sum += mode === 1 ? left[band] : (mode === 2 ? right[band] : (left[band] + right[band]) / 2);
        }
        var level = sum / (end - start + 1);
        var eased = bounds[1] > bounds[0] ? smooth01(bounds[0], bounds[1], level) : (level >= bounds[0] ? 1 : 0);
        return Math.max(0, Math.min(1, Math.pow(eased, exponent)));
      };
    }
    // The sound the Mac plays, for the shaders and scripts that draw by it; asked for once one
    // of them wants it, and heard for as long as the canvas is on the page.
    function listen() {
      if (listening || typeof window.wallpaperRegisterAudioListener !== 'function') return;
      listening = true;
      var host = window.__wallaeroHost;
      if (host) host.owner = canvas;
      window.wallpaperRegisterAudioListener(function (levels) { spectrum = levels; });
      if (host) host.owner = null;
    }
    function isSet(value) {
      return value !== undefined && value !== null;
    }
    // Building: building.js.
    var all, scripted, listening;
    makeBuilding(ctx);
    // Changes made in the editor: editor.js.
    var changes, pristine, FOLLOWED;
    var editorPart = makeEditor(ctx);
    var hexOf = editorPart.hexOf, changeOf = editorPart.changeOf, amended = editorPart.amended, amendGeneral = editorPart.amendGeneral, skeleton = editorPart.skeleton, canonical = editorPart.canonical, follow = editorPart.follow, add = editorPart.add, settleIn = editorPart.settleIn, isMoving = editorPart.isMoving, isLively = editorPart.isLively;
    // Moving with the pointer: pointer-moves.js.
    var eye, shake, camera;
    var pointerMovesPart = makePointerMoves(ctx);
    var look = pointerMovesPart.look;
    // Glow: glow.js.
    var fillVertex;
    var glowPart = makeGlow(ctx);
    var glow = glowPart.glow;
    // Size: size.js.
    var sizePart = makeSize(ctx);
    var resize = sizePart.resize;
    // Drawing: drawing.js.
    var frames, asked, before, editions;
    var drawingPart = makeDrawing(ctx);
    var wake = drawingPart.wake, goOn = drawingPart.goOn, holdFilms = drawingPart.holdFilms;
    function seenPart() {
      if (seenOnce.frame === frames) return seenOnce;
      var box = canvas.getBoundingClientRect();
      var from = box.width > 0 && box.height > 0 ? sceneAt(box.left, box.bottom) : [0, 0];
      var to = box.width > 0 && box.height > 0 ? sceneAt(box.right, box.top) : [sceneWidth, sceneHeight];
      seenOnce = { frame: frames, left: Math.max(0, from[0]), bottom: Math.max(0, from[1]),
                   right: Math.min(sceneWidth, to[0]), top: Math.min(sceneHeight, to[1]) };
      return seenOnce;
    }
    // A point of the page as a point of the scene, and back. The scene counts from its bottom.
    function sceneAt(pageX, pageY) {
      var shown = shownAt();
      return [(pageX - shown.left) / shown.width * sceneWidth, (1 - (pageY - shown.top) / shown.height) * sceneHeight];
    }
    // Where the whole scene is on the page, in its pixels; parts of it may be cut off.
    function shownAt() {
      var box = canvas.getBoundingClientRect();
      var fit = canvas.style.objectFit || 'cover';
      var by = fit === 'contain' ? Math.min(box.width / sceneWidth, box.height / sceneHeight)
             : Math.max(box.width / sceneWidth, box.height / sceneHeight);
      var width = fit === 'fill' ? box.width : sceneWidth * by, height = fit === 'fill' ? box.height : sceneHeight * by;
      var kept = (canvas.style.objectPosition || '50% 50%').split(/\s+/).map(parseFloat);
      return { left: box.left + (box.width - width) * (isFinite(kept[0]) ? kept[0] : 50) / 100,
               top: box.top + (box.height - height) * (isFinite(kept[1]) ? kept[1] : 50) / 100, width: width, height: height };
    }
    // The mouse: mouse.js.
    var mice, seenOnce;
    var mousePart = makeMouse(ctx);
    var pageAt = mousePart.pageAt;
    // The graphics chip may take everything back — when the Mac is short of memory, or the
    // web engine's own helper starts anew. Then the scene is built again from the start.
    function lost(event) {
      event.preventDefault();
    }
    function restored() {
      if (!stopped) window.WallaeroEngine.play(canvas, scene, properties, changes);
    }
    canvas.addEventListener('webglcontextlost', lost);
    canvas.addEventListener('webglcontextrestored', restored);

    resize();
    // Every script made ready, in the scene's order, once the screen has its size.
    scripts.slice().forEach(function (script) {
      if (script.value) script.value.now = readyScript(script, script.value.now);
    });
    wake();

    var player = {
      // `again` when the same canvas is about to be drawn on anew: what it has is then kept.
      stop: function (again) {
        if (stopped) return;
        tellScripts('destroy');
        stopped = true;
        if (asked) cancelAnimationFrame(asked);
        Object.keys(mice).forEach(function (name) { window.removeEventListener(name, mice[name], true); });
        window.removeEventListener('resize', changed);
        canvas.removeEventListener('webglcontextlost', lost);
        canvas.removeEventListener('webglcontextrestored', restored);
        players.forEach(function (each) { each.stop(); });
        films.forEach(function (each) {
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
        editions++;
        var other = {};
        var any = false;
        Object.keys(settings || {}).forEach(function (name) {
          if (properties[name] === settings[name]) return;
          properties[name] = settings[name];
          other[name] = forScripts(settings[name]);
          any = true;
        });
        if (!any || stopped) return;
        clear = numbers(general.clearcolor, 3, 0);
        things.slice().forEach(function (thing) { refresh(thing, true); });
        tellScripts('applyUserProperties', other);
        changed();
      },
      // What was made of the scene, for whoever looks into why it shows as it does.
      // How many of the scene's pictures and videos have yet to come.
      loading: function () { return loading; },
      report: function () {
        return JSON.stringify({
          scene: sceneWidth + '×' + sceneHeight, drawn: canvas.width + '×' + canvas.height, frames: frames,
          seconds: Math.round(time * 10) / 10, moving: isMoving(), lively: isLively(), loading: loading,
          scripts: scripts.filter(function (script) { return script.made; }).length + ' of ' + scripts.length,
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
        if (!stopped) hearOfMedia(kind, event);
      },
      // What the editor has changed of the scene: what is now changed otherwise shows at once.
      // False when it cannot be shown without the scene being played anew.
      setChanges: function (next) {
        editions++;
        var text = JSON.stringify(next || {});
        if (stopped || text === JSON.stringify(changes)) return true;
        changes = JSON.parse(text);
        amendGeneral();
        var followed = things.slice().every(function (thing) {
          var original = isSet(thing.id) ? pristine.objects[String(thing.id)] : null;
          return !original || follow(thing, amended(original, changeOf(thing.id)));
        });
        changed();
        return followed;
      },
      // The scene as the editor now has it, its file written anew. What changed of the values
      // played as they change shows at once; false when anything else changed, which needs the
      // scene played anew from the new file.
      setDescription: function (text) {
        editions++;
        var next;
        try { next = JSON.parse(text); } catch (error) { return false; }
        if (stopped) return true;
        var nextObjects = Array.isArray(next && next.objects) ? next.objects : [];
        if (nextObjects.length !== pristine.order.length) return false;
        if (canonical(next.general || {}) !== canonical(pristine.general)) return false;
        for (var i = 0; i < nextObjects.length; i++) {
          var before = pristine.order[i] || {}, after = nextObjects[i] || {};
          if (String(before.id) !== String(after.id) || canonical(skeleton(before)) !== canonical(skeleton(after))) return false;
        }
        files['scene.json'] = text;
        pristine.order = nextObjects;
        nextObjects.forEach(function (object) {
          if (isSet(object.id)) pristine.objects[String(object.id)] = object;
        });
        var followed = things.slice().every(function (thing) {
          var object = isSet(thing.id) ? pristine.objects[String(thing.id)] : null;
          return !object || follow(thing, amended(object, changeOf(thing.id)));
        });
        changed();
        return followed;
      },
      // Has the animations show a moment, in seconds, whether they play or wait; with
      // nothing, they go on as they were.
      seek: function (seconds) {
        timelineAt = typeof seconds === 'number' && isFinite(seconds) ? seconds : null;
        things.slice().forEach(function (thing) { refresh(thing, true); });
        dirty = true;
        changed();
      },
      // The scene's moment, in seconds.
      time: function () { return time; },
      // What the scene's camera shows: of a flat scene the middle of what it shows, from
      // the scene's middle, and how near; of one in three dimensions where its eye is, what
      // it looks at, which way is up, and how wide it sees, up and down, in degrees; with
      // the camera object it is, if one, and whether that hangs on another.
      cameraView: function () {
        if (!inDepth) {
          var seen = view();
          return { depth: false, x: seen.x, y: seen.y, zoom: seen.zoom, width: sceneWidth, height: sceneHeight };
        }
        var look = cameraLook(), shot = activeCamera();
        var fov = (shot && number(plain(shot.state.fov ? shot.state.fov[0] : shot.said.fov), 0)) || number(general.perspectiveoverridefov, number(general.fov, 50));
        return { depth: true, eye: look.eye, center: look.center, up: look.up, fov: fov, scripted: !!scriptedLook,
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
        before = 0;
        dirty = true;
        wake();
      },
      // Goes on to a moment of the scene, a thirtieth at a time, as it would have played up
      // to it, and shows it. A moment gone by cannot be come back to: false then, and the
      // scene has to be played anew from its start.
      goTo: function (seconds) {
        if (!(typeof seconds === 'number' && isFinite(seconds)) || stopped) return false;
        if (seconds < time - 1e-6) return false;
        var since = realNow();
        while (time < seconds - 1e-6) {
          goOn(Math.min(1 / 30, seconds - time));
          // A scene too heavy to go on so quickly gets there in bigger steps; not in a test,
          // which must step the same each time.
          if (!testClock && realNow() - since > 2000) goOn(Math.max(0, seconds - time));
        }
        timelineAt = time;
        holdFilms();
        things.slice().forEach(function (thing) { refresh(thing, true); });
        dirty = true;
        changed();
        return true;
      },
      // The scene for the editor: its objects as the scene has them, without the editor's
      // changes, which the editor knows, and what of them can be changed.
      describe: function () {
        return {
          width: sceneWidth, height: sceneHeight,
          parallax: flag(pristine.general.cameraparallax, false), parallaxAmount: number(pristine.general.cameraparallaxamount, 0.5),
          bloom: flag(pristine.general.bloom, false), bloomStrength: number(pristine.general.bloomstrength, 2),
          objects: pristine.order.filter(function (object) { return numbered(object.id); }).map(describeObject)
        };
      },
      // The object of the scene at a point of the page: the topmost there that shows. Layers
      // that put an effect over all under them are passed over: they would be everywhere.
      hit: function (pageX, pageY) {
        var at = sceneAt(pageX, pageY);
        for (var i = objects.length - 1; i >= 0; i--) {
          var thing = objects[i];
          if (!thing.size || !isSet(thing.id) || !pristine.objects[String(thing.id)] || thing.takesScene || thing.holds) continue;
          var stands = standing(thing);
          if (stands.visible && stands.alpha > 0.01 && spot(thing, at[0], at[1])) return numbered(thing.id) ? Number(thing.id) : null;
        }
        return null;
      },
      // Where an object is on the page: its middle and, if it has a size, the corners of its
      // rectangle from the top left one round.
      outline: function (id) {
        var thing = byId[String(id)];
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
        var written = scriptLog;
        scriptLog = [];
        return { errors: scriptErrors, log: written };
      },
      // A picture given other bones and a mesh as it is edited, or none, before they are written.
      puppet: function (id, table, layers) {
        var thing = byId[String(id)];
        if (!thing) return false;
        var old = thing.puppet;
        thing.puppet = table ? buildPuppet(table, layers || [], thing.name, thing.backsCulled !== false, thing) : null;
        if (old) gl.deleteVertexArray(old.shape);
        if (thing.puppet) thing.moving = true;
        dirty = true;
        changed();
        return !table || !!thing.puppet;
      },
      // Bones held where the editor has them, each from its parent — place (2), turn, scale
      // (2), turns about x and y — or left to play again.
      holdPuppet: function (id, pose) {
        var thing = byId[String(id)];
        if (!thing || !thing.puppet) return false;
        thing.puppet.held = pose || null;
        thing.moving = true;
        dirty = true;
        changed();
        return true;
      },
      // Each bone of a picture as it stands, from the picture: six numbers to take a point of
      // it there.
      bones: function (id, atRest) {
        var thing = byId[String(id)];
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
        var thing = byId[String(id)];
        var parent = thing && isSet(thing.parent) ? byId[String(thing.parent)] : null;
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
      var scale = numbers(object.scale, 3, 1);
      var angles = numbers(object.angles, 3, 0);
      var result = {
        id: Number(object.id), kind: kind, parent: hangs && numbered(object.parent) ? Number(object.parent) : null,
        // Unnamed, an object goes by its file: "models/girl.json" is “girl”.
        name: String(plain(object.name) || file.replace(/^.*\//, '').replace(/\.[^.]*$/, '') || ''),
        isVisible: flag(object.visible, true), x: real(origin[0]), y: real(origin[1]), scaleX: real(scale[0], 1), scaleY: real(scale[1], 1),
        rotation: real(-angles[2] * 180 / Math.PI), opacity: real(number(object.alpha, 1) * 100, 100), color: hexOf(numbers(object.color, 3, 1)),
        steered: FOLLOWED.filter(function (name) { return changesByItself(object[name]); }),
        effects: (Array.isArray(object.effects) ? object.effects : []).map(describeEffect)
      };
      if (kind === 'text') {
        var text = plain(object.text);
        result.text = isSet(text) ? String(text) : '';
        result.fontSize = real(number(object.pointsize, 32), 32);
      }
      if (kind === 'sound') result.volume = real(number(object.volume, 1) * 100, 100);
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
        var own = ((json(step.material) || {}).passes || [])[0];
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

    return player;
  }
