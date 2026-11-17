  // ------------------------------------------------------------------ headers
  //
  // What the shaders of a scene include and Wallpaper Engine keeps to itself. These are written
  // anew to the same names; a function a shader calls that is not here fails to compile, and
  // the effect it belongs to is left out.

  var BLENDS = [
    // 1–5: darker
    'min(A, B)',
    'A * B',
    '1.0 - min(vec3(1.0), (1.0 - A) / max(B, vec3(0.0001)))',
    'max(A + B - 1.0, vec3(0.0))',
    '(dot(A, vec3(0.299, 0.587, 0.114)) < dot(B, vec3(0.299, 0.587, 0.114)) ? A : B)',
    // 6–10: lighter
    'max(A, B)',
    '1.0 - (1.0 - A) * (1.0 - B)',
    'min(vec3(1.0), A / max(1.0 - B, vec3(0.0001)))',
    'A + B',
    '(dot(A, vec3(0.299, 0.587, 0.114)) > dot(B, vec3(0.299, 0.587, 0.114)) ? A : B)',
    // 11–17: contrast
    'mix(2.0 * A * B, 1.0 - 2.0 * (1.0 - A) * (1.0 - B), step(0.5, A))',
    'mix(2.0 * A * B + A * A * (1.0 - 2.0 * B), sqrt(A) * (2.0 * B - 1.0) + 2.0 * A * (1.0 - B), step(0.5, B))',
    'mix(2.0 * A * B, 1.0 - 2.0 * (1.0 - A) * (1.0 - B), step(0.5, B))',
    'mix(1.0 - min(vec3(1.0), (1.0 - A) / max(2.0 * B, vec3(0.0001))), min(vec3(1.0), A / max(2.0 * (1.0 - B), vec3(0.0001))), step(0.5, B))',
    'clamp(A + 2.0 * B - 1.0, 0.0, 1.0)',
    'mix(min(A, 2.0 * B), max(A, 2.0 * B - 1.0), step(0.5, B))',
    'step(vec3(1.0), A + B)',
    // 18–20: difference
    'abs(A - B)',
    'A + B - 2.0 * A * B',
    'max(A - B, vec3(0.0))',
    // 21–25
    'min(vec3(1.0), A * A / max(1.0 - B, vec3(0.0001)))',
    'min(vec3(1.0), B * B / max(1.0 - A, vec3(0.0001)))',
    'min(A, B) - max(A, B) + 1.0',
    '(A + B) * 0.5',
    '1.0 - abs(1.0 - A - B)',
    // 26–29: one of hue, saturation and lightness taken from the one, the rest from the other
    'wallaeroSetLum(wallaeroSetSat(B, wallaeroSat(A)), wallaeroLum(A))',
    'wallaeroSetLum(wallaeroSetSat(A, wallaeroSat(B)), wallaeroLum(A))',
    'wallaeroSetLum(B, wallaeroLum(A))',
    'wallaeroSetLum(A, wallaeroLum(B))',
    // 30: tinted — as light as it was, in the other's color
    'max(A.r, max(A.g, A.b)) * B',
    // 31: added, without an upper end. A scene of three videos shows it: white writing on
    // black laid over a face with this mode leaves the face and adds the writing.
    'A + B',
    // 32: what light effects — caustics — come set to. Taken for adding too; Wallpaper
    // Engine's own list was not at hand.
    'A + B'
  ];

  // The blend modes by name, as the header image editors' formulas are passed around in has
  // them: for one value (ending in f) and for a color, and one that weighs a blend in.
  var BLEND_NAMES = [
    '#define BlendLinearDodgef BlendAddf',
    '#define BlendLinearBurnf BlendSubstractf',
    '#define BlendAddf(base, blend) min((base) + (blend), 1.0)',
    '#define BlendSubstractf(base, blend) max((base) + (blend) - 1.0, 0.0)',
    '#define BlendLightenf(base, blend) max((blend), (base))',
    '#define BlendDarkenf(base, blend) min((blend), (base))',
    '#define BlendLinearLightf(base, blend) ((blend) < 0.5 ? BlendLinearBurnf((base), (2.0 * (blend))) : BlendLinearDodgef((base), (2.0 * ((blend) - 0.5))))',
    '#define BlendScreenf(base, blend) (1.0 - ((1.0 - (base)) * (1.0 - (blend))))',
    '#define BlendOverlayf(base, blend) ((base) < 0.5 ? (2.0 * (base) * (blend)) : (1.0 - 2.0 * (1.0 - (base)) * (1.0 - (blend))))',
    '#define BlendSoftLightf(base, blend) (((blend) < 0.5) ? (2.0 * (base) * (blend) + (base) * (base) * (1.0 - 2.0 * (blend))) : (sqrt(base) * (2.0 * (blend) - 1.0) + 2.0 * (base) * (1.0 - (blend))))',
    '#define BlendColorDodgef(base, blend) (((blend) >= 1.0) ? (blend) : min((base) / (1.0 - (blend)), 1.0))',
    '#define BlendColorBurnf(base, blend) (((blend) <= 0.0) ? (blend) : max((1.0 - ((1.0 - (base)) / (blend))), 0.0))',
    '#define BlendVividLightf(base, blend) (((blend) < 0.5) ? BlendColorBurnf((base), (2.0 * (blend))) : BlendColorDodgef((base), (2.0 * ((blend) - 0.5))))',
    '#define BlendPinLightf(base, blend) (((blend) < 0.5) ? BlendDarkenf((base), (2.0 * (blend))) : BlendLightenf((base), (2.0 * ((blend) - 0.5))))',
    '#define BlendHardMixf(base, blend) ((BlendVividLightf((base), (blend)) < 0.5) ? 0.0 : 1.0)',
    '#define BlendReflectf(base, blend) (((blend) >= 1.0) ? (blend) : min((base) * (base) / (1.0 - (blend)), 1.0))',
    '#define Blend(base, blend, funcf) vec3(funcf((base).r, (blend).r), funcf((base).g, (blend).g), funcf((base).b, (blend).b))',
    '#define BlendNormal(base, blend) (blend)',
    '#define BlendLighten BlendLightenf',
    '#define BlendDarken BlendDarkenf',
    '#define BlendMultiply(base, blend) ((base) * (blend))',
    '#define BlendAverage(base, blend) (((base) + (blend)) / 2.0)',
    '#define BlendAdd(base, blend) min((base) + (blend), vec3(1.0))',
    '#define BlendSubstract(base, blend) max((base) + (blend) - vec3(1.0), vec3(0.0))',
    '#define BlendSubtract BlendSubstract',
    '#define BlendDifference(base, blend) abs((base) - (blend))',
    '#define BlendNegation(base, blend) (vec3(1.0) - abs(vec3(1.0) - (base) - (blend)))',
    '#define BlendExclusion(base, blend) ((base) + (blend) - 2.0 * (base) * (blend))',
    '#define BlendScreen(base, blend) Blend((base), (blend), BlendScreenf)',
    '#define BlendOverlay(base, blend) Blend((base), (blend), BlendOverlayf)',
    '#define BlendSoftLight(base, blend) Blend((base), (blend), BlendSoftLightf)',
    '#define BlendHardLight(base, blend) BlendOverlay((blend), (base))',
    '#define BlendColorDodge(base, blend) Blend((base), (blend), BlendColorDodgef)',
    '#define BlendColorBurn(base, blend) Blend((base), (blend), BlendColorBurnf)',
    '#define BlendLinearDodge BlendAdd',
    '#define BlendLinearBurn BlendSubstract',
    '#define BlendLinearLight(base, blend) Blend((base), (blend), BlendLinearLightf)',
    '#define BlendVividLight(base, blend) Blend((base), (blend), BlendVividLightf)',
    '#define BlendPinLight(base, blend) Blend((base), (blend), BlendPinLightf)',
    '#define BlendHardMix(base, blend) Blend((base), (blend), BlendHardMixf)',
    '#define BlendReflect(base, blend) Blend((base), (blend), BlendReflectf)',
    '#define BlendGlow(base, blend) BlendReflect((blend), (base))',
    '#define BlendPhoenix(base, blend) (min((base), (blend)) - max((base), (blend)) + vec3(1.0))',
    '#define BlendOpacity(base, blend, F, O) (F((base), (blend)) * (O) + (base) * (1.0 - (O)))'
  ];
  // What the blend modes above are worked out with.
  var BLEND_HELPERS = [
    'float wallaeroLum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }',
    'float wallaeroSat(vec3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }',
    'vec3 wallaeroSetLum(vec3 c, float l) {',
    '  c += l - wallaeroLum(c);',
    '  float least = min(c.r, min(c.g, c.b));',
    '  float most = max(c.r, max(c.g, c.b));',
    '  if (least < 0.0) c = l + (c - l) * l / max(l - least, 0.0001);',
    '  if (most > 1.0) c = l + (c - l) * (1.0 - l) / max(most - l, 0.0001);',
    '  return c;',
    '}',
    'vec3 wallaeroSetSat(vec3 c, float s) {',
    '  float least = min(c.r, min(c.g, c.b));',
    '  float most = max(c.r, max(c.g, c.b));',
    '  return most > least ? (c - least) * s / (most - least) : vec3(0.0);',
    '}'
  ];

  var HEADERS = {
    'common.h': [
      '#define M_PI 3.14159265359',
      '#define M_PI_HALF 1.57079632679',
      '#define M_PI_2 6.28318530718',
      '#define SQRT_2 1.41421356237',
      '#define SQRT_3 1.73205080756',
      'vec3 hsv2rgb(vec3 c) {',
      '  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);',
      '  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);',
      '  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);',
      '}',
      'vec3 rgb2hsv(vec3 c) {',
      '  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);',
      '  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));',
      '  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));',
      '  float d = q.x - min(q.w, q.y);',
      '  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);',
      '}',
      'vec2 rotateVec2(vec2 v, float r) {',
      '  vec2 cs = vec2(cos(r), sin(r));',
      '  return vec2(v.x * cs.x - v.y * cs.y, v.x * cs.y + v.y * cs.x);',
      '}',
      'float greyscale(vec3 color) { return dot(color, vec3(0.299, 0.587, 0.114)); }'
    ].join('\n'),

    // The blend modes go by number, in the order image editors list them.
    'common_blending.h': BLEND_NAMES.concat(BLEND_HELPERS, ['vec3 wallaeroBlend(vec3 A, vec3 B) {'], BLENDS.map(function (formula, index) {
      return '#if BLENDMODE == ' + (index + 1) + '\n  return ' + formula + ';\n#endif';
    })).concat([
      '  return B;',
      '}',
      'vec3 ApplyBlending(float blendMode, vec3 A, vec3 B, float opacity) {',
      '  return mix(A, wallaeroBlend(A, B), opacity);',
      '}'
    ]).join('\n'),

    // How an effect's result is put together with the picture it was made of: in place of it,
    // blended over it, under it, or only where the picture is not. Not in packages; written by
    // what the names say and by the settings scenes give it.
    'common_composite.h': [
      '#include "common_blending.h"',
      'uniform vec3 g_CompositeColor; // {"material":"compositecolor","label":"ui_editor_properties_composite_color","type":"color","default":"1 1 1"}',
      'uniform float g_CompositeAlpha; // {"material":"compositealpha","label":"ui_editor_properties_composite_alpha","default":1,"range":[0,2]}',
      'uniform vec2 g_CompositeOffset; // {"material":"compositeoffset","label":"ui_editor_properties_composite_offset","default":"0 0"}',
      'vec2 ApplyCompositeOffset(vec2 coords, vec2 resolution) {',
      '#if COMPOSITE == 0',
      '  return coords;',
      '#else',
      '  return coords - g_CompositeOffset / max(resolution, vec2(1.0));',
      '#endif',
      '}',
      'vec4 ApplyComposite(vec4 base, vec4 made) {',
      '#if COMPOSITE == 0',
      '  return made;',
      '#else',
      '#if COMPOSITEMONO',
      '  made.rgb = g_CompositeColor;',
      '#else',
      '  made.rgb *= g_CompositeColor;',
      '#endif',
      '  made.a = clamp(made.a * g_CompositeAlpha, 0.0, 1.0);',
      '#if COMPOSITE == 2',
      '  float under = base.a + made.a * (1.0 - base.a);',
      '  return vec4((base.rgb * base.a + made.rgb * made.a * (1.0 - base.a)) / max(under, 0.0001), under);',
      '#elif COMPOSITE == 3',
      '  return vec4(made.rgb, made.a * (1.0 - base.a));',
      '#else',
      '  return vec4(ApplyBlending(BLENDMODE, mix(made.rgb, base.rgb, base.a), made.rgb, made.a), base.a + made.a * (1.0 - base.a));',
      '#endif',
      '#endif',
      '}'
    ].join('\n'),

    // The mapping of the unit square onto any four-cornered shape, as a matrix.
    'common_perspective.h': [
      'mat3 squareToQuad(vec2 p0, vec2 p1, vec2 p2, vec2 p3) {',
      '  vec2 d1 = p1 - p2;',
      '  vec2 d2 = p3 - p2;',
      '  vec2 sum = p0 - p1 + p2 - p3;',
      '  float det = d1.x * d2.y - d2.x * d1.y;',
      '  float g = 0.0;',
      '  float h = 0.0;',
      '  if (abs(det) > 1.0e-10) {',
      '    g = (sum.x * d2.y - d2.x * sum.y) / det;',
      '    h = (d1.x * sum.y - sum.x * d1.y) / det;',
      '  }',
      '  return mat3(p1.x - p0.x + g * p1.x, p1.y - p0.y + g * p1.y, g,',
      '              p3.x - p0.x + h * p3.x, p3.y - p0.y + h * p3.y, h,',
      '              p0.x, p0.y, 1.0);',
      '}'
    ].join('\n'),

    'common_fragment.h': [
      'vec3 DecompressNormal(vec4 normal) {',
      '  vec2 xy = normal.ag * 2.0 - 1.0;',
      '  return vec3(xy, sqrt(clamp(1.0 - dot(xy, xy), 0.0, 1.0)));',
      '}',
      'vec4 DecompressNormalWithMask(vec4 normal) {',
      '  vec2 xy = normal.ag * 2.0 - 1.0;',
      '  return vec4(xy, sqrt(clamp(1.0 - dot(xy, xy), 0.0, 1.0)), normal.r);',
      '}',
      'float ConvertSampleR8(vec4 color) { return color.r; }',
      'vec4 ConvertTexture0Format(vec4 color) { return color; }'
    ].join('\n'),

    'common_vertex.h': [
      'mat3 BuildTangentSpace(vec3 normal, vec4 signedTangent) {',
      '  vec3 tangent = signedTangent.xyz;',
      '  vec3 bitangent = cross(normal, tangent) * signedTangent.w;',
      '  return mat3(tangent, bitangent, normal);',
      '}',
      'mat3 BuildTangentSpace(mat3 modelTransform, vec3 normal, vec4 signedTangent) {',
      '  vec3 tangent = normalize(modelTransform * signedTangent.xyz);',
      '  vec3 n = normalize(modelTransform * normal);',
      '  return mat3(tangent, cross(n, tangent) * signedTangent.w, n);',
      '}'
    ].join('\n'),

    // Blurs along one direction: the picture in the shader's first slot, looked at in several
    // places to both sides and weighed as a bell curve weighs them. They are written as
    // replacements of text, not as functions: a shader includes this before it names its
    // pictures. The ones ending in `a` keep how solid the picture is; the others give its
    // color alone.
    'common_blur.h': (function () {
      // A blur over so many pixels, as a middle weight and pairs of distance and weight.
      function blur(name, middle, pairs) {
        var sum = 'texSample2D(g_Texture0, (u)) * ' + middle;
        pairs.forEach(function (pair) {
          sum += ' + (texSample2D(g_Texture0, (u) + (d) * ' + pair[0] + ') + texSample2D(g_Texture0, (u) - (d) * ' + pair[0] + ')) * ' + pair[1];
        });
        return ['#define ' + name + 'a(u, d) (' + sum + ')', '#define ' + name + '(u, d) ((' + sum + ').rgb)'];
      }
      // A blur around a middle point `c`: the picture looked at where `u` lands when turned
      // about it by so much, or as far the other way along the line it moved, each place
      // with a weight. `a` turns by a fortieth of a radian for each unit.
      function radial(name, taps) {
        var away = '((u) - (c))';
        var sum = taps.map(function (tap) {
          var moved = '(wallaeroTurn(' + away + ', ' + tap[0] + ' * (a) * 0.025) - ' + away + ')';
          return 'texSample2D(g_Texture0, (u) ' + (tap[2] < 0 ? '- ' : '+ ') + moved + ') * ' + tap[1];
        }).join(' + ');
        return '#define ' + name + '(u, c, a) (' + sum + ')';
      }
      return [
        'vec2 wallaeroTurn(vec2 v, float r) { return vec2(v.x * cos(r) - v.y * sin(r), v.x * sin(r) + v.y * cos(r)); }'
      ].concat(
        blur('blur13', '0.1964825501511404', [['1.411764705882353', '0.2969069646728344'], ['3.2941176470588234', '0.09447039785044732'],
                                              ['5.176470588235294', '0.010381362401148057']]),
        blur('blur7', '0.2270270270', [['1.3846153846', '0.3162162162'], ['3.2307692308', '0.0702702703']]),
        blur('blur3', '0.29411764705882354', [['1.3333333333333333', '0.35294117647058826']]),
        radial('blurRadial13a', [['0.0', '0.1976406528809576', 1],
                                 ['1.4091998770852122', '0.2959855056006557', 1], ['1.4091998770852122', '0.2959855056006557', -1],
                                 ['3.2979348079914822', '0.0935333619980593', 1], ['3.2979348079914822', '0.0935333619980593', -1],
                                 ['5.2062900776825969', '0.0116608059608062', 1], ['5.2062900776825969', '0.0116608059608062', -1]]),
        radial('blurRadial7a', [['2.3515644035337887', '0.2028175528299753', 1], ['0.469433779698372', '0.4044856614512112', 1],
                                ['-1.4091998770852121', '0.3213933537319605', 1], ['-3.0', '0.0713034319868530', 1]]),
        radial('blurRadial3a', [['0.0', '0.5', 1], ['1.0', '0.25', 1], ['1.0', '0.25', -1]])
      ).join('\n');
    })()
  };

