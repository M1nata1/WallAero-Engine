import Foundation

/// The player of Wallpaper Engine's own scenes: the script a scene's page loads to draw one as
/// its background. It is written into the folder of every scene that holds such a scene, next
/// to the runtime, and rewritten when the app has a newer one. See `WallpaperEngineScene` for
/// how a scene's files get there.
public enum WallpaperEngineRuntime {
    public static let fileName = "engine.js"

    /// The script. While the player is being worked on it can be taken from a file instead,
    /// named by `WALLAERO_ENGINE_JS`, so that a change shows without building the app.
    public static var script: String {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["WALLAERO_ENGINE_JS"],
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        #endif
        return source
    }

    static let source = #"""
    // WallAero Engine: the player of Wallpaper Engine's own scenes.
    // Generated and rewritten when the app updates.
    //
    // A scene of Wallpaper Engine's is a list of objects on a canvas: pictures, each with a chain of
    // effects drawn by shaders; particles; sounds. The scene's own files say all of it — they lie in
    // the table the page loads before this script — and this draws them with WebGL. The shaders are
    // the scene's own, written in Wallpaper Engine's dialect of GLSL; they are translated to the
    // GLSL this browser compiles the way Wallpaper Engine itself does it on phones. What a scene
    // leaves to Wallpaper Engine — the headers its shaders include, the textures it names without
    // bringing them — is made here.
    (function () {
      'use strict';

      // What the player has to say of the scene: what it left out, and why.
      var notes = [];
      function note(text) {
        if (notes.length < 100 && notes.indexOf(text) < 0) notes.push(text);
      }

      // ------------------------------------------------------------------ values

      // The wallpaper's settings as they are set now, by the names the scene knows them under.
      var properties = {};

      // A value as a scene gives it. One that a setting of the wallpaper, an animation or a script
      // stands behind is written as an object with the value inside; a setting, if the wallpaper
      // has it, takes the place of that value. A setting may also stand behind a yes or no by
      // being at one certain choice.
      function plain(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value) || !('value' in value || 'user' in value)) return value;
        var user = value.user;
        var name = user && typeof user === 'object' ? user.name : user;
        if (typeof name === 'string' && Object.prototype.hasOwnProperty.call(properties, name)) {
          var given = properties[name];
          if (user && typeof user === 'object' && user.condition !== undefined) return String(given) === String(user.condition);
          return given;
        }
        return value.value;
      }

      function number(value, fallback) {
        value = plain(value);
        if (typeof value === 'number' && isFinite(value)) return value;
        if (typeof value === 'string' && value.trim() !== '' && isFinite(Number(value))) return Number(value);
        if (typeof value === 'boolean') return value ? 1 : 0;
        return fallback;
      }

      // Several numbers written as one text, "990.000 540.000 0.000" or "0.0, 1.0", or one number
      // for them all.
      function numbers(value, count, fallback) {
        value = plain(value);
        var list = [];
        if (typeof value === 'number') {
          for (var i = 0; i < count; i++) list.push(value);
        } else if (typeof value === 'string') {
          list = value.split(/[\s,]+/).filter(function (part) { return part !== ''; }).map(Number).filter(function (n) { return isFinite(n); });
        } else if (Array.isArray(value)) {
          list = value.map(Number).filter(function (n) { return isFinite(n); });
        }
        var result = [];
        for (var j = 0; j < count; j++) {
          result.push(j < list.length ? list[j] : (Array.isArray(fallback) ? fallback[j] : fallback));
        }
        return result;
      }

      function flag(value, fallback) {
        value = plain(value);
        if (value === 'true' || value === '1') return true;
        if (value === 'false' || value === '0') return false;
        return typeof value === 'boolean' ? value : (typeof value === 'number' ? value !== 0 : fallback);
      }

