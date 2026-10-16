/// The script the editor adds to the scene's page in its preview. It lets layers be picked,
/// dragged, resized and turned with the mouse — and so the objects of one of Wallpaper Engine's
/// scenes in the background, which the scene's player places — and reports each change to the
/// app, which owns the scene. It is never written into the wallpaper itself.
enum SceneEditorScript {
    static let source = #"""
    (function () {
      'use strict';
      if (window.wallaeroEditor) return;

      function post(message) { window.webkit.messageHandlers.wallaeroEditor.postMessage(message); }
      function make(tag, className) { var e = document.createElement(tag); e.className = className; return e; }
      function round(value) { return Math.round(value * 100) / 100; }

      var layersHost = document.getElementById('wallaero-layers');
      var sheet = document.createElement('style');
      sheet.textContent =
        '.wallaero-layer { cursor: move; pointer-events: auto; }' +
        '.wallaero-layer * { pointer-events: none; }' +
        // The selection is drawn in the Mac's accent color, which the app hands over (`setAccent`).
        '.wallaero-layer:hover { outline: 1px dashed var(--wallaero-accent, #0a84ff); }' +
        '#wallaero-editor { position: fixed; left: 0; top: 0; width: 100%; height: 100%; pointer-events: none; z-index: 2147483000; }' +
        '.wallaero-frame { position: absolute; box-sizing: border-box; border: 1.5px solid var(--wallaero-accent, #0a84ff); display: none; }' +
        '.wallaero-handle { position: absolute; width: 10px; height: 10px; margin: -5px 0 0 -5px; box-sizing: border-box;' +
        '  background: #fff; border: 1.5px solid var(--wallaero-accent, #0a84ff); border-radius: 2px; pointer-events: auto; }' +
        '.wallaero-handle[data-handle=nw] { left: 0; top: 0; cursor: nwse-resize; }' +
        '.wallaero-handle[data-handle=ne] { left: 100%; top: 0; cursor: nesw-resize; }' +
        '.wallaero-handle[data-handle=sw] { left: 0; top: 100%; cursor: nesw-resize; }' +
        '.wallaero-handle[data-handle=se] { left: 100%; top: 100%; cursor: nwse-resize; }' +
        '.wallaero-handle[data-handle=e] { left: 100%; top: 50%; cursor: ew-resize; }' +
        '.wallaero-handle[data-handle=rotate] { left: 50%; top: -24px; border-radius: 50%; cursor: grab; }' +
        // An object of the scene with no size of its own — particles, a sound — is marked where
        // it is, and only moved; one that is hidden has its frame dashed.
        '.wallaero-frame.point { border-radius: 50%; }' +
        '.wallaero-frame.point .wallaero-handle { display: none !important; }' +
        '.wallaero-frame.hidden { border-style: dashed; }' +
        '.wallaero-guide { position: absolute; background: #ff453a; display: none; }' +
        '.wallaero-guide.vertical { left: 50%; top: 0; width: 1px; height: 100%; }' +
        '.wallaero-guide.horizontal { left: 0; top: 50%; width: 100%; height: 1px; }';
      document.head.appendChild(sheet);

      var overlay = make('div', '');
      overlay.id = 'wallaero-editor';
      var guideX = make('div', 'wallaero-guide vertical');
      var guideY = make('div', 'wallaero-guide horizontal');
      var frame = make('div', 'wallaero-frame');
      ['nw', 'ne', 'sw', 'se', 'e', 'rotate'].forEach(function (name) {
        var handle = make('div', 'wallaero-handle');
        handle.dataset.handle = name;
        frame.appendChild(handle);
      });
      overlay.appendChild(guideX);
      overlay.appendChild(guideY);
      overlay.appendChild(frame);
      document.body.appendChild(overlay);

      var selected = null;
      var object = null;   // the selected object of Wallpaper Engine's scene, by its number
      var described = {};  // that scene's objects as its player describes them, by number
      var following = false;
      var drag = null;
      var pending = null;

      function box(id) { return id ? layersHost.querySelector('.wallaero-layer[data-layer="' + id + '"]') : null; }
      function data(id) {
        var list = (window.wallaero.scene && window.wallaero.scene.layers) || [];
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return null;
      }
      function sized(kind) { return kind === 'shape' || kind === 'code'; }

      function placeFrame() {
        if (object !== null) {
          placeObjectFrame();
          return;
        }
        frame.classList.remove('point', 'hidden');
        var element = box(selected);
        if (!element || element.style.display === 'none') {
          frame.style.display = 'none';
          return;
        }
        frame.style.display = 'block';
        frame.style.left = element.style.left;
        frame.style.top = element.style.top;
        frame.style.width = element.offsetWidth + 'px';
        frame.style.height = element.offsetHeight + 'px';
        frame.style.transform = element.style.transform;
        var layer = data(selected);
        // Only text is worth narrowing on its own; the rest keeps the corner handles.
        frame.querySelector('[data-handle=e]').style.display = layer && layer.kind === 'text' ? 'block' : 'none';
      }

      function select(id, tellApp) {
        selected = id || null;
        object = null;
        placeFrame();
        if (tellApp) post({ type: 'select', id: selected });
      }

      // Tells the app of a change once per frame, however often it comes.
      function report(type, id, patch) {
        if (!pending) {
          pending = {};
          requestAnimationFrame(function () {
            var waiting = pending;
            pending = null;
            for (var name in waiting) post(waiting[name]);
          });
        }
        var message = pending[type + ' ' + id] || (pending[type + ' ' + id] = { type: type, id: id, patch: {} });
        for (var key in patch) message.patch[key] = patch[key];
      }

      // Moves the layer on the page right away, and tells the app once per frame.
      function apply(id, patch) {
        var layer = data(id), element = box(id);
        if (!layer || !element) return;
        for (var key in patch) layer[key] = patch[key];
        element.style.left = layer.x + '%';
        element.style.top = layer.y + '%';
        element.style.width = layer.width + 'vw';
        if (sized(layer.kind)) element.style.height = layer.height + 'vh';
        element.style.transform = 'translate(-50%, -50%) rotate(' + (layer.rotation || 0) + 'deg)';
        if (layer.kind === 'text' && patch.fontSize !== undefined) element.firstElementChild.style.fontSize = layer.fontSize + 'vh';
        placeFrame();
        report('change', id, patch);
      }

      // --- The objects of Wallpaper Engine's scene in the background ---------------------

      function engine() {
        return window.WallaeroEngine && window.WallaeroEngine.describe ? window.WallaeroEngine : null;
      }

      // Tells the app what the scene has, once its player has it.
      function describeEngine() {
        var player = engine();
        var scene = player && player.describe();
        if (!scene) return;
        described = {};
        scene.objects.forEach(function (each) { described[String(each.id)] = each; });
        post({ type: 'engine', scene: JSON.stringify(scene) });
        placeFrame();
      }

      function changesOf() {
        var scene = window.wallaero.scene || {};
        var background = scene.background || (scene.background = {});
        return background.engine || (background.engine = {});
      }

      // An object's value as it is now: as the editor has changed it, else as the scene has it.
      function valueOf(id, name) {
        var list = changesOf().objects || [];
        for (var i = 0; i < list.length; i++) {
          if (list[i].id === id && list[i][name] !== undefined && list[i][name] !== null) return list[i][name];
        }
        var about = described[String(id)];
        return about ? about[name] : 0;
      }

      // Changes an object in the scene the page shows and has it shown at once; the app is
      // told once per frame.
      function change(id, patch) {
        var changes = changesOf();
        var list = changes.objects || (changes.objects = []);
        var own = list.filter(function (each) { return each.id === id; })[0];
        if (!own) list.push(own = { id: id });
        for (var name in patch) own[name] = patch[name];
        window.wallaero.updateEngine();
        placeFrame();
        report('object-change', id, patch);
      }

      // The frame around the selected object, where the player says it is.
      function placeObjectFrame() {
        var player = engine();
        var outline = player && player.outline(object);
        if (!outline) {
          frame.style.display = 'none';
          return;
        }
        var corners = outline.corners;
        var width = 14, height = 14, turn = 0;
        if (corners) {
          width = Math.max(4, Math.hypot(corners[1][0] - corners[0][0], corners[1][1] - corners[0][1]));
          height = Math.max(4, Math.hypot(corners[2][0] - corners[1][0], corners[2][1] - corners[1][1]));
          turn = Math.atan2(corners[1][1] - corners[0][1], corners[1][0] - corners[0][0]) * 180 / Math.PI;
        }
        frame.style.display = 'block';
        frame.style.left = outline.middle[0] + 'px';
        frame.style.top = outline.middle[1] + 'px';
        frame.style.width = width + 'px';
        frame.style.height = height + 'px';
        frame.style.transform = 'translate(-50%, -50%) rotate(' + turn + 'deg)';
        frame.classList.toggle('point', !corners);
        frame.classList.toggle('hidden', !outline.visible);
        frame.querySelector('[data-handle=e]').style.display = 'none';
      }

      // The scene moves as it plays — with the pointer, by its scripts — and the frame with it.
      function followObject() {
        if (object === null) {
          following = false;
          return;
        }
        placeObjectFrame();
        requestAnimationFrame(followObject);
      }

      function selectObject(id, tellApp) {
        selected = null;
        object = id === undefined ? null : id;
        placeFrame();
        if (object !== null && !following) {
          following = true;
          requestAnimationFrame(followObject);
        }
        if (tellApp) post({ type: 'select-object', id: object });
      }

      // Whether the pointer is on the mark of a selected object that has no size of its own.
      function onMark(event) {
        if (object === null || !frame.classList.contains('point') || frame.style.display === 'none') return false;
        var mark = frame.getBoundingClientRect();
        return Math.abs(event.clientX - (mark.left + mark.width / 2)) <= 12 && Math.abs(event.clientY - (mark.top + mark.height / 2)) <= 12;
      }

      function startObjectDrag(event, mode) {
        var player = engine();
        var outline = player && player.outline(object);
        if (!outline) return;
        event.preventDefault();
        drag = {
          object: object, mode: mode, pointerX: event.clientX, pointerY: event.clientY,
          place: player.placeAt(object, event.clientX, event.clientY), middle: outline.middle,
          x: valueOf(object, 'x'), y: valueOf(object, 'y'), scaleX: valueOf(object, 'scaleX'), scaleY: valueOf(object, 'scaleY'),
          rotation: valueOf(object, 'rotation')
        };
      }

      function dragObject(event) {
        var player = engine();
        if (!player) return;
        var patch = {};
        var middleX = drag.middle[0], middleY = drag.middle[1];
        if (drag.mode === 'move') {
          var place = player.placeAt(drag.object, event.clientX, event.clientY);
          patch.x = round(drag.x + place[0] - drag.place[0]);
          patch.y = round(drag.y + place[1] - drag.place[1]);
        } else if (drag.mode === 'rotate') {
          var from = Math.atan2(drag.pointerY - middleY, drag.pointerX - middleX);
          var to = Math.atan2(event.clientY - middleY, event.clientX - middleX);
          var angle = drag.rotation + (to - from) * 180 / Math.PI;
          if (event.shiftKey) {
            angle = Math.round(angle / 15) * 15;
          } else {
            var nearest = Math.round(angle / 90) * 90;
            if (Math.abs(angle - nearest) < 3) angle = nearest;
          }
          patch.rotation = round(((angle + 180) % 360 + 360) % 360 - 180);
        } else {
          // From the middle, as far as the pointer is now against where it took hold.
          var before = Math.hypot(drag.pointerX - middleX, drag.pointerY - middleY);
          var by = before > 1 ? Math.max(0.01, Math.hypot(event.clientX - middleX, event.clientY - middleY) / before) : 1;
          patch.scaleX = Math.round(drag.scaleX * by * 1000) / 1000;
          patch.scaleY = Math.round(drag.scaleY * by * 1000) / 1000;
        }
        change(drag.object, patch);
      }

      document.addEventListener('pointerdown', function (event) {
        if (event.button !== 0) return;
        var handle = event.target.closest ? event.target.closest('.wallaero-handle') : null;
        if (object !== null && (handle || onMark(event))) {
          startObjectDrag(event, handle ? handle.dataset.handle : 'move');
          return;
        }
        var element = handle ? box(selected) : (event.target.closest ? event.target.closest('.wallaero-layer') : null);
        if (!element) {
          // On the background: an object of the scene there, if it is one of Wallpaper
          // Engine's, or the background itself.
          var player = engine();
          var hit = player ? player.hit(event.clientX, event.clientY) : null;
          if (hit === null || hit === undefined) {
            select(null, true);
            return;
          }
          if (hit !== object) selectObject(hit, true);
          startObjectDrag(event, 'move');
          return;
        }
        var id = element.dataset.layer;
        if (id !== selected) select(id, true);
        var layer = data(id);
        if (!layer) return;
        event.preventDefault();
        drag = {
          id: id,
          mode: handle ? handle.dataset.handle : 'move',
          kind: layer.kind,
          pointerX: event.clientX,
          pointerY: event.clientY,
          x: layer.x, y: layer.y, width: layer.width, height: layer.height,
          rotation: layer.rotation || 0, fontSize: layer.fontSize,
          halfWidth: Math.max(1, element.offsetWidth / 2),
          halfHeight: Math.max(1, element.offsetHeight / 2)
        };
      }, true);

      window.addEventListener('pointermove', function (event) {
        if (!drag) return;
        if (drag.object !== undefined) {
          dragObject(event);
          return;
        }
        var width = window.innerWidth, height = window.innerHeight;
        var centerX = drag.x / 100 * width, centerY = drag.y / 100 * height;
        var patch = {};
        if (drag.mode === 'move') {
          var x = drag.x + (event.clientX - drag.pointerX) / width * 100;
          var y = drag.y + (event.clientY - drag.pointerY) / height * 100;
          // The middle of the screen pulls a little, with a line to show it.
          var snapX = Math.abs(x - 50) < 0.8, snapY = Math.abs(y - 50) < 0.8;
          guideX.style.display = snapX ? 'block' : 'none';
          guideY.style.display = snapY ? 'block' : 'none';
          patch.x = snapX ? 50 : round(x);
          patch.y = snapY ? 50 : round(y);
        } else if (drag.mode === 'rotate') {
          var angle = Math.atan2(event.clientY - centerY, event.clientX - centerX) * 180 / Math.PI + 90;
          if (event.shiftKey) {
            angle = Math.round(angle / 15) * 15;
          } else {
            var nearest = Math.round(angle / 90) * 90;
            if (Math.abs(angle - nearest) < 3) angle = nearest; // upright is easy to hit
          }
          angle = ((angle + 180) % 360 + 360) % 360 - 180;
          patch.rotation = round(angle);
        } else {
          // The pointer in the layer's own axes, so a turned layer resizes along its sides.
          var radians = -drag.rotation * Math.PI / 180;
          var px = event.clientX - centerX, py = event.clientY - centerY;
          var alongX = Math.abs(px * Math.cos(radians) - py * Math.sin(radians));
          var alongY = Math.abs(px * Math.sin(radians) + py * Math.cos(radians));
          if (drag.mode === 'e') {
            patch.width = round(Math.max(1, alongX * 2 / width * 100));
          } else if (sized(drag.kind) && !event.shiftKey) {
            patch.width = round(Math.max(1, alongX * 2 / width * 100));
            patch.height = round(Math.max(1, alongY * 2 / height * 100));
          } else {
            var scale = Math.max(0.05, Math.max(alongX / drag.halfWidth, alongY / drag.halfHeight));
            patch.width = round(Math.max(1, drag.width * scale));
            if (sized(drag.kind)) patch.height = round(Math.max(1, drag.height * scale));
            if (drag.kind === 'text') patch.fontSize = round(Math.max(0.5, drag.fontSize * scale));
          }
        }
        apply(drag.id, patch);
      });

      function endDrag() {
        if (!drag) return;
        drag = null;
        guideX.style.display = guideY.style.display = 'none';
        // After the frame that carries the last change.
        requestAnimationFrame(function () { post({ type: 'commit' }); });
      }
      window.addEventListener('pointerup', endDrag);
      window.addEventListener('pointercancel', endDrag);

      document.addEventListener('keydown', function (event) {
        if (object !== null) {
          // A pixel of the scene at a time, or ten; the scene counts upwards.
          var by = event.shiftKey ? 10 : 1, moved = null;
          if (event.key === 'ArrowLeft') moved = { x: round(valueOf(object, 'x') - by) };
          else if (event.key === 'ArrowRight') moved = { x: round(valueOf(object, 'x') + by) };
          else if (event.key === 'ArrowUp') moved = { y: round(valueOf(object, 'y') + by) };
          else if (event.key === 'ArrowDown') moved = { y: round(valueOf(object, 'y') - by) };
          else return;
          event.preventDefault();
          change(object, moved);
          return;
        }
        if (!selected) return;
        var layer = data(selected);
        if (!layer) return;
        var step = event.shiftKey ? 1 : 0.1;
        var patch = null;
        if (event.key === 'ArrowLeft') patch = { x: round(layer.x - step) };
        else if (event.key === 'ArrowRight') patch = { x: round(layer.x + step) };
        else if (event.key === 'ArrowUp') patch = { y: round(layer.y - step) };
        else if (event.key === 'ArrowDown') patch = { y: round(layer.y + step) };
        else if (event.key === 'Backspace' || event.key === 'Delete') post({ type: 'delete', id: selected });
        else return;
        event.preventDefault();
        if (patch) apply(selected, patch);
      });

      document.addEventListener('contextmenu', function (event) { event.preventDefault(); });
      document.addEventListener('wallaero:scene', placeFrame);
      window.addEventListener('resize', placeFrame);
      // Text can change size on its own: a clock ticking over, a font arriving late.
      setInterval(placeFrame, 500);

      document.addEventListener('wallaero:engine', function () { setTimeout(describeEngine, 0); });

      window.wallaeroEditor = {
        select: function (id) { select(id, false); },
        selectObject: function (id) { selectObject(id, false); },
        // The scene changed in the editor: what the player has of it is read again.
        refresh: describeEngine,
        setAccent: function (color) { document.documentElement.style.setProperty('--wallaero-accent', color); }
      };
      post({ type: 'ready' });
      describeEngine();
    })();
    """#
}
