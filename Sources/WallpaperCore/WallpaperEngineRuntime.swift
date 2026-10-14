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

      // Matrices are not made here; a script that makes one goes on, and gets nothing from it.
      function Matrix() {
        return lenient(this);
      }

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
                    'cursorEnter', 'cursorLeave', 'cursorMove', 'cursorDown', 'cursorUp', 'cursorClick'];
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
        if (/fog|smoke|cloud|mist|steam|dust|haze/.test(name)) {
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
        } else if (/leaf|petal|feather|confetti|flake/.test(name)) {
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
          ['a_Position', 'a_TexCoord', 'a_Place', 'a_Color', 'a_Frame', 'a_Spot', 'a_Uv', 'a_More'].forEach(function (name, index) {
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
          // A slot Wallpaper Engine fills itself — with the cover of the music that plays — has
          // nothing in it here: the picture the scene keeps there is for its author to look at
          // while making it.
          if (bound && typeof bound === 'object' && bound.type === 'system' && /^\$media/i.test(String(bound.name))) return 'util/nothing';
          var name = typeof bound === 'string' ? bound : (bound && typeof bound === 'object' && bound.type !== 'system' ? bound.name : null);
          return typeof name === 'string' && pictures['user/' + key(name)] ? 'user/' + key(name) : null;
        }

        // A texture by the name a material gives it: one of the scene's own, or one made here.
        // The scene's own arrive later; until then the texture is see-through.
        function texture(name) {
          var id = key(name);
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

        function forgetTargets() {
          Object.keys(targets).forEach(function (id) {
            targets[id].forEach(function (target) {
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
        function drawPass(pass, target, inputs, layer, onScreen) {
          gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
          gl.viewport(0, 0, target.width, target.height);
          gl.disable(gl.BLEND);
          gl.useProgram(pass.program.program);
          var context = { width: target.nominalWidth || target.width, height: target.nominalHeight || target.height, resolutions: [] };
          pass.slots.forEach(function (slot) {
            var input = inputs[slot];
            gl.activeTexture(gl.TEXTURE0 + slot);
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
                 script.subject && script.owner ? effectObject(script.owner, script.subject) : layerObject(script.owner),
                 inputObject, shared, consoleObject, storageObject, lenient({}),
                 scriptSettings(script.said.scriptproperties), Vec2, Vec3, Vec4, Matrix, Matrix,
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
          setInterval: function (callback, delay) { return later(callback, delay, true); }
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
          object.isPlaying = function () { return true; };
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
          object.getAnimationLayerCount = function () { return thing.puppet && thing.puppet.moving ? 1 : 0; };
          ['getAnimationLayer', 'getTextureAnimation', 'getVideoTexture', 'getMaterial'].forEach(function (name) { object[name] = unsteered; });
          // An animation of one of the object's values, by the name the scene gives it.
          object.getAnimation = function (wanted) {
            var found = motionOf(thing, wanted);
            return found ? steered(found) : unsteered();
          };
          thing.forScripts = lenient(object);
          standsFor.set(thing.forScripts, thing);
          return thing.forScripts;
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
          getCameraTransforms: function () {
            return { eye: new Vec3(0, 0, 1), center: new Vec3(0, 0, 0), up: new Vec3(0, 1, 0), zoom: 1 };
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
          scripts.slice().forEach(function (script) { call(script, name, argument); });
        }

        // What plays on the Mac is not told to scenes. Their scripts are told so once, the way
        // Wallpaper Engine tells them that nothing plays: a scene made to put its music widget
        // away then does, rather than showing it with nothing in it.
        var mediaTold = false;
        function tellNoMedia() {
          mediaTold = true;
          var none = new Vec3(0, 0, 0);
          tellScripts('mediaStatusChanged', { enabled: false });
          tellScripts('mediaPlaybackChanged', { state: MEDIA_PLAYBACK.PLAYBACK_STOPPED });
          tellScripts('mediaPropertiesChanged', { title: '', artist: '', subTitle: '', albumTitle: '', albumArtist: '', genres: '', contentType: '' });
          tellScripts('mediaThumbnailChanged', { hasThumbnail: false, primaryColor: none, secondaryColor: none, tertiaryColor: none,
                                                 textColor: new Vec3(1, 1, 1), highContrastColor: new Vec3(1, 1, 1) });
          tellScripts('mediaTimelineChanged', { position: 0, duration: 0 });
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

        function buildPuppet(said, layers, name) {
          var corners = numbersOf(said.corners, Float32Array);
          var triangles = numbersOf(said.triangles, Uint16Array);
          var count = Math.floor(corners.length / 12);
          var bones = (said.bones || []).map(function (bone) {
            var matrix = bone.matrix || [];
            return { parent: number(bone.parent, -1), rest: [matrix[0], matrix[1], matrix[4], matrix[5], matrix[12], matrix[13]] };
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

          // The animation that plays: the first of the layers the scene has switched on.
          var playing = null;
          (layers || []).forEach(function (layer) {
            if (flag(layer.visible, true) === false) return;
            var animation = (said.animations || []).filter(function (each) { return each.id === number(layer.animation, -1); })[0];
            if (!animation) return;
            if (playing) {
              note('“' + name + '” plays several animations at once; only the first is played');
              return;
            }
            playing = { frames: numbersOf(animation.frames, Float32Array), frameCount: animation.frameCount, length: animation.length,
                        rate: animation.fps * number(layer.rate, 1), mode: animation.mode };
          });

          var places = new Float32Array(count * 2);
          var texture = new Float32Array(count * 2);
          for (var corner = 0; corner < count; corner++) {
            places[corner * 2] = corners[corner * 12];
            places[corner * 2 + 1] = corners[corner * 12 + 1];
            texture[corner * 2] = corners[corner * 12 + 2];
            texture[corner * 2 + 1] = corners[corner * 12 + 3];
          }
          var shape = gl.createVertexArray();
          gl.bindVertexArray(shape);
          var placeBuffer = gl.createBuffer();
          gl.bindBuffer(gl.ARRAY_BUFFER, placeBuffer);
          gl.bufferData(gl.ARRAY_BUFFER, places, gl.DYNAMIC_DRAW);
          gl.enableVertexAttribArray(5);
          gl.vertexAttribPointer(5, 2, gl.FLOAT, false, 0, 0);
          gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
          gl.bufferData(gl.ARRAY_BUFFER, texture, gl.STATIC_DRAW);
          gl.enableVertexAttribArray(6);
          gl.vertexAttribPointer(6, 2, gl.FLOAT, false, 0, 0);
          gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
          gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, triangles, gl.STATIC_DRAW);
          gl.bindVertexArray(null);

          var puppet = { shape: shape, count: triangles.length, moving: !!playing };
          // Puts every corner where the bones are at a moment.
          puppet.pose = function (seconds) {
            if (!playing) return;
            var at = seconds * playing.rate;
            if (playing.mode === 'mirror') {
              at = at % (playing.length * 2);
              if (at > playing.length) at = playing.length * 2 - at;
            } else if (playing.mode === 'single') {
              at = Math.min(at, playing.length);
            } else {
              at = at % playing.length;
            }
            var before = Math.min(Math.floor(at), playing.frameCount - 1);
            var after = Math.min(before + 1, playing.frameCount - 1);
            var share = at - before;
            var frames = playing.frames;
            // Each bone from its parent in this frame: scaled, turned, then moved.
            bones.forEach(function (bone, index) {
              var one = (index * playing.frameCount + before) * 9, two = (index * playing.frameCount + after) * 9;
              function value(part) { return frames[one + part] + (frames[two + part] - frames[one + part]) * share; }
              var cos = Math.cos(value(5)), sin = Math.sin(value(5));
              bone.now = [cos * value(6), sin * value(6), -sin * value(7), cos * value(7), value(0), value(1)];
              bone.done = false;
            });
            function whole(index, depth) {
              var bone = bones[index];
              if (!bone.done) {
                var parent = bones[bone.parent];
                bone.moved = parent && depth < 64 ? joined(whole(bone.parent, depth + 1), bone.now) : bone.now;
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
          };
          return puppet;
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
            // Drawn into the layer that holds it, an object is placed in that layer's own
            // coordinates; the layer's place is added when the layer is drawn.
            if (!parent.holds || whole) matrix = times(up.matrix, matrix);
          } else if (eye && eye.on) {
            // What hangs together moves with the pointer together.
            var moved = shifted(thing);
            matrix[12] += moved[0];
            matrix[13] += moved[1];
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
              return { name: key(target.name), scale: Math.max(1, number(target.scale, 1)) };
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
          var chosenPicture = chosenTexture((base.usertextures || [])[0]);
          if (chosenPicture) layer.picture = shows(layer, texture(chosenPicture));
          else if (base.textures && base.textures[0]) layer.picture = shows(layer, texture('materials/' + base.textures[0]));
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
            layer.puppet = buildPuppet(bends, object.animationlayers, layer.name);
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
            mesh.pose(time);
            place = placeOf(matrix, [1, 1]);
          }
          var effects = layer.effects.filter(function (effect) { return effect.shown.now; });

          // The picture as it comes: a frame of it, if it is animated.
          var source = null;
          if (layer.picture) {
            var shown = frameAt(layer.picture, time);
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
              var target = acquire(width / wanted.scale, height / wanted.scale);
              target.nominalWidth = nominal[0] / wanted.scale;
              target.nominalHeight = nominal[1] / wanted.scale;
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
            Object.keys(named).forEach(function (name) { release(named[name]); });
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
            default:
              note('“' + system.name + '”: what sets up a particle by “' + said.name + '” is not played');
              return null;
          }
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
              note('“' + system.name + '”: a particle\'s “' + String(said.output) + '” changed by “remapvalue” is not played');
              return null;
            default:
              note('“' + system.name + '”: what changes a particle by “' + said.name + '” is not played');
              return null;
          }
        }

        function buildParticles(object, system) {
          var fileName = String(plain(object.particle) || '');
          var said = json(fileName);
          var name = system.name;
          if (!said) {
            note('“' + name + '”: its particles, ' + fileName + ', are not in the scene');
            return null;
          }
          var material = ((json(said.material) || {}).passes || [])[0] || {};
          var over = object.instanceoverride || {};
          system.moving = true;
          system.age = 0;
          system.particles = [];
          system.made = 0;
          system.picture = texture('materials/' + ((material.textures || [])[0] || 'particle/dot'));
          system.additive = key(material.blending || 'translucent') === 'additive';
          system.bright = number((material.constantshadervalues || {}).ui_editor_properties_overbright, 1);
          // Further away is smaller: the particles have depth, and are drawn as seen by an eye.
          system.perspective = (number(said.flags, 0) & 4) !== 0;
          // What the scene changes of the particles where it uses them; a setting of the
          // wallpaper may stand behind each, and the editor may change each.
          system.settle = function () {
            over = system.said.instanceoverride || {};
            system.most = Math.max(1, Math.min(20000, Math.round(number(said.maxcount, 100) * number(over.count, 1))));
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
            if (point.onScene) {
              var matrix = standing(system, true).matrix;
              var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
              if (Math.abs(area) < 1e-9) return point.offset;
              var dx = point.onScene[0] - matrix[12], dy = point.onScene[1] - matrix[13];
              return [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area, point.onScene[2]];
            }
            return point.follows ? [pointerThere[0] + point.offset[0], pointerThere[1] + point.offset[1], point.offset[2]] : point.offset;
          };
          function findPointer() {
            var matrix = standing(system, true).matrix;
            var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
            if (Math.abs(area) < 1e-9) return;
            var dx = pointer[0] * sceneWidth - matrix[12], dy = (1 - pointer[1]) * sceneHeight - matrix[13];
            pointerThere = [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area];
          }
          system.emitters = (said.emitter || []).map(function (emitter) {
            return {
              point: number(emitter.controlpoint, 0), withPointer: follows(number(emitter.controlpoint, 0)),
              box: key(emitter.name) === 'boxrandom',
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

          function make(emitter) {
            var particle = { id: ++system.made, seed: Math.random(), age: 0, life: 1, size: 20, alpha: 1, red: 1, green: 1, blue: 1,
                             angle: 0, spin: 0, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0 };
            var away = [0, 0, 0];
            var axis;
            if (emitter.box) {
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
            particle.x = emitter.origin[0] + away[0] + from[0];
            particle.y = emitter.origin[1] + away[1] + from[1];
            particle.z = emitter.origin[2] + away[2] + from[2];
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
          }

          system.step = function (seconds) {
            system.age += seconds;
            if (points.some(function (point) { return point.follows; })) findPointer();
            system.emitters.forEach(function (emitter) {
              if (system.age < emitter.waits) return;
              // Particles made where the pointer is are not made while it is away.
              if (emitter.withPointer && !pointerSeen) return;
              if (emitter.burst > 0) {
                for (var first = 0; first < emitter.burst && system.particles.length < system.most; first++) make(emitter);
                emitter.burst = 0;
              }
              if (emitter.lasts > 0 && system.age > emitter.waits + emitter.lasts) return;
              emitter.owed += emitter.rate * system.rate * seconds;
              while (emitter.owed >= 1) {
                emitter.owed -= 1;
                if (system.particles.length < system.most) make(emitter);
              }
            });
            var alive = [];
            system.particles.forEach(function (particle) {
              particle.age += seconds;
              if (particle.age >= particle.life) return;
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
            var stands = standing(system);
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
            gl.useProgram(particleProgram.program);
            gl.enable(gl.BLEND);
            if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
            else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, layer.texture);
            gl.uniform1i(particleProgram.uniforms.u_Texture.location, 0);
            gl.uniform1i(particleProgram.uniforms.u_Channels.location, CHANNELS[system.picture.channels] || 0);
            gl.uniform1f(particleProgram.uniforms.u_Bright.location, system.bright);
            gl.uniformMatrix2fv(particleProgram.uniforms.u_Linear.location, false, new Float32Array(linear));
            gl.uniform2f(particleProgram.uniforms.u_Scene.location, surface.width, surface.height);
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
              var stands = standing(system);
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
              var stands = standing(system);
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

          // A system begins as if it had been running for a while already.
          var warm = Math.min(60, Math.max(0, number(said.starttime, 0)));
          for (var played = 0; played < warm; played += 1 / 20) system.step(1 / 20);
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
        all.forEach(function (object) {
          if (object.parent !== undefined && object.parent !== null) hasChildren[String(object.parent)] = true;
        });

        // Puts an object on the scene, above what is there.
        function add(object) {
          var hidden = object.visible === false;
          var make = object.image ? buildImage : (object.particle ? buildParticles : (object.sound ? buildSound :
                     (object.text !== undefined && object.text !== null ? buildText : null)));
          var thing = placed(object, String(plain(object.image) || plain(object.particle) || (object.sound ? 'sound' : (make ? 'text' : 'group'))));
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
          if (hidden && !scripted) {
            thing.unmade = !!make;
            return thing;
          }
          if (!make) {
            // Something with only a place holds the objects that hang on it together.
            if (!hidden && (object.model || object.light || object.camera)) {
              note('“' + thing.name + '” is ' + (object.model ? 'a 3D model' : (object.light ? 'a light' : 'a camera')) + ', which is not played');
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
          if (thing.state.visible || (!object.image && !object.particle)) {
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

        function look(seconds) {
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
          var strength = number(general.bloomstrength, 2), threshold = number(general.bloomthreshold, 0.65);
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

        function draw() {
          gl.bindFramebuffer(gl.FRAMEBUFFER, sceneTarget.framebuffer);
          gl.viewport(0, 0, sceneTarget.width, sceneTarget.height);
          gl.disable(gl.BLEND);
          gl.clearColor(clear[0], clear[1], clear[2], 1);
          gl.clear(gl.COLOR_BUFFER_BIT);
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
