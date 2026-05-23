/* ============================================================
   Observer — real-time terminal view of agent internals.

   Each event is a single short line. Click any line to expand
   its detail payload. Events stream in AS they happen — the
   chatbot broadcasts the session ID via BroadcastChannel before
   the request fires, so the Observer connects to the stream
   before any events exist.
   ============================================================ */

(function () {
  'use strict';

  var nsParam = (function () {
    var m = location.search.match(/[?&]ns=([^&]*)/);
    return m ? decodeURIComponent(m[1]) : 'USER';
  })();
  var EDITOR_URL = '/ui/interop/interop-editor/index.html?%24NAMESPACE=' + encodeURIComponent(nsParam);

  var app        = document.getElementById('app');
  var editorPane = document.getElementById('editor-pane');
  var editorFrame= document.getElementById('editor-frame');
  var flow       = document.getElementById('flow');
  var emptyState = document.getElementById('empty-state');
  var statusPill = document.getElementById('status-pill');
  var statusLbl  = document.getElementById('status-label');
  var timerVal   = document.getElementById('timer-value');
  var toolsCount = document.getElementById('tools-count');
  var tokensCount= document.getElementById('tokens-count');
  var clearBtn   = document.getElementById('btn-clear');
  var editorBtn  = document.getElementById('btn-editor');

  var toolCount     = 0;
  var tokenTotal    = 0;
  var startTime     = null;
  var timerHandle   = null;
  var sessionEnded  = false;
  var pollHandle    = null;
  var abortCtrl     = null;
  var seenSessions  = {};
  var auth          = null;
  var splitOpen     = false;

  // ============================================================
  //  AUTH
  // ============================================================
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
  //  SPLIT VIEW
  // ============================================================
  function openSplitView() {
    if (splitOpen) return;
    splitOpen = true;
    app.classList.add('split');
    editorFrame.src = EDITOR_URL;
    editorBtn.textContent = 'Close Editor';
    editorBtn.classList.add('active');
  }
  function closeSplitView() {
    if (!splitOpen) return;
    splitOpen = false;
    app.classList.remove('split');
    editorFrame.src = 'about:blank';
    editorBtn.textContent = 'Open Editor';
    editorBtn.classList.remove('active');
  }
  editorBtn.addEventListener('click', function () {
    if (splitOpen) closeSplitView(); else openSplitView();
  });
  document.addEventListener('click', function (e) {
    if (e.target.classList.contains('editor-link')) {
      e.preventDefault();
      openSplitView();
    }
  });

  // ============================================================
  //  TERMINAL — one short line per event, click to expand
  // ============================================================

  function line(type, text, detail) {
    if (emptyState) emptyState.style.display = 'none';
    if (!startTime) startTimer();
    var el = document.createElement('div');
    el.className = 'log-line';
    var elapsed = startTime ? ((Date.now() - startTime) / 1000).toFixed(1) : '0.0';

    var html = '<span class="ts">' + elapsed + 's</span>' +
               '<span class="badge ' + type + '">' + badge(type) + '</span>' +
               '<span class="msg">' + text + '</span>';
    el.innerHTML = html;

    if (detail) {
      el.classList.add('has-detail');
      var det = document.createElement('div');
      det.className = 'detail';
      det.textContent = typeof detail === 'string' ? detail : JSON.stringify(detail, null, 2);
      det.hidden = true;
      el.addEventListener('click', function () { det.hidden = !det.hidden; });
      flow.appendChild(el);
      flow.appendChild(det);
    } else {
      flow.appendChild(el);
    }
    el.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }

  function sep() {
    var hr = document.createElement('hr');
    hr.className = 'sep';
    flow.appendChild(hr);
  }

  function badge(type) {
    return ({ trace:'TRACE', provider:'PROVIDER', mcp:'MCP', skill:'SKILL',
      llm_call:'LLM >>>', llm_response:'LLM <<<',
      tool_start:'TOOL >>>', tool_result:'TOOL <<<', tool_error:'TOOL ERR',
      status:'STATUS', token:'RESPONSE', error:'ERROR',
      session_start:'SESSION', session_end:'SESSION', done:'DONE',
      tool_confirm:'CONFIRM' })[type] || type.toUpperCase();
  }

  function esc(s) { var d = document.createElement('span'); d.textContent = s; return d.innerHTML; }

  function fmtNum(n) { return n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n); }

  // ============================================================
  //  RENDER — one event = one light line
  // ============================================================

  function render(ev) {
    if (!ev || !ev.type || ev.type === 'timeout') return;
    var d = ev.data || {};
    var t = ev.type;

    if (t === 'session_start') {
      setStatus('connected', 'Live');
      line('session_start', esc(d.user || '') + ' @ ' + esc(d.namespace || ''),
        'session=' + (d.sessionId || ''));
      sep();
      return;
    }
    if (t === 'provider') {
      line('provider', esc(d.connection || 'default'),
        'provider=' + (d.provider || '') + '  model=' + (d.model || ''));
      return;
    }
    if (t === 'mcp') {
      var short = (d.mcp || '').split('.').pop();
      var ts = (d.toolsets || '').split(',').map(function (s) { return s.trim().split('.').pop(); }).filter(Boolean).join(', ');
      line('mcp', esc(short) + (ts ? '  [' + esc(ts) + ']' : ''), d.mcp);
      return;
    }
    if (t === 'skill') {
      line('skill', esc((d.class || '').split('.').pop()), d.class);
      return;
    }
    if (t === 'trace') {
      line('trace', esc(d.msg || ''));
      return;
    }
    if (t === 'llm_call') {
      sep();
      var iter = d.iteration ? 'iteration ' + d.iteration + '/' + (d.maxIterations || '?') : '';
      line('llm_call', esc(iter),
        'model=' + (d.model || '') + '  ' + (d.msg || ''));
      return;
    }
    if (t === 'llm_response') {
      var tin = d.inputTokens || 0, tout = d.outputTokens || 0;
      if (tin || tout) { tokenTotal += tin + tout; tokensCount.textContent = fmtNum(tokenTotal); }
      var lat = d.latencyMs ? (d.latencyMs / 1000).toFixed(1) + 's' : '?';
      var tc = d.hasToolCalls ? '  tools: yes' : '';
      line('llm_response', lat + '  ' + fmtNum(tin) + ' in / ' + fmtNum(tout) + ' out' + tc,
        'latency=' + (d.latencyMs || '') + 'ms  inputTokens=' + tin + '  outputTokens=' + tout);
      return;
    }
    if (t === 'tool_start') {
      toolCount++; toolsCount.textContent = toolCount;
      var argsStr = '';
      try { argsStr = d.args ? (typeof d.args === 'string' ? d.args : JSON.stringify(d.args)) : ''; } catch (e) {}
      line('tool_start', esc(d.name || '?'), argsStr || null);
      return;
    }
    if (t === 'tool_result') {
      var r = '';
      try { r = d.result ? (typeof d.result === 'string' ? d.result : JSON.stringify(d.result, null, 2)) : ''; } catch (e) { r = String(d.result); }
      var ok = r.indexOf('"ok":1') !== -1 || r.indexOf('"ok": 1') !== -1;
      line('tool_result', esc(d.name || '?') + (ok ? '  ok' : ''), r || null);
      return;
    }
    if (t === 'tool_error') {
      line('tool_error', esc(d.name || '?') + '  ' + esc(d.error || ''));
      return;
    }
    if (t === 'status') {
      line('status', esc(d.message || d.phase || d.msg || ''));
      return;
    }
    if (t === 'token') {
      if (!document.getElementById('resp-mark')) {
        sep();
        var m = document.createElement('span'); m.id = 'resp-mark'; m.hidden = true; flow.appendChild(m);
        line('token', (d.text || '').length + ' chars');
      }
      return;
    }
    if (t === 'done') {
      sessionEnded = true; stopTimer();
      setStatus('ended', 'Complete');
      if (d.totalTokens) { tokenTotal = +d.totalTokens; tokensCount.textContent = fmtNum(tokenTotal); }
      sep();
      var parts = [];
      if (d.latencyMs) parts.push((d.latencyMs / 1000).toFixed(1) + 's');
      if (d.iterations) parts.push(d.iterations + ' iter');
      if (d.totalTokens) parts.push(fmtNum(+d.totalTokens) + ' tokens');
      if (toolCount) parts.push(toolCount + ' tools');
      var box = document.createElement('div');
      box.className = 'done-box';
      box.textContent = 'DONE  ' + parts.join('  |  ');
      if (d.toolTrace) {
        var det = document.createElement('div');
        det.className = 'detail';
        det.textContent = 'trace: ' + d.toolTrace;
        det.hidden = true;
        box.style.cursor = 'pointer';
        box.addEventListener('click', function () { det.hidden = !det.hidden; });
        flow.appendChild(box);
        flow.appendChild(det);
      } else {
        flow.appendChild(box);
      }
      box.scrollIntoView({ behavior: 'smooth', block: 'end' });
      return;
    }
    if (t === 'session_end') { sessionEnded = true; return; }
    if (t === 'error') {
      line('error', esc(d.error || d.msg || 'error') + (d.stage ? '  [' + d.stage + ']' : ''));
      return;
    }
    if (t === 'tool_confirm') {
      line('tool_confirm', 'APPROVE: ' + esc(d.name || d.tool || ''));
      return;
    }
    // fallback
    line('trace', t + ': ' + esc(d.msg || JSON.stringify(d)));
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
    es.innerHTML = 'Waiting for a chat session...<br>' +
      '<a href="#" class="editor-link">Open IRIS Interop Editor</a> to start.';
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
  //  STREAM — connect to a session's event stream
  // ============================================================

  function connectToSession(sid) {
    seenSessions[sid] = true;
    sessionEnded = false;
    var a = getAuth();
    if (!a) return;
    setStatus('connected', 'Connecting...');
    if (abortCtrl) { try { abortCtrl.abort(); } catch (e) {} }
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
            var l = lines[i];
            if (l.indexOf('event: ') === 0) evType = l.substring(7).trim();
            else if (l.indexOf('data: ') === 0) evData = l.substring(6);
            else if (l === '' && evType === 'feed' && evData) {
              try { render(JSON.parse(evData)); } catch (e) {}
              evType = null; evData = null;
            } else if (l === '') { evType = null; evData = null; }
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

  // ============================================================
  //  POLLING — discover active sessions
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
        auth = null; setStatus('error', 'Auth failed');
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

  // ============================================================
  //  BROADCAST CHANNEL — chatbot tells us the session ID
  //  BEFORE the request fires, so we connect instantly
  // ============================================================

  try {
    var channel = new BroadcastChannel('agentic-observer');
    channel.onmessage = function (ev) {
      if (ev.data && ev.data.type === 'session' && ev.data.id) {
        // Stop any existing poll/stream — new session incoming
        stopPolling();
        if (abortCtrl) { try { abortCtrl.abort(); } catch (e) {} abortCtrl = null; }
        // Reset counters for the new session
        toolCount = 0; tokenTotal = 0; startTime = null; sessionEnded = false;
        timerVal.textContent = '0.0s';
        toolsCount.textContent = '0';
        tokensCount.textContent = '0';
        // Clear previous log
        flow.innerHTML = '';
        emptyState = null;
        // Connect immediately — the stream will wait for events
        setStatus('connected', 'Waiting for events...');
        connectToSession(ev.data.id);
      }
    };
  } catch (e) {}

  // ============================================================
  //  INIT
  // ============================================================

  // If ?session= is in the URL, connect directly (no polling)
  var urlSession = (function () {
    var m = location.search.match(/[?&]session=([^&]*)/);
    return m ? decodeURIComponent(m[1]) : '';
  })();

  if (location.search.indexOf('split') !== -1) {
    openSplitView();
  }

  if (urlSession) {
    connectToSession(urlSession);
  } else {
    startPolling();
  }
})();