      function key(name) {
        return String(name).replace(/\\/g, '/').toLowerCase();
      }

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
          return [].concat(
            blur('blur13', '0.1964825501511404', [['1.411764705882353', '0.2969069646728344'], ['3.2941176470588234', '0.09447039785044732'],
                                                  ['5.176470588235294', '0.010381362401148057']]),
            blur('blur7', '0.2270270270', [['1.3846153846', '0.3162162162'], ['3.2307692308', '0.0702702703']]),
            blur('blur3', '0.29411764705882354', [['1.3333333333333333', '0.35294117647058826']])
          ).join('\n');
        })()
      };

      // ------------------------------------------------------------------ shaders
      //
      // A shader of Wallpaper Engine's is GLSL of the old kind with names of its own on top, written
      // loosely: whole numbers wherever fractions are meant. Wallpaper Engine turns them into the
      // strict GLSL of phones by making every whole number a fraction, and so does this:
      //
      //   – `#include`, `#if` and the like are resolved here, with the switches of the effect;
      //   – whole numbers and the type for them become fractions, except where the language wants
      //     a whole number, between square brackets;
      //   – the old names for inputs and outputs, and Wallpaper Engine's own for functions, become
      //     the ones of this GLSL.

      // Every switch a shader declares in a comment, `// [COMBO] {...}`, and what its uniforms say
      // of themselves in theirs.
      // What a shader says of itself is written by hand, as JSON and nearly JSON: a number may
      // begin with noughts, a list end with a comma.
      function loose(text) {
        try {
          return JSON.parse(text);
        } catch (error) {
          return JSON.parse(text.replace(/([\[,:]\s*)0+(\d)/g, '$1$2').replace(/,(\s*[}\]])/g, '$1'));
        }
      }

      // The headers a shader includes, and those they include, as they are written: what they
      // say of their settings in comments counts like what the shader says.
      function headersOf(source, files, seen) {
        seen = seen || {};
        var texts = [];
        String(source).replace(/^[ \t]*#[ \t]*include[ \t]+["<]([^">]+)[">]/gm, function (whole, named) {
          var header = key(named.trim());
          if (seen[header]) return whole;
          seen[header] = true;
          var text = HEADERS[header] !== undefined ? HEADERS[header] : (files || {})['shaders/' + header];
          if (typeof text === 'string') texts.push(text, headersOf(text, files, seen));
          return whole;
        });
        return texts.join('\n');
      }

      // `types`: the type each uniform is declared with, "float" or "vec3".
      function annotations(source) {
        var result = { combos: {}, uniforms: {}, types: {} };
        source.replace(/\r\n?/g, '\n').split('\n').forEach(function (line) {
          var combo = /^\s*\/\/\s*\[\s*(?:COMBO|COMBO_OFF|OFF_COMBO)\s*\]\s*(\{.*\})\s*$/.exec(line);
          if (combo) {
            try {
              var declared = loose(combo[1]);
              if (declared && declared.combo) result.combos[declared.combo] = number(declared['default'], 0);
            } catch (error) {}
            return;
          }
          var uniform = /^\s*uniform\s+(\w+)\s+(\w+)\s*(?:\[[^\]]*\])?\s*;\s*\/\/\s*(\{.*\})\s*$/.exec(line);
          if (uniform) {
            try {
              result.uniforms[uniform[2]] = loose(uniform[3]);
              result.types[uniform[2]] = uniform[1];
            } catch (error) {}
          }
        });
        return result;
      }

      // Without its comments, and with the line endings of Windows, where these files are written,
      // made plain.
      function stripComments(source) {
        return source.replace(/\r\n?/g, '\n').replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, '');
      }

      // The value of the condition of an `#if`: whole-number arithmetic, comparisons, `defined`.
      // A name that stands for nothing counts as zero.
      function evaluate(expression, defines, depth) {
        var tokens = expression.match(/0[xX][0-9a-fA-F]+|\d+\.?\d*|[A-Za-z_]\w*|&&|\|\||==|!=|<=|>=|[-+*\/%()!<>]/g) || [];
        var at = 0;
        function valueOf(name) {
          if (!(name in defines) || depth > 8) return 0;
          var text = String(defines[name]).trim();
          if (text === '') return 1;
          if (/^-?\d+(\.\d*)?$/.test(text)) return Number(text);
          return evaluate(text, defines, depth + 1);
        }
        function primary() {
          var token = tokens[at++];
          if (token === undefined) return 0;
          if (token === '(') {
            var inner = or();
            at++;
            return inner;
          }
          if (token === '!') return primary() ? 0 : 1;
          if (token === '-') return -primary();
          if (token === '+') return primary();
          if (token === 'defined') {
            var name = tokens[at++];
            if (name === '(') {
              name = tokens[at++];
              at++;
            }
            return name in defines ? 1 : 0;
          }
          if (/^[A-Za-z_]/.test(token)) return valueOf(token);
          return /^0[xX]/.test(token) ? parseInt(token, 16) : Number(token);
        }
        function product() {
          var left = primary();
          while (tokens[at] === '*' || tokens[at] === '/' || tokens[at] === '%') {
            var operator = tokens[at++];
            var right = primary();
            left = operator === '*' ? left * right : (right === 0 ? 0 : (operator === '/' ? Math.trunc(left / right) : left % right));
          }
          return left;
        }
        function sum() {
          var left = product();
          while (tokens[at] === '+' || tokens[at] === '-') {
            left = tokens[at++] === '+' ? left + product() : left - product();
          }
          return left;
        }
        function comparison() {
          var left = sum();
          while (['<', '>', '<=', '>=', '==', '!='].indexOf(tokens[at]) >= 0) {
            var operator = tokens[at++];
            var right = sum();
            left = (operator === '<' ? left < right : operator === '>' ? left > right : operator === '<=' ? left <= right :
                    operator === '>=' ? left >= right : operator === '==' ? left === right : left !== right) ? 1 : 0;
          }
          return left;
        }
        function and() {
          var left = comparison();
          while (tokens[at] === '&&') {
            at++;
            var right = comparison();
            left = left && right ? 1 : 0;
          }
          return left;
        }
        function or() {
          var left = and();
          while (tokens[at] === '||') {
            at++;
            var right = and();
            left = left || right ? 1 : 0;
          }
          return left;
        }
        return or();
      }

      // Resolves includes and conditions. `defines` is added to by the shader's own `#define`s;
      // those stay in the text too, for the compiler to put in where they are used.
      function preprocess(source, defines, files, included) {
        var out = [];
        var stack = []; // of { outer: whether the lines around are live, taken: a branch was, live }
        function live() {
          return stack.length === 0 || stack[stack.length - 1].live;
        }
        stripComments(source).replace(/\\\r?\n/g, ' ').split('\n').forEach(function (line) {
          var directive = /^\s*#\s*(\w+)\s*(.*)$/.exec(line);
          if (!directive) {
            if (live()) out.push(line);
            return;
          }
          var name = directive[1];
          var rest = directive[2].trim();
          var top = stack[stack.length - 1];
          if (name === 'if' || name === 'ifdef' || name === 'ifndef') {
            var outer = live();
            var met = outer && (name === 'if' ? evaluate(rest, defines, 0) !== 0 : (rest.split(/\s/)[0] in defines) === (name === 'ifdef'));
            stack.push({ outer: outer, taken: met, live: met });
          } else if (name === 'elif' && top) {
            top.live = top.outer && !top.taken && evaluate(rest, defines, 0) !== 0;
            top.taken = top.taken || top.live;
          } else if (name === 'else' && top) {
            top.live = top.outer && !top.taken;
            top.taken = true;
          } else if (name === 'endif') {
            stack.pop();
          } else if (!live()) {
            return;
          } else if (name === 'include') {
            var header = key(rest.replace(/["<>]/g, '').trim());
            if (included[header]) return;
            included[header] = true;
            var text = HEADERS[header];
            if (text === undefined) text = files['shaders/' + header];
            if (text === undefined) {
              // Left for the compiler to trip over: the effect is then left out, with the reason.
              out.push('#error the header ' + header + ' is not known');
              return;
            }
            out.push(preprocess(text, defines, files, included));
          } else if (name === 'define') {
            var define = /^(\w+)(\([^)]*\))?\s*(.*)$/.exec(rest);
            if (!define) return;
            // One with arguments is the compiler's to deal with; a plain one is also kept here,
            // for the conditions that ask about it.
            if (!define[2]) defines[define[1]] = define[3];
            out.push('#define ' + define[1] + (define[2] || '') + ' ' + define[3]);
          } else if (name === 'undef') {
            delete defines[rest.split(/\s/)[0]];
            out.push('#undef ' + rest);
          }
          // #pragma, #extension, #version and the like have no meaning here.
        });
        return out.join('\n');
      }

      // Names this GLSL keeps for itself that a shader may have taken for something of its own.
      var TAKEN = ['sample', 'input', 'output', 'filter', 'common', 'partition', 'active', 'smooth', 'flat', 'half', 'fixed',
                   'packed', 'resource', 'shared', 'texture', 'cast', 'namespace', 'using', 'external', 'interface', 'long',
                   'short', 'double', 'unsigned', 'superp', 'patch', 'centroid', 'layout', 'precise', 'inline', 'noinline',
                   'static', 'extern', 'public', 'union', 'enum', 'typedef', 'template', 'this', 'goto', 'class', 'asm'];
      var NAMES = {
        texSample2D: 'texture', texSample2DLod: 'textureLod', texture2D: 'texture', texture2DLod: 'textureLod',
        textureCube: 'texture', frac: 'fract', atan2: 'atan', lerp: 'mix', ddx: 'dFdx', ddy: 'dFdy',
        ivec2: 'vec2', ivec3: 'vec3', ivec4: 'vec4', uvec2: 'vec2', uvec3: 'vec3', uvec4: 'vec4',
        float2: 'vec2', float3: 'vec3', float4: 'vec4', float3x3: 'mat3', float4x4: 'mat4', gl_FragColor: 'wallaero_FragColor'
      };
      var TOKEN = /([A-Za-z_]\w*)|((?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)[fFuUlL]*)|(\s+)|([\s\S])/g;

      function wholeNumber(text) {
        return /^(0[xX][0-9a-fA-F]+|\d+)[uUlL]*$/.test(text);
      }

      // A number as a fraction.
      function fraction(text) {
        text = text.replace(/[fFuUlL]+$/, '');
        if (/^0[xX]/.test(text)) return parseInt(text, 16) + '.0';
        if (/[eE]/.test(text)) return text;
        if (text.indexOf('.') < 0) return text + '.0';
        if (text.charAt(0) === '.') return '0' + text;
        return text.charAt(text.length - 1) === '.' ? text + '0' : text;
      }

      // Turns the text between `from` and `to` of the tokens into this GLSL.
      function rewrite(tokens, from, to, stage) {
        var out = '';
        for (var i = from; i < to; i++) {
          var token = tokens[i];
          if (token.kind === 'name') {
            var name = token.text;
            if (name === 'int' || name === 'uint') {
              // As a type it is the type of fractions; called, it cuts the fraction off a number.
              var next = i + 1;
              while (next < to && tokens[next].kind === 'space') next++;
              out += next < to && tokens[next].text === '(' ? 'trunc' : 'float';
            } else if (name === 'attribute') {
              out += 'in';
            } else if (name === 'varying') {
              out += stage === 'vertex' ? 'out' : 'in';
            } else if (name === 'main' && stage === 'vertex') {
              out += 'wallaero_main';
            } else if (NAMES.hasOwnProperty(name)) {
              out += NAMES[name];
            } else if (TAKEN.indexOf(name) >= 0) {
              // A shader written for this GLSL already may call `texture` as the function it is.
              var after = i + 1;
              while (after < to && tokens[after].kind === 'space') after++;
              out += name === 'texture' && after < to && tokens[after].text === '(' ? name : name + '_';
            } else {
              out += name;
            }
          } else if (token.kind === 'number') {
            out += fraction(token.text);
          } else if (token.text === '[') {
            // What is between square brackets counts things, and stays a whole number.
            var depth = 1;
            var close = i + 1;
            while (close < to && depth > 0) {
              if (tokens[close].text === '[') depth++;
              if (tokens[close].text === ']') depth--;
              close++;
            }
            var inside = tokens.slice(i + 1, close - 1).filter(function (inner) { return inner.kind !== 'space'; });
            if (inside.length === 0) {
              out += '[]';
            } else if (inside.length === 1 && inside[0].kind === 'number' && wholeNumber(inside[0].text)) {
              out += '[' + parseInt(inside[0].text, /^0[xX]/.test(inside[0].text) ? 16 : 10) + ']';
            } else {
              out += '[int(' + rewrite(tokens, i + 1, close - 1, stage) + ')]';
            }
            i = close - 1;
          } else {
            out += token.text;
          }
        }
        return out;
      }

      function tokenize(text) {
        var tokens = [];
        var match;
        TOKEN.lastIndex = 0;
        while ((match = TOKEN.exec(text)) !== null) {
          tokens.push({ kind: match[1] ? 'name' : match[2] ? 'number' : match[3] ? 'space' : 'other', text: match[0] });
        }
        return tokens;
      }

      // --- Shaders a browser refuses and Wallpaper Engine takes -------------------------------
      //
      // Wallpaper Engine hands its shaders to Direct3D, which is lenient where a browser is not:
      // a function given vectors of different sizes works with the smaller, and a vector put
      // where a smaller one or a single number belongs loses its last parts. Scenes are written
      // against that. When a shader does not compile, what the compiler says is turned into the
      // change that lets it through, and it is tried again.

      // Functions that take vectors part by part, with how many values each takes.
      var LENIENT = { mix: 3, clamp: 3, smoothstep: 3, min: 2, max: 2, pow: 2, step: 2, mod: 2, atan: 2, dot: 2, distance: 2, reflect: 2 };
      var TO_ONE_NUMBER = { dot: true, distance: true };

      // The function under a name of its own, for every mixture of sizes: all its values are cut
      // to the smallest vector among them, and single numbers are spread over that.
      function overloads(name) {
        var types = ['', 'float', 'vec2', 'vec3', 'vec4'];
        var lines = [];
        function all(sizes) {
          if (sizes.length < LENIENT[name]) {
            for (var size = 1; size <= 4; size++) all(sizes.concat([size]));
            return;
          }
          var vectors = sizes.filter(function (each) { return each > 1; });
          var least = vectors.length ? Math.min.apply(null, vectors) : 1;
          var takes = sizes.map(function (each, index) { return types[each] + ' v' + index; });
          var gives = sizes.map(function (each, index) { return each === least ? 'v' + index : types[least] + '(v' + index + ')'; });
          lines.push((TO_ONE_NUMBER[name] ? 'float' : types[least]) + ' wallaero_' + name + '(' + takes.join(', ') + ') { return ' +
                     name + '(' + gives.join(', ') + '); }');
        }
        all([]);
        return lines.join('\n');
      }

      // How many numbers a kind of value has, as the compiler names it: 1 for a single number,
      // 2 to 4 for a vector, 'bool' for a yes or no, 0 for anything else.
      function sizeNamed(kind) {
        var parts = /(\d)-component vector of float/.exec(kind);
        if (parts) return Number(parts[1]);
        if (/\bbool\b/.test(kind)) return 'bool';
        return /\bfloat\b/.test(kind) && !/matrix|vector/.test(kind) ? 1 : 0;
      }

      // The value that stands right before a place in a line, or right after it: a name with
      // what is taken of it, a call, a number, or something in brackets. Gives where it starts
      // and ends.
      function valueBefore(text, at) {
        var end = at;
        while (end > 0 && text.charAt(end - 1) === ' ') end--;
        var start = end;
        while (start > 0) {
          var letter = text.charAt(start - 1);
          if (/[\w.]/.test(letter)) {
            start--;
          } else if (letter === ')' || letter === ']') {
            var depth = 0;
            do {
              var inner = text.charAt(start - 1);
              if (inner === ')' || inner === ']') depth++;
              if (inner === '(' || inner === '[') depth--;
              start--;
            } while (start > 0 && depth > 0);
          } else {
            break;
          }
        }
        return [start, end];
      }

      function valueAfter(text, at) {
        var start = at;
        while (start < text.length && text.charAt(start) === ' ') start++;
        var end = start;
        if (text.charAt(end) === '-' || text.charAt(end) === '+') end++;
        while (end < text.length) {
          var letter = text.charAt(end);
          if (/[\w.]/.test(letter)) {
            end++;
          } else if (letter === '(' || letter === '[') {
            var depth = 0;
            do {
              var inner = text.charAt(end);
              if (inner === '(' || inner === '[') depth++;
              if (inner === ')' || inner === ']') depth--;
              end++;
            } while (end < text.length && depth > 0);
          } else {
            break;
          }
        }
        return [start, end];
      }

      // How many numbers a value written out has, where that can be told from how it is written
      // or from how its name was declared; 0 where it cannot.
      function sizeWritten(text, declared) {
        text = text.trim();
        var taken = /\.([xyzwrgbastpq]{1,4})$/.exec(text);
        if (taken) return taken[1].length;
        var made = /^(vec([234])|float)\s*\(/.exec(text);
        if (made && valueAfter(text, 0)[1] === text.length) return made[2] ? Number(made[2]) : 1;
        if (/^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i.test(text)) return 1;
        return /^\w+$/.test(text) && typeof declared[text] === 'number' ? declared[text] : 0;
      }

      // How many numbers each name of a shader stands for, by how it is declared.
      function declaredIn(source) {
        var declared = {};
        source.replace(/\b(float|vec([234]))\s+(\w+)\s*[;,=)\[]/g, function (whole, kind, parts, name) {
          var size = parts ? Number(parts) : 1;
          // A name declared as two kinds in two places tells nothing.
          declared[name] = declared[name] === undefined || declared[name] === size ? size : 'unsure';
          return whole;
        });
        return declared;
      }

      // A translated shader changed so that what its compiler complained of is gone; null when
      // none of the complaints is one that can be mended. `messages` is all it said of one line,
      // `line` that line, counted from one.
      function mend(source, messages, line) {
        messages = Array.isArray(messages) ? messages : [messages];
        for (var which = 0; which < messages.length; which++) {
          var mended = mendOne(source, String(messages[which]), line);
          if (mended !== null) return mended;
        }
        return null;
      }

      // A value the vertex shader hands to the fragment shader, or a setting both of them take,
      // declared by the two with different sizes: Direct3D hands on what fits, and makes each
      // shader by itself. The smaller declaration is made as large as the other, and where that
      // shader used the value whole, it uses the parts it knew of. What the vertex shader then
      // never sets of a value it hands on is nought. Gives both shaders, or null.
      function mendPair(vertex, fragment, messages) {
        var named = null;
        (Array.isArray(messages) ? messages : [messages]).some(function (message) {
          named = /Types of (varying|uniform) '(\w+)' differ/.exec(String(message));
          return !!named;
        });
        if (!named) return null;
        var name = named[2];
        var handed = named[1] === 'varying';
        var declared = new RegExp('^([ \\t]*' + (handed ? '(?:flat[ \\t]+|smooth[ \\t]+)?(?:in|out)' : 'uniform') +
                                  '[ \\t]+(?:(?:highp|mediump|lowp)[ \\t]+)?)(float|vec[234])([ \\t]+' + name + '[ \\t]*;)', 'm');
        var first = declared.exec(vertex), second = declared.exec(fragment);
        if (!first || !second) return null;
        function sizeOf(type) { return type === 'float' ? 1 : Number(type.charAt(3)); }
        var sizes = [sizeOf(first[2]), sizeOf(second[2])];
        if (sizes[0] === sizes[1]) return null;
        var larger = sizes[0] > sizes[1] ? first[2] : second[2];
        var parts = '.' + 'xyzw'.slice(0, Math.min(sizes[0], sizes[1]));
        function widened(source, found, sets) {
          var whole = new RegExp('\\b' + name + '\\b(?![ \\t]*\\.)', 'g');
          var before = source.slice(0, found.index).replace(whole, name + parts);
          var after = source.slice(found.index + found[0].length).replace(whole, name + parts);
          if (sets) {
            after = after.replace(/void\s+main\s*\(\s*(?:void)?\s*\)\s*\{/, function (opened) { return opened + ' ' + name + ' = ' + larger + '(0.0);'; });
          }
          return before + found[1] + larger + found[3] + after;
        }
        return sizes[0] < sizes[1] ? { vertex: widened(vertex, first, handed), fragment: fragment }
                                   : { vertex: vertex, fragment: widened(fragment, second, false) };
      }

      function mendOne(source, message, line) {
        // A value handed to the fragment shader that it changes: it changes a copy of its own,
        // made as its work begins.
        var handed = /l-value required \(can't modify an input "(\w+)"\)/.exec(message);
        if (handed) {
          var own = 'wallaero_own_' + handed[1];
          var given = new RegExp('^[ \\t]*(?:flat[ \\t]+|smooth[ \\t]+)?in[ \\t]+(?:(?:highp|mediump|lowp)[ \\t]+)?(float|vec[234])[ \\t]+' + handed[1] + '[ \\t]*;', 'm').exec(source);
          if (!given || source.indexOf(own) >= 0) return null;
          var upTo = given.index + given[0].length;
          var rest = source.slice(upTo).replace(new RegExp('\\b' + handed[1] + '\\b', 'g'), own);
          var opened = /void\s+main\s*\(\s*(?:void)?\s*\)\s*\{/.exec(rest);
          if (!opened) return null;
          var at = opened.index + opened[0].length;
          return source.slice(0, upTo) + ' ' + given[1] + ' ' + own + ';' + rest.slice(0, at) + ' ' + own + ' = ' + handed[1] + ';' + rest.slice(at);
        }
        // A number where a yes or no is asked for, in "a ? b : c" or "if (a)": Direct3D takes
        // anything but nought for a yes.
        if (/boolean expression expected/.test(message)) {
          var asking = source.split('\n');
          var row = asking[line - 1];
          if (!(line > 0) || row === undefined) return null;
          function plainNumber(asked) {
            return asked !== '' && !/[<>!]=?|==|&&|\|\||\b(true|false)\b|!= 0\.0\)/.test(asked);
          }
          for (var mark = 0; mark < row.length; mark++) {
            if (row.charAt(mark) !== '?') continue;
            // What is asked: back from the mark to where that expression begins.
            var nested = 0, from = mark - 1;
            for (; from >= 0; from--) {
              var sign = row.charAt(from);
              if (sign === ')' || sign === ']') nested++;
              else if (sign === '(' || sign === '[') {
                if (nested === 0) break;
                nested--;
              } else if (nested === 0 && (sign === ',' || sign === ';' || sign === '?' || sign === ':' || sign === '{' ||
                         (sign === '=' && row.charAt(from + 1) !== '=' && '=!<>'.indexOf(row.charAt(from - 1)) < 0))) break;
            }
            var lead = /^\s*(?:return\b)?\s*/.exec(row.slice(from + 1, mark))[0].length;
            var asked = row.slice(from + 1 + lead, mark).trim();
            if (!plainNumber(asked)) continue;
            asking[line - 1] = row.slice(0, from + 1 + lead) + '((' + asked + ') != 0.0) ' + row.slice(mark);
            return asking.join('\n');
          }
          var whether = /\b(if|while)\s*\(/.exec(row);
          if (whether) {
            var open = whether.index + whether[0].length, deep = 1, close = open;
            for (; close < row.length && deep > 0; close++) {
              if (row.charAt(close) === '(') deep++;
              if (row.charAt(close) === ')') deep--;
            }
            var inside = row.slice(open, close - 1).trim();
            if (deep === 0 && plainNumber(inside)) {
              asking[line - 1] = row.slice(0, open) + '(' + inside + ') != 0.0' + row.slice(close - 1);
              return asking.join('\n');
            }
          }
          return null;
        }
        // A function given vectors of different sizes.
        var call = /'(\w+)' : no matching overloaded function found/.exec(message);
        if (call) {
          if (!LENIENT[call[1]] || source.indexOf('wallaero_' + call[1] + '(') >= 0) return null;
          var body = source.replace(new RegExp('\\b' + call[1] + '\\s*\\(', 'g'), 'wallaero_' + call[1] + '(');
          var mark = body.indexOf('\n#define log10(');
          if (mark < 0) return null;
          var after = body.indexOf('\n', mark + 1) + 1;
          return body.slice(0, after) + overloads(call[1]) + '\n' + body.slice(after);
        }
        var lines = source.split('\n');
        var text = lines[line - 1];
        if (!(line > 0) || text === undefined) return null;

        // Two values of different sizes joined by a sign: the larger is cut to the smaller. A yes
        // or no joined to a number counts as one or nought.
        var joined = /'([-+*\/%])' : wrong operand types.*left-hand operand of type '([^']*)' and a right operand of type '([^']*)'/.exec(message);
        if (joined && joined[1] === '%') {
          // What is left of a division. A translated shader counts in fractions, which have no
          // sign for that; the function does what the sign did.
          for (var sign = 0; sign < text.length; sign++) {
            if (text.charAt(sign) !== '%' || text.charAt(sign + 1) === '=') continue;
            var divided = valueBefore(text, sign), by = valueAfter(text, sign + 1);
            if (divided[0] === divided[1] || by[0] === by[1]) continue;
            lines[line - 1] = text.slice(0, divided[0]) + 'fmod(' + text.slice(divided[0], divided[1]) + ', ' + text.slice(by[0], by[1]) + ')' + text.slice(by[1]);
            return lines.join('\n');
          }
          return null;
        }
        if (joined) {
          var left = sizeNamed(joined[2]), right = sizeNamed(joined[3]);
          if (left === 0 || right === 0 || left === right) return null;
          var declared = declaredIn(source);
          var best = null;
          for (var at = 0; at < text.length; at++) {
            if (text.charAt(at) !== joined[1] || text.charAt(at + 1) === '=' || text.charAt(at + 1) === joined[1] || text.charAt(at - 1) === joined[1]) continue;
            var before = valueBefore(text, at), behind = valueAfter(text, at + 1);
            // A sign with nothing before it belongs to the number after it.
            if (before[0] === before[1] || behind[0] === behind[1] || /^(\d+\.?\d*|\.\d+)[eE]$/.test(text.slice(before[0], before[1]))) continue;
            var first = sizeWritten(text.slice(before[0], before[1]), declared), second = sizeWritten(text.slice(behind[0], behind[1]), declared);
            var wantsLeft = left === 'bool' ? 0 : left, wantsRight = right === 'bool' ? 0 : right;
            if ((first !== 0 && wantsLeft !== 0 && first !== wantsLeft) || (second !== 0 && wantsRight !== 0 && second !== wantsRight)) continue;
            var sure = (first !== 0 ? 1 : 0) + (second !== 0 ? 1 : 0);
            if (!best || sure > best.sure) best = { sure: sure, before: before, behind: behind };
          }
          if (!best) return null;
          var cut, where;
          if (left === 'bool' || right === 'bool') {
            cut = 'float';
            where = left === 'bool' ? best.before : best.behind;
          } else {
            if (left === 1 || right === 1) return null;
            cut = 'vec' + Math.min(left, right);
            where = left > right ? best.before : best.behind;
          }
          lines[line - 1] = text.slice(0, where[0]) + cut + '(' + text.slice(where[0], where[1]) + ')' + text.slice(where[1]);
          return lines.join('\n');
        }

        // A vector put where a smaller one or a single number belongs loses its last parts.
        var convert = /cannot convert from '([^']*)' to '([^']*)'/.exec(message);
        if (convert) {
          var from = sizeNamed(convert[1]), to = sizeNamed(convert[2]);
          // A vector cannot grow; a yes or no counts as one or nought, and a number as a yes if it is not nought.
          if (to === 0 || from === 0 || (typeof from === 'number' && typeof to === 'number' && from !== 1 && from < to)) return null;
          var type = to === 'bool' ? 'bool' : (to === 1 ? 'float' : 'vec' + to);
          // The statements of the line, one after another: the first that gives a value to
          // something of that size, and has not been mended already, is mended.
          var names = declaredIn(source);
          var start = 0;
          var kind = 0; // the size of the names a statement declares, one after another
          while (start < text.length) {
            var depth = 0, stop = -1, sign = -1;
            for (var i = start; i < text.length; i++) {
              var letter = text.charAt(i);
              if (letter === '(' || letter === '[') depth++;
              if (letter === ')' || letter === ']') depth--;
              // A statement ends here, or one of the names it declares does.
              if ((letter === ';' || letter === ',') && depth === 0) {
                stop = i;
                break;
              }
              if (letter === '=' && depth === 0 && sign < 0 && text.charAt(i + 1) !== '=' && '=!<>'.indexOf(text.charAt(i - 1)) < 0) sign = i;
            }
            if (stop < 0) break;
            // What is given a value, or only named: "vec3 b", "a.rgb", "b".
            var target = text.slice(start, sign >= 0 ? sign : stop).replace(/[-+*\/]$/, '').trim();
            var made = /^(?:const\s+)?(float|vec[234])\s+\w+$/.exec(target);
            if (made) kind = made[1] === 'float' ? 1 : Number(made[1].charAt(3));
            if (sign >= 0) {
              var size = made || (kind !== 0 && /^\w+$/.test(target)) ? kind : sizeWritten(target, names);
              var given = text.slice(sign + 1, stop).trim();
              var done = given.indexOf(type + '(') === 0 && valueAfter(given, 0)[1] === given.length;
              if ((size === 0 || size === to) && given !== '' && !done) {
                lines[line - 1] = text.slice(0, sign + 1) + ' ' + type + '(' + given + ')' + text.slice(stop);
                return lines.join('\n');
              }
            }
            if (text.charAt(stop) === ';') kind = 0;
            start = stop + 1;
          }
          return null;
        }
        return null;
      }

      // The whole of a shader, ready to compile. `defines` are the switches of the effect.
      function translate(source, stage, defines, files) {
        // A value declared with parts named after it ("varying vec4 v_Size.xy;") is that value
        // whole: Wallpaper Engine reads the name and passes over the rest.
        source = String(source).replace(/^([ \t]*(?:varying|uniform|attribute)[ \t]+\w+[ \t]+\w+)\.[xyzwrgbastpq]+([ \t]*;)/gm, '$1$2');
        var table = { GLSL: 1 };
        Object.keys(defines).forEach(function (name) { table[name] = defines[name]; });
        var pieces = [];
        var plainLines = [];
        // Lines that are not directives are rewritten together: a bracket may open on one line
        // and close on another.
        function flush() {
          if (!plainLines.length) return;
          var tokens = tokenize(plainLines.join('\n'));
          pieces.push(rewrite(tokens, 0, tokens.length, stage));
          plainLines = [];
        }
        preprocess(source, table, files, {}).split('\n').forEach(function (line) {
          var define = /^(\s*#define\s+\w+(?:\([^)]*\))?)(.*)$/.exec(line);
          if (define) {
            flush();
            var tokens = tokenize(define[2]);
            pieces.push(define[1] + rewrite(tokens, 0, tokens.length, stage));
          } else if (/^\s*#/.test(line)) {
            flush();
            pieces.push(line);
          } else {
            plainLines.push(line);
          }
        });
        flush();

        var head = [
          '#version 300 es',
          'precision highp float;',
          'precision highp int;',
          'precision highp sampler2D;',
          '#define mul(x, y) ((y) * (x))',
          '#define saturate(x) clamp(x, 0.0, 1.0)',
          '#define CAST2(x) vec2(x)',
          '#define CAST3(x) vec3(x)',
          '#define CAST4(x) vec4(x)',
          '#define CAST3X3(x) mat3(x)',
          '#define fmod(x, y) ((x) - (y) * trunc((x) / (y)))',
          '#define log10(x) (log2(x) * 0.30102999566)'
        ];
        // The switches are also names a shader may use as numbers.
        Object.keys(defines).forEach(function (name) {
          head.push('#define ' + name + ' ' + fraction(String(Number(defines[name]) || 0)));
        });
        var tail = [];
        if (stage === 'vertex') {
          // A picture is kept with its top row first, in a texture and in what is drawn into one
          // alike; the shader is written for a screen that has its top row at the top.
          head.push('uniform float wallaero_Flip;');
          tail.push('void main() {', '  wallaero_main();', '  gl_Position.y *= wallaero_Flip;', '}');
        } else {
          head.push('out vec4 wallaero_FragColor;');
        }
        return head.concat(pieces, tail).join('\n') + '\n';
      }

      // ------------------------------------------------------------------ values that change
      //
      // A value of a scene — where a picture is, how see-through, what a text says — is written
      // plainly, or with something behind it: a setting of the wallpaper, an animation that changes
      // it over time, a script that works it out. All three come as an object with the plain value
      // inside, which is what `plain` gives; the rest is done here.

      // An animation of a value: for each of its numbers a list of moments, with the number at
      // each and how the curve leaves one moment and arrives at the next.
      //
      //   { c0: [{ frame, value, front: { enabled, magic, x, y }, back: { enabled, magic, x, y } }, …],
      //     c1: …, options: { fps, length, mode, wraploop }, relative }
      //
      // A handle says how the curve leaves or reaches its moment: by how much the curve has moved
      // on, in frames and in value, where the handle ends. A handle marked `magic` is left to the
      // player: the curve passes its moment smoothly, level where the value turns back. With
      // `wraploop` the curve goes on from its last moment to its first, one length later, so that
      // a loop has no jump. With `relative` the numbers are counted from what the scene says.
      function curveOf(animation) {
        if (!animation || typeof animation !== 'object') return null;
        var channels = [];
        Object.keys(animation).forEach(function (name) {
          var channel = /^c(\d+)$/.exec(name);
          if (!channel || !Array.isArray(animation[name])) return;
          var keys = animation[name].filter(function (each) { return each && isFinite(Number(each.frame)) && isFinite(Number(each.value)); })
            .map(function (each) {
              function handle(said) {
                return said && said.enabled ? { x: Number(said.x) || 0, y: Number(said.y) || 0, magic: said.magic === true } : null;
              }
              return { frame: Number(each.frame), value: Number(each.value), front: handle(each.front), back: handle(each.back) };
            })
            .sort(function (first, second) { return first.frame - second.frame; });
          if (keys.length) channels[Number(channel[1])] = keys;
        });
        if (!channels.length) return null;
        var options = animation.options || {};
        var rate = Number(options.fps) > 0 ? Number(options.fps) : 30;
        var length = Number(options.length) > 0 ? Number(options.length) : 0;
        channels.forEach(function (keys) { length = Math.max(length, options.length > 0 ? 0 : keys[keys.length - 1].frame); });
        var mode = String(options.mode || 'loop').toLowerCase();
        var wraps = mode === 'loop' && options.wraploop === true && length > 0;
        var relative = animation.relative === true;

        // The moment before or after one of a curve's: with `wraploop`, round the end.
        function beside(keys, index, by) {
          var other = keys[index + by];
          if (other) return other;
          if (!wraps) return null;
          other = by > 0 ? keys[0] : keys[keys.length - 1];
          return { frame: other.frame + by * length, value: other.value, front: other.front, back: other.back };
        }

        // How steeply a curve left to the player passes a moment: as the line between the moments
        // on both sides of it runs, and level where the value turns back or the curve ends.
        function slope(keys, index) {
          var here = keys[index], before = beside(keys, index, -1), after = beside(keys, index, 1);
          if (!before || !after || after.frame === before.frame) return 0;
          if ((here.value - before.value) * (after.value - here.value) <= 0) return 0;
          return (after.value - before.value) / (after.frame - before.frame);
        }

        function along(first, second, third, fourth, t) {
          var rest = 1 - t;
          return rest * rest * rest * first + 3 * rest * rest * t * second + 3 * rest * t * t * third + t * t * t * fourth;
        }

        // The value between two moments; `fromIndex` and `toIndex` say which of the curve's they are.
        function span(keys, from, to, fromIndex, toIndex, frame) {
          var wide = to.frame - from.frame;
          if (!(wide > 0)) return to.value;
          if (!from.front && !to.back) return from.value + (to.value - from.value) * (frame - from.frame) / wide;
          // A curve drawn with two handles; the moment along it is looked for, then its height.
          var x1 = from.frame, y1 = from.value, x2 = to.frame, y2 = to.value;
          if (from.front) {
            x1 += from.front.magic ? wide / 3 : Math.max(0, Math.min(wide, from.front.x));
            y1 += from.front.magic ? slope(keys, fromIndex) * wide / 3 : from.front.y;
          }
          if (to.back) {
            x2 += to.back.magic ? -wide / 3 : Math.max(-wide, Math.min(0, to.back.x));
            y2 += to.back.magic ? -slope(keys, toIndex) * wide / 3 : to.back.y;
          }
          var low = 0, high = 1;
          for (var step = 0; step < 24; step++) {
            var middle = (low + high) / 2;
            if (along(from.frame, x1, x2, to.frame, middle) < frame) low = middle;
            else high = middle;
          }
          return along(from.value, y1, y2, to.value, (low + high) / 2);
        }

        function at(keys, frame) {
          var last = keys.length - 1;
          if (frame <= keys[0].frame) {
            var before = beside(keys, 0, -1);
            return before && frame < keys[0].frame ? span(keys, before, keys[0], last, 0, frame) : keys[0].value;
          }
          if (frame >= keys[last].frame) {
            var after = beside(keys, last, 1);
            return after && frame > keys[last].frame ? span(keys, keys[last], after, last, 0, frame) : keys[last].value;
          }
          var index = 1;
          while (keys[index].frame < frame) index++;
          return span(keys, keys[index - 1], keys[index], index - 1, index, frame);
        }

        // The numbers at a moment, in seconds since the scene began; a number the animation
        // does not have is left as `base` has it.
        function valueAt(seconds, base) {
          var frame = seconds * rate;
          if (length > 0) {
            if (mode === 'mirror') {
              frame = frame % (length * 2);
              if (frame > length) frame = length * 2 - frame;
            } else if (mode === 'single') {
              frame = Math.min(frame, length);
            } else {
              frame = frame % length;
            }
          }
          var result = base.slice();
          channels.forEach(function (keys, index) {
            if (index < result.length) result[index] = (relative ? base[index] : 0) + at(keys, frame);
          });
          return result;
        }
        // How it plays: the name scripts know it by, whether it waits for one of them to start
        // it, and the value of the same object whose animation it plays along with.
        valueAt.called = typeof options.name === 'string' ? options.name : '';
        valueAt.startsPaused = options.startpaused === true;
        valueAt.mode = mode;
        valueAt.rate = rate;
        valueAt.frames = length;
        valueAt.follows = options.parent && typeof options.parent === 'object' && typeof options.parent.key === 'string' ? options.parent.key : '';
        return valueAt;
      }

      // --- What a script of a scene has to work with ----------------------------------------
      //
      // Scripts are written against Wallpaper Engine's own names: vectors, a few helpers, and
      // objects that stand for the scene, the layer and the app. Those are made here to the same
      // names, as its documentation gives them.

      function vector(names) {
        function Vector(first) {
          var given = arguments;
          var self = this;
          if (typeof first === 'string') {
            var parts = first.trim().split(/\s+/).map(Number);
            names.forEach(function (name, index) { self[name] = isFinite(parts[index]) ? parts[index] : 0; });
          } else if (first && typeof first === 'object') {
            names.forEach(function (name, index) {
              self[name] = typeof first[name] === 'number' ? first[name] : (typeof given[index] === 'number' && index > 0 ? given[index] : 0);
            });
          } else if (given.length <= 1) {
            // One number stands for them all.
            names.forEach(function (name) { self[name] = typeof first === 'number' ? first : 0; });
          } else {
            names.forEach(function (name, index) { self[name] = typeof given[index] === 'number' ? given[index] : 0; });
          }
        }
        var proto = Vector.prototype;
        function each(self, other, change) {
          var result = new Vector(0);
          names.forEach(function (name) {
            result[name] = change(self[name], other !== null && typeof other === 'object' ? (typeof other[name] === 'number' ? other[name] : 0) : other);
          });
          return result;
        }
        function both(change) {
          return function (other) { return each(this, other === undefined ? 0 : other, change); };
        }
        function alone(change) {
          return function () { return each(this, 0, change); };
        }
        proto.copy = alone(function (value) { return value; });
        proto.add = both(function (value, other) { return value + other; });
        proto.subtract = both(function (value, other) { return value - other; });
        proto.multiply = both(function (value, other) { return value * other; });
        proto.divide = both(function (value, other) { return value / other; });
        proto.min = both(Math.min);
        proto.max = both(Math.max);
        proto.mod = both(function (value, other) { return value - other * Math.floor(value / other); });
        proto.step = both(function (value, edge) { return value < edge ? 0 : 1; });
        proto.negate = alone(function (value) { return -value; });
        proto.abs = alone(Math.abs);
        proto.sign = alone(Math.sign);
        proto.round = alone(Math.round);
        proto.floor = alone(Math.floor);
        proto.ceil = alone(Math.ceil);
        proto.fract = alone(function (value) { return value - Math.floor(value); });
        proto.dot = function (other) {
          var self = this, sum = 0;
          names.forEach(function (name) { sum += self[name] * other[name]; });
          return sum;
        };
        proto.lengthSqr = function () { return this.dot(this); };
        proto.length = function () { return Math.sqrt(this.dot(this)); };
        proto.distanceSqr = function (other) { return this.subtract(other).lengthSqr(); };
        proto.distance = function (other) { return this.subtract(other).length(); };
        proto.normalize = function () {
          var length = this.length();
          return length > 0 ? this.divide(length) : this.copy();
        };
        proto.equals = function (other) {
          var self = this;
          return !!other && names.every(function (name) { return self[name] === other[name]; });
        };
        proto.isFinite = function () {
          var self = this;
          return names.every(function (name) { return isFinite(self[name]); });
        };
        proto.mix = function (other, amount) {
          var self = this;
          var result = new Vector(0);
          names.forEach(function (name) {
            var share = typeof amount === 'object' ? amount[name] : amount;
            result[name] = self[name] + (other[name] - self[name]) * share;
          });
          return result;
        };
        proto.clamp = function (least, most) { return this.max(least).min(most); };
        proto.smoothStep = function (least, most) {
          var self = this;
          var result = new Vector(0);
          names.forEach(function (name) {
            var low = typeof least === 'object' ? least[name] : least, high = typeof most === 'object' ? most[name] : most;
            var share = Math.max(0, Math.min(1, (self[name] - low) / (high - low || 1)));
            result[name] = share * share * (3 - 2 * share);
          });
          return result;
        };
        proto.reflect = function (normal) { return this.subtract(normal.multiply(2 * this.dot(normal))); };
        proto.project = function (other) { return other.multiply(this.dot(other) / (other.lengthSqr() || 1)); };
        proto.angleBetween = function (other) {
          return Math.acos(Math.max(-1, Math.min(1, this.dot(other) / ((this.length() * other.length()) || 1)))) * 180 / Math.PI;
        };
        proto.toString = function () {
          var self = this;
          return names.map(function (name) { return self[name]; }).join(' ');
        };
        return Vector;
      }

      var Vec2 = vector(['x', 'y']);
      var Vec3 = vector(['x', 'y', 'z']);
      var Vec4 = vector(['x', 'y', 'z', 'w']);
      // Angles are in degrees, as everywhere in scripts.
      Vec2.prototype.angle = function () { return Math.atan2(this.y, this.x) * 180 / Math.PI; };
      Vec2.prototype.perpendicular = function () { return new Vec2(-this.y, this.x); };
      Vec2.prototype.rotate = function (angle) {
        var cos = Math.cos(angle * Math.PI / 180), sin = Math.sin(angle * Math.PI / 180);
        return new Vec2(this.x * cos - this.y * sin, this.x * sin + this.y * cos);
      };
      Vec3.prototype.cross = function (other) {
        return new Vec3(this.y * other.z - this.z * other.y, this.z * other.x - this.x * other.z, this.x * other.y - this.y * other.x);
      };

      var MODULES = {
        WEMath: {
          smoothStep: function (least, most, value) {
            var share = Math.max(0, Math.min(1, (value - least) / (most - least || 1)));
            return share * share * (3 - 2 * share);
          },
          mix: function (first, second, share) { return first + (second - first) * share; },
          deg2rad: Math.PI / 180,
          rad2deg: 180 / Math.PI
        },
        WEVector: {
          angleVector2: function (angle) { return new Vec2(Math.cos(angle * Math.PI / 180), Math.sin(angle * Math.PI / 180)); },
          vectorAngle2: function (direction) { return Math.atan2(direction.y, direction.x) * 180 / Math.PI; }
        },
        WEColor: {
          // Colors go from 0 to 1 a part; the hue too.
          rgb2hsv: function (rgb) {
            var most = Math.max(rgb.x, rgb.y, rgb.z), least = Math.min(rgb.x, rgb.y, rgb.z);
            var spread = most - least;
            var hue = 0;
            if (spread > 0) {
              if (most === rgb.x) hue = ((rgb.y - rgb.z) / spread) % 6;
              else if (most === rgb.y) hue = (rgb.z - rgb.x) / spread + 2;
              else hue = (rgb.x - rgb.y) / spread + 4;
            }
            hue = (hue / 6 + 1) % 1;
            return new Vec3(hue, most > 0 ? spread / most : 0, most);
          },
          hsv2rgb: function (hsv) {
            function part(shift) {
              var k = (shift + hsv.x * 6) % 6;
              return hsv.z - hsv.z * hsv.y * Math.max(0, Math.min(k, 4 - k, 1));
            }
            return new Vec3(part(5), part(3), part(1));
          },
          normalizeColor: function (rgb) { return new Vec3(rgb.x / 255, rgb.y / 255, rgb.z / 255); },
          expandColor: function (rgb) { return new Vec3(rgb.x * 255, rgb.y * 255, rgb.z * 255); }
        }
      };

      // Anything a script asks of an object that is not made here does nothing and gives
      // nothing, rather than stopping the script.
      function lenient(target) {
        if (typeof Proxy !== 'function') return target;
        return new Proxy(target, {
          get: function (object, name) {
            if (name in object || typeof name !== 'string') return object[name];
            return function () {};
          }
        });
      }

      // The names a script knows the state of the music by. What plays on the Mac is not told to
      // scenes, so a script that asks finds it stopped.
      var MEDIA_PLAYBACK = { PLAYBACK_STOPPED: 0, PLAYBACK_PLAYING: 1, PLAYBACK_PAUSED: 2 };

      // Matrices as scripts have them: numbers by columns, the place in the last one, angles in
      // degrees, turned as the objects of a scene are (about x, then y, then z).
      var DEGREE = Math.PI / 180;
      function times4(a, b) {
        var r = new Array(16);
        for (var column = 0; column < 4; column++) {
          for (var row = 0; row < 4; row++) {
            var sum = 0;
            for (var k = 0; k < 4; k++) sum += a[k * 4 + row] * b[column * 4 + k];
            r[column * 4 + row] = sum;
          }
        }
        return r;
      }
      function euler4(x, y, z) {
        var cx = Math.cos(x * DEGREE), sx = Math.sin(x * DEGREE), cy = Math.cos(y * DEGREE), sy = Math.sin(y * DEGREE);
        var cz = Math.cos(z * DEGREE), sz = Math.sin(z * DEGREE);
        return [cz * cy, sz * cy, -sy, 0,
                cz * sy * sx - sz * cx, sz * sy * sx + cz * cx, cy * sx, 0,
                cz * sy * cx + sz * sx, sz * sy * cx - cz * sx, cy * cx, 0,
                0, 0, 0, 1];
      }
      function Mat4(values) {
        this.m = Array.isArray(values) && values.length === 16 ? values.slice() : [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
      }
      Mat4.identity = function () { return new Mat4(); };
      Mat4.fromTranslation = function (v) { return new Mat4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, v.x || 0, v.y || 0, v.z || 0, 1]); };
      Mat4.fromScale = function (v) {
        var x = typeof v === 'number' ? v : v.x, y = typeof v === 'number' ? v : v.y, z = typeof v === 'number' ? v : (v.z === undefined ? 1 : v.z);
        return new Mat4([x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1]);
      };
      Mat4.fromRotation = function (angle, axis) {
        var length = Math.sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z) || 1;
        var x = axis.x / length, y = axis.y / length, z = axis.z / length;
        var c = Math.cos(angle * DEGREE), s = Math.sin(angle * DEGREE), t = 1 - c;
        return new Mat4([t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0,
                         t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0,
                         t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0,
                         0, 0, 0, 1]);
      };
      Mat4.fromEuler = function (x, y, z) {
        if (x && typeof x === 'object') return new Mat4(euler4(x.x, x.y, x.z));
        return new Mat4(euler4(x || 0, y || 0, z || 0));
      };
      Mat4.fromBasis = function (right, up, forward) {
        return new Mat4([right.x, right.y, right.z, 0, up.x, up.y, up.z, 0, forward.x, forward.y, forward.z, 0, 0, 0, 0, 1]);
      };
      Mat4.lookAt = function (eye, center, up) {
        var f = new Vec3(center.x - eye.x, center.y - eye.y, center.z - eye.z).normalize();
        var r = f.cross(up).normalize();
        var u = r.cross(f);
        return new Mat4([r.x, u.x, -f.x, 0, r.y, u.y, -f.y, 0, r.z, u.z, -f.z, 0,
                         -r.dot(eye), -u.dot(eye), f.dot(eye), 1]);
      };
      Mat4.compose = function (translation, rotation, scale) {
        return Mat4.fromTranslation(translation).multiply(Mat4.fromEuler(rotation)).multiply(Mat4.fromScale(scale));
      };
      Mat4.prototype.translation = function (position) {
        if (position) {
          this.m[12] = position.x || 0;
          this.m[13] = position.y || 0;
          this.m[14] = position.z || 0;
        }
        return new Vec3(this.m[12], this.m[13], this.m[14]);
      };
      Mat4.prototype.right = function () { return new Vec3(this.m[0], this.m[1], this.m[2]); };
      Mat4.prototype.up = function () { return new Vec3(this.m[4], this.m[5], this.m[6]); };
      Mat4.prototype.forward = function () { return new Vec3(this.m[8], this.m[9], this.m[10]); };
      Mat4.prototype.add = function (other) { var o = other.m; return new Mat4(this.m.map(function (v, i) { return v + o[i]; })); };
      Mat4.prototype.subtract = function (other) { var o = other.m; return new Mat4(this.m.map(function (v, i) { return v - o[i]; })); };
      Mat4.prototype.multiply = function (value) {
        if (typeof value === 'number') return new Mat4(this.m.map(function (v) { return v * value; }));
        if (value instanceof Mat4) return new Mat4(times4(this.m, value.m));
        var m = this.m, x = value.x || 0, y = value.y || 0, z = value.z || 0, w = value.w === undefined ? 1 : value.w;
        return new Vec4(m[0] * x + m[4] * y + m[8] * z + m[12] * w, m[1] * x + m[5] * y + m[9] * z + m[13] * w,
                        m[2] * x + m[6] * y + m[10] * z + m[14] * w, m[3] * x + m[7] * y + m[11] * z + m[15] * w);
      };
      Mat4.prototype.translate = function (v) { return this.multiply(Mat4.fromTranslation(v)); };
      Mat4.prototype.rotate = function (angle, axis) { return this.multiply(Mat4.fromRotation(angle, axis)); };
      Mat4.prototype.scale = function (v) { return this.multiply(Mat4.fromScale(v)); };
      Mat4.prototype.transformPoint = function (v) {
        var m = this.m, x = v.x || 0, y = v.y || 0, z = v.z || 0;
        var w = m[3] * x + m[7] * y + m[11] * z + m[15] || 1;
        return new Vec3((m[0] * x + m[4] * y + m[8] * z + m[12]) / w, (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
                        (m[2] * x + m[6] * y + m[10] * z + m[14]) / w);
      };
      Mat4.prototype.transformDirection = function (v) {
        var m = this.m, x = v.x || 0, y = v.y || 0, z = v.z || 0;
        return new Vec3(m[0] * x + m[4] * y + m[8] * z, m[1] * x + m[5] * y + m[9] * z, m[2] * x + m[6] * y + m[10] * z);
      };
      Mat4.prototype.transpose = function () {
        var m = this.m, r = new Array(16);
        for (var c = 0; c < 4; c++) for (var row = 0; row < 4; row++) r[row * 4 + c] = m[c * 4 + row];
        return new Mat4(r);
      };
      Mat4.prototype.determinant = function () {
        var m = this.m;
        var b0 = m[0] * m[5] - m[1] * m[4], b1 = m[0] * m[6] - m[2] * m[4], b2 = m[0] * m[7] - m[3] * m[4];
        var b3 = m[1] * m[6] - m[2] * m[5], b4 = m[1] * m[7] - m[3] * m[5], b5 = m[2] * m[7] - m[3] * m[6];
        var b6 = m[8] * m[13] - m[9] * m[12], b7 = m[8] * m[14] - m[10] * m[12], b8 = m[8] * m[15] - m[11] * m[12];
        var b9 = m[9] * m[14] - m[10] * m[13], b10 = m[9] * m[15] - m[11] * m[13], b11 = m[10] * m[15] - m[11] * m[14];
        return b0 * b11 - b1 * b10 + b2 * b9 + b3 * b8 - b4 * b7 + b5 * b6;
      };
      Mat4.prototype.inverse = function () {
        var m = this.m;
        var b0 = m[0] * m[5] - m[1] * m[4], b1 = m[0] * m[6] - m[2] * m[4], b2 = m[0] * m[7] - m[3] * m[4];
        var b3 = m[1] * m[6] - m[2] * m[5], b4 = m[1] * m[7] - m[3] * m[5], b5 = m[2] * m[7] - m[3] * m[6];
        var b6 = m[8] * m[13] - m[9] * m[12], b7 = m[8] * m[14] - m[10] * m[12], b8 = m[8] * m[15] - m[11] * m[12];
        var b9 = m[9] * m[14] - m[10] * m[13], b10 = m[9] * m[15] - m[11] * m[13], b11 = m[10] * m[15] - m[11] * m[14];
        var det = b0 * b11 - b1 * b10 + b2 * b9 + b3 * b8 - b4 * b7 + b5 * b6;
        if (!det) return new Mat4();
        var d = 1 / det;
        return new Mat4([
          (m[5] * b11 - m[6] * b10 + m[7] * b9) * d, (m[2] * b10 - m[1] * b11 - m[3] * b9) * d,
          (m[13] * b5 - m[14] * b4 + m[15] * b3) * d, (m[10] * b4 - m[9] * b5 - m[11] * b3) * d,
          (m[6] * b8 - m[4] * b11 - m[7] * b7) * d, (m[0] * b11 - m[2] * b8 + m[3] * b7) * d,
          (m[14] * b2 - m[12] * b5 - m[15] * b1) * d, (m[8] * b5 - m[10] * b2 + m[11] * b1) * d,
          (m[4] * b10 - m[5] * b8 + m[7] * b6) * d, (m[1] * b8 - m[0] * b10 - m[3] * b6) * d,
          (m[12] * b4 - m[13] * b2 + m[15] * b0) * d, (m[9] * b2 - m[8] * b4 - m[11] * b0) * d,
          (m[5] * b7 - m[4] * b9 - m[6] * b6) * d, (m[0] * b9 - m[1] * b7 + m[2] * b6) * d,
          (m[13] * b1 - m[12] * b3 - m[14] * b0) * d, (m[8] * b3 - m[9] * b1 + m[10] * b0) * d
        ]);
      };
      // The scale of each axis, and the angles of what is left once the scale is taken out.
      Mat4.prototype.decompose = function () {
        var m = this.m;
        var sx = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]) || 1, sy = Math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6]) || 1;
        var sz = Math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10]) || 1;
        if (this.determinant() < 0) sx = -sx;
        var r = [m[0] / sx, m[1] / sx, m[2] / sx, m[4] / sy, m[5] / sy, m[6] / sy, m[8] / sz, m[9] / sz, m[10] / sz];
        var y = Math.asin(Math.max(-1, Math.min(1, -r[2])));
        var x, z;
        if (Math.abs(r[2]) < 0.99999) {
          x = Math.atan2(r[5], r[8]);
          z = Math.atan2(r[1], r[0]);
        } else {
          x = Math.atan2(-r[7], r[4]);
          z = 0;
        }
        return { translation: new Vec3(m[12], m[13], m[14]), rotation: new Vec3(x / DEGREE, y / DEGREE, z / DEGREE),
                 scale: new Vec3(sx, sy, sz) };
      };
      Mat4.prototype.extractEuler = function () { return this.decompose().rotation; };
      Mat4.prototype.normalMatrix = function () {
        var i = this.inverse().m;
        return new Mat3([i[0], i[4], i[8], i[1], i[5], i[9], i[2], i[6], i[10]]);
      };
      Mat4.prototype.copy = function () { return new Mat4(this.m); };
      Mat4.prototype.equals = function (other) {
        return !!other && other.m && this.m.every(function (v, i) { return Math.abs(v - other.m[i]) < 1e-6; });
      };
      Mat4.prototype.toString = function () { return this.m.join(' '); };

      // A 3×3 matrix for the plane: by columns, the place in the last one, the angle in degrees.
      function times3(a, b) {
        var r = new Array(9);
        for (var column = 0; column < 3; column++) {
          for (var row = 0; row < 3; row++) {
            var sum = 0;
            for (var k = 0; k < 3; k++) sum += a[k * 3 + row] * b[column * 3 + k];
            r[column * 3 + row] = sum;
          }
        }
        return r;
      }
      function Mat3(values) {
        this.m = Array.isArray(values) && values.length === 9 ? values.slice() : [1, 0, 0, 0, 1, 0, 0, 0, 1];
      }
      Mat3.identity = function () { return new Mat3(); };
      Mat3.fromTranslation = function (v) { return new Mat3([1, 0, 0, 0, 1, 0, v.x || 0, v.y || 0, 1]); };
      Mat3.fromScale = function (v) {
        var x = typeof v === 'number' ? v : v.x, y = typeof v === 'number' ? v : v.y;
        return new Mat3([x, 0, 0, 0, y, 0, 0, 0, 1]);
      };
      Mat3.fromRotation = function (angle) {
        var c = Math.cos(angle * DEGREE), s = Math.sin(angle * DEGREE);
        return new Mat3([c, s, 0, -s, c, 0, 0, 0, 1]);
      };
      Mat3.fromBasis = function (right, up) { return new Mat3([right.x, right.y, 0, up.x, up.y, 0, 0, 0, 1]); };
      Mat3.fromMat4 = function (other) {
        var m = other.m;
        return new Mat3([m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]]);
      };
      Mat3.compose = function (translation, rotation, scale) {
        return Mat3.fromTranslation(translation).multiply(Mat3.fromRotation(rotation)).multiply(Mat3.fromScale(scale));
      };
      Mat3.prototype.translation = function (position) {
        if (position) {
          this.m[6] = position.x || 0;
          this.m[7] = position.y || 0;
        }
        return new Vec2(this.m[6], this.m[7]);
      };
      Mat3.prototype.angle = function () { return Math.atan2(this.m[1], this.m[0]) / DEGREE; };
      Mat3.prototype.add = function (other) { var o = other.m; return new Mat3(this.m.map(function (v, i) { return v + o[i]; })); };
      Mat3.prototype.subtract = function (other) { var o = other.m; return new Mat3(this.m.map(function (v, i) { return v - o[i]; })); };
      Mat3.prototype.multiply = function (value) {
        if (typeof value === 'number') return new Mat3(this.m.map(function (v) { return v * value; }));
        if (value instanceof Mat3) return new Mat3(times3(this.m, value.m));
        var m = this.m, x = value.x || 0, y = value.y || 0, z = value.z === undefined ? 1 : value.z;
        return new Vec3(m[0] * x + m[3] * y + m[6] * z, m[1] * x + m[4] * y + m[7] * z, m[2] * x + m[5] * y + m[8] * z);
      };
      Mat3.prototype.translate = function (v) { return this.multiply(Mat3.fromTranslation(v)); };
      Mat3.prototype.rotate = function (angle) { return this.multiply(Mat3.fromRotation(angle)); };
      Mat3.prototype.scale = function (v) { return this.multiply(Mat3.fromScale(v)); };
      Mat3.prototype.transformPoint = function (v) {
        var m = this.m;
        return new Vec2(m[0] * v.x + m[3] * v.y + m[6], m[1] * v.x + m[4] * v.y + m[7]);
      };
      Mat3.prototype.transformDirection = function (v) {
        var m = this.m;
        return new Vec2(m[0] * v.x + m[3] * v.y, m[1] * v.x + m[4] * v.y);
      };
      Mat3.prototype.transpose = function () {
        var m = this.m;
        return new Mat3([m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]);
      };
      Mat3.prototype.determinant = function () {
        var m = this.m;
        return m[0] * (m[4] * m[8] - m[7] * m[5]) - m[3] * (m[1] * m[8] - m[7] * m[2]) + m[6] * (m[1] * m[5] - m[4] * m[2]);
      };
      Mat3.prototype.inverse = function () {
        var m = this.m, det = this.determinant();
        if (!det) return new Mat3();
        var d = 1 / det;
        return new Mat3([
          (m[4] * m[8] - m[5] * m[7]) * d, (m[2] * m[7] - m[1] * m[8]) * d, (m[1] * m[5] - m[2] * m[4]) * d,
          (m[5] * m[6] - m[3] * m[8]) * d, (m[0] * m[8] - m[2] * m[6]) * d, (m[2] * m[3] - m[0] * m[5]) * d,
          (m[3] * m[7] - m[4] * m[6]) * d, (m[1] * m[6] - m[0] * m[7]) * d, (m[0] * m[4] - m[1] * m[3]) * d
        ]);
      };
      Mat3.prototype.decompose = function () {
        var m = this.m;
        var sx = Math.sqrt(m[0] * m[0] + m[1] * m[1]), sy = Math.sqrt(m[3] * m[3] + m[4] * m[4]);
        if (this.determinant() < 0) sy = -sy;
        return { translation: new Vec2(m[6], m[7]), rotation: Math.atan2(m[1], m[0]) / DEGREE, scale: new Vec2(sx, sy) };
      };
      Mat3.prototype.copy = function () { return new Mat3(this.m); };
      Mat3.prototype.equals = function (other) {
        return !!other && other.m && this.m.every(function (v, i) { return Math.abs(v - other.m[i]) < 1e-6; });
      };
      Mat3.prototype.toString = function () { return this.m.join(' '); };

      // A direction from angles on a sphere — around and up, in degrees — and as far as said; and back.
      Vec3.fromSpherical = function (azimuth, elevation, radius) {
        var r = radius === undefined ? 1 : radius, a = (azimuth || 0) * DEGREE, e = (elevation || 0) * DEGREE;
        return new Vec3(r * Math.cos(e) * Math.cos(a), r * Math.sin(e), r * Math.cos(e) * Math.sin(a));
      };
      Vec3.prototype.toSpherical = function () {
        var r = this.length();
        return new Vec3(Math.atan2(this.z, this.x) / DEGREE, r > 0 ? Math.asin(Math.max(-1, Math.min(1, this.y / r))) / DEGREE : 0, r);
      };
      // Bent as light is through a surface, from one medium into one `ratio` times as dense.
      Vec3.prototype.refract = function (normal, ratio) {
        var cos = -this.dot(normal);
        var k = 1 - ratio * ratio * (1 - cos * cos);
        return k < 0 ? new Vec3(0, 0, 0) : this.multiply(ratio).add(normal.multiply(ratio * cos - Math.sqrt(k)));
      };

      // The settings a script declares for itself: `createScriptProperties().addSlider({…}).finish()`.
      // Each has a name and a value, and the scene may give another value for it.
      function scriptSettings(given) {
        return function () {
          var values = {};
          function add(said) {
            if (!said || said.name === undefined) return;
            var own; // what the script itself has set it to
            Object.defineProperty(values, said.name, {
              enumerable: true,
              configurable: true,
              // Asked anew every time: a setting of the wallpaper may stand behind the value the
              // scene gives, and may be changed while the scene plays.
              get: function () {
                if (own !== undefined) return own;
                var value = given && typeof given === 'object' && said.name in given ? plain(given[said.name]) : said.value;
                if (value === undefined || value === null) return said.value;
                // A color comes as three numbers in a text; a script that declared one takes a vector.
                if (typeof value === 'string' && said.value && typeof said.value === 'object' && 'x' in said.value) return new Vec3(value);
                return value;
              },
              set: function (value) { own = value; }
            });
          }
          var builder = typeof Proxy === 'function' ? new Proxy({}, {
            get: function (object, name) {
              if (name === 'finish') return function () { return values; };
              return function (said) {
                add(said);
                return builder;
              };
            }
          }) : { finish: function () { return values; } };
          return builder;
        };
      }

      // Turns the text of a script into what it has to offer: the functions the scene calls.
      // A script is a module; its `export`s are found, and its `import`s of the helpers above
      // are given those. In Wallpaper Engine a script has the scene to work with and nothing
      // else, so the page's own names are kept from it; and what it declares is its own, whatever
      // it is called.
      var EVENTS = ['init', 'update', 'destroy', 'resizeScreen', 'applyUserProperties', 'applyGeneralSettings',
                    'cursorEnter', 'cursorLeave', 'cursorMove', 'cursorDown', 'cursorUp', 'cursorClick',
                    'mediaStatusChanged', 'mediaPropertiesChanged', 'mediaThumbnailChanged', 'mediaPlaybackChanged', 'mediaTimelineChanged'];
      var KEPT_AWAY = ['window', 'document', 'globalThis', 'self', 'top', 'parent', 'frames', 'opener', 'fetch', 'XMLHttpRequest',
                       'WebSocket', 'EventSource', 'Worker', 'navigator', 'location', 'history', 'indexedDB', 'sessionStorage',
                       'caches', 'eval', 'Function', 'open', 'postMessage', 'webkit'];
      function compileScript(source, names, values) {
        var text = String(source).replace(/\r\n?/g, '\n')
          .replace(/^\s*import\s+\*\s+as\s+(\w+)\s+from\s+['"](\w+)['"]\s*;?/gm, function (whole, name, module) {
            return 'var ' + name + ' = __modules.' + module + ' || {};';
          })
          .replace(/^\s*import\s+\{([^}]*)\}\s+from\s+['"](\w+)['"]\s*;?/gm, function (whole, list, module) {
            return 'var {' + list.replace(/\s+as\s+/g, ': ') + '} = __modules.' + module + ' || {};';
          })
          .replace(/^(\s*)export\s+(default\s+)?(?=function|var|let|const|class|async)/gm, '$1')
          .replace(/^\s*export\s*\{[^}]*\}\s*;?/gm, '');
        var tail = '\n;return {' + EVENTS.map(function (name) {
          return name + ': typeof ' + name + ' === "function" ? ' + name + ' : null';
        }).join(', ') + '};';
        var body = 'return (function () {\n"use strict";\n' + text + tail + '\n}).call(undefined);';
        return Function.apply(null, names.concat(['__modules'], KEPT_AWAY, [body])).apply(null, values.concat([MODULES]));
      }

      // ------------------------------------------------------------------ pictures made here
      //
      // Textures a scene names without bringing them: Wallpaper Engine has them, a scene's
      // package does not. They are drawn here to the same purpose — a flat color, noise, the soft
      // shapes particles are made of — and so look alike, not the same.

      // A value that is the same every time for the same place: noise that does not change from
      // one start of the wallpaper to the next.
      function hash(x, y, seed) {
        var h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(seed | 0, 2147483647);
        h = Math.imul(h ^ (h >>> 13), 1274126177);
        return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
      }

      // Smooth noise that repeats every `period` cells, so that a texture of it tiles.
      function smoothNoise(x, y, period, seed) {
        var x0 = Math.floor(x), y0 = Math.floor(y);
        var fx = x - x0, fy = y - y0;
        fx = fx * fx * (3 - 2 * fx);
        fy = fy * fy * (3 - 2 * fy);
        function corner(cx, cy) {
          return hash(((cx % period) + period) % period, ((cy % period) + period) % period, seed);
        }
        var top = corner(x0, y0) + (corner(x0 + 1, y0) - corner(x0, y0)) * fx;
        var bottom = corner(x0, y0 + 1) + (corner(x0 + 1, y0 + 1) - corner(x0, y0 + 1)) * fx;
        return top + (bottom - top) * fy;
      }

      // Noise of gradients that repeats every `period` cells: soft, without the blots noise of
      // values has.
      function gradientNoise(x, y, period, seed) {
        var x0 = Math.floor(x), y0 = Math.floor(y);
        var fx = x - x0, fy = y - y0;
        function corner(cx, cy, dx, dy) {
          var angle = hash(((cx % period) + period) % period, ((cy % period) + period) % period, seed) * Math.PI * 2;
          return Math.cos(angle) * dx + Math.sin(angle) * dy;
        }
        var ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10), uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10);
        var top = corner(x0, y0, fx, fy) + (corner(x0 + 1, y0, fx - 1, fy) - corner(x0, y0, fx, fy)) * ux;
        var bottom = corner(x0, y0 + 1, fx, fy - 1) + (corner(x0 + 1, y0 + 1, fx - 1, fy - 1) - corner(x0, y0 + 1, fx, fy - 1)) * ux;
        return top + (bottom - top) * uy;
      }

      // Clouds: noise of several sizes laid over one another, grey around the middle.
      function cloudsPixels(size) {
        var pixels = new Uint8Array(size * size * 4);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            var value = 0, weight = 0.6, cells = 4;
            for (var octave = 0; octave < 6; octave++) {
              value += weight * gradientNoise(x / size * cells, y / size * cells, cells, octave + 1);
              weight *= 0.5;
              cells *= 2;
            }
            var shade = Math.round(Math.max(0, Math.min(1, 0.5 + value)) * 255);
            var at = (y * size + x) * 4;
            pixels[at] = pixels[at + 1] = pixels[at + 2] = shade;
            pixels[at + 3] = 255;
          }
        }
        return pixels;
      }

      function noisePixels(size) {
        var pixels = new Uint8Array(size * size * 4);
        for (var i = 0; i < size * size * 4; i++) {
          pixels[i] = Math.round(hash(i % (size * 4), Math.floor(i / (size * 4)), 7) * 255);
        }
        return pixels;
      }

      // A ramp from black to white: down the picture, or across it.
      function rampPixels(size, across, reverse) {
        var pixels = new Uint8Array(size * size * 4);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            var share = (across ? x : y) / (size - 1);
            var shade = Math.round((reverse ? 1 - share : share) * 255);
            var at = (y * size + x) * 4;
            pixels[at] = pixels[at + 1] = pixels[at + 2] = shade;
            pixels[at + 3] = 255;
          }
        }
        return pixels;
      }

      // The colors of a soap film, across the picture: for effects that color by how bright.
      function rainbowPixels(size) {
        var pixels = new Uint8Array(size * size * 4);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            var turn = x / size * Math.PI * 2;
            var at = (y * size + x) * 4;
            pixels[at] = Math.round((0.72 + 0.28 * Math.cos(turn)) * 255);
            pixels[at + 1] = Math.round((0.72 + 0.28 * Math.cos(turn - 2.094)) * 255);
            pixels[at + 2] = Math.round((0.72 + 0.28 * Math.cos(turn + 2.094)) * 255);
            pixels[at + 3] = 255;
          }
        }
        return pixels;
      }

      // Cells, as light on the floor of a pool is: bright where two cells meet. It repeats, so a
      // texture of it tiles; `soft` makes the lines wide and faint, for a glow.
      function cellsPixels(size, soft) {
        var cells = 6;
        var points = [];
        for (var cy = 0; cy < cells; cy++) {
          for (var cx = 0; cx < cells; cx++) {
            points.push([(cx + 0.15 + 0.7 * hash(cx, cy, 71)) / cells, (cy + 0.15 + 0.7 * hash(cx, cy, 73)) / cells]);
          }
        }
        var pixels = new Uint8Array(size * size * 4);
        var reach = (soft ? 0.5 : 0.22) / cells;
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            var u = (x + 0.5) / size, v = (y + 0.5) / size;
            var nearest = 9, second = 9;
            var homeX = Math.floor(u * cells), homeY = Math.floor(v * cells);
            for (var dy = -1; dy <= 1; dy++) {
              for (var dx = -1; dx <= 1; dx++) {
                var gx = homeX + dx, gy = homeY + dy;
                var point = points[((gy % cells) + cells) % cells * cells + ((gx % cells) + cells) % cells];
                // The point of a cell beyond the edge is the one of the cell at the other edge.
                var px = point[0] + Math.floor(gx / cells), py = point[1] + Math.floor(gy / cells);
                var far = Math.sqrt((px - u) * (px - u) + (py - v) * (py - v));
                if (far < nearest) {
                  second = nearest;
                  nearest = far;
                } else if (far < second) {
                  second = far;
                }
              }
            }
            var edge = Math.max(0, 1 - (second - nearest) / reach);
            var shade = Math.round(Math.pow(edge, soft ? 1.5 : 3) * 255);
            var at = (y * size + x) * 4;
            pixels[at] = pixels[at + 1] = pixels[at + 2] = shade;
            pixels[at + 3] = 255;
          }
        }
        return pixels;
      }

      // The shapes of particles, drawn white on nothing; a particle's own color tints them.
      // A drop on glass, as clear as the glass: a darker rim, a glint where the light falls on it.
      function spritePixels(name, size) {
        var canvas = document.createElement('canvas');
        canvas.width = canvas.height = size;
        var context = canvas.getContext('2d');
        var half = size / 2;
        function glow(x, y, radius, strength) {
          var gradient = context.createRadialGradient(x, y, 0, x, y, radius);
          gradient.addColorStop(0, 'rgba(255,255,255,' + strength + ')');
          gradient.addColorStop(0.4, 'rgba(255,255,255,' + strength * 0.45 + ')');
          gradient.addColorStop(1, 'rgba(255,255,255,0)');
          context.fillStyle = gradient;
          context.fillRect(0, 0, size, size);
        }
        if (/shaft|godray|sunbeam|sunray|light_ray/.test(name)) {
          // Light falling through. Wallpaper Engine's own pictures of it are of a few kinds, told
          // by their number: a soft column of light falling from the top edge (0, and the plainest
          // one, 6), thin rays from a point at the top (1, 3), a wide fan from the top (4) and a
          // burst from the middle (2, 5). Each is drawn here in its shape: rays from where the
          // light comes in, fading as they go. Such a picture is made large and turned.
          var kind = Number((/(\d+)\D*$/.exec(name) || [])[1]);
          // `spread`: how far to either side the rays go, as an angle; `from`: where they start,
          // as a share of the height above the top; `count`, `widths` and `strength` of the rays.
          // Their light dies away downward as Wallpaper Engine's does — most of it in the upper half,
          // next to none at the bottom — and they are as bright, against one another, as its are.
          // How bright they are on a scene was set against Wallpaper Engine's own picture of one
          // ("Frieren with music"): there the light adds about a quarter to the brightness where it
          // falls, warm and in streaks.
          var fan = { 0: { spread: 0.16, from: 0.25, count: 22, widths: [0.05, 0.16], strength: 0.022 },
                      6: { spread: 0.05, from: 0.6, count: 10, widths: [0.12, 0.3], strength: 0.009 },
                      1: { spread: 0.3, from: 0, count: 9, widths: [0.004, 0.02], strength: 0.024 },
                      3: { spread: 0.12, from: 0, count: 6, widths: [0.004, 0.015], strength: 0.028 },
                      4: { spread: 0.95, from: 0, count: 30, widths: [0.01, 0.06], strength: 0.038 } }[kind];
          if (fan) {
            var topX = half, topY = -fan.from * size;
            var reach = size - topY;
            for (var ray = 0; ray < fan.count; ray++) {
              var turn = (hash(ray, 4, 7) * 2 - 1) * fan.spread;
              var wide = (fan.widths[0] + hash(ray, 5, 7) * (fan.widths[1] - fan.widths[0])) * Math.PI;
              var strong = fan.strength * (0.5 + hash(ray, 6, 7));
              // Faded toward where it ends, and where it starts, as light comes in through leaves.
              var fade = context.createRadialGradient(topX, topY, 0, topX, topY, reach);
              // Stops by how far down the picture they are.
              var down = function (share) { return Math.min(1, (fan.from + share) / (1 + fan.from)); };
              fade.addColorStop(0, 'rgba(255,255,255,0)');
              if (down(0) > 0) fade.addColorStop(down(0) * 0.9, 'rgba(255,255,255,0)');
              fade.addColorStop(down(0.12), 'rgba(255,255,255,' + strong + ')');
              fade.addColorStop(down(0.3), 'rgba(255,255,255,' + strong * 0.75 + ')');
              fade.addColorStop(down(0.5), 'rgba(255,255,255,' + strong * 0.3 + ')');
              fade.addColorStop(down(0.75), 'rgba(255,255,255,' + strong * 0.07 + ')');
              fade.addColorStop(1, 'rgba(255,255,255,0)');
              context.fillStyle = fade;
              context.beginPath();
              context.moveTo(topX, topY);
              context.arc(topX, topY, reach, Math.PI / 2 + turn - wide / 2, Math.PI / 2 + turn + wide / 2);
              context.closePath();
              context.fill();
            }
            // Brightest where it comes in.
            var inlet = context.createRadialGradient(half, size * 0.12, 0, half, size * 0.12, size * 0.3);
            inlet.addColorStop(0, 'rgba(255,255,255,' + Math.min(1, fan.strength * 2) + ')');
            inlet.addColorStop(1, 'rgba(255,255,255,0)');
            context.fillStyle = inlet;
            context.fillRect(0, 0, size, size * 0.4);
          } else {
            // A burst: soft rays from the middle outward, of many widths, fading as they go.
            for (var spike = 0; spike < 18; spike++) {
              var toward = hash(spike, 4, 7) * Math.PI * 2;
              var narrow = (0.01 + hash(spike, 5, 7) * 0.05) * Math.PI;
              var bright = 0.12 + hash(spike, 6, 7) * 0.25;
              var burst = context.createRadialGradient(half, half, 0, half, half, half);
              burst.addColorStop(0, 'rgba(255,255,255,0)');
              burst.addColorStop(0.08, 'rgba(255,255,255,' + bright + ')');
              burst.addColorStop(0.55, 'rgba(255,255,255,' + bright * 0.45 + ')');
              burst.addColorStop(1, 'rgba(255,255,255,0)');
              context.fillStyle = burst;
              context.beginPath();
              context.moveTo(half, half);
              context.arc(half, half, half, toward - narrow / 2, toward + narrow / 2);
              context.closePath();
              context.fill();
            }
          }
        } else if (/fog|smoke|cloud|mist|steam|dust|haze/.test(name)) {
          // A puff: many soft blots, more of them toward the middle.
          for (var blot = 0; blot < 40; blot++) {
            var angle = hash(blot, 1, 3) * Math.PI * 2;
            var away = Math.pow(hash(blot, 2, 3), 0.8) * half * 0.55;
            glow(half + Math.cos(angle) * away, half + Math.sin(angle) * away, half * (0.2 + hash(blot, 3, 3) * 0.3), 0.05);
          }
        } else if (/rain|drop|streak|line|trail|beam|ray/.test(name)) {
          var streak = context.createLinearGradient(0, 0, 0, size);
          streak.addColorStop(0, 'rgba(255,255,255,0)');
          streak.addColorStop(0.5, 'rgba(255,255,255,0.9)');
          streak.addColorStop(1, 'rgba(255,255,255,0)');
          context.fillStyle = streak;
          context.fillRect(half - size * 0.04, 0, size * 0.08, size);
        } else if (/fire|flame|blaze|burn/.test(name)) {
          // A flame: a tongue rising from a bright foot, frayed at its edges.
          for (var tongue = 0; tongue < 24; tongue++) {
            var rise = hash(tongue, 5, 9);
            var sway = (hash(tongue, 6, 9) - 0.5) * half * 0.5 * rise;
            glow(half + sway, size * (0.72 - rise * 0.5), half * (0.32 - rise * 0.2), 0.16 * (1 - rise * 0.6));
          }
        } else if (/halo|glow|light|dot|spark|ember|orb|bokeh|firefl/.test(name)) {
          // A halo: a small bright core in a faint glow, as light seen through a lens is.
          var halo = context.createRadialGradient(half, half, 0, half, half, half);
          halo.addColorStop(0, 'rgba(255,255,255,1)');
          halo.addColorStop(0.08, 'rgba(255,255,255,0.85)');
          halo.addColorStop(0.2, 'rgba(255,255,255,0.3)');
          halo.addColorStop(0.5, 'rgba(255,255,255,0.08)');
          halo.addColorStop(1, 'rgba(255,255,255,0)');
          context.fillStyle = halo;
          context.fillRect(0, 0, size, size);
        } else if (/star|sparkle|flare|twinkle/.test(name)) {
          glow(half, half, half * 0.5, 1);
          context.fillStyle = 'rgba(255,255,255,0.8)';
          [[1, 0.06], [0.06, 1]].forEach(function (arm) {
            context.beginPath();
            context.ellipse(half, half, half * arm[0], half * arm[1], 0, 0, Math.PI * 2);
            context.fill();
          });
        } else if (/leaf|leaves|foliage/.test(name)) {
          // A leaf: pointed at both ends, a little lighter along its middle, on a short stalk.
          context.translate(half, half);
          context.rotate(Math.PI / 5);
          context.beginPath();
          context.moveTo(-half * 0.82, 0);
          context.quadraticCurveTo(-half * 0.1, -half * 0.62, half * 0.82, 0);
          context.quadraticCurveTo(-half * 0.1, half * 0.62, -half * 0.82, 0);
          context.closePath();
          var body = context.createLinearGradient(0, -half * 0.4, 0, half * 0.4);
          body.addColorStop(0, 'rgba(205,205,205,0.95)');
          body.addColorStop(0.5, 'rgba(255,255,255,0.95)');
          body.addColorStop(1, 'rgba(175,175,175,0.95)');
          context.fillStyle = body;
          context.fill();
          context.strokeStyle = 'rgba(255,255,255,0.9)';
          context.lineWidth = size / 64;
          context.beginPath();
          context.moveTo(-half * 0.95, 0);
          context.lineTo(half * 0.7, 0);
          context.stroke();
        } else if (/petal|feather|confetti|flake/.test(name)) {
          context.fillStyle = 'rgba(255,255,255,0.95)';
          context.beginPath();
          context.ellipse(half, half, half * 0.85, half * 0.4, Math.PI / 5, 0, Math.PI * 2);
          context.fill();
        } else {
          // A soft round dot: snow, sparks, lights, and whatever has no shape of its own here.
          glow(half, half, half, 1);
        }
        return context.getImageData(0, 0, size, size).data;
      }

      // ------------------------------------------------------------------ the player

      function play(canvas, scene, settings, startingChanges) {
        properties = {};
        Object.keys(settings || {}).forEach(function (name) { properties[name] = settings[name]; });
        var files = (scene && scene.files) || {};
        var pictures = (scene && scene.textures) || {};
        var soundFiles = (scene && scene.sounds) || {};
        var puppets = (scene && scene.puppets) || {};
        var stopped = false;
        var gl = canvas.getContext('webgl2', { alpha: false, antialias: false, depth: false, stencil: false,
                                               premultipliedAlpha: false, preserveDrawingBuffer: false });
        if (!gl) {
          note('this Mac\'s web engine has no WebGL 2; the scene cannot be drawn');
          return { stop: function () {} };
        }

        // A file of the scene that holds JSON. The files are written by programs, but by many
        // versions of them; one that does not parse is treated as missing.
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
          ['a_Position', 'a_TexCoord', 'a_Place', 'a_Color', 'a_Frame', 'a_Spot', 'a_Uv', 'a_More', 'a_Normal'].forEach(function (name, index) {
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

        function newTexture(clamp, smooth) {
          var texture = gl.createTexture();
          gl.bindTexture(gl.TEXTURE_2D, texture);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, clamp ? gl.CLAMP_TO_EDGE : gl.REPEAT);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, clamp ? gl.CLAMP_TO_EDGE : gl.REPEAT);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, smooth ? gl.LINEAR : gl.NEAREST);
          return texture;
        }

        // `grainy`: looked at as it is wherever it is shown small — noise that is averaged out
        // is no noise.
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
          if (textureCache[id]) return textureCache[id];
          var entry = pictures[id] || pictures['materials/' + id];
          var result;
          if (entry && entry.video) {
            result = film(entry);
          } else if (entry && entry.pictures && entry.pictures.length) {
            result = { layers: [], width: entry.pictures[0].width, height: entry.pictures[0].height,
                       channels: entry.channels || 'rgba', frames: entry.frames || null, ready: false };
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
        var projection = general.orthogonalprojection || {};
        var sceneWidth = number(projection.width, 0);
        var sceneHeight = number(projection.height, 0);
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
        function buildPass(shaderName, combos, constants, slotTextures, what, owner) {
          var vertexSource = files['shaders/' + key(shaderName) + '.vert'];
          var fragmentSource = files['shaders/' + key(shaderName) + '.frag'];
          if (typeof vertexSource !== 'string' || typeof fragmentSource !== 'string') {
            note(what + ': the shader ' + shaderName + ' is not in the scene');
            return null;
          }
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
          gl.bindTexture(gl.TEXTURE_2D, texture);
          var wrapS = gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S), wrapT = gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T);
          var smooth = gl.getTexParameter(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER) !== gl.NEAREST;
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

        function drawPass(pass, target, inputs, layer, onScreen) {
          gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
          gl.viewport(0, 0, target.width, target.height);
          gl.disable(gl.BLEND);
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
              gl.uniform1f(uniform.location, -1);
            } else if (uniform.type === gl.FLOAT_MAT4) {
              // An effect is drawn onto its layer's own picture, which needs no placing; how the
              // layer itself stands on the scene — how large, how turned — a shader may ask.
              var asked = IDENTITY;
              if (value.name === 'g_LayerModelMatrix' && layer) {
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
        }

        // --- Values that change -----------------------------------------------
        //
        // Where an object is, how large, how see-through, what it says: each is read through a
        // `live` value, which knows what stands behind it. One with an animation or a script is
        // read every frame, one with a setting of the wallpaper when the settings change, and
        // one with nothing behind it never again: what a script has made of it meanwhile stays.

        var things = [];         // everything of the scene that has a place: pictures, texts, particles
        var motions = [];        // the animations of values, each with how far it has played
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
          var motion = curve ? { curve: curve, called: curve.called, at: 0, playing: !curve.startsPaused, started: !curve.startsPaused,
                                 speed: 1, leader: null } : null;
          if (motion) motions.push(motion);
          // `bound`: a setting of the wallpaper stands behind it.
          var value = { raw: raw, changes: !!curve, motion: motion, script: script, bound: !!(behind && behind.user !== undefined && behind.user !== null) };
          value.now = base();
          value.read = function () {
            // A script carries on from what the value is; anything else starts from what the
            // scene says.
            var result = script && script.made !== undefined ? value.now : base();
            if (curve && (motion.leader || motion).started) result = curve((motion.leader || motion).at, result);
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

        function call(script, name, argument) {
          var wanted = script.made && script.made[name];
          if (!wanted || script.failures > 3) return undefined;
          try {
            return wanted(argument);
          } catch (error) {
            script.failures = (script.failures || 0) + 1;
            note('a script of “' + (script.owner ? script.owner.name : 'the scene') + '” fails: ' + error.message);
            return undefined;
          }
        }

        // Makes a script ready the first time its value is wanted — by then every object of the
        // scene is there for it to ask about — and gives its value for this frame.
        function runScript(script, current) {
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
            }
            if (script.made) {
              var first = call(script, 'init', toScript(script, current));
              script.quiet = first === undefined;
              current = fromScript(script, first, current);
              call(script, 'applyUserProperties', engineObject.userProperties);
            }
          }
          if (script.made && script.made.update) {
            var answer = call(script, 'update', toScript(script, current));
            // One that gives nothing back has done its work on the scene by itself.
            script.quiet = answer === undefined;
            current = fromScript(script, answer, current);
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

        var consoleObject = {
          log: function () { if (window.console) window.console.log.apply(window.console, arguments); },
          error: function () { note('a script says: ' + Array.prototype.join.call(arguments, ' ')); }
        };

        var storageObject = {
          LOCATION_GLOBAL: 'global', LOCATION_SCREEN: 'screen',
          get: function (name) { return stored[name]; },
          set: function (name, value) { stored[name] = value; },
          'delete': function (name) { return delete stored[name]; },
          clear: function () { stored = {}; }
        };

        var inputObject = {
          get cursorWorldPosition() { return new Vec3(pointer[0] * sceneWidth, (1 - pointer[1]) * sceneHeight, 0); },
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
             'limitrows', 'maxrows', 'limitwidth', 'maxwidth'].forEach(function (name) {
              plainOf(name, function () {
                var now = thing.own[name] !== undefined ? thing.own[name] : plain(thing.said[name]);
                return name === 'backgroundcolor' ? new Vec3(String(now === undefined ? '0 0 0' : now)) : now;
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
              get: function () { var c = thing.recolor || [1, 1, 1]; return new Vec3(c[0], c[1], c[2]); },
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
          return lenient({ visible: true, rate: 1, isPlaying: function () { return true; }, getFrame: function () { return 0; } });
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
            var x = sceneWidth / 2 + camera.x, y = sceneHeight / 2 + camera.y;
            return { eye: new Vec3(x, y, 1), center: new Vec3(x, y, 0), up: new Vec3(0, 1, 0), zoom: camera.zoom };
          },
          setCameraTransforms: function (transforms) {
            var said = transforms || {};
            var at = said.center || said.eye;
            if (at && typeof at.x === 'number') {
              camera.x = at.x - sceneWidth / 2;
              camera.y = at.y - sceneHeight / 2;
            }
            if (typeof said.zoom === 'number' && said.zoom > 0) camera.zoom = said.zoom;
            dirty = true;
          },
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
          'out vec2 v_Uv;',
          'void main() {',
          '  v_Uv = a_TexCoord;',
          '  vec3 at = u_Place * vec3(a_TexCoord.x - 0.5, 0.5 - a_TexCoord.y, 1.0);',
          '  gl_Position = vec4(at.xy, 0.0, 1.0);',
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
          'out vec2 v_Uv;',
          'void main() {',
          '  v_Uv = a_Uv;',
          '  vec3 at = u_Place * vec3(a_Spot, 1.0);',
          '  gl_Position = vec4(at.xy, 0.0, 1.0);',
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

        var CHANNELS = { rgba: 0, r8: 1, rg88: 2 };

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
            gl.blitFramebuffer(0, 0, onto.width, onto.height, 0, 0, onto.width, onto.height, gl.COLOR_BUFFER_BIT, gl.NEAREST);
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
          gl.uniformMatrix3fv(program.uniforms.u_Place.location, false, place);
          gl.uniform4fv(program.uniforms.u_Tint.location, tint);
          gl.uniform4fv(program.uniforms.u_Frame.location, source.frame || [0, 0, 1, 1]);
          gl.uniform1i(program.uniforms.u_Channels.location, CHANNELS[source.channels] || 0);
          if (mesh) {
            gl.bindVertexArray(mesh.shape);
            gl.drawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_SHORT, 0);
            gl.bindVertexArray(null);
          } else {
            gl.bindVertexArray(passShape);
            gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
          }
        }

        // A puppet drawn part by part, in its order: a part that shows only within others through
        // a mask of those others, drawn first as they are bent at the moment.
        function putClipped(source, place, tint, how, mesh) {
          var framebuffer = gl.getParameter(gl.FRAMEBUFFER_BINDING);
          var view = gl.getParameter(gl.VIEWPORT);
          var width = view[2], height = view[3];
          var clippedBy = {};
          mesh.clips.forEach(function (clip) { clippedBy[clip.part] = clip; });
          function useMesh(program) {
            gl.useProgram(program.program);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, source.texture);
            gl.uniform1i(program.uniforms.u_Texture.location, 0);
            gl.uniformMatrix3fv(program.uniforms.u_Place.location, false, place);
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
            gl.uniformMatrix3fv(clipMaskProgram.uniforms.u_Place.location, false, place);
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

        // --- Pictures that bend ---------------------------------------------------
        //
        // A puppet is a picture cut into triangles whose corners hang on bones. An animation says
        // where every bone is in every frame; a corner goes where its bones take it, each by its
        // weight. Bones and corners live on the flat of the picture, so a bone's place is kept as
        // six numbers: x' = a·x + c·y + e, y' = b·x + d·y + f.

        function numbersOf(text, kind) {
          var raw = atob(text || '');
          var bytes = new Uint8Array(raw.length);
          for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
          return new kind(bytes.buffer, 0, Math.floor(bytes.length / kind.BYTES_PER_ELEMENT));
        }

        // First `second`, then `first`.
        function joined(first, second) {
          return [first[0] * second[0] + first[2] * second[1], first[1] * second[0] + first[3] * second[1],
                  first[0] * second[2] + first[2] * second[3], first[1] * second[2] + first[3] * second[3],
                  first[0] * second[4] + first[2] * second[5] + first[4], first[1] * second[4] + first[3] * second[5] + first[5]];
        }

        function undone(move) {
          var det = move[0] * move[3] - move[2] * move[1] || 1;
          var a = move[3] / det, b = -move[1] / det, c = -move[2] / det, d = move[0] / det;
          return [a, b, c, d, -(a * move[4] + c * move[5]), -(b * move[4] + d * move[5])];
        }

        // How a bone sways by itself, as Wallpaper Engine's editor writes it: on a spring that
        // brings it back (`se`), or hanging free (`re`) where only friction holds it; turning about
        // its root (`r`), or moving (`t`), or both; pulled by gravity (`ge`, `gd`) or not, and
        // turned no further than it may (`la`, `lamin`, `lamax`). How stiff the spring is (`rs`,
        // `ts`), how much friction (`rf`, `tf`), how heavy it moves (`ri`, `ti`), and where its
        // tip is from its root (`tp`). Null for a bone that does not sway; bones bent towards a
        // target (`ik`) do not either.
        function swayOf(text) {
          if (typeof text !== 'string' || text.charAt(0) !== '{') return null;
          var said;
          try { said = JSON.parse(text); } catch (error) { return null; }
          if (!said || (!said.se && !said.re)) return null;
          var turns = said.r !== false && said.r !== null, moves = !!said.t;
          if (!turns && !moves) return null;
          var tip = numbers(said.tp, 3, 0);
          var gravity = numbers(said.gd, 3, 0);
          if (!said.gd) gravity = [0, -1, 0];
          var limited = !!said.la;
          return {
            spring: !!said.se, turns: turns, moves: moves,
            stiff: said.se ? number(said.rs, 200) : 0, friction: number(said.rf, 20), weight: Math.max(0.01, number(said.ri, 30)),
            moveStiff: said.se ? number(said.ts, 200) : 0, moveFriction: number(said.tf, 20), moveWeight: Math.max(0.01, number(said.ti, 30)),
            gravity: said.ge ? gravity : null,
            low: limited ? numbers(said.lamin, 3, 0)[2] : -Infinity, high: limited ? numbers(said.lamax, 3, 0)[2] : Infinity,
            tip: Math.hypot(tip[0], tip[1]) > 1e-3 ? [tip[0], tip[1]] : null,
            angle: 0, spin: 0, shift: [0, 0], speed: [0, 0], last: null
          };
        }

        // How strongly gravity pulls on a swaying bone, in pixels of the scene a second squared.
        var SWAY_GRAVITY = 1000;

        // `culls`: whether the picture's material leaves out the backs of its triangles.
        function buildPuppet(said, layers, name, culls, owner) {
          var corners = numbersOf(said.corners, Float32Array);
          var triangles = numbersOf(said.triangles, Uint16Array);
          var count = Math.floor(corners.length / 12);
          var bones = (said.bones || []).map(function (bone) {
            var matrix = bone.matrix || [];
            return { name: typeof bone.name === 'string' ? bone.name : '', parent: number(bone.parent, -1),
                     rest: [matrix[0], matrix[1], matrix[4], matrix[5], matrix[12], matrix[13]], sway: swayOf(bone.physics) };
          });
          if (!count || !triangles.length || !bones.length) return null;
          // Where every bone is at rest, from the picture and not from its parent; and the way back.
          function atRest(index, depth) {
            var bone = bones[index];
            if (!bone.whole) {
              var parent = bones[bone.parent];
              bone.whole = parent && depth < 64 ? joined(atRest(bone.parent, depth + 1), bone.rest) : bone.rest;
            }
            return bone.whole;
          }
          bones.forEach(function (bone, index) { bone.back = undone(atRest(index, 0)); });

          // Points other objects of the scene hang on, by name: the bone each is on, and where it
          // is from the bone.
          var points = {};
          (said.attachments || []).forEach(function (point) {
            var matrix = point.matrix || [];
            var bone = number(point.bone, -1);
            if (typeof point.name !== 'string' || !bones[bone]) return;
            points[point.name] = { bone: bone, rest: [matrix[0], matrix[1], matrix[4], matrix[5], matrix[12], matrix[13]] };
          });

          // The layers of animation the object has, in their order, each with its own clock: the
          // frame it is on, whether it plays, how fast. A script may pause one, put it on a frame,
          // add one that plays once, or take one away. Of those that set the bones, one a script
          // started to play once comes first while it plays; else the first that has not come to
          // its end — one that plays once gives way to the next when it is over. Those that add to
          // them move the bones further, each by how far it takes them from where they are at rest,
          // as much as its blend says.
          var animations = said.animations || [];
          function animationOf(wanted) {
            return animations.filter(function (each) {
              return typeof wanted === 'number' ? each.id === wanted : each.name === wanted || String(each.id) === String(wanted);
            })[0] || null;
          }
          function makeLayer(animation, config) {
            config = config || {};
            return { name: typeof config.name === 'string' ? config.name : (animation.name || ''), animation: animation,
                     frames: numbersOf(animation.frames, Float32Array), frameCount: animation.frameCount, length: animation.length,
                     fps: animation.fps || 30, speed: number(plain(config.rate), 1), mode: animation.mode,
                     adds: flag(config.additive, false), blend: Math.max(0, Math.min(1, number(plain(config.blend), 1))),
                     visible: true, frame: 0, playing: true, done: false, ended: [], once: false };
          }
          var playing = [];
          (layers || []).forEach(function (config) {
            var animation = animationOf(number(plain(config.animation), -1));
            if (!animation) return;
            var layer = makeLayer(animation, config);
            // Whether it shows may be a setting of the wallpaper's, or what a script says; such a
            // script has the layer of animation for `thisObject`.
            layer.shows = live(config.visible === undefined ? true : config.visible, 0, true, owner || null, 'flag');
            if (layer.shows.script) layer.shows.script.animationLayer = function () { return puppet.scriptLayer(layer); };
            layer.visible = layer.shows.now !== false;
            playing.push(layer);
          });
          // A layer's clock moves on; what is said to happen when it comes to its end happens.
          function advance(passed) {
            playing.slice().forEach(function (layer) {
              if (!layer.playing || !(passed > 0)) return;
              var before = layer.frame;
              layer.frame += passed * layer.fps * layer.speed;
              var cycle = layer.mode === 'mirror' ? layer.length * 2 : layer.length;
              if (!(cycle > 0)) return;
              if (layer.mode === 'single' || layer.once) {
                if (layer.frame >= layer.length) {
                  layer.frame = layer.length;
                  layer.playing = false;
                  layer.done = true;
                  ended(layer);
                  if (layer.once) puppet.removeLayer(layer);
                }
              } else if (Math.floor(layer.frame / cycle) > Math.floor(before / cycle)) {
                ended(layer);
              }
            });
          }
          function ended(layer) {
            layer.ended.slice().forEach(function (callback) {
              try {
                callback();
              } catch (error) {
                note('a script fails in what it asked for at the end of an animation: ' + error.message);
              }
            });
          }
          // Each bone at rest from its parent, as the frames have it: place, turn, scale.
          bones.forEach(function (bone) {
            var rest = bone.rest;
            bone.still = [rest[4], rest[5], Math.atan2(rest[1], rest[0]), Math.sqrt(rest[0] * rest[0] + rest[1] * rest[1]),
                          Math.sqrt(rest[2] * rest[2] + rest[3] * rest[3])];
          });
          // Where an animation has a bone on the frame its layer is on: place, turn, scale.
          function sample(layer, index) {
            var at = layer.frame;
            if (layer.mode === 'mirror') {
              at = at % (layer.length * 2);
              if (at > layer.length) at = layer.length * 2 - at;
            } else if (layer.mode === 'single') {
              at = Math.min(at, layer.length);
            } else {
              at = at % layer.length;
            }
            var before = Math.min(Math.floor(at), layer.frameCount - 1);
            var after = Math.min(before + 1, layer.frameCount - 1);
            var share = at - before;
            var one = (index * layer.frameCount + before) * 9, two = (index * layer.frameCount + after) * 9;
            function value(part) { return layer.frames[one + part] + (layer.frames[two + part] - layer.frames[one + part]) * share; }
            return [value(0), value(1), value(5), value(6), value(7)];
          }

          var places = new Float32Array(count * 2);
          var spots = new Float32Array(count * 2);
          for (var corner = 0; corner < count; corner++) {
            places[corner * 2] = corners[corner * 12];
            places[corner * 2 + 1] = corners[corner * 12 + 1];
            spots[corner * 2] = corners[corner * 12 + 2];
            spots[corner * 2 + 1] = corners[corner * 12 + 3];
          }
          var shape = gl.createVertexArray();
          gl.bindVertexArray(shape);
          var placeBuffer = gl.createBuffer();
          gl.bindBuffer(gl.ARRAY_BUFFER, placeBuffer);
          gl.bufferData(gl.ARRAY_BUFFER, places, gl.DYNAMIC_DRAW);
          gl.enableVertexAttribArray(5);
          gl.vertexAttribPointer(5, 2, gl.FLOAT, false, 0, 0);
          gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
          gl.bufferData(gl.ARRAY_BUFFER, spots, gl.STATIC_DRAW);
          gl.enableVertexAttribArray(6);
          gl.vertexAttribPointer(6, 2, gl.FLOAT, false, 0, 0);
          var triangleBuffer = gl.createBuffer();
          gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, triangleBuffer);
          gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, triangles, gl.DYNAMIC_DRAW);
          gl.bindVertexArray(null);

          var swaying = bones.some(function (bone) { return bone.sway; });
          var puppet = { shape: shape, count: triangles.length, moving: playing.length > 0 || swaying, layers: playing, bones: bones };
          // Which way round a triangle's corners go when its face is seen: as most go at rest. A
          // puppet may turn part of itself over to hide it — an eye closing folds the eyeball
          // under the lid — and with a material that leaves out backs, what is turned over is
          // not drawn.
          function turn(corners, at) {
            var a = triangles[at], b = triangles[at + 1], c = triangles[at + 2];
            return (corners[b * 2] - corners[a * 2]) * (corners[c * 2 + 1] - corners[a * 2 + 1]) -
                   (corners[c * 2] - corners[a * 2]) * (corners[b * 2 + 1] - corners[a * 2 + 1]);
          }
          var facing = 0;
          for (var each = 0; each < triangles.length; each += 3) facing += turn(places, each) >= 0 ? 1 : -1;
          facing = facing >= 0 ? 1 : -1;
          var shown = culls ? new Uint16Array(triangles.length) : null;
          // Its parts, in the order they are drawn — all of it as one where the file does not say
          // or says what does not add up — and where each one's triangles are in what is drawn.
          var parts = (Array.isArray(said.parts) ? said.parts : []).map(function (part) { return [number(part[0], 0), number(part[1], 0)]; });
          var covered = parts.reduce(function (sum, part) { return sum + part[1]; }, 0);
          if (!parts.length || covered !== triangles.length) parts = [[0, triangles.length]];
          puppet.parts = parts.map(function (part) { return part.slice(); });
          // Parts shown only within others.
          puppet.clips = (said.clips || []).map(function (clip) {
            var picture = String(clip.texture || '');
            return { part: number(clip.part, -1), masks: (clip.masks || []).map(function (each) { return number(each, -1); }),
                     picture: picture ? texture('materials/' + picture) : null };
          }).filter(function (clip) { return parts[clip.part] && parts.length > 1; });
          // Where a point to hang things on is as the picture was last posed, in the picture's own
          // pixels from its middle; null for a point the puppet does not have.
          puppet.attachmentNames = Object.keys(points);
          puppet.attachment = function (name) {
            var point = points[name];
            if (!point) return null;
            var bone = bones[point.bone];
            return joined(bone.moved || atRest(point.bone, 0), point.rest);
          };
          // Layers of animation made by scripts: by an animation's name or number, or by what a
          // layer is described by in a scene. One made to play once goes away when it is over.
          puppet.addLayer = function (wanted, config, once) {
            var described = wanted && typeof wanted === 'object' ? wanted : (config || {});
            var asked = wanted && typeof wanted === 'object' ? (wanted.animation !== undefined ? wanted.animation : wanted.name) : wanted;
            var animation = animationOf(asked);
            // A script may name a layer of the object for its animation.
            if (!animation) {
              var named = puppet.findLayer(String(asked));
              animation = named ? named.animation : null;
            }
            if (!animation) return null;
            var layer = makeLayer(animation, described);
            if (described.visible !== undefined) layer.visible = flag(described.visible, true);
            layer.once = !!once;
            playing.push(layer);
            puppet.moving = true;
            if (owner) owner.moving = true;
            changed();
            return layer;
          };
          puppet.removeLayer = function (layer) {
            var at = playing.indexOf(layer);
            if (at < 0) return false;
            playing.splice(at, 1);
            changed();
            return true;
          };
          puppet.findLayer = function (wanted) {
            if (typeof wanted === 'number') return playing[wanted] || null;
            if (wanted && typeof wanted === 'object') return playing.filter(function (layer) { return layer.forScripts === wanted; })[0] || null;
            return playing.filter(function (layer) { return layer.name === wanted; })[0] || null;
          };
          // A layer of animation as scripts have it.
          puppet.scriptLayer = function (layer) {
            if (!layer.forScripts) {
              layer.forScripts = lenient({
                get fps() { return layer.fps; },
                get frameCount() { return layer.frameCount; },
                get duration() { return layer.length / (layer.fps || 30); },
                get name() { return layer.name; },
                set name(value) { layer.name = String(value); },
                get rate() { return layer.speed; },
                set rate(value) { layer.speed = Number(value) || 0; },
                get blend() { return layer.blend; },
                set blend(value) { layer.blend = Math.max(0, Math.min(1, Number(value) || 0)); changed(); },
                get visible() { return layer.visible; },
                set visible(value) { layer.visible = !!value; changed(); },
                play: function () {
                  if (layer.done) {
                    layer.frame = 0;
                    layer.done = false;
                  }
                  layer.playing = true;
                  if (owner) owner.moving = true;
                  changed();
                },
                pause: function () { layer.playing = false; },
                stop: function () {
                  layer.playing = false;
                  layer.frame = 0;
                  layer.done = false;
                  changed();
                },
                isPlaying: function () { return layer.playing; },
                // Where in the animation it is, its repeats left out.
                getFrame: function () {
                  var length = layer.length > 0 ? layer.length : 1;
                  if (layer.mode === 'single' || layer.once) return Math.min(layer.frame, length);
                  if (layer.mode === 'mirror') {
                    var at = layer.frame % (length * 2);
                    return at > length ? length * 2 - at : at;
                  }
                  return layer.frame % length;
                },
                setFrame: function (frame) {
                  layer.frame = Math.max(0, Number(frame) || 0);
                  layer.done = false;
                  changed();
                },
                addEndedCallback: function (callback) { if (typeof callback === 'function') layer.ended.push(callback); }
              });
            }
            return layer.forScripts;
          };
          // What scripts have set of a bone, in place of what the animations say: where it is from
          // its parent and how it is turned and scaled there.
          puppet.overridden = false;
          puppet.boneIndex = function (wanted) {
            if (typeof wanted === 'number') return bones[wanted] ? wanted : -1;
            for (var i = 0; i < bones.length; i++) if (bones[i].name === wanted) return i;
            return -1;
          };
          puppet.localPose = function (index) {
            var bone = bones[index];
            if (!bone) return null;
            var now = bone.now || bone.rest;
            var pose = [now[4], now[5], Math.atan2(now[1], now[0]), Math.sqrt(now[0] * now[0] + now[1] * now[1]), Math.sqrt(now[2] * now[2] + now[3] * now[3])];
            // What a script has set shows from the next frame on, and is read back at once.
            var override = bone.override;
            if (override) {
              if (override.origin) {
                pose[0] = override.origin[0];
                pose[1] = override.origin[1];
              }
              if (override.angle !== undefined) pose[2] = override.angle;
              if (override.scale) {
                pose[3] = override.scale[0];
                pose[4] = override.scale[1];
              }
            }
            return pose;
          };
          puppet.setLocal = function (index, change) {
            var bone = bones[index];
            if (!bone) return;
            var pose = puppet.localPose(index);
            bone.override = bone.override || {};
            if (change.origin) bone.override.origin = change.origin;
            if (change.angle !== undefined) bone.override.angle = change.angle;
            if (change.scale) bone.override.scale = change.scale;
            if (!bone.override.origin) bone.override.origin = [pose[0], pose[1]];
            puppet.overridden = true;
            if (owner) owner.moving = true;
            changed();
          };
          puppet.worldOf = function (index) {
            var bone = bones[index];
            return bone ? (bone.moved || atRest(index, 0)) : null;
          };
          // A bone that sways: where the animation puts it, then turned and moved further by what
          // it keeps of its own motion. It is moved in the scene — by its parent, the animation,
          // the object it is on — and lags behind, swings, and comes back as a spring does, or
          // hangs as gravity has it. `above`: where its parent is in the picture; `placed`: where
          // the picture is in the scene.
          function sway(bone, above, placed, passed) {
            var state = bone.sway;
            var m = placed || [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
            var inScene = [m[0], m[1], m[4], m[5], m[12], m[13]];
            var animated = above ? joined(above, bone.now) : bone.now;
            var world = joined(inScene, animated);
            var root = [world[4], world[5]];
            var angle = Math.atan2(world[1], world[0]);
            var tipLocal = state.tip || [50, 0];
            var tip = [world[0] * tipLocal[0] + world[2] * tipLocal[1], world[1] * tipLocal[0] + world[3] * tipLocal[1]];
            var length = Math.max(1, Math.hypot(tip[0], tip[1]));
            var last = state.last;
            // How fast the root moves and turns, and how that changes: what the bone lags behind.
            var push = [0, 0], twist = 0;
            if (last && passed > 0) {
              var step = Math.min(passed, 0.1);
              var velocity = [(root[0] - last.root[0]) / step, (root[1] - last.root[1]) / step];
              var turn = angle - last.angle;
              turn = Math.atan2(Math.sin(turn), Math.cos(turn)) / step;
              if (last.velocity) {
                push = [(velocity[0] - last.velocity[0]) / step, (velocity[1] - last.velocity[1]) / step];
                twist = (turn - last.turn) / step;
              }
              // A jump — a new loop of the animation, a scene put elsewhere — is not a push.
              var most = 20 * SWAY_GRAVITY;
              var strength = Math.hypot(push[0], push[1]);
              if (strength > most) push = [push[0] * most / strength, push[1] * most / strength];
              twist = Math.max(-200, Math.min(200, twist));
              state.last = { root: root, angle: angle, velocity: velocity, turn: turn };
            } else {
              state.last = { root: root, angle: angle, velocity: null, turn: 0 };
            }
            var pull = state.gravity ? [state.gravity[0] * SWAY_GRAVITY, state.gravity[1] * SWAY_GRAVITY] : [0, 0];
            var left = Math.min(passed, 0.1);
            while (left > 1e-6) {
              var dt = Math.min(left, 1 / 120);
              left -= dt;
              if (state.turns) {
                // What pulls across the bone, at its tip, turns it.
                var now = Math.atan2(tip[1], tip[0]) + state.angle;
                var across = [-Math.sin(now), Math.cos(now)];
                var force = ((pull[0] - push[0]) * across[0] + (pull[1] - push[1]) * across[1]) / length;
                var spin = force - twist + (-state.stiff * state.angle - state.friction * state.spin) / state.weight;
                state.spin += spin * dt;
                state.angle += state.spin * dt;
                if (state.angle < state.low) { state.angle = state.low; state.spin = Math.max(0, state.spin); }
                if (state.angle > state.high) { state.angle = state.high; state.spin = Math.min(0, state.spin); }
              }
              if (state.moves) {
                for (var axis = 0; axis < 2; axis++) {
                  var speedUp = pull[axis] - push[axis] + (-state.moveStiff * state.shift[axis] - state.moveFriction * state.speed[axis]) / state.moveWeight;
                  state.speed[axis] += speedUp * dt;
                  state.shift[axis] += state.speed[axis] * dt;
                }
                // Hanging free, it goes no further than its own length.
                var far = Math.hypot(state.shift[0], state.shift[1]);
                if (!state.spring && far > length) {
                  state.shift = [state.shift[0] * length / far, state.shift[1] * length / far];
                  state.speed = [0, 0];
                }
              }
            }
            if (!isFinite(state.angle) || !isFinite(state.shift[0]) || !isFinite(state.shift[1])) puppet.resetSway(bone);
            // Back from the scene into the parent's coordinates: the turn as it is, the move
            // through the parent and the picture.
            var now2 = bone.now.slice();
            if (state.angle) {
              var c = Math.cos(state.angle), s2 = Math.sin(state.angle);
              now2 = [c * now2[0] - s2 * now2[1], s2 * now2[0] + c * now2[1], c * now2[2] - s2 * now2[3], s2 * now2[2] + c * now2[3], now2[4], now2[5]];
            }
            if (state.shift[0] || state.shift[1]) {
              var outer = above ? joined(inScene, above) : inScene;
              var back = undone(outer);
              now2[4] += back[0] * state.shift[0] + back[2] * state.shift[1];
              now2[5] += back[1] * state.shift[0] + back[3] * state.shift[1];
            }
            bone.now = now2;
          }
          puppet.resetSway = function (bone) {
            var state = bone && bone.sway;
            if (!state) return;
            state.angle = state.spin = 0;
            state.shift = [0, 0];
            state.speed = [0, 0];
            state.last = null;
          };
          // A push given by a script: a bone, or all of them, moved and turned faster at once.
          puppet.pushSway = function (index, moving, turning) {
            bones.forEach(function (bone, at) {
              if (!bone.sway || (index >= 0 && at !== index)) return;
              bone.sway.speed[0] += moving[0];
              bone.sway.speed[1] += moving[1];
              bone.sway.spin += turning;
            });
            if (owner) owner.moving = true;
            changed();
          };

          // Puts every corner where the bones are at a moment of the scene.
          var lastSeconds = null;
          puppet.pose = function (seconds, placed) {
            var passed = lastSeconds === null ? 0 : Math.max(0, seconds - lastSeconds);
            lastSeconds = seconds;
            advance(passed);
            playing.forEach(function (layer) {
              if (layer.shows) layer.visible = layer.shows.read() !== false;
            });
            var showing = playing.filter(function (layer) { return layer.visible; });
            if (!showing.length && !puppet.overridden && !swaying) return;
            var setting = showing.filter(function (layer) { return !layer.adds; });
            var adding = showing.filter(function (layer) { return layer.adds; });
            var once = setting.filter(function (layer) { return layer.once && !layer.done; });
            var base = once[once.length - 1] || setting.filter(function (layer) { return layer.mode !== 'single' || !layer.done; })[0] ||
                       setting[setting.length - 1] || null;
            // Each bone from its parent in this frame: scaled, turned, then moved.
            bones.forEach(function (bone, index) {
              var pose = base ? sample(base, index) : bone.still.slice();
              if (base && base.blend < 1) {
                for (var part = 0; part < 5; part++) pose[part] = bone.still[part] + (pose[part] - bone.still[part]) * base.blend;
              }
              adding.forEach(function (layer) {
                var more = sample(layer, index);
                pose[0] += (more[0] - bone.still[0]) * layer.blend;
                pose[1] += (more[1] - bone.still[1]) * layer.blend;
                pose[2] += (more[2] - bone.still[2]) * layer.blend;
                if (bone.still[3] > 1e-6) pose[3] *= 1 + (more[3] / bone.still[3] - 1) * layer.blend;
                if (bone.still[4] > 1e-6) pose[4] *= 1 + (more[4] / bone.still[4] - 1) * layer.blend;
              });
              var override = bone.override;
              if (override) {
                if (override.origin) {
                  pose[0] = override.origin[0];
                  pose[1] = override.origin[1];
                }
                if (override.angle !== undefined) pose[2] = override.angle;
                if (override.scale) {
                  pose[3] = override.scale[0];
                  pose[4] = override.scale[1];
                }
              }
              var cos = Math.cos(pose[2]), sin = Math.sin(pose[2]);
              bone.now = [cos * pose[3], sin * pose[3], -sin * pose[4], cos * pose[4], pose[0], pose[1]];
              bone.done = false;
            });
            function whole(index, depth) {
              var bone = bones[index];
              if (!bone.done) {
                var parent = bones[bone.parent];
                var above = parent && depth < 64 ? whole(bone.parent, depth + 1) : null;
                if (bone.sway) sway(bone, above, placed, passed);
                bone.moved = above ? joined(above, bone.now) : bone.now;
                // From where the corner is at rest to where the bone has taken it.
                bone.takes = joined(bone.moved, bone.back);
                bone.done = true;
              }
              return bone.moved;
            }
            bones.forEach(function (bone, index) { whole(index, 0); });
            for (var corner = 0; corner < count; corner++) {
              var base = corner * 12;
              var x = corners[base], y = corners[base + 1];
              var newX = 0, newY = 0, total = 0;
              for (var slot = 0; slot < 4; slot++) {
                var weight = corners[base + 8 + slot];
                var bone = bones[corners[base + 4 + slot]];
                if (!(weight > 0) || !bone) continue;
                var takes = bone.takes;
                newX += weight * (takes[0] * x + takes[2] * y + takes[4]);
                newY += weight * (takes[1] * x + takes[3] * y + takes[5]);
                total += weight;
              }
              places[corner * 2] = total > 0 ? newX / total : x;
              places[corner * 2 + 1] = total > 0 ? newY / total : y;
            }
            gl.bindBuffer(gl.ARRAY_BUFFER, placeBuffer);
            gl.bufferSubData(gl.ARRAY_BUFFER, 0, places);
            if (shown) {
              var kept = 0;
              parts.forEach(function (part, index) {
                var from = kept;
                for (var at = part[0]; at < part[0] + part[1]; at += 3) {
                  if (turn(places, at) * facing < 0) continue;
                  shown[kept++] = triangles[at];
                  shown[kept++] = triangles[at + 1];
                  shown[kept++] = triangles[at + 2];
                }
                puppet.parts[index] = [from, kept - from];
              });
              gl.bindVertexArray(shape);
              gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, triangleBuffer);
              gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, shown.subarray(0, kept));
              gl.bindVertexArray(null);
              puppet.count = kept;
            }
          };
          return puppet;
        }
        // --- Models in three dimensions --------------------------------------
        //
        // A scene may hold models: meshes with a picture laid over them, lit by the scene's lights,
        // by the light that comes from everywhere (ambient) and from the sky above. Wallpaper
        // Engine's own shaders for them are not in the wallpapers; they are drawn here by one of the
        // player's own, much as Wallpaper Engine lights them: what faces a light is lit by it, as
        // much as is left of it at that distance, with a shine as sharp as the material is smooth
        // and of the picture's own color as far as it is metal.

        var MAX_LIGHTS = 8;
        var modelProgram = link([
          '#version 300 es',
          'in vec3 a_Position;',
          'in vec3 a_Normal;',
          'in vec2 a_TexCoord;',
          'uniform mat4 u_Model;',
          'uniform mat4 u_ViewProjection;',
          'uniform mat3 u_NormalMatrix;',
          'out vec3 v_World;',
          'out vec3 v_Normal;',
          'out vec2 v_Uv;',
          'void main() {',
          '  vec4 world = u_Model * vec4(a_Position, 1.0);',
          '  v_World = world.xyz;',
          '  v_Normal = u_NormalMatrix * a_Normal;',
          '  v_Uv = a_TexCoord;',
          '  gl_Position = u_ViewProjection * world;',
          '}'
        ].join('\n'), [
          '#version 300 es',
          'precision highp float;',
          'in vec3 v_World;',
          'in vec3 v_Normal;',
          'in vec2 v_Uv;',
          'uniform sampler2D u_Texture;',
          'uniform int u_Channels;',
          'uniform vec4 u_Tint;',
          'uniform vec3 u_Ambient;',
          'uniform vec3 u_Sky;',
          'uniform vec3 u_Eye;',
          'uniform float u_Metallic;',
          'uniform float u_Roughness;',
          'uniform int u_LightCount;',
          'uniform vec4 u_LightPlace[' + MAX_LIGHTS + '];', // where (w 1), or which way it shines (w 0)
          'uniform vec4 u_LightColor[' + MAX_LIGHTS + '];', // color times strength, and how far it reaches
          'uniform vec4 u_LightAim[' + MAX_LIGHTS + '];',   // which way a spot points, and how fast it fades
          'out vec4 color;',
          'void main() {',
          '  vec4 base = texture(u_Texture, v_Uv);',
          '  if (u_Channels == 1) base = vec4(1.0, 1.0, 1.0, base.r);',
          '  if (u_Channels == 2) base = vec4(base.rrr, base.g);',
          '  base *= u_Tint;',
          '  vec3 n = normalize(v_Normal);',
          '  if (!gl_FrontFacing) n = -n;',
          '  vec3 toEye = normalize(u_Eye - v_World);',
          '  vec3 diffuse = base.rgb * (1.0 - u_Metallic);',
          '  vec3 shineColor = mix(vec3(0.04), base.rgb, u_Metallic);',
          '  float rough = clamp(u_Roughness, 0.03, 1.0);',
          '  float sharp = max(1.0, 2.0 / (rough * rough * rough * rough) - 2.0);',
          '  vec3 lit = u_Ambient * base.rgb + u_Sky * base.rgb * (0.5 + 0.5 * n.y);',
          '  for (int i = 0; i < ' + MAX_LIGHTS + '; i++) {',
          '    if (i >= u_LightCount) break;',
          '    vec3 toLight;',
          '    float left = 1.0;',
          '    if (u_LightPlace[i].w > 0.5) {',
          '      vec3 way = u_LightPlace[i].xyz - v_World;',
          '      float far = length(way);',
          '      toLight = way / max(far, 0.0001);',
          '      float reach = u_LightColor[i].w;',
          '      if (reach > 0.0) left = pow(clamp(1.0 - far / reach, 0.0, 1.0), max(u_LightAim[i].w, 0.01));',
          '      if (dot(u_LightAim[i].xyz, u_LightAim[i].xyz) > 0.0) left *= smoothstep(0.5, 0.9, dot(-toLight, normalize(u_LightAim[i].xyz)));',
          '    } else {',
          '      toLight = normalize(-u_LightPlace[i].xyz);',
          '    }',
          '    float facing = max(dot(n, toLight), 0.0);',
          '    vec3 halfway = normalize(toLight + toEye);',
          '    float shine = pow(max(dot(n, halfway), 0.0), sharp) * (sharp + 8.0) / 25.0;',
          '    lit += u_LightColor[i].rgb * left * facing * (diffuse + shineColor * shine);',
          '  }',
          '  color = vec4(lit, base.a);',
          '}'
        ].join('\n'), 'the player\'s own shader');

        // The lights of the scene as they are now, for the models: at most so many, the strongest.
        function sceneLights() {
          var list = [];
          objects.forEach(function (thing) {
            if (!thing.lightKind) return;
            var stands = standing(thing, true);
            if (!stands.visible) return;
            var m = stands.matrix;
            var shade = thing.state.color || [1, 1, 1];
            var strength = number((thing.state.intensity || [])[0], 1);
            // Which way it shines: down its own z axis.
            var aim = [-m[8], -m[9], -m[10]];
            var length = Math.sqrt(aim[0] * aim[0] + aim[1] * aim[1] + aim[2] * aim[2]) || 1;
            aim = aim.map(function (part) { return part / length; });
            list.push({
              place: thing.lightKind === 'directional' ? [aim[0], aim[1], aim[2], 0] : [m[12], m[13], m[14], 1],
              color: [shade[0] * strength, shade[1] * strength, shade[2] * strength, number((thing.state.radius || [])[0], 0)],
              aim: thing.lightKind === 'spot' ? [aim[0], aim[1], aim[2], number((thing.state.exponent || [])[0], 1)] : [0, 0, 0, number((thing.state.exponent || [])[0], 1)],
              strength: strength
            });
          });
          list.sort(function (a, b) { return b.strength - a.strength; });
          return list.slice(0, MAX_LIGHTS);
        }

        // From the scene to where it lands on what is drawn on: the scene's own flat view, with
        // nearer for larger z; or, for a scene seen through a lens, from in front of its middle.
        function viewProjection() {
          var w = surface.width, h = surface.height;
          var far = Math.max(1, number(general.farz, 10000));
          // What is drawn is kept with its top row first, as the pictures are: y is turned over.
          if (general.orthogonalprojection) {
            return [2 / w, 0, 0, 0, 0, -2 / h, 0, 0, 0, 0, -1 / far, 0,
                    -1 - 2 * surface.left / w, 1 + 2 * surface.bottom / h, 0, 1];
          }
          var fov = number(general.perspectiveoverridefov, number(general.fov, 50)) * Math.PI / 180;
          var away = (sceneHeight / 2) / Math.tan(fov / 2);
          var near = Math.max(0.01, number(general.nearz, 0.01)), f = 1 / Math.tan(fov / 2), aspect = w / h;
          var lens = [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), -1, 0, 0, 2 * far * near / (near - far), 0];
          var look = Mat4.lookAt(new Vec3(sceneWidth / 2, sceneHeight / 2, away), new Vec3(sceneWidth / 2, sceneHeight / 2, 0), new Vec3(0, 1, 0)).m;
          var seen = times4(lens, look);
          [1, 5, 9, 13].forEach(function (index) { seen[index] = -seen[index]; });
          return seen;
        }

        function buildModel(object, thing) {
          var name = String(plain(object.model) || '');
          var mesh = puppets[key(name)];
          if (!mesh || !mesh.solid || !modelProgram) {
            note('“' + thing.name + '”: its model, ' + name + ', ' + (mesh ? 'has no faces to light' : 'is not in the scene') + '; it is left out');
            return null;
          }
          // A model may be made of several parts, each drawn with a material of its own: a body,
          // a face, hair. The first is the file's own; the scene may name another material for it.
          var given = [{ solid: mesh.solid, triangles: mesh.triangles, material: object.material || mesh.material }]
            .concat((mesh.pieces || []).map(function (piece) { return { solid: piece.solid, triangles: piece.triangles, material: piece.material }; }));
          var low = [Infinity, Infinity, Infinity], high = [-Infinity, -Infinity, -Infinity];
          var parts = given.map(function (piece) {
            var corners = numbersOf(piece.solid, Float32Array);
            var triangles = numbersOf(piece.triangles, Uint16Array);
            var count = Math.floor(corners.length / 8);
            if (!count || !triangles.length) return null;
            for (var corner = 0; corner < count; corner++) {
              for (var axis = 0; axis < 3; axis++) {
                low[axis] = Math.min(low[axis], corners[corner * 8 + axis]);
                high[axis] = Math.max(high[axis], corners[corner * 8 + axis]);
              }
            }
            var material = json(String(piece.material || '')) || {};
            var pass = (material.passes || [])[0] || {};
            var constants = {};
            Object.keys(pass.constantshadervalues || {}).forEach(function (each) { constants[key(each)] = pass.constantshadervalues[each]; });
            var shape = gl.createVertexArray();
            gl.bindVertexArray(shape);
            gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
            gl.bufferData(gl.ARRAY_BUFFER, corners, gl.STATIC_DRAW);
            gl.enableVertexAttribArray(0);
            gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 32, 0);
            gl.enableVertexAttribArray(8);
            gl.vertexAttribPointer(8, 3, gl.FLOAT, false, 32, 12);
            gl.enableVertexAttribArray(1);
            gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 32, 24);
            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
            gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, triangles, gl.STATIC_DRAW);
            gl.bindVertexArray(null);
            return {
              corners: corners, count: count, shape: shape, length: triangles.length,
              picture: (pass.textures || [])[0] ? texture('materials/' + pass.textures[0]) : null,
              culls: key(String(pass.cullmode || 'normal')) !== 'nocull',
              tests: key(String(pass.depthtest || 'enabled')) !== 'disabled',
              writes: key(String(pass.depthwrite || 'enabled')) !== 'disabled',
              blending: key(String(pass.blending || 'normal')),
              metallic: number(plain(constants.metallic), 0), roughness: number(plain(constants.roughness), 0.5)
            };
          }).filter(Boolean);
          if (!parts.length) return null;
          // How large it is, for what is said to bounce off it.
          var middle = [(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2];
          var radius = 0;
          parts.forEach(function (part) {
            for (var corner = 0; corner < part.count; corner++) {
              radius = Math.max(radius, Math.hypot(part.corners[corner * 8] - middle[0], part.corners[corner * 8 + 1] - middle[1], part.corners[corner * 8 + 2] - middle[2]));
            }
          });
          thing.bounds = { middle: middle, radius: radius };
          var white = null;
          thing.draw = function () {
            var stands = standing(thing);
            if (!stands.visible) return;
            var target = surface.target;
            depthOf(target);
            gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
            gl.viewport(0, 0, target.width, target.height);
            var program = modelProgram;
            // A uniform the compiler left out has no place; setting it at none does nothing.
            function at(name) { var uniform = program.uniforms[name]; return uniform ? uniform.location : null; }
            gl.useProgram(program.program);
            var model = stands.matrix;
            gl.uniformMatrix4fv(at('u_Model'), false, new Float32Array(model));
            gl.uniformMatrix4fv(at('u_ViewProjection'), false, new Float32Array(viewProjection()));
            gl.uniformMatrix3fv(at('u_NormalMatrix'), false, new Float32Array(new Mat4(model).normalMatrix().m));
            var tint = thing.state.color || [1, 1, 1];
            gl.uniform4f(at('u_Tint'), tint[0], tint[1], tint[2], stands.alpha);
            var ambient = numbers(general.ambientcolor, 3, 0), sky = numbers(general.skylightcolor, 3, 0);
            gl.uniform3f(at('u_Ambient'), ambient[0], ambient[1], ambient[2]);
            gl.uniform3f(at('u_Sky'), sky[0], sky[1], sky[2]);
            gl.uniform3f(at('u_Eye'), sceneWidth / 2, sceneHeight / 2, Math.max(sceneWidth, sceneHeight) * 4);
            var lights = sceneLights();
            gl.uniform1i(at('u_LightCount'), lights.length);
            if (lights.length) {
              var places = [], shades = [], aims = [];
              lights.forEach(function (light) { places.push.apply(places, light.place); shades.push.apply(shades, light.color); aims.push.apply(aims, light.aim); });
              gl.uniform4fv(at('u_LightPlace'), new Float32Array(places));
              gl.uniform4fv(at('u_LightColor'), new Float32Array(shades));
              gl.uniform4fv(at('u_LightAim'), new Float32Array(aims));
            }
            gl.depthFunc(gl.LEQUAL);
            // Turned over, the faces that look this way go round the other way.
            gl.frontFace(gl.CW);
            gl.enable(gl.BLEND);
            gl.activeTexture(gl.TEXTURE0);
            gl.uniform1i(at('u_Texture'), 0);
            parts.forEach(function (part) {
              gl.uniform1f(at('u_Metallic'), part.metallic);
              gl.uniform1f(at('u_Roughness'), part.roughness);
              var layer = part.picture && part.picture.ready !== false ? part.picture.layers[0] : null;
              if (!layer) white = white || flat(255, 255, 255, 255);
              gl.bindTexture(gl.TEXTURE_2D, (layer || white.layers[0]).texture);
              gl.uniform1i(at('u_Channels'), layer ? (CHANNELS[part.picture.channels] || 0) : 0);
              if (part.tests) gl.enable(gl.DEPTH_TEST); else gl.disable(gl.DEPTH_TEST);
              gl.depthMask(part.writes);
              if (part.culls) gl.enable(gl.CULL_FACE); else gl.disable(gl.CULL_FACE);
              if (part.blending === 'additive') gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
              else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
              gl.bindVertexArray(part.shape);
              gl.drawElements(gl.TRIANGLES, part.length, gl.UNSIGNED_SHORT, 0);
            });
            gl.bindVertexArray(null);
            gl.disable(gl.DEPTH_TEST);
            gl.disable(gl.CULL_FACE);
            gl.frontFace(gl.CCW);
            gl.depthMask(true);
          };
          return thing;
        }

        // A light: where it is, its color and strength, how far it reaches and how fast it fades
        // there. A light that shines from far away in one direction has no place, only a way.
        function buildLight(object, thing) {
          var kind = key(String(plain(object.light) || 'lpoint'));
          thing.lightKind = /dir|sun/.test(kind) ? 'directional' : (/spot/.test(kind) ? 'spot' : 'point');
          also(thing, 'intensity', live(object.intensity === undefined ? 1 : object.intensity, 1, 1, thing));
          also(thing, 'radius', live(object.radius === undefined ? 0 : object.radius, 1, 0, thing));
          also(thing, 'exponent', live(object.exponent === undefined ? 1 : object.exponent, 1, 1, thing));
          return thing;
        }

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
          thing.lives.origin = live(object.origin, 3, hangs ? 0 : [sceneWidth / 2, sceneHeight / 2, 0], thing);
          thing.lives.scale = live(object.scale, 3, 1, thing);
          thing.lives.angles = live(object.angles, 3, 0, thing, 'numbers', 'degrees');
          thing.lives.alpha = live(object.alpha, 1, 1, thing);
          thing.lives.color = live(object.color, 3, 1, thing);
          thing.lives.visible = live(object.visible, 0, true, thing, 'flag');
          thing.state.parallax = numbers(object.parallaxDepth, 2, 1);
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
            // Drawn into the layer that holds it, an object is placed in that layer's own
            // coordinates; the layer's place is added when the layer is drawn.
            if (!parent.holds || whole) {
              // An object the scene gives no place stands, for what hangs on it, where Wallpaper
              // Engine puts it: at the scene's corner, not in its middle, where it is drawn — a
              // layer over the whole screen, say, whose pictures are placed by the scene's pixels.
              var base = up.matrix;
              if (parent.parent === undefined && !isSet(parent.said && parent.said.origin)) {
                base = base.slice();
                base[12] -= sceneWidth / 2;
                base[13] -= sceneHeight / 2;
              }
              matrix = times(base, matrix);
            }
          } else {
            if ((eye && eye.on) || (shake && shake.on)) {
              // What hangs together moves with the pointer together, and shakes with the camera.
              var moved = shifted(thing);
              matrix[12] += moved[0] + (shake ? shake.x : 0);
              matrix[13] += moved[1] + (shake ? shake.y : 0);
            }
            if (camera && (camera.x || camera.y || camera.zoom !== 1)) {
              // Where a script has put the camera: the scene seen from there, nearer or further.
              var cx = sceneWidth / 2, cy = sceneHeight / 2;
              [0, 1, 4, 5].forEach(function (index) { matrix[index] *= camera.zoom; });
              matrix[12] = cx + (matrix[12] - cx - camera.x) * camera.zoom;
              matrix[13] = cy + (matrix[13] - cy - camera.y) * camera.zoom;
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
              return { name: key(target.name), scale: Math.max(1, number(target.scale, 1)), fit: Math.max(0, number(target.fit, 0)) };
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
                } else if (/^_rt_/.test(key(name))) {
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
            if (!layer.holds) layer.takesScene = true;
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
            size = [number(model && model.width, 0) || (layer.picture && layer.picture.width > 1 ? layer.picture.width : sceneWidth),
                    number(model && model.height, 0) || (layer.picture && layer.picture.height > 1 ? layer.picture.height : sceneHeight)];
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
          // A picture that bends, if its bones came with the scene and could be read.
          var bends = model && model.puppet ? puppets[key(model.puppet)] : null;
          if (bends) {
            layer.puppet = buildPuppet(bends, object.animationlayers, layer.name, key(String(base.cullmode || 'normal')) !== 'nocull', layer);
            if (layer.puppet && layer.puppet.moving) layer.moving = true;
          } else if (model && model.puppet) {
            note('“' + layer.name + '” is a picture that bends, but its bones could not be read; it is shown still');
          }
          buildEffects(layer, object);
          // What takes the scene under it changes whenever anything under it does.
          if (layer.takesScene) layer.moving = true;
          layer.draw = function () { drawImage(layer); };
          return layer;
        }

        // --- Texts ------------------------------------------------------------
        //
        // A text is drawn by the browser into a picture of its own, anew whenever it says
        // something else, and then put on the scene like any picture.

        var fontFiles = (scene && scene.fonts) || {};
        var fontsMade = {};
        var fontsThere = 0; // how many of them have arrived
        // Fonts of Windows by the names Wallpaper Engine has for them, each with what a Mac has
        // that is nearest to it.
        var KNOWN_FONTS = {
          arial: 'Arial, Helvetica', arialblack: '"Arial Black", Arial', consolas: 'Consolas, Menlo, Monaco, monospace',
          couriernew: '"Courier New", Courier, monospace', lucidaconsole: '"Lucida Console", Menlo, monospace',
          cascadiacode: '"Cascadia Code", Menlo, monospace', cascadiamono: '"Cascadia Mono", Menlo, monospace',
          timesnewroman: '"Times New Roman", Times, serif', georgia: 'Georgia, serif', cambria: 'Cambria, Georgia, serif',
          constantia: 'Constantia, Georgia, serif', palatinolinotype: '"Palatino Linotype", Palatino, serif',
          bookantiqua: '"Book Antiqua", Palatino, serif', garamond: 'Garamond, Georgia, serif', sylfaen: 'Sylfaen, Georgia, serif',
          verdana: 'Verdana', tahoma: 'Tahoma', trebuchetms: '"Trebuchet MS"', impact: 'Impact', comicsansms: '"Comic Sans MS"',
          segoeui: '"Segoe UI", -apple-system', segoeuilight: '"Segoe UI Light", -apple-system',
          segoeuisemibold: '"Segoe UI Semibold", -apple-system', segoeuiblack: '"Segoe UI Black", -apple-system',
          calibri: 'Calibri, "Helvetica Neue"', candara: 'Candara, "Helvetica Neue"', corbel: 'Corbel, "Helvetica Neue"',
          centurygothic: '"Century Gothic", Futura', franklingothicmedium: '"Franklin Gothic Medium", "Helvetica Neue"',
          bahnschrift: 'Bahnschrift, "DIN Alternate", "Helvetica Neue"', lucidasansunicode: '"Lucida Sans Unicode", "Lucida Grande"',
          microsoftsansserif: '"Microsoft Sans Serif", Helvetica', segoeprint: '"Segoe Print", "Bradley Hand"',
          segoescript: '"Segoe Script", "Snell Roundhand"', inkfree: '"Ink Free", "Bradley Hand"',
          microsoftyahei: '"Microsoft YaHei", "PingFang SC"', microsoftyaheiui: '"Microsoft YaHei UI", "PingFang SC"',
          simsun: 'SimSun, "Songti SC"', simhei: 'SimHei, "PingFang SC"', microsoftjhenghei: '"Microsoft JhengHei", "PingFang TC"',
          msgothic: '"MS Gothic", "Hiragino Sans"', meiryo: 'Meiryo, "Hiragino Sans"', yugothic: '"Yu Gothic", "Hiragino Sans"',
          malgungothic: '"Malgun Gothic", "Apple SD Gothic Neo"'
        };
        var fontsMissed = {};

        // The font a text names, for the browser: one of the scene's own files, or one of the
        // system's by the name Wallpaper Engine has for it. A file the scene names without
        // bringing it is one of Wallpaper Engine's own; it is looked for among the Mac's fonts by
        // its name, and the system's font stands in for it if it is not there.
        function fontOf(name) {
          var id = key(String(name || ''));
          var file = fontFiles[id];
          if (file) {
            if (!fontsMade[id]) {
              fontsMade[id] = 'wallaero-font-' + (Object.keys(fontsMade).length + 1);
              try {
                var face = new FontFace(fontsMade[id], 'url("' + encodeURI(file) + '")');
                document.fonts.add(face);
                face.load().then(function () {
                  fontsThere++;
                  changed();
                }, function () { note('the font ' + name + ' cannot be loaded'); });
              } catch (error) {
                note('the font ' + name + ' cannot be loaded');
              }
            }
            return '"' + fontsMade[id] + '", -apple-system, sans-serif';
          }
          if (/\.(ttf|otf|ttc|woff2?)$/.test(id)) {
            if (!fontsMissed[id]) {
              fontsMissed[id] = true;
              note('the font ' + name + ' is not in the scene; if the Mac does not have it, the system\'s stands in for it');
            }
            // "fonts/Monofur-PK7og.ttf" is Monofur.
            var family = String(name).replace(/^.*[\\/]/, '').replace(/\.\w+$/, '').replace(/[-_].*$/, '').replace(/["\\]/g, '');
            return '"' + family + '", -apple-system, sans-serif';
          }
          var plainName = id.replace(/^systemfont_/, '').replace(/[^a-z0-9 ]/g, '');
          return (KNOWN_FONTS[plainName.replace(/ /g, '')] || '"' + plainName + '"') + ', -apple-system, sans-serif';
        }

        function buildText(object, thing) {
          thing.kept = null;
          thing.blending = 'translucent';
          thing.brightness = 1;
          thing.blendMode = number(object.colorBlendMode, 0);
          thing.ownColor = true; // the color is in the picture already
          also(thing, 'text', live(object.text, 0, '', thing, 'text'));
          also(thing, 'pointsize', live(object.pointsize, 1, 32, thing));
          // What a script has told the text to look like, in place of what the scene says.
          thing.own = {};
          function said(name) {
            return thing.own[name] !== undefined ? thing.own[name] : object[name];
          }
          var paper = document.createElement('canvas');
          var pen = paper.getContext('2d');
          var entry = { texture: newTexture(true, true), width: 1, height: 1 };
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
          thing.picture = { layers: [entry], width: 1, height: 1, channels: 'rgba', frames: null, ready: true };
          // The box the scene gives the text: as wide as the text was when the scene was saved and
          // as high as its lines, in the font it names — with the room it leaves for effects on
          // every side, if it has effects. It says how wide the letters of that font are.
          var given = numbers(object.size, 2, 0);
          var roomy = Array.isArray(object.effects) && object.effects.length > 0;
          thing.size = given[0] > 0 ? given : [1, 1];
          var saved = object.text && typeof object.text === 'object' && !Array.isArray(object.text) ? object.text.value : object.text;
          saved = typeof saved === 'string' ? saved : '';
          var shown = null;

          function hex(parts) {
            return 'rgb(' + parts.slice(0, 3).map(function (part) { return Math.round(Math.max(0, Math.min(1, part)) * 255); }).join(',') + ')';
          }

          // Draws the text into its picture, if it says or looks other than what is there.
          thing.settle = function () {
            var state = thing.state;
            var padding = number(said('padding'), 0);
            var across = key(plain(said('horizontalalign')) || 'center'), down = key(plain(said('verticalalign')) || 'center');
            var background = flag(said('opaquebackground'), false) ? numbers(said('backgroundcolor'), 3, 0) : null;
            var family = fontOf(plain(said('font')));
            var widest = flag(said('limitwidth'), false) ? number(said('maxwidth'), 0) : 0;
            var rows = flag(said('limitrows'), false) ? Math.max(1, number(said('maxrows'), 1)) : 0;
            var asked = [state.text, state.pointsize[0], state.color.join(), scale, padding, across, down, String(background), family, fontsThere, widest, rows].join('\u0001');
            if (asked === shown) return;
            shown = asked;
            // Wallpaper Engine counts a point of a font at 300 to the inch, with a unit of the
            // scene for a pixel: the square its letters are drawn in is 300/72 units to the point.
            var letter = Math.max(1, state.pointsize[0] * 25 / 6);
            var font = letter + 'px ' + family;
            pen.font = font;
            var whole = pen.measureText('M');
            var rise = whole.fontBoundingBoxAscent, fall = whole.fontBoundingBoxDescent;
            if (!(rise > 0) || !(fall >= 0)) {
              rise = letter * 0.93;
              fall = letter * 0.24;
            }
            var line = rise + fall; // from one line to the next
            // Where another font stands in for the one the text names, its letters are narrower
            // or wider. The box the scene gives says how wide the text was in the right font, so
            // the letters are drawn that much narrower or wider, and the text takes its old room.
            var squeeze = 1;
            if (given[0] > 0 && saved !== '' && saved.indexOf('\n') < 0 && !(widest > 0)) {
              var measured = pen.measureText(saved).width;
              var savedWidth = given[0] - (roomy ? padding * 2 : 0);
              if (measured > 0 && savedWidth > 0) squeeze = Math.max(0.5, Math.min(1.5, savedWidth / measured));
              if (Math.abs(squeeze - 1) < 0.03) squeeze = 1;
            }
            var lines = String(state.text).split('\n');
            if (widest > 0) {
              // Lines longer than the scene allows are broken between words.
              var broken = [];
              lines.forEach(function (each) {
                var current = '';
                each.split(' ').forEach(function (word) {
                  var longer = current ? current + ' ' + word : word;
                  if (current && pen.measureText(longer).width > widest) {
                    broken.push(current);
                    current = word;
                  } else {
                    current = longer;
                  }
                });
                broken.push(current);
              });
              lines = broken;
            }
            if (rows > 0) lines = lines.slice(0, rows);
            var widths = lines.map(function (each) { return pen.measureText(each).width * squeeze; });
            // The text itself, and around it the room the scene leaves for what effects add.
            var content = [Math.max.apply(null, widths.concat([1])), Math.max(1, lines.length) * line];
            var width = content[0] + padding * 2, height = content[1] + padding * 2;
            paper.width = Math.max(1, Math.min(8192, Math.ceil(width * scale)));
            paper.height = Math.max(1, Math.min(8192, Math.ceil(height * scale)));
            pen.setTransform(paper.width / width, 0, 0, paper.height / height, 0, 0);
            pen.clearRect(0, 0, width, height);
            if (background) {
              pen.fillStyle = hex(background);
              pen.fillRect(0, 0, width, height);
            }
            pen.font = font;
            pen.fillStyle = hex(state.color);
            pen.textBaseline = 'alphabetic';
            lines.forEach(function (each, index) {
              var x = across === 'left' ? padding : (across === 'right' ? width - padding - widths[index] : (width - widths[index]) / 2);
              pen.save();
              pen.translate(x, padding + rise + index * line);
              pen.scale(squeeze, 1);
              pen.fillText(each, 0, 0);
              pen.restore();
            });
            gl.bindTexture(gl.TEXTURE_2D, entry.texture);
            gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
            gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, paper);
            entry.width = paper.width;
            entry.height = paper.height;
            // The side the text is aligned to is at its place, and the text grows away from it;
            // aligned to the middle, it has its middle there. Up and down the text counts from
            // the top of its first line to the line its last letters stand on: what hangs below
            // that line is not counted.
            thing.shift = [across === 'left' ? content[0] / 2 : (across === 'right' ? -content[0] / 2 : 0),
                           down === 'top' ? -content[1] / 2 : (down === 'bottom' ? content[1] / 2 - fall : -fall / 2)];
            thing.size = [width, height];
            stale(thing);
          };
          buildEffects(thing, object);
          thing.draw = function () {
            thing.settle();
            drawImage(thing);
          };
          return thing;
        }

        // How far the scene is moved for an object as the pointer moves: the nearer an object is
        // said to be, the further.
        function shifted(thing) {
          if (!eye || !eye.on) return [0, 0];
          var depth = thing.state.parallax;
          return [-eye.x * depth[0] * eye.amount * sceneWidth, eye.y * depth[1] * eye.amount * sceneHeight];
        }

        function drawImage(layer) {
          var state = layer.state;
          var stands = standing(layer);
          if (!stands.visible) return;
          var nominal = layer.size;
          var width = nominal[0] * scale, height = nominal[1] * scale;
          var matrix = layer.shift ? nudged(stands.matrix, layer.shift[0], layer.shift[1]) : stands.matrix;
          var bright = layer.brightness;
          if (layer.materialAlpha !== undefined) stands = { matrix: stands.matrix, alpha: stands.alpha * layer.materialAlpha, above: stands.above, visible: stands.visible };
          var tint = layer.ownColor ? [1, 1, 1, stands.alpha]
                   : [state.color[0] * bright, state.color[1] * bright, state.color[2] * bright, stands.alpha];
          var how = layer.blendMode > 0 && layer.blendMode !== 9 ? layer.blendMode :
                    (layer.blendMode === 9 || layer.blending === 'additive' ? 'additive' : (layer.blending === 'normal' ? 'normal' : 'translucent'));
          var onto = surface;
          var place = placeOf(matrix, nominal);
          var onScreen = place;
          // A picture that bends is drawn as its triangles, whose corners are counted in the
          // picture's own pixels from its middle.
          var mesh = layer.puppet || null;
          if (mesh) {
            mesh.pose(time, matrix);
            place = placeOf(matrix, [1, 1]);
          }
          var effects = layer.effects.filter(function (effect) { return effect.shown.now; });

          // The picture as it comes: a frame of it, if it is animated.
          var source = null;
          if (layer.picture) {
            var shown = frameAt(layer.picture, sheetTime(layer));
            var first = shown ? shown.layer : layer.picture.layers[0];
            source = { texture: first.texture, frame: shown ? shown.frame : null, channels: layer.picture.channels,
                       resolution: layer.plain ? [nominal[0], nominal[1], nominal[0], nominal[1]] : [first.width, first.height, first.width, first.height] };
          }
          if (!effects.length && source) {
            put(source, place, tint, how, mesh);
            return;
          }
          // One that does not move is drawn once and kept.
          if (layer.kept) {
            put({ texture: layer.kept.texture }, place, tint, how, mesh);
            return;
          }

          var spare = [acquire(width, height), acquire(width, height)];
          spare.forEach(function (target) {
            target.nominalWidth = nominal[0];
            target.nominalHeight = nominal[1];
          });
          var held = null;
          var resolution = [nominal[0], nominal[1], nominal[0], nominal[1]];
          function next() {
            return spare[0] === held ? spare[1] : spare[0];
          }
          if (layer.takesScene) {
            // What of the scene lies under the layer, wherever the layer is and however turned.
            held = next();
            gl.bindFramebuffer(gl.FRAMEBUFFER, held.framebuffer);
            gl.viewport(0, 0, held.width, held.height);
            gl.disable(gl.BLEND);
            if (grabProgram) {
              gl.useProgram(grabProgram.program);
              gl.activeTexture(gl.TEXTURE0);
              gl.bindTexture(gl.TEXTURE_2D, onto.target.texture);
              gl.uniform1i(grabProgram.uniforms.u_Texture.location, 0);
              gl.uniformMatrix3fv(grabProgram.uniforms.u_Place.location, false, place);
              gl.bindVertexArray(passShape);
              gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
            }
            source = { texture: held.texture, resolution: resolution };
          } else if (layer.holds) {
            // The layers that hang on this one are drawn into it, with its middle as theirs and
            // cut at its edges; its effects are then put over all of them at once.
            var inside = next();
            surface = { target: inside, copy: null, width: nominal[0], height: nominal[1], left: -nominal[0] / 2, bottom: -nominal[1] / 2 };
            gl.bindFramebuffer(gl.FRAMEBUFFER, inside.framebuffer);
            gl.viewport(0, 0, inside.width, inside.height);
            gl.disable(gl.BLEND);
            gl.clearColor(0, 0, 0, 0);
            gl.clear(gl.COLOR_BUFFER_BIT);
            layer.held.forEach(function (child) {
              gl.bindFramebuffer(gl.FRAMEBUFFER, inside.framebuffer);
              gl.viewport(0, 0, inside.width, inside.height);
              child.draw();
            });
            if (surface.copy) release(surface.copy);
            surface = onto;
            held = spare[0] === inside ? spare[1] : spare[0];
            gl.bindFramebuffer(gl.FRAMEBUFFER, held.framebuffer);
            gl.viewport(0, 0, held.width, held.height);
            gl.disable(gl.BLEND);
            if (straightProgram) {
              gl.useProgram(straightProgram.program);
              gl.activeTexture(gl.TEXTURE0);
              gl.bindTexture(gl.TEXTURE_2D, inside.texture);
              gl.uniform1i(straightProgram.uniforms.u_Texture.location, 0);
              gl.bindVertexArray(passShape);
              gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
            }
            source = { texture: held.texture, resolution: resolution };
          } else if (source.frame || source.channels !== 'rgba') {
            // Made plain first — the one frame, in full color — as the effects expect it.
            held = next();
            gl.bindFramebuffer(gl.FRAMEBUFFER, held.framebuffer);
            gl.viewport(0, 0, held.width, held.height);
            put(source, FILL, [1, 1, 1, 1], 'normal');
            source = { texture: held.texture, resolution: resolution };
          }

          var previous = source;
          effects.forEach(function (effect) {
            var named = {};
            effect.targets.forEach(function (wanted) {
              var wide = width / wanted.scale, high = height / wanted.scale;
              var nominalWide = nominal[0] / wanted.scale, nominalHigh = nominal[1] / wanted.scale;
              if (wanted.fit > 0) {
                // As large as fits in a square of that side, whatever the layer's size.
                var by = wanted.fit / Math.max(nominal[0], nominal[1], 1);
                wide = nominalWide = Math.max(1, Math.round(nominal[0] * by));
                high = nominalHigh = Math.max(1, Math.round(nominal[1] * by));
              }
              var target;
              if (effect.lasting[wanted.name]) {
                effect.kept = effect.kept || {};
                target = effect.kept[wanted.name];
                if (!target || target.width !== Math.max(1, Math.round(wide)) || target.height !== Math.max(1, Math.round(high))) {
                  if (target) release(target);
                  // It starts with nothing in it.
                  target = effect.kept[wanted.name] = acquire(wide, high);
                  gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
                  gl.viewport(0, 0, target.width, target.height);
                  gl.clearColor(0, 0, 0, 0);
                  gl.clear(gl.COLOR_BUFFER_BIT);
                }
              } else {
                target = acquire(wide, high);
              }
              target.nominalWidth = nominalWide;
              target.nominalHeight = nominalHigh;
              named[wanted.name] = target;
            });
            function input(from) {
              if (from.picture) {
                var first = from.picture.layers[0];
                return { texture: first.texture, resolution: [first.width, first.height, first.width, first.height] };
              }
              if (from.target && named[from.target]) {
                var target = named[from.target];
                return { texture: target.texture, resolution: [target.nominalWidth, target.nominalHeight, target.nominalWidth, target.nominalHeight] };
              }
              if (from.target === '_rt_fullframebuffer') {
                return { texture: onto.target.texture, resolution: [onto.width, onto.height, onto.width, onto.height] };
              }
              // What the picture has become so far, also under the names Wallpaper Engine has for it.
              return previous;
            }
            effect.passes.forEach(function (pass) {
              if (pass.copy) {
                var into = named[pass.target];
                var from = named[pass.source];
                if (!into) return;
                gl.bindFramebuffer(gl.FRAMEBUFFER, into.framebuffer);
                gl.viewport(0, 0, into.width, into.height);
                put(from ? { texture: from.texture } : previous, FILL, [1, 1, 1, 1], 'normal');
                return;
              }
              var target = pass.target ? named[pass.target] : next();
              if (!target) return;
              drawPass(pass, target, pass.inputs.map(input), layer, onScreen);
              if (!pass.target) {
                held = target;
                previous = { texture: target.texture, resolution: resolution };
              }
            });
            Object.keys(named).forEach(function (name) {
              if (!effect.lasting[name]) release(named[name]);
            });
          });

          gl.bindFramebuffer(gl.FRAMEBUFFER, onto.target.framebuffer);
          gl.viewport(0, 0, onto.target.width, onto.target.height);
          put({ texture: previous.texture }, place, tint, how, mesh);
          // What holds other layers is another picture whenever one of them is.
          if (!layer.moving && !layer.holds && held && loading === 0) {
            layer.kept = held;
            release(spare[0] === held ? spare[1] : spare[0]);
          } else {
            spare.forEach(release);
          }
        }

        // --- Particles --------------------------------------------------------
        //
        // A system of particles is said in three lists: emitters, which make particles; initializers,
        // which give each new one its size, color, speed and time to live; and operators, which
        // change it as it lives. They are played here on the processor, and all the particles of a
        // system are drawn at once.

        var particleProgram = link([
          '#version 300 es',
          'in vec2 a_TexCoord;',
          'in vec4 a_Place;',  // where its middle is on the scene, its size and how far it is turned
          'in vec4 a_Color;',
          'in vec4 a_Frame;',  // where in the texture its picture is
          'in vec4 a_More;',   // how many times longer than wide it is drawn
          'uniform mat2 u_Linear;',
          'uniform vec2 u_Scene;',
          'out vec2 v_Uv;',
          'out vec4 v_Color;',
          'void main() {',
          '  vec2 corner = vec2(a_TexCoord.x - 0.5, (0.5 - a_TexCoord.y) * a_More.x);',
          '  float c = cos(a_Place.w);',
          '  float s = sin(a_Place.w);',
          '  vec2 at = a_Place.xy + u_Linear * (vec2(corner.x * c - corner.y * s, corner.x * s + corner.y * c) * a_Place.z);',
          '  gl_Position = vec4(2.0 * at.x / u_Scene.x - 1.0, 1.0 - 2.0 * at.y / u_Scene.y, 0.0, 1.0);',
          '  v_Uv = a_Frame.xy + a_TexCoord * a_Frame.zw;',
          '  v_Color = a_Color;',
          '}'
        ].join('\n'), [
          '#version 300 es',
          'precision highp float;',
          'in vec2 v_Uv;',
          'in vec4 v_Color;',
          'uniform sampler2D u_Texture;',
          'uniform int u_Channels;',
          'uniform float u_Bright;',
          'out vec4 color;',
          'void main() {',
          '  vec4 c = texture(u_Texture, v_Uv);',
          '  if (u_Channels == 1) c = vec4(1.0, 1.0, 1.0, c.r);',
          '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
          '  color = vec4(c.rgb * v_Color.rgb * u_Bright, c.a * v_Color.a);',
          '}'
        ].join('\n'), 'the player\'s own shader');
        // Particles that bend what is behind them — drops on glass, bubbles — rather than show a
        // picture: each is a clear lens over a copy of what is under it, which it takes from
        // nearer its middle the nearer its edge, as a drop does. Its picture only says its shape.
        var refractProgram = link([
          '#version 300 es',
          'in vec2 a_TexCoord;',
          'in vec4 a_Place;',
          'in vec4 a_Color;',
          'in vec4 a_Frame;',
          'in vec4 a_More;',
          'uniform mat2 u_Linear;',
          'uniform vec2 u_Scene;',
          'out vec2 v_Uv;',
          'out vec2 v_Local;',
          'out vec4 v_Color;',
          'out float v_Size;',
          'void main() {',
          '  vec2 corner = vec2(a_TexCoord.x - 0.5, (0.5 - a_TexCoord.y) * a_More.x);',
          '  float c = cos(a_Place.w);',
          '  float s = sin(a_Place.w);',
          '  vec2 at = a_Place.xy + u_Linear * (vec2(corner.x * c - corner.y * s, corner.x * s + corner.y * c) * a_Place.z);',
          '  gl_Position = vec4(2.0 * at.x / u_Scene.x - 1.0, 1.0 - 2.0 * at.y / u_Scene.y, 0.0, 1.0);',
          '  v_Uv = a_Frame.xy + a_TexCoord * a_Frame.zw;',
          '  v_Local = vec2(a_TexCoord.x * 2.0 - 1.0, 1.0 - a_TexCoord.y * 2.0);',
          '  v_Color = a_Color;',
          '  v_Size = a_Place.z;',
          '}'
        ].join('\n'), [
          '#version 300 es',
          'precision highp float;',
          'in vec2 v_Uv;',
          'in vec2 v_Local;',
          'in vec4 v_Color;',
          'in float v_Size;',
          'uniform sampler2D u_Texture;',
          'uniform sampler2D u_Behind;',
          'uniform vec2 u_BehindSize;',
          'uniform int u_Channels;',
          'uniform float u_Bright;',
          'uniform float u_Amount;',
          'out vec4 color;',
          'void main() {',
          '  vec4 c = texture(u_Texture, v_Uv);',
          '  if (u_Channels == 1) c = vec4(1.0, 1.0, 1.0, c.r);',
          '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
          '  vec4 base = c * v_Color;',
          // The way a clear drop faces where it bends what is behind it: as a dome does, its
          // slope growing toward its rim, where it ends.
          '  float r = length(v_Local);',
          '  vec2 slope = r < 1.0 ? v_Local * (1.0 - smoothstep(0.85, 1.0, r)) : vec2(0.0);',
          // As Wallpaper Engine bends it: by so much of the screen as the material says, for a
          // particle as far as it shows.
          '  vec2 at = gl_FragCoord.xy / u_BehindSize + slope * u_Amount * v_Color.a;',
          '  vec3 behind = texture(u_Behind, at).rgb;',
          '  color = vec4(base.rgb * behind * u_Bright, base.a);',
          '}'
        ].join('\n'), 'the player\'s own shader');
        var FLOATS = 16; // to a particle, for the shader
        // Particles drawn as a rope: one band through them all, in the order they were made, as
        // wide as each is large. The picture is laid across the band, and along it where the band
        // is the tail of one particle.
        var ropeProgram = link([
          '#version 300 es',
          'in vec4 a_Place;',  // where a point of the band's edge is, and where across the picture
          'in vec4 a_Color;',
          'uniform vec2 u_Scene;',
          'out vec2 v_Uv;',
          'out vec4 v_Color;',
          'void main() {',
          '  gl_Position = vec4(2.0 * a_Place.x / u_Scene.x - 1.0, 1.0 - 2.0 * a_Place.y / u_Scene.y, 0.0, 1.0);',
          '  v_Uv = a_Place.zw;',
          '  v_Color = a_Color;',
          '}'
        ].join('\n'), [
          '#version 300 es',
          'precision highp float;',
          'in vec2 v_Uv;',
          'in vec4 v_Color;',
          'uniform sampler2D u_Texture;',
          'uniform int u_Channels;',
          'uniform float u_Bright;',
          'out vec4 color;',
          'void main() {',
          '  vec4 c = texture(u_Texture, v_Uv);',
          '  if (u_Channels == 1) c = vec4(1.0, 1.0, 1.0, c.r);',
          '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
          '  color = vec4(c.rgb * v_Color.rgb * u_Bright, c.a * v_Color.a);',
          '}'
        ].join('\n'), 'the player\'s own shader');

        function mix(from, to, share) {
          return from + (to - from) * share;
        }

        // A color written "r g b", by Wallpaper Engine from 0 to 255 in some places and from 0 to
        // 1 in others; here from 0 to 1.
        function color(value, fallback) {
          var parts = numbers(value, 3, fallback);
          var large = parts[0] > 1.5 || parts[1] > 1.5 || parts[2] > 1.5;
          return large ? parts.map(function (part) { return part / 255; }) : parts;
        }

        // What gives a new particle one of its properties; null for one not known here.
        function initializer(said, system) {
          var exponent = number(said.exponent, 1);
          function pick(least, most) {
            return mix(least, most, exponent === 1 ? Math.random() : Math.pow(Math.random(), exponent));
          }
          var least, most;
          switch (key(said.name)) {
            case 'lifetimerandom':
              least = number(said.min, 1);
              most = number(said.max, 1);
              return function (particle) { particle.life = Math.max(0.01, pick(least, most)); };
            case 'sizerandom':
              least = number(said.min, 20);
              most = number(said.max, 20);
              return function (particle) { particle.size = pick(least, most); };
            case 'alpharandom':
              least = number(said.min, 1);
              most = number(said.max, 1);
              return function (particle) { particle.alpha = pick(least, most); };
            case 'velocityrandom':
              least = numbers(said.min, 3, 0);
              most = numbers(said.max, 3, 0);
              return function (particle) {
                particle.vx += pick(least[0], most[0]);
                particle.vy += pick(least[1], most[1]);
                particle.vz += pick(least[2], most[2]);
              };
            case 'colorrandom':
              least = color(said.min, 255);
              most = color(said.max, 255);
              return function (particle) {
                // One of the colors between the two, not each part of it on its own.
                var share = pick(0, 1);
                particle.red = mix(least[0], most[0], share);
                particle.green = mix(least[1], most[1], share);
                particle.blue = mix(least[2], most[2], share);
              };
            case 'rotationrandom':
              least = numbers(said.min, 3, 0)[2];
              most = numbers(said.max, 3, 0)[2];
              return function (particle) { particle.angle = pick(least, most); };
            case 'angularvelocityrandom':
              least = numbers(said.min, 3, 0)[2];
              most = numbers(said.max, 3, 0)[2];
              return function (particle) { particle.spin = pick(least, most); };
            case 'turbulentvelocityrandom':
              // A speed in a direction that wanders around `forward`, the more the larger the scale.
              var forward = numbers(said.forward, 3, [0, 1, 0]);
              var heading = Math.atan2(forward[1], forward[0]);
              var spread = number(said.scale, 1) * Math.PI / 2;
              least = number(said.speedmin, 100);
              most = number(said.speedmax, 250);
              return function (particle) {
                var wander = (smoothNoise(system.age * number(said.timescale, 1) * 2, particle.seed * 50, 256, 11) - 0.5) * 2 * spread;
                var speed = mix(least, most, Math.random());
                particle.vx += Math.cos(heading + wander) * speed;
                particle.vy += Math.sin(heading + wander) * speed;
              };
            case 'mapsequencearoundcontrolpoint':
              // One particle after another is sent off a step further round: so many to a turn.
              var toTurn = Math.max(1, Math.round(number(said.count, 1)));
              var offLeast = numbers(said.speedmin, 3, 0), offMost = numbers(said.speedmax, 3, 0);
              return function (particle) {
                var turn = ((particle.id - 1) % toTurn) / toTurn * Math.PI * 2;
                var share = Math.random();
                var x = mix(offLeast[0], offMost[0], share), y = mix(offLeast[1], offMost[1], share);
                particle.vx += x * Math.cos(turn) - y * Math.sin(turn);
                particle.vy += x * Math.sin(turn) + y * Math.cos(turn);
                particle.vz += mix(offLeast[2], offMost[2], share);
              };
            case 'hsvcolorrandom':
              // A color said as where on the wheel it is, how full and how light: each drawn by itself.
              var hues = [number(said.huemin, 0), number(said.huemax, 1)];
              if (hues[0] > 1.5 || hues[1] > 1.5) hues = [hues[0] / 360, hues[1] / 360];
              var fullness = [number(said.saturationmin, 0), number(said.saturationmax, 1)];
              var lightness = [number(said.valuemin, 0), number(said.valuemax, 1)];
              return function (particle) {
                var hue = ((pick(hues[0], hues[1]) % 1) + 1) % 1 * 6;
                var full = Math.max(0, Math.min(1, pick(fullness[0], fullness[1]))), light = Math.max(0, Math.min(1, pick(lightness[0], lightness[1])));
                function part(shift) {
                  var k = (shift + hue) % 6;
                  return light - light * full * Math.max(0, Math.min(k, 4 - k, 1));
                }
                particle.red = part(5);
                particle.green = part(3);
                particle.blue = part(1);
              };
            case 'mapsequencebetweencontrolpoints':
              // One particle after another is put a step further along the way from one of the
              // system's points to another: so many to the way, and then back or from the start.
              var toWay = Math.max(2, Math.round(number(said.count, 2)));
              var wayFrom = number(said.controlpointstart, 0), wayTo = number(said.controlpointend, 1);
              var back = key(said.limitbehavior || 'repeat') === 'mirror';
              return function (particle) {
                var step = (particle.id - 1) % (back ? (toWay - 1) * 2 : toWay);
                if (back && step >= toWay) step = (toWay - 1) * 2 - step;
                var share = step / (toWay - 1);
                var here = system.pointAt(wayFrom), there = system.pointAt(wayTo);
                particle.x = mix(here[0], there[0], share);
                particle.y = mix(here[1], there[1], share);
                particle.z = mix(here[2], there[2], share);
              };
            case 'colorlist':
              // One of the colors of a list, each as likely as another.
              var listed = (Array.isArray(said.colors) ? said.colors : []).map(function (each) { return color(each, 1); });
              if (!listed.length) return null;
              return function (particle) {
                var chosen = listed[Math.floor(Math.random() * listed.length)];
                particle.red = chosen[0];
                particle.green = chosen[1];
                particle.blue = chosen[2];
              };
            case 'positionoffsetrandom':
              // Put somewhere within a distance of where it was made.
              var within = number(said.distance, 0);
              return function (particle) {
                var turn = Math.random() * Math.PI * 2, far = Math.sqrt(Math.random()) * within;
                particle.x += Math.cos(turn) * far;
                particle.y += Math.sin(turn) * far;
              };
            case 'inheritcontrolpointvelocity':
              // Sent off with a share of the speed one of the system's points moves at: particles made
              // where the pointer is fly off the way it was going.
              var moving = number(said.controlpoint, 0);
              least = number(said.min, 1);
              most = number(said.max, 1);
              return function (particle) {
                var speed = system.pointVelocity(moving), share = pick(least, most);
                particle.vx += speed[0] * share;
                particle.vy += speed[1] * share;
                particle.vz += speed[2] * share;
              };
            case 'remapinitialvalue':
              return remapping(said, system);
            case 'inheritinitialvaluefromevent':
              // A child's particle made by one of its parent's starts as that one is.
              var taking = inheriting(said);
              return function (particle) {
                var parent = particle.from && (particle.from.source || particle.from.host);
                if (parent) taking(particle, parent);
              };
            default:
              note('“' + system.name + '”: what sets up a particle by “' + said.name + '” is not played');
              return null;
          }
        }

        // A property of a new particle set by something measured: how far it is from one of the
        // system's points, how far two points are apart, how long the system has run — or chance.
        function remapping(said, system) {
          var input = key(said.input || 'random');
          var from = number(said.inputrangemin, 0), to = number(said.inputrangemax, 1);
          var low = numbers(said.outputrangemin, 3, 0), high = numbers(said.outputrangemax, 3, 1);
          var how = key(said.operation || 'remap');
          var output = key(said.output || '');
          var first = number(said.inputcontrolpoint0, 0), second = number(said.inputcontrolpoint1, 1);
          function measured(particle) {
            var a, b;
            if (input === 'distancetocontrolpoint') {
              a = system.pointAt(first);
              return Math.sqrt(Math.pow(particle.x - a[0], 2) + Math.pow(particle.y - a[1], 2) + Math.pow(particle.z - a[2], 2));
            }
            if (input === 'distancebetweencontrolpoints') {
              a = system.pointAt(first);
              b = system.pointAt(second);
              return Math.sqrt(Math.pow(a[0] - b[0], 2) + Math.pow(a[1] - b[1], 2) + Math.pow(a[2] - b[2], 2));
            }
            if (input === 'particlesystemtime' || input === 'time') return system.age;
            if (input === 'lifetime') return particle.life;
            return mix(from, to, Math.random());
          }
          function put(old, value) {
            return how === 'add' ? old + value : (how === 'multiply' ? old * value : value);
          }
          var setters = {
            color: function (particle, value) {
              particle.red = put(particle.red, value[0]);
              particle.green = put(particle.green, value[1]);
              particle.blue = put(particle.blue, value[2]);
            },
            size: function (particle, value) { particle.size = put(particle.size, value[0]); },
            alpha: function (particle, value) { particle.alpha = put(particle.alpha, value[0]); },
            lifetime: function (particle, value) { particle.life = Math.max(0.01, put(particle.life, value[0])); },
            velocity: function (particle, value) {
              particle.vx = put(particle.vx, value[0]);
              particle.vy = put(particle.vy, value[1]);
              particle.vz = put(particle.vz, value[2]);
            },
            rotation: function (particle, value) { particle.angle = put(particle.angle, value[2]); },
            angularvelocity: function (particle, value) { particle.spin = put(particle.spin, value[2]); }
          };
          setters.opacity = setters.alpha;
          setters.angle = setters.rotation;
          var set = setters[output];
          if (!set) {
            note('“' + system.name + '”: a particle\'s “' + String(said.output) + '” set by “' + said.name + '” is not played');
            return null;
          }
          return function (particle) {
            var share = to === from ? 0 : Math.max(0, Math.min(1, (measured(particle) - from) / (to - from)));
            set(particle, [mix(low[0], high[0], share), mix(low[1], high[1], share), mix(low[2], high[2], share)]);
          };
        }

        // Takes what a particle of a child has from the particle of its parent it goes with: its
        // color unless another property is said.
        function inheriting(said) {
          var what = key(said.input || said.output || 'color');
          return function (particle, parent) {
            if (what === 'size') {
              particle.size = parent.size * (parent.sizeNow || 1);
            } else if (what === 'alpha' || what === 'opacity') {
              particle.alpha = parent.alpha * (parent.alphaNow || 1);
            } else if (what === 'velocity') {
              particle.vx = parent.vx;
              particle.vy = parent.vy;
              particle.vz = parent.vz;
            } else if (what === 'rotation' || what === 'angle') {
              particle.angle = parent.angle;
            } else {
              particle.red = parent.red * (parent.redNow || 1);
              particle.green = parent.green * (parent.greenNow || 1);
              particle.blue = parent.blue * (parent.blueNow || 1);
            }
          };
        }

        // How far a change that runs from `start` to `end` of a particle's life has got.
        function ramp(share, start, end) {
          return end <= start ? (share >= end ? 1 : 0) : Math.max(0, Math.min(1, (share - start) / (end - start)));
        }

        // What changes a particle as it lives; null for one not known here.
        function operator(said, system) {
          var start = number(said.starttime, 0), end = number(said.endtime, 1);
          // The wave of an oscillation at a moment of a particle's life, from −1 to 1. Each
          // particle has its own pace and start, drawn once from its own number.
          function wave(particle, share, salt) {
            var pace = mix(number(said.frequencymin, 0), number(said.frequencymax, 10), hash(particle.id, salt, 1));
            var shift = mix(number(said.phasemin, 0), number(said.phasemax, Math.PI * 2), hash(particle.id, salt, 2));
            return Math.sin(Math.PI * 2 * pace * share + shift);
          }
          switch (key(said.name)) {
            case 'movement':
              var gravity = numbers(said.gravity, 3, 0);
              var drag = number(said.drag, 0);
              return function (particle, seconds) {
                var keep = Math.max(0, 1 - drag * seconds);
                particle.vx = (particle.vx + gravity[0] * seconds) * keep;
                particle.vy = (particle.vy + gravity[1] * seconds) * keep;
                particle.vz = (particle.vz + gravity[2] * seconds) * keep;
                particle.x += particle.vx * seconds;
                particle.y += particle.vy * seconds;
                particle.z += particle.vz * seconds;
              };
            case 'angularmovement':
              var force = numbers(said.force, 3, 0)[2];
              var slowing = number(said.drag, 0);
              return function (particle, seconds) {
                particle.spin = (particle.spin + force * seconds) * Math.max(0, 1 - slowing * seconds);
                particle.angle += particle.spin * seconds;
              };
            case 'alphafade':
              var fadeIn = number(said.fadeintime, 0.5), fadeOut = number(said.fadeouttime, 0.5);
              return function (particle, seconds, share) {
                if (fadeIn > 0 && share < fadeIn) particle.alphaNow *= share / fadeIn;
                if (fadeOut < 1 && share > fadeOut) particle.alphaNow *= (1 - share) / (1 - fadeOut);
              };
            case 'sizechange':
              var sizeFrom = number(said.startvalue, 1), sizeTo = number(said.endvalue, 0);
              return function (particle, seconds, share) { particle.sizeNow *= mix(sizeFrom, sizeTo, ramp(share, start, end)); };
            case 'alphachange':
              var alphaFrom = number(said.startvalue, 1), alphaTo = number(said.endvalue, 0);
              return function (particle, seconds, share) { particle.alphaNow *= mix(alphaFrom, alphaTo, ramp(share, start, end)); };
            case 'colorchange':
              var colorFrom = color(said.startvalue, 1), colorTo = color(said.endvalue, 1);
              return function (particle, seconds, share) {
                var done = ramp(share, start, end);
                particle.redNow *= mix(colorFrom[0], colorTo[0], done);
                particle.greenNow *= mix(colorFrom[1], colorTo[1], done);
                particle.blueNow *= mix(colorFrom[2], colorTo[2], done);
              };
            case 'oscillatealpha':
              var alphaLow = number(said.scalemin, 0), alphaHigh = number(said.scalemax, 1);
              return function (particle, seconds, share) { particle.alphaNow *= mix(alphaLow, alphaHigh, 0.5 + 0.5 * wave(particle, share, 31)); };
            case 'oscillatesize':
              var sizeLow = number(said.scalemin, 0.8), sizeHigh = number(said.scalemax, 1.2);
              return function (particle, seconds, share) { particle.sizeNow *= mix(sizeLow, sizeHigh, 0.5 + 0.5 * wave(particle, share, 37)); };
            case 'oscillateposition':
              var mask = numbers(said.mask, 3, [1, 1, 0]);
              var swingLow = number(said.scalemin, 1), swingHigh = number(said.scalemax, 1);
              return function (particle, seconds, share) {
                var swing = mix(swingLow, swingHigh, hash(particle.id, 43, 3)) * wave(particle, share, 41);
                particle.shiftX += mask[0] * swing;
                particle.shiftY += mask[1] * swing;
              };
            case 'turbulence':
              // A push that changes smoothly from place to place and with time.
              var grain = number(said.scale, 0.01), pace = number(said.timescale, 1);
              var pushLow = number(said.speedmin, 100), pushHigh = number(said.speedmax, 200);
              var along = numbers(said.mask, 3, [1, 1, 0]);
              return function (particle, seconds) {
                var push = mix(pushLow, pushHigh, hash(particle.id, 47, 4)) * seconds;
                var at = system.age * pace;
                particle.vx += along[0] * push * (smoothNoise(particle.x * grain + at, particle.y * grain, 4096, 5) - 0.5) * 2;
                particle.vy += along[1] * push * (smoothNoise(particle.x * grain, particle.y * grain + at, 4096, 6) - 0.5) * 2;
              };
            case 'controlpointattract':
              // Pulled toward one of the system's points, or pushed from it, while nearer to it
              // than the threshold.
              var toward = number(said.controlpoint, 0), pull = number(said.scale, 0), reach = number(said.threshold, 0);
              var beside = numbers(said.origin, 3, 0);
              return function (particle, seconds) {
                var point = system.pointAt(toward);
                var dx = point[0] + beside[0] - particle.x, dy = point[1] + beside[1] - particle.y, dz = point[2] + beside[2] - particle.z;
                var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
                if (far < 0.0001 || (reach > 0 && far > reach)) return;
                var by = pull * seconds / far;
                particle.vx += dx * by;
                particle.vy += dy * by;
                particle.vz += dz * by;
              };
            case 'vortex_v2':
            case 'vortex':
              // Swept round one of the system's points: fastest within the inner distance, less
              // and less up to the outer one.
              var about = number(said.controlpoint, 0), swirlAt = numbers(said.offset, 3, 0);
              var inner = number(said.distanceinner, 0), outer = number(said.distanceouter, 0);
              var swiftest = number(said.speedinner, 0), slowest = number(said.speedouter, 0);
              var handed = numbers(said.axis, 3, [0, 0, 1])[2] < 0 ? -1 : 1;
              return function (particle, seconds) {
                var point = system.pointAt(about);
                var dx = particle.x - point[0] - swirlAt[0], dy = particle.y - point[1] - swirlAt[1];
                var far = Math.sqrt(dx * dx + dy * dy);
                if (far < 0.0001) return;
                var out = outer > inner ? Math.max(0, Math.min(1, (far - inner) / (outer - inner))) : (far > outer ? 1 : 0);
                var by = mix(swiftest, slowest, out) * seconds * handed / far;
                particle.vx -= dy * by;
                particle.vy += dx * by;
              };
            case 'remapvalue':
              // One of a particle's properties follows a wave or a smooth wandering along its life,
              // between two values. Each particle wanders its own way.
              var remapped = key(said.output || '');
              var way = key(said.transformfunction || 'linear');
              var grain = number(said.transforminputscale, 1);
              var lowest = numbers(said.outputrangemin, 3, 0), highest = numbers(said.outputrangemax, 3, 1);
              var inFrom = number(said.inputrangemin, 0), inTo = number(said.inputrangemax, 1);
              var how = key(said.operation || 'remap');
              function wandered(particle, share, axis) {
                var input = ramp(share, inFrom, inTo) * grain;
                if (/noise/.test(way)) return smoothNoise(input + particle.seed * 97 + axis * 31.7, particle.seed * 53 + axis * 17.3, 4096, 61 + axis);
                if (way === 'sine') return 0.5 + 0.5 * Math.sin(input * Math.PI * 2);
                if (way === 'cosine') return 0.5 + 0.5 * Math.cos(input * Math.PI * 2);
                if (way === 'square') return input % 1 < 0.5 ? 0 : 1;
                if (way === 'saw') return ((input % 1) + 1) % 1;
                if (way === 'triangle') return 1 - Math.abs(((input % 1) + 1) % 1 * 2 - 1);
                return Math.max(0, Math.min(1, input));
              }
              function taken(old, value, seconds) {
                return how === 'add' ? old + value * seconds : (how === 'multiply' ? old * value : value);
              }
              if (remapped === 'velocity') {
                return function (particle, seconds, share) {
                  particle.vx = taken(particle.vx, mix(lowest[0], highest[0], wandered(particle, share, 0)), seconds);
                  particle.vy = taken(particle.vy, mix(lowest[1], highest[1], wandered(particle, share, 1)), seconds);
                  particle.vz = taken(particle.vz, mix(lowest[2], highest[2], wandered(particle, share, 2)), seconds);
                };
              }
              if (remapped === 'size') {
                return function (particle, seconds, share) { particle.sizeNow *= mix(lowest[0], highest[0], wandered(particle, share, 0)); };
              }
              if (remapped === 'alpha' || remapped === 'opacity') {
                return function (particle, seconds, share) { particle.alphaNow *= mix(lowest[0], highest[0], wandered(particle, share, 0)); };
              }
              if (remapped === 'color') {
                return function (particle, seconds, share) {
                  particle.redNow *= mix(lowest[0], highest[0], wandered(particle, share, 0));
                  particle.greenNow *= mix(lowest[1], highest[1], wandered(particle, share, 1));
                  particle.blueNow *= mix(lowest[2], highest[2], wandered(particle, share, 2));
                };
              }
              if (remapped === 'rotation' || remapped === 'angle') {
                return function (particle, seconds, share) { particle.angle = taken(particle.angle, mix(lowest[2], highest[2], wandered(particle, share, 2)), seconds); };
              }
              if (remapped === 'angularvelocity') {
                return function (particle, seconds, share) { particle.spin = taken(particle.spin, mix(lowest[2], highest[2], wandered(particle, share, 2)), seconds); };
              }
              note('“' + system.name + '”: a particle\'s “' + String(said.output) + '” changed by “remapvalue” is not played');
              return null;
            case 'capvelocity':
              // No faster than a speed, from a point of its life on.
              var fastest = number(said.maxspeed, 100), capFrom = number(said.blendinstart, 0), capTo = number(said.blendinend, 0);
              return function (particle, seconds, share) {
                var speed = Math.sqrt(particle.vx * particle.vx + particle.vy * particle.vy + particle.vz * particle.vz);
                if (speed <= fastest || speed < 0.000001) return;
                var by = mix(1, fastest / speed, ramp(share, capFrom, capTo));
                particle.vx *= by;
                particle.vy *= by;
                particle.vz *= by;
              };
            case 'reducemovementnearcontrolpoint':
              // Slowed near one of the system's points: the most within the inner distance, less and
              // less up to the outer one.
              var slowAt = number(said.controlpoint, 0), slowInner = number(said.distanceinner, 0), slowOuter = number(said.distanceouter, 100);
              var cutInner = number(said.reductioninner, 1), cutOuter = number(said.reductionouter, 0);
              return function (particle, seconds) {
                var point = system.pointAt(slowAt);
                var far = Math.sqrt(Math.pow(particle.x - point[0], 2) + Math.pow(particle.y - point[1], 2) + Math.pow(particle.z - point[2], 2));
                var out = slowOuter > slowInner ? Math.max(0, Math.min(1, (far - slowInner) / (slowOuter - slowInner))) : (far > slowOuter ? 1 : 0);
                var keep = Math.max(0, 1 - mix(cutInner, cutOuter, out) * seconds);
                particle.vx *= keep;
                particle.vy *= keep;
                particle.vz *= keep;
              };
            case 'maintaindistancetocontrolpoint':
              // Kept at a distance from one of the system's points: drawn back to it from either side.
              var keptFrom = number(said.controlpoint, 0), keptAt = number(said.distance, 100), firm = number(said.variablestrength, 5);
              return function (particle, seconds) {
                var point = system.pointAt(keptFrom);
                var dx = particle.x - point[0], dy = particle.y - point[1], dz = particle.z - point[2];
                var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
                if (far < 0.0001) return;
                var by = (keptAt - far) / far * Math.min(1, firm * seconds);
                particle.x += dx * by;
                particle.y += dy * by;
                particle.z += dz * by;
              };
            case 'maintaindistancebetweencontrolpoints':
              // Kept on the way between two of the system's points, as on a string held between them.
              var endA = number(said.controlpointstart, 0), endB = number(said.controlpointend, 1), hold = number(said.variablestrength, 5);
              return function (particle, seconds) {
                var a = system.pointAt(endA), b = system.pointAt(endB);
                var wx = b[0] - a[0], wy = b[1] - a[1], wz = b[2] - a[2];
                var length = wx * wx + wy * wy + wz * wz;
                var along = length > 0 ? Math.max(0, Math.min(1, ((particle.x - a[0]) * wx + (particle.y - a[1]) * wy + (particle.z - a[2]) * wz) / length)) : 0;
                var by = Math.min(1, hold * seconds);
                particle.x += (a[0] + wx * along - particle.x) * by;
                particle.y += (a[1] + wy * along - particle.y) * by;
                particle.z += (a[2] + wz * along - particle.z) * by;
              };
            case 'boids':
              // A flock: drawn to the middle of those near it and kept apart from the nearest,
              // going the way they go.
              var sight = Math.max(1, number(said.neighborthreshold, 50));
              var cohesion = number(said.cohesionfactor, 1), separation = number(said.separationfactor, 1), alignment = number(said.alignmentfactor, 0);
              return function (particle, seconds) {
                var near = system.neighbors(particle, sight);
                if (!near.length) return;
                var cx = 0, cy = 0, cz = 0, sx = 0, sy = 0, sz = 0, ax = 0, ay = 0, az = 0;
                near.forEach(function (other) {
                  cx += other.x;
                  cy += other.y;
                  cz += other.z;
                  ax += other.vx;
                  ay += other.vy;
                  az += other.vz;
                  var dx = particle.x - other.x, dy = particle.y - other.y, dz = particle.z - other.z;
                  var far = Math.sqrt(dx * dx + dy * dy + dz * dz) || 0.0001;
                  var push = (sight - far) / sight / far;
                  sx += dx * push;
                  sy += dy * push;
                  sz += dz * push;
                });
                var count = near.length;
                particle.vx += ((cx / count - particle.x) * cohesion + sx * separation * sight + (ax / count - particle.vx) * alignment) * seconds;
                particle.vy += ((cy / count - particle.y) * cohesion + sy * separation * sight + (ay / count - particle.vy) * alignment) * seconds;
                particle.vz += ((cz / count - particle.z) * cohesion + sz * separation * sight + (az / count - particle.vz) * alignment) * seconds;
              };
            case 'collisionplane':
            case 'collisionquad':
            case 'collisionsphere':
            case 'collisionbounds':
            case 'collisionmodel':
              return collision(said, system);
            case 'inheritvaluefromevent':
              // A child's particle that goes with one of its parent's keeps taking after it.
              var takingNow = inheriting(said);
              return function (particle) {
                var parent = particle.from && (particle.from.host || particle.from.source);
                if (parent) takingNow(particle, parent);
              };
            default:
              note('“' + system.name + '”: what changes a particle by “' + said.name + '” is not played');
              return null;
          }
        }

        // What a particle meets and what then becomes of it: it bounces off, slides along, stops or
        // dies. A plane (the ground, say), a rectangle of one, a ball, or the edges of the scene.
        function collision(said, system) {
          var kind = key(said.name);
          var behavior = key(said.collisionbehavior || 'bounce');
          var bounce = number(said.bouncefactor, behavior === 'slide' ? 0 : 0.5);
          var origin = numbers(said.origin, 3, 0);
          var normal = numbers(said.plane || said.normal || said.forward, 3, [0, 1, 0]);
          var length = Math.sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]) || 1;
          normal = normal.map(function (part) { return part / length; });
          var distance = number(said.distance, 0);
          var size = numbers(said.size, 2, 100);
          var radius = number(said.radius, 100);
          // Meets a surface with `n` pointing to the side it must stay on, `under` deep beyond it.
          function meet(particle, n, under) {
            particle.x += n[0] * under;
            particle.y += n[1] * under;
            particle.z += n[2] * under;
            if (behavior === 'kill' || behavior === 'die') {
              particle.age = particle.life;
              return;
            }
            var toward = particle.vx * n[0] + particle.vy * n[1] + particle.vz * n[2];
            if (toward >= 0) return;
            var by = behavior === 'stop' ? 1 : (behavior === 'slide' ? 1 : 1 + bounce);
            particle.vx -= n[0] * toward * by;
            particle.vy -= n[1] * toward * by;
            particle.vz -= n[2] * toward * by;
            if (behavior === 'stop') {
              particle.vx = particle.vy = particle.vz = 0;
            }
          }
          if (kind === 'collisionsphere') {
            return function (particle) {
              var dx = particle.x - origin[0], dy = particle.y - origin[1], dz = particle.z - origin[2];
              var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
              if (far >= radius || far < 0.0001) return;
              meet(particle, [dx / far, dy / far, dz / far], radius - far);
            };
          }
          if (kind === 'collisionmodel') {
            // The model the scene names for it, met as the ball around its shape: the n-th such
            // operator of the system meets the n-th model its object depends on.
            var which = system.collisionModels = (system.collisionModels || 0) + 1;
            var needs = ((system.owner && system.owner.said && system.owner.said.dependencies) || []).filter(function (each) {
              return each && key(String(each.type || '')) === 'collisionmodel';
            });
            var need = needs.filter(function (each) { return number(each.index, 0) === which - 1; })[0] || needs[which - 1] || needs[0];
            if (!need) return null;
            return function (particle) {
              var model = byId[String(need.id)];
              if (!model || !model.bounds) return;
              var stands = standing(model, true);
              if (!stands.visible) return;
              var m = stands.matrix, b = model.bounds.middle;
              var middle = system.fromScene(m[0] * b[0] + m[4] * b[1] + m[8] * b[2] + m[12],
                                            m[1] * b[0] + m[5] * b[1] + m[9] * b[2] + m[13],
                                            m[2] * b[0] + m[6] * b[1] + m[10] * b[2] + m[14]);
              if (!middle) return;
              var grown = Math.max(Math.hypot(m[0], m[1], m[2]), Math.hypot(m[4], m[5], m[6]), Math.hypot(m[8], m[9], m[10]));
              var reach = model.bounds.radius * grown * middle[3];
              var dx = particle.x - middle[0], dy = particle.y - middle[1], dz = particle.z - middle[2];
              var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
              if (far >= reach || far < 0.0001) return;
              meet(particle, [dx / far, dy / far, dz / far], reach - far);
            };
          }
          if (kind === 'collisionbounds') {
            return function (particle) {
              var box = system.sceneBox();
              if (!box) return;
              if (particle.x < box[0]) meet(particle, [1, 0, 0], box[0] - particle.x);
              if (particle.x > box[2]) meet(particle, [-1, 0, 0], particle.x - box[2]);
              if (particle.y < box[1]) meet(particle, [0, 1, 0], box[1] - particle.y);
              if (particle.y > box[3]) meet(particle, [0, -1, 0], particle.y - box[3]);
            };
          }
          // A plane through `origin` (a quad) or at `distance` from the system's middle.
          var through = kind === 'collisionquad' ? origin[0] * normal[0] + origin[1] * normal[1] + origin[2] * normal[2] : distance;
          return function (particle) {
            var side = particle.x * normal[0] + particle.y * normal[1] + particle.z * normal[2] - through;
            if (side >= 0) return;
            if (kind === 'collisionquad') {
              // Only within the rectangle, which lies across the plane.
              var rx = particle.x - origin[0], rz = particle.z - origin[2], ry = particle.y - origin[1];
              var across = Math.abs(normal[1]) > 0.5 ? [rx, rz] : [rx, ry];
              if (Math.abs(across[0]) > size[0] / 2 || Math.abs(across[1]) > size[1] / 2) return;
              // A particle that is well past it came round, not through it.
              if (side < -Math.max(4, Math.abs(particle.vx) + Math.abs(particle.vy) + Math.abs(particle.vz)) * 0.1) return;
            }
            meet(particle, normal, -side);
          };
        }

        function buildParticles(object, thing) {
          var fileName = String(plain(object.particle) || '');
          if (!json(fileName)) {
            note('“' + thing.name + '”: its particles, ' + fileName + ', are not in the scene');
            return null;
          }
          var system = particleSystem(fileName, thing, thing, null, 0);
          // A system begins as if it had been running for a while already: as long as the one of
          // its family that asks for the longest.
          var warm = Math.min(60, Math.max(0, system.warm));
          for (var played = 0; played < warm; played += 1 / 20) system.step(1 / 20);
          return system;
        }

        // The object of the scene another one depends on for something — `kind` as the scene
        // names it — the n-th of them, or the first; null for none.
        function dependency(thing, kind, nth) {
          var needs = ((thing.said && thing.said.dependencies) || []).filter(function (each) {
            return each && key(String(each.type || '')) === kind;
          });
          var need = needs.filter(function (each) { return number(each.index, 0) === nth; })[0] || needs[nth] || needs[0];
          return need ? { id: String(need.id) } : null;
        }

        // A point of the scene where a picture shows, picked at random among the places it is not
        // see-through: the picture is read back once, made small, when it has come.
        var OPAQUE_SIDE = 128;
        function opaqueSpot(wanted) {
          var picture = byId[wanted.id];
          if (!picture || !picture.size) return null;
          var source = picture.picture;
          var layer = source && source.ready !== false && source.layers ? source.layers[0] : null;
          if (!layer || !layer.texture) return null;
          if (picture.opaque === undefined || picture.opaqueFrom !== layer.texture) {
            picture.opaqueFrom = layer.texture;
            picture.opaque = opaqueCells(layer.texture, layer.width || source.width, layer.height || source.height, source.channels);
          }
          var cells = picture.opaque;
          if (!cells || !cells.length) return null;
          var cell = cells[Math.floor(Math.random() * cells.length)];
          var u = (cell % OPAQUE_SIDE + Math.random()) / OPAQUE_SIDE, v = (Math.floor(cell / OPAQUE_SIDE) + Math.random()) / OPAQUE_SIDE;
          var x = (u - 0.5) * picture.size[0], y = (0.5 - v) * picture.size[1];
          var m = standing(picture, true).matrix;
          return [m[0] * x + m[4] * y + m[12], m[1] * x + m[5] * y + m[13], m[2] * x + m[6] * y + m[14]];
        }
        function opaqueCells(texture, width, height, channels) {
          if (!(width > 0 && height > 0)) return null;
          var wasRead = gl.getParameter(gl.READ_FRAMEBUFFER_BINDING), wasDrawn = gl.getParameter(gl.DRAW_FRAMEBUFFER_BINDING);
          var read = gl.createFramebuffer(), small = gl.createFramebuffer(), store = gl.createRenderbuffer();
          gl.bindRenderbuffer(gl.RENDERBUFFER, store);
          gl.renderbufferStorage(gl.RENDERBUFFER, gl.RGBA8, OPAQUE_SIDE, OPAQUE_SIDE);
          gl.bindFramebuffer(gl.FRAMEBUFFER, small);
          gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, store);
          gl.bindFramebuffer(gl.READ_FRAMEBUFFER, read);
          gl.framebufferTexture2D(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
          var cells = null;
          if (gl.checkFramebufferStatus(gl.READ_FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE) {
            gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, small);
            gl.blitFramebuffer(0, 0, width, height, 0, 0, OPAQUE_SIDE, OPAQUE_SIDE, gl.COLOR_BUFFER_BIT, gl.LINEAR);
            gl.bindFramebuffer(gl.READ_FRAMEBUFFER, small);
            var pixels = new Uint8Array(OPAQUE_SIDE * OPAQUE_SIDE * 4);
            gl.readPixels(0, 0, OPAQUE_SIDE, OPAQUE_SIDE, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
            // How see-through a texel is: its alpha, or for a texture of one or two channels the
            // last of them.
            var part = channels === 'r8' ? 0 : (channels === 'rg88' ? 1 : 3);
            cells = [];
            for (var i = 0; i < OPAQUE_SIDE * OPAQUE_SIDE; i++) if (pixels[i * 4 + part] > 127) cells.push(i);
          }
          gl.bindFramebuffer(gl.READ_FRAMEBUFFER, wasRead);
          gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, wasDrawn);
          gl.deleteFramebuffer(read);
          gl.deleteFramebuffer(small);
          gl.deleteRenderbuffer(store);
          return cells;
        }

        // A system of particles, made of its file, drawn for `thing`, the object of the scene that
        // has it. That is the system itself, or — for a child of another system, as `entry` of
        // that one's children says — the object of the system it is a child of, which it goes
        // with: where that one is, with what the scene changes of it. A child either makes its
        // particles alongside its parent, or goes with each of the parent's particles: follows
        // it, or makes its particles where one is made or where one dies.
        function particleSystem(fileName, system, thing, entry, depth) {
          var said = json(fileName);
          var name = system.name;
          var material = ((json(said.material) || {}).passes || [])[0] || {};
          var over = thing.said.instanceoverride || {};
          var kind = entry ? key(String(plain(entry.type) || 'static')) : 'static';
          if (['static', 'eventfollow', 'eventspawn', 'eventdeath'].indexOf(kind) < 0) kind = 'static';
          system.kind = kind;
          system.children = [];
          // A child may be given a count of its own; one that goes with its parent's particles has
          // that many for each of them.
          var ownMost = entry && isSet(entry.maxcount) ? number(entry.maxcount, 100) : number(said.maxcount, 100);
          // Where a child stands on its parent's place, and the way back from there.
          var offset = entry ? matrixOf(numbers(entry.origin, 3, 0), numbers(entry.angles, 3, 0).map(function (angle) { return angle * Math.PI / 180; }),
                                        numbers(entry.scale, 3, 1)) : null;
          function placement(whole) {
            var up = standing(thing, whole);
            return offset ? { matrix: times(up.matrix, offset), alpha: up.alpha, above: up.above, visible: up.visible } : up;
          }
          function ownPoint(x, y, z) {
            if (!offset) return [x, y, z];
            var area = offset[0] * offset[5] - offset[4] * offset[1];
            if (Math.abs(area) < 1e-9) return null; // a child made of no size is not seen
            var dx = x - offset[12], dy = y - offset[13];
            return [(dx * offset[5] - dy * offset[4]) / area, (dy * offset[0] - dx * offset[1]) / area, z - offset[14]];
          }
          // Whether particles stay where they were made when what made them moves on, as a trail
          // does; a glow that goes with a particle moves along with it.
          var stays = (number(said.flags, 0) & 1) !== 0;
          system.moving = true;
          system.age = 0;
          system.particles = [];
          system.made = 0;
          // A particle that bends what is behind it, a drop on glass, has for its pictures how it
          // bends it rather than what it looks like. The bending is not drawn here; such a drop
          // shows as a clear bead.
          system.refracts = number(plain((material.combos || {}).REFRACT), 0) === 1 && !!refractProgram;
          system.refractAmount = number(plain((material.constantshadervalues || {}).ui_editor_properties_refract_amount), 0.05);
          system.picture = texture('materials/' + ((material.textures || [])[0] || 'particle/dot'));
          system.additive = key(material.blending || 'translucent') === 'additive';
          system.bright = number((material.constantshadervalues || {}).ui_editor_properties_overbright, 1);
          // Further away is smaller: the particles have depth, and are drawn as seen by an eye.
          system.perspective = (number(said.flags, 0) & 4) !== 0;
          // What the scene changes of the particles where it uses them; a setting of the
          // wallpaper may stand behind each, and the editor may change each.
          system.settle = function () {
            over = thing.said.instanceoverride || {};
            system.each = Math.max(1, Math.min(20000, Math.round(ownMost * number(over.count, 1))));
            system.most = kind === 'static' ? system.each : Math.min(20000, system.each * Math.max(1, system.owner ? system.owner.most : 1));
            system.rate = number(over.rate, 1);
            system.sizeBy = number(over.size, 1);
            system.alphaBy = number(over.alpha, 1);
            system.speedBy = number(over.speed, 1);
            system.lifeBy = number(over.lifetime, 1);
            system.tint = [1, 1, 1];
            // The color the scene gives is the particles' color, whatever the system would have
            // given them and however it would have changed it as they live: a fire that burns
            // from yellow to red, given violet by the scene, is violet throughout.
            system.recolor = over.colorn !== undefined ? color(over.colorn, 1) : (over.color !== undefined ? color(over.color, 255) : null);
          };
          // The color of a particle as it is drawn.
          system.colorOf = function (particle, state) {
            var own = system.recolor || [particle.red * particle.redNow, particle.green * particle.greenNow, particle.blue * particle.blueNow];
            return [own[0] * system.tint[0] * state.color[0], own[1] * system.tint[1] * state.color[1], own[2] * system.tint[2] * state.color[2]];
          };
          system.settle();
          // The points a system's particles are counted from. One may follow the pointer: a
          // system that makes its particles there trails the mouse.
          var points = (Array.isArray(said.controlpoint) ? said.controlpoint : []).map(function (point) {
            var id = number(point.id, 0);
            // The scene may put a point of the system somewhere of its own choosing: a place on
            // the scene, not one counted from the system.
            var put = over['controlpoint' + id];
            return { id: id, follows: (number(point.flags, 0) & 1) !== 0, offset: numbers(point.offset, 3, 0),
                     onScene: put !== undefined && put !== null ? numbers(put, 3, 0) : null };
          });
          var pointerThere = [0, 0]; // the pointer, in the system's own coordinates
          function follows(index) {
            return points.some(function (point) { return point.id === index && point.follows; });
          }
          system.pointAt = function (index) {
            var point = points.filter(function (each) { return each.id === index; })[0];
            if (!point) return [0, 0, 0];
            // A script may have put the point somewhere since.
            var put = (thing.said.instanceoverride || {})['controlpoint' + index];
            if (put !== undefined && put !== null) point.onScene = numbers(put, 3, 0);
            if (point.onScene) {
              var matrix = placement(true).matrix;
              var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
              if (Math.abs(area) < 1e-9) return point.offset;
              var dx = point.onScene[0] - matrix[12], dy = point.onScene[1] - matrix[13];
              return [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area, point.onScene[2]];
            }
            return point.follows ? [pointerThere[0] + point.offset[0], pointerThere[1] + point.offset[1], point.offset[2]] : point.offset;
          };
          // How fast each of the system's points moves, measured from one step to the next.
          var pointsBefore = {}, pointSpeeds = {};
          system.pointVelocity = function (index) {
            return pointSpeeds[index] || [0, 0, 0];
          };
          function measurePoints(seconds) {
            if (!(seconds > 0)) return;
            points.forEach(function (point) {
              var now = system.pointAt(point.id), before = pointsBefore[point.id];
              pointSpeeds[point.id] = before ? [(now[0] - before[0]) / seconds, (now[1] - before[1]) / seconds, (now[2] - before[2]) / seconds] : [0, 0, 0];
              pointsBefore[point.id] = now;
            });
          }
          // The scene's edges in the system's own coordinates: left, bottom, right, top.
          // A point of the scene in the system's own coordinates, and how much larger a length of
          // the scene is there; null where the system has no size.
          system.owner = thing;
          system.fromScene = function (x, y, z) {
            var matrix = placement(true).matrix;
            var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
            if (Math.abs(area) < 1e-9) return null;
            var dx = x - matrix[12], dy = y - matrix[13];
            return [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area, (z - matrix[14]) / Math.sqrt(Math.abs(area)), 1 / Math.sqrt(Math.abs(area))];
          };
          system.sceneBox = function () {
            var matrix = placement(true).matrix;
            var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
            if (Math.abs(area) < 1e-9) return null;
            var xs = [], ys = [];
            [[0, 0], [sceneWidth, 0], [0, sceneHeight], [sceneWidth, sceneHeight]].forEach(function (corner) {
              var dx = corner[0] - matrix[12], dy = corner[1] - matrix[13];
              xs.push((dx * matrix[5] - dy * matrix[4]) / area);
              ys.push((dy * matrix[0] - dx * matrix[1]) / area);
            });
            return [Math.min.apply(null, xs), Math.min.apply(null, ys), Math.max.apply(null, xs), Math.max.apply(null, ys)];
          };
          // The particles near one, found through a grid of cells as large as the distance looked
          // across, made once a step.
          var grid = null, gridSize = 0, gridAge = -1;
          system.neighbors = function (particle, reach) {
            if (gridAge !== system.age || gridSize !== reach) {
              grid = {};
              gridSize = reach;
              gridAge = system.age;
              system.particles.forEach(function (each) {
                var cell = Math.floor(each.x / reach) + ',' + Math.floor(each.y / reach);
                (grid[cell] || (grid[cell] = [])).push(each);
              });
            }
            var near = [], cx = Math.floor(particle.x / reach), cy = Math.floor(particle.y / reach);
            for (var gx = cx - 1; gx <= cx + 1; gx++) {
              for (var gy = cy - 1; gy <= cy + 1; gy++) {
                (grid[gx + ',' + gy] || []).forEach(function (other) {
                  if (other === particle || near.length >= 32) return;
                  var dx = other.x - particle.x, dy = other.y - particle.y, dz = other.z - particle.z;
                  if (dx * dx + dy * dy + dz * dz < reach * reach) near.push(other);
                });
              }
            }
            return near;
          };
          function findPointer() {
            var matrix = placement(true).matrix;
            var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
            if (Math.abs(area) < 1e-9) return;
            var dx = pointer[0] * sceneWidth - matrix[12], dy = (1 - pointer[1]) * sceneHeight - matrix[13];
            pointerThere = [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area];
          }
          var layerEmitters = 0;
          system.emitters = (said.emitter || []).map(function (emitter) {
            var fromLayer = key(emitter.name) === 'layerimage';
            return {
              // The picture of the scene it is made over, as the object names it; the n-th such
              // emitter has the n-th one.
              picture: fromLayer ? dependency(thing, 'emitterimage', layerEmitters++) : null,
              point: number(emitter.controlpoint, 0), withPointer: follows(number(emitter.controlpoint, 0)),
              box: key(emitter.name) === 'boxrandom',
              // Made all over a layer's picture: here, over the scene where the system lies.
              layer: key(emitter.name) === 'layerimage',
              origin: numbers(emitter.origin, 3, 0), directions: numbers(emitter.directions, 3, 1),
              least: numbers(emitter.distancemin, 3, 0), most: numbers(emitter.distancemax, 3, 256),
              sign: numbers(emitter.sign, 3, 0),
              rate: number(emitter.rate, 5), burst: number(emitter.instantaneous, 0),
              speedLeast: number(emitter.speedmin, 0), speedMost: number(emitter.speedmax, 0),
              lasts: number(emitter.duration, 0), waits: number(emitter.delay, 0), owed: 0
            };
          });
          system.initializers = (said.initializer || []).map(function (each) { return initializer(each, system); }).filter(Boolean);
          system.operators = (said.operator || []).map(function (each) { return operator(each, system); }).filter(Boolean);
          (said.renderer || []).forEach(function (renderer) {
            var kind = key(renderer.name);
            if (kind === 'rope') {
              system.rope = true;
            } else if (kind === 'spritetrail') {
              // Stretched along its way: so many times its width to a unit of speed, within bounds.
              system.trail = { by: number(renderer.length, 0.05), least: Math.max(0, number(renderer.minlength, 0)),
                               most: Math.max(0, number(renderer.maxlength, 10)) };
            } else if (kind === 'ropetrail') {
              // A tail behind each particle, through where it has been in the last seconds.
              system.tails = Math.max(0.02, number(renderer.length, 1));
            } else if (kind !== 'sprite') {
              note('“' + name + '”: particles drawn as “' + renderer.name + '” are drawn as plain sprites');
            }
          });
          system.data = new Float32Array(system.most * FLOATS);
          system.buffer = gl.createBuffer();
          system.shape = gl.createVertexArray();
          gl.bindVertexArray(system.shape);
          gl.bindBuffer(gl.ARRAY_BUFFER, passBuffer);
          gl.enableVertexAttribArray(1);
          gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 20, 12);
          gl.bindBuffer(gl.ARRAY_BUFFER, system.buffer);
          gl.bufferData(gl.ARRAY_BUFFER, system.data.byteLength, gl.DYNAMIC_DRAW);
          [2, 3, 4, 7].forEach(function (place, attribute) {
            gl.enableVertexAttribArray(place);
            gl.vertexAttribPointer(place, 4, gl.FLOAT, false, FLOATS * 4, attribute * 16);
            gl.vertexAttribDivisor(place, 1);
          });
          gl.bindVertexArray(null);

          // Where the system makes its particles: for most, the one place of the system itself; for
          // a child that goes with its parent's particles, the place of each of them — those it
          // follows, or where one was made or died. `alive`: how many of its particles live.
          system.instances = kind === 'static' ? [{ at: [0, 0, 0], age: 0, owed: [], burst: [], alive: 0 }] : [];

          // Something happened to a particle of the parent: it was made, or it died.
          system.event = function (particle) {
            var at = ownPoint(particle.x + (particle.shiftX || 0), particle.y + (particle.shiftY || 0), particle.z);
            if (at) system.instances.push({ at: at, age: 0, owed: [], burst: [], alive: 0, source: particle });
          };

          // A child that follows the parent's particles makes its particles where each of them is.
          function followParent() {
            var known = {};
            system.instances.forEach(function (instance) { known[instance.host.id] = instance; });
            system.instances = system.owner.particles.map(function (particle) {
              var instance = known[particle.id] || { host: particle, age: 0, owed: [], burst: [], alive: 0 };
              instance.at = ownPoint(particle.x + (particle.shiftX || 0), particle.y + (particle.shiftY || 0), particle.z);
              return instance;
            }).filter(function (instance) { return instance.at; });
          }

          function room(instance) {
            return system.particles.length < system.most && (kind === 'static' || instance.alive < system.each);
          }

          function tell(what, particle) {
            system.children.forEach(function (child) {
              if (child.kind === what) child.event(particle);
            });
          }

          function make(emitter, instance) {
            var particle = { id: ++system.made, seed: Math.random(), age: 0, life: 1, size: 20, alpha: 1, red: 1, green: 1, blue: 1,
                             angle: 0, spin: 0, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, from: instance, base: instance.at.slice() };
            var away = [0, 0, 0];
            var axis;
            var spot = emitter.picture ? opaqueSpot(emitter.picture) : null;
            var spread = emitter.layer && !spot && !emitter.picture ? system.sceneBox() : null;
            if (emitter.picture && !spot) {
              // Its picture shows nothing yet, or nowhere: nothing is made.
              return null;
            }
            if (spot) {
              var there = system.fromScene(spot[0], spot[1], spot[2]);
              if (!there) return null;
              var from0 = system.pointAt(emitter.point);
              away = [there[0] - emitter.origin[0] - from0[0] - instance.at[0], there[1] - emitter.origin[1] - from0[1] - instance.at[1],
                      there[2] - emitter.origin[2] - from0[2] - instance.at[2]];
            } else if (spread) {
              away = [mix(spread[0], spread[2], Math.random()), mix(spread[1], spread[3], Math.random()), 0];
            } else if (emitter.box) {
              for (axis = 0; axis < 3; axis++) {
                var side = emitter.sign[axis] > 0 ? 1 : (emitter.sign[axis] < 0 ? -1 : (Math.random() < 0.5 ? -1 : 1));
                away[axis] = side * mix(emitter.least[axis], emitter.most[axis], Math.random()) * emitter.directions[axis];
              }
            } else {
              // Any direction, as far as somewhere between the least and the most.
              var turn = Math.random() * Math.PI * 2, rise = Math.random() * 2 - 1, flat = Math.sqrt(1 - rise * rise);
              var toward = [Math.cos(turn) * flat, Math.sin(turn) * flat, rise];
              var far = mix(emitter.least[0], emitter.most[0], Math.random());
              for (axis = 0; axis < 3; axis++) {
                if (emitter.sign[axis] !== 0) toward[axis] = Math.abs(toward[axis]) * (emitter.sign[axis] > 0 ? 1 : -1);
                away[axis] = toward[axis] * far * emitter.directions[axis];
              }
            }
            var from = system.pointAt(emitter.point);
            particle.x = emitter.origin[0] + away[0] + from[0] + instance.at[0];
            particle.y = emitter.origin[1] + away[1] + from[1] + instance.at[1];
            particle.z = emitter.origin[2] + away[2] + from[2] + instance.at[2];
            var speed = mix(emitter.speedLeast, emitter.speedMost, Math.random());
            var length = Math.sqrt(away[0] * away[0] + away[1] * away[1] + away[2] * away[2]);
            if (speed !== 0 && length > 0) {
              particle.vx = away[0] / length * speed;
              particle.vy = away[1] / length * speed;
              particle.vz = away[2] / length * speed;
            }
            system.initializers.forEach(function (set) { set(particle); });
            particle.vx *= system.speedBy;
            particle.vy *= system.speedBy;
            particle.vz *= system.speedBy;
            particle.life *= system.lifeBy;
            system.particles.push(particle);
            instance.alive++;
            tell('eventspawn', particle);
          }

          system.emitNow = function (count) {
            var instance = system.instances[0];
            if (!instance) return;
            for (var made = 0; made < count && room(instance); made++) {
              system.emitters.forEach(function (emitter) { if (room(instance)) make(emitter, instance); });
            }
            dirty = true;
          };
          system.step = function (seconds) {
            system.age += seconds;
            if (points.length) measurePoints(seconds);
            if (points.some(function (point) { return point.follows; })) findPointer();
            if (kind === 'eventfollow' && system.owner) followParent();
            system.instances.forEach(function (instance) {
              instance.age += seconds;
              system.emitters.forEach(function (emitter, index) {
                if (instance.age < emitter.waits) return;
                // Particles made where the pointer is are not made while it is away.
                if (emitter.withPointer && !pointerSeen) return;
                // A script may have stopped the system making particles.
                if (system.emitting === false) return;
                if (emitter.burst > 0 && !instance.burst[index]) {
                  instance.burst[index] = true;
                  for (var first = 0; first < emitter.burst && room(instance); first++) make(emitter, instance);
                }
                if (emitter.lasts > 0 && instance.age > emitter.waits + emitter.lasts) return;
                instance.owed[index] = (instance.owed[index] || 0) + emitter.rate * system.rate * seconds;
                while (instance.owed[index] >= 1) {
                  instance.owed[index] -= 1;
                  if (room(instance)) make(emitter, instance);
                }
              });
            });
            // What a particle made or dying started is over once its child has made what it makes:
            // a burst, or particles for as long as the child says — for a second where it does not.
            if (kind === 'eventspawn' || kind === 'eventdeath') {
              system.instances = system.instances.filter(function (instance) {
                return system.emitters.some(function (emitter) {
                  return instance.age < emitter.waits || (emitter.rate > 0 && instance.age < emitter.waits + (emitter.lasts > 0 ? emitter.lasts : 1));
                });
              });
            }
            var alive = [];
            system.instances.forEach(function (instance) { instance.alive = 0; });
            system.particles.forEach(function (particle) {
              particle.age += seconds;
              if (particle.age >= particle.life) {
                tell('eventdeath', particle);
                return;
              }
              // A particle of a child that follows another goes along with it, unless it stays
              // where it was made.
              if (!stays && kind === 'eventfollow' && particle.from.at) {
                var at = particle.from.at;
                particle.x += at[0] - particle.base[0];
                particle.y += at[1] - particle.base[1];
                particle.z += at[2] - particle.base[2];
                particle.base = at.slice();
              }
              particle.from.alive++;
              particle.alphaNow = particle.sizeNow = particle.redNow = particle.greenNow = particle.blueNow = 1;
              particle.shiftX = particle.shiftY = 0;
              var share = particle.age / particle.life;
              system.operators.forEach(function (change) { change(particle, seconds, share); });
              if (system.tails) {
                // Where it has been, a few times a tail's length, the oldest first.
                var path = particle.path || (particle.path = []);
                if (!path.length || system.age - path[path.length - 1][2] >= system.tails / 16) {
                  path.push([particle.x + particle.shiftX, particle.y + particle.shiftY, system.age]);
                }
                while (path.length && system.age - path[0][2] > system.tails) path.shift();
              }
              alive.push(particle);
            });
            system.particles = alive;
          };

          // How far the eye is from the scene, for particles with depth.
          var away = (sceneHeight / 2) / Math.tan(number(general.perspectiveoverridefov, number(general.fov, 50)) * Math.PI / 360);

          system.draw = function () {
            if (!particleProgram || !system.particles.length) return;
            var stands = placement();
            if (!stands.visible) return;
            // The editor may have let the system have more particles than there was room for.
            if (system.data.length < system.most * FLOATS) {
              system.data = new Float32Array(system.most * FLOATS);
              gl.bindBuffer(gl.ARRAY_BUFFER, system.buffer);
              gl.bufferData(gl.ARRAY_BUFFER, system.data.byteLength, gl.DYNAMIC_DRAW);
            }
            var state = system.state;
            // Counted from the lower left corner of what the particles are drawn on.
            var matrix = stands.matrix;
            var originX = matrix[12] - surface.left, originY = matrix[13] - surface.bottom;
            var middleX = surface.width / 2, middleY = surface.height / 2;
            // Its own directions there: stretched, then turned.
            var linear = [matrix[0], matrix[1], matrix[4], matrix[5]];
            var deep = Math.sqrt(matrix[8] * matrix[8] + matrix[9] * matrix[9] + matrix[10] * matrix[10]);
            var see = system.alphaBy * stands.alpha;
            var data = system.data;
            var count = Math.min(system.particles.length, system.most);
            var layer = system.picture.layers[0];
            for (var i = 0; i < count; i++) {
              var particle = system.particles[i];
              var localX = particle.x + particle.shiftX, localY = particle.y + particle.shiftY;
              var x = originX + linear[0] * localX + linear[2] * localY;
              var y = originY + linear[1] * localX + linear[3] * localY;
              var near = 1;
              if (system.perspective) {
                near = away / Math.max(away * 0.2, away - particle.z * deep);
                x = middleX + (x - middleX) * near;
                y = middleY + (y - middleY) * near;
              }
              var at = i * FLOATS;
              var turned = particle.angle, long = 1;
              if (system.trail) {
                var speed = Math.sqrt(particle.vx * particle.vx + particle.vy * particle.vy);
                long = Math.max(system.trail.least, Math.min(system.trail.most, speed * system.trail.by));
                if (speed > 0.0001) turned = Math.atan2(particle.vy, particle.vx) - Math.PI / 2;
              }
              data[at] = x;
              data[at + 1] = y;
              data[at + 2] = particle.size * particle.sizeNow * system.sizeBy * near;
              data[at + 3] = turned;
              var shade = system.colorOf(particle, state);
              data[at + 4] = shade[0];
              data[at + 5] = shade[1];
              data[at + 6] = shade[2];
              data[at + 7] = Math.max(0, Math.min(1, particle.alpha * particle.alphaNow * see));
              data[at + 8] = 0;
              data[at + 9] = 0;
              data[at + 10] = 1;
              data[at + 11] = 1;
              data[at + 12] = long;
            }
            var program = system.refracts ? refractProgram : particleProgram;
            // A uniform the compiler left out has no place; setting it at none does nothing.
            function slot(name) { var uniform = program.uniforms[name]; return uniform ? uniform.location : null; }
            if (system.refracts) {
              // What is under the drops, as it is before they are drawn.
              var onto = surface.target;
              if (!surface.copy) surface.copy = acquire(onto.width, onto.height);
              gl.bindFramebuffer(gl.READ_FRAMEBUFFER, onto.framebuffer);
              gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, surface.copy.framebuffer);
              gl.blitFramebuffer(0, 0, onto.width, onto.height, 0, 0, onto.width, onto.height, gl.COLOR_BUFFER_BIT, gl.NEAREST);
              gl.bindFramebuffer(gl.FRAMEBUFFER, onto.framebuffer);
            }
            gl.useProgram(program.program);
            gl.enable(gl.BLEND);
            if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
            else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, layer.texture);
            gl.uniform1i(slot('u_Texture'), 0);
            gl.uniform1i(slot('u_Channels'), CHANNELS[system.picture.channels] || 0);
            gl.uniform1f(slot('u_Bright'), system.bright);
            gl.uniformMatrix2fv(slot('u_Linear'), false, new Float32Array(linear));
            gl.uniform2f(slot('u_Scene'), surface.width, surface.height);
            if (system.refracts) {
              gl.activeTexture(gl.TEXTURE1);
              gl.bindTexture(gl.TEXTURE_2D, surface.copy.texture);
              gl.uniform1i(slot('u_Behind'), 1);
              gl.uniform2f(slot('u_BehindSize'), surface.target.width, surface.target.height);
              gl.uniform1f(slot('u_Amount'), system.refractAmount);
              gl.activeTexture(gl.TEXTURE0);
            }
            gl.bindVertexArray(system.shape);
            gl.bindBuffer(gl.ARRAY_BUFFER, system.buffer);
            gl.bufferSubData(gl.ARRAY_BUFFER, 0, data.subarray(0, count * FLOATS));
            gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count);
            gl.bindVertexArray(null);
          };

          if (system.rope && ropeProgram) {
            // Two points to a particle, one at each edge of the band, with its color.
            var band = new Float32Array(system.most * 16);
            var bandBuffer = gl.createBuffer();
            var bandShape = gl.createVertexArray();
            gl.bindVertexArray(bandShape);
            gl.bindBuffer(gl.ARRAY_BUFFER, bandBuffer);
            gl.bufferData(gl.ARRAY_BUFFER, band.byteLength, gl.DYNAMIC_DRAW);
            gl.enableVertexAttribArray(2);
            gl.vertexAttribPointer(2, 4, gl.FLOAT, false, 32, 0);
            gl.enableVertexAttribArray(3);
            gl.vertexAttribPointer(3, 4, gl.FLOAT, false, 32, 16);
            gl.bindVertexArray(null);
            system.draw = function () {
              var count = Math.min(system.particles.length, system.most);
              var stands = placement();
              if (count < 2 || !stands.visible) return;
              if (band.length < system.most * 16) {
                band = new Float32Array(system.most * 16);
                gl.bindBuffer(gl.ARRAY_BUFFER, bandBuffer);
                gl.bufferData(gl.ARRAY_BUFFER, band.byteLength, gl.DYNAMIC_DRAW);
              }
              var state = system.state;
              var matrix = stands.matrix;
              var wide = Math.sqrt(Math.abs(matrix[0] * matrix[5] - matrix[4] * matrix[1])) * system.sizeBy;
              var see = system.alphaBy * stands.alpha;
              var spots = [];
              var i;
              for (i = 0; i < count; i++) {
                var particle = system.particles[i];
                var localX = particle.x + particle.shiftX, localY = particle.y + particle.shiftY;
                spots.push([matrix[12] - surface.left + matrix[0] * localX + matrix[4] * localY,
                            matrix[13] - surface.bottom + matrix[1] * localX + matrix[5] * localY]);
              }
              for (i = 0; i < count; i++) {
                var each = system.particles[i];
                var before = spots[Math.max(0, i - 1)], after = spots[Math.min(count - 1, i + 1)];
                var dx = after[0] - before[0], dy = after[1] - before[1];
                var far = Math.sqrt(dx * dx + dy * dy);
                // Where the band does not go on, it has no width: a rope lying in one spot is not seen.
                var half = far > 0.0001 ? each.size * each.sizeNow * wide / 2 / far : 0;
                for (var side = 0; side < 2; side++) {
                  var at = (i * 2 + side) * 8, turn = side ? 1 : -1;
                  band[at] = spots[i][0] - dy * half * turn;
                  band[at + 1] = spots[i][1] + dx * half * turn;
                  band[at + 2] = side;
                  band[at + 3] = 0.5;
                  var shade = system.colorOf(each, state);
                  band[at + 4] = shade[0];
                  band[at + 5] = shade[1];
                  band[at + 6] = shade[2];
                  band[at + 7] = Math.max(0, Math.min(1, each.alpha * each.alphaNow * see));
                }
              }
              gl.useProgram(ropeProgram.program);
              gl.enable(gl.BLEND);
              if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
              else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
              gl.activeTexture(gl.TEXTURE0);
              gl.bindTexture(gl.TEXTURE_2D, system.picture.layers[0].texture);
              gl.uniform1i(ropeProgram.uniforms.u_Texture.location, 0);
              gl.uniform1i(ropeProgram.uniforms.u_Channels.location, CHANNELS[system.picture.channels] || 0);
              gl.uniform1f(ropeProgram.uniforms.u_Bright.location, system.bright);
              gl.uniform2f(ropeProgram.uniforms.u_Scene.location, surface.width, surface.height);
              gl.bindVertexArray(bandShape);
              gl.bindBuffer(gl.ARRAY_BUFFER, bandBuffer);
              gl.bufferSubData(gl.ARRAY_BUFFER, 0, band.subarray(0, count * 16));
              gl.drawArrays(gl.TRIANGLE_STRIP, 0, count * 2);
              gl.bindVertexArray(null);
            };
          }

          if (system.tails && ropeProgram) {
            // A band to each particle, from where it was to where it is; the picture runs along
            // it, its top at the particle. The bands are drawn as one, joined by corners that
            // have no area.
            var tailBand = new Float32Array(0);
            var tailBuffer = gl.createBuffer();
            var tailShape = gl.createVertexArray();
            gl.bindVertexArray(tailShape);
            gl.bindBuffer(gl.ARRAY_BUFFER, tailBuffer);
            gl.enableVertexAttribArray(2);
            gl.vertexAttribPointer(2, 4, gl.FLOAT, false, 32, 0);
            gl.enableVertexAttribArray(3);
            gl.vertexAttribPointer(3, 4, gl.FLOAT, false, 32, 16);
            gl.bindVertexArray(null);
            system.draw = function () {
              var stands = placement();
              if (!stands.visible || !system.particles.length) return;
              var state = system.state;
              var matrix = stands.matrix;
              var wide = Math.sqrt(Math.abs(matrix[0] * matrix[5] - matrix[4] * matrix[1])) * system.sizeBy;
              var see = system.alphaBy * stands.alpha;
              var corners = [];
              system.particles.forEach(function (particle) {
                var spots = (particle.path || []).map(function (spot) { return [spot[0], spot[1]]; });
                spots.push([particle.x + particle.shiftX, particle.y + particle.shiftY]);
                if (spots.length < 2) return;
                spots = spots.map(function (spot) {
                  return [matrix[12] - surface.left + matrix[0] * spot[0] + matrix[4] * spot[1],
                          matrix[13] - surface.bottom + matrix[1] * spot[0] + matrix[5] * spot[1]];
                });
                var tint = system.colorOf(particle, state).concat([Math.max(0, Math.min(1, particle.alpha * particle.alphaNow * see))]);
                var half = particle.size * particle.sizeNow * wide / 2;
                var first = corners.length;
                spots.forEach(function (spot, index) {
                  var before = spots[Math.max(0, index - 1)], after = spots[Math.min(spots.length - 1, index + 1)];
                  var dx = after[0] - before[0], dy = after[1] - before[1];
                  var far = Math.sqrt(dx * dx + dy * dy);
                  var across = far > 0.0001 ? half / far : 0;
                  for (var side = 0; side < 2; side++) {
                    var turn = side ? 1 : -1;
                    corners.push([spot[0] - dy * across * turn, spot[1] + dx * across * turn, side, 1 - index / (spots.length - 1)].concat(tint));
                  }
                });
                // Joined to the band before it by its own first corner and that band's last, twice each.
                if (first > 0) corners.splice(first, 0, corners[first - 1], corners[first]);
              });
              if (corners.length < 4) return;
              if (tailBand.length < corners.length * 8) tailBand = new Float32Array(corners.length * 8 * 2);
              corners.forEach(function (corner, index) { tailBand.set(corner, index * 8); });
              gl.useProgram(ropeProgram.program);
              gl.enable(gl.BLEND);
              if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
              else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
              gl.activeTexture(gl.TEXTURE0);
              gl.bindTexture(gl.TEXTURE_2D, system.picture.layers[0].texture);
              gl.uniform1i(ropeProgram.uniforms.u_Texture.location, 0);
              gl.uniform1i(ropeProgram.uniforms.u_Channels.location, CHANNELS[system.picture.channels] || 0);
              gl.uniform1f(ropeProgram.uniforms.u_Bright.location, system.bright);
              gl.uniform2f(ropeProgram.uniforms.u_Scene.location, surface.width, surface.height);
              gl.bindVertexArray(tailShape);
              gl.bindBuffer(gl.ARRAY_BUFFER, tailBuffer);
              gl.bufferData(gl.ARRAY_BUFFER, tailBand.subarray(0, corners.length * 8), gl.DYNAMIC_DRAW);
              gl.drawArrays(gl.TRIANGLE_STRIP, 0, corners.length);
              gl.bindVertexArray(null);
            };
          }

          // Its children, made after it, are drawn after it and move on as it does.
          (Array.isArray(said.children) ? said.children : []).forEach(function (child) {
            if (!child || typeof child !== 'object' || depth >= 4) return;
            var childFile = String(plain(child.name) || '');
            if (!json(childFile)) {
              note('“' + name + '”: its particles ' + childFile + ' are not in the scene');
              return;
            }
            var made = particleSystem(childFile, { name: name, owner: system, state: thing.state }, thing, child, depth + 1);
            if (made) system.children.push(made);
          });
          var ownStep = system.step, ownDraw = system.draw, ownSettle = system.settle;
          system.step = function (seconds) {
            ownStep(seconds);
            system.children.forEach(function (child) { child.step(seconds); });
          };
          system.draw = function () {
            ownDraw();
            system.children.forEach(function (child) { child.draw(); });
          };
          system.settle = function () {
            ownSettle();
            system.children.forEach(function (child) { child.settle(); });
          };
          system.warm = system.children.reduce(function (most, child) { return Math.max(most, child.warm); }, number(said.starttime, 0));
          return system;
        }

        // --- Sounds -----------------------------------------------------------

        var players = [];

        // A sound of the scene plays as the page's own sound would: the app decides whether it is
        // heard and how loud, as for any wallpaper, and the scene how loud next to its other sounds.
        function buildSound(object, thing) {
          var list = (Array.isArray(object.sound) ? object.sound : [object.sound]).map(function (name) {
            return soundFiles[key(String(plain(name) || ''))];
          }).filter(Boolean);
          var name = thing.name;
          if (!list.length) {
            note('“' + name + '”: its sound is not in the scene');
            return null;
          }
          also(thing, 'volume', live(object.volume, 1, 1, thing));
          var mode = key(plain(object.playbackmode) || 'loop');
          var least = number(object.mintime, 0), most = number(object.maxtime, 0);
          var audio = document.createElement('audio');
          var index = 0;
          var timer = 0;
          var wanted = !flag(object.startsilent, false); // until a script says otherwise
          var loud = -1;
          audio.style.display = 'none';
          audio.preload = 'auto';
          audio.loop = mode === 'loop' && list.length === 1;

          function start() {
            var started = audio.play();
            if (started && started['catch']) started['catch'](function () {});
          }
          audio.addEventListener('ended', function () {
            if (stopped) return;
            if (mode === 'single') {
              wanted = false;
              return;
            }
            // The next one, or any one after a pause, as the scene says.
            index = mode === 'random' ? Math.floor(Math.random() * list.length) : (index + 1) % list.length;
            timer = setTimeout(function () {
              audio.src = encodeURI(list[index]);
              if (wanted && standing(thing).visible) start();
            }, mode === 'random' ? mix(least, most, Math.random()) * 1000 : 0);
          });
          audio.addEventListener('error', function () { note('“' + name + '”: this web engine cannot play ' + list[index].replace(/^.*\./, '.') + ' sound'); });
          if (mode === 'random') index = Math.floor(Math.random() * list.length);

          // Plays while the scene shows the object, it is not turned all the way down and nothing
          // has stopped it, as loud as the scene says: a share of what the app lets the wallpaper have.
          thing.settle = function () {
            var share = Math.max(0, Math.min(1, thing.state.volume[0]));
            if (share !== loud) {
              loud = share;
              audio.wallaeroShare = share;
              var host = window.__wallaeroHost;
              if (host && host.apply) host.apply({});
              else audio.volume = share;
            }
            // One turned all the way down is not played at all: playing it unheard keeps the
            // Mac's sound awake for nothing.
            var sounds = wanted && share > 0 && standing(thing).visible;
            if (sounds && audio.paused && !audio.ended) start();
            if (!sounds && !audio.paused) audio.pause();
          };
          thing.sound = {
            play: function () {
              wanted = true;
              if (audio.ended) audio.currentTime = 0;
              thing.settle();
            },
            pause: function () {
              wanted = false;
              thing.settle();
            },
            stop: function () {
              wanted = false;
              thing.settle();
              try {
                audio.currentTime = 0;
              } catch (error) {}
            },
            isPlaying: function () { return !audio.paused && !audio.ended; }
          };
          audio.src = encodeURI(list[index]);
          document.body.appendChild(audio);
          players.push({ audio: audio, stop: function () { clearTimeout(timer); audio.pause(); audio.remove(); } });
          thing.draw = thing.settle;
          thing.settle();
          return thing;
        }

        // --- Building ---------------------------------------------------------

        var listening = false;

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
        if (!(sceneWidth > 0 && sceneHeight > 0)) {
          // A scene may leave its size to its first picture.
          var first = all.filter(function (object) { return object.image; })[0];
          var firstSize = first ? numbers(first.size, 2, 0) : [0, 0];
          sceneWidth = firstSize[0] > 0 ? firstSize[0] : 1920;
          sceneHeight = firstSize[1] > 0 ? firstSize[1] : 1080;
        }
        // A scene with scripts may show what it has hidden; in any other, what is hidden for good
        // is left out.
        var scripted = /"script"\s*:/.test(files['scene.json'] || '');

        // --- Changes made in the editor ------------------------------------------------------
        //
        // The app's editor changes a scene without touching its files: its changes come with the
        // scene and are put over what the scene says, before the scene is played and while it
        // plays. The scene as it came is kept, for a change that is taken back.

        var changes = {};
        var pristine = { general: merged(general, {}), objects: {}, order: all };
        all.forEach(function (object) {
          if (object.id !== undefined && object.id !== null) pristine.objects[String(object.id)] = object;
        });
        var generalChanged = {}; // the names of what the editor has changed of the scene as a whole

        function isSet(value) {
          return value !== undefined && value !== null;
        }

        // A value of the scene made another. What stood behind it — an animation, a script — goes
        // on from the new value; a setting of the wallpaper that stood behind it does no longer.
        function replaced(raw, value) {
          if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return value;
          var copy = merged(raw, { value: value });
          delete copy.user;
          return copy;
        }

        // A color as the editor gives it, "#FF8000", as the scene writes one: "1 0.50196 0".
        function colorText(hex) {
          var parts = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i.exec(String(hex || ''));
          if (!parts) return null;
          return [1, 2, 3].map(function (index) { return +(parseInt(parts[index], 16) / 255).toFixed(5); }).join(' ');
        }

        function hexOf(parts) {
          return '#' + parts.slice(0, 3).map(function (part) {
            return ('0' + Math.round(Math.max(0, Math.min(1, part)) * 255).toString(16)).slice(-2);
          }).join('').toUpperCase();
        }

        function changeOf(id) {
          var list = Array.isArray(changes.objects) ? changes.objects : [];
          for (var i = 0; i < list.length; i++) {
            if (list[i] && String(list[i].id) === String(id)) return list[i];
          }
          return null;
        }

        // An object of the scene with the editor's change put over it: a copy, or the object itself
        // when nothing of it is changed.
        function amended(object, change) {
          if (!change) return object;
          var copy = merged(object, {});
          function put(name, value) { copy[name] = replaced(object[name], value); }
          if (isSet(change.isVisible)) put('visible', !!change.isVisible);
          // The app sets `wallaeroStill` when it draws the picture for the lock screen; what the
          // editor keeps out of that picture is hidden there.
          if (window.wallaeroStill && change.showsOnLockScreen === false) put('visible', false);
          if (isSet(change.x) || isSet(change.y)) {
            var hangs = object.parent !== undefined && object.parent !== null;
            var origin = numbers(object.origin, 3, hangs ? 0 : [sceneWidth / 2, sceneHeight / 2, 0]);
            if (isSet(change.x)) origin[0] = Number(change.x);
            if (isSet(change.y)) origin[1] = Number(change.y);
            put('origin', origin.join(' '));
          }
          if (isSet(change.scaleX) || isSet(change.scaleY)) {
            var scale = numbers(object.scale, 3, 1);
            if (isSet(change.scaleX)) scale[0] = Number(change.scaleX);
            if (isSet(change.scaleY)) scale[1] = Number(change.scaleY);
            put('scale', scale.join(' '));
          }
          if (isSet(change.rotation)) {
            // The editor turns clockwise, as on the page; the scene counts the other way.
            var angles = numbers(object.angles, 3, 0);
            angles[2] = -Number(change.rotation) * Math.PI / 180;
            put('angles', angles.join(' '));
          }
          if (isSet(change.opacity)) put('alpha', Number(change.opacity) / 100);
          if (colorText(change.color)) put('color', colorText(change.color));
          if (isSet(change.text)) put('text', String(change.text));
          if (isSet(change.fontSize)) put('pointsize', Number(change.fontSize));
          if (isSet(change.volume)) put('volume', Number(change.volume) / 100);
          var over = null;
          [['particleCount', 'count'], ['particleRate', 'rate'], ['particleSpeed', 'speed'], ['particleSize', 'size'],
           ['particleLifetime', 'lifetime'], ['particleOpacity', 'alpha']].forEach(function (pair) {
            if (!isSet(change[pair[0]])) return;
            over = over || merged(object.instanceoverride, {});
            over[pair[1]] = replaced(over[pair[1]], Number(change[pair[0]]) / 100);
          });
          if (colorText(change.particleColor)) {
            over = over || merged(object.instanceoverride, {});
            over.colorn = replaced(over.colorn, colorText(change.particleColor));
          }
          if (over) copy.instanceoverride = over;
          if (Array.isArray(change.effects) && Array.isArray(object.effects)) {
            copy.effects = object.effects.map(function (use, place) {
              var own = change.effects.filter(function (each) { return each && each.id === place; })[0];
              return own && use ? amendedEffect(use, own) : use;
            });
          }
          return copy;
        }

        // An effect with the editor's change put over it. A value of the effect is changed in
        // each of its passes, as Wallpaper Engine's own editor does.
        function amendedEffect(use, change) {
          var copy = merged(use, {});
          if (isSet(change.isVisible)) copy.visible = replaced(use.visible, !!change.isVisible);
          var names = Object.keys(change.values || {});
          if (!names.length) return copy;
          var effect = json(String(plain(use.file) || '')) || {};
          var count = Math.max((effect.passes || []).length, (use.passes || []).length);
          copy.passes = [];
          for (var step = 0; step < count; step++) {
            var chosen = merged((use.passes || [])[step], {});
            var constants = merged(chosen.constantshadervalues, {});
            names.forEach(function (name) {
              var value = change.values[name];
              if (!Array.isArray(value) || !value.length) return;
              constants[name] = replaced(constants[name], value.length === 1 ? Number(value[0]) : value.map(Number).join(' '));
            });
            chosen.constantshadervalues = constants;
            copy.passes.push(chosen);
          }
          return copy;
        }

        // The scene as a whole: whether it moves with the pointer, whether what is bright glows.
        function amendGeneral() {
          [['parallax', 'cameraparallax'], ['parallaxAmount', 'cameraparallaxamount'], ['bloom', 'bloom'],
           ['bloomStrength', 'bloomstrength']].forEach(function (pair) {
            var value = changes[pair[0]];
            if (isSet(value)) {
              general[pair[1]] = replaced(pristine.general[pair[1]], typeof value === 'boolean' ? value : Number(value));
              generalChanged[pair[1]] = true;
            } else if (generalChanged[pair[1]]) {
              // Taken back: as the scene has it, whatever a script made of it meanwhile.
              if (pair[1] in pristine.general) general[pair[1]] = pristine.general[pair[1]];
              else delete general[pair[1]];
              delete generalChanged[pair[1]];
            }
          });
        }

        // The values of an object that are played as they change.
        var FOLLOWED = ['origin', 'scale', 'angles', 'alpha', 'color', 'visible', 'text', 'pointsize', 'volume'];

        // An object without what is played as it changes — those values, its name, and of its
        // effects whether they show and their values: what stays the same while an object is only
        // moved, recolored or set otherwise.
        function skeleton(object) {
          var copy = merged(object, {});
          FOLLOWED.forEach(function (name) { delete copy[name]; });
          delete copy.name;
          copy.effects = (object.effects || []).map(function (use) {
            return { file: use && use.file, passes: ((use && use.passes) || []).map(function (pass) {
              return { combos: pass && pass.combos, textures: pass && pass.textures };
            }) };
          });
          return copy;
        }

        // A value as text with its keys in order, to tell whether two are the same.
        function canonical(value) {
          if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
          if (value && typeof value === 'object') {
            return '{' + Object.keys(value).sort().map(function (name) { return JSON.stringify(name) + ':' + canonical(value[name]); }).join(',') + '}';
          }
          return JSON.stringify(value === undefined ? null : value);
        }

        // Brings what is played of an object up to the object as the editor has changed it. False
        // when that cannot be done without playing the scene anew: something that was not made
        // ready because it was hidden is to show.
        function follow(thing, object) {
          if (thing.unmade && flag(object.visible, true)) return false;
          thing.said = object;
          FOLLOWED.forEach(function (name) {
            var value = thing.lives[name];
            if (!value || JSON.stringify(value.raw) === JSON.stringify(object[name])) return;
            value.raw = object[name];
            var behind = value.raw && typeof value.raw === 'object' && !Array.isArray(value.raw) ? value.raw : null;
            value.bound = !!(behind && isSet(behind.user));
            // What a script makes of the value, it goes on making.
            if (value.script && value.script.made !== undefined) return;
            var next = value.read();
            if (!same(next, thing.state[name])) {
              thing.state[name] = next;
              dirty = true;
            }
          });
          var uses = object.effects || [];
          var made = {};
          (thing.effects || []).forEach(function (effect) { made[effect.place] = effect; });
          for (var place = 0; place < uses.length; place++) {
            var use = uses[place] || {};
            var effect = made[place];
            if (!effect) {
              if (thing.effectsOff && thing.effectsOff[place] && flag(use.visible, true)) return false;
              continue;
            }
            var touched = false;
            if (JSON.stringify(effect.shown.raw) !== JSON.stringify(use.visible)) {
              effect.shown.raw = use.visible;
              if (!(effect.shown.script && effect.shown.script.made !== undefined)) {
                var before = effect.shown.now;
                if (effect.shown.read() !== before) touched = true;
              }
            }
            effect.passes.forEach(function (pass) {
              if (!pass.own) return;
              var constants = merged(pass.own.constantshadervalues, ((use.passes || [])[pass.step] || {}).constantshadervalues);
              pass.values.forEach(function (value) {
                if (!value.live || value.material === undefined) return;
                var raw = constants[value.material] !== undefined ? constants[value.material] : value.fallback;
                if (JSON.stringify(raw) === JSON.stringify(value.live.raw)) return;
                value.live.raw = raw;
                if (value.live.script && value.live.script.made !== undefined) return;
                var before = value.live.now;
                if (!same(value.live.read(), before)) touched = true;
              });
            });
            if (touched) stale(thing);
          }
          if (thing.settle) thing.settle();
          return true;
        }

        changes = merged(startingChanges, {});
        amendGeneral();
        all = all.map(function (object) {
          return isSet(object.id) ? amended(object, changeOf(object.id)) : object;
        });

        function idle() {}
        var hasChildren = {};
        // Objects others make use of — a picture particles are made over, say — are made even
        // when hidden.
        var usedByOthers = {};
        all.forEach(function (object) {
          if (object.parent !== undefined && object.parent !== null) hasChildren[String(object.parent)] = true;
          (Array.isArray(object.dependencies) ? object.dependencies : []).forEach(function (need) {
            if (need && need.id !== undefined) usedByOthers[String(need.id)] = true;
          });
        });

        // Puts an object on the scene, above what is there.
        function add(object) {
          var hidden = object.visible === false;
          var make = object.image ? buildImage : (object.particle ? buildParticles : (object.sound ? buildSound :
                     (object.text !== undefined && object.text !== null ? buildText :
                     (object.model ? buildModel : (object.light ? buildLight : null)))));
          var thing = placed(object, String(plain(object.image) || plain(object.particle) || plain(object.model) ||
                                            (object.light ? 'light' : (object.sound ? 'sound' : (make ? 'text' : 'group')))));
          thing.draw = idle;
          objects.push(thing);
          // A layer made to put effects over others either takes what the scene shows under it or
          // holds the layers that hang on it, which are then drawn into it. The scene says which;
          // where it does not, the layer holds what hangs on it if anything does.
          if (object.image && /composelayer/.test(key(String(plain(object.image) || '')))) {
            var through = object.config && typeof object.config === 'object' ? plain(object.config.passthrough) : undefined;
            thing.holds = through === false || (through === undefined && hasChildren[String(object.id)] === true);
            thing.held = [];
          }
          // What is hidden for good is only there for what hangs on it to be hidden with it.
          if (hidden && !scripted && !usedByOthers[String(object.id)]) {
            thing.unmade = !!make;
            return thing;
          }
          if (!make) {
            // Something with only a place holds the objects that hang on it together.
            if (!hidden && object.camera) {
              note('“' + thing.name + '” is a camera, which is not played');
            }
            return thing;
          }
          function finish() {
            var built = null;
            try {
              // As the editor may have changed it meanwhile.
              built = make(thing.said, thing);
            } catch (error) {
              note('“' + thing.name + '”: ' + error.message);
            }
            if (!built) {
              thing.draw = idle;
              thing.step = null;
            }
            return built;
          }
          if (thing.state.visible || (!object.image && !object.particle && !object.model) || usedByOthers[String(object.id)]) {
            finish();
          } else {
            // A picture that is hidden is made ready when it first shows: its files are not
            // loaded and its shaders not made for nothing.
            thing.draw = function () {
              if (!standing(thing).visible) return;
              thing.draw = idle;
              if (!finish()) return;
              gl.bindFramebuffer(gl.FRAMEBUFFER, surface.target.framebuffer);
              gl.viewport(0, 0, surface.target.width, surface.target.height);
              thing.draw();
            };
          }
          return thing;
        }

        // Each object is drawn by the nearest layer above it that holds layers, if there is one.
        function settleIn(thing) {
          var up = thing;
          for (var depth = 0; depth < 64 && up.parent !== undefined; depth++) {
            up = byId[String(up.parent)];
            if (!up || up === thing) return;
            if (up.holds) {
              thing.heldBy = up;
              up.held.push(thing);
              return;
            }
          }
        }

        all.forEach(add);
        objects.forEach(settleIn);

        // Whether anything of the scene is another picture every frame.
        function isMoving() {
          if (shake.on) return true;
          return objects.some(function (object) {
            // What changes by itself over time, also whether the object shows.
            if (Object.keys(object.lives).some(function (name) {
              var value = object.lives[name];
              return value.changes && (!value.motion || (value.motion.leader || value.motion).playing);
            })) return true;
            if (!standing(object).visible) return false;
            return object.moving || (object.effects || []).some(function (effect) { return effect.shown.changes; });
          });
        }

        // Whether the scene has to be looked at every frame, though it may not have to be drawn:
        // a script that runs every frame, something it asked to be called for, the scene still
        // coming to rest after the pointer.
        function isLively() {
          return timers.length > 0 || audioBuffers.length > 0 || eye.settling || scripts.some(function (script) {
            return script.made === undefined || !!(script.made && script.made.update && !(script.failures > 3));
          }) || films.some(function (each) { return !each.video.paused && !each.video.ended && !each.video.error; });
        }

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
          '  float over = max(0.0, dot(c, vec3(0.2126, 0.7152, 0.0722)) - u_Threshold);',
          '  color = vec4(c * over * u_Strength, 1.0);',
          '}'
        ].join('\n'), 'the player\'s own shader');
        var blurProgram = link(fillVertex, [
          '#version 300 es',
          'precision highp float;',
          'in vec2 v_Uv;',
          'uniform sampler2D u_Texture;',
          'uniform vec2 u_Step;',
          'out vec4 color;',
          'void main() {',
          '  vec3 c = texture(u_Texture, v_Uv).rgb * 0.2270270270;',
          '  c += (texture(u_Texture, v_Uv + u_Step * 1.3846153846).rgb + texture(u_Texture, v_Uv - u_Step * 1.3846153846).rgb) * 0.3162162162;',
          '  c += (texture(u_Texture, v_Uv + u_Step * 3.2307692308).rgb + texture(u_Texture, v_Uv - u_Step * 3.2307692308).rgb) * 0.0702702703;',
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
          forgetTargets();
          sceneTarget = acquire(width, height);
          copyTarget = acquire(width, height);
          redraw = true;
          if (again) tellScripts('resizeScreen', new Vec2(width, height));
        }

        // --- Drawing ----------------------------------------------------------

        var frames = 0;

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
          objects.slice().forEach(function (object) {
            // What a layer holds is drawn by that layer.
            if (object.heldBy) return;
            gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.framebuffer);
            gl.viewport(0, 0, sceneTarget.width, sceneTarget.height);
            object.draw();
          });
          if (flag(general.bloom, false)) glow();
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

        function frame(now) {
          asked = 0;
          if (stopped) return;
          // The speed the app plays the wallpaper at; a long gap, as after a pause, counts as none.
          var host = window.__wallaeroHost;
          var passed = before ? Math.min(0.1, Math.max(0, (now - before) / 1000)) * ((host && host.rate) || 1) : 0;
          before = now;
          frameTime = passed;
          time += passed;
          resize();
          serveScripts();
          look(passed);
          if (showFilms()) dirty = true;
          // Animations move on; one that plays once stops at its end.
          motions.forEach(function (motion) {
            if (motion.leader || !motion.playing) return;
            motion.at += passed * motion.speed;
            var curve = motion.curve;
            if (curve.mode === 'single' && curve.frames > 0 && motion.at * curve.rate >= curve.frames) {
              motion.at = curve.frames / curve.rate;
              motion.playing = false;
            }
          });
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
          // Drawn anew only when it would come out another picture: a scene whose scripts only
          // wait, or whose clock still shows the same minute, is left as it is.
          var moving = isMoving();
          var must = moving || redraw || dirty || loading > 0;
          redraw = false;
          dirty = false;
          if (must) draw();
          pointerBefore = pointer.slice();
          // A scene in which nothing moves is drawn once it is all there, and then left alone.
          if (moving || loading > 0 || redraw || dirty || isLively()) {
            wake();
          } else {
            before = 0;
          }
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
              var w = thing.size[0] / 2, h = thing.size[1] / 2;
              result.corners = [page(-w, h), page(w, h), page(w, -h), page(-w, -h)];
            }
            return result;
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
          var origin = numbers(object.origin, 3, hangs ? 0 : [sceneWidth / 2, sceneHeight / 2, 0]);
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
        function describeEffect(use, place) {
          use = use || {};
          var fileName = String(plain(use.file) || '');
          var effect = json(fileName) || {};
          var values = [];
          var seen = {};
          (effect.passes || []).forEach(function (step, index) {
            if (step.command) return;
            var own = ((json(step.material) || {}).passes || [])[0];
            var vertex = own ? files['shaders/' + key(own.shader) + '.vert'] : null;
            var fragment = own ? files['shaders/' + key(own.shader) + '.frag'] : null;
            if (typeof vertex !== 'string' || typeof fragment !== 'string') return;
            var said = annotations(vertex + '\n' + fragment + '\n' + headersOf(vertex + '\n' + fragment, files));
            var constants = merged(own.constantshadervalues, ((use.passes || [])[index] || {}).constantshadervalues);
            Object.keys(said.uniforms).forEach(function (name) {
              var about = said.uniforms[name];
              var count = { 'float': 1, vec2: 2, vec3: 3, vec4: 4 }[said.types[name]];
              if (!about || !count || !isSet(about.material) || seen[about.material] || about.hidden === true) return;
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
                   isVisible: flag(use.visible, true), isSteered: changesByItself(use.visible), values: values };
        }

        return player;
      }

      var current = null;

      // The page is asked what music plays once a scene that shows it plays: the app then starts
      // asking the players, which asks the user's leave for some. Each piece of news goes to the
      // scene playing then, and is kept for one that starts later.
      var mediaHeard = null;
      function hearMedia() {
        if (mediaHeard || typeof window.wallpaperRegisterMediaPropertiesListener !== 'function') return;
        mediaHeard = {};
        [['status', 'wallpaperRegisterMediaStatusListener'], ['properties', 'wallpaperRegisterMediaPropertiesListener'],
         ['thumbnail', 'wallpaperRegisterMediaThumbnailListener'], ['playback', 'wallpaperRegisterMediaPlaybackListener'],
         ['timeline', 'wallpaperRegisterMediaTimelineListener']].forEach(function (pair) {
          window[pair[1]](function (event) {
            mediaHeard[pair[0]] = event;
            if (current && current.media) current.media(pair[0], event);
          });
        });
      }
      function showsMedia(scene) {
        var files = (scene && scene.files) || {};
        return Object.keys(files).some(function (name) {
          return typeof files[name] === 'string' && /\$media|media(Status|Properties|Thumbnail|Playback|Timeline)Changed/.test(files[name]);
        });
      }

      // What the editor asks of the scene playing now.
      function ofCurrent(name) {
        return function () {
          return current && current[name] ? current[name].apply(current, arguments) : null;
        };
      }
      window.WallaeroEngine = {
        // Draws a scene on a canvas until told to stop. One scene plays at a time. `settings` are
        // the wallpaper's own, by the names the scene has for them, and `changes` what the app's
        // editor has changed of the scene.
        play: function (canvas, scene, settings, changes) {
          if (current) current.stop(current.canvas === canvas);
          notes = [];
          current = play(canvas, scene, settings, changes);
          current.canvas = canvas;
          if (showsMedia(scene)) {
            hearMedia();
            Object.keys(mediaHeard || {}).forEach(function (kind) { current.media(kind, mediaHeard[kind]); });
          }
          // For the editor, which then shows the scene's objects.
          document.dispatchEvent(new CustomEvent('wallaero:engine'));
          return current;
        },
        report: function () { return current && current.report ? current.report() : JSON.stringify({ notes: notes }); },
        describe: ofCurrent('describe'),
        hit: ofCurrent('hit'),
        outline: ofCurrent('outline'),
        placeAt: ofCurrent('placeAt'),
        // The translation of a shader alone, for whoever wants to see or check it.
        translate: translate,
        annotations: annotations,
        // The way a value changes over time, a script made ready and the settings it declares, a
        // refused shader mended and numbers read from a text: also for checking.
        curve: curveOf,
        script: compileScript,
        mend: mend,
        mendPair: mendPair,
        numbers: numbers,
        settings: scriptSettings
      };
    })();

    """#
}
