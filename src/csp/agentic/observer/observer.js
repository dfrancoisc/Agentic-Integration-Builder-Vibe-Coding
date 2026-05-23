/* ============================================================
   Observer — Terminal-style behind-the-scenes view

   Shows every internal step: provider resolution, MCP registration,
   skill loading, LLM calls to Bedrock, tool dispatch, results,
   cooldowns, fabrication guards — all as a scrolling terminal log.
   ============================================================ */

(function () {
  'use strict';

  var flow       = document.getElementById('flow');
  var emptyState = document.getElementById('empty-state');
  var statusPill = document.getElementById('status-pill');
  var statusLbl  = document.getElementById('status-label');
  var timerVal   = document.getElementById('timer-value');
  var toolsCount = document.getElementById('tools-count');
  var tokensCount= document.getElementById('tokens-count');
  var clearBtn   = document.getElementById('btn-clear');

  var toolCount     = 0;
  var tokenTotal    = 0;
  var startTime     = null;
  var timerHandle   = null;
  var sessionEnded  = false;
  var pollHandle    = null;
  var abortCtrl     = null;
  var seenSessions  = {};
  var auth          = null;

  // --- Auth ---
  function getAuth() {
    if (auth) return auth;
    var creds = localStorage.getItem('agentic_credentials');
    if (creds) { auth = 'Basic ' + creds; return auth; }
    var user = prompt('IRIS Username:');
    if (!user) return null;
    var pass = prompt('IRIS Password:');
    if (pass === null) return null;
    var encoded = btoa(user + ':' + pass);
    localStorage.setItem('agentic_credentials', encoded);
    auth = 'Basic ' + encoded;
    return auth;
  }

  function startTimer() {
    if (timerHandle) return;
    startTime = Date.now();
    timerHandle = setInterval(function () {
      timerVal.textContent = ((Date.now() - startTime) / 1000).toFixed(1) + 's';
    }, 100);
  }
  function stopTimer() {
    if (timerHandle) { clearInterval(timerHandle); timerHandle = null; }
  }

  // ============================================================
  //  TERMINAL OUTPUT
  // ============================================================

  function log(type, msg, detail) {
    if (emptyState) emptyState.style.display = 'none';
    if (!startTime) startTimer();

    var elapsed = startTime ? ((Date.now() - startTime) / 1000).toFixed(1) : '0.0';

    var line = document.createElement('div');
    line.className = 'log-line';

    var ts = document.createElement('span');
    ts.className = 'log-ts';
    ts.textContent = '+' + padLeft(elapsed, 6) + 's';

    var badge = document.createElement('span');
    badge.className = 'log-badge ' + type;
    badge.textContent = badgeText(type);

    var msgEl = document.createElement('span');
    msgEl.className = 'log-msg';
    msgEl.innerHTML = msg;

    line.appendChild(ts);
    line.appendChild(badge);
    line.appendChild(msgEl);
    flow.appendChild(line);

    if (detail) {
      var detEl = document.createElement('div');
      detEl.className = 'log-detail';
      var truncated = detail.length > 500 ? detail.substring(0, 500) + '...' : detail;
      detEl.textContent = truncated;
      if (detail.length > 500) {
        detEl.addEventListener('click', function () {
          if (detEl.classList.contains('expanded')) {
            detEl.textContent = truncated;
            detEl.classList.remove('expanded');
          } else {
            detEl.textContent = detail;
            detEl.classList.add('expanded');
          }
        });
      }
      flow.appendChild(detEl);
    }

    line.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }

  function separator() {
    var hr = document.createElement('hr');
    hr.className = 'log-separator';
    flow.appendChild(hr);
  }

  function badgeText(type) {
    var map = {
      trace: 'TRACE', provider: 'PROVIDER', mcp: 'MCP', skill: 'SKILL',
      llm_call: 'LLM CALL', llm_response: 'LLM RESP',
      tool_start: 'TOOL', tool_result: 'RESULT', tool_error: 'TOOL ERR',
      status: 'STATUS', token: 'RESPONSE', error: 'ERROR',
      session_start: 'SESSION', session_end: 'SESSION', done: 'DONE',
      tool_confirm: 'APPROVE'
    };
    return map[type] || type.toUpperCase();
  }

  function padLeft(s, len) {
    s = String(s);
    while (s.length < len) s = ' ' + s;
    return s;
  }

  function esc(s) {
    var d = document.createElement('span');
    d.textContent = s;
    return d.innerHTML;
  }

  function fmtNum(n) {
    return n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n);
  }

  function summarize(val, max) {
    if (!val) return '';
    try {
      return typeof val === 'string' ? val.substring(0, max || 500) : JSON.stringify(val, null, 2).substring(0, max || 500);
    } catch (e) { return String(val).substring(0, max || 500); }
  }

  // ============================================================
  //  RENDER EVENTS
  // ============================================================

  function renderEvent(ev) {
    if (!ev || !ev.type) return;
    if (ev.type === 'timeout') return;

    var d = ev.data || {};
    var type = ev.type;

    // --- session_start ---
    if (type === 'session_start') {
      setStatus('connected', 'Live');
      log('session_start',
        '<span class="hi-ok">Session started</span> ' +
        '<span class="hi-dim">user=</span><span class="hi-val">' + esc(d.user || '') + '</span> ' +
        '<span class="hi-dim">ns=</span><span class="hi-val">' + esc(d.namespace || '') + '</span> ' +
        '<span class="hi-dim">id=</span><span class="hi-val">' + esc((d.sessionId || '').substring(0, 8)) + '</span>');
      separator();
      return;
    }

    // --- provider ---
    if (type === 'provider') {
      log('provider',
        '<span class="hi-val">' + esc(d.connection || '') + '</span> ' +
        '<span class="hi-dim">provider=</span><span class="hi-val">' + esc(d.provider || '') + '</span> ' +
        '<span class="hi-dim">model=</span><span class="hi-val">' + esc(d.model || '') + '</span>');
      return;
    }

    // --- mcp ---
    if (type === 'mcp') {
      var mcpShort = (d.mcp || '').split('.').pop();
      var toolsets = d.toolsets || '';
      var tsNames = toolsets.split(',').map(function(t) { return t.trim().split('.').pop(); }).join(', ');
      log('mcp',
        '<span class="hi-name">' + esc(mcpShort) + '</span>' +
        (tsNames ? ' <span class="hi-dim">toolsets=[</span>' + esc(tsNames) + '<span class="hi-dim">]</span>' : ''));
      return;
    }

    // --- skill ---
    if (type === 'skill') {
      var skillShort = (d.class || '').split('.').pop();
      log('skill',
        '<span class="hi-name">' + esc(skillShort) + '</span> ' +
        '<span class="hi-dim">' + esc(d.class || '') + '</span>');
      return;
    }

    // --- trace ---
    if (type === 'trace') {
      log('trace', '<span class="hi-dim">' + esc(d.msg || '') + '</span>');
      return;
    }

    // --- llm_call ---
    if (type === 'llm_call') {
      separator();
      log('llm_call',
        '<span class="hi-warn">' + esc(d.msg || 'Calling LLM...') + '</span>' +
        (d.iteration ? ' <span class="hi-dim">iteration=' + d.iteration + '/' + (d.maxIterations || '?') + '</span>' : '') +
        (d.model ? ' <span class="hi-dim">model=</span><span class="hi-val">' + esc(d.model) + '</span>' : ''));
      return;
    }

    // --- llm_response ---
    if (type === 'llm_response') {
      var tokIn = d.inputTokens || 0;
      var tokOut = d.outputTokens || 0;
      if (tokIn || tokOut) {
        tokenTotal += (tokIn + tokOut);
        tokensCount.textContent = fmtNum(tokenTotal);
      }
      log('llm_response',
        '<span class="hi-ok">' + esc(d.msg || 'Response received') + '</span>' +
        ' <span class="hi-dim">latency=</span><span class="hi-val">' + (d.latencyMs || '?') + 'ms</span>' +
        ' <span class="hi-dim">in=</span><span class="hi-val">' + fmtNum(tokIn) + '</span>' +
        ' <span class="hi-dim">out=</span><span class="hi-val">' + fmtNum(tokOut) + '</span>' +
        ' <span class="hi-dim">tools=</span>' + (d.hasToolCalls ? '<span class="hi-warn">yes</span>' : '<span class="hi-dim">no</span>'));
      return;
    }

    // --- tool_start ---
    if (type === 'tool_start') {
      toolCount++;
      toolsCount.textContent = toolCount;
      var argsStr = '';
      if (d.args) {
        try {
          argsStr = typeof d.args === 'string' ? d.args : JSON.stringify(d.args);
        } catch (e) {}
      }
      log('tool_start',
        '<span class="hi-name">' + esc(d.name || '?') + '</span>' +
        (argsStr ? ' <span class="hi-dim">' + esc(argsStr.length > 120 ? argsStr.substring(0, 120) + '...' : argsStr) + '</span>' : ''),
        argsStr.length > 120 ? argsStr : null);
      return;
    }

    // --- tool_result ---
    if (type === 'tool_result') {
      var resultStr = summarize(d.result, 2000);
      var shortResult = resultStr.length > 120 ? resultStr.substring(0, 120) + '...' : resultStr;
      log('tool_result',
        '<span class="hi-name">' + esc(d.name || '?') + '</span> ' +
        '<span class="hi-dim">' + esc(shortResult) + '</span>',
        resultStr.length > 120 ? resultStr : null);
      return;
    }

    // --- status ---
    if (type === 'status') {
      var msg = d.message || d.phase || d.msg || 'status';
      log('status', esc(msg));
      return;
    }

    // --- token (response text) ---
    if (type === 'token') {
      // Don't flood the terminal with the full response text
      if (!document.getElementById('response-logged')) {
        separator();
        var marker = document.createElement('span');
        marker.id = 'response-logged';
        marker.style.display = 'none';
        flow.appendChild(marker);
        var textLen = (d.text || '').length;
        log('token', '<span class="hi-ok">Generating final response</span> <span class="hi-dim">(' + textLen + ' chars)</span>');
      }
      return;
    }

    // --- done ---
    if (type === 'done') {
      sessionEnded = true;
      stopTimer();
      setStatus('ended', 'Complete');
      if (d.totalTokens) {
        tokenTotal = +d.totalTokens;
        tokensCount.textContent = fmtNum(tokenTotal);
      }
      separator();
      var box = document.createElement('div');
      box.className = 'completion-box';
      var parts = [];
      if (d.latencyMs) parts.push('<span class="stat">' + (d.latencyMs / 1000).toFixed(1) + 's</span> total');
      if (d.iterations) parts.push('<span class="stat">' + d.iterations + '</span> iterations');
      if (d.totalTokens) parts.push('<span class="stat">' + fmtNum(+d.totalTokens) + '</span> tokens');
      if (toolCount) parts.push('<span class="stat">' + toolCount + '</span> tool calls');
      if (d.toolTrace) parts.push('trace: <span class="stat">' + esc(d.toolTrace) + '</span>');
      box.innerHTML = 'SESSION COMPLETE  |  ' + parts.join('  |  ');
      flow.appendChild(box);
      box.scrollIntoView({ behavior: 'smooth', block: 'end' });
      return;
    }

    // --- session_end ---
    if (type === 'session_end') {
      sessionEnded = true;
      return;
    }

    // --- error ---
    if (type === 'error') {
      log('error', '<span class="hi-err">' + esc(d.error || d.msg || 'Error') + '</span>' +
        (d.stage ? ' <span class="hi-dim">stage=' + esc(d.stage) + '</span>' : ''));
      return;
    }

    // --- tool_confirm ---
    if (type === 'tool_confirm') {
      log('tool_confirm',
        '<span class="hi-warn">APPROVAL REQUIRED: ' + esc(d.name || d.tool || '') + '</span>');
      return;
    }

    // --- fallback ---
    log('trace', esc(type) + ': ' + esc(d.msg || JSON.stringify(d)));
  }

  // ============================================================
  //  STATUS + RESET
  // ============================================================

  function setStatus(state, label) {
    statusPill.className = 'status-pill ' + state;
    statusLbl.textContent = label;
  }

  function resetUI() {
    if (abortCtrl) { try { abortCtrl.abort(); } catch (e) {} abortCtrl = null; }
    if (pollHandle) { clearInterval(pollHandle); pollHandle = null; }
    stopTimer();
    flow.innerHTML = '';
    var es = document.createElement('div');
    es.className = 'empty-state';
    es.id = 'empty-state';
    es.innerHTML = 'Waiting for a chat session to begin...<br><br>' +
      'Open <a href="/ui/interop/interop-editor/index.html" target="_blank">IRIS for Health Interop Editor</a> and click the chat icon in the toolbar.<br>' +
      'This page will automatically show each step as the agent works.';
    flow.appendChild(es);
    emptyState = es;
    toolCount = 0; tokenTotal = 0; startTime = null;
    sessionEnded = false;
    timerVal.textContent = '0.0s';
    toolsCount.textContent = '0';
    tokensCount.textContent = '0';
    setStatus('waiting', 'Waiting...');
  }

  clearBtn.addEventListener('click', function () {
    var a = getAuth();
    if (a) {
      fetch('/api/agentic/observer/purge', {
        method: 'POST', headers: { 'Authorization': a }
      }).catch(function () {});
    }
    resetUI();
    seenSessions = {};
    startPolling();
  });

  // ============================================================
  //  POLLING + STREAM
  // ============================================================

  function startPolling() {
    if (pollHandle) return;
    setStatus('waiting', 'Waiting...');
    poll();
    pollHandle = setInterval(poll, 2000);
  }

  function stopPolling() {
    if (pollHandle) { clearInterval(pollHandle); pollHandle = null; }
  }

  function poll() {
    var a = getAuth();
    if (!a) return;
    fetch('/api/agentic/observer/sessions', {
      headers: { 'Authorization': a }
    }).then(function (r) {
      if (r.status === 401) {
        localStorage.removeItem('agentic_credentials');
        auth = null;
        setStatus('error', 'Auth failed');
        stopPolling();
        return null;
      }
      return r.json();
    }).then(function (sessions) {
      if (!sessions || !Array.isArray(sessions)) return;
      for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].active && !seenSessions[sessions[i].id]) {
          stopPolling();
          connectToSession(sessions[i].id);
          return;
        }
      }
    }).catch(function () {});
  }

  function connectToSession(sid) {
    seenSessions[sid] = true;
    sessionEnded = false;
    var a = getAuth();
    if (!a) return;
    setStatus('connected', 'Live');
    abortCtrl = new AbortController();

    fetch('/api/agentic/observer/stream?session=' + encodeURIComponent(sid), {
      method: 'GET',
      headers: { 'Authorization': a },
      signal: abortCtrl.signal
    }).then(function (response) {
      if (!response.ok) {
        if (response.status === 401) {
          localStorage.removeItem('agentic_credentials');
          auth = null; setStatus('error', 'Auth failed');
        }
        return;
      }
      var reader = response.body.getReader();
      var decoder = new TextDecoder();
      var buffer = '';

      function pump() {
        return reader.read().then(function (result) {
          if (result.done) {
            if (!sessionEnded) setStatus('ended', 'Stream closed');
            setTimeout(startPolling, 3000);
            return;
          }
          buffer += decoder.decode(result.value, { stream: true });
          var lines = buffer.split('\n');
          buffer = lines.pop();
          var evType = null, evData = null;
          for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (line.indexOf('event: ') === 0) evType = line.substring(7).trim();
            else if (line.indexOf('data: ') === 0) evData = line.substring(6);
            else if (line === '' && evType === 'feed' && evData) {
              try { renderEvent(JSON.parse(evData)); } catch (e) {}
              evType = null; evData = null;
            } else if (line === '') { evType = null; evData = null; }
          }
          return pump();
        });
      }
      return pump();
    }).catch(function (err) {
      if (err.name === 'AbortError') return;
      setTimeout(startPolling, 3000);
    });
  }

  // --- Init ---
  startPolling();
})();
