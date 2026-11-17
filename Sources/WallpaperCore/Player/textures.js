  // Textures: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeTextures(ctx) {
    var pictures = ctx.pictures, gl = ctx.gl, changed = ctx.changed, stale = ctx.stale;
    // --- Textures ---------------------------------------------------------

    ctx.loading = 0;       // pictures still on their way
    var textureCache = {};

    // The finished picture of a layer — what it shows after its effects — as others take it
    // by name, `_rt_imageLayerComposite_<id>_a`: a planet's surface, a picture in a frame. It
    // stands empty until the layer is first drawn; the layer then keeps it up to date.
    ctx.composites = {};
    function compositeNamed(name) {
      var made = /_rt_imagelayercomposite_(\d+)_[ab]$/.exec(key(name));
      if (!made) return null;
      if (!ctx.composites[made[1]]) {
        var empty = flat(0, 0, 0, 0);
        ctx.composites[made[1]] = { layers: [empty.layers[0]], width: 1, height: 1, channels: 'rgba', ready: true };
      }
      return ctx.composites[made[1]];
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
    ctx.covers = { now: blankCover(), before: blankCover(), shown: '' };

    ctx.films = [];   // the textures that are videos, each with the video it shows

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
        ctx.loading--;
        changed();
      }
      ctx.loading++;
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
      ctx.films.push(result.film);
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
      ctx.films.forEach(function (each) {
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
      if (id === '$mediathumbnail') return ctx.covers.now;
      if (id === '$mediapreviousthumbnail') return ctx.covers.before;
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
          ctx.loading++;
          image.onload = function () {
            ctx.loading--;
            if (ctx.stopped) return;
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
            ctx.loading--;
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

    return { compositeNamed: compositeNamed, newTexture: newTexture, looksOf: looksOf, sheetFrames: sheetFrames, flat: flat, shows: shows, showFilms: showFilms, chosenTexture: chosenTexture, texture: texture };
  }

