/* ============================================================
   Observer — Behind the Scenes live feed

   Demo flow:
   1. Open this page -> "Waiting for session..."
   2. Open chatbot in another tab, send a message
   3. Observer lights up with real-time steps as the agent works
   4. Session ends -> completion banner
   5. Click "Clear" -> resets, waits for the next session

   Connection model:
   - Poll /observer/sessions every 2s looking for an ACTIVE session
   - When found, stream /observer/stream?session=<id>
   - When stream ends (session_end), show completion, stop polling
   - "Clear" button: purge server data, reset UI, resume polling
   ============================================================ */

(function () {
  'use strict';

  // --- DOM refs ---
  var flow       = document.getElementById('flow');
  var emptyState = document.getElementById('empty-state');
  var statusPill = document.getElementById('status-pill');
  var statusLbl  = document.getElementById('status-label');
  var timerVal   = document.getElementById('timer-value');
  var toolsCount = document.getElementById('tools-count');
  var tokensCount= document.getElementById('tokens-count');
  var clearBtn   = document.getElementById('btn-clear');

  // --- State ---
  var stepNum       = 0;
  var toolCount     = 0;
  var tokenCount    = 0;
  var startTime     = null;
  var timerHandle   = null;
  var currentPhase  = null;
  var phaseEl       = null;
  var listEl        = null;
  var sessionEnded  = false;
  var pollHandle    = null;
  var abortCtrl     = null;    // AbortController for the current stream fetch
  var connectedSid  = null;    // session id we are currently streaming
  var seenSessions  = {};      // sessions we already showed (skip on next poll)
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

  // --- Timer ---
  function startTimer() {
    if (timerHandle) return;
    startTime = Date.now();
    timerHandle = setInterval(function () {
      var elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
      timerVal.textContent = elapsed + 's';
    }, 100);
  }

  function stopTimer() {
    if (timerHandle) { clearInterval(timerHandle); timerHandle = null; }
  }

  // ============================================================
  //  RESET / CLEAR
  // ============================================================
  function resetUI() {
    // Abort any in-flight stream
    if (abortCtrl) { try { abortCtrl.abort(); } catch (e) {} abortCtrl = null; }
    // Stop polling
    if (pollHandle) { clearInterval(pollHandle); pollHandle = null; }
    // Stop timer
    stopTimer();
    // Clear DOM
    flow.innerHTML = '';
    // Re-add empty state
    var es = document.createElement('div');
    es.className = 'empty-state';
    es.id = 'empty-state';
    es.innerHTML = 'Waiting for a chat session to begin...<br><br>' +
      'Open <a href="/ui/interop/interop-editor/index.html" target="_blank">IRIS for Health Interop Editor</a> and click the chat icon in the toolbar.<br>' +
      'This page will automatically show each step as the agent works.';
    flow.appendChild(es);
    emptyState = es;
    // Reset counters
    stepNum = 0;
    toolCount = 0;
    tokenCount = 0;
    startTime = null;
    currentPhase = null;
    phaseEl = null;
    listEl = null;
    sessionEnded = false;
    connectedSid = null;
    timerVal.textContent = '0.0s';
    toolsCount.textContent = '0';
    tokensCount.textContent = '0';
    setStatus('waiting', 'Waiting for session...');
  }

  // Clear button handler — purge server data then reset
  clearBtn.addEventListener('click', function () {
    var a = getAuth();
    if (!a) return;
    // Purge server-side LiveFeed
    fetch('/api/agentic/observer/purge', {
      method: 'POST',
      headers: { 'Authorization': a }
    }).catch(function () {});  // best-effort
    // Reset UI and mark all known sessions as seen so we don't replay them
    resetUI();
    seenSessions = {};
    // Restart polling
    startPolling();
  });

  // ============================================================
  //  POLLING — look for an active session
  // ============================================================
  function startPolling() {
    if (pollHandle) return;
    setStatus('waiting', 'Waiting for session...');
    poll();  // immediate first check
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
      // Find an active session we haven't connected to yet
      for (var i = 0; i < sessions.length; i++) {
        var s = sessions[i];
        if (s.active && !seenSessions[s.id]) {
          stopPolling();
          connectToSession(s.id);
          return;
        }
      }
    }).catch(function () {});
  }

  // ============================================================
  //  STREAM — connect to a specific session
  // ============================================================
  function connectToSession(sid) {
    connectedSid = sid;
    seenSessions[sid] = true;
    sessionEnded = false;

    var a = getAuth();
    if (!a) return;

    setStatus('connected', 'Connected');

    abortCtrl = new AbortController();
    var url = '/api/agentic/observer/stream?session=' + encodeURIComponent(sid);

    fetch(url, {
      method: 'GET',
      headers: { 'Authorization': a },
      signal: abortCtrl.signal
    }).then(function (response) {
      if (!response.ok) {
        if (response.status === 401) {
          localStorage.removeItem('agentic_credentials');
          auth = null;
          setStatus('error', 'Auth failed');
          return;
        }
        throw new Error('HTTP ' + response.status);
      }

      var reader = response.body.getReader();
      var decoder = new TextDecoder();
      var buffer = '';

      function pump() {
        return reader.read().then(function (result) {
          if (result.done) {
            // Stream closed by server
            if (!sessionEnded) {
              setStatus('ended', 'Stream closed');
            }
            // Go back to polling for the next session
            setTimeout(function () { startPolling(); }, 3000);
            return;
          }

          buffer += decoder.decode(result.value, { stream: true });
          var lines = buffer.split('\n');
          buffer = lines.pop();

          var eventType = null;
          var eventData = null;

          for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (line.indexOf('event: ') === 0) {
              eventType = line.substring(7).trim();
            } else if (line.indexOf('data: ') === 0) {
              eventData = line.substring(6);
            } else if (line === '' && eventType === 'feed' && eventData) {
              try {
                var envelope = JSON.parse(eventData);
                renderStep(envelope);
              } catch (e) {}
              eventType = null;
              eventData = null;
            } else if (line === '' && eventType === 'error' && eventData) {
              // Server-side error (e.g. "no session") — ignore, keep polling
              eventType = null;
              eventData = null;
            } else if (line === '') {
              eventType = null;
              eventData = null;
            }
          }
          return pump();
        });
      }
      return pump();
    }).catch(function (err) {
      if (err.name === 'AbortError') return;  // user clicked Clear
      console.error('Observer stream error:', err);
      setTimeout(function () { startPolling(); }, 3000);
    });
  }

  // ============================================================
  //  PHASE + BADGE classification
  // ============================================================
  function classifyPhase(ev) {
    var type = ev.type;
    var data = ev.data || {};
    var name = (data.name || '').toLowerCase();

    if (type === 'session_start') return 'session';
    if (type === 'session_end')   return 'complete';
    if (type === 'error')         return 'error';
    if (type === 'done')          return 'complete';
    if (type === 'token')         return 'report';

    if (type === 'tool_start' || type === 'tool_result') {
      if (name.indexOf('search') >= 0 || name.indexOf('catalog') >= 0 ||
          name.indexOf('describe') >= 0 || name.indexOf('gethl7') >= 0 ||
          name.indexOf('fieldmapping') >= 0 || name.indexOf('field_mapping') >= 0 ||
          name.indexOf('getsegment') >= 0 || name.indexOf('getschema') >= 0 ||
          name.indexOf('pipeline') >= 0)
        return 'research';
      if (name.indexOf('list') >= 0 || name.indexOf('get') >= 0 ||
          name.indexOf('lookup') >= 0 || name.indexOf('explain') >= 0)
        return 'research';
      if (name.indexOf('create') >= 0 || name.indexOf('add') >= 0 ||
          name.indexOf('build') >= 0 || name.indexOf('update') >= 0 ||
          name.indexOf('compile') >= 0 || name.indexOf('ensure') >= 0)
        return 'build';
      if (name.indexOf('test') >= 0 || name.indexOf('send') >= 0 ||
          name.indexOf('validate') >= 0 || name.indexOf('dryrun') >= 0 ||
          name.indexOf('dry_run') >= 0 || name.indexOf('compare') >= 0 ||
          name.indexOf('postbuild') >= 0)
        return 'test';
      if (name.indexOf('confirm') >= 0 || name.indexOf('approve') >= 0)
        return 'approve';
      return 'build';
    }
    if (type === 'tool_confirm') return 'approve';
    if (type === 'status') return 'status';
    return 'status';
  }

  var phaseLabels = {
    session: 'Session', research: 'Research', plan: 'Plan',
    build: 'Build', test: 'Test', approve: 'Approval Gate',
    report: 'Report', complete: 'Complete', error: 'Error', status: 'Status'
  };
  var phaseIcons = {
    session: 'S', research: 'R', plan: 'P', build: 'B', test: 'T',
    approve: 'A', report: 'F', complete: 'C', error: 'E', status: 'I'
  };
  var phaseClasses = {
    session: 'research', research: 'research', plan: 'plan',
    build: 'build', test: 'test', approve: 'plan',
    report: 'report', complete: 'report', error: 'test', status: 'research'
  };

  function ensurePhase(phaseName) {
    if (currentPhase === phaseName && phaseEl) return;
    currentPhase = phaseName;
    phaseEl = document.createElement('div');
    phaseEl.className = 'phase-section';
    var header = document.createElement('div');
    header.className = 'phase-header';
    var icon = document.createElement('div');
    icon.className = 'phase-icon ' + (phaseClasses[phaseName] || 'research');
    icon.textContent = phaseIcons[phaseName] || '?';
    var title = document.createElement('div');
    title.className = 'phase-title';
    title.textContent = phaseLabels[phaseName] || phaseName;
    var count = document.createElement('div');
    count.className = 'phase-count';
    header.appendChild(icon);
    header.appendChild(title);
    header.appendChild(count);
    phaseEl.appendChild(header);
    listEl = document.createElement('div');
    listEl.className = 'step-list';
    phaseEl.appendChild(listEl);
    flow.appendChild(phaseEl);
  }

  function badgeType(ev) {
    var type = ev.type;
    var name = ((ev.data || {}).name || '').toLowerCase();
    if (type === 'tool_confirm')   return 'approve';
    if (type === 'error')          return 'error';
    if (type === 'token')          return 'token';
    if (type === 'status')         return 'status';
    if (type === 'session_start' || type === 'session_end') return 'session';
    if (type === 'done')           return 'session';
    if (name.indexOf('search') >= 0 || name.indexOf('catalog') >= 0 ||
        name.indexOf('describe') >= 0 || name.indexOf('gethl7') >= 0 ||
        name.indexOf('getsegment') >= 0 || name.indexOf('getschema') >= 0 ||
        name.indexOf('pipeline') >= 0 || name.indexOf('fieldmapping') >= 0)
      return 'rag';
    return 'tool';
  }

  function badgeLabel(ev) {
    var labels = {
      tool: 'TOOL', rag: 'RAG', skill: 'SKILL', approve: 'APPROVE',
      status: 'STATUS', token: 'RESPONSE', error: 'ERROR', session: 'SESSION'
    };
    return labels[badgeType(ev)] || 'EVENT';
  }

  // ============================================================
  //  RENDER a single step
  // ============================================================
  function renderStep(ev) {
    if (!ev || !ev.type) return;
    if (ev.type === 'timeout') return;

    // Hide empty state on first real event
    if (emptyState) emptyState.style.display = 'none';
    if (!startTime) startTimer();

    var data = ev.data || {};
    var phase = classifyPhase(ev);

    // --- token: single "Generating response..." card ---
    if (ev.type === 'token') {
      ensurePhase('report');
      if (!document.getElementById('report-card')) {
        stepNum++;
        var card = buildCard(stepNum, ev, 'Generating response...');
        card.id = 'report-card';
        card.classList.add('active');
        addCard(card);
      }
      return;
    }

    // --- done: completion banner ---
    if (ev.type === 'done') {
      // Mark the report card as done
      var rc = document.getElementById('report-card');
      if (rc) { rc.classList.remove('active'); rc.classList.add('done'); }
      sessionEnded = true;
      stopTimer();
      setStatus('ended', 'Session complete');
      if (data.totalTokens) {
        tokenCount = +data.totalTokens;
        tokensCount.textContent = formatNum(tokenCount);
      }
      showCompletionBanner(data);
      return;
    }

    // --- session_end: mark finished ---
    if (ev.type === 'session_end') {
      sessionEnded = true;
      return;
    }

    // --- session_start ---
    if (ev.type === 'session_start') {
      setStatus('connected', 'Live');
      ensurePhase('session');
      stepNum++;
      var label = 'Session started';
      if (data.user) label += '  |  user: ' + data.user;
      if (data.namespace) label += '  |  namespace: ' + data.namespace;
      var card = buildCard(stepNum, ev, label);
      card.classList.add('done');
      addCard(card);
      return;
    }

    // --- status ---
    if (ev.type === 'status') {
      var msg = data.message || data.phase || 'Status update';
      if (data.phase === 'ready') {
        msg = 'Agent ready  (' + (data.turnsReplayed || 0) + ' prior turns replayed)';
      }
      ensurePhase('status');
      stepNum++;
      var card = buildCard(stepNum, ev, msg);
      card.classList.add('done');
      addCard(card);
      return;
    }

    // --- error ---
    if (ev.type === 'error') {
      ensurePhase('error');
      stepNum++;
      var card = buildCard(stepNum, ev, data.error || 'Unknown error');
      card.classList.add('error-card');
      addCard(card);
      return;
    }

    // --- tool_start ---
    if (ev.type === 'tool_start') {
      toolCount++;
      toolsCount.textContent = toolCount;
      ensurePhase(phase);
      stepNum++;
      var name = data.name || 'unknown';
      var detail = '';
      if (data.args) {
        try {
          detail = typeof data.args === 'string' ? data.args : JSON.stringify(data.args, null, 2);
        } catch (e) { detail = String(data.args); }
      }
      var card = buildCard(stepNum, ev, name, detail);
      card.classList.add('active');
      card.setAttribute('data-tool', name);
      if (phase === 'approve') card.classList.add('approve-gate');
      addCard(card);
      return;
    }

    // --- tool_result ---
    if (ev.type === 'tool_result') {
      var name = data.name || '(tool)';
      var activeCards = flow.querySelectorAll('.step-card.active[data-tool="' + CSS.escape(name) + '"]');
      if (activeCards.length > 0) {
        var target = activeCards[activeCards.length - 1];
        target.classList.remove('active');
        target.classList.add('done');
        appendResult(target, data.result);
        if (ev.elapsed) {
          var t = target.querySelector('.step-timing');
          if (t) t.textContent = ev.elapsed + 's';
        }
      } else {
        ensurePhase(phase);
        stepNum++;
        var snippet = summarize(data.result, 200);
        var card = buildCard(stepNum, ev, name + ' (result)', snippet);
        card.classList.add('done');
        addCard(card);
      }
      if (ev.elapsed) timerVal.textContent = ev.elapsed + 's';
      return;
    }

    // --- tool_confirm ---
    if (ev.type === 'tool_confirm') {
      ensurePhase('approve');
      stepNum++;
      var card = buildCard(stepNum, ev, 'Approval requested: ' + (data.name || data.tool || ''));
      card.classList.add('approve-gate', 'active');
      addCard(card);
      return;
    }

    // --- fallback ---
    ensurePhase('status');
    stepNum++;
    addCard(buildCard(stepNum, ev, ev.type));
  }

  // ============================================================
  //  DOM builders
  // ============================================================
  function buildCard(num, ev, label, detail) {
    var card = document.createElement('div');
    card.className = 'step-card';

    var numEl = document.createElement('div');
    numEl.className = 'step-num';
    numEl.textContent = num;

    var badge = document.createElement('div');
    badge.className = 'step-badge ' + badgeType(ev);
    badge.textContent = badgeLabel(ev);

    var content = document.createElement('div');
    content.className = 'step-content';
    var nameEl = document.createElement('div');
    nameEl.className = 'step-name';
    nameEl.textContent = label || '';
    content.appendChild(nameEl);
    if (detail) {
      var detailEl = document.createElement('div');
      detailEl.className = 'step-detail';
      detailEl.textContent = detail.length > 300 ? detail.substring(0, 300) + '...' : detail;
      content.appendChild(detailEl);
      if (detail.length > 300) {
        content.appendChild(makeToggle(detail, detailEl, 'Show more'));
      }
    }

    var timing = document.createElement('div');
    timing.className = 'step-timing';
    timing.textContent = ev.elapsed ? ev.elapsed + 's' : '';

    card.appendChild(numEl);
    card.appendChild(badge);
    card.appendChild(content);
    card.appendChild(timing);
    return card;
  }

  function appendResult(card, result) {
    var text = summarize(result, 99999);
    if (!text) return;
    var contentEl = card.querySelector('.step-content');
    if (!contentEl) return;
    var el = document.createElement('div');
    el.className = 'step-detail step-result';
    el.style.marginTop = '6px';
    el.style.color = '#6b7a8d';
    el.style.borderTop = '1px solid #2a313c';
    el.style.paddingTop = '6px';
    el.textContent = text.length > 300 ? text.substring(0, 300) + '...' : text;
    contentEl.appendChild(el);
    if (text.length > 300) {
      contentEl.appendChild(makeToggle(text, el, 'Show full result'));
    }
  }

  function makeToggle(fullText, el, label) {
    var tog = document.createElement('div');
    tog.className = 'step-detail-toggle visible';
    tog.textContent = label;
    tog.addEventListener('click', function () {
      if (el.classList.contains('expanded')) {
        el.textContent = fullText.substring(0, 300) + '...';
        el.classList.remove('expanded');
        tog.textContent = label;
      } else {
        el.textContent = fullText;
        el.classList.add('expanded');
        tog.textContent = 'Collapse';
      }
    });
    return tog;
  }

  function addCard(card) {
    if (!listEl) return;
    if (listEl.children.length > 0) {
      var conn = document.createElement('div');
      conn.className = 'step-connector' + (card.classList.contains('active') ? ' active' : '');
      listEl.appendChild(conn);
    }
    listEl.appendChild(card);
    card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    var pc = phaseEl ? phaseEl.querySelector('.phase-count') : null;
    if (pc) {
      var n = listEl.querySelectorAll('.step-card').length;
      pc.textContent = n + ' step' + (n !== 1 ? 's' : '');
    }
  }

  function showCompletionBanner(data) {
    var banner = document.createElement('div');
    banner.className = 'completion-banner';
    var title = document.createElement('div');
    title.className = 'title';
    title.textContent = 'Session Complete';
    banner.appendChild(title);
    var stats = document.createElement('div');
    stats.className = 'stats';
    var parts = [];
    if (data.latencyMs) parts.push('<span>' + (data.latencyMs / 1000).toFixed(1) + 's</span> total time');
    if (data.iterations) parts.push('<span>' + data.iterations + '</span> iterations');
    if (data.totalTokens) parts.push('<span>' + formatNum(data.totalTokens) + '</span> tokens');
    if (toolCount > 0) parts.push('<span>' + toolCount + '</span> tool calls');
    if (data.model) parts.push('Model: <span>' + escapeHtml(data.model) + '</span>');
    stats.innerHTML = parts.join('  |  ');
    banner.appendChild(stats);
    flow.appendChild(banner);
    banner.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  // ============================================================
  //  Helpers
  // ============================================================
  function setStatus(state, label) {
    statusPill.className = 'status-pill ' + state;
    statusLbl.textContent = label;
  }

  function formatNum(n) {
    return n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n);
  }

  function escapeHtml(s) {
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  function summarize(val, max) {
    if (!val) return '';
    var s;
    try {
      s = typeof val === 'string' ? val : JSON.stringify(val, null, 2);
    } catch (e) { s = String(val); }
    return max && s.length > max ? s.substring(0, max) + '...' : s;
  }

  function toast(msg) {
    var el = document.getElementById('toast');
    el.textContent = msg;
    el.hidden = false;
    setTimeout(function () { el.hidden = true; }, 4000);
  }

  // ============================================================
  //  Init — start polling immediately
  // ============================================================
  startPolling();

})();
