  // Moving with the pointer: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePointerMoves(ctx) {
    var general = ctx.general;
    // --- Moving with the pointer ---------------------------------------------------------
    //
    // A scene may be looked at as through a window: as the pointer moves, what is said to be
    // near moves more than what is far. `eye` is where the scene is looked at from, from the
    // middle, and follows the pointer with a delay.

    ctx.eye = { on: false, amount: 0, x: 0, y: 0, settling: false };
    // The camera may shake: the whole scene is moved a little, smoothly and without end, as
    // far as the amplitude says (a share of the scene's height), as fast as the speed says,
    // and the rougher, the more of a quicker trembling there is in it.
    ctx.shake = { on: false, x: 0, y: 0 };
    // Where a script has moved the camera from the scene's middle, and how near it is.
    ctx.camera = { x: 0, y: 0, zoom: 1 };

    function tremble() {
      ctx.shake.on = flag(general.camerashake, false);
      if (!ctx.shake.on) {
        if (ctx.shake.x || ctx.shake.y) {
          ctx.shake.x = ctx.shake.y = 0;
          ctx.dirty = true;
        }
        return;
      }
      var reach = number(general.camerashakeamplitude, 0.5) / 100 * ctx.sceneHeight;
      var at = ctx.time * number(general.camerashakespeed, 3), rough = Math.max(0, number(general.camerashakeroughness, 1));
      function wobble(seed) {
        return (smoothNoise(at, seed * 13.7, 4096, seed) - 0.5) * 2 + rough * 0.5 * (smoothNoise(at * 4, seed * 29.1, 4096, seed + 1) - 0.5) * 2;
      }
      ctx.shake.x = reach * wobble(3);
      ctx.shake.y = reach * wobble(9);
      ctx.dirty = true;
    }

    function look(seconds) {
      tremble();
      ctx.eye.on = flag(general.cameraparallax, false);
      if (!ctx.eye.on) {
        ctx.eye.settling = false;
        return;
      }
      ctx.eye.amount = number(general.cameraparallaxamount, 0.5);
      var reach = number(general.cameraparallaxmouseinfluence, 0.5);
      var delay = Math.max(0, number(general.cameraparallaxdelay, 0.1));
      var toX = (Math.max(0, Math.min(1, ctx.pointer[0])) - 0.5) * reach, toY = (Math.max(0, Math.min(1, ctx.pointer[1])) - 0.5) * reach;
      var share = delay > 0 ? 1 - Math.exp(-seconds / delay) : 1;
      var x = ctx.eye.x + (toX - ctx.eye.x) * share, y = ctx.eye.y + (toY - ctx.eye.y) * share;
      ctx.eye.settling = Math.abs(toX - x) + Math.abs(toY - y) > 0.0002;
      if (!ctx.eye.settling) {
        x = toX;
        y = toY;
      }
      if (x !== ctx.eye.x || y !== ctx.eye.y) {
        ctx.eye.x = x;
        ctx.eye.y = y;
        ctx.dirty = true;
      }
    }

    return { look: look };
  }

