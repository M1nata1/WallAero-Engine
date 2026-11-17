  // What the shaders are told of the scene: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeShaderValues(ctx) {
    function changed() {
      ctx.redraw = true;
      ctx.wake();
    }

    ctx.IDENTITY = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    ctx.MOVING = /^g_(Time|Frametime|Daytime|PointerPosition|PointerPositionLast|AudioSpectrum\d+(Left|Right))$/;

    function bands(count, right) {
      var values = new Float32Array(count);
      if (!ctx.spectrum) return values;
      var each = 64 / count;
      for (var i = 0; i < count; i++) {
        var sum = 0;
        for (var j = 0; j < each; j++) sum += ctx.spectrum[(right ? 64 : 0) + i * each + j] || 0;
        values[i] = sum / each;
      }
      return values;
    }

    // What Wallpaper Engine itself tells a shader, by the uniform's name.
    function engineValue(name, context) {
      switch (name) {
        case 'g_Time': return [ctx.time];
        case 'g_Frametime': return [ctx.frameTime];
        case 'g_Daytime': var now = new Date(); return [(now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400];
        case 'g_PointerPosition': return ctx.pointer;
        case 'g_PointerPositionLast': return ctx.pointerBefore;
        // Whether the mouse button is down.
        case 'g_PointerState': return [ctx.pressed ? 1 : 0, 0, ctx.pressed ? 1 : 0, 0];
        case 'g_TexelSize': return [1 / context.width, 1 / context.height];
        case 'g_TexelSizeHalf': return [0.5 / context.width, 0.5 / context.height];
        case 'g_Screen': return [ctx.sceneWidth, ctx.sceneHeight, ctx.sceneWidth / ctx.sceneHeight];
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
        case ctx.gl.FLOAT:
          if (uniform.size > 1) ctx.gl.uniform1fv(location, new Float32Array(values).subarray(0, uniform.size));
          else ctx.gl.uniform1f(location, values[0]);
          break;
        case ctx.gl.FLOAT_VEC2: ctx.gl.uniform2f(location, values[0], values[1]); break;
        case ctx.gl.FLOAT_VEC3: ctx.gl.uniform3f(location, values[0], values[1], values[2]); break;
        case ctx.gl.FLOAT_VEC4: ctx.gl.uniform4f(location, values[0], values[1], values[2], values[3]); break;
        case ctx.gl.INT: case ctx.gl.BOOL: ctx.gl.uniform1i(location, values[0]); break;
      }
    }
    return { changed: changed, bands: bands, engineValue: engineValue, setUniform: setUniform };
  }

