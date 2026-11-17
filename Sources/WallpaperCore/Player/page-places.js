  // Where on the page the scene is: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePagePlaces(ctx) {
    function seenPart() {
      if (ctx.seenOnce.frame === ctx.frames) return ctx.seenOnce;
      var box = ctx.canvas.getBoundingClientRect();
      var from = box.width > 0 && box.height > 0 ? sceneAt(box.left, box.bottom) : [0, 0];
      var to = box.width > 0 && box.height > 0 ? sceneAt(box.right, box.top) : [ctx.sceneWidth, ctx.sceneHeight];
      ctx.seenOnce = { frame: ctx.frames, left: Math.max(0, from[0]), bottom: Math.max(0, from[1]),
                   right: Math.min(ctx.sceneWidth, to[0]), top: Math.min(ctx.sceneHeight, to[1]) };
      return ctx.seenOnce;
    }
    // A point of the page as a point of the scene, and back. The scene counts from its bottom.
    function sceneAt(pageX, pageY) {
      var shown = shownAt();
      return [(pageX - shown.left) / shown.width * ctx.sceneWidth, (1 - (pageY - shown.top) / shown.height) * ctx.sceneHeight];
    }
    // Where the whole scene is on the page, in its pixels; parts of it may be cut off.
    function shownAt() {
      var box = ctx.canvas.getBoundingClientRect();
      var fit = ctx.canvas.style.objectFit || 'cover';
      var by = fit === 'contain' ? Math.min(box.width / ctx.sceneWidth, box.height / ctx.sceneHeight)
             : Math.max(box.width / ctx.sceneWidth, box.height / ctx.sceneHeight);
      var width = fit === 'fill' ? box.width : ctx.sceneWidth * by, height = fit === 'fill' ? box.height : ctx.sceneHeight * by;
      var kept = (ctx.canvas.style.objectPosition || '50% 50%').split(/\s+/).map(parseFloat);
      return { left: box.left + (box.width - width) * (isFinite(kept[0]) ? kept[0] : 50) / 100,
               top: box.top + (box.height - height) * (isFinite(kept[1]) ? kept[1] : 50) / 100, width: width, height: height };
    }
    return { seenPart: seenPart, sceneAt: sceneAt, shownAt: shownAt };
  }

