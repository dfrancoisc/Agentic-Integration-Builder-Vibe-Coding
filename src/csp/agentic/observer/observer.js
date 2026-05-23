/* ============================================================
   Observer — Behind the Scenes live feed
   Connects to /api/agentic/observer/stream?session=latest
   and renders every event as a step-by-step flow.
   ============================================================ */

(function () {
  'use strict';

  // --- DOM refs ---
  var flow       = document.getElementById('flow');
  var emptyState = document.getElementById('empty-state');
  var statusPill = document.getElementById('status-pill');
  var statusDot  = document.getElementById('status-dot');
  var statusLbl  = document.getElementById('status-label');
  var timerVal   = document.getElementById('timer-value');
  var toolsCount = document.getElementById('tools-count');
  var tokensCount= document.getElementById('tokens-count');

  // --- State ---
  var stepNum    = 0;
  var toolCount  = 0;
  var tokenCount = 0;
  var startTime  = null;
  var timerHandle= null;
  var currentPhase = null;
  var phaseEl    = null;
  var listEl     = null;
  var lastCardEl = null;
  var sessionEnded = false;
  var retryCount = 0;
  var maxRetries = 60;  // 60 retries * 5s = 5 min of trying
  var evtSource  = null;

  // --- Auth ---
  function getAuth() {
    var creds = localStorage.getItem('agentic_credentials');
    if (creds) return 'Basic ' + creds;
    // Prompt for credentials
    var user = prompt('IRIS Username:');
    if (!user) return null;
    var pass = prompt('IRIS Password:');
    if (pass === null) return null;
    var encoded = btoa(user + ':' + pass);
    localStorage.setItem('agentic_credentials', encoded);
    return 'Basic ' + encoded;
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
    if (timerHandle) {
      clearInterval(timerHandle);
      timerHandle = null;
    }
  }

  // --- Phase management ---
  // Classify events into phases based on tool names and event types
  function classifyPhase(ev) {
    var type = ev.type;
    var data = ev.data || {};
    var name = (data.name || '').toLowerCase();

    if (type === 'session_start') return 'session';
    if (type === 'session_end')   return 'complete';
    if (type === 'error')         return 'error';
    if (type === 'done')          return 'complete';
    if (type === 'token')         return 'report';

    // tool_start / tool_result classification
    if (type === 'tool_start' || type === 'tool_result') {
      // RAG / catalog tools
      if (name.indexOf('search') >= 0 || name.indexOf('catalog') >= 0 ||
          name.indexOf('describe') >= 0 || name.indexOf('gethl7') >= 0 ||
          name.indexOf('fieldmapping') >= 0 || name.indexOf('field_mapping') >= 0) {
        return 'research';
      }
      // Planning / listing tools
      if (name.indexOf('list') >= 0 || name.indexOf('get') >= 0) {
        return 'research';
      }
      // Build tools
      if (name.indexOf('create') >= 0 || name.indexOf('add') >= 0 ||
          name.indexOf('build') >= 0 || name.indexOf('update') >= 0 ||
          name.indexOf('compile') >= 0 || name.indexOf('ensure') >= 0) {
        return 'build';
      }
      // Test tools
      if (name.indexOf('test') >= 0 || name.indexOf('send') >= 0 ||
          name.indexOf('validate') >= 0 || name.indexOf('dryrun') >= 0 ||
          name.indexOf('dry_run') >= 0 || name.indexOf('simulate') >= 0) {
        return 'test';
      }
      // Approval gate
      if (name.indexOf('confirm') >= 0 || name.indexOf('approve') >= 0) {
        return 'approve';
      }
      return 'build';  // default for unknown tools
    }

    // tool_confirm events
    if (type === 'tool_confirm') return 'approve';

    // status events
    if (type === 'status') return 'status';

    return 'status';
  }

  var phaseLabels = {
    session:  'Session',
    research: 'Research',
    plan:     'Plan',
    build:    'Build',
    test:     'Test',
    approve:  'Approval Gate',
    report:   'Report',
    complete: 'Complete',
    error:    'Error',
    status:   'Status'
  };

  var phaseIcons = {
    session:  'S',
    research: 'R',
    plan:     'P',
    build:    'B',
    test:     'T',
    approve:  'A',
    report:   'F',
    complete: 'C',
    error:    'E',
    status:   'I'
  };

  var phaseClasses = {
    session:  'research',
    research: 'research',
    plan:     'plan',
    build:    'build',
    test:     'test',
    approve:  'plan',
    report:   'report',
    complete: 'report',
    error:    'test',
    status:   'research'
  };

  function ensurePhase(phaseName) {
    if (currentPhase === phaseName && phaseEl) return;
    currentPhase = phaseName;

    // Create phase section
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
    count.setAttribute('data-phase', phaseName);

    header.appendChild(icon);
    header.appendChild(title);
    header.appendChild(count);
    phaseEl.appendChild(header);

    listEl = document.createElement('div');
    listEl.className = 'step-list';
    phaseEl.appendChild(listEl);

    flow.appendChild(phaseEl);
  }

  // --- Badge type for events ---
  function badgeType(ev) {
    var type = ev.type;
    var name = ((ev.data || {}).name || '').toLowerCase();

    if (type === 'tool_confirm')   return 'approve';
    if (type === 'error')          return 'error';
    if (type === 'token')          return 'token';
    if (type === 'status')         return 'status';
    if (type === 'session_start' || type === 'session_end') return 'session';
    if (type === 'done')           return 'session';

    // tool_start / tool_result
    if (name.indexOf('search') >= 0 || name.indexOf('catalog') >= 0 ||
        name.indexOf('describe') >= 0 || name.indexOf('gethl7') >= 0 ||
        name.indexOf('fieldmapping') >= 0 || name.indexOf('field_mapping') >= 0) {
      return 'rag';
    }
    return 'tool';
  }

  function badgeLabel(ev) {
    var b = badgeType(ev);
    var labels = {
      tool: 'TOOL', rag: 'RAG', skill: 'SKILL', approve: 'APPROVE',
      status: 'STATUS', token: 'RESPONSE', error: 'ERROR', session: 'SESSION'
    };
    return labels[b] || b.toUpperCase();
  }

  // --- Render a single step ---
  function renderStep(ev) {
    if (!ev || !ev.type) return;

    // Skip keepalive / padding
    if (ev.type === 'timeout') return;

    // Hide empty state
    if (emptyState) {
      emptyState.style.display = 'none';
    }

    // Start timer on first event
    if (!startTime) startTimer();

    var phase = classifyPhase(ev);
    var data = ev.data || {};

    // --- Special: token events accumulate, don't create individual cards ---
    if (ev.type === 'token') {
      // just update report phase indicator
      ensurePhase('report');
      if (!document.getElementById('report-card')) {
        stepNum++;
        var card = buildCard(stepNum, ev, 'Generating response...');
        card.id = 'report-card';
        addCard(card);
      }
      return;
    }

    // --- Special: done event — show completion banner ---
    if (ev.type === 'done') {
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

    // --- Special: session_end ---
    if (ev.type === 'session_end') {
      sessionEnded = true;
      return;
    }

    // --- Special: session_start ---
    if (ev.type === 'session_start') {
      setStatus('connected', 'Connected');
      ensurePhase('session');
      stepNum++;
      var label = 'Session started';
      if (data.user) label += ' by ' + data.user;
      if (data.namespace) label += ' in ' + data.namespace;
      var card = buildCard(stepNum, ev, label);
      card.classList.add('done');
      addCard(card);
      return;
    }

    // --- Special: status ---
    if (ev.type === 'status') {
      var msg = data.message || data.phase || 'Status update';
      if (data.phase === 'ready') {
        msg = 'Session ready (' + (data.turnsReplayed || 0) + ' turns replayed)';
      }
      // Don't create a card for rate-limit waits — update the last status card
      ensurePhase('status');
      stepNum++;
      var card = buildCard(stepNum, ev, msg);
      addCard(card);
      return;
    }

    // --- Special: error ---
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

      // Check for approval gate
      if (phase === 'approve') {
        card.classList.add('approve-gate');
      }

      addCard(card);
      return;
    }

    // --- tool_result ---
    if (ev.type === 'tool_result') {
      var name = data.name || '(tool)';
      // Find the matching tool_start card and mark it done
      var activeCards = flow.querySelectorAll('.step-card.active[data-tool="' + name + '"]');
      if (activeCards.length > 0) {
        var target = activeCards[activeCards.length - 1];
        target.classList.remove('active');
        target.classList.add('done');

        // Add result snippet to the card
        var resultText = '';
        if (data.result) {
          try {
            resultText = typeof data.result === 'string' ? data.result : JSON.stringify(data.result, null, 2);
          } catch (e) { resultText = String(data.result); }
        }
        if (resultText) {
          var truncated = resultText.length > 300 ? resultText.substring(0, 300) + '...' : resultText;
          var resultEl = target.querySelector('.step-result');
          if (!resultEl) {
            resultEl = document.createElement('div');
            resultEl.className = 'step-detail step-result';
            resultEl.style.marginTop = '6px';
            resultEl.style.color = '#6b7a8d';
            resultEl.style.borderTop = '1px solid #2a313c';
            resultEl.style.paddingTop = '6px';
            var contentEl = target.querySelector('.step-content');
            if (contentEl) contentEl.appendChild(resultEl);
          }
          resultEl.textContent = truncated;

          if (resultText.length > 300) {
            var toggle = document.createElement('div');
            toggle.className = 'step-detail-toggle visible';
            toggle.textContent = 'Show full result';
            toggle.addEventListener('click', (function(full, el, tog) {
              return function() {
                if (el.classList.contains('expanded')) {
                  el.textContent = full.substring(0, 300) + '...';
                  el.classList.remove('expanded');
                  tog.textContent = 'Show full result';
                } else {
                  el.textContent = full;
                  el.classList.add('expanded');
                  tog.textContent = 'Collapse';
                }
              };
            })(resultText, resultEl, toggle));
            var contentEl = target.querySelector('.step-content');
            if (contentEl) contentEl.appendChild(toggle);
          }
        }
        // Update timing
        if (ev.elapsed) {
          var timingEl = target.querySelector('.step-timing');
          if (timingEl) timingEl.textContent = ev.elapsed + 's';
        }
      } else {
        // No matching start card — create a standalone result card
        ensurePhase(phase);
        stepNum++;
        var resultSnippet = '';
        if (data.result) {
          try {
            resultSnippet = typeof data.result === 'string' ? data.result : JSON.stringify(data.result, null, 2);
            if (resultSnippet.length > 200) resultSnippet = resultSnippet.substring(0, 200) + '...';
          } catch (e) {}
        }
        var card = buildCard(stepNum, ev, name + ' (result)', resultSnippet);
        card.classList.add('done');
        addCard(card);
      }

      // Update timing
      if (ev.elapsed) {
        timerVal.textContent = ev.elapsed + 's';
      }
      return;
    }

    // --- tool_confirm ---
    if (ev.type === 'tool_confirm') {
      ensurePhase('approve');
      stepNum++;
      var label = 'Approval requested: ' + (data.name || data.tool || 'unknown tool');
      var card = buildCard(stepNum, ev, label);
      card.classList.add('approve-gate', 'active');
      addCard(card);
      return;
    }

    // --- Fallback: unknown event type ---
    ensurePhase('status');
    stepNum++;
    var card = buildCard(stepNum, ev, ev.type);
    addCard(card);
  }

  // --- Build a step card DOM element ---
  function buildCard(num, ev, label, detail) {
    var card = document.createElement('div');
    card.className = 'step-card';

    // Step number
    var numEl = document.createElement('div');
    numEl.className = 'step-num';
    numEl.textContent = num;

    // Badge
    var badge = document.createElement('div');
    badge.className = 'step-badge ' + badgeType(ev);
    badge.textContent = badgeLabel(ev);

    // Content
    var content = document.createElement('div');
    content.className = 'step-content';

    var nameEl = document.createElement('div');
    nameEl.className = 'step-name';
    nameEl.textContent = label || '';
    content.appendChild(nameEl);

    if (detail) {
      var detailEl = document.createElement('div');
      detailEl.className = 'step-detail';
      var truncated = detail.length > 300 ? detail.substring(0, 300) + '...' : detail;
      detailEl.textContent = truncated;
      content.appendChild(detailEl);

      if (detail.length > 300) {
        var toggle = document.createElement('div');
        toggle.className = 'step-detail-toggle visible';
        toggle.textContent = 'Show more';
        toggle.addEventListener('click', (function(full, el, tog) {
          return function() {
            if (el.classList.contains('expanded')) {
              el.textContent = full.substring(0, 300) + '...';
              el.classList.remove('expanded');
              tog.textContent = 'Show more';
            } else {
              el.textContent = full;
              el.classList.add('expanded');
              tog.textContent = 'Collapse';
            }
          };
        })(detail, detailEl, toggle));
        content.appendChild(toggle);
      }
    }

    // Timing
    var timing = document.createElement('div');
    timing.className = 'step-timing';
    timing.textContent = ev.elapsed ? ev.elapsed + 's' : '';

    card.appendChild(numEl);
    card.appendChild(badge);
    card.appendChild(content);
    card.appendChild(timing);

    return card;
  }

  // --- Add card to current phase list ---
  function addCard(card) {
    if (!listEl) return;

    // Add connector line between cards (except the first)
    if (listEl.children.length > 0) {
      var connector = document.createElement('div');
      connector.className = 'step-connector';
      if (card.classList.contains('active')) connector.classList.add('active');
      listEl.appendChild(connector);
    }

    listEl.appendChild(card);
    lastCardEl = card;

    // Scroll into view
    card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

    // Update phase count
    var phaseCountEl = phaseEl ? phaseEl.querySelector('.phase-count') : null;
    if (phaseCountEl) {
      var cards = listEl.querySelectorAll('.step-card');
      phaseCountEl.textContent = cards.length + ' step' + (cards.length !== 1 ? 's' : '');
    }
  }

  // --- Completion banner ---
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

  // --- Status pill ---
  function setStatus(state, label) {
    statusPill.className = 'status-pill ' + state;
    statusLbl.textContent = label;
  }

  // --- Helpers ---
  function formatNum(n) {
    if (n >= 1000) return (n / 1000).toFixed(1) + 'k';
    return String(n);
  }

  function escapeHtml(s) {
    var div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  function toast(msg) {
    var el = document.getElementById('toast');
    el.textContent = msg;
    el.hidden = false;
    setTimeout(function () { el.hidden = true; }, 4000);
  }

  // --- SSE connection ---
  // EventSource doesn't support custom headers (for auth). We use
  // fetch() with ReadableStream to parse the SSE manually, passing
  // the Authorization header.
  function connect() {
    var auth = getAuth();
    if (!auth) {
      setStatus('error', 'No credentials');
      return;
    }

    setStatus('waiting', 'Waiting for session...');

    var url = '/api/agentic/observer/stream?session=latest';
    fetch(url, {
      method: 'GET',
      headers: { 'Authorization': auth },
      credentials: 'include'
    }).then(function (response) {
      if (!response.ok) {
        if (response.status === 401) {
          localStorage.removeItem('agentic_credentials');
          setStatus('error', 'Auth failed');
          toast('Authentication failed. Reload to re-enter credentials.');
          return;
        }
        throw new Error('HTTP ' + response.status);
      }

      retryCount = 0;
      var reader = response.body.getReader();
      var decoder = new TextDecoder();
      var buffer = '';

      function pump() {
        return reader.read().then(function (result) {
          if (result.done) {
            // Stream ended — retry after delay if session didn't end
            if (!sessionEnded) {
              setTimeout(function () { reconnect(); }, 3000);
            }
            return;
          }

          buffer += decoder.decode(result.value, { stream: true });

          // Parse SSE frames from buffer
          var lines = buffer.split('\n');
          buffer = lines.pop(); // keep incomplete line

          var eventType = null;
          var eventData = null;

          for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (line.indexOf('event: ') === 0) {
              eventType = line.substring(7).trim();
            } else if (line.indexOf('data: ') === 0) {
              eventData = line.substring(6);
            } else if (line === '' && eventType === 'feed' && eventData) {
              // Complete event — parse the feed envelope
              try {
                var envelope = JSON.parse(eventData);
                renderStep(envelope);
              } catch (e) {
                // Ignore parse errors (padding, comments)
              }
              eventType = null;
              eventData = null;
            } else if (line === '' && eventType === 'error' && eventData) {
              try {
                var errObj = JSON.parse(eventData);
                setStatus('error', errObj.error || 'Unknown error');
                toast(errObj.error || 'Stream error');
              } catch (e) {}
              eventType = null;
              eventData = null;
            } else if (line === '') {
              // Reset on empty line (end of event)
              eventType = null;
              eventData = null;
            }
            // Skip comment lines (start with ':')
          }

          return pump();
        });
      }

      return pump();
    }).catch(function (err) {
      console.error('Observer stream error:', err);
      if (!sessionEnded) {
        setTimeout(function () { reconnect(); }, 3000);
      }
    });
  }

  function reconnect() {
    retryCount++;
    if (retryCount > maxRetries) {
      setStatus('error', 'Max retries exceeded');
      toast('Could not connect to observer stream. Reload the page to try again.');
      return;
    }
    setStatus('waiting', 'Reconnecting (' + retryCount + ')...');
    connect();
  }

  // --- Polling mode (fallback) ---
  // If the fetch/ReadableStream approach fails (older browsers), fall
  // back to polling /observer/sessions every 3s and rendering events
  // from the JSON sessions endpoint. Not implemented yet — the
  // ReadableStream SSE approach works in all modern browsers.

  // --- Init ---
  connect();

})();
