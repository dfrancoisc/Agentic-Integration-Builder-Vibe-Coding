/* agentic_interop — install AI Configuration + AI Chatbot launchers
 * INSIDE the IRIS Interop Editor's Angular UI, AFTER the user has
 * authenticated. Per kickoff restriction #3, NO part of agentic_interop
 * appears on the login screen or any other unauthenticated state.
 *
 * Loaded by /usr/irissys/ui/interop/interop-editor/index.html via a
 * <script defer> tag added by AgenticInterop.Install.InteropEditorPatch
 * (called from the IPM Activate phase).
 *
 * Lifecycle:
 *   1. Wait for the Angular SPA to render the post-login chrome
 *      (detected by the username chip + namespace selector).
 *   2. Verify a real IRIS session exists by calling /api/agentic/whoami.
 *      If the call returns 401 (or fails), do not render anything.
 *   3. Mount two compact buttons inside the SPA's top header, before
 *      the "Back to standard UI" button. One-shot — the MutationObserver
 *      disconnects after success so we don't fight Angular's change
 *      detection.
 *   4. On click, open the matching UI (admin / chat) in a centred
 *      modal iframe. The iframe runs in the same authenticated browser
 *      context, so the IRIS session cookie carries through automatically;
 *      every REST call is auth-gated and audit-logged on the backend.
 *   5. If the SPA navigates back to a logged-out state we tear our
 *      buttons down.
 */
