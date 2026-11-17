  // Where things stand: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePlacing(ctx) {
    // --- Where things stand -------------------------------------------------------
    //
    // An object has a place, a size and a turn about each of the three axes, all counted from
    // the object it hangs on. They are kept as a matrix of four by four, column by column.
    // The scene is looked at from straight ahead and from far: depth shows only in how
    // something turned is foreshortened, and in where what lies behind it comes to stand.

    // What is being drawn on: the scene, or a layer that holds other layers. `left` and
    // `bottom` are where its lower left corner is, in the coordinates of what is drawn on it.
    ctx.surface = null;

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
      var width = ctx.surface.width, height = ctx.surface.height;
      return new Float32Array([
        2 * matrix[0] * size[0] / width, -2 * matrix[1] * size[0] / height, 0,
        2 * matrix[4] * size[1] / width, -2 * matrix[5] * size[1] / height, 0,
        2 * (matrix[12] - ctx.surface.left) / width - 1, 1 - 2 * (matrix[13] - ctx.surface.bottom) / height, 1
      ]);
    }

    // Where a rectangle stands in a scene in three dimensions, as seen through the camera: a
    // matrix of four by four from its own coordinates, from its middle with y up. `tests`:
    // whether it is hidden behind what is nearer, as a material that tests depth asks.
    function worldPlaceOf(matrix, size, tests) {
      var sized = matrix.slice();
      [0, 1, 2].forEach(function (index) { sized[index] *= size[0]; sized[4 + index] *= size[1]; });
      var place = new Float32Array(times4(ctx.viewProjection(), sized));
      place.tests = !!tests;
      return place;
    }
    // Tells a program where to put what it draws: on the surface, or in the world.
    function placeIn(program, place) {
      var inWorld = place.length === 16;
      if (program.uniforms.u_InWorld) ctx.gl.uniform1i(program.uniforms.u_InWorld.location, inWorld ? 1 : 0);
      if (inWorld) ctx.gl.uniformMatrix4fv(program.uniforms.u_World.location, false, place);
      else ctx.gl.uniformMatrix3fv(program.uniforms.u_Place.location, false, place);
    }

    ctx.CHANNELS = { rgba: 0, r8: 1, rg88: 2 };

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
      if (mesh && mesh.clips && mesh.clips.length && typeof how !== 'number' && ctx.clipMaskProgram && ctx.clippedProgram) {
        putClipped(source, place, tint, how, mesh);
        return;
      }
      var program = mesh ? ctx.meshProgram : ctx.placeProgram;
      var onto = ctx.surface.target;
      if (typeof how === 'number') {
        // What is under the picture is read from a copy of what it is drawn on.
        if (!ctx.surface.copy) ctx.surface.copy = ctx.acquire(onto.width, onto.height);
        ctx.gl.bindFramebuffer(ctx.gl.READ_FRAMEBUFFER, onto.framebuffer);
        ctx.gl.bindFramebuffer(ctx.gl.DRAW_FRAMEBUFFER, ctx.surface.copy.framebuffer);
        // Only what lies under the picture: a small one copies a small part.
        var under = mesh || place.length === 16 ? null : coveredBy(place, onto);
        if (under) ctx.gl.blitFramebuffer(under[0], under[1], under[2], under[3], under[0], under[1], under[2], under[3], ctx.gl.COLOR_BUFFER_BIT, ctx.gl.NEAREST);
        else ctx.gl.blitFramebuffer(0, 0, onto.width, onto.height, 0, 0, onto.width, onto.height, ctx.gl.COLOR_BUFFER_BIT, ctx.gl.NEAREST);
        ctx.gl.bindFramebuffer(ctx.gl.FRAMEBUFFER, onto.framebuffer);
        program = mesh ? ctx.meshBlendProgram : ctx.blendProgram;
      }
      if (!program) return;
      ctx.gl.useProgram(program.program);
      if (typeof how === 'number') {
        ctx.gl.disable(ctx.gl.BLEND);
        ctx.gl.activeTexture(ctx.gl.TEXTURE1);
        ctx.gl.bindTexture(ctx.gl.TEXTURE_2D, ctx.surface.copy.texture);
        ctx.gl.uniform1i(program.uniforms.u_Scene.location, 1);
        ctx.gl.uniform2f(program.uniforms.u_SceneSize.location, onto.width, onto.height);
        ctx.gl.uniform1i(program.uniforms.u_Mode.location, how);
      } else if (how === 'normal') {
        ctx.gl.disable(ctx.gl.BLEND);
      } else {
        ctx.gl.enable(ctx.gl.BLEND);
        if (how === 'additive') ctx.gl.blendFuncSeparate(ctx.gl.SRC_ALPHA, ctx.gl.ONE, ctx.gl.ZERO, ctx.gl.ONE);
        else ctx.gl.blendFuncSeparate(ctx.gl.SRC_ALPHA, ctx.gl.ONE_MINUS_SRC_ALPHA, ctx.gl.ONE, ctx.gl.ONE_MINUS_SRC_ALPHA);
      }
      ctx.gl.activeTexture(ctx.gl.TEXTURE0);
      ctx.gl.bindTexture(ctx.gl.TEXTURE_2D, source.texture);
      ctx.gl.uniform1i(program.uniforms.u_Texture.location, 0);
      placeIn(program, place);
      ctx.gl.uniform4fv(program.uniforms.u_Tint.location, tint);
      ctx.gl.uniform4fv(program.uniforms.u_Frame.location, source.frame || [0, 0, 1, 1]);
      ctx.gl.uniform1i(program.uniforms.u_Channels.location, ctx.CHANNELS[source.channels] || 0);
      if (source.sampler) ctx.gl.bindSampler(0, source.sampler);
      if (place.tests) {
        ctx.gl.enable(ctx.gl.DEPTH_TEST);
        ctx.gl.depthFunc(ctx.gl.LEQUAL);
        ctx.gl.depthMask(false);
      }
      if (mesh) {
        ctx.gl.bindVertexArray(mesh.shape);
        ctx.gl.drawElements(ctx.gl.TRIANGLES, mesh.count, ctx.gl.UNSIGNED_SHORT, 0);
        ctx.gl.bindVertexArray(null);
      } else {
        ctx.gl.bindVertexArray(ctx.passShape);
        ctx.gl.drawArrays(ctx.gl.TRIANGLE_STRIP, 0, 4);
      }
      if (place.tests) {
        ctx.gl.disable(ctx.gl.DEPTH_TEST);
        ctx.gl.depthMask(true);
      }
      if (source.sampler) ctx.gl.bindSampler(0, null);
    }

    // A puppet drawn part by part, in its order: a part that shows only within others through
    // a mask of those others, drawn first as they are bent at the moment.
    function putClipped(source, place, tint, how, mesh) {
      var framebuffer = ctx.bound.draw;
      var view = ctx.bound.viewport.slice();
      var width = view[2], height = view[3];
      var clippedBy = {};
      mesh.clips.forEach(function (clip) { clippedBy[clip.part] = clip; });
      function useMesh(program) {
        ctx.gl.useProgram(program.program);
        ctx.gl.activeTexture(ctx.gl.TEXTURE0);
        ctx.gl.bindTexture(ctx.gl.TEXTURE_2D, source.texture);
        ctx.gl.uniform1i(program.uniforms.u_Texture.location, 0);
        placeIn(program, place);
        ctx.gl.uniform4fv(program.uniforms.u_Tint.location, tint);
        ctx.gl.uniform4fv(program.uniforms.u_Frame.location, source.frame || [0, 0, 1, 1]);
        ctx.gl.uniform1i(program.uniforms.u_Channels.location, ctx.CHANNELS[source.channels] || 0);
      }
      function blended(always) {
        if (how === 'normal' && !always) {
          ctx.gl.disable(ctx.gl.BLEND);
          return;
        }
        ctx.gl.enable(ctx.gl.BLEND);
        if (how === 'additive') ctx.gl.blendFuncSeparate(ctx.gl.SRC_ALPHA, ctx.gl.ONE, ctx.gl.ZERO, ctx.gl.ONE);
        else ctx.gl.blendFuncSeparate(ctx.gl.SRC_ALPHA, ctx.gl.ONE_MINUS_SRC_ALPHA, ctx.gl.ONE, ctx.gl.ONE_MINUS_SRC_ALPHA);
      }
      function drawPart(index) {
        var part = mesh.parts[index];
        if (part && part[1] > 0) ctx.gl.drawElements(ctx.gl.TRIANGLES, part[1], ctx.gl.UNSIGNED_SHORT, part[0] * 2);
      }
      ctx.gl.bindVertexArray(mesh.shape);
      for (var index = 0; index < mesh.parts.length; index++) {
        var clip = clippedBy[index];
        if (!clip) {
          useMesh(ctx.meshProgram);
          blended(false);
          drawPart(index);
          continue;
        }
        var mask = ctx.acquire(width, height);
        ctx.gl.bindFramebuffer(ctx.gl.FRAMEBUFFER, mask.framebuffer);
        ctx.gl.viewport(0, 0, width, height);
        ctx.gl.clearColor(0, 0, 0, 0);
        ctx.gl.clear(ctx.gl.COLOR_BUFFER_BIT);
        ctx.gl.useProgram(ctx.clipMaskProgram.program);
        var byPicture = !!(clip.picture && clip.picture.ready && clip.picture.layers[0]);
        ctx.gl.activeTexture(ctx.gl.TEXTURE0);
        ctx.gl.bindTexture(ctx.gl.TEXTURE_2D, byPicture ? clip.picture.layers[0].texture : source.texture);
        ctx.gl.uniform1i(ctx.clipMaskProgram.uniforms.u_Texture.location, 0);
        ctx.gl.uniform1i(ctx.clipMaskProgram.uniforms.u_Alpha.location, byPicture ? 0 : 1);
        placeIn(ctx.clipMaskProgram, place);
        ctx.gl.enable(ctx.gl.BLEND);
        ctx.gl.blendEquation(ctx.gl.MAX);
        clip.masks.forEach(drawPart);
        ctx.gl.blendEquation(ctx.gl.FUNC_ADD);
        ctx.gl.bindFramebuffer(ctx.gl.FRAMEBUFFER, framebuffer);
        ctx.gl.viewport(view[0], view[1], view[2], view[3]);
        useMesh(ctx.clippedProgram);
        ctx.gl.activeTexture(ctx.gl.TEXTURE2);
        ctx.gl.bindTexture(ctx.gl.TEXTURE_2D, mask.texture);
        ctx.gl.uniform1i(ctx.clippedProgram.uniforms.u_Mask.location, 2);
        ctx.gl.uniform2f(ctx.clippedProgram.uniforms.u_MaskSize.location, width, height);
        blended(true);
        drawPart(index);
        ctx.gl.activeTexture(ctx.gl.TEXTURE0);
        ctx.release(mask);
      }
      ctx.gl.bindVertexArray(null);
    }

    // The whole of a target, as the matrix that fills it.
    ctx.FILL = new Float32Array([2, 0, 0, 0, -2, 0, 0, 0, 1]);

    return { times: times, matrixOf: matrixOf, nudged: nudged, placeOf: placeOf, worldPlaceOf: worldPlaceOf, put: put };
  }

