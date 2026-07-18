/* agentic_interop — AI launchers inside the IRIS Interop Editor.
 *
 * Two entry points, matching the established new-interoperability-health
 * pattern (which the customer pointed to as the reference):
 *
 *   1. "AI Hub" tab — appended to .dashboard alongside Production
 *      Configuration / Rule Editor / Data Transformation Editor / etc.
 *      Star icon, indigo accent, opens the admin (configuration) in a
 *      full-screen overlay. Configuration is cross-namespace by design.
 *
 *   2. Chat icon — inserted into mat-toolbar-row (top header) right
 *      BEFORE the namespace dropdown. Chat-bubble glyph + green dot.
 *      Opens the chat in a right-side SLIDE-IN panel (~min(840, 65vw),
 *      full height) with a dimmed editor backdrop. The user keeps the
 *      Interop Editor visible while the agent answers.
 *
 * Both inject custom DOM only; we never modify shipped Angular nodes
 * inline. A debounced MutationObserver re-injects after Angular
 * re-renders. Hidden during the login screen via a body class.
 *
 * Auth bridge is preserved from the previous design: window.fetch and
 * XMLHttpRequest.setRequestHeader are intercepted at script load to
 * capture the SPA's IRIS-issued JWT, which is then handed to the
 * iframes via postMessage so they authenticate against /api/agentic
 * (JWTAuthEnabled=1, GroupById=%ISCMgtPortal) without a second login.
 *
 * Namespace from window.location.search?$NAMESPACE is forwarded both
 * via URL param and postMessage so the chat can scope itself to the
 * user's active namespace before the user types anything.
 */
