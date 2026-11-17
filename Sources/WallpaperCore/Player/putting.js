  // Putting a picture on the scene: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePutting(ctx) {
    var link = ctx.link;
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
    ctx.grabProgram = link([
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
    ctx.placeProgram = link(placeVertex, sampleLines.concat(['void main() { color = picture(); }']).join('\n'), 'the player\'s own shader');
    // Layers drawn one over another onto nothing leave their colors multiplied by how solid
    // the result is. Effects, and the scene, take colors that are not: this divides them back.
    ctx.straightProgram = link([
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
    ctx.meshProgram = link(meshVertex, sampleLines.concat(['void main() { color = picture(); }']).join('\n'), 'the player\'s own shader');
    // A part of a puppet that shows only within others — an iris within the white of its eye —
    // is drawn through a mask of those others: where a picture says they count, or where they
    // are not see-through.
    ctx.clipMaskProgram = link(meshVertex, [
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
    ctx.clippedProgram = link(meshVertex, sampleLines.concat([
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
    ctx.blendProgram = link(placeVertex, blendFragment, 'the player\'s own shader');
    ctx.meshBlendProgram = link(meshVertex, blendFragment, 'the player\'s own shader');

    return {};
  }

