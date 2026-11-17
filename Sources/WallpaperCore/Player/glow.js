  // Glow: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeGlow(ctx) {
    var gl = ctx.gl, link = ctx.link, passShape = ctx.passShape, acquire = ctx.acquire, release = ctx.release, general = ctx.general, put = ctx.put, FILL = ctx.FILL;
    // --- Glow -----------------------------------------------------------------
    //
    // A scene may glow where it is bright (bloom): what is brighter than a threshold is taken
    // out small, blurred and added back over the scene.

    ctx.fillVertex = [
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec2 a_TexCoord;',
      'out vec2 v_Uv;',
      'void main() {',
      '  v_Uv = a_TexCoord;',
      '  gl_Position = vec4(a_TexCoord * 2.0 - 1.0, 0.0, 1.0);',
      '}'
    ].join('\n');
    var brightProgram = link(ctx.fillVertex, [
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
    var blurProgram = link(ctx.fillVertex, [
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
      var quarter = acquire(ctx.sceneTarget.width / 4, ctx.sceneTarget.height / 4);
      var small = [acquire(ctx.sceneTarget.width / 8, ctx.sceneTarget.height / 8), acquire(ctx.sceneTarget.width / 8, ctx.sceneTarget.height / 8)];
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
      fill(quarter, brightProgram, ctx.sceneTarget);
      gl.uniform2f(brightProgram.uniforms.u_Texel.location, 1 / ctx.sceneTarget.width, 1 / ctx.sceneTarget.height);
      gl.uniform1f(brightProgram.uniforms.u_Threshold.location, threshold);
      gl.uniform1f(brightProgram.uniforms.u_Strength.location, strength);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      fill(small[0], blurProgram, quarter);
      gl.uniform2f(blurProgram.uniforms.u_Step.location, 1 / small[0].width, 0);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      fill(small[1], blurProgram, small[0]);
      gl.uniform2f(blurProgram.uniforms.u_Step.location, 0, 1 / small[0].height);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.sceneTarget.framebuffer);
      gl.viewport(0, 0, ctx.sceneTarget.width, ctx.sceneTarget.height);
      var tint = numbers(general.bloomtint, 3, 1);
      put({ texture: small[1].texture }, FILL, [tint[0], tint[1], tint[2], 1], 'additive');
      release(quarter);
      small.forEach(release);
    }

    return { glow: glow };
  }

