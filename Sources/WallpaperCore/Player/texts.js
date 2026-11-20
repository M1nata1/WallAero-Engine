  // Texts: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeTexts(ctx) {
    var gl = ctx.gl, link = ctx.link, passShape = ctx.passShape, newTexture = ctx.newTexture, looksOf = ctx.looksOf, flat = ctx.flat, acquire = ctx.acquire, release = ctx.release, general = ctx.general, inDepth = ctx.inDepth, changed = ctx.changed, withLooks = ctx.withLooks, drawPass = ctx.drawPass, same = ctx.same, live = ctx.live, sheetTime = ctx.sheetTime, grabProgram = ctx.grabProgram, straightProgram = ctx.straightProgram, nudged = ctx.nudged, placeOf = ctx.placeOf, worldPlaceOf = ctx.worldPlaceOf, CHANNELS = ctx.CHANNELS, put = ctx.put, FILL = ctx.FILL, MAX_LIGHTS = ctx.MAX_LIGHTS, sceneLights = ctx.sceneLights, frameAt = ctx.frameAt, also = ctx.also, standing = ctx.standing, stale = ctx.stale, buildEffects = ctx.buildEffects;
    // --- Texts ------------------------------------------------------------
    //
    // A text is drawn by the browser into a picture of its own, anew whenever it says
    // something else, and then put on the scene like any picture.

    var fontFiles = (ctx.scene && ctx.scene.fonts) || {};
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
      thing.blendMode = number(object.colorBlendMode, defaults.object.colorBlendMode);
      thing.ownColor = true; // the color is in the picture already
      // In a scene in three dimensions a text stands in the world, as a picture does.
      thing.inWorld = inDepth;
      also(thing, 'text', live(object.text, 0, defaults.text.text, thing, 'text'));
      also(thing, 'pointsize', live(object.pointsize, 1, defaults.text.pointsize, thing));
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
        // The room left around the letters, across and up: one number for both, or two.
        var room = numbers(said('padding'), 2, defaults.text.padding);
        var across = key(plain(said('horizontalalign')) || defaults.text.horizontalalign), down = key(plain(said('verticalalign')) || defaults.text.verticalalign);
        var background = flag(said('opaquebackground'), defaults.text.opaquebackground) ? numbers(said('backgroundcolor'), 3, defaults.text.backgroundcolor) : null;
        var family = fontOf(plain(said('font')));
        var widest = flag(said('limitwidth'), defaults.text.limitwidth) ? number(said('maxwidth'), defaults.text.maxwidth) : 0;
        var rows = flag(said('limitrows'), defaults.text.limitrows) ? Math.max(1, number(said('maxrows'), defaults.text.maxrows)) : 0;
        var ellipsis = flag(said('limituseellipsis'), defaults.text.limituseellipsis);
        // Between letters and between lines, in units of the scene.
        var spacing = numbers(said('spacing'), 2, defaults.text.spacing);
        var outline = flag(said('outline'), defaults.text.outline) ? { color: numbers(said('outlinecolor'), 3, defaults.text.outlinecolor), thickness: Math.max(0, number(said('outlinethickness'), defaults.text.outlinethickness)) } : null;
        var shadow = flag(said('dropshadow'), defaults.text.dropshadow) ? { color: numbers(said('dropshadowcolor'), 3, defaults.text.dropshadowcolor), offset: numbers(said('dropshadowoffset'), 2, defaults.text.dropshadowoffset),
                                                        size: Math.max(0, number(said('dropshadowsize'), defaults.text.dropshadowsize)), opacity: Math.max(0, number(said('dropshadowopacity'), defaults.text.dropshadowopacity)) } : null;
        var blur = flag(said('blur'), defaults.text.blur) ? Math.max(0, number(said('blursize'), defaults.text.blursize)) : 0;
        var asked = [state.text, state.pointsize[0], state.color.join(), ctx.scale, room.join(), across, down, String(background), family, fontsThere, widest, rows,
                     ellipsis, spacing.join(), JSON.stringify(outline), JSON.stringify(shadow), blur].join('\u0001');
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
        var line = Math.max(1, rise + fall + spacing[1]); // from one line to the next
        // How wide a line is, with the room between its letters.
        function wide(text) {
          if (!spacing[0]) return pen.measureText(text).width;
          var letters = Array.from(text);
          return pen.measureText(text).width + spacing[0] * Math.max(0, letters.length - 1);
        }
        // Where another font stands in for the one the text names, its letters are narrower
        // or wider. The box the scene gives says how wide the text was in the right font, so
        // the letters are drawn that much narrower or wider, and the text takes its old room.
        var squeeze = 1;
        if (given[0] > 0 && saved !== '' && saved.indexOf('\n') < 0 && !(widest > 0)) {
          var measured = wide(saved);
          var savedWidth = given[0] - (roomy ? room[0] * 2 : 0);
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
              if (current && wide(longer) > widest) {
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
        if (rows > 0 && lines.length > rows) {
          lines = lines.slice(0, rows);
          // What is cut off is told by an ellipsis at the end of the last line that shows.
          if (ellipsis) {
            var last = Array.from(lines[rows - 1].replace(/\s+$/, ''));
            while (last.length && widest > 0 && wide(last.join('') + '…') > widest) last.pop();
            lines[rows - 1] = last.join('') + '…';
          }
        } else if (ellipsis && widest > 0) {
          // A single word longer than the line ends with an ellipsis where the line ends.
          lines = lines.map(function (each) {
            if (wide(each) <= widest) return each;
            var letters = Array.from(each);
            while (letters.length && wide(letters.join('') + '…') > widest) letters.pop();
            return letters.join('') + '…';
          });
        }
        var widths = lines.map(function (each) { return wide(each) * squeeze; });
        // The text itself, and around it the room the scene leaves for what effects add; then
        // as much again as the outline, the shadow and the blur reach past the letters.
        var content = [Math.max.apply(null, widths.concat([1])), Math.max(1, lines.length) * line];
        var reach = Math.ceil(Math.max(outline ? outline.thickness : 0,
                                       shadow ? Math.max(Math.abs(shadow.offset[0]), Math.abs(shadow.offset[1])) + shadow.size * 2 : 0,
                                       blur * 2));
        var inner = [content[0] + room[0] * 2, content[1] + room[1] * 2];
        var width = inner[0] + reach * 2, height = inner[1] + reach * 2;
        paper.width = Math.max(1, Math.min(8192, Math.ceil(width * ctx.scale)));
        paper.height = Math.max(1, Math.min(8192, Math.ceil(height * ctx.scale)));
        var unit = paper.width / width; // pixels of the picture to a unit of the scene
        pen.setTransform(unit, 0, 0, paper.height / height, 0, 0);
        pen.clearRect(0, 0, width, height);
        if (background) {
          pen.fillStyle = hex(background);
          pen.fillRect(reach, reach, inner[0], inner[1]);
        }
        pen.font = font;
        pen.textBaseline = 'alphabetic';
        pen.lineJoin = 'round';
        // Every line, the way `paint` puts letters down: filled, or traced round.
        function letters(paint) {
          lines.forEach(function (each, index) {
            var x = reach + (across === 'left' ? room[0] : (across === 'right' ? inner[0] - room[0] - widths[index] : (inner[0] - widths[index]) / 2));
            pen.save();
            pen.translate(x, reach + room[1] + rise + index * line);
            pen.scale(squeeze, 1);
            if (!spacing[0]) {
              paint(each, 0);
            } else {
              var at = 0;
              Array.from(each).forEach(function (one) {
                paint(one, at);
                at += pen.measureText(one).width + spacing[0];
              });
            }
            pen.restore();
          });
        }
        function fill(text, x) { pen.fillText(text, x, 0); }
        function trace(text, x) { pen.strokeText(text, x, 0); }
        // The text as a whole, outline under the letters, in one color or as it is.
        function lettering(color) {
          if (outline) {
            pen.strokeStyle = color || hex(outline.color);
            pen.lineWidth = outline.thickness * 2;
            letters(trace);
          }
          pen.fillStyle = color || hex(state.color);
          letters(fill);
        }
        // A shadow or a blur is drawn as the shadow of letters put far off the picture, so
        // that only the shadow lands on it: blurred by the canvas, the way it can everywhere.
        function blurred(color, alpha, size, dx, dy) {
          var away = width + height + 1000;
          pen.save();
          pen.globalAlpha = Math.min(1, alpha);
          pen.shadowColor = color;
          pen.shadowBlur = size * unit;
          pen.shadowOffsetX = (away + dx) * unit;
          pen.shadowOffsetY = dy * (paper.height / height);
          pen.translate(-away, 0);
          lettering(color);
          pen.restore();
        }
        if (shadow) {
          // Stronger than whole, a shadow is laid down again for what is past one.
          for (var left = shadow.opacity; left > 0.001; left -= 1) {
            blurred(hex(shadow.color), left, shadow.size, shadow.offset[0], shadow.offset[1]);
          }
        }
        if (blur > 0) blurred(hex(state.color), 1, blur, 0, 0);
        else lettering(null);
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
      if (!ctx.eye || !ctx.eye.on) return [0, 0];
      var depth = thing.state.parallax;
      return [-ctx.eye.x * depth[0] * ctx.eye.amount * ctx.sceneWidth, ctx.eye.y * depth[1] * ctx.eye.amount * ctx.sceneHeight];
    }

    // A picture as the scene's lights show it, drawn into a target of its own the size it is
    // drawn at: lit by every light, by physically based shading with the surface facing as
    // its normal map says (or straight out of the scene without one), plus what is behind it,
    // reflected and bent by its normal map. What comes out is drawn as the picture would be.
    var litMade = null, litWhite = null;
    function litProgramNow() {
      if (litMade !== null) return litMade;
      litMade = link(ctx.fillVertex, [
        '#version 300 es',
        'precision highp float;',
        'in vec2 v_Uv;',
        'uniform sampler2D u_Texture;',
        'uniform vec4 u_Frame;',
        'uniform int u_Channels;',
        'uniform sampler2D u_Normal;',
        'uniform int u_HasNormal;',
        'uniform sampler2D u_Masks;',
        'uniform vec4 u_Maps;',          // which channels of the masks are used: metal, rough, reflect, glow
        'uniform sampler2D u_Scene;',
        'uniform int u_Lighting;',
        'uniform int u_Reflecting;',
        'uniform mat4 u_Matrix;',        // the picture in the scene
        'uniform vec2 u_Size;',          // its size, in units of the scene
        'uniform vec2 u_SceneSize;',
        'uniform float u_Metallic;',
        'uniform float u_Roughness;',
        'uniform float u_Reflectivity;',
        'uniform vec3 u_Emissive;',
        'uniform vec3 u_Ambient;',
        'uniform int u_LightCount;',
        'uniform vec4 u_LightPlace[' + MAX_LIGHTS + '];',
        'uniform vec4 u_LightColor[' + MAX_LIGHTS + '];',
        'uniform vec4 u_LightAim[' + MAX_LIGHTS + '];',
        'out vec4 color;',
        'const float PI = 3.14159265;',
        // Light from one direction on a surface: the diffuse part, and the specular one by the
        // GGX distribution, Smith geometry and Schlick's Fresnel.
        'vec3 shade(vec3 n, vec3 l, vec3 albedo, vec3 radiance, vec3 f0, float rough, float metal) {',
        '  vec3 v = vec3(0.0, 0.0, 1.0);',
        '  vec3 h = normalize(v + l);',
        '  float a = rough * rough;',
        '  float a2 = a * a;',
        '  float nh = max(dot(n, h), 0.0);',
        '  float spread = nh * nh * (a2 - 1.0) + 1.0;',
        '  float d = a2 / (PI * spread * spread);',
        '  float k = (rough + 1.0) * (rough + 1.0) / 8.0;',
        '  float nv = max(dot(n, v), 0.001);',
        '  float nl = max(dot(n, l), 0.0);',
        '  float g = nv / (nv * (1.0 - k) + k) * max(nl, 0.001) / (max(nl, 0.001) * (1.0 - k) + k);',
        '  vec3 f = f0 + (1.0 - f0) * pow(max(1.0 - max(dot(h, v), 0.0), 0.001), 5.0);',
        '  vec3 specular = d * g * f / max(4.0 * nv * nl, 0.001);',
        '  vec3 diffuse = (1.0 - metal) * (1.0 - f);',
        '  return (diffuse * albedo / PI + specular) * radiance * nl;',
        '}',
        'void main() {',
        '  vec4 base = texture(u_Texture, u_Frame.xy + v_Uv * u_Frame.zw);',
        '  if (u_Channels == 1) base = vec4(1.0, 1.0, 1.0, base.r);',
        '  if (u_Channels == 2) base = vec4(base.rrr, base.g);',
        '  vec4 masks = texture(u_Masks, v_Uv);',
        '  float metal = mix(u_Metallic, masks.r, u_Maps.x);',
        '  float rough = clamp(mix(u_Roughness, masks.g, u_Maps.y), 0.03, 1.0);',
        // The picture's own directions in the scene: across it, and up it.
        '  vec3 across = normalize(u_Matrix[0].xyz);',
        '  vec3 up = normalize(u_Matrix[1].xyz);',
        '  vec3 n = vec3(0.0, 0.0, 1.0);',
        '  if (u_HasNormal == 1) {',
        '    vec2 m = texture(u_Normal, v_Uv).xy * 2.0 - 1.0;',
        '    n = vec3(m, sqrt(clamp(1.0 - dot(m, m), 0.0, 1.0)));',
        '  }',
        '  vec3 world = normalize(across * n.x + up * n.y + vec3(0.0, 0.0, n.z));',
        // Where this point of the picture is in the scene; its top row comes first.
        '  vec2 local = vec2((v_Uv.x - 0.5) * u_Size.x, (0.5 - v_Uv.y) * u_Size.y);',
        '  vec3 place = (u_Matrix * vec4(local, 0.0, 1.0)).xyz;',
        '  vec3 result = base.rgb;',
        '  if (u_Lighting == 1) {',
        '    vec3 f0 = mix(vec3(0.04), base.rgb, metal);',
        '    vec3 light = vec3(0.0);',
        '    for (int i = 0; i < ' + MAX_LIGHTS + '; i++) {',
        '      if (i >= u_LightCount) break;',
        '      vec3 toLight;',
        '      float left = 1.0;',
        '      if (u_LightPlace[i].w > 0.5) {',
        '        vec3 way = u_LightPlace[i].xyz - place;',
        '        float far = length(way);',
        '        toLight = way / max(far, 0.0001);',
        '        float reach = u_LightColor[i].w;',
        '        if (reach > 0.0) left = pow(clamp(1.0 - far / reach, 0.0, 1.0), max(u_LightAim[i].w, 0.01));',
        '        if (dot(u_LightAim[i].xyz, u_LightAim[i].xyz) > 0.0) left *= smoothstep(0.5, 0.9, dot(-toLight, normalize(u_LightAim[i].xyz)));',
        '      } else {',
        '        toLight = normalize(-u_LightPlace[i].xyz);',
        '      }',
        '      light += shade(world, toLight, base.rgb, u_LightColor[i].rgb * left, f0, rough, metal);',
        '    }',
        '    if (u_Maps.w > 0.5) light = max(light, u_Emissive * base.rgb * masks.a);',
        '    result = max(vec3(0.001), u_Ambient) * base.rgb + light;',
        '  }',
        '  if (u_Reflecting == 1) {',
        // What is behind, seen through the surface where it leans: further the more it does.
        '    float facing = max(0.001, n.z);',
        '    vec2 lean = length(n.xy) > 0.0001 ? normalize(n.xy) * vec2(0.15, 0.15 * u_SceneSize.x / u_SceneSize.y) : vec2(0.0);',
        '    vec2 onScene = vec2(place.x / u_SceneSize.x, 1.0 - place.y / u_SceneSize.y);',
        '    onScene += (vec2(across.x, -across.y) * lean.x + vec2(up.x, -up.y) * lean.y) * facing;',
        // A rough surface reflects a blur.
        '    float spread = rough * 0.01;',
        '    vec3 seen = texture(u_Scene, onScene).rgb * 0.4;',
        '    seen += (texture(u_Scene, onScene + vec2(spread, 0.0)).rgb + texture(u_Scene, onScene - vec2(spread, 0.0)).rgb',
        '           + texture(u_Scene, onScene + vec2(0.0, spread)).rgb + texture(u_Scene, onScene - vec2(0.0, spread)).rgb) * 0.15;',
        '    float strength = u_Reflectivity * mix(1.0, masks.b, u_Maps.z);',
        '    seen = pow(max(vec3(0.001), seen * (1.0 - facing) * strength), vec3(2.0 - metal));',
        '    result += clamp(seen, 0.0, 1.0);',
        '  }',
        '  color = vec4(result, base.a);',
        '}'
      ].join('\n'), 'the player\'s own shader') || false;
      return litMade;
    }

    function litPicture(layer, source, matrix, nominal, width, height) {
      var lit = layer.lit;
      if (!lit.target || lit.target.width !== Math.max(1, Math.round(width)) || lit.target.height !== Math.max(1, Math.round(height))) {
        release(lit.target);
        lit.target = acquire(width, height);
      }
      var program = litProgramNow();
      var at = function (name) { return program.uniforms[name] ? program.uniforms[name].location : null; };
      // What is under the picture, for it to reflect: a copy of what it is drawn on.
      var behind = null;
      if (lit.reflecting) {
        var onto = ctx.surface.target;
        behind = acquire(onto.width, onto.height);
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, onto.framebuffer);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, behind.framebuffer);
        gl.blitFramebuffer(0, 0, onto.width, onto.height, 0, 0, onto.width, onto.height, gl.COLOR_BUFFER_BIT, gl.LINEAR);
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER, lit.target.framebuffer);
      gl.viewport(0, 0, lit.target.width, lit.target.height);
      gl.disable(gl.BLEND);
      gl.useProgram(program.program);
      litWhite = litWhite || flat(255, 255, 255, 255);
      var white = litWhite;
      [[0, source.texture, 'u_Texture'],
       [1, lit.normal && lit.normal.ready !== false ? lit.normal.layers[0].texture : white.layers[0].texture, 'u_Normal'],
       [2, lit.masks && lit.masks.ready !== false ? lit.masks.layers[0].texture : white.layers[0].texture, 'u_Masks'],
       [3, behind ? behind.texture : white.layers[0].texture, 'u_Scene']].forEach(function (input) {
        gl.activeTexture(gl.TEXTURE0 + input[0]);
        gl.bindTexture(gl.TEXTURE_2D, input[1]);
        if (at(input[2])) gl.uniform1i(at(input[2]), input[0]);
      });
      gl.uniform4fv(at('u_Frame'), source.frame || [0, 0, 1, 1]);
      gl.uniform1i(at('u_Channels'), CHANNELS[source.channels] || 0);
      gl.uniform1i(at('u_HasNormal'), lit.normal && lit.normal.ready !== false ? 1 : 0);
      gl.uniform4fv(at('u_Maps'), lit.maps);
      gl.uniform1i(at('u_Lighting'), lit.lighting ? 1 : 0);
      gl.uniform1i(at('u_Reflecting'), behind ? 1 : 0);
      gl.uniformMatrix4fv(at('u_Matrix'), false, new Float32Array(matrix));
      gl.uniform2f(at('u_Size'), nominal[0], nominal[1]);
      gl.uniform2f(at('u_SceneSize'), ctx.sceneWidth, ctx.sceneHeight);
      gl.uniform1f(at('u_Metallic'), lit.metallic);
      gl.uniform1f(at('u_Roughness'), lit.roughness);
      gl.uniform1f(at('u_Reflectivity'), lit.reflectivity);
      gl.uniform3f(at('u_Emissive'), lit.emissive[0] * lit.glow, lit.emissive[1] * lit.glow, lit.emissive[2] * lit.glow);
      var ambient = numbers(general.ambientcolor, 3, defaults.lit.ambientcolor);
      gl.uniform3f(at('u_Ambient'), ambient[0], ambient[1], ambient[2]);
      var lights = sceneLights();
      gl.uniform1i(at('u_LightCount'), lights.length);
      if (lights.length) {
        var places = [], shades = [], aims = [];
        lights.forEach(function (light) {
          // A tube, for a flat layer, shines from its middle.
          var place = light.end[3] ? [0, 1, 2].map(function (k) { return (light.place[k] + light.end[k]) / 2; }).concat([1]) : light.place;
          places.push.apply(places, place); shades.push.apply(shades, light.color); aims.push.apply(aims, light.aim);
        });
        gl.uniform4fv(at('u_LightPlace'), new Float32Array(places));
        gl.uniform4fv(at('u_LightColor'), new Float32Array(shades));
        gl.uniform4fv(at('u_LightAim'), new Float32Array(aims));
      }
      gl.bindVertexArray(passShape);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      [0, 1, 2, 3].forEach(function (unit) {
        gl.activeTexture(gl.TEXTURE0 + unit);
        gl.bindTexture(gl.TEXTURE_2D, null);
      });
      gl.activeTexture(gl.TEXTURE0);
      release(behind);
      gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.surface.target.framebuffer);
      gl.viewport(0, 0, ctx.surface.target.width, ctx.surface.target.height);
      return { texture: lit.target.texture, resolution: source.resolution };
    }

    // `ahead`: only its finished picture is made, for others to take (`layer.composite`); it is
    // then put on the scene from that, later in the frame, if it shows.
    function drawImage(layer, ahead) {
      var state = layer.state;
      var stands = standing(layer);
      var shows = stands.visible && !ahead;
      if (layer.composite && !ahead && layer.composite.frame === ctx.frames && layer.composite.target) {
        if (shows) {
          var already = layer.shift ? nudged(stands.matrix, layer.shift[0], layer.shift[1]) : stands.matrix;
          drawComposite(layer, already, stands);
        }
        return;
      }
      // A hidden layer others take the finished picture of is still made in its turn, only not
      // put on the scene: Wallpaper Engine fills it all the same (2938612768's capsule takes
      // its color from a hidden layer over the background, and is not seen against it).
      if (!shows && !layer.composite) return;
      var nominal = layer.size;
      var matrix = layer.shift ? nudged(stands.matrix, layer.shift[0], layer.shift[1]) : stands.matrix;
      // The layer's effects are worked out no finer than the layer shows on the screen: one
      // shown at a third of its size needs a ninth of the pixels, and its effects, which are
      // told the layer's own size, come out the same. Taken in sixteenths, so that a layer
      // whose size is animated does not ask for a picture of a new size every frame.
      var finer = function (x, y) {
        var shown = Math.sqrt(x * x + y * y);
        return Math.max(1 / 16, Math.min(1, Math.ceil(shown * 16) / 16));
      };
      // One others take as a picture is made at its own size, however small it shows; so is
      // one in the world, whose size on the screen its matrix does not tell.
      var world = layer.inWorld && !layer.takesScene && !layer.holds && ctx.surface.target === ctx.sceneTarget;
      var whole = layer.composite || world;
      var width = whole ? nominal[0] : nominal[0] * ctx.scale * finer(matrix[0], matrix[1]);
      var height = whole ? nominal[1] : nominal[1] * ctx.scale * finer(matrix[4], matrix[5]);
      var bright = layer.brightness;
      if (layer.materialAlpha !== undefined) stands = { matrix: stands.matrix, alpha: stands.alpha * layer.materialAlpha, above: stands.above, visible: stands.visible };
      var tint = layer.ownColor ? [1, 1, 1, stands.alpha]
               : [state.color[0] * bright, state.color[1] * bright, state.color[2] * bright, stands.alpha];
      var how = layer.blendMode > 0 && layer.blendMode !== 9 ? layer.blendMode :
                (layer.blendMode === 9 || layer.blending === 'additive' ? 'additive' : (layer.blending === 'normal' ? 'normal' : 'translucent'));
      var onto = ctx.surface;
      var place = world ? worldPlaceOf(matrix, nominal, layer.testsDepth) : placeOf(matrix, nominal);
      var onScreen = placeOf(matrix, nominal);
      // A picture that bends is drawn as its triangles, whose corners are counted in the
      // picture's own pixels from its middle.
      var mesh = layer.puppet || null;
      if (mesh) {
        mesh.pose(ctx.time, matrix);
        place = world ? worldPlaceOf(matrix, [1, 1], layer.testsDepth) : placeOf(matrix, [1, 1]);
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
      if (source && layer.lit && litProgramNow()) source = litPicture(layer, source, matrix, nominal, width, height);
      if (!effects.length && source && !layer.composite) {
        put(withLooks(source, layer), place, tint, how, mesh);
        return;
      }
      // A layer's color and how see-through it is are its picture's, given before its effects,
      // as Wallpaper Engine's own pass of the picture gives them: an effect that draws by
      // itself shows on a layer not to be seen (3662790108's orbits), and its finished
      // picture, taken by others, has them. What is put on the scene then is as it is.
      var atBase = !!source && !layer.takesScene && !layer.holds;
      var finished = atBase ? [1, 1, 1, 1] : tint;
      layer.tintedAtBase = atBase;
      // One that does not move is drawn once and kept — at the size it is now shown at, and
      // of the color it had.
      if (layer.kept && (layer.kept.width !== Math.max(1, Math.round(width)) || layer.kept.height !== Math.max(1, Math.round(height)) ||
                         (atBase && !same(layer.keptTint, tint)) || compositesChanged(layer))) {
        release(layer.kept);
        layer.kept = null;
      }
      if (layer.kept) {
        if (layer.composite) keepComposite(layer, layer.kept, width, height, false);
        if (shows) put(withLooks({ texture: layer.kept.texture }, layer), place, finished, how, mesh);
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
        ctx.surface = { target: inside, copy: null, width: nominal[0], height: nominal[1], left: -nominal[0] / 2, bottom: -nominal[1] / 2 };
        gl.bindFramebuffer(gl.FRAMEBUFFER, inside.framebuffer);
        gl.viewport(0, 0, inside.width, inside.height);
        gl.disable(gl.BLEND);
        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT);
        if (layer.copiesBackground && grabProgram) {
          gl.useProgram(grabProgram.program);
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, onto.target.texture);
          gl.uniform1i(grabProgram.uniforms.u_Texture.location, 0);
          gl.uniformMatrix3fv(grabProgram.uniforms.u_Place.location, false, place);
          gl.bindVertexArray(passShape);
          gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        }
        layer.held.forEach(function (child) {
          gl.bindFramebuffer(gl.FRAMEBUFFER, inside.framebuffer);
          gl.viewport(0, 0, inside.width, inside.height);
          child.draw();
        });
        if (ctx.surface.copy) release(ctx.surface.copy);
        ctx.surface = onto;
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

      // In the world the last pass of the last effect is drawn straight onto the scene, through
      // the layer's place, at the scene's pixels, as Wallpaper Engine draws it: 3662790108's
      // orbits are drawn by effects on layers of 10 by 10 in lines a pixel wide over the
      // screen.
      var last = null;
      effects.forEach(function (effect) {
        if (effect.passes.length) last = effect.passes[effect.passes.length - 1];
      });
      var straight = world && shows && typeof how === 'string' && !mesh && !layer.composite && last && !last.copy && !last.target &&
                     last.program && last.program.uniforms.g_ModelViewProjectionMatrix
                   ? { onto: onto, place: place, how: how, tests: place.tests } : null;
      if (atBase && !same(tint, [1, 1, 1, 1])) {
        var tinted = next();
        gl.bindFramebuffer(gl.FRAMEBUFFER, tinted.framebuffer);
        gl.viewport(0, 0, tinted.width, tinted.height);
        put(source, FILL, tint, 'normal');
        held = tinted;
        source = { texture: tinted.texture, resolution: resolution };
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
          if (wanted.width > 0 && wanted.height > 0) {
            wide = nominalWide = wanted.width;
            high = nominalHigh = wanted.height;
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
          if (wanted.repeats && !target.repeats) {
            target.repeats = true;
            gl.bindTexture(gl.TEXTURE_2D, target.texture);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
            target.texture.looks = { wrapS: gl.REPEAT, wrapT: gl.REPEAT, smooth: looksOf(target.texture).smooth };
          }
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
          if (straight && pass === last) {
            drawPass(pass, target, pass.inputs.map(input), layer, onScreen, straight);
            return;
          }
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

      if (layer.composite) keepComposite(layer, previous, width, height, true);
      gl.bindFramebuffer(gl.FRAMEBUFFER, onto.target.framebuffer);
      gl.viewport(0, 0, onto.target.width, onto.target.height);
      if (shows && !straight) put(withLooks({ texture: previous.texture }, layer), place, finished, how, mesh);
      // What holds other layers is another picture whenever one of them is.
      if (!layer.moving && !layer.holds && held && ctx.loading === 0 && !straight) {
        layer.kept = held;
        layer.keptTint = tint.slice();
        layer.keptAt = ctx.frames;
        release(spare[0] === held ? spare[1] : spare[0]);
      } else {
        spare.forEach(release);
      }
    }

    // Whether a layer that takes others' finished pictures in its effects must be drawn anew:
    // one of them was made anew since it was kept (2938612768's bar takes the scene under a
    // hidden layer, and kept from the first frame it showed a dark box ever after). Also when
    // made in the very frame it was kept, as a layer drawn later in the scene's order makes it.
    function compositesChanged(layer) {
      return !!layer.takesComposites && layer.takesComposites.some(function (composite) {
        return composite.changed !== undefined && composite.changed >= layer.keptAt;
      });
    }

    // The finished picture of a layer copied into one of its own, which no other drawing
    // takes, for those that take it by name; marked as made in this frame, and, if `fresh`
    // (not from what the layer kept), as changed.
    function keepComposite(layer, made, width, height, fresh) {
      var wide = Math.max(1, Math.round(width)), high = Math.max(1, Math.round(height));
      var target = layer.composite.target;
      if (!target || target.width !== wide || target.height !== high) {
        if (target) releaseRepeated(target);
        target = layer.composite.target = acquire(wide, high);
        fresh = true;
        // Taken by a model, it repeats past its edges unless the layer says not, as a picture
        // does (3737268876's eyes reach past them).
        if (!layer.clampsUvs) {
          gl.bindTexture(gl.TEXTURE_2D, target.texture);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
          target.texture.looks = { wrapS: gl.REPEAT, wrapT: gl.REPEAT, smooth: looksOf(target.texture).smooth };
        }
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
      gl.viewport(0, 0, target.width, target.height);
      gl.disable(gl.BLEND);
      if (straightProgram) {
        gl.useProgram(straightProgram.program);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, made.texture);
        gl.uniform1i(straightProgram.uniforms.u_Texture.location, 0);
        gl.bindVertexArray(passShape);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      }
      layer.composite.layers[0] = { texture: target.texture, width: target.width, height: target.height };
      layer.composite.width = target.width;
      layer.composite.height = target.height;
      layer.composite.frame = ctx.frames;
      if (fresh) layer.composite.changed = ctx.frames;
      gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.surface.target.framebuffer);
      gl.viewport(0, 0, ctx.surface.target.width, ctx.surface.target.height);
    }

    // A target given back to the others as they had it: ending at its edges.
    function releaseRepeated(target) {
      gl.bindTexture(gl.TEXTURE_2D, target.texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      target.texture.looks = { wrapS: gl.CLAMP_TO_EDGE, wrapT: gl.CLAMP_TO_EDGE, smooth: looksOf(target.texture).smooth };
      release(target);
    }

    // A layer whose finished picture was made ahead in this frame, put on the scene from it.
    function drawComposite(layer, matrix, stands) {
      var state = layer.state, bright = layer.brightness;
      var alpha = stands.alpha * (layer.materialAlpha !== undefined ? layer.materialAlpha : 1);
      var tint = layer.tintedAtBase ? [1, 1, 1, 1]
               : layer.ownColor ? [1, 1, 1, alpha] : [state.color[0] * bright, state.color[1] * bright, state.color[2] * bright, alpha];
      var how = layer.blendMode > 0 && layer.blendMode !== 9 ? layer.blendMode :
                (layer.blendMode === 9 || layer.blending === 'additive' ? 'additive' : (layer.blending === 'normal' ? 'normal' : 'translucent'));
      var mesh = layer.puppet || null;
      var world = layer.inWorld && !layer.holds && ctx.surface.target === ctx.sceneTarget;
      var place = world ? worldPlaceOf(matrix, layer.size, layer.testsDepth) : placeOf(matrix, layer.size);
      if (mesh) {
        mesh.pose(ctx.time, matrix);
        place = world ? worldPlaceOf(matrix, [1, 1], layer.testsDepth) : placeOf(matrix, [1, 1]);
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER, ctx.surface.target.framebuffer);
      gl.viewport(0, 0, ctx.surface.target.width, ctx.surface.target.height);
      put(withLooks({ texture: layer.composite.target.texture }, layer), place, tint, how, mesh);
    }

    return { buildText: buildText, shifted: shifted, drawImage: drawImage, releaseRepeated: releaseRepeated };
  }

