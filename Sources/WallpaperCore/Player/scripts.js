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
            if (value === undefined || value === null) return said.value === undefined && said.options && said.options[0] ? said.options[0].value : said.value;
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
                'mediaStatusChanged', 'mediaPropertiesChanged', 'mediaThumbnailChanged', 'mediaPlaybackChanged', 'mediaTimelineChanged',
                'animationEvent'];
  var KEPT_AWAY = ['window', 'document', 'self', 'top', 'parent', 'frames', 'opener', 'fetch', 'XMLHttpRequest',
                   'WebSocket', 'EventSource', 'Worker', 'navigator', 'location', 'history', 'indexedDB', 'sessionStorage',
                   'caches', 'eval', 'Function', 'open', 'postMessage', 'webkit'];
  function scriptBody(source) {
    // A script may come squeezed onto one line, its statements one after another with no
    // room between them (`'use strict';import*as WEMath from'WEMath';…;export function …`,
    // 3811154012): what starts a statement may follow a line's start, `;`, `{` or `}`.
    var text = String(source).replace(/\r\n?/g, '\n')
      .replace(/(^|[;{}])\s*import\s*\*\s*as\s+(\w+)\s+from\s*['"](\w+)['"]\s*;?/gm, function (whole, before, name, module) {
        return before + 'var ' + name + ' = __modules.' + module + ' || {};';
      })
      .replace(/(^|[;{}])\s*import\s*\{([^}]*)\}\s*from\s*['"](\w+)['"]\s*;?/gm, function (whole, before, list, module) {
        return before + 'var {' + list.replace(/\s+as\s+/g, ': ') + '} = __modules.' + module + ' || {};';
      })
      .replace(/(^|[;{}])(\s*)export\s+(default\s+)?(?=function|var|let|const|class|async)/gm, '$1$2')
      .replace(/(^|[;{}])\s*export\s*\{[^}]*\}\s*;?/gm, '$1');
    var tail = '\n;return {' + EVENTS.map(function (name) {
      return name + ': typeof ' + name + ' === "function" ? ' + name + ' : null';
    }).join(', ') + '};';
    // In Wallpaper Engine the scripts of a scene run in one context: what one puts on
    // `globalThis` another reads, there or by its bare name (3800262433's lights and
    // brightness, `globalThis.stageBri` here, `personBri` there). Here each scene has one
    // such object of its own, without the page's names, seen through `with`.
    // Only in a scene that uses it: names looked up through `with` cost scripts their speed.
    var open = SCRIPTS_SHARE_GLOBAL ? 'with (globalThis) { ' : '', close = SCRIPTS_SHARE_GLOBAL ? ' }' : '';
    return open + 'return (function () {\n"use strict";\n' + text + tail + '\n}).call(undefined);' + close;
  }
  var SCRIPT_GLOBAL = Object.create(null);
  var SCRIPTS_SHARE_GLOBAL = false;
  function compileScript(source, names, values, own) {
    return Function.apply(null, names.concat(['__modules', 'globalThis'], KEPT_AWAY, [scriptBody(source)]))
      .apply(null, values.concat([MODULES, own || SCRIPT_GLOBAL]));
  }

  // The line of the script's own text an error stands on: what `Function` and `scriptBody`
  // put in front of it comes to four lines.
  function scriptLine(error) {
    return typeof error.line === 'number' ? Math.max(1, error.line - 4) : 0;
  }

  // For the editor: whether a script can be read at all, without running any of it.
  function checkScript(source) {
    try {
      Function.apply(null, ['__modules', 'globalThis'].concat(KEPT_AWAY, [scriptBody(source)]));
      return null;
    } catch (error) {
      return { message: error.message, line: scriptLine(error) };
    }
  }

  // For the editor: the settings a script declares. Its text is run with nothing of a scene
  // to touch, which is all it can get at outside of its functions.
  function scriptDeclares(source) {
    var found = [];
    var builder = new Proxy({}, {
      get: function (object, name) {
        if (name === 'finish') return function () { return {}; };
        return function (said) {
          if (said && said.name !== undefined) {
            var plainly = {};
            Object.keys(said).forEach(function (part) { plainly[part] = said[part]; });
            plainly.kind = String(name).replace(/^add/, '').toLowerCase();
            if (plainly.value && typeof plainly.value === 'object' && 'x' in plainly.value) {
              plainly.value = plainly.value.x + ' ' + plainly.value.y + ' ' + plainly.value.z;
            }
            found.push(plainly);
          }
          return builder;
        };
      }
    });
    function nothing() { return new Proxy(function () {}, { get: function (object, name) { return typeof name === 'string' ? nothing() : undefined; }, apply: function () { return nothing(); } }); }
    try {
      compileScript(source,
        ['engine', 'thisScene', 'thisLayer', 'thisObject', 'input', 'shared', 'console', 'localStorage', 'renderContext',
         'createScriptProperties', 'Vec2', 'Vec3', 'Vec4', 'Mat3', 'Mat4'],
        [nothing(), nothing(), nothing(), nothing(), nothing(), {}, nothing(), nothing(), nothing(),
         function () { return builder; }, Vec2, Vec3, Vec4, Mat3, Mat4], Object.create(null));
    } catch (error) {}
    return found;
  }

