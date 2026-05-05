/* agentic_interop — install AI Configuration + AI Chatbot launchers
 * INSIDE the IRIS Interop Editor's Angular UI, AFTER the user has
 * authenticated. Per kickoff restriction #3, NO part of agentic_interop
 * appears on the login screen.
 *
 * Design notes (after a long day of failed attempts):
 *   - The Interop SPA (2026.2 modern UI) is fully Bearer-token based;
 *     its auth lives in JS memory, not in any cookie. There is no
 *     IRIS session cookie that can be shared with /api/agentic — so the
 *     earlier "call /api/agentic/whoami first" approach can't work
 *     without re-authenticating.
 *   - Therefore inject.js NO LONGER calls any auth endpoint. It renders
 *     the buttons whenever the SPA is in its post-login chrome state
 *     (detected purely from the DOM). The buttons open the agentic UI
 *     in a modal iframe; that iframe handles its OWN auth (inline
 *     login form, sessionStorage Basic creds, all REST calls audited
 *     server-side).
 *   - We do not poke into Angular's tree — the launchers mount as a
 *     sibling of the SPA's "Back to standard UI" button using one-shot
 *     insertBefore + an observer that disconnects on success. A 2s
 *     watchdog re-mounts if Angular re-renders the chrome.
 */
(function () {
    'use strict';

    var STATE = { injected: false, observer: null, container: null };

    var TABS = [
        { id: 'agentic-config', label: 'AI Configuration', url: '/agentic/admin/index.html', color: '#3b82f6', icon: '⚙' },
        { id: 'agentic-chat',   label: 'AI Chatbot',       url: '/agentic/chat/index.html',  color: '#22c55e', icon: '💬' }
    ];

    /* ---------------- modal ---------------- */

    function ensureModal() {
        var existing = document.getElementById('agentic-modal');
        if (existing) return existing;
        var shell = document.createElement('div');
        shell.id = 'agentic-modal';
        shell.style.cssText =
            'position:fixed;inset:0;background:rgba(0,0,0,0.55);z-index:2147483646;' +
            'display:none;align-items:center;justify-content:center;';
        var box = document.createElement('div');
        box.style.cssText =
            'background:#fff;width:92%;max-width:1280px;height:86%;max-height:880px;' +
            'border-radius:6px;overflow:hidden;display:flex;flex-direction:column;' +
            'box-shadow:0 16px 48px rgba(0,0,0,0.45);';
        var bar = document.createElement('div');
        bar.style.cssText =
            'display:flex;align-items:center;justify-content:space-between;' +
            'padding:8px 14px;background:#1c2129;color:#e6e8eb;' +
            'font:600 13px/1.2 system-ui, sans-serif;border-bottom:1px solid #2a313c;';
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
        box.appendChild(iframe);
        shell.appendChild(box);
        shell.addEventListener('click', function (e) { if (e.target === shell) shell.style.display = 'none'; });
        document.body.appendChild(shell);
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
        btn.title = tab.label;
        btn.style.cssText =
            'display:inline-flex;align-items:center;gap:6px;padding:5px 12px;' +
            'border:1px solid ' + tab.color + ';border-radius:4px;background:' + tab.color + ';' +
            'color:#fff;font:600 12px/1 system-ui, sans-serif;cursor:pointer;margin-right:8px;' +
            'box-shadow:0 1px 0 rgba(0,0,0,0.05);';
        btn.innerHTML =
            '<span style="font-size:13px;line-height:1;">' + tab.icon + '</span>' +
            '<span>' + tab.label + '</span>';
        btn.addEventListener('click', function () { openModal(tab.label, tab.url); });
        btn.addEventListener('mouseover', function () { btn.style.filter = 'brightness(1.08)'; });
        btn.addEventListener('mouseout',  function () { btn.style.filter = ''; });
        return btn;
    }

    /* ---------------- DOM detection ---------------- */

    function isLoginScreen() {
        return !!document.querySelector('input[type="password"]');
    }

    function findAnchor() {
        var spans = document.querySelectorAll('button span, fr-button button span');
        for (var i = 0; i < spans.length; i++) {
            if ((spans[i].textContent || '').trim() === 'Back to standard UI') {
                var btn = spans[i].closest('button');
                if (btn) return btn.closest('fr-button') || btn;
            }
        }
        return null;
    }

    /* ---------------- mount / teardown ---------------- */

    function mount(anchor) {
        if (STATE.injected) return;
        if (!anchor || !anchor.parentNode) return;
        var c = document.createElement('span');
        c.id = 'agentic-launchers';
        c.setAttribute('data-agentic-host', '1');
        c.style.cssText = 'display:inline-flex;align-items:center;margin-right:12px;';
        TABS.forEach(function (t) { c.appendChild(buildButton(t)); });
        anchor.parentNode.insertBefore(c, anchor);
        STATE.container = c;
        STATE.injected = true;
        if (STATE.observer) { STATE.observer.disconnect(); STATE.observer = null; }
    }

    function teardown() {
        if (STATE.container && STATE.container.parentNode) {
            STATE.container.parentNode.removeChild(STATE.container);
        }
        STATE.container = null;
        STATE.injected = false;
    }

    /* ---------------- main loop ---------------- */

    function tryMount() {
        if (STATE.injected) return true;
        if (isLoginScreen()) return false;
        var a = findAnchor();
        if (!a) return false;
        mount(a);
        return true;
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
        if (!tryMount()) watch();
        // Re-check on a 2s cadence so login -> post-login transitions
        // (and the reverse) are picked up without busy-watching the DOM.
        setInterval(function () {
            if (isLoginScreen()) { teardown(); return; }
            if (STATE.injected) {
                if (!STATE.container || !STATE.container.parentNode) {
                    STATE.injected = false;
                    STATE.container = null;
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