(function () {
    'use strict';

    var STATE = {
        injected: false,
        observer: null,
        bar: null,
        modal: null
    };

    var TABS = [
        {
            id: 'agentic-config',
            label: 'AI Configuration',
            url: '/agentic/admin/index.html',
            color: '#3b82f6',
            icon: '⚙'
        },
        {
            id: 'agentic-chat',
            label: 'AI Chatbot',
            url: '/agentic/chat/index.html',
            color: '#22c55e',
            icon: '💬'
        }
    ];

    /* ---------------- session check ---------------- */

    function checkSession() {
        return fetch('/api/agentic/whoami', {
            credentials: 'include',
            headers: { 'Accept': 'application/json' },
            cache: 'no-store'
        }).then(function (r) {
            if (!r.ok) return null;
            return r.json();
        }).then(function (j) {
            if (!j || !j.username) return null;
            // IRIS may return UnknownUser when an anonymous binding slipped
            // through — treat it as no session.
            if (j.username === 'UnknownUser') return null;
            return j;
        }).catch(function () { return null; });
    }

    /* ---------------- modal ---------------- */

    function ensureModal() {
        if (STATE.modal) return STATE.modal;
        var shell = document.createElement('div');
        shell.id = 'agentic-modal';
        shell.style.cssText = [
            'position: fixed', 'inset: 0',
            'background: rgba(0,0,0,0.55)',
            'z-index: 2147483646',
            'display: none',
            'align-items: center', 'justify-content: center'
        ].join(';');
        var box = document.createElement('div');
        box.style.cssText = [
            'background: #fff', 'width: 92%', 'max-width: 1280px',
            'height: 86%', 'max-height: 880px',
            'border-radius: 6px', 'overflow: hidden',
            'display: flex', 'flex-direction: column',
            'box-shadow: 0 16px 48px rgba(0,0,0,0.45)'
        ].join(';');
        var bar = document.createElement('div');
        bar.style.cssText = [
            'display: flex', 'align-items: center', 'justify-content: space-between',
            'padding: 8px 14px', 'background: #1c2129', 'color: #e6e8eb',
            'font: 600 13px/1.2 system-ui, sans-serif',
            'border-bottom: 1px solid #2a313c'
        ].join(';');
        var title = document.createElement('span');
        title.id = 'agentic-modal-title';
        bar.appendChild(title);
        var actions = document.createElement('span');
        var openTab = document.createElement('button');
        openTab.textContent = 'Open in new tab';
        openTab.style.cssText = 'background:transparent;color:#8b95a6;border:1px solid #2a313c;padding:4px 10px;border-radius:3px;cursor:pointer;font:inherit;margin-right:8px;';
        openTab.addEventListener('click', function () { window.open(shell.dataset.url, '_blank'); });
        var close = document.createElement('button');
        close.textContent = 'Close';
        close.style.cssText = 'background:transparent;color:#8b95a6;border:1px solid #2a313c;padding:4px 10px;border-radius:3px;cursor:pointer;font:inherit;';
        close.addEventListener('click', function () { shell.style.display = 'none'; });
        actions.appendChild(openTab);
        actions.appendChild(close);
        bar.appendChild(actions);
        box.appendChild(bar);
        var iframe = document.createElement('iframe');
        iframe.id = 'agentic-modal-iframe';
        iframe.style.cssText = 'border:0;flex:1;width:100%;background:#0f1115;';
        iframe.setAttribute('referrerpolicy', 'no-referrer-when-downgrade');
        // credentialless=false so the IRIS session cookie reaches the iframe
        box.appendChild(iframe);
        shell.appendChild(box);
        shell.addEventListener('click', function (e) {
            if (e.target === shell) shell.style.display = 'none';
        });
        document.body.appendChild(shell);
        STATE.modal = shell;
        return shell;
    }

    function openModal(label, url) {
        var shell = ensureModal();
        document.getElementById('agentic-modal-title').textContent = label;
        document.getElementById('agentic-modal-iframe').src = url;
        shell.dataset.url = url;
        shell.style.display = 'flex';
    }

    /* ---------------- buttons ---------------- */

    function buildButton(tab) {
        var btn = document.createElement('button');
        btn.id = tab.id;
        btn.type = 'button';
        btn.setAttribute('data-agentic-button', tab.id);
        btn.style.cssText = [
            'display: inline-flex', 'align-items: center', 'gap: 6px',
            'padding: 5px 12px',
            'border: 1px solid ' + tab.color, 'border-radius: 4px',
            'background: ' + tab.color, 'color: #fff',
            'font: 600 12px/1 system-ui, sans-serif',
            'cursor: pointer', 'margin-right: 8px',
            'box-shadow: 0 1px 0 rgba(0,0,0,0.05)'
        ].join(';');
        btn.innerHTML =
            '<span style="font-size:13px;line-height:1;">' + tab.icon + '</span>' +
            '<span>' + tab.label + '</span>';
        btn.addEventListener('click', function () { openModal(tab.label, tab.url); });
        btn.addEventListener('mouseover', function () { btn.style.filter = 'brightness(1.08)'; });
        btn.addEventListener('mouseout',  function () { btn.style.filter = ''; });
        return btn;
    }

    /* ---------------- find post-login anchor ---------------- */

    /* The post-login Interop Editor has, in its top-right header:
     *     [ Back to standard UI ]   { } HSCUSTOM   account_circle _SYSTEM
     * The .frBackToStdUI button (or its FR-BUTTON parent) is the anchor we
     * insert before. We never modify Angular's child arrays in place — we
     * just call insertBefore once and then disconnect the observer. */
    function findAnchor() {
        // Look for a button labelled "Back to standard UI" — its parent
        // FR-BUTTON sits inside the Angular header row.
        var spans = document.querySelectorAll('button span, fr-button button span');
        for (var i = 0; i < spans.length; i++) {
            if ((spans[i].textContent || '').trim() === 'Back to standard UI') {
                var btn = spans[i].closest('button');
                if (btn) {
                    // Walk up to the FR-BUTTON wrapper (or button itself)
                    var wrap = btn.closest('fr-button') || btn;
                    return wrap;
                }
            }
        }
        return null;
    }

    function isLoginScreen() {
        // The Angular login route renders inputs explicitly named username
        // / password. If we see them, we are NOT logged in.
        var u = document.querySelector('input[name="username"], input[id*="username"]');
        var p = document.querySelector('input[type="password"]');
        return !!(u || p);
    }

    /* ---------------- mount / teardown ---------------- */

    function mount(anchor) {
        if (STATE.injected) return;
        if (!anchor || !anchor.parentNode) return;
        var container = document.createElement('span');
        container.id = 'agentic-launchers';
        container.setAttribute('data-agentic-host', '1');
        container.style.cssText = 'display: inline-flex; align-items: center; margin-right: 12px;';
        TABS.forEach(function (t) { container.appendChild(buildButton(t)); });
        // insertBefore is one-shot — does not require the observer to keep
        // firing. Angular tolerates a static sibling it didn't create as
        // long as we don't re-mutate.
        anchor.parentNode.insertBefore(container, anchor);
        STATE.bar = container;
        STATE.injected = true;
        if (STATE.observer) {
            STATE.observer.disconnect();
            STATE.observer = null;
        }
    }

    function teardown() {
        if (STATE.bar && STATE.bar.parentNode) {
            STATE.bar.parentNode.removeChild(STATE.bar);
        }
        STATE.bar = null;
        STATE.injected = false;
    }

    /* ---------------- main loop ---------------- */

    function tryMount() {
        if (STATE.injected) return true;
        if (isLoginScreen()) return false;
        var anchor = findAnchor();
        if (!anchor) return false;
        // Confirm a real IRIS session before showing anything.
        checkSession().then(function (sess) {
            if (!sess) return; // not authenticated → render nothing
            if (isLoginScreen()) return; // raced into login — bail
            // Re-find anchor in case Angular re-rendered while waiting
            var a = findAnchor();
            if (!a) return;
            mount(a);
        });
        return true; // we triggered the async path; observer can disconnect now
    }

    function watch() {
        if (STATE.observer) return;
        STATE.observer = new MutationObserver(function () {
            if (STATE.injected) {
                STATE.observer.disconnect();
                STATE.observer = null;
                return;
            }
            tryMount();
        });
        STATE.observer.observe(document.body, { childList: true, subtree: true });
    }

    function start() {
        // Try once immediately (page may already be rendered)
        if (!tryMount()) watch();
        // Re-check every few seconds to catch login → post-login transitions
        // and post-login → login (logout) transitions.
        setInterval(function () {
            if (isLoginScreen()) { teardown(); return; }
            if (STATE.injected) {
                // If our anchor disappeared, tear down so we re-inject when
                // the SPA brings the header back.
                if (!STATE.bar || !STATE.bar.parentNode) {
                    STATE.injected = false;
                    STATE.bar = null;
                }
                return;
            }
            tryMount();
        }, 2000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
