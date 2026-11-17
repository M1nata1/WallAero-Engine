  // Shapes: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeShapes(ctx) {
    var gl = ctx.gl;
    // --- Shapes -----------------------------------------------------------

    // The rectangle every pass of an effect is drawn as: the corners of the screen, each with
    // the corner of the picture that belongs there, the top left one first.
    ctx.passShape = gl.createVertexArray();
    gl.bindVertexArray(ctx.passShape);
    ctx.passBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, ctx.passBuffer);
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

    return {};
  }

