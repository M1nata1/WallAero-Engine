  // ------------------------------------------------------------------ the player

  function play(canvas, scene, settings, startingChanges) {
    // --- What the parts made by factories share with play (generated) ---
    var ctx = {
      get CHANNELS() { return CHANNELS; }, set CHANNELS(value) { CHANNELS = value; },
      get FILL() { return FILL; }, set FILL(value) { FILL = value; },
      get FOLLOWED() { return FOLLOWED; }, set FOLLOWED(value) { FOLLOWED = value; },
      get IDENTITY() { return IDENTITY; }, set IDENTITY(value) { IDENTITY = value; },
      get MAX_LIGHTS() { return MAX_LIGHTS; }, set MAX_LIGHTS(value) { MAX_LIGHTS = value; },
      get MOVING() { return MOVING; }, set MOVING(value) { MOVING = value; },
      get PATH_FADE() { return PATH_FADE; }, set PATH_FADE(value) { PATH_FADE = value; },
      get acquire() { return acquire; },
      get activeCamera() { return activeCamera; },
      get add() { return add; },
      get all() { return all; }, set all(value) { all = value; },
      get also() { return also; },
      get amendGeneral() { return amendGeneral; },
      get amended() { return amended; },
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
      get canonical() { return canonical; },
      get canvas() { return canvas; },
      get changeOf() { return changeOf; },
      get changed() { return changed; },
      get changes() { return changes; }, set changes(value) { changes = value; },
      get chosenTexture() { return chosenTexture; },
      get clear() { return clear; }, set clear(value) { clear = value; },
      get clipMaskProgram() { return clipMaskProgram; }, set clipMaskProgram(value) { clipMaskProgram = value; },
      get clippedProgram() { return clippedProgram; }, set clippedProgram(value) { clippedProgram = value; },
      get color() { return color; },
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
      get follow() { return follow; },
      get forScripts() { return forScripts; },
      get forgetTargets() { return forgetTargets; },
      get frameAt() { return frameAt; },
      get frameTime() { return frameTime; }, set frameTime(value) { frameTime = value; },
      get frames() { return frames; }, set frames(value) { frames = value; },
      get freeLook() { return freeLook; },
      get general() { return general; },
      get gl() { return gl; },
      get glow() { return glow; },
      get goOn() { return goOn; },
      get grabProgram() { return grabProgram; }, set grabProgram(value) { grabProgram = value; },
      get hearOfMedia() { return hearOfMedia; },
      get hearing() { return hearing; },
      get hexOf() { return hexOf; },
      get holdFilms() { return holdFilms; },
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
      get lost() { return lost; },
      get m4invert() { return m4invert; },
      get m4mul() { return m4mul; },
      get materialPass() { return materialPass; },
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
      get pageAt() { return pageAt; },
      get passBuffer() { return passBuffer; }, set passBuffer(value) { passBuffer = value; },
      get passShape() { return passShape; }, set passShape(value) { passShape = value; },
      get pathLook() { return pathLook; },
      get pathLuck() { return pathLuck; }, set pathLuck(value) { pathLuck = value; },
      get pictures() { return pictures; },
      get placeOf() { return placeOf; },
      get placeProgram() { return placeProgram; }, set placeProgram(value) { placeProgram = value; },
      get placed() { return placed; },
      get player() { return player; }, set player(value) { player = value; },
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
      get restored() { return restored; },
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
      get skeleton() { return skeleton; },
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
    // --- Parts made at the start ---
    var pagePlacesPart = makePagePlaces(ctx);
    var seenPart = pagePlacesPart.seenPart, sceneAt = pagePlacesPart.sceneAt, shownAt = pagePlacesPart.shownAt;
    var hearingPart = makeHearing(ctx);
    var hearing = hearingPart.hearing, listen = hearingPart.listen, isSet = hearingPart.isSet;
    var liveValuesPart = makeLiveValues(ctx);
    var live = liveValuesPart.live;
    var IDENTITY, MOVING;
    var shaderValuesPart = makeShaderValues(ctx);
    var changed = shaderValuesPart.changed, bands = shaderValuesPart.bands, engineValue = shaderValuesPart.engineValue, setUniform = shaderValuesPart.setUniform;
    var surface, CHANNELS, FILL;
    var placingPart = makePlacing(ctx);
    var times = placingPart.times, matrixOf = placingPart.matrixOf, nudged = placingPart.nudged, placeOf = placingPart.placeOf, worldPlaceOf = placingPart.worldPlaceOf, put = placingPart.put;
    var cameraPart = makeCamera(ctx);
    var freeLook = cameraPart.freeLook, cameraLook = cameraPart.cameraLook, eyePlace = cameraPart.eyePlace, activeCamera = cameraPart.activeCamera, scenePathLook = cameraPart.scenePathLook, pathLook = cameraPart.pathLook, cameraMatrix = cameraPart.cameraMatrix, view = cameraPart.view, also = cameraPart.also, standing = cameraPart.standing, spot = cameraPart.spot, stale = cameraPart.stale, showsAll = cameraPart.showsAll, nextPath = cameraPart.nextPath;
    // --- end of parts made at the start ---
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
    // The global object the scene's scripts share is the scene's own: one played anew in the
    // editor starts without what the scripts had left there.
    SCRIPT_GLOBAL = Object.create(null);
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

    // The first pass of a material, by its name: what a picture, a model's part, a particle
    // system or a pass of an effect is drawn with. Null for a material not in the scene.
    function materialPass(name) {
      return ((json(String(name || '')) || {}).passes || [])[0] || null;
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
    var clear = numbers(general.clearcolor, 3, defaults.general.clearcolor);
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

    // What the shaders are told of the scene: shader-values.js, made at the start.

    // A pass of an effect: effects.js.
    var effectsPart = makeEffects(ctx);
    var buildPass = effectsPart.buildPass, withLooks = effectsPart.withLooks, drawPass = effectsPart.drawPass;
    // Values with a setting, an animation or a script behind them: live-values.js, made at the start.
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
    // Where things stand: placing.js, made at the start.
    // Pictures that bend: puppets.js.
    var puppetsPart = makePuppets(ctx);
    var numbersOf = puppetsPart.numbersOf, joined = puppetsPart.joined, undone = puppetsPart.undone, buildPuppet = puppetsPart.buildPuppet;
    // Models in three dimensions: models.js.
    var MAX_LIGHTS;
    var modelsPart = makeModels(ctx);
    var sceneLights = modelsPart.sceneLights, viewProjection = modelsPart.viewProjection, m4mul = modelsPart.m4mul, m4invert = modelsPart.m4invert, buildModel = modelsPart.buildModel, buildLight = modelsPart.buildLight;
    // The camera, and how each thing stands now: camera.js, made at the start.
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
    // What the scene hears: hearing.js, made at the start.
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
    // Where on the page the scene is: page-places.js, made at the start.
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

    // What the app asks of a scene playing: player-api.js.
    var player;
    makePlayerApi(ctx);
    return player;
  }
