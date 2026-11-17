  // Size: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeSize(ctx) {
    var gl = ctx.gl, flat = ctx.flat, acquire = ctx.acquire, release = ctx.release, forgetTargets = ctx.forgetTargets, objects = ctx.objects, tellScripts = ctx.tellScripts, releaseRepeated = ctx.releaseRepeated;
    // --- Size -------------------------------------------------------------

    // The scene is drawn as large as it shows on the screen, and no larger than it is.
    function resize() {
      var density = window.devicePixelRatio || 1;
      var shown = Math.max(window.innerWidth * density / ctx.sceneWidth, window.innerHeight * density / ctx.sceneHeight);
      var wanted = Math.max(0.05, Math.min(1, shown || 1));
      var width = Math.max(1, Math.round(ctx.sceneWidth * wanted)), height = Math.max(1, Math.round(ctx.sceneHeight * wanted));
      if (ctx.sceneTarget && ctx.canvas.width === width && ctx.canvas.height === height) return;
      var again = !!ctx.sceneTarget;
      ctx.scale = wanted;
      ctx.canvas.width = width;
      ctx.canvas.height = height;
      // Everything drawn at the old size goes.
      objects.forEach(function (object) {
        if (object.kept) {
          gl.deleteFramebuffer(object.kept.framebuffer);
          gl.deleteTexture(object.kept.texture);
          object.kept = null;
        }
      });
      [ctx.sceneTarget, ctx.copyTarget].forEach(release);
      // So do the finished pictures kept for others; they show nothing until made again.
      Object.keys(ctx.composites).forEach(function (id) {
        var kept = ctx.composites[id];
        if (kept.target) releaseRepeated(kept.target);
        kept.target = null;
        kept.layers[0] = flat(0, 0, 0, 0).layers[0];
      });
      forgetTargets();
      ctx.sceneTarget = acquire(width, height);
      ctx.copyTarget = acquire(width, height);
      ctx.redraw = true;
      if (again) tellScripts('resizeScreen', new Vec2(width, height));
    }

    return { resize: resize };
  }

