  // The mouse: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeMouse(ctx) {
    var seenPart = ctx.seenPart, sceneAt = ctx.sceneAt, shownAt = ctx.shownAt, changed = ctx.changed, tellPointer = ctx.tellPointer, eye = ctx.eye, wake = ctx.wake;
    // --- The mouse --------------------------------------------------------------

    // Where the pointer is over the scene, from 0 to 1 from its top left corner: the scene is
    // fitted to the screen by the page, cut or with bars.
    function point(event) {
      var shown = shownAt();
      ctx.pointer = [(event.clientX - shown.left) / shown.width, (event.clientY - shown.top) / shown.height];
      // Come over the wallpaper — from a window, or for the first time — the pointer has not
      // moved from where it was last seen, across the screen: it is only now seen here.
      if (!ctx.pointerSeen) ctx.pointerBefore = ctx.pointer.slice();
      ctx.pointerSeen = true;
    }
    // The part of the scene the screen shows, in the scene's units from its bottom left
    // corner: all of it, unless the scene is cut to fill the screen. Worked out once a frame.
    ctx.seenOnce = { frame: -1 };
    function pageAt(x, y) {
      var shown = shownAt();
      return [shown.left + x / ctx.sceneWidth * shown.width, shown.top + (1 - y / ctx.sceneHeight) * shown.height];
    }
    // What the mouse does is told to the scripts; whatever they change by it is then drawn.
    function mouse(kind) {
      return function (event) {
        point(event);
        if (kind === 'down') ctx.pressed = true;
        if (kind === 'up') ctx.pressed = false;
        tellPointer(kind);
        if (ctx.dirty || eye.on) wake();
      };
    }
    ctx.mice = { pointermove: mouse('move'), pointerdown: mouse('down'), pointerup: mouse('up'),
                 // Gone from the wallpaper: over a window, or to another display.
                 pointerleave: function () { ctx.pointerSeen = false; } };
    Object.keys(ctx.mice).forEach(function (name) { window.addEventListener(name, ctx.mice[name], true); });
    window.addEventListener('resize', changed);

    return { pageAt: pageAt };
  }

