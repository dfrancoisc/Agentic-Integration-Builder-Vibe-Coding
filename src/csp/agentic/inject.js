/* agentic_interop — install two large buttons (AI Configuration + AI
 * Chatbot) inside the IRIS Interop Editor at /ui/interop/interop-editor/.
 *
 * The Interop editor is an Angular SPA that owns its DOM tree. Adding
 * children inside Angular-managed elements crashes its change detection
 * with "Cannot read properties of null (reading 'name')" — so we DO NOT
 * touch .dashboard or any other Angular node. Instead we mount a
 * top-of-page bar at the document body, OUTSIDE the SPA root, and shift
 * the SPA down a few pixels so the bar is part of the layout (not a
 * floating overlay).
 *
 * The bar is loaded by /agentic/inject.js, which the post-install
 * routine adds to the shipped index.html with a `<script defer>` tag.
 */
(function () {
    'use strict';

    var BAR_HEIGHT = 40;
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

    function ensureModalShell() {
        var existing = document.getElementById('agentic-modal');
        if (existing) return existing;

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
            'background: #fff',
            'width: 92%', 'max-width: 1280px',
            'height: 86%', 'max-height: 880px',
            'border-radius: 6px',
            'overflow: hidden',
            'display: flex', 'flex-direction: column',
            'box-shadow: 0 16px 48px rgba(0,0,0,0.45)'
        ].join(';');

        var bar = document.createElement('div');
        bar.style.cssText = [
            'display: flex', 'align-items: center', 'justify-content: space-between',
            'padding: 8px 14px',
            'background: #1c2129', 'color: #e6e8eb',
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
        box.appendChild(iframe);

        shell.appendChild(box);
        shell.addEventListener('click', function (e) {
            if (e.target === shell) shell.style.display = 'none';
        });
        document.body.appendChild(shell);
        return shell;
    }

    function openModal(label, url) {
        var shell = ensureModalShell();
        document.getElementById('agentic-modal-title').textContent = label;
        document.getElementById('agentic-modal-iframe').src = url;
        shell.dataset.url = url;
        shell.style.display = 'flex';
    }

    function buildButton(tab) {
        var btn = document.createElement('button');
        btn.id = tab.id;
        btn.type = 'button';
        btn.style.cssText = [
            'display: inline-flex', 'align-items: center', 'gap: 8px',
            'padding: 6px 14px',
            'border: 1px solid ' + tab.color, 'border-radius: 4px',
            'background: ' + tab.color, 'color: #fff',
            'font: 600 13px/1 system-ui, sans-serif',
            'cursor: pointer',
            'box-shadow: 0 1px 0 rgba(0,0,0,0.05)'
        ].join(';');
        btn.innerHTML =
            '<span style="font-size:14px;line-height:1;">' + tab.icon + '</span>' +
            '<span>' + tab.label + '</span>';
        btn.addEventListener('click', function () { openModal(tab.label, tab.url); });
        btn.addEventListener('mouseover', function () { btn.style.filter = 'brightness(1.08)'; });
        btn.addEventListener('mouseout',  function () { btn.style.filter = ''; });
        return btn;
    }

    function ensureBar() {
        var existing = document.getElementById('agentic-bar');
        if (existing) return existing;

        // Push the SPA down to make room for our bar — body-level CSS that
        // doesn't reach into Angular's tree.
        var pushStyle = document.createElement('style');
        pushStyle.id = 'agentic-bar-push';
        pushStyle.textContent =
            'body > app-root, body > #app-root { display: block; padding-top: ' + BAR_HEIGHT + 'px !important; box-sizing: border-box; }' +
            'html, body { min-height: 100vh; }';
        document.head.appendChild(pushStyle);

        var bar = document.createElement('div');
        bar.id = 'agentic-bar';
        bar.style.cssText = [
            'position: fixed', 'top: 0', 'left: 0', 'right: 0',
            'height: ' + BAR_HEIGHT + 'px',
            'background: linear-gradient(180deg, #1c2129 0%, #161a21 100%)',
            'border-bottom: 1px solid #2a313c',
            'display: flex', 'align-items: center', 'gap: 10px',
            'padding: 0 16px',
            'z-index: 2147483645',
            'box-shadow: 0 1px 4px rgba(0,0,0,0.18)',
            'font: 13px system-ui, sans-serif'
        ].join(';');

        var brand = document.createElement('span');
        brand.textContent = 'agentic_interop';
        brand.style.cssText = 'color: #e6e8eb; font-weight: 600; letter-spacing: 0.02em; margin-right: 12px;';
        bar.appendChild(brand);

        TABS.forEach(function (t) { bar.appendChild(buildButton(t)); });

        var spacer = document.createElement('span');
        spacer.style.cssText = 'flex: 1;';
        bar.appendChild(spacer);

        var hint = document.createElement('span');
        hint.textContent = 'Embedded into Interop Editor';
        hint.style.cssText = 'color: #8b95a6; font-size: 11px; letter-spacing: 0.04em; text-transform: uppercase;';
        bar.appendChild(hint);

        document.body.appendChild(bar);
        return bar;
    }

    function start() {
        if (document.getElementById('agentic-bar')) return;
        ensureBar();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