(function () {
    'use strict';

    if (window.__agenticInject) return;
    window.__agenticInject = true;

    var TAB_MARK = 'agentic-tab';        // .dashboard tab marker
    var HDR_MARK = 'agentic-hdr-chat';   // mat-toolbar-row chat icon marker
    var FAB_ID = 'agentic-fab';          // floating launcher (host-agnostic)
    var CONFIG_OVERLAY_ID = 'agentic-config-overlay';
    var CHAT_OVERLAY_ID = 'agentic-chat-overlay';
    var AUD_MARK = 'agentic-hdr-audit';  // mat-toolbar-row audit icon marker
    var LOAD_MARK = 'agentic-hdr-load';  // mat-toolbar-row "Load FHIR Data" icon marker
    var AUD_NAV_MARK = 'agentic-nav-audit';  // (unused) left mat-sidenav nav-list item marker
    var LOAD_NAV_MARK = 'agentic-nav-load';  // (unused) left mat-sidenav nav-list item marker
    var AUD_OVERLAY_ID = 'agentic-audit-overlay';  // left-slide audit panel
    var CLEAN_PROD_MARK = 'agentic-clean-prod';
    var CLEAN_ART_MARK  = 'agentic-clean-art';
    var SPEC_MARK = 'agentic-spec-tab';          // .dashboard "Interface Spec" tab
    var SPEC_OVERLAY_ID = 'agentic-spec-overlay';

    var STATE = { bearer: '', bearerExp: 0 };

    /* ---------------- self config (chatbot key + mode + title) ----------
     * Read from THIS script tag's own query string, e.g.
     *   <script src="/agentic/inject.js?chatbot=fhir-management&mode=floating&title=FHIR%20Assistant">
     * Defaults reproduce the original Interop-Editor behavior, so the
     * existing InteropEditorPatch keeps working unchanged.
     *   chatbot — the Chatbot config key; forwarded to the chat iframe,
     *             which the backend maps to an %AI.Agent.
     *   mode    — "interop" (splice into the editor chrome) | "floating"
     *             (host-agnostic bottom-right launcher).
     *   title   — panel/launcher label.
     */
    function selfParam(name) {
        try {
            var src = (document.currentScript && document.currentScript.src) || '';
            if (!src) {
                var ss = document.getElementsByTagName('script');
                for (var i = 0; i < ss.length; i++) {
                    if (ss[i].src && ss[i].src.indexOf('agentic/inject.js') >= 0) { src = ss[i].src; break; }
                }
            }
            return new URLSearchParams(src.split('?')[1] || '').get(name) || '';
        } catch (e) { return ''; }
    }
    var CHATBOT_KEY = selfParam('chatbot') || 'interop';
    var INJECT_MODE = selfParam('mode') || 'interop';
    var CHAT_TITLE  = selfParam('title') || 'Agentic Interoperability Builder';

    /* ---------------- JWT helpers ---------------- */

    // Decode JWT payload without verification (just reads exp claim).
    function jwtExp(bearerStr) {
        try {
            var token = bearerStr.replace(/^Bearer\s+/i, '');
            var parts = token.split('.');
            if (parts.length !== 3) return 0;
            var b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
            // Pad to 4-char boundary
            while (b64.length % 4) b64 += '=';
            var payload = JSON.parse(atob(b64));
            return payload.exp || 0;
        } catch (e) { return 0; }
    }

    function tokenSecondsLeft() {
        if (!STATE.bearerExp) return 99999; // no exp => assume long-lived
        return Math.floor(STATE.bearerExp - Date.now() / 1000);
    }

    // Try to trigger a fresh Bearer capture by making a lightweight
    // API call through the Angular SPA's own fetch path. The wrapped
    // window.fetch will capture any outgoing Authorization header.
    // This only helps if the Angular app's HTTP interceptor attaches
    // a FRESH token to outgoing requests. If the Angular app is also
    // using the expired token, this is a no-op — the caller falls
    // through to the stale token and chat.js handles the 401.
    var refreshInFlight = false;
    function tryRefreshBearer() {
        if (refreshInFlight) return Promise.resolve();
        refreshInFlight = true;
        return window.fetch('/api/interop-editors/', {
            method: 'GET',
            cache: 'no-store'
        }).catch(function(){}).then(function(){ refreshInFlight = false; });
    }

    /* ---------------- Bearer + namespace capture ---------------- */

    function captureFromHeaders(headers) {
        try {
            var auth;
            if (headers instanceof Headers) {
                auth = headers.get('Authorization') || headers.get('authorization');
            } else if (Array.isArray(headers)) {
                for (var i = 0; i < headers.length; i++) {
                    if (Array.isArray(headers[i]) && /^authorization$/i.test(headers[i][0])) {
                        auth = headers[i][1]; break;
                    }
                }
            } else if (headers && typeof headers === 'object') {
                auth = headers.Authorization || headers.authorization;
            }
            if (typeof auth === 'string' && auth.indexOf('Bearer ') === 0) {
                STATE.bearer = auth;
                STATE.bearerExp = jwtExp(auth);
            }
        } catch {}
    }

    var origFetch = window.fetch;
    window.fetch = function (input, init) {
        try {
            if (input instanceof Request) captureFromHeaders(input.headers);
            if (init && init.headers) captureFromHeaders(init.headers);
        } catch {}
        return origFetch.apply(this, arguments);
    };

    var origSet = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
        try {
            if (/^authorization$/i.test(name) && typeof value === 'string' && value.indexOf('Bearer ') === 0) {
                STATE.bearer = value;
                STATE.bearerExp = jwtExp(value);
            }
        } catch {}
        return origSet.apply(this, arguments);
    };

    function currentNamespace() {
        try {
            var p = new URLSearchParams(window.location.search);
            return p.get('$NAMESPACE') || p.get('%24NAMESPACE') || '';
        } catch { return ''; }
    }

    window.addEventListener('message', function (e) {
        var d = e.data || {};
        if (d && d.type === 'agentic:auth:request') {
            var respond = function () {
                try {
                    if (e.source && e.source.postMessage) {
                        e.source.postMessage({
                            type: 'agentic:auth:response',
                            bearer: STATE.bearer || '',
                            namespace: currentNamespace(),
                            tokenSecondsLeft: tokenSecondsLeft()
                        }, '*');
                    }
                } catch {}
            };
            // If the token is expired or about to expire, try to refresh
            // before responding. This gives the Angular SPA a chance to
            // issue a fresh token via its own HTTP interceptor.
            if (tokenSecondsLeft() < 30) {
                tryRefreshBearer().then(respond);
            } else {
                respond();
            }
        }
        if (d && d.type === 'agentic:close-chat') closeChat();
        if (d && d.type === 'agentic:close-config') closeConfig();
        if (d && d.type === 'agentic:close-spec') closeSpec();
        // Interface Specification Builder handed off a completed spec: it has
        // already staged the prompt in localStorage. Swap the spec panel for
        // the chat panel; chat.js picks the prompt up as it finishes booting.
        if (d && d.type === 'agentic:spec:send') {
            closeSpec();
            setTimeout(openChat, 180);
        }
    });

    /* ---------------- styles ---------------- */

    function injectStyles() {
        if (document.getElementById('agentic-inject-styles')) return;
        var s = document.createElement('style');
        s.id = 'agentic-inject-styles';
        s.textContent = [
            // .dashboard "AI Hub" tab (matches the existing tab look)
            '.dashboard .navbuttons.' + TAB_MARK + ' {',
            '  display:flex; flex:0 1 auto;',
            '  margin:5px; height:32px; box-sizing:border-box;',
            '  border:1px solid #cbcbcb; background:#fff;',
            '  cursor:pointer; transition:background .15s, border-color .15s;',
            '}',
            '.dashboard .navbuttons.' + TAB_MARK + ':hover {',
            '  background:rgba(79,70,229,.08); border-color:#4f46e5;',
            '}',
            '.dashboard .navbuttons.' + TAB_MARK + ' .agentic-tab-inner {',
            '  display:flex; align-items:center; gap:6px; padding:0 10px;',
            '  font-family:-apple-system,"Noto Sans",system-ui,sans-serif;',
            '  font-size:13px; font-weight:600; color:#4f46e5;',
            '}',
            '.dashboard .navbuttons.' + TAB_MARK + ' .agentic-tab-inner svg { width:18px; height:18px; }',
            '.dashboard .navbuttons.' + TAB_MARK + '.is-active {',
            '  background:#4f46e5; border-color:#4f46e5;',
            '}',
            '.dashboard .navbuttons.' + TAB_MARK + '.is-active .agentic-tab-inner { color:#fff; }',
            '.dashboard .navbuttons.' + TAB_MARK + '.is-active .agentic-tab-inner svg path { fill:#fff !important; }',

            // Cleanup buttons — amber for Clean Productions, red for Delete Artifacts
            '.dashboard .navbuttons.' + CLEAN_PROD_MARK + ',',
            '.dashboard .navbuttons.' + CLEAN_ART_MARK + ' {',
            '  display:flex; flex:0 1 auto;',
            '  margin:5px; height:32px; box-sizing:border-box;',
            '  border:1px solid #cbcbcb; background:#fff;',
            '  cursor:pointer; transition:background .15s, border-color .15s;',
            '}',
            '.dashboard .navbuttons.' + CLEAN_PROD_MARK + ':hover {',
            '  background:rgba(217,119,6,.08); border-color:#d97706;',
            '}',
            '.dashboard .navbuttons.' + CLEAN_ART_MARK + ':hover {',
            '  background:rgba(220,38,38,.08); border-color:#dc2626;',
            '}',
            '.dashboard .navbuttons.' + CLEAN_PROD_MARK + ' .agentic-tab-inner {',
            '  display:flex; align-items:center; gap:6px; padding:0 10px;',
            '  font-family:-apple-system,"Noto Sans",system-ui,sans-serif;',
            '  font-size:13px; font-weight:600; color:#d97706;',
            '}',
            '.dashboard .navbuttons.' + CLEAN_ART_MARK + ' .agentic-tab-inner {',
            '  display:flex; align-items:center; gap:6px; padding:0 10px;',
            '  font-family:-apple-system,"Noto Sans",system-ui,sans-serif;',
            '  font-size:13px; font-weight:600; color:#dc2626;',
            '}',
            '.dashboard .navbuttons.' + CLEAN_PROD_MARK + '.is-busy,',
            '.dashboard .navbuttons.' + CLEAN_ART_MARK + '.is-busy {',
            '  opacity:0.6; pointer-events:none;',
            '}',

            // "Interface Spec" tab — teal accent, distinct from AI Settings
            '.dashboard .navbuttons.' + SPEC_MARK + ' {',
            '  display:flex; flex:0 1 auto;',
            '  margin:5px; height:32px; box-sizing:border-box;',
            '  border:1px solid #cbcbcb; background:#fff;',
            '  cursor:pointer; transition:background .15s, border-color .15s;',
            '}',
            '.dashboard .navbuttons.' + SPEC_MARK + ':hover {',
            '  background:rgba(13,148,136,.08); border-color:#0d9488;',
            '}',
            '.dashboard .navbuttons.' + SPEC_MARK + ' .agentic-tab-inner {',
            '  display:flex; align-items:center; gap:6px; padding:0 10px;',
            '  font-family:-apple-system,"Noto Sans",system-ui,sans-serif;',
            '  font-size:13px; font-weight:600; color:#0d9488;',
            '}',
            '.dashboard .navbuttons.' + SPEC_MARK + '.is-active { background:#0d9488; border-color:#0d9488; }',
            '.dashboard .navbuttons.' + SPEC_MARK + '.is-active .agentic-tab-inner { color:#fff; }',

            // Interface Spec full-screen overlay (dark, matches the spec page)
            '#' + SPEC_OVERLAY_ID + ' { position:fixed; inset:0; z-index:99999; background:#0b0d11; display:none; }',
            '#' + SPEC_OVERLAY_ID + '.open { display:flex; flex-direction:column; }',
            '#' + SPEC_OVERLAY_ID + ' .bar {',
            '  flex:0 0 auto; height:44px; background:#0d9488;',
            '  display:flex; align-items:center; justify-content:space-between;',
            '  padding:0 18px; color:white;',
            '  font:600 14px/1 -apple-system,"Noto Sans",system-ui,sans-serif;',
            '}',
            '#' + SPEC_OVERLAY_ID + ' .bar .close {',
            '  background:transparent; color:white; border:1px solid rgba(255,255,255,0.35);',
            '  width:28px; height:28px; border-radius:4px; cursor:pointer; font-size:14px;',
            '}',
            '#' + SPEC_OVERLAY_ID + ' .bar .close:hover { background:rgba(255,255,255,0.14); }',
            '#' + SPEC_OVERLAY_ID + ' iframe { flex:1; width:100%; border:0; background:#0b0d11; }',

            // Top mat-toolbar chat icon
            'mat-toolbar-row .dropdown.' + HDR_MARK + ' { display:flex; align-items:center; }',
            'mat-toolbar-row .dropdown.' + HDR_MARK + ' button {',
            '  background:transparent; border:0; cursor:pointer;',
            '  padding:6px 10px; display:inline-flex; align-items:center;',
            '  color:#4f46e5; position:relative;',
            '}',
            'mat-toolbar-row .dropdown.' + HDR_MARK + ' button:hover { background:rgba(79,70,229,.08); border-radius:6px; }',
            'mat-toolbar-row .dropdown.' + HDR_MARK + ' svg { width:22px; height:22px; }',
            'mat-toolbar-row .dropdown.' + HDR_MARK + ' .dot {',
            '  position:absolute; top:6px; right:8px;',
            '  width:8px; height:8px; border-radius:50%;',
            '  background:#10b981; border:1.5px solid white;',
            '}',

            // Login-mode hide
            'body.agentic-login-mode .' + TAB_MARK + ',',
            'body.agentic-login-mode .' + HDR_MARK + ',',
            'body.agentic-login-mode .' + AUD_NAV_MARK + ',',
            'body.agentic-login-mode .' + LOAD_NAV_MARK + ',',
            'body.agentic-login-mode .' + CLEAN_PROD_MARK + ',',
            'body.agentic-login-mode .' + CLEAN_ART_MARK + ',',
            'body.agentic-login-mode .' + SPEC_MARK + ',',
            'body.agentic-login-mode #' + SPEC_OVERLAY_ID + ',',
            'body.agentic-login-mode #' + CONFIG_OVERLAY_ID + ',',
            'body.agentic-login-mode #' + AUD_OVERLAY_ID + ',',
            'body.agentic-login-mode #' + CHAT_OVERLAY_ID + ' { display:none !important; }',
            'body.agentic-login-mode #' + FAB_ID + ' { display:none !important; }',

            // Floating launcher (host-agnostic — e.g. FHIR Management page)
            '#' + FAB_ID + ' {',
            '  position:fixed; right:24px; bottom:24px; z-index:99998;',
            '  width:56px; height:56px; border-radius:50%; border:0; cursor:pointer;',
            '  background:#4f46e5; box-shadow:0 6px 20px rgba(79,70,229,.45);',
            '  display:flex; align-items:center; justify-content:center;',
            '  transition:transform .15s, box-shadow .15s;',
            '}',
            '#' + FAB_ID + ':hover { transform:translateY(-2px); box-shadow:0 10px 26px rgba(79,70,229,.55); }',
            '#' + FAB_ID + ' svg { width:26px; height:26px; }',
            '#' + FAB_ID + ' .agentic-fab-dot {',
            '  position:absolute; top:12px; right:12px; width:10px; height:10px;',
            '  border-radius:50%; background:#10b981; border:2px solid #4f46e5;',
            '}',

            // Chat right-slide panel
            '#' + CHAT_OVERLAY_ID + ' {',
            '  position:fixed; inset:0; z-index:99999;',
            '  background:rgba(15,23,42,0.32); display:none;',
            '}',
            '#' + CHAT_OVERLAY_ID + '.open { display:block; }',
            '#' + CHAT_OVERLAY_ID + ' .panel {',
            '  position:absolute; top:0; right:0; bottom:0;',
            '  width:min(840px, 65vw);',
            '  background:#0f1115;',
            '  box-shadow:-12px 0 48px rgba(0,0,0,0.5);',
            '  display:flex; flex-direction:column;',
            '  transform:translateX(100%); transition:transform 220ms ease-out;',
            '}',
            '#' + CHAT_OVERLAY_ID + '.open .panel { transform:translateX(0); }',
            '#' + CHAT_OVERLAY_ID + ' .bar {',
            '  flex:0 0 auto; height:42px; background:#1c2129;',
            '  display:flex; align-items:center; justify-content:space-between;',
            '  padding:0 14px; color:#e6e8eb; border-bottom:1px solid #2a313c;',
            '  font:600 13px/1 system-ui,sans-serif;',
            '}',
            '#' + CHAT_OVERLAY_ID + ' .bar .close {',
            '  background:transparent; color:#8b95a6; border:1px solid #2a313c;',
            '  width:26px; height:26px; border-radius:4px; cursor:pointer; font-size:13px;',
            '}',
            '#' + CHAT_OVERLAY_ID + ' .bar .close:hover { background:rgba(255,255,255,0.06); color:#e6e8eb; }',
            '#' + CHAT_OVERLAY_ID + ' .bar .obs-link {',
            '  color:#4ec9b0; font-size:11px; font-weight:400; text-decoration:none;',
            '  margin-left:auto; margin-right:12px; cursor:pointer;',
            '  opacity:0.7; transition:opacity 120ms;',
            '}',
            '#' + CHAT_OVERLAY_ID + ' .bar .obs-link:hover { opacity:1; text-decoration:underline; }',
            '#' + CHAT_OVERLAY_ID + ' iframe { flex:1; width:100%; border:0; background:#0f1115; }',

            // Audit overlay (LEFT-slide panel)
            '#' + AUD_OVERLAY_ID + ' { position:fixed; inset:0; z-index:99999; background:rgba(15,23,42,0.32); display:none; }',
            '#' + AUD_OVERLAY_ID + '.open { display:block; }',
            '#' + AUD_OVERLAY_ID + ' .panel {',
            '  position:absolute; top:0; left:0; bottom:0; width:min(720px, 60vw);',
            '  background:#0b0d11; box-shadow:12px 0 48px rgba(0,0,0,0.5);',
            '  display:flex; flex-direction:column;',
            '  transform:translateX(-100%); transition:transform 220ms ease-out;',
            '}',
            '#' + AUD_OVERLAY_ID + '.open .panel { transform:translateX(0); }',
            '#' + AUD_OVERLAY_ID + ' .bar {',
            '  flex:0 0 auto; height:42px; background:#1c2129; display:flex; align-items:center;',
            '  justify-content:space-between; padding:0 14px; color:#e6e8eb;',
            '  border-bottom:1px solid #2a313c; font:600 13px/1 system-ui,sans-serif;',
            '}',
            '#' + AUD_OVERLAY_ID + ' .bar .close { background:transparent; color:#8b95a6; border:1px solid #2a313c; width:26px; height:26px; border-radius:4px; cursor:pointer; font-size:13px; }',
            '#' + AUD_OVERLAY_ID + ' .bar .close:hover { background:rgba(255,255,255,0.06); color:#e6e8eb; }',
            '#' + AUD_OVERLAY_ID + ' iframe { flex:1; width:100%; border:0; background:#0b0d11; }',

            // Config full-screen overlay
            '#' + CONFIG_OVERLAY_ID + ' {',
            '  position:fixed; inset:0; z-index:99999;',
            '  background:#fff; display:none;',
            '}',
            '#' + CONFIG_OVERLAY_ID + '.open { display:flex; flex-direction:column; }',
            '#' + CONFIG_OVERLAY_ID + ' .bar {',
            '  flex:0 0 auto; height:44px; background:#4f46e5;',
            '  display:flex; align-items:center; justify-content:space-between;',
            '  padding:0 18px; color:white;',
            '  font:600 14px/1 -apple-system,"Noto Sans",system-ui,sans-serif;',
            '}',
            '#' + CONFIG_OVERLAY_ID + ' .bar .title { display:flex; align-items:center; gap:8px; }',
            '#' + CONFIG_OVERLAY_ID + ' .bar .close {',
            '  background:transparent; color:white; border:1px solid rgba(255,255,255,0.3);',
            '  width:28px; height:28px; border-radius:4px; cursor:pointer; font-size:14px;',
            '}',
            '#' + CONFIG_OVERLAY_ID + ' .bar .close:hover { background:rgba(255,255,255,0.12); }',
            '#' + CONFIG_OVERLAY_ID + ' iframe { flex:1; width:100%; border:0; background:white; }'
        ].join('\n');
        document.head.appendChild(s);
    }

    /* ---------------- chat overlay (right-slide) ---------------- */

    function buildChatOverlay() {
        if (document.getElementById(CHAT_OVERLAY_ID)) return;
        var overlay = document.createElement('div');
        overlay.id = CHAT_OVERLAY_ID;
        overlay.innerHTML =
            '<div class="panel">' +
              '<div class="bar">' +
                '<span>' + (CHAT_TITLE || 'Agentic Interoperability Builder') + '</span>' +
                '<a class="obs-link" title="Open Observer in a new tab — shows every internal step as the agent works">Observer</a>' +
                '<button class="close" type="button" title="Close">✕</button>' +
              '</div>' +
              '<iframe src="about:blank" title="Agentic Interoperability Builder"></iframe>' +
            '</div>';
        document.body.appendChild(overlay);
        overlay.querySelector('.obs-link').addEventListener('click', function () {
            window.open('/agentic/observer/index.html?split', '_blank');
        });
        overlay.querySelector('.close').addEventListener('click', closeChat);
        overlay.addEventListener('click', function (e) { if (e.target === overlay) closeChat(); });
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && overlay.classList.contains('open')) closeChat();
        });
    }

    function openChat() {
        buildChatOverlay();
        var overlay = document.getElementById(CHAT_OVERLAY_ID);
        var iframe = overlay.querySelector('iframe');
        var ns = currentNamespace();
        var url = '/agentic/chat/index.html?via=interop&t=' + Date.now()
            + '&chatbot=' + encodeURIComponent(CHATBOT_KEY)
            + (CHAT_TITLE ? '&title=' + encodeURIComponent(CHAT_TITLE) : '')
            + (ns ? '&namespace=' + encodeURIComponent(ns) : '');
        iframe.src = url;
        overlay.classList.add('open');
    }

    function closeChat() {
        var overlay = document.getElementById(CHAT_OVERLAY_ID);
        if (!overlay) return;
        overlay.classList.remove('open');
        var iframe = overlay.querySelector('iframe');
        if (iframe) iframe.src = 'about:blank';
    }

    /* ---------------- audit overlay (left-slide) ---------------- */

    function buildAuditOverlay() {
        if (document.getElementById(AUD_OVERLAY_ID)) return;
        var overlay = document.createElement('div');
        overlay.id = AUD_OVERLAY_ID;
        overlay.innerHTML =
            '<div class="panel">' +
              '<div class="bar">' +
                '<span class="agentic-lp-title">FHIR Server Audit</span>' +
                '<button class="close" type="button" title="Close">✕</button>' +
              '</div>' +
              '<iframe src="about:blank" title="FHIR panel"></iframe>' +
            '</div>';
        document.body.appendChild(overlay);
        overlay.querySelector('.close').addEventListener('click', closeAudit);
        overlay.addEventListener('click', function (e) { if (e.target === overlay) closeAudit(); });
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && overlay.classList.contains('open')) closeAudit();
        });
    }

    // Generic left-slide panel — used by both the Audit and Load FHIR Data
    // menu items (one panel at a time). src = page to load, title = bar label.
    function openLeftPanel(src, title) {
        buildAuditOverlay();
        var overlay = document.getElementById(AUD_OVERLAY_ID);
        var ns = currentNamespace();
        var t = overlay.querySelector('.agentic-lp-title');
        if (t) t.textContent = title || 'FHIR';
        overlay.querySelector('iframe').src = src + (src.indexOf('?') < 0 ? '?' : '&') + 't=' + Date.now() + (ns ? '&ns=' + encodeURIComponent(ns) : '');
        overlay.classList.add('open');
    }
    function openAudit() { openLeftPanel('/agentic/audit/index.html', 'FHIR Server Audit'); }
    function openLoad()  { openLeftPanel('/agentic/upload/index.html', 'Load FHIR Data'); }

    function closeAudit() {
        var overlay = document.getElementById(AUD_OVERLAY_ID);
        if (!overlay) return;
        overlay.classList.remove('open');
        var iframe = overlay.querySelector('iframe');
        if (iframe) iframe.src = 'about:blank';
    }

    /* ---------------- config overlay (full-screen) ---------------- */

    function buildConfigOverlay() {
        if (document.getElementById(CONFIG_OVERLAY_ID)) return;
        var overlay = document.createElement('div');
        overlay.id = CONFIG_OVERLAY_ID;
        overlay.innerHTML =
            '<div class="bar">' +
              '<div class="title">' +
                '<svg viewBox="0 0 20 20" width="16" height="16"><path d="M10 1l2.2 5 5.3.4-4 3.6 1.2 5.2L10 12.6 5.3 15.2l1.2-5.2-4-3.6L7.8 6 10 1z" fill="#fde047"/></svg>' +
                '<span>AI Settings</span>' +
              '</div>' +
              '<button class="close" type="button" title="Close">✕</button>' +
            '</div>' +
            '<iframe src="about:blank" title="AI Settings"></iframe>';
        document.body.appendChild(overlay);
        overlay.querySelector('.close').addEventListener('click', closeConfig);
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && overlay.classList.contains('open')) closeConfig();
        });
    }

    function openConfig() {
        buildConfigOverlay();
        var overlay = document.getElementById(CONFIG_OVERLAY_ID);
        var iframe = overlay.querySelector('iframe');
        var ns = currentNamespace();
        var url = '/agentic/admin/index.html?via=interop&t=' + Date.now() + (ns ? '&namespace=' + encodeURIComponent(ns) : '');
        iframe.src = url;
        overlay.classList.add('open');
        setTabActive(true);
    }

    function closeConfig() {
        var overlay = document.getElementById(CONFIG_OVERLAY_ID);
        if (!overlay) return;
        overlay.classList.remove('open');
        var iframe = overlay.querySelector('iframe');
        if (iframe) iframe.src = 'about:blank';
        setTabActive(false);
    }

    function setTabActive(yes) {
        var tab = document.querySelector('.' + TAB_MARK);
        if (tab) tab.classList.toggle('is-active', !!yes);
    }

    /* ---------------- Interface Specification Builder (full-screen) ------
     * The questionnaire that produces a specification prompt for the agent.
     * Lives on the same page as the chatbot: user fills the form, previews
     * the generated prompt ("Output Trial"), then either copies it or sends
     * it straight to the chat ("Send it to AIB"), which arrives here as an
     * agentic:spec:send message. */

    function buildSpecOverlay() {
        if (document.getElementById(SPEC_OVERLAY_ID)) return;
        var overlay = document.createElement('div');
        overlay.id = SPEC_OVERLAY_ID;
        overlay.innerHTML =
            '<div class="bar">' +
              '<span>InterSystems Integration Spec Questionnaire</span>' +
              '<button class="close" type="button" title="Close">✕</button>' +
            '</div>' +
            '<iframe src="about:blank" title="InterSystems Integration Spec Questionnaire"></iframe>';
        document.body.appendChild(overlay);
        overlay.querySelector('.close').addEventListener('click', closeSpec);
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && overlay.classList.contains('open')) closeSpec();
        });
    }

    function openSpec() {
        buildSpecOverlay();
        var overlay = document.getElementById(SPEC_OVERLAY_ID);
        var iframe = overlay.querySelector('iframe');
        var ns = currentNamespace();
        // Only load once per open so a half-filled form is not wiped by a
        // stray re-render of the host page.
        if (!iframe.src || iframe.src === 'about:blank') {
            iframe.src = '/agentic/spec/index.html?t=' + Date.now() +
                         (ns ? '&ns=' + encodeURIComponent(ns) : '');
        }
        overlay.classList.add('open');
        var tab = document.querySelector('.' + SPEC_MARK);
        if (tab) tab.classList.add('is-active');
    }

    function closeSpec() {
        var overlay = document.getElementById(SPEC_OVERLAY_ID);
        if (!overlay) return;
        overlay.classList.remove('open');
        var tab = document.querySelector('.' + SPEC_MARK);
        if (tab) tab.classList.remove('is-active');
        // Deliberately keep the iframe loaded so answers survive a close;
        // the user can reopen and continue where they left off.
    }

    function ensureSpecTab() {
        var dash = document.querySelector('.dashboard');
        if (!dash) return false;
        if (dash.querySelector('.' + SPEC_MARK)) return true;
        injectStyles();
        var tab = document.createElement('div');
        tab.className = 'navbuttons ' + SPEC_MARK;
        tab.innerHTML =
            '<div class="agentic-tab-inner">' +
              '<svg viewBox="0 0 20 20" width="18" height="18"><path d="M5 2h7l3 3v13H5V2zm7 1.5V6h2.5L12 3.5zM7 9h6v1.2H7V9zm0 3h6v1.2H7V12zm0 3h4v1.2H7V15z" fill="#0d9488"/></svg>' +
              '<span>Integration Spec</span>' +
            '</div>';
        tab.addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            openSpec();
        });
        dash.appendChild(tab);
        return true;
    }

    /* ---------------- cleanup helpers (REST calls from inject) -------- */

    function cleanupFetch(method, path) {
        var ns = currentNamespace();
        var opts = { method: method, headers: {} };
        if (STATE.bearer) opts.headers['Authorization'] = STATE.bearer;
        if (ns) opts.headers['X-IRIS-Namespace'] = ns;
        return origFetch('/api/agentic' + path, opts).then(function (r) {
            if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + r.statusText);
            return r.json();
        });
    }

    function doCleanProductions() {
        var btn = document.querySelector('.' + CLEAN_PROD_MARK);
        if (btn) btn.classList.add('is-busy');
        cleanupFetch('POST', '/cleanup/productions')
            .then(function (data) {
                if (data.ok) {
                    alert('Production state cleared.\n\n' +
                          'Namespace: ' + data.namespace + '\n' +
                          'Previous: ' + (data.previousProduction || '(none)') + '\n' +
                          'Final state: ' + data.finalState + '\n\n' +
                          data.message);
                } else {
                    alert('Error cleaning productions:\n' + (data.error || 'Unknown error'));
                }
            })
            .catch(function (e) { alert('Clean productions failed:\n' + e.message); })
            .then(function () { if (btn) btn.classList.remove('is-busy'); });
    }

    function doDeleteArtifacts() {
        var btn = document.querySelector('.' + CLEAN_ART_MARK);
        if (btn) btn.classList.add('is-busy');
        cleanupFetch('GET', '/cleanup/artifacts')
            .then(function (data) {
                if (!data.ok) {
                    alert('Error listing artifacts:\n' + (data.error || 'Unknown'));
                    return null;
                }
                if (data.totalArtifacts === 0) {
                    alert('No custom artifacts found in ' + data.namespace + '.\n\n' +
                          'Only system/core classes exist.');
                    return null;
                }
                var msg = 'Found ' + data.totalArtifacts + ' custom artifact(s) in ' + data.namespace + ':\n\n';
                if (data.totalProductions > 0) {
                    msg += 'Productions (' + data.totalProductions + '):\n';
                    for (var i = 0; i < data.productions.length; i++) msg += '  - ' + data.productions[i]["class"] + '\n';
                }
                if (data.totalDTLs > 0) {
                    msg += 'DTLs (' + data.totalDTLs + '):\n';
                    for (var i = 0; i < data.dtls.length; i++) msg += '  - ' + data.dtls[i]["class"] + '\n';
                }
                if (data.totalBPLs > 0) {
                    msg += 'BPLs (' + data.totalBPLs + '):\n';
                    for (var i = 0; i < data.bpls.length; i++) msg += '  - ' + data.bpls[i]["class"] + '\n';
                }
                if (data.totalRoutingRules > 0) {
                    msg += 'Routing Rules (' + data.totalRoutingRules + '):\n';
                    for (var i = 0; i < data.routingRules.length; i++) msg += '  - ' + data.routingRules[i]["class"] + '\n';
                }
                msg += '\nDelete ALL of these?';
                if (!confirm(msg)) return null;
                return cleanupFetch('DELETE', '/cleanup/artifacts');
            })
            .then(function (result) {
                if (!result) return;
                if (result.ok) {
                    alert('Deleted ' + result.totalDeleted + ' artifact(s).\n' +
                          (result.totalErrors > 0 ? result.totalErrors + ' error(s) occurred.' : 'No errors.') +
                          '\n\n' + result.message);
                } else {
                    alert('Delete failed:\n' + (result.error || 'Unknown error'));
                }
            })
            .catch(function (e) { alert('Delete artifacts failed:\n' + e.message); })
            .then(function () { if (btn) btn.classList.remove('is-busy'); });
    }

    /* ---------------- inject AI Hub tab into .dashboard ---------------- */

    function ensureTab() {
        var dash = document.querySelector('.dashboard');
        if (!dash) return false;
        if (dash.querySelector('.' + TAB_MARK)) return true;
        injectStyles();
        var tab = document.createElement('div');
        tab.className = 'navbuttons ' + TAB_MARK;
        tab.innerHTML =
            '<div class="agentic-tab-inner">' +
              '<svg viewBox="0 0 20 20"><path d="M10 1l2.2 5 5.3.4-4 3.6 1.2 5.2L10 12.6 5.3 15.2l1.2-5.2-4-3.6L7.8 6 10 1z" fill="#4f46e5"/></svg>' +
              '<span>AI Settings</span>' +
            '</div>';
        tab.addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            openConfig();
        });
        dash.appendChild(tab);
        return true;
    }

    function ensureCleanupButtons() {
        var dash = document.querySelector('.dashboard');
        if (!dash) return false;
        if (dash.querySelector('.' + CLEAN_PROD_MARK)) return true;
        injectStyles();
        var cleanBtn = document.createElement('div');
        cleanBtn.className = 'navbuttons ' + CLEAN_PROD_MARK;
        cleanBtn.innerHTML = '<div class="agentic-tab-inner"><span>Clean Productions</span></div>';
        cleanBtn.addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            doCleanProductions();
        });
        dash.appendChild(cleanBtn);
        var delBtn = document.createElement('div');
        delBtn.className = 'navbuttons ' + CLEAN_ART_MARK;
        delBtn.innerHTML = '<div class="agentic-tab-inner"><span>Delete Artifacts</span></div>';
        delBtn.addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            doDeleteArtifacts();
        });
        dash.appendChild(delBtn);
        return true;
    }

    /* ---------------- inject chat icon into mat-toolbar-row ---------------- */

    function ensureHeaderChat() {
        var row = document.querySelector('mat-toolbar mat-toolbar-row')
               || document.querySelector('mat-toolbar-row')
               || document.querySelector('mat-toolbar');
        if (!row) return false;
        for (var i = 0; i < row.children.length; i++) {
            if (row.children[i].classList.contains(HDR_MARK)) return true;
        }
        injectStyles();
        var wrap = document.createElement('div');
        wrap.className = 'dropdown ' + HDR_MARK;
        wrap.innerHTML =
            '<button type="button" aria-label="Open the Agentic Interoperability Builder" title="Chat with the Agentic Interoperability Builder">' +
              '<svg viewBox="0 0 24 24"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-2 12H6v-2h12v2zm0-3H6V9h12v2zm0-3H6V6h12v2z" fill="currentColor"/></svg>' +
              '<span class="dot" aria-hidden="true"></span>' +
            '</button>';
        wrap.querySelector('button').addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            openChat();
        });
        // Insert before the FIRST direct-child .dropdown (the namespace pill).
        var firstDirectDrop = null;
        for (var j = 0; j < row.children.length; j++) {
            if (row.children[j].classList.contains('dropdown')) {
                firstDirectDrop = row.children[j]; break;
            }
        }
        if (firstDirectDrop) row.insertBefore(wrap, firstDirectDrop);
        else row.appendChild(wrap);
        return true;
    }

    // FHIR Server Audit button — left-slide metrics/storage panel. Only for
    // the FHIR Management injection (chatbot=fhir-management).
    function ensureHeaderAudit() {
        if (CHATBOT_KEY !== 'fhir-management') return false;
        var row = document.querySelector('mat-toolbar mat-toolbar-row')
               || document.querySelector('mat-toolbar-row')
               || document.querySelector('mat-toolbar');
        if (!row) return false;
        for (var i = 0; i < row.children.length; i++) {
            if (row.children[i].classList.contains(AUD_MARK)) return true;
        }
        injectStyles();
        var wrap = document.createElement('div');
        wrap.className = 'dropdown ' + HDR_MARK + ' ' + AUD_MARK;
        wrap.innerHTML =
            '<button type="button" aria-label="Open FHIR Server Audit" title="FHIR Server performance and storage audit">' +
              '<svg viewBox="0 0 24 24"><path d="M4 20h16v-2H4v2zM6 10h3v6H6v-6zm5-4h3v10h-3V6zm5 6h3v4h-3v-4z" fill="currentColor"/></svg>' +
            '</button>';
        wrap.querySelector('button').addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            openAudit();
        });
        // Place right after the chat button if present, else before the pill.
        var chatDrop = null, firstDirectDrop = null;
        for (var j = 0; j < row.children.length; j++) {
            var ch = row.children[j];
            if (ch.classList.contains(AUD_MARK)) continue;
            if (ch.classList.contains(HDR_MARK) && !chatDrop) chatDrop = ch;
            if (ch.classList.contains('dropdown') && !firstDirectDrop) firstDirectDrop = ch;
        }
        if (chatDrop && chatDrop.nextSibling) row.insertBefore(wrap, chatDrop.nextSibling);
        else if (firstDirectDrop) row.insertBefore(wrap, firstDirectDrop);
        else row.appendChild(wrap);
        return true;
    }

    // "Load FHIR Data" header button — opens the upload panel. Sits in the
    // top toolbar next to the chat + audit icons. FHIR Management only.
    function ensureHeaderLoad() {
        if (CHATBOT_KEY !== 'fhir-management') return false;
        var row = document.querySelector('mat-toolbar mat-toolbar-row')
               || document.querySelector('mat-toolbar-row')
               || document.querySelector('mat-toolbar');
        if (!row) return false;
        for (var i = 0; i < row.children.length; i++) {
            if (row.children[i].classList.contains(LOAD_MARK)) return true;
        }
        injectStyles();
        var wrap = document.createElement('div');
        wrap.className = 'dropdown ' + HDR_MARK + ' ' + LOAD_MARK;
        wrap.innerHTML =
            '<button type="button" aria-label="Load FHIR Data" title="Upload FHIR JSON files to a server folder for loading">' +
              '<svg viewBox="0 0 24 24"><path d="M19 13v6H5v-6H3v6c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2v-6h-2zM11 4.83V15h2V4.83l3.59 3.58L18 7l-6-6-6 6 1.41 1.41L11 4.83z" fill="currentColor"/></svg>' +
            '</button>';
        wrap.querySelector('button').addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            openLoad();
        });
        // Place after the audit button if present, else after chat, else
        // before the namespace pill. (audit carries both HDR_MARK + AUD_MARK.)
        var auditDrop = null, chatDrop = null, firstDirectDrop = null;
        for (var j = 0; j < row.children.length; j++) {
            var ch = row.children[j];
            if (ch.classList.contains(LOAD_MARK)) continue;
            if (ch.classList.contains(AUD_MARK) && !auditDrop) auditDrop = ch;
            else if (ch.classList.contains(HDR_MARK) && !chatDrop) chatDrop = ch;
            if (ch.classList.contains('dropdown') && !firstDirectDrop) firstDirectDrop = ch;
        }
        var anchor = auditDrop || chatDrop;
        if (anchor && anchor.nextSibling) row.insertBefore(wrap, anchor.nextSibling);
        else if (firstDirectDrop) row.insertBefore(wrap, firstDirectDrop);
        else row.appendChild(wrap);
        return true;
    }

    // FHIR Server Audit — a LEFT-NAV menu item in the FHIR Management
    // Angular Material sidenav (mat-sidenav > mat-nav-list). Only for the
    // FHIR Management injection. Clones an existing nav item so it matches
    // the app's styling, then rebinds it to open the audit panel.
    // Generic: add a left-nav (mat-sidenav > mat-nav-list) menu item by cloning
    // an existing item for styling, then rebinding it. Used for both the FHIR
    // Audit and Load FHIR Data items. Only for the FHIR Management injection.
    function ensureNavItem(marker, label, titleAttr, iconName, onClick) {
        if (CHATBOT_KEY !== 'fhir-management') return false;
        var navList = document.querySelector('mat-sidenav mat-nav-list')
                   || document.querySelector('mat-sidenav-container mat-nav-list')
                   || document.querySelector('mat-nav-list');
        if (!navList) return false;
        if (navList.querySelector('.' + marker)) return true;
        // Clone a REAL shipped nav item for styling — never one of our own
        // injected items (otherwise a second injection clones the first and
        // the styling/label drift).
        var samples = navList.querySelectorAll('a[mat-list-item], a.mat-mdc-list-item, [mat-list-item], .mat-mdc-list-item, mat-list-item');
        var sample = null;
        for (var si = 0; si < samples.length; si++) {
            if (!samples[si].classList.contains(AUD_NAV_MARK) && !samples[si].classList.contains(LOAD_NAV_MARK)) { sample = samples[si]; break; }
        }
        var item;
        if (sample) {
            item = sample.cloneNode(true);
            item.removeAttribute('href');
            item.removeAttribute('routerlink');
            item.removeAttribute('ng-reflect-router-link');
            item.removeAttribute('ng-reflect-router-link-active');
            // Replace the visible label without disturbing the icon node.
            var txt = item.querySelector('.mdc-list-item__primary-text')
                   || item.querySelector('.mat-mdc-list-item-unscoped-content')
                   || item.querySelector('.mdc-list-item__content')
                   || item;
            try { txt.textContent = label; } catch (e) {}
            // Retarget the Material icon ONLY when it is a font-ligature icon
            // (has text, no <svg>, no svgIcon attr) — otherwise leave the
            // shipped icon alone so we never paint stray text next to an SVG.
            var ic = item.querySelector('mat-icon');
            if (ic && iconName && ic.textContent && ic.textContent.trim().length && !ic.getAttribute('svgicon') && !ic.querySelector('svg')) {
                try { ic.textContent = iconName; } catch (e) {}
            }
        } else {
            item = document.createElement('a');
            item.textContent = label;
            item.style.cssText = 'display:block;padding:12px 16px;color:inherit;text-decoration:none;';
        }
        item.classList.add(marker);
        item.style.cursor = 'pointer';
        item.setAttribute('title', titleAttr);
        item.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); onClick(); });
        // Insert at the TOP of the list (above the ~23 shipped items) so it is
        // visible without scrolling — the prior append put it below the fold.
        if (sample && sample.parentNode) sample.parentNode.insertBefore(item, sample);
        else navList.appendChild(item);
        return true;
    }
    function ensureSideNavAudit() { return ensureNavItem(AUD_NAV_MARK, 'FHIR Audit', 'FHIR Server performance and storage audit', 'assessment', openAudit); }
    function ensureSideNavLoad() { return ensureNavItem(LOAD_NAV_MARK, 'Load FHIR Data', 'Upload FHIR JSON files to a server folder for loading', 'upload_file', openLoad); }

    /* ---------------- floating launcher (host-agnostic) ---------------- */

    function ensureFloatingLauncher() {
        if (document.getElementById(FAB_ID)) return true;
        injectStyles();
        var fab = document.createElement('button');
        fab.id = FAB_ID;
        fab.type = 'button';
        fab.setAttribute('aria-label', 'Open ' + (CHAT_TITLE || 'Agentic Interoperability Builder'));
        fab.title = 'Chat with the ' + (CHAT_TITLE || 'Agentic Interoperability Builder');
        fab.innerHTML =
            '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z" fill="#fff"/></svg>' +
            '<span class="agentic-fab-dot" aria-hidden="true"></span>';
        fab.addEventListener('click', function (e) {
            e.preventDefault(); e.stopPropagation();
            openChat();
        });
        document.body.appendChild(fab);
        return true;
    }

    /* ---------------- login-mode hide ---------------- */

    function refreshLoginMode() {
        var onLogin;
        if (INJECT_MODE === 'floating' || INJECT_MODE === 'header') {
            // Host-agnostic pages have no .dashboard; only the visible
            // password field of the login screen means "not logged in".
            onLogin = !!document.querySelector('input[type="password"]:not([hidden])');
        } else {
            onLogin =
                !document.querySelector('.dashboard') ||
                !!document.querySelector('input[type="password"]:not([hidden])');
        }
        document.body.classList.toggle('agentic-login-mode', onLogin);
    }

    /* ---------------- watch + tick ---------------- */

    var pending = null;
    function schedule() {
        if (pending) return;
        pending = setTimeout(function () { pending = null; tick(); }, 150);
    }
    function tick() {
        if (INJECT_MODE === 'floating') {
            ensureFloatingLauncher();
        } else if (INJECT_MODE === 'header') {
            // Host-agnostic: splice Chat + Audit + Load FHIR Data into the page's
            // top toolbar, side by side. The header is the proven mechanism (the
            // chat icon has always rendered there); the left-nav (mat-nav-list)
            // injection was unreliable in this build, so all three live here.
            ensureHeaderChat();
            ensureHeaderAudit();
            ensureHeaderLoad();
        } else {
            ensureTab();
            ensureSpecTab();
            ensureCleanupButtons();
            ensureHeaderChat();
        }
        refreshLoginMode();
    }

    function start() {
        tick();
        new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
        setInterval(refreshLoginMode, 800);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
