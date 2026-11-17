  // A pass of an effect: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeEffects(ctx) {
    var files = ctx.files, gl = ctx.gl, link = ctx.link, passShape = ctx.passShape, looksOf = ctx.looksOf, IDENTITY = ctx.IDENTITY, MOVING = ctx.MOVING, engineValue = ctx.engineValue, setUniform = ctx.setUniform, live = ctx.live, standing = ctx.standing, listen = ctx.listen;
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
          if (program || !ctx.complaint) break;
          if (ctx.complaint.stage === 'both') {
            // The two shaders do not fit each other.
            var pair = mendPair(sources.vertex, sources.fragment, ctx.complaint.messages);
            if (pair === null) {
              note(ctx.complaint.said);
              break;
            }
            sources = pair;
            continue;
          }
          var mended = mend(sources[ctx.complaint.stage], ctx.complaint.messages, ctx.complaint.line);
          if (mended === null) {
            note(ctx.complaint.said);
            break;
          }
          sources[ctx.complaint.stage] = mended;
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

    return { buildPass: buildPass, withLooks: withLooks, drawPass: drawPass };
  }

