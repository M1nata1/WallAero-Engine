  // ------------------------------------------------------------------ the player

  function play(canvas, scene, settings, startingChanges) {
    // --- What the parts made by factories share with play (generated) ---
    var ctx = {
      get CHANNELS() { return CHANNELS; },
      get FILL() { return FILL; },
      get FOLLOWED() { return FOLLOWED; }, set FOLLOWED(value) { FOLLOWED = value; },
      get MAX_LIGHTS() { return MAX_LIGHTS; }, set MAX_LIGHTS(value) { MAX_LIGHTS = value; },
      get acquire() { return acquire; },
      get activeCamera() { return activeCamera; },
      get all() { return all; }, set all(value) { all = value; },
      get also() { return also; },
      get audioBuffers() { return audioBuffers; },
      get bound() { return bound; },
      get buildEffects() { return buildEffects; },
      get buildImage() { return buildImage; },
      get buildLight() { return buildLight; },
      get buildModel() { return buildModel; },
      get buildParticles() { return buildParticles; },
      get buildSound() { return buildSound; },
      get buildText() { return buildText; },
      get byId() { return byId; },
      get cameraLook() { return cameraLook; },
      get cameraMatrix() { return cameraMatrix; },
      get changed() { return changed; },
      get changes() { return changes; }, set changes(value) { changes = value; },
      get compositeNamed() { return compositeNamed; },
      get depthOf() { return depthOf; },
      get description() { return description; },
      get dirty() { return dirty; }, set dirty(value) { dirty = value; },
      get drawPass() { return drawPass; },
      get eye() { return eye; },
      get eyePlace() { return eyePlace; },
      get files() { return files; },
      get fillVertex() { return fillVertex; },
      get films() { return films; },
      get flat() { return flat; },
      get frameAt() { return frameAt; },
      get frames() { return frames; }, set frames(value) { frames = value; },
      get freeLook() { return freeLook; },
      get general() { return general; },
      get gl() { return gl; },
      get grabProgram() { return grabProgram; },
      get hearing() { return hearing; },
      get inDepth() { return inDepth; },
      get isSet() { return isSet; },
      get json() { return json; },
      get link() { return link; },
      get live() { return live; },
      get loading() { return loading; }, set loading(value) { loading = value; },
      get looksOf() { return looksOf; },
      get m4invert() { return m4invert; },
      get matrixOf() { return matrixOf; },
      get merged() { return merged; },
      get mix() { return mix; },
      get newTexture() { return newTexture; },
      get nudged() { return nudged; },
      get numbersOf() { return numbersOf; },
      get objects() { return objects; },
      get passBuffer() { return passBuffer; },
      get passShape() { return passShape; },
      get pathLook() { return pathLook; },
      get placeOf() { return placeOf; },
      get placed() { return placed; },
      get players() { return players; }, set players(value) { players = value; },
      get pointer() { return pointer; }, set pointer(value) { pointer = value; },
      get pointerSeen() { return pointerSeen; }, set pointerSeen(value) { pointerSeen = value; },
      get pristine() { return pristine; }, set pristine(value) { pristine = value; },
      get puppets() { return puppets; },
      get put() { return put; },
      get release() { return release; },
      get same() { return same; },
      get scale() { return scale; }, set scale(value) { scale = value; },
      get scene() { return scene; },
      get sceneHeight() { return sceneHeight; }, set sceneHeight(value) { sceneHeight = value; },
      get sceneLights() { return sceneLights; },
      get scenePathLook() { return scenePathLook; },
      get sceneTarget() { return sceneTarget; }, set sceneTarget(value) { sceneTarget = value; },
      get sceneVersion() { return sceneVersion; },
      get sceneWidth() { return sceneWidth; }, set sceneWidth(value) { sceneWidth = value; },
      get scripted() { return scripted; },
      get scriptedLook() { return scriptedLook; }, set scriptedLook(value) { scriptedLook = value; },
      get scripts() { return scripts; }, set scripts(value) { scripts = value; },
      get shake() { return shake; },
      get sheetFrames() { return sheetFrames; },
      get sheetTime() { return sheetTime; },
      get soundFiles() { return soundFiles; },
      get stale() { return stale; },
      get standing() { return standing; },
      get startingChanges() { return startingChanges; },
      get stopped() { return stopped; }, set stopped(value) { stopped = value; },
      get straightProgram() { return straightProgram; },
      get surface() { return surface; }, set surface(value) { surface = value; },
      get texture() { return texture; },
      get time() { return time; }, set time(value) { time = value; },
      get timelineAt() { return timelineAt; }, set timelineAt(value) { timelineAt = value; },
      get timers() { return timers; }, set timers(value) { timers = value; },
      get times() { return times; },
      get unplaced() { return unplaced; },
      get viewProjection() { return viewProjection; },
      get withLooks() { return withLooks; },
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

    // --- Programs ---------------------------------------------------------

    // What the compiler last complained of, when it was asked not to say so itself.
    var complaint = null;

    function compile(type, source, what, quietly) {
      var shader = gl.createShader(type);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        var problem = (gl.getShaderInfoLog(shader) || '').split('\n')[0];
        // The line the compiler names, to make the reason readable.
        var line = /ERROR: \d+:(\d+)/.exec(problem);
        var text = line ? (source.split('\n')[Number(line[1]) - 1] || '').trim() : '';
        var said = what + ' does not compile: ' + problem.replace(/^ERROR: \d+:\d+: /, '') + (text ? ' — in “' + text.slice(0, 80) + '”' : '');
        // Everything it says of that line: the first complaint is not always the telling one.
        var ofLine = (gl.getShaderInfoLog(shader) || '').split('\n').filter(function (each) {
          var named = /ERROR: \d+:(\d+)/.exec(each);
          return named && line && named[1] === line[1];
        });
        complaint = { stage: type === gl.VERTEX_SHADER ? 'vertex' : 'fragment', messages: ofLine, line: line ? Number(line[1]) : 0, said: said };
        if (!quietly) note(said);
        gl.deleteShader(shader);
        return null;
      }
      return shader;
    }

    // A program with what it takes: its uniforms by name, with their kinds.
    function link(vertexSource, fragmentSource, what, quietly) {
      complaint = null;
      var vertex = compile(gl.VERTEX_SHADER, vertexSource, what + ' (vertex)', quietly);
      var fragment = vertex && compile(gl.FRAGMENT_SHADER, fragmentSource, what + ' (fragment)', quietly);
      if (!vertex || !fragment) return null;
      var program = gl.createProgram();
      gl.attachShader(program, vertex);
      gl.attachShader(program, fragment);
      // The same places in every program, so that one shape serves them all.
      ['a_Position', 'a_TexCoord', 'a_Place', 'a_Color', 'a_Frame', 'a_Spot', 'a_Uv', 'a_More', 'a_Normal', 'a_Bones', 'a_Weights'].forEach(function (name, index) {
        gl.bindAttribLocation(program, index, name);
      });
      gl.linkProgram(program);
      gl.deleteShader(vertex);
      gl.deleteShader(fragment);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        var refused = (gl.getProgramInfoLog(program) || '').split('\n').filter(Boolean);
        complaint = { stage: 'both', messages: refused, line: 0, said: what + ' does not link: ' + (refused[0] || '') };
        if (!quietly) note(complaint.said);
        gl.deleteProgram(program);
        return null;
      }
      var uniforms = {};
      var count = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
      for (var i = 0; i < count; i++) {
        var info = gl.getActiveUniform(program, i);
        var name = info.name.replace(/\[0\]$/, '');
        uniforms[name] = { location: gl.getUniformLocation(program, info.name), type: info.type, size: info.size };
      }
      return { program: program, uniforms: uniforms };
    }

    // --- Shapes -----------------------------------------------------------

    // The rectangle every pass of an effect is drawn as: the corners of the screen, each with
    // the corner of the picture that belongs there, the top left one first.
    var passShape = gl.createVertexArray();
    gl.bindVertexArray(passShape);
    var passBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, passBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
      -1, 1, 0, 0, 0,
      1, 1, 0, 1, 0,
      -1, -1, 0, 0, 1,
      1, -1, 0, 1, 1
    ]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 20, 0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 20, 12);
    gl.bindVertexArray(null);

    // --- Textures ---------------------------------------------------------

    var loading = 0;       // pictures still on their way
    var textureCache = {};

    // The finished picture of a layer — what it shows after its effects — as others take it
    // by name, `_rt_imageLayerComposite_<id>_a`: a planet's surface, a picture in a frame. It
    // stands empty until the layer is first drawn; the layer then keeps it up to date.
    var composites = {};
    function compositeNamed(name) {
      var made = /_rt_imagelayercomposite_(\d+)_[ab]$/.exec(key(name));
      if (!made) return null;
      if (!composites[made[1]]) {
        var empty = flat(0, 0, 0, 0);
        composites[made[1]] = { layers: [empty.layers[0]], width: 1, height: 1, channels: 'rgba', ready: true };
      }
      return composites[made[1]];
    }

    function newTexture(clamp, smooth) {
      var texture = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, clamp ? gl.CLAMP_TO_EDGE : gl.REPEAT);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, clamp ? gl.CLAMP_TO_EDGE : gl.REPEAT);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
      // How it is read, kept with it: see `bound`.
      texture.looks = { wrapS: clamp ? gl.CLAMP_TO_EDGE : gl.REPEAT, wrapT: clamp ? gl.CLAMP_TO_EDGE : gl.REPEAT, smooth: !!smooth };
      return texture;
    }

    // How a texture is read: as it was made, or, for one not made here, as the context says,
    // once.
    function looksOf(texture) {
      if (!texture.looks) {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        texture.looks = { wrapS: gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S), wrapT: gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T),
                          smooth: gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER) !== gl.NEAREST };
      }
      return texture.looks;
    }

    // `grainy`: looked at as it is wherever it is shown small — noise that is averaged out
    // is no noise.
    // The frames of a sheet as parts of the picture, x, y, width and height from 0 to 1 with
    // the top first; null if the picture is not a sheet.
    function sheetFrames(picture) {
      if (!picture || !picture.frames || !picture.frames.length || !(picture.width > 0 && picture.height > 0)) return null;
      if (picture.cells) return picture.cells;
      picture.cells = picture.frames.map(function (frame) {
        return [frame[2] / picture.width, frame[3] / picture.height, frame[4] / picture.width, frame[7] / picture.height];
      });
      return picture.cells;
    }

    // One of Wallpaper Engine's own pictures, drawn anew (`builtinPicture`), as a texture.
    function fromBuiltin(made) {
      var texture = newTexture(made.clamp, true);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, made.width, made.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, made.pixels);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      return { layers: [{ texture: texture, width: made.width, height: made.height }], width: made.width, height: made.height,
               channels: 'rgba', frames: made.frames || null, ready: true, made: true, builtin: true };
    }

    function fromPixels(pixels, size, clamp, grainy) {
      var texture = newTexture(clamp, true);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, size, size, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(pixels.buffer || pixels));
      if (size > 1 && !grainy) {
        gl.generateMipmap(gl.TEXTURE_2D);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      }
      return { layers: [{ texture: texture, width: size, height: size }], width: size, height: size,
               channels: 'rgba', frames: null, ready: true };
    }

    function flat(red, green, blue, alpha) {
      return fromPixels(new Uint8Array([red, green, blue, alpha]), 1, false);
    }

    // The cover of the music that plays, and of what played before it: see-through until
    // there is one. What shows them is drawn anew when they change, as for a video.
    function blankCover() {
      var picture = flat(0, 0, 0, 0);
      picture.film = { users: [] };
      return picture;
    }
    var covers = { now: blankCover(), before: blankCover(), shown: '' };

    var films = [];   // the textures that are videos, each with the video it shows

    // A texture that is a video. It plays by itself, over and over and without sound, at the
    // speed the app plays the wallpaper at; every frame of it goes into the texture as it comes.
    function film(entry) {
      var layer = { texture: newTexture(entry.clamp !== false, entry.smooth !== false),
                    width: number(entry.width, 0) || 1, height: number(entry.height, 0) || 1 };
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
      var result = { layers: [layer], width: layer.width, height: layer.height, channels: 'rgba', frames: null, ready: false };
      var video = document.createElement('video');
      video.muted = true;
      video.defaultMuted = true;
      video.loop = true;
      video.playsInline = true;
      video.preload = 'auto';
      video.style.display = 'none';
      // Whatever sound it has is not the wallpaper's.
      video.wallaeroShare = 0;
      var waited = true;
      function settled() {
        if (!waited) return;
        waited = false;
        loading--;
        changed();
      }
      loading++;
      video.addEventListener('loadeddata', settled);
      video.addEventListener('error', function () {
        if (waited) note('the video ' + entry.video + ' cannot be played; nothing shows in its place');
        result.ready = true;
        settled();
      });
      video.src = encodeURI(entry.video);
      document.body.appendChild(video);
      var host = window.__wallaeroHost;
      if (host && host.autoplay) {
        host.autoplay(video);
      } else {
        var started = video.play();
        if (started && started['catch']) started['catch'](function () {});
      }
      // `users` are the objects that show it: what is kept of them is no longer good when the
      // video has moved on.
      result.film = { video: video, layer: layer, picture: result, shown: -1, users: [], seen: false };
      films.push(result.film);
      // A video says it is ready before it has a picture to give — a large one by seconds —
      // and what is taken from it meanwhile is black. So nothing is taken until the web engine
      // has shown a frame of it; where it cannot say so, or does not, the wait is by the clock.
      function seen() {
        if (result.film.seen) return;
        result.film.seen = true;
        changed();
      }
      if (typeof video.requestVideoFrameCallback === 'function') video.requestVideoFrameCallback(seen);
      video.addEventListener('loadeddata', function () {
        setTimeout(seen, typeof video.requestVideoFrameCallback === 'function' ? 6000 : 300);
      });
      return result;
    }

    // Notes that an object shows a picture, which matters if the picture is a video.
    function shows(thing, picture) {
      if (picture && picture.film && picture.film.users.indexOf(thing) < 0) picture.film.users.push(thing);
      return picture;
    }

    // Puts the frames the videos have come to into their textures; true if any was new.
    function showFilms() {
      var any = false;
      films.forEach(function (each) {
        var video = each.video;
        if (!each.seen || video.readyState < 2 || video.currentTime === each.shown || !video.videoWidth) return;
        // Back at its start: it came to its end.
        if (each.ended && each.shown > 0 && video.currentTime < each.shown - 0.25) {
          each.ended.slice().forEach(function (callback) {
            try { callback(); } catch (error) { note('a script fails in what it asked for at the end of a video: ' + error.message); }
          });
        }
        each.shown = video.currentTime;
        gl.bindTexture(gl.TEXTURE_2D, each.layer.texture);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);
        each.picture.ready = true;
        each.users.forEach(stale);
        any = true;
      });
      return any;
    }

    // A slot of a material may be left to a setting of the wallpaper: a picture the user is
    // to choose. The name of the texture that came for it, if one did.
    function chosenTexture(bound) {
      // A slot Wallpaper Engine fills itself has the cover of the music that plays, or of what
      // played before it; the picture the scene keeps there is for its author to look at while
      // making it.
      if (bound && typeof bound === 'object' && bound.type === 'system' && /^\$media/i.test(String(bound.name))) {
        return /previous/i.test(String(bound.name)) ? '$mediapreviousthumbnail' : '$mediathumbnail';
      }
      var name = typeof bound === 'string' ? bound : (bound && typeof bound === 'object' && bound.type !== 'system' ? bound.name : null);
      return typeof name === 'string' && pictures['user/' + key(name)] ? 'user/' + key(name) : null;
    }

    // A texture by the name a material gives it: one of the scene's own, or one made here.
    // The scene's own arrive later; until then the texture is see-through.
    function texture(name) {
      var id = key(name);
      if (id === '$mediathumbnail') return covers.now;
      if (id === '$mediapreviousthumbnail') return covers.before;
      if (compositeNamed(id)) return compositeNamed(id);
      if (textureCache[id]) return textureCache[id];
      var entry = pictures[id] || pictures['materials/' + id];
      var result, builtin;
      if (entry && entry.video) {
        result = film(entry);
      } else if (entry && entry.pictures && entry.pictures.length) {
        result = { layers: [], width: entry.pictures[0].width, height: entry.pictures[0].height,
                   channels: entry.channels || 'rgba', frames: entry.frames || null, maps: number(entry.maps, 0), compressed: !!entry.compressed, ready: false };
        var waiting = entry.pictures.length;
        entry.pictures.forEach(function (picture, index) {
          var layer = { texture: newTexture(entry.clamp !== false, entry.smooth !== false), width: picture.width, height: picture.height };
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
          result.layers[index] = layer;
          var image = new Image();
          loading++;
          image.onload = function () {
            loading--;
            if (stopped) return;
            gl.bindTexture(gl.TEXTURE_2D, layer.texture);
            gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
            gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
            gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
            if (entry.smooth !== false) {
              gl.generateMipmap(gl.TEXTURE_2D);
              gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
            }
            if (--waiting === 0) result.ready = true;
            changed();
          };
          image.onerror = function () {
            loading--;
            note('the picture ' + picture.file + ' cannot be loaded');
            if (--waiting === 0) result.ready = true;
            changed();
          };
          image.src = encodeURI(picture.file);
        });
      } else if ((builtin = builtinPicture(id))) {
        result = fromBuiltin(builtin);
      } else if (/(^|\/)util\/white$/.test(id)) {
        result = flat(255, 255, 255, 255);
      } else if (/(^|\/)util\/black$/.test(id)) {
        result = flat(0, 0, 0, 255);
      } else if (/(^|\/)util\/nothing$/.test(id)) {
        result = flat(0, 0, 0, 0);
      } else if (/(^|\/)util\/noflow$/.test(id)) {
        // The middle value of a map of directions: no direction at all.
        result = flat(127, 127, 0, 255);
      } else if (/(^|\/)util\/normal/.test(id)) {
        result = flat(128, 128, 255, 255);
      } else if (/(^|\/)util\/.*(cloud|perlin)/.test(id)) {
        result = fromPixels(cloudsPixels(256), 256, false);
      } else if (/(^|\/)util\/.*(noise|uniform)/.test(id)) {
        result = fromPixels(noisePixels(256), 256, false, true);
      } else if (/(^|\/)gradient\/blend_gradient/.test(id)) {
        // The masks an effect is faded in by from one side: taken to run down the picture,
        // from nothing at the top — by a scene whose screen darkens toward its bottom with it.
        result = fromPixels(rampPixels(256, false, /reverse/.test(id)), 256, true);
      } else if (/(^|\/)gradient\/.*iridescent/.test(id)) {
        result = fromPixels(rainbowPixels(256), 256, false);
      } else if (/(^|\/)gradient\//.test(id)) {
        note('the gradient ' + name + ' is not in the scene; one from black to white stands in for it');
        result = fromPixels(rampPixels(256, true, false), 256, true);
      } else if (/(^|\/)pattern\/voronoi/.test(id)) {
        result = fromPixels(cellsPixels(256, !/local/.test(id)), 256, false);
      } else if (/(^|\/)particle\//.test(id)) {
        result = fromPixels(spritePixels(id, 128), 128, true);
        result.made = true;
        // The drop drawn takes part of its square; a clear drop bends the light within it.
        if (isDropSheet(id)) result.fill = DROP_FILL;
      } else {
        note('the texture ' + name + ' is not in the scene; white stands in for it');
        result = flat(255, 255, 255, 255);
      }
      textureCache[id] = result;
      return result;
    }

    // --- Pictures to draw into --------------------------------------------

    var targets = {};   // those not in use, by size

    function acquire(width, height) {
      width = Math.max(1, Math.round(width));
      height = Math.max(1, Math.round(height));
      var id = width + 'x' + height;
      var free = targets[id];
      if (free && free.length) return free.pop();
      var texture = newTexture(true, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      var framebuffer = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
      return { id: id, framebuffer: framebuffer, texture: texture, width: width, height: height };
    }

    function release(target) {
      if (!target) return;
      // One made to repeat goes back as the others are, ending at its edges.
      if (target.repeats) {
        target.repeats = false;
        gl.bindTexture(gl.TEXTURE_2D, target.texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        target.texture.looks = { wrapS: gl.CLAMP_TO_EDGE, wrapT: gl.CLAMP_TO_EDGE, smooth: looksOf(target.texture).smooth };
      }
      (targets[target.id] = targets[target.id] || []).push(target);
    }

    // What a target needs for objects in three dimensions: how near what was drawn on each of
    // its pixels is, so that what is behind is hidden. Made when first needed, and cleared
    // once a frame, before the first such object is drawn on it.
    function depthOf(target) {
      if (!target.depth) {
        target.depth = gl.createRenderbuffer();
        gl.bindRenderbuffer(gl.RENDERBUFFER, target.depth);
        gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, target.width, target.height);
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
        gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, target.depth);
      }
      if (target.depthCleared !== frames) {
        target.depthCleared = frames;
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
        gl.depthMask(true);
        gl.clear(gl.DEPTH_BUFFER_BIT);
      }
    }

    function forgetTargets() {
      Object.keys(targets).forEach(function (id) {
        targets[id].forEach(function (target) {
          if (target.depth) gl.deleteRenderbuffer(target.depth);
          gl.deleteFramebuffer(target.framebuffer);
          gl.deleteTexture(target.texture);
        });
      });
      targets = {};
    }

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

    // --- A pass of an effect ---------------------------------------------

    // Makes a pass ready to draw: its shader translated with the effect's switches, and for
    // every uniform where its value comes from. Null if the shader is not there or will not
    // compile; the effect is then left out.
    // A value a shader's two halves both take, but each of a kind of its own — a pair of
    // numbers to one, a number to the other (3660962877's frame builder, “Reference
    // resolution”): Direct3D gives each half its own, GLSL will not link them. The fragment
    // shader's is named apart, its description kept, and each is given the setting as its
    // kind takes it.
    function ownUniforms(vertex, fragment) {
      var declared = /^[ \t]*uniform[ \t]+(?:(?:highp|mediump|lowp)[ \t]+)?(\w+)[ \t]+(\w+)[ \t]*(?:\[|;)/gm;
      var kinds = {}, found;
      while ((found = declared.exec(vertex))) kinds[found[2]] = found[1];
      var clashing = [];
      declared.lastIndex = 0;
      while ((found = declared.exec(fragment))) {
        if (kinds[found[2]] && kinds[found[2]] !== found[1] && clashing.indexOf(found[2]) < 0) clashing.push(found[2]);
      }
      clashing.forEach(function (name) {
        fragment = fragment.replace(new RegExp('\\b' + name + '\\b', 'g'), name + '_wallaeroFragment');
      });
      return fragment;
    }

    function buildPass(shaderName, combos, constants, slotTextures, what, owner) {
      var vertexSource = files['shaders/' + key(shaderName) + '.vert'];
      var fragmentSource = files['shaders/' + key(shaderName) + '.frag'];
      if (typeof vertexSource !== 'string' || typeof fragmentSource !== 'string') {
        note(what + ': the shader ' + shaderName + ' is not in the scene');
        return null;
      }
      fragmentSource = ownUniforms(vertexSource, fragmentSource);
      var said = annotations(vertexSource + '\n' + fragmentSource + '\n' + headersOf(vertexSource + '\n' + fragmentSource, files));
      var defines = {};
      Object.keys(said.combos).forEach(function (name) { defines[name] = said.combos[name]; });
      Object.keys(combos || {}).forEach(function (name) { defines[name] = number(combos[name], 0); });
      // A texture slot may come with a switch of its own, on when a texture is put there.
      var defaults = [];
      Object.keys(said.uniforms).forEach(function (name) {
        var slot = /^g_Texture(\d)$/.exec(name);
        if (!slot) return;
        var about = said.uniforms[name];
        defaults[Number(slot[1])] = about['default'];
        if (about.combo && slotTextures[Number(slot[1])]) defines[about.combo] = 1;
      });
      var program = null;
      try {
        var sources = { vertex: translate(vertexSource, 'vertex', defines, files), fragment: translate(fragmentSource, 'fragment', defines, files) };
        // A shader the compiler refuses is mended by what it said and tried again, a few times.
        for (var attempt = 0; attempt < 24 && !program; attempt++) {
          program = link(sources.vertex, sources.fragment, what, true);
          if (program || !complaint) break;
          if (complaint.stage === 'both') {
            // The two shaders do not fit each other.
            var pair = mendPair(sources.vertex, sources.fragment, complaint.messages);
            if (pair === null) {
              note(complaint.said);
              break;
            }
            sources = pair;
            continue;
          }
          var mended = mend(sources[complaint.stage], complaint.messages, complaint.line);
          if (mended === null) {
            note(complaint.said);
            break;
          }
          sources[complaint.stage] = mended;
        }
      } catch (error) {
        note(what + ': ' + error.message);
        return null;
      }
      if (!program) return null;
      var pass = { program: program, moving: false, values: [], lives: [], slots: [], defaults: defaults };
      Object.keys(program.uniforms).forEach(function (name) {
        var uniform = program.uniforms[name];
        var slot = /^g_Texture(\d)$/.exec(name);
        if (slot && uniform.type === gl.SAMPLER_2D) {
          pass.slots.push(Number(slot[1]));
          gl.useProgram(program.program);
          gl.uniform1i(uniform.location, Number(slot[1]));
          return;
        }
        if (MOVING.test(name)) pass.moving = true;
        // A shader that draws by the sound has the sound listened to.
        if (/^g_AudioSpectrum/.test(name)) listen();
        var about = said.uniforms[name];
        var value = { name: name, uniform: uniform, live: null, material: about ? about.material : undefined };
        if (about) {
          // What the scene sets the effect to, else what the shader says it starts with. A
          // setting of the wallpaper, an animation or a script may stand behind it.
          var given = about.material !== undefined && constants ? constants[about.material] : undefined;
          var count = uniform.type === gl.FLOAT ? Math.max(1, uniform.size)
                    : (uniform.type === gl.FLOAT_VEC2 ? 2 : (uniform.type === gl.FLOAT_VEC3 ? 3 : (uniform.type === gl.FLOAT_VEC4 ? 4 : 1)));
          value.live = live(given !== undefined ? given : about['default'], count, 0, owner);
          value.fallback = about['default'];
          if (value.live.changes) pass.moving = true;
          if (given && typeof given === 'object' && !Array.isArray(given)) pass.lives.push(value.live);
        }
        pass.values.push(value);
      });
      return pass;
    }

    // Draws a pass into `target` (null for none: the caller has one bound already).
    // `inputs` are the textures by slot: { texture, resolution }.
    // `layer` is the object the pass belongs to and `onScreen` where its rectangle lands on what
    // is drawn on, for the shaders that ask.
    // An effect reads its pictures without their smaller copies: it is drawn at the size of its
    // layer, where they are not needed, and a shader that wraps the picture round — `frac` of
    // where it reads, to scroll it — would otherwise have the smallest of them show as a line
    // where it wraps. How each picture repeats and how smooth it is stay as they are.
    var plainSamplers = {};
    function plainSampler(texture) {
      var looks = looksOf(texture);
      var wrapS = looks.wrapS, wrapT = looks.wrapT, smooth = looks.smooth;
      var name = wrapS + ',' + wrapT + ',' + smooth;
      if (!plainSamplers[name]) {
        var sampler = gl.createSampler();
        gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_S, wrapS);
        gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_T, wrapT);
        gl.samplerParameteri(sampler, gl.TEXTURE_MAG_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
        gl.samplerParameteri(sampler, gl.TEXTURE_MIN_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
        plainSamplers[name] = sampler;
      }
      return plainSamplers[name];
    }

    // How a layer's picture is read where it is put on the scene, if the layer says: ending
    // at its edges rather than repeating (`clampuvs`), and its pixels kept square rather than
    // smoothed (`nointerpolation`). Otherwise as the picture itself says.
    var layerSamplers = {};
    function withLooks(source, layer) {
      var said = layer.said || {};
      var clamped = flag(said.clampuvs, false), square = flag(said.nointerpolation, false);
      if (!clamped && !square) return source;
      var looks = looksOf(source.texture);
      var wrapS = clamped ? gl.CLAMP_TO_EDGE : looks.wrapS;
      var wrapT = clamped ? gl.CLAMP_TO_EDGE : looks.wrapT;
      var smooth = !square && looks.smooth;
      var name = wrapS + ',' + wrapT + ',' + smooth;
      if (!layerSamplers[name]) {
        var sampler = gl.createSampler();
        gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_S, wrapS);
        gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_T, wrapT);
        gl.samplerParameteri(sampler, gl.TEXTURE_MAG_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
        gl.samplerParameteri(sampler, gl.TEXTURE_MIN_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
        layerSamplers[name] = sampler;
      }
      var looked = {};
      Object.keys(source).forEach(function (name) { looked[name] = source[name]; });
      looked.sampler = layerSamplers[name];
      return looked;
    }

    // `straight`, if given, draws the pass not into `target` but onto the scene, through the
    // layer's place in the world: { onto, place, how, tests }.
    function drawPass(pass, target, inputs, layer, onScreen, straight) {
      if (straight) {
        gl.bindFramebuffer(gl.FRAMEBUFFER, straight.onto.target.framebuffer);
        gl.viewport(0, 0, straight.onto.target.width, straight.onto.target.height);
        if (straight.how === 'normal') {
          gl.disable(gl.BLEND);
        } else {
          gl.enable(gl.BLEND);
          if (straight.how === 'additive') gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
          else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        }
        if (straight.tests) {
          gl.enable(gl.DEPTH_TEST);
          gl.depthFunc(gl.LEQUAL);
          gl.depthMask(false);
        }
      } else {
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
        gl.viewport(0, 0, target.width, target.height);
        gl.disable(gl.BLEND);
      }
      gl.useProgram(pass.program.program);
      var context = { width: target.nominalWidth || target.width, height: target.nominalHeight || target.height, resolutions: [] };
      pass.slots.forEach(function (slot) {
        var input = inputs[slot];
        gl.activeTexture(gl.TEXTURE0 + slot);
        gl.bindSampler(slot, input && input.texture ? plainSampler(input.texture) : null);
        gl.bindTexture(gl.TEXTURE_2D, input ? input.texture : null);
      });
      inputs.forEach(function (input, slot) {
        if (input) context.resolutions[slot] = input.resolution;
      });
      pass.values.forEach(function (value) {
        var uniform = value.uniform;
        if (value.name === 'wallaero_Flip') {
          // The place in the world already turns the scene's rows over.
          gl.uniform1f(uniform.location, straight ? 1 : -1);
        } else if (uniform.type === gl.FLOAT_MAT4) {
          // An effect is drawn onto its layer's own picture, which needs no placing; how the
          // layer itself stands on the scene — how large, how turned — a shader may ask.
          var asked = IDENTITY;
          if (value.name === 'g_ModelViewProjectionMatrix' && straight) {
            // The pass's corners, ±1, to the layer's, ±½ of its size.
            asked = new Float32Array(straight.place);
            [0, 1, 2, 3, 4, 5, 6, 7].forEach(function (index) { asked[index] *= 0.5; });
          } else if (value.name === 'g_LayerModelMatrix' && layer) {
            asked = new Float32Array(standing(layer, true).matrix);
          } else if (value.name === 'g_EffectModelViewProjectionMatrix' && onScreen) {
            // From the corners of the layer's rectangle to where they are on the scene, as a
            // shader that looks at the scene under the layer has to know.
            asked = new Float32Array([onScreen[0] / 2, onScreen[1] / 2, 0, 0, onScreen[3] / 2, onScreen[4] / 2, 0, 0,
                                      0, 0, 1, 0, onScreen[6], onScreen[7], 0, 1]);
          } else if (value.name === 'g_EffectTextureProjectionMatrixInverse' && onScreen) {
            // From a place on the screen, the pointer's, to where it is on the layer. The
            // screen is counted upward here, as Wallpaper Engine counts it; what the scene is
            // drawn on is kept the other way up.
            var a = onScreen[0] / 2, b = -onScreen[1] / 2, c = onScreen[3] / 2, d = -onScreen[4] / 2;
            var e = onScreen[6], f = -onScreen[7];
            var area = a * d - b * c;
            if (Math.abs(area) > 1e-12) {
              var ia = d / area, ib = -b / area, ic = -c / area, id = a / area;
              asked = new Float32Array([ia, ib, 0, 0, ic, id, 0, 0, 0, 0, 1, 0, -(ia * e + ic * f), -(ib * e + id * f), 0, 1]);
            }
          }
          gl.uniformMatrix4fv(uniform.location, false, asked);
        } else if (uniform.type === gl.FLOAT_MAT3) {
          gl.uniformMatrix3fv(uniform.location, false, new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]));
        } else {
          var values = engineValue(value.name, context) || (value.live ? value.live.now : null);
          if (values) setUniform(uniform, values);
        }
      });
      gl.bindVertexArray(passShape);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      pass.slots.forEach(function (slot) { gl.bindSampler(slot, null); });
      if (straight && straight.tests) {
        gl.disable(gl.DEPTH_TEST);
        gl.depthMask(true);
      }
    }

    // --- Values that change -----------------------------------------------
    //
    // Where an object is, how large, how see-through, what it says: each is read through a
    // `live` value, which knows what stands behind it. One with an animation or a script is
    // read every frame, one with a setting of the wallpaper when the settings change, and
    // one with nothing behind it never again: what a script has made of it meanwhile stays.

    var things = [];         // everything of the scene that has a place: pictures, texts, particles
    var motions = [];        // the animations of values, each with how far it has played
    var timelineAt = null;   // the moment the editor's timeline shows, in seconds, while it does
    var scripts = [];        // the scripts that are running
    var timers = [];         // what the scripts asked to be called later
    var shared = {};         // what the scripts keep for one another
    var stored = {};         // what they keep for themselves
    var dirty = true;        // something that shows has changed since the last frame drawn
    var pressed = false;     // the mouse button
    var audioBuffers = [];   // the sound, as the scripts asked for it

    function same(first, second) {
      if (!Array.isArray(first) || !Array.isArray(second)) return first === second;
      if (first.length !== second.length) return false;
      for (var i = 0; i < first.length; i++) {
        if (first[i] !== second[i]) return false;
      }
      return true;
    }

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
        scriptErrors[script.said.script] = { message: error.message, line: scriptLine(error), during: name };
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
          scriptErrors[script.said.script] = { message: error.message, line: scriptLine(error) };
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
    var scriptErrors = {};
    var scriptLog = [];

    // Gives a script's value for this frame.
    function runScript(script, current) {
      current = readyScript(script, current);
      if (script.made && script.made.update) {
        // By the editor's clock a script is run once a moment, until the editor or the
        // settings change something: frames drawn while the scene stands, as many as it takes
        // its pictures to come in, would each take it on a step (a twinkle, a smoothing, a
        // value it adds to its own last) where no time has gone by.
        if (editorClock.on && script.ranAt === time && script.ranFor === editions) return script.ranTo;
        var answer = call(script, 'update', toScript(script, current));
        // One that gives nothing back has done its work on the scene by itself.
        script.quiet = answer === undefined;
        current = fromScript(script, answer, current);
        if (editorClock.on) {
          script.ranAt = time;
          script.ranFor = editions;
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
      get frametime() { return frameTime; },
      get runtime() { return time; },
      get timeOfDay() {
        var now = new Date();
        return (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400;
      },
      get canvasSize() { return new Vec2(sceneWidth, sceneHeight); },
      get screenResolution() { return new Vec2(canvas.width, canvas.height); },
      get userProperties() {
        var result = {};
        Object.keys(properties).forEach(function (name) { result[name] = forScripts(properties[name]); });
        return result;
      },
      isPortrait: function () { return sceneHeight > sceneWidth; },
      isLandscape: function () { return sceneWidth >= sceneHeight; },
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
      timer.at = time + timer.every;
      timers.push(timer);
      return function () { timers = timers.filter(function (each) { return each !== timer; }); };
    }

    function written(list) {
      scriptLog.push(Array.prototype.map.call(list, function (part) {
        return part && typeof part === 'object' ? (part.x !== undefined ? part.toString() : JSON.stringify(part)) : String(part);
      }).join(' '));
      if (scriptLog.length > 200) scriptLog.shift();
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
      get: function (name) { return stored[name]; },
      set: function (name, value) { stored[name] = value; },
      'delete': function (name) { return delete stored[name]; },
      clear: function () { stored = {}; }
    };

    var inputObject = {
      // Where the pointer is in the scene, as the camera sees it.
      get cursorWorldPosition() {
        var seen = view(), cx = sceneWidth / 2, cy = sceneHeight / 2;
        return new Vec3(cx + seen.x + (pointer[0] * sceneWidth - cx) / seen.zoom, cy + seen.y + ((1 - pointer[1]) * sceneHeight - cy) / seen.zoom, 0);
      },
      get cursorScreenPosition() { return new Vec2(pointer[0] * canvas.width, pointer[1] * canvas.height); },
      get cursorLeftDown() { return pressed; }
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
            dirty = true;
          }
        });
      }
      function plainOf(name, get, set) {
        Object.defineProperty(object, name, { enumerable: true, get: get, set: function (value) { set(value); dirty = true; } });
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
            set: function (value) { override()[name] = Number(value); thing.settle(); dirty = true; }
          });
        });
        Object.defineProperty(object.instanceValues, 'colorn', {
          enumerable: true,
          get: function () { var c = thing.recolorGiven || [1, 1, 1]; return new Vec3(c[0], c[1], c[2]); },
          set: function (value) { override().colorn = String(value); thing.settle(); dirty = true; }
        });
        object.instanceValues.setControlPointPosition = function (index, value) {
          override()['controlpoint' + Math.round(Number(index) || 0)] = value && typeof value === 'object' ? [value.x, value.y, value.z || 0] : value;
          dirty = true;
        };
        object.instanceValues.getControlPointPosition = function (index) {
          var at = thing.pointAt(Math.round(Number(index) || 0));
          return new Vec3(at[0], at[1], at[2]);
        };
        object.instanceValues.play = function () { thing.emitting = true; };
        object.instanceValues.pause = function () { thing.emitting = false; };
        object.instanceValues.stop = function () { thing.emitting = false; thing.particles = []; dirty = true; };
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
        setFromTwo(index, parent >= 0 ? joined(undone(thing.puppet.worldOf(parent)), two) : two);
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
        set rate(value) { sheet.at = sheetTime(thing); sheet.since = time; sheet.rate = Number(value) || 0; },
        play: function () { sheet.at = sheetTime(thing); sheet.since = time; sheet.playing = true; changed(); },
        pause: function () { sheet.at = sheetTime(thing); sheet.playing = false; changed(); },
        stop: function () { sheet.at = 0; sheet.playing = false; changed(); },
        isPlaying: function () { return sheet.playing; },
        getFrame: function () { return frameNow(); },
        setFrame: function (index) { sheet.at = frameStart(Math.max(0, Math.round(Number(index) || 0))); sheet.since = time; changed(); }
      });
    }

    // The time an object's animated texture is at: the scene's own, unless a script steers it.
    function sheetTime(thing) {
      var sheet = thing && thing.sheet;
      if (!sheet) return time;
      if (sheet.since === undefined) sheet.since = time;
      return sheet.playing ? sheet.at + (time - sheet.since) * sheet.rate : sheet.at;
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
      if (!curve.events.length || timelineAt !== null) return;
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
          scripts.slice().forEach(function (script) {
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
        if (said.id === undefined || byId[String(said.id)]) said.id = 'made ' + made;
        var thing;
        try {
          thing = add(said);
        } catch (error) {
          note('a layer a script makes cannot be made: ' + error.message);
          return lenient({});
        }
        settleIn(thing);
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
        if (thing.id !== undefined && byId[String(thing.id)] === thing) delete byId[String(thing.id)];
        scripts = scripts.filter(function (script) { return script.owner !== thing; });
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
                   up: new Vec3(look.up[0], look.up[1], look.up[2]), zoom: camera.zoom };
        }
        var x = sceneWidth / 2 + camera.x, y = sceneHeight / 2 + camera.y;
        return { eye: new Vec3(x, y, 1), center: new Vec3(x, y, 0), up: new Vec3(0, 1, 0), zoom: camera.zoom };
      },
      setCameraTransforms: function (transforms) {
        var said = transforms || {};
        if (inDepth) {
          // In three dimensions the eye is put where the script says, looking where it says.
          var now = cameraLook();
          function three(value, before) {
            return value && isFinite(value.x) && isFinite(value.y) && isFinite(value.z) ? [Number(value.x), Number(value.y), Number(value.z)] : before;
          }
          scriptedLook = { eye: three(said.eye, now.eye), center: three(said.center, now.center), up: three(said.up, now.up) };
          dirty = true;
          return;
        }
        var at = said.center || said.eye;
        if (at && typeof at.x === 'number') {
          camera.x = at.x - sceneWidth / 2;
          camera.y = at.y - sceneHeight / 2;
        }
        if (typeof said.zoom === 'number' && said.zoom > 0) camera.zoom = said.zoom;
        dirty = true;
      },
      get camerafade() { return flag(general.camerafade, true); },
      set camerafade(value) { general.camerafade = !!value; },
      // How wide a scene in three dimensions is seen.
      get fov() { return number(general.perspectiveoverridefov, number(general.fov, 50)); },
      set fov(value) { if (Number(value) > 0) { general.perspectiveoverridefov = Number(value); dirty = true; } },
      get bloom() { return flag(general.bloom, false); },
      set bloom(value) { general.bloom = !!value; dirty = true; },
      get bloomstrength() { return number(general.bloomstrength, 2); },
      set bloomstrength(value) { general.bloomstrength = Number(value); dirty = true; },
      get bloomthreshold() { return number(general.bloomthreshold, 0.65); },
      set bloomthreshold(value) { general.bloomthreshold = Number(value); dirty = true; },
      get clearcolor() { return new Vec3(clear[0], clear[1], clear[2]); },
      set clearcolor(value) { clear = [value.x, value.y, value.z]; dirty = true; },
      get cameraparallax() { return flag(general.cameraparallax, false); },
      set cameraparallax(value) { general.cameraparallax = !!value; dirty = true; }
    });

    // Runs what the scripts asked to be called later, and fills the sound they listen to.
    function serveScripts() {
      timers.slice().forEach(function (timer) {
        if (time < timer.at) return;
        if (timer.again) timer.at = time + Math.max(timer.every, 0.001);
        else timers = timers.filter(function (each) { return each !== timer; });
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
      scripts.slice().forEach(function (script) {
        // Each its own copy of what happened: a script that writes into it changes it for no other.
        call(script, name, plainObject ? Object.assign({}, argument) : argument);
      });
    }

    // What music plays, as the page hears of it: each kind of news as it last came. The
    // scripts are told at first that nothing plays, the way Wallpaper Engine tells them — a
    // scene made to put its music widget away then does — and then of what does, once they
    // are ready, and of every change after.
    var mediaTold = false;
    var mediaNews = {};
    function tellNoMedia() {
      mediaTold = true;
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
      if (!mediaTold) return;
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
        if (stopped || covers.shown !== address) return;
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
      scripts.slice().forEach(function (script) {
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

    // --- Putting a picture on the scene -----------------------------------

    var placeVertex = [
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec2 a_TexCoord;',
      'uniform mat3 u_Place;',
      // In a scene in three dimensions a picture stands in the world, seen through the camera.
      'uniform mat4 u_World;',
      'uniform int u_InWorld;',
      'out vec2 v_Uv;',
      'void main() {',
      '  v_Uv = a_TexCoord;',
      '  vec3 at = u_Place * vec3(a_TexCoord.x - 0.5, 0.5 - a_TexCoord.y, 1.0);',
      '  gl_Position = u_InWorld == 1 ? u_World * vec4(a_TexCoord.x - 0.5, 0.5 - a_TexCoord.y, 0.0, 1.0) : vec4(at.xy, 0.0, 1.0);',
      '}'
    ].join('\n');
    var sampleLines = [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'uniform sampler2D u_Texture;',
      'uniform vec4 u_Tint;',
      'uniform vec4 u_Frame;',
      'uniform int u_Channels;',
      'out vec4 color;',
      'vec4 picture() {',
      '  vec4 c = texture(u_Texture, u_Frame.xy + v_Uv * u_Frame.zw);',
      // A texture of one value a pixel is a shade of grey; of two, a shade and its opacity.
      '  if (u_Channels == 1) c = vec4(c.rrr, 1.0);',
      '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
      '  return c * u_Tint;',
      '}'
    ];
    // A picture that bends is drawn as its triangles, each corner where its bones have put it.
    var meshVertex = [
      '#version 300 es',
      'in vec2 a_Spot;',
      'in vec2 a_Uv;',
      'uniform mat3 u_Place;',
      'uniform mat4 u_World;',
      'uniform int u_InWorld;',
      'out vec2 v_Uv;',
      'void main() {',
      '  v_Uv = a_Uv;',
      '  vec3 at = u_Place * vec3(a_Spot, 1.0);',
      '  gl_Position = u_InWorld == 1 ? u_World * vec4(a_Spot, 0.0, 1.0) : vec4(at.xy, 0.0, 1.0);',
      '}'
    ].join('\n');
    // The part of the scene that lies under a rectangle of it, to fill a picture of its own.
    var grabProgram = link([
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec2 a_TexCoord;',
      'uniform mat3 u_Place;',
      'out vec2 v_Uv;',
      'void main() {',
      '  v_Uv = (u_Place * vec3(a_TexCoord.x - 0.5, 0.5 - a_TexCoord.y, 1.0)).xy * 0.5 + 0.5;',
      '  gl_Position = vec4(a_TexCoord * 2.0 - 1.0, 0.0, 1.0);',
      '}'
    ].join('\n'), [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'uniform sampler2D u_Texture;',
      'out vec4 color;',
      'void main() { color = texture(u_Texture, v_Uv); }'
    ].join('\n'), 'the player\'s own shader');
    var placeProgram = link(placeVertex, sampleLines.concat(['void main() { color = picture(); }']).join('\n'), 'the player\'s own shader');
    // Layers drawn one over another onto nothing leave their colors multiplied by how solid
    // the result is. Effects, and the scene, take colors that are not: this divides them back.
    var straightProgram = link([
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec2 a_TexCoord;',
      'out vec2 v_Uv;',
      'void main() {',
      '  v_Uv = a_TexCoord;',
      '  gl_Position = vec4(a_TexCoord * 2.0 - 1.0, 0.0, 1.0);',
      '}'
    ].join('\n'), [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'uniform sampler2D u_Texture;',
      'out vec4 color;',
      'void main() {',
      '  vec4 c = texture(u_Texture, v_Uv);',
      '  color = c.a > 0.0 ? vec4(c.rgb / c.a, c.a) : vec4(0.0);',
      '}'
    ].join('\n'), 'the player\'s own shader');
    var meshProgram = link(meshVertex, sampleLines.concat(['void main() { color = picture(); }']).join('\n'), 'the player\'s own shader');
    // A part of a puppet that shows only within others — an iris within the white of its eye —
    // is drawn through a mask of those others: where a picture says they count, or where they
    // are not see-through.
    var clipMaskProgram = link(meshVertex, [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'uniform sampler2D u_Texture;',
      'uniform int u_Alpha;',
      'out vec4 color;',
      'void main() {',
      '  vec4 c = texture(u_Texture, v_Uv);',
      '  color = vec4(u_Alpha == 1 ? c.a : c.r);',
      '}'
    ].join('\n'), 'the player\'s own shader');
    var clippedProgram = link(meshVertex, sampleLines.concat([
      'uniform sampler2D u_Mask;',
      'uniform vec2 u_MaskSize;',
      'void main() {',
      '  vec4 c = picture();',
      '  color = vec4(c.rgb, c.a * texture(u_Mask, gl_FragCoord.xy / u_MaskSize).r);',
      '}'
    ]).join('\n'), 'the player\'s own shader');
    // Blended with what lies under it in one of the ways image editors have; the scene so far
    // is read from a copy.
    var blendFragment = sampleLines.concat([
      'uniform sampler2D u_Scene;',
      'uniform vec2 u_SceneSize;',
      'uniform int u_Mode;'
    ], BLEND_HELPERS, [
      'vec3 blend(vec3 A, vec3 B) {'
    ], BLENDS.map(function (formula, index) {
      return '  if (u_Mode == ' + (index + 1) + ') return ' + formula + ';';
    }), [
      '  return B;',
      '}',
      'void main() {',
      '  vec4 c = picture();',
      '  vec3 under = texture(u_Scene, gl_FragCoord.xy / u_SceneSize).rgb;',
      '  color = vec4(mix(under, clamp(blend(under, c.rgb), 0.0, 1.0), clamp(c.a, 0.0, 1.0)), 1.0);',
      '}'
    ]).join('\n');
    var blendProgram = link(placeVertex, blendFragment, 'the player\'s own shader');
    var meshBlendProgram = link(meshVertex, blendFragment, 'the player\'s own shader');

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

    var byId = {};

    // What every object with a place has: where it is, how large and how turned, how
    // see-through and of what tint, and whether it shows at all.
    function placed(object, otherName) {
      var hangs = object.parent !== undefined && object.parent !== null;
      var thing = { name: String(plain(object.name) || otherName || object.id || ''), id: object.id, parent: hangs ? object.parent : undefined,
                    said: object, state: {}, lives: {}, moving: false };
      // The mouse is told to an object unless the scene says it is not solid.
      thing.solid = flag(object.solid, true);
      var given = numbers(object.size, 2, 0);
      if (given[0] > 0 && given[1] > 0) thing.size = given;
      thing.lives.origin = live(object.origin, 3, unplaced(object), thing);
      thing.lives.scale = live(object.scale, 3, 1, thing);
      thing.lives.angles = live(object.angles, 3, 0, thing, 'numbers', 'degrees');
      thing.lives.alpha = live(object.alpha, 1, 1, thing);
      thing.lives.color = live(object.color, 3, 1, thing);
      thing.lives.visible = live(object.visible, 0, true, thing, 'flag');
      thing.state.parallax = numbers(object.parallaxDepth, 2, 1);
      // A camera: where it looks from, against the middle of the scene, and how near.
      if (object.camera !== undefined && object.camera !== null) {
        thing.isCamera = true;
        thing.lives.zoom = live(object.zoom === undefined ? 1 : object.zoom, 1, 1, thing);
        thing.paths = cameraPathsOf(plain(object.path));
        thing.pathOrder = key(String(plain(object.queuemode) || 'sequential')) === 'random' ? 'random' : 'sequential';
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
      if (object.id !== undefined) byId[String(object.id)] = thing;
      things.push(thing);
      return thing;
    }

    // Where the scene is seen from this frame, against its middle, and how near: the camera
    // of the scene that shows — of several, the last in the scene's list, as in Wallpaper
    // Engine — moved and zoomed further by a script and by the scene's own zoom.
    var viewOnce = { frame: -1 };
    // The camera object the scene is seen through: the last one that shows.
    // Where the eye is, for how light glints: the camera of a scene in three dimensions, or in
    // front of the middle of a flat one.
    // Where the eye of a scene in three dimensions is, what it looks at and which way is up:
    // as a script has put it (`setCameraTransforms`), else its camera object's, else the
    // scene's own.
    var scriptedLook = null;
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
    var scenePaths;
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
    // Chosen at random, the same way every time the scene plays, so that its pictures can
    // be compared; never the same path twice in a row when there is another.
    var pathLuck = 7;
    function nextPath(shot, after) {
      var count = shot.paths.length;
      if (count < 2) return 0;
      if (shot.pathOrder !== 'random') return after < 0 ? 0 : (after + 1) % count;
      pathLuck = (pathLuck * 1103515245 + 12345) % 2147483648;
      var pick = pathLuck % (after < 0 ? count : count - 1);
      return after >= 0 && pick >= after ? pick + 1 : pick;
    }
    // Where the active camera's path has it on this frame — eye, centre, up and how wide it
    // sees — and how dark the scene is while one path gives way to the next (`camerafade`);
    // null for a camera without paths.
    var PATH_FADE = 0.35; // seconds of darkening on each side of a change of path (not measured)
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
    // Whether an object and all it hangs on are shown, without working out where they are.
    function showsAll(thing) {
      for (var depth = 0; thing && depth < 64; depth++) {
        if (thing.state.visible === false) return false;
        thing = thing.parent !== undefined ? byId[String(thing.parent)] : null;
      }
      return true;
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
          dirty = true;
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

    // What was drawn of an object once and kept no longer holds.
    function stale(thing) {
      dirty = true;
      if (thing.kept) {
        release(thing.kept);
        thing.kept = null;
      }
    }

    // The effects on an object, each a list of passes ready to draw.
    function buildEffects(thing, object) {
      thing.effects = [];
      // Those not made ready because they were off, by their places.
      thing.effectsOff = {};
      (object.effects || []).forEach(function (use, place) {
        // One the scene has switched off for good is not made ready at all, unless the scene
        // has scripts, which may switch it on.
        if (use.visible === false && !scripted) {
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
          var own = ((json(step.material) || {}).passes || [])[0];
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
        if (layer.holds) layer.copiesBackground = flag(object.copybackground, true) !== false;
        if (!layer.holds && flag(object.copybackground, true) === false) {
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
      var base = (model && (json(model.material) || {}).passes || [])[0] || {};
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
        var own = sheet ? [sheet[4], sheet[7]] : layer.picture && layer.picture.width > 1 ? [layer.picture.width, layer.picture.height] : [sceneWidth, sceneHeight];
        size = [number(model && model.width, 0) || own[0], number(model && model.height, 0) || own[1]];
      }
      layer.size = size;
      // Which point of the picture is at its place: its middle, the middle of a side, or a corner.
      var hangs = key(String(plain(object.alignment) || 'center'));
      var aside = [/left/.test(hangs) ? size[0] / 2 : (/right/.test(hangs) ? -size[0] / 2 : 0),
                   /top/.test(hangs) ? -size[1] / 2 : (/bottom/.test(hangs) ? size[1] / 2 : 0)];
      if (aside[0] !== 0 || aside[1] !== 0) layer.shift = aside;
      layer.brightness = number(object.brightness, 1);
      // Scenes of early versions say how see-through and how bright a picture is in its
      // material rather than on the object.
      var own = {};
      Object.keys(base.constantshadervalues || {}).forEach(function (name) { own[key(name)] = base.constantshadervalues[name]; });
      layer.materialAlpha = number(plain(own.alpha), 1);
      layer.brightness *= number(plain(own.brightness), 1);
      layer.blendMode = number(object.colorBlendMode, 0);
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
          metallic: number(plain(own.metallic), 0.5), roughness: number(plain(own.roughness), 0.5),
          reflectivity: number(plain(own.reflectivity), 1),
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
      layer.draw = function () { drawImage(layer); };
      // Made ahead of the rest of the frame when others take its finished picture.
      // One that shows what lies under it is made in its turn: ahead, there is nothing under it yet.
      if (layer.composite && !layer.takesScene && !layer.copiesBackground) layer.makeComposite = function () { drawImage(layer, true); };
      return layer;
    }

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
    // --- Building ---------------------------------------------------------

    var listening = false;

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

    var all = (description.objects || []).filter(function (object) { return object && typeof object === 'object'; });
    if (!(sceneWidth > 0 && sceneHeight > 0) && inDepth && window.innerWidth > 0 && window.innerHeight > 0) {
      // A scene in three dimensions is seen through the screen, whatever its pictures: a
      // first one of 32 by 32 made 3509243656 a blur.
      sceneWidth = 1920;
      sceneHeight = Math.round(1920 * window.innerHeight / window.innerWidth);
    }
    if (!(sceneWidth > 0 && sceneHeight > 0)) {
      // A scene may leave its size to its first picture.
      var first = all.filter(function (object) { return object.image; })[0];
      var firstSize = first ? numbers(first.size, 2, 0) : [0, 0];
      if (first && !(firstSize[0] > 0 && firstSize[1] > 0)) {
        // One that is as large as its picture says so only in its picture: a frame of the GIF
        // of Wallpaper Engine's template (843532366, 480 by 300, its middle at 240, 150), or,
        // without a picture to tell, twice as far as the middle it is placed at.
        var firstModel = json(String(plain(first.image) || '')) || {};
        var firstPass = ((json(String(firstModel.material || '')) || {}).passes || [])[0] || {};
        var firstPicture = (firstPass.textures || [])[0] ? texture('materials/' + firstPass.textures[0]) : null;
        var firstFrame = firstPicture && firstPicture.frames && firstPicture.frames[0];
        firstSize = firstFrame ? [firstFrame[4], firstFrame[7]] : firstPicture && firstPicture.width > 1 ? [firstPicture.width, firstPicture.height]
                  : numbers(first.origin, 2, 0).map(function (part) { return part * 2; });
      }
      sceneWidth = firstSize[0] > 0 ? firstSize[0] : 1920;
      sceneHeight = firstSize[1] > 0 ? firstSize[1] : 1080;
    }
    // A scene with scripts may show what it has hidden; in any other, what is hidden for good
    // is left out.
    var scripted = /"script"\s*:/.test(files['scene.json'] || '');

    function isSet(value) {
      return value !== undefined && value !== null;
    }
    // Changes made in the editor: editor.js.
    var changes, pristine, FOLLOWED;
    var editorPart = makeEditor(ctx);
    var hexOf = editorPart.hexOf, changeOf = editorPart.changeOf, amended = editorPart.amended, amendGeneral = editorPart.amendGeneral, skeleton = editorPart.skeleton, canonical = editorPart.canonical, follow = editorPart.follow, add = editorPart.add, settleIn = editorPart.settleIn, isMoving = editorPart.isMoving, isLively = editorPart.isLively;
    // --- Moving with the pointer ---------------------------------------------------------
    //
    // A scene may be looked at as through a window: as the pointer moves, what is said to be
    // near moves more than what is far. `eye` is where the scene is looked at from, from the
    // middle, and follows the pointer with a delay.

    var eye = { on: false, amount: 0, x: 0, y: 0, settling: false };
    // The camera may shake: the whole scene is moved a little, smoothly and without end, as
    // far as the amplitude says (a share of the scene's height), as fast as the speed says,
    // and the rougher, the more of a quicker trembling there is in it.
    var shake = { on: false, x: 0, y: 0 };
    // Where a script has moved the camera from the scene's middle, and how near it is.
    var camera = { x: 0, y: 0, zoom: 1 };

    function tremble() {
      shake.on = flag(general.camerashake, false);
      if (!shake.on) {
        if (shake.x || shake.y) {
          shake.x = shake.y = 0;
          dirty = true;
        }
        return;
      }
      var reach = number(general.camerashakeamplitude, 0.5) / 100 * sceneHeight;
      var at = time * number(general.camerashakespeed, 3), rough = Math.max(0, number(general.camerashakeroughness, 1));
      function wobble(seed) {
        return (smoothNoise(at, seed * 13.7, 4096, seed) - 0.5) * 2 + rough * 0.5 * (smoothNoise(at * 4, seed * 29.1, 4096, seed + 1) - 0.5) * 2;
      }
      shake.x = reach * wobble(3);
      shake.y = reach * wobble(9);
      dirty = true;
    }

    function look(seconds) {
      tremble();
      eye.on = flag(general.cameraparallax, false);
      if (!eye.on) {
        eye.settling = false;
        return;
      }
      eye.amount = number(general.cameraparallaxamount, 0.5);
      var reach = number(general.cameraparallaxmouseinfluence, 0.5);
      var delay = Math.max(0, number(general.cameraparallaxdelay, 0.1));
      var toX = (Math.max(0, Math.min(1, pointer[0])) - 0.5) * reach, toY = (Math.max(0, Math.min(1, pointer[1])) - 0.5) * reach;
      var share = delay > 0 ? 1 - Math.exp(-seconds / delay) : 1;
      var x = eye.x + (toX - eye.x) * share, y = eye.y + (toY - eye.y) * share;
      eye.settling = Math.abs(toX - x) + Math.abs(toY - y) > 0.0002;
      if (!eye.settling) {
        x = toX;
        y = toY;
      }
      if (x !== eye.x || y !== eye.y) {
        eye.x = x;
        eye.y = y;
        dirty = true;
      }
    }

    // --- Glow -----------------------------------------------------------------
    //
    // A scene may glow where it is bright (bloom): what is brighter than a threshold is taken
    // out small, blurred and added back over the scene.

    var fillVertex = [
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec2 a_TexCoord;',
      'out vec2 v_Uv;',
      'void main() {',
      '  v_Uv = a_TexCoord;',
      '  gl_Position = vec4(a_TexCoord * 2.0 - 1.0, 0.0, 1.0);',
      '}'
    ].join('\n');
    var brightProgram = link(fillVertex, [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'uniform sampler2D u_Texture;',
      'uniform vec2 u_Texel;',
      'uniform float u_Threshold;',
      'uniform float u_Strength;',
      'out vec4 color;',
      'void main() {',
      '  vec3 c = (texture(u_Texture, v_Uv + u_Texel * vec2(-1.0, -1.0)).rgb + texture(u_Texture, v_Uv + u_Texel * vec2(1.0, -1.0)).rgb +',
      '            texture(u_Texture, v_Uv + u_Texel * vec2(-1.0, 1.0)).rgb + texture(u_Texture, v_Uv + u_Texel * vec2(1.0, 1.0)).rgb) * 0.25;',
      // As Wallpaper Engine's own glow: the brightest of the three channels over the
      // threshold says how much, so a deep blue light glows too, and the glow is made twice
      // as colorful as it is.
      '  float over = clamp(max(max(c.r, c.g), c.b) - u_Threshold, 0.0, 1.0);',
      '  c *= over;',
      '  c = c * 2.0 - dot(vec3(0.2989, 0.5870, 0.1140), c);',
      '  color = vec4(max(vec3(0.0), c * u_Strength), 1.0);',
      '}'
    ].join('\n'), 'the player\'s own shader');
    // Thirteen steps of an eighth of the picture apart, weighed as Wallpaper Engine's glow
    // weighs them, across and then down.
    var blurProgram = link(fillVertex, [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'uniform sampler2D u_Texture;',
      'uniform vec2 u_Step;',
      'out vec4 color;',
      'const float WEIGHT[7] = float[7](0.171834, 0.156756, 0.119007, 0.075189, 0.039533, 0.017298, 0.006299);',
      'void main() {',
      '  vec3 c = texture(u_Texture, v_Uv).rgb * WEIGHT[0];',
      '  for (int i = 1; i < 7; i++) {',
      '    c += (texture(u_Texture, v_Uv + u_Step * float(i)).rgb + texture(u_Texture, v_Uv - u_Step * float(i)).rgb) * WEIGHT[i];',
      '  }',
      '  color = vec4(c, 1.0);',
      '}'
    ].join('\n'), 'the player\'s own shader');

    function glow() {
      // In a scene drawn with a high range of brightness, the glow has settings of its own; its
      // threshold counts from brighter than white, which a picture here never is.
      var hdr = flag(general.hdr, false);
      var strength = hdr ? number(general.bloomhdrstrength, 2) : number(general.bloomstrength, 2);
      var threshold = hdr ? Math.min(0.95, number(general.bloomhdrthreshold, 1) * 0.65) : number(general.bloomthreshold, 0.65);
      if (!brightProgram || !blurProgram || !(strength > 0)) return;
      var quarter = acquire(sceneTarget.width / 4, sceneTarget.height / 4);
      var small = [acquire(sceneTarget.width / 8, sceneTarget.height / 8), acquire(sceneTarget.width / 8, sceneTarget.height / 8)];
      function fill(target, program, source) {
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
        gl.viewport(0, 0, target.width, target.height);
        gl.useProgram(program.program);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, source.texture);
        gl.uniform1i(program.uniforms.u_Texture.location, 0);
      }
      gl.disable(gl.BLEND);
      gl.bindVertexArray(passShape);
      fill(quarter, brightProgram, sceneTarget);
      gl.uniform2f(brightProgram.uniforms.u_Texel.location, 1 / sceneTarget.width, 1 / sceneTarget.height);
      gl.uniform1f(brightProgram.uniforms.u_Threshold.location, threshold);
      gl.uniform1f(brightProgram.uniforms.u_Strength.location, strength);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      fill(small[0], blurProgram, quarter);
      gl.uniform2f(blurProgram.uniforms.u_Step.location, 1 / small[0].width, 0);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      fill(small[1], blurProgram, small[0]);
      gl.uniform2f(blurProgram.uniforms.u_Step.location, 0, 1 / small[0].height);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.framebuffer);
      gl.viewport(0, 0, sceneTarget.width, sceneTarget.height);
      var tint = numbers(general.bloomtint, 3, 1);
      put({ texture: small[1].texture }, FILL, [tint[0], tint[1], tint[2], 1], 'additive');
      release(quarter);
      small.forEach(release);
    }

    // --- Size -------------------------------------------------------------

    // The scene is drawn as large as it shows on the screen, and no larger than it is.
    function resize() {
      var density = window.devicePixelRatio || 1;
      var shown = Math.max(window.innerWidth * density / sceneWidth, window.innerHeight * density / sceneHeight);
      var wanted = Math.max(0.05, Math.min(1, shown || 1));
      var width = Math.max(1, Math.round(sceneWidth * wanted)), height = Math.max(1, Math.round(sceneHeight * wanted));
      if (sceneTarget && canvas.width === width && canvas.height === height) return;
      var again = !!sceneTarget;
      scale = wanted;
      canvas.width = width;
      canvas.height = height;
      // Everything drawn at the old size goes.
      objects.forEach(function (object) {
        if (object.kept) {
          gl.deleteFramebuffer(object.kept.framebuffer);
          gl.deleteTexture(object.kept.texture);
          object.kept = null;
        }
      });
      [sceneTarget, copyTarget].forEach(release);
      // So do the finished pictures kept for others; they show nothing until made again.
      Object.keys(composites).forEach(function (id) {
        var kept = composites[id];
        if (kept.target) releaseRepeated(kept.target);
        kept.target = null;
        kept.layers[0] = flat(0, 0, 0, 0).layers[0];
      });
      forgetTargets();
      sceneTarget = acquire(width, height);
      copyTarget = acquire(width, height);
      redraw = true;
      if (again) tellScripts('resizeScreen', new Vec2(width, height));
    }

    // --- Drawing ----------------------------------------------------------

    var frames = 0;

    var fadeWhite = null; // a white picture, darkened to black, for the camera's fade
    var keptWidth = 0; // the size of the picture kept from before, for a scene that does not clear it
    function draw() {
      gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.framebuffer);
      gl.viewport(0, 0, sceneTarget.width, sceneTarget.height);
      gl.disable(gl.BLEND);
      // A scene may say not to clear what was drawn before, so that what moves leaves its trace
      // on the picture. The glow is added onto the picture, so with it the picture is cleared
      // all the same, as it is for the first frame.
      var keeps = general.clearenabled === false && !flag(general.bloom, false) && frames > 0 && sceneTarget.width === keptWidth;
      keptWidth = sceneTarget.width;
      if (!keeps) {
        gl.clearColor(clear[0], clear[1], clear[2], 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
      }
      surface = { target: sceneTarget, copy: copyTarget, width: sceneWidth, height: sceneHeight, left: 0, bottom: 0 };
      // In a scene in three dimensions, as Wallpaper Engine sorts it: first every model's parts
      // that hide what is behind them, then everything in the scene's order with the models'
      // parts that show through — else a glow drawn early hides, by its depth, the street
      // drawn after it.
      var passes = inDepth ? ['solid', 'through'] : [null];
      // What others take as a picture is made first: a planet's surface, a face in a frame.
      objects.forEach(function (object) {
        if (!object.makeComposite) return;
        object.makeComposite();
        gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.framebuffer);
        gl.viewport(0, 0, sceneTarget.width, sceneTarget.height);
      });
      // What the scene has before its first model is drawn before any model, as the scene
      // orders it: a background over the whole screen does not then hide the models drawn
      // after it (3796846129's ToeJam and Earl).
      var drawn = objects.slice();
      var firstModel = drawn.findIndex(function (object) { return object.isModel; });
      var before = inDepth && firstModel > 0 ? drawn.slice(0, firstModel) : [];
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
          gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.framebuffer);
          gl.viewport(0, 0, sceneTarget.width, sceneTarget.height);
          object.draw(pass === 'under' ? 'through' : pass);
        });
      });
      if (flag(general.bloom, false)) glow();
      // Dark for a moment while the camera goes from one of its paths to the next.
      var onPath = inDepth && !freeLook() ? pathLook(activeCamera()) : null;
      if (onPath && onPath.dark > 0) {
        fadeWhite = fadeWhite || flat(255, 255, 255, 255);
        gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.framebuffer);
        gl.viewport(0, 0, sceneTarget.width, sceneTarget.height);
        put(fadeWhite.layers[0], FILL, [0, 0, 0, onPath.dark], 'translucent');
      }
      // Onto the canvas, turned over: the scene is kept with its top row first.
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, sceneTarget.framebuffer);
      gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
      gl.blitFramebuffer(0, 0, sceneTarget.width, sceneTarget.height, 0, sceneTarget.height, sceneTarget.width, 0, gl.COLOR_BUFFER_BIT, gl.NEAREST);
      frames++;
    }

    var asked = 0;
    var before = 0;

    function wake() {
      if (!asked && !stopped) asked = requestAnimationFrame(frame);
    }

    var testBegun = false;
    // How many times the editor or the settings have changed the scene (see `runScript`).
    var editions = 0;
    function frame(now) {
      asked = 0;
      if (stopped) return;
      // In a test, once the first frame has made the scene's objects, nothing more is done
      // until their pictures are all in: how many frames that takes varies from run to run.
      if (testClock && testBegun && loading > 0) {
        wake();
        return;
      }
      testBegun = true;
      // The speed the app plays the wallpaper at; a long gap, as after a pause, counts as none.
      // Held by the editor, the scene's time stands.
      var host = window.__wallaeroHost;
      var passed = before && !editorClock.held ? Math.min(0.1, Math.max(0, (now - before) / 1000)) * ((host && host.rate) || 1) : 0;
      before = now;
      goOn(passed);
      // Drawn anew only when it would come out another picture: a scene whose scripts only
      // wait, or whose clock still shows the same minute, is left as it is. One the editor
      // holds changes only as it is changed.
      var moving = !editorClock.held && isMoving();
      var must = moving || redraw || dirty || loading > 0;
      redraw = false;
      dirty = false;
      if (must) draw();
      pointerBefore = pointer.slice();
      // A scene in which nothing moves is drawn once it is all there, and then left alone.
      if (moving || loading > 0 || redraw || dirty || (!editorClock.held && isLively())) {
        wake();
      } else {
        before = 0;
      }
    }

    // The scene goes on by a while, in seconds: its clock, its scripts, its animations, its
    // particles; what that makes of it is drawn after.
    function goOn(passed) {
      // Never nought for scripts, as in Wallpaper Engine: the first frame takes the one before
      // as long as a sixtieth (3737268876's camera works out `frametime * (1 / frametime)`).
      if (passed > 0) frameTime = passed;
      // By the editor's clock each frame draws its chances afresh from the moment it starts
      // at: what frames drawn while the scene stood (as its pictures came in, a number that
      // varies from run to run) took of them changes nothing of what comes after.
      if (editorClock.on) seedChance(Math.round(time * 1000) + 1);
      time += passed;
      if (testClock) testClock.at = time * 1000;
      // The editor's timeline shows every animation at the scene's moment; standing, at
      // the moment the editor shows it at.
      if (editorClock.on && passed > 0) timelineAt = time;
      holdFilms();
      resize();
      serveScripts();
      look(passed);
      if (showFilms()) dirty = true;
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
      scripts.slice().forEach(function (script) {
        if (script.made === undefined) script.made = null;
      });
      if (!mediaTold) tellNoMedia();
      objects.slice().forEach(function (object) {
        if (object.step && passed > 0 && standing(object).visible) object.step(passed);
      });
    }

    // Videos stand while the editor holds the scene, at the scene's moment, and play on with it.
    function holdFilms() {
      if (!editorClock.on) return;
      films.forEach(function (each) {
        var video = each.video;
        if (editorClock.held) {
          if (!video.paused) video.pause();
          var length = video.duration;
          var at = length > 0 && isFinite(length) ? time % length : 0;
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

    // --- The mouse --------------------------------------------------------------

    // Where the pointer is over the scene, from 0 to 1 from its top left corner: the scene is
    // fitted to the screen by the page, cut or with bars.
    function point(event) {
      var shown = shownAt();
      pointer = [(event.clientX - shown.left) / shown.width, (event.clientY - shown.top) / shown.height];
      // Come over the wallpaper — from a window, or for the first time — the pointer has not
      // moved from where it was last seen, across the screen: it is only now seen here.
      if (!pointerSeen) pointerBefore = pointer.slice();
      pointerSeen = true;
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
    // The part of the scene the screen shows, in the scene's units from its bottom left
    // corner: all of it, unless the scene is cut to fill the screen. Worked out once a frame.
    var seenOnce = { frame: -1 };
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
    function pageAt(x, y) {
      var shown = shownAt();
      return [shown.left + x / sceneWidth * shown.width, shown.top + (1 - y / sceneHeight) * shown.height];
    }
    // What the mouse does is told to the scripts; whatever they change by it is then drawn.
    function mouse(kind) {
      return function (event) {
        point(event);
        if (kind === 'down') pressed = true;
        if (kind === 'up') pressed = false;
        tellPointer(kind);
        if (dirty || eye.on) wake();
      };
    }
    var mice = { pointermove: mouse('move'), pointerdown: mouse('down'), pointerup: mouse('up'),
                 // Gone from the wallpaper: over a window, or to another display.
                 pointerleave: function () { pointerSeen = false; } };
    Object.keys(mice).forEach(function (name) { window.addEventListener(name, mice[name], true); });
    window.addEventListener('resize', changed);

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
