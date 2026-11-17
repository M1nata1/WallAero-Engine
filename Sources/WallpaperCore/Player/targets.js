  // Pictures to draw into: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeTargets(ctx) {
    var gl = ctx.gl, newTexture = ctx.newTexture, looksOf = ctx.looksOf;
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
      // One made to repeat goes back as the others are, ending at its edges.
      if (target.repeats) {
        target.repeats = false;
        gl.bindTexture(gl.TEXTURE_2D, target.texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        target.texture.looks = { wrapS: gl.CLAMP_TO_EDGE, wrapT: gl.CLAMP_TO_EDGE, smooth: looksOf(target.texture).smooth };
      }
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
      if (target.depthCleared !== ctx.frames) {
        target.depthCleared = ctx.frames;
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

    return { acquire: acquire, release: release, depthOf: depthOf, forgetTargets: forgetTargets };
  }

