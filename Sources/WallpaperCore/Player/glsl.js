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
    var result = { combos: {}, uniforms: {}, types: {}, switches: {} };
    source.replace(/\r\n?/g, '\n').split('\n').forEach(function (line) {
      var combo = /^\s*\/\/\s*\[\s*(?:COMBO|COMBO_OFF|OFF_COMBO)\s*\]\s*(\{.*\})\s*$/.exec(line);
      if (combo) {
        try {
          var declared = loose(combo[1]);
          if (declared && declared.combo) result.combos[declared.combo] = number(declared['default'], 0);
          if (declared && declared.combo && declared.material && /\[\s*COMBO\s*\]/.test(line)) result.switches[declared.combo] = declared;
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
    var rows = source.split('\n');
    var row = line > 0 ? rows[line - 1] : undefined;
    // A part of a value handed over that its declaration here is too small to have, as
    // Direct3D allows: the value is taken whole, as four numbers.
    if (/vector swizzle selection out of range/.test(message) && row !== undefined) {
      var picked = /\b(\w+)\s*\.\s*[xyzwrgba]+\b/g, found, widened = source;
      while ((found = picked.exec(row))) {
        var declared = new RegExp('^([ \\t]*(?:flat[ \\t]+|smooth[ \\t]+)?(?:in|varying)[ \\t]+(?:(?:highp|mediump|lowp)[ \\t]+)?)(float|vec[23])([ \\t]+' + found[1] + '[ \\t]*;)', 'm');
        if (declared.test(widened)) return widened.replace(declared, '$1vec4$3');
      }
      return null;
    }
    // A constant worked out from uniforms, which GLSL will not have at the top of a shader:
    // the name stands for the expression wherever it is used.
    if (/global const initializers must be constant/.test(message) && row !== undefined) {
      var constant = /^[ \t]*const[ \t]+(?:(?:highp|mediump|lowp)[ \t]+)?\w+[ \t]+(\w+)[ \t]*=[ \t]*(.+?);[ \t]*$/.exec(row);
      if (!constant) return null;
      rows[line - 1] = '#define ' + constant[1] + ' (' + constant[2] + ')';
      return rows.join('\n');
    }
    // A constant inside a function given what is known only as it runs, as Direct3D allows:
    // a plain value.
    // Where the point is, read in a fragment shader as a vertex shader writes it: Direct3D
    // gives a pixel shader the pixel's place under that name (3819066109's light pillar).
    if (/'gl_Position' : undeclared identifier/.test(message) && /\bgl_Position\b/.test(source)) {
      return source.replace(/\bgl_Position\b/g, 'gl_FragCoord');
    }
    // A function of the shader's own named as one of GLSL's: in Direct3D the name is free
    // (3819066109's `fract`, Direct3D's own being `frac`). The shader's is renamed where the
    // shader calls it; the shared header's names that stand for GLSL's are left as they are.
    var builtin = /'redefinition of built-in function'/.test(message) && row !== undefined
      ? /\b(?:void|float|int|bool|vec[234]|ivec[234]|mat[234])\s+(\w+)\s*\(/.exec(row) : null;
    if (builtin) {
      var named = new RegExp('\\b' + builtin[1] + '\\s*\\(', 'g');
      return rows.map(function (each) {
        return /^\s*#/.test(each) ? each : each.replace(named, 'wallaero_' + builtin[1] + '(');
      }).join('\n');
    }
    // A function said to give back a constant, as Direct3D lets one be (3819066109's
    // `const float fract(float x)`): what it gives back is a value all the same.
    if (/no qualifiers allowed for function return/.test(message) && row !== undefined && /\bconst\s+\w+\s+\w+\s*\(/.test(row)) {
      rows[line - 1] = row.replace(/\bconst\s+(?=\w+\s+\w+\s*\()/, '');
      return rows.join('\n');
    }
    if (/'non-constant initializer' : not supported/.test(message) && row !== undefined && /\bconst\b/.test(row)) {
      rows[line - 1] = row.replace(/\bconst\s+/, '');
      return rows.join('\n');
    }
    // A name the shared header already gives a value: the shader's own takes its place.
    var redefined = /'#define' : Macro redefined[^:]*: (\w+)/.exec(message);
    if (redefined && row !== undefined) {
      rows[line - 1] = '#undef ' + redefined[1] + '\n' + row;
      return rows.join('\n');
    }
    // A texture read at four numbers, as Direct3D reads it at the first two.
    if (/'texture' : no matching overloaded function found/.test(message) && row !== undefined) {
      var mended = row.replace(/\btexture\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)/g, function (all, sampler, at) {
        return new RegExp('\\bvec4[ \\t]+' + at + '\\b').test(source) ? 'texture(' + sampler + ', ' + at + '.xy)' : all;
      });
      if (mended !== row) {
        rows[line - 1] = mended;
        return rows.join('\n');
      }
    }
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
      // The copy is declared on a line of its own: where the two shaders do not agree on what
      // is handed over, the line that takes it in is written anew (3701796900's sine wave).
      return source.slice(0, upTo) + '\n' + given[1] + ' ' + own + ';' + rest.slice(0, at) + ' ' + own + ' = ' + handed[1] + ';' + rest.slice(at);
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
    if (call && !LENIENT[call[1]]) {
      // One the shader or a header writes itself, `vec2 rotateVec2(vec2 v, float r)`: on that
      // line, each value given it that may be larger is cut to what the function takes.
      var heading = new RegExp('\\b(?:void|float|vec[234])\\s+' + call[1] + '\\s*\\(([^)]*)\\)\\s*\\{').exec(source);
      if (!heading || !(line > 0) || row === undefined) return null;
      var takes = heading[1].split(',').map(function (each) {
        var typed = /\b(float|vec[234])\s+\w+\s*$/.exec(each.trim());
        return typed ? typed[1] : null;
      });
      var sizes = declaredIn(source);
      var opening = new RegExp('\\b' + call[1] + '\\s*\\(', 'g'), found, cutRow = row;
      while ((found = opening.exec(cutRow))) {
        var given = [], from = found.index + found[0].length, depth = 0, at = from;
        for (; at < cutRow.length; at++) {
          var letter = cutRow.charAt(at);
          if (letter === '(' || letter === '[') depth++;
          else if ((letter === ')' || letter === ']') && depth > 0) depth--;
          else if ((letter === ',' || letter === ')') && depth === 0) {
            given.push(cutRow.slice(from, at));
            from = at + 1;
            if (letter === ')') break;
          }
        }
        if (at >= cutRow.length || given.length !== takes.length) continue;
        var cut = given.map(function (value, index) {
          var type = takes[index], size = type === 'float' ? 1 : (type ? Number(type.charAt(3)) : 0);
          var has = sizeWritten(value, sizes);
          return !type || (has !== 0 && has <= size) ? value : value.replace(/^(\s*)([\s\S]*?)(\s*)$/, '$1' + type + '($2)$3');
        }).join(',');
        cutRow = cutRow.slice(0, found.index + found[0].length) + cut + cutRow.slice(at);
        opening.lastIndex = found.index + found[0].length + cut.length;
      }
      if (cutRow === row) return null;
      rows[line - 1] = cutRow;
      return rows.join('\n');
    }
    if (call) {
      if (source.indexOf('wallaero_' + call[1] + '(') >= 0) return null;
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
      if (!best) {
        // The larger side is more than one value — `v_TexCoord * 2.0 - 1.0 - center`, with
        // `center` a vec2 — and Direct3D cuts it as a whole. Cutting each name of that size
        // on the line, where it is taken whole, comes to the same, as the signs work part by part.
        if (typeof left !== 'number' || typeof right !== 'number' || left === 1 || right === 1) return null;
        var larger = Math.max(left, right), parts = '.' + 'xyzw'.slice(0, Math.min(left, right));
        var trimmed = text.replace(/\b\w+\b(?!\s*[.\[(])/g, function (name, place) {
          return declared[name] === larger && text.charAt(place - 1) !== '.' ? name + parts : name;
        });
        if (trimmed === text) return null;
        lines[line - 1] = trimmed;
        return lines.join('\n');
      }
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
    // A shader that writes one of those functions itself keeps its own: `float log10(float x)`.
    var written = pieces.join('\n');
    ['mul', 'saturate', 'fmod', 'log10'].forEach(function (name) {
      if (new RegExp('\\b(?:float|vec[234]|mat[234])\\s+' + name + '\\s*\\(').test(written)) head.push('#undef ' + name);
    });
    return head.concat(pieces, tail).join('\n') + '\n';
  }

