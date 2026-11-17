  // Programs: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePrograms(ctx) {
    var gl = ctx.gl;
    // --- Programs ---------------------------------------------------------

    // What the compiler last complained of, when it was asked not to say so itself.
    ctx.complaint = null;

    function compile(type, source, what, quietly) {
      var shader = gl.createShader(type);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        var problem = (gl.getShaderInfoLog(shader) || '').split('\n')[0];
        // The line the compiler names, to make the reason readable.
        var line = /ERROR: \d+:(\d+)/.exec(problem);
        var text = line ? (source.split('\n')[Number(line[1]) - 1] || '').trim() : '';
        var said = what + ' does not compile: ' + problem.replace(/^ERROR: \d+:\d+: /, '') + (text ? ' — in “' + text.slice(0, 80) + '”' : '');
        // Everything it says of that line: the first complaint is not always the telling one.
        var ofLine = (gl.getShaderInfoLog(shader) || '').split('\n').filter(function (each) {
          var named = /ERROR: \d+:(\d+)/.exec(each);
          return named && line && named[1] === line[1];
        });
        ctx.complaint = { stage: type === gl.VERTEX_SHADER ? 'vertex' : 'fragment', messages: ofLine, line: line ? Number(line[1]) : 0, said: said };
        if (!quietly) note(said);
        gl.deleteShader(shader);
        return null;
      }
      return shader;
    }

    // A program with what it takes: its uniforms by name, with their kinds.
    function link(vertexSource, fragmentSource, what, quietly) {
      ctx.complaint = null;
      var vertex = compile(gl.VERTEX_SHADER, vertexSource, what + ' (vertex)', quietly);
      var fragment = vertex && compile(gl.FRAGMENT_SHADER, fragmentSource, what + ' (fragment)', quietly);
      if (!vertex || !fragment) return null;
      var program = gl.createProgram();
      gl.attachShader(program, vertex);
      gl.attachShader(program, fragment);
      // The same places in every program, so that one shape serves them all.
      ['a_Position', 'a_TexCoord', 'a_Place', 'a_Color', 'a_Frame', 'a_Spot', 'a_Uv', 'a_More', 'a_Normal', 'a_Bones', 'a_Weights'].forEach(function (name, index) {
        gl.bindAttribLocation(program, index, name);
      });
      gl.linkProgram(program);
      gl.deleteShader(vertex);
      gl.deleteShader(fragment);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        var refused = (gl.getProgramInfoLog(program) || '').split('\n').filter(Boolean);
        ctx.complaint = { stage: 'both', messages: refused, line: 0, said: what + ' does not link: ' + (refused[0] || '') };
        if (!quietly) note(ctx.complaint.said);
        gl.deleteProgram(program);
        return null;
      }
      var uniforms = {};
      var count = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
      for (var i = 0; i < count; i++) {
        var info = gl.getActiveUniform(program, i);
        var name = info.name.replace(/\[0\]$/, '');
        uniforms[name] = { location: gl.getUniformLocation(program, info.name), type: info.type, size: info.size };
      }
      return { program: program, uniforms: uniforms };
    }

    return { link: link };
  }

