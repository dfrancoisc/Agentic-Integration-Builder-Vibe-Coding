// Agentic Integration Builder admin — vanilla JS SPA against /api/agentic/*
//
// Auth model:
// When opened from inject.js inside the Interop Editor (URL has
// ?via=interop), this admin UI asks the parent window for the Bearer
// JWT the Interop SPA captured. /api/agentic shares JWTAuthEnabled +
// GroupById=%ISCMgtPortal with /api/interop-editors so the SAME token
// authenticates seamlessly — no second login. The handshake is via
// postMessage and times out after 1.5s; if no Bearer arrives we fall
// back to the inline login overlay (used for direct/standalone access
// to /agentic/admin/).

const API = '/api/agentic';
const ADMIN_VERSION = '2026.05.11.3';
const TABS = ['agents', 'mcps', 'toolsets', 'tools', 'skills', 'connections', 'chatbots', 'catalogs', 'transforms', 'tokens', 'audit'];
const AUTH_KEY = 'AGENTIC_AUTH';

// [CSP cookie fix] Force credentials:'omit' on every fetch from this
// iframe. Without this, the browser's default credentials:'same-origin'
// sends the Interop Editor's CSPSESSIONID cookie with every request to
// /api/agentic/. The CSP gateway sees the stale session cookie, tries
// to validate it, FAILS, and returns 401 before ever reading the
// Authorization header we send.
{
    const _fetch = window.fetch.bind(window);
    window.fetch = (url, opts) => _fetch(url, Object.assign({}, opts, { credentials: 'omit' }));
}

// Bearer + namespace received from inject.js via postMessage. Set
// during bootstrap before any API call.
let bridgeBearer = '';
let bridgeNamespace = '';
// Once bootstrap validates auth (via /whoami) we set this. Subsequent
// 401s throw a toast instead of re-prompting — the original repeated
// re-prompt UX was unacceptable.
let authValidated = false;

function isViaInterop() {
    try { return new URLSearchParams(window.location.search).get('via') === 'interop'; }
    catch { return false; }
}

function urlNamespace() {
    try { return new URLSearchParams(window.location.search).get('namespace') || ''; }
    catch { return ''; }
}

async function fetchBridgeAuth() {
    return new Promise((resolve) => {
        let done = false;
        function finish(payload) { if (done) return; done = true; resolve(payload || {}); }
        function listener(e) {
            const d = e.data || {};
            if (d && d.type === 'agentic:auth:response') {
                window.removeEventListener('message', listener);
                finish(d);
            }
        }
        window.addEventListener('message', listener);
        try { window.parent.postMessage({ type: 'agentic:auth:request' }, '*'); } catch {}
        setTimeout(() => { window.removeEventListener('message', listener); finish({}); }, 1500);
    });
}

const state = {
    tab: 'agents',
    list: [],
    selected: null,    // currently-open detail (object)
    detailKind: null,  // which entity is on the right pane
    registry: { agents: [], mcps: [], toolsets: [], skills: [] },
    namespace: '',
    username: ''
};

const $ = (id) => document.getElementById(id);

// -------- auth helpers --------

// Stored in localStorage so credentials survive iframe close+reopen,
// browser tab restarts, and overlay dismissals. The parent IRIS shell
// is already authenticated; we want to ride that for the duration of
// the IRIS session, not prompt every time the AI Settings overlay
// reopens.
function getStoredAuth() {
    try { return localStorage.getItem(AUTH_KEY) || ''; } catch { return ''; }
}
function setStoredAuth(basic) {
    try { localStorage.setItem(AUTH_KEY, basic); } catch {}
}
function showLoginOverlay(message) {
    return new Promise((resolve) => {
        const existing = document.getElementById('agentic-login-overlay');
        if (existing) existing.remove();
        const overlay = document.createElement('div');
        overlay.id = 'agentic-login-overlay';
        overlay.style.cssText =
            'position:fixed;inset:0;background:rgba(15,17,21,0.85);z-index:9999;' +
            'display:flex;align-items:center;justify-content:center;' +
            'font:13px system-ui, sans-serif;color:#e6e8eb;';
        overlay.innerHTML =
            '<form id="agentic-login-form" style="background:#161a21;border:1px solid #2a313c;border-radius:6px;padding:24px;width:340px;display:flex;flex-direction:column;gap:12px;">' +
            '<div style="font-weight:600;font-size:14px;">Sign in to AI Tools</div>' +
            '<div style="color:#8b95a6;font-size:12px;line-height:1.4;">' +
              (message || 'Enter your IRIS credentials. Required separately from the Interop Editor login because the SPA does not share its session.') +
            '</div>' +
            '<label style="color:#8b95a6;font-size:11px;text-transform:uppercase;letter-spacing:0.04em;">Username' +
              '<input id="agentic-login-user" type="text" autocomplete="username" autofocus style="width:100%;background:#0b0d11;color:#e6e8eb;border:1px solid #2a313c;border-radius:4px;padding:8px;font:inherit;margin-top:4px;">' +
            '</label>' +
            '<label style="color:#8b95a6;font-size:11px;text-transform:uppercase;letter-spacing:0.04em;">Password' +
              '<input id="agentic-login-pass" type="password" autocomplete="current-password" style="width:100%;background:#0b0d11;color:#e6e8eb;border:1px solid #2a313c;border-radius:4px;padding:8px;font:inherit;margin-top:4px;">' +
            '</label>' +
            '<div id="agentic-login-err" style="color:#ef4444;font-size:11px;display:none;"></div>' +
            '<button type="submit" style="background:#3b82f6;border:1px solid #3b82f6;color:#fff;padding:8px;border-radius:4px;cursor:pointer;font:600 13px system-ui;">Sign in</button>' +
            '</form>';
        document.body.appendChild(overlay);
        const form = overlay.querySelector('#agentic-login-form');
        const err = overlay.querySelector('#agentic-login-err');
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const user = overlay.querySelector('#agentic-login-user').value;
            const pass = overlay.querySelector('#agentic-login-pass').value;
            if (!user || !pass) return;
            const basic = 'Basic ' + btoa(user + ':' + pass);
            // Verify against /whoami
            try {
                const res = await fetch(API + '/whoami', { headers: { Authorization: basic }, cache: 'no-store' });
                if (!res.ok) {
                    err.textContent = 'Invalid credentials.';
                    err.style.display = 'block';
                    return;
                }
                setStoredAuth(basic);
                overlay.remove();
                resolve(true);
            } catch (e2) {
                err.textContent = 'Network error: ' + e2.message;
                err.style.display = 'block';
            }
        });
    });
}

// -------- HTTP helpers --------

// Probe an Authorization header against /whoami. Returns true on 2xx.
async function probeAuth(authHeader) {
    if (!authHeader) return false;
    try {
        const r = await fetch(API + '/whoami', {
            headers: { Authorization: authHeader, Accept: 'application/json' },
            cache: 'no-store'
        });
        return r.ok;
    } catch { return false; }
}

// Validate auth once at boot: try the SPA's bridge bearer first, then
// any stored Basic credentials, finally show the inline overlay. Once
// any of these succeeds, mark `authValidated = true` so subsequent 401s
// surface a toast instead of re-prompting on every tab click.
async function bootstrapAuth() {
    if (authValidated) return;
    if (bridgeBearer && await probeAuth(bridgeBearer)) {
        authValidated = true;
        return;
    }
    bridgeBearer = '';
    const stored = getStoredAuth();
    if (stored && await probeAuth(stored)) {
        authValidated = true;
        return;
    }
    // DO NOT clear stored creds on probe failure here. The probe could
    // have failed for transient reasons (server restart, network blip,
    // 5xx) — wiping creds turns one transient failure into "user is
    // re-prompted forever." Keep them; they'll succeed on the next
    // bootstrap or be replaced when the user signs in via the overlay.
    await showLoginOverlay();
    authValidated = true;
}

async function api(path, opts = {}) {
    if (!authValidated) await bootstrapAuth();
    const auth = bridgeBearer || getStoredAuth();
    const headers = {
        'Content-Type': 'application/json',
        'Authorization': auth,
        ...(opts.headers || {})
    };
    // bridgeNamespace is captured for display + future Phase 2 tool
    // calls (passed in request body), NOT as an X-IRIS-Namespace
    // header — the gateway's namespace switch reaches a USER ns where
    // AgenticInterop.REST.Dispatch isn't compiled, so the request 500s.
    // The dispatch always runs in its install namespace (HSCUSTOM by
    // default); per-tool handlers will switch context internally.
    const res = await fetch(API + path, { ...opts, headers });
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch (e) { /* keep null */ }
    if (res.status === 401) {
        // Bootstrap succeeded once and got us a working credential. A
        // mid-session 401 is almost always either (a) a transient
        // server-side hiccup, or (b) a single endpoint that requires
        // a different scope. Either way, do NOT reset authValidated
        // and do NOT clear stored creds — that turns one bad request
        // into a forced re-login on the next click, which is the
        // exact pain the customer escalated. Surface a toast for this
        // request and let the next call try again with the same
        // credentials.
        toast('Authorization rejected for this request.', 'error');
        const err = new Error('Authorization rejected');
        err.status = 401;
        throw err;
    }
    if (!res.ok) {
        const msg = (json && json.error) ? json.error : `HTTP ${res.status}`;
        const detail = (json && json.detail) ? json.detail : text;
        const err = new Error(msg);
        err.detail = detail;
        err.status = res.status;
        throw err;
    }
    return json;
}

const get   = (p)       => api(p);
const post  = (p, body) => api(p, { method: 'POST',   body: JSON.stringify(body) });
const put   = (p, body) => api(p, { method: 'PUT',    body: JSON.stringify(body) });
const del   = (p)       => api(p, { method: 'DELETE' });

// -------- toast --------

function toast(msg, kind = '') {
    const t = $('toast');
    t.textContent = msg;
    t.className = 'toast' + (kind ? ' ' + kind : '');
    t.hidden = false;
    setTimeout(() => { t.hidden = true; }, 3500);
}

// -------- tabs --------

function setTab(tab) {
    state.tab = tab;
    state.selected = null;
    state.detailKind = null;
    document.querySelectorAll('#tabs button').forEach(b => {
        b.classList.toggle('active', b.dataset.tab === tab);
    });
    // Tabs without a per-row detail pane (audit, catalogs) get the
    // whole viewport — body[data-layout=full] hides #detail-panel
    // and lets #list-panel flex to 100% width.
    document.body.dataset.layout = (tab === 'audit' || tab === 'tokens' || tab === 'catalogs' || tab === 'transforms') ? 'full' : 'split';
    $('list-title').textContent = ({
        agents: 'Agents', mcps: 'MCPs', toolsets: 'ToolSets', tools: 'Tools', skills: 'Skills', connections: 'Connections', chatbots: 'Chatbots', catalogs: 'Catalogs', transforms: 'Transforms', tokens: 'Tokens', audit: 'Audit'
    })[tab];
    $('btn-new').style.display = (tab === 'tools' || tab === 'skills' || tab === 'catalogs' || tab === 'audit' || tab === 'tokens' || tab === 'transforms') ? 'none' : 'inline-block';
    $('detail-panel').hidden = true;
    loadList();
}

document.querySelectorAll('#tabs button').forEach(b => {
    b.addEventListener('click', () => setTab(b.dataset.tab));
});

// -------- list rendering --------

async function loadList() {
    const list = $('list');
    list.innerHTML = '<div class="empty-state">Loading…</div>';
    try {
        if (state.tab === 'agents') {
            const data = await get('/registry/agents');
            state.list = data.agents || [];
            state.registry.agents = state.list;
            renderAgentList();
        } else if (state.tab === 'mcps') {
            const data = await get('/registry/mcps');
            state.list = data.mcps || [];
            state.registry.mcps = state.list;
            renderMCPList();
        } else if (state.tab === 'toolsets') {
            const data = await get('/registry/toolsets');
            state.list = data.toolsets || [];
            state.registry.toolsets = state.list;
            renderToolSetList();
        } else if (state.tab === 'skills') {
            const data = await get('/registry/skills');
            state.list = data.skills || [];
            state.registry.skills = state.list;
            renderSkillList();
        } else if (state.tab === 'connections') {
            const data = await get('/connections');
            state.list = data.connections || [];
            renderConnectionList();
        } else if (state.tab === 'chatbots') {
            const data = await get('/chatbots');
            state.list = data.chatbots || [];
            renderChatbotList();
        } else if (state.tab === 'catalogs') {
            const data = await get('/catalog/status');
            state.list = [data];
            renderCatalogList();
        } else if (state.tab === 'transforms') {
            await loadTransformInventory();
        } else if (state.tab === 'audit') {
            await loadAuditList();
        } else if (state.tab === 'tokens') {
            await loadTokens();
        } else if (state.tab === 'tools') {
            // Tools view: flatten across all toolsets that the registry knows
            const data = await get('/registry/toolsets');
            state.list = data.toolsets || [];
            state.registry.toolsets = state.list;
            renderToolList();
        }
    } catch (e) {
        list.innerHTML = `<div class="empty-state">Failed: ${e.message}</div>`;
    }
}

function renderAgentList() {
    const list = $('list');
    if (!state.list.length) { list.innerHTML = '<div class="empty-state">No agents.</div>'; return; }
    list.innerHTML = '';
    for (const a of state.list) {
        const div = document.createElement('div');
        div.className = 'list-item';
        div.dataset.id = a.class;
        div.innerHTML = `
            <div class="row1">${escapeHtml(a.name || shortName(a.class))}</div>
            <div class="row2"><code>${escapeHtml(a.class)}</code></div>
            <div class="row2 desc">${escapeHtml((a.description || '').replace(/\s+/g, ' ').trim() || '—')}</div>
        `;
        div.addEventListener('click', () => openAgent(a.class));
        list.appendChild(div);
    }
}

function renderMCPList() {
    const list = $('list');
    if (!state.list.length) { list.innerHTML = '<div class="empty-state">No MCPs.</div>'; return; }
    list.innerHTML = '';
    for (const m of state.list) {
        const div = document.createElement('div');
        div.className = 'list-item';
        div.dataset.id = m.class;
        div.innerHTML = `
            <div class="row1">${escapeHtml(m.name || shortName(m.class))}</div>
            <div class="row2"><code>${escapeHtml(m.class)}</code></div>
            <div class="row2 desc">${escapeHtml((m.shortDescription || m.description || '').replace(/\s+/g, ' ').trim() || '—')}</div>
            <div class="row2">${m.toolsets.length} toolset(s)</div>
        `;
        div.addEventListener('click', () => openMCP(m.class));
        list.appendChild(div);
    }
}

function renderToolSetList() {
    const list = $('list');
    if (!state.list.length) { list.innerHTML = '<div class="empty-state">No Tool classes found.</div>'; return; }
    list.innerHTML = '';
    for (const t of state.list) {
        const div = document.createElement('div');
        div.className = 'list-item';
        div.dataset.id = t.class;
        div.innerHTML = `
            <div class="row1">${escapeHtml(t.name || shortName(t.class))}</div>
            <div class="row2"><code>${escapeHtml(t.class)}</code></div>
            <div class="row2">${t.toolCount || 0} tool(s)</div>
        `;
        div.addEventListener('click', () => openToolSet(t.class));
        list.appendChild(div);
    }
}

function renderSkillList() {
    const list = $('list');
    if (!state.list.length) { list.innerHTML = '<div class="empty-state">No Skills.</div>'; return; }
    list.innerHTML = '';
    for (const s of state.list) {
        const div = document.createElement('div');
        div.className = 'list-item';
        div.dataset.id = s.class;
        div.innerHTML = `
            <div class="row1">${escapeHtml(shortName(s.class))}</div>
            <div class="row2"><code>${escapeHtml(s.class)}</code></div>
            <div class="row2 desc">${escapeHtml((s.description || '').replace(/\s+/g, ' ').trim() || '—')}</div>
            <div class="row2">${s.toolsets.length} toolset(s)</div>
        `;
        div.addEventListener('click', () => openSkill(s.class));
        list.appendChild(div);
    }
}

// LLM Connections — modeled on Catalog.Connections from
// new-interoperability-health. Identity is the connection NAME (frozen on
// create), not a numeric id. Provider is one of openai / anthropic /
// bedrock / gemini / azure-openai / nim. A live "Test" button posts to
// /connections/:name/test which runs %AI.Provider.Create + ChatComplete.
const CONNECTION_PROVIDERS = ['openai','anthropic','bedrock','gemini','azure-openai','nim'];

const CONNECTION_KEY_LABEL = {
    openai:        'OpenAI API key',
    anthropic:     'Anthropic API key',
    bedrock:       'AWS bearer token (AWS_BEARER_TOKEN_BEDROCK)',
    gemini:        'Gemini API key',
    'azure-openai': 'Azure OpenAI key',
    nim:           'NIM API key (optional for local NIM)'
};

function renderConnectionList() {
    const list = $('list');
    if (!state.list.length) {
        list.innerHTML = '<div class="empty-state">No connections configured. Click + New to add one.</div>';
        return;
    }
    list.innerHTML = '';
    for (const c of state.list) {
        const div = document.createElement('div');
        div.className = 'list-item conn-item';
        div.dataset.id = c.name;
        const status = c.lastTestOk === 1 ? 'green' : (c.lastTestOk === 0 ? 'red' : 'unknown');
        const statusLabel = status === 'green' ? 'tested ok' : (status === 'red' ? 'last test failed' : 'untested');
        // One-line meta (kind + status). Latency is the operational
        // detail the user actually cares about; full timestamp goes to
        // the detail page.
        const latency = c.lastTestLatencyMs ? c.lastTestLatencyMs + 'ms' : '';
        const metaParts = [escapeHtml(c.provider || '')];
        if (latency) metaParts.push(escapeHtml(latency));
        metaParts.push(c.hasSecret ? 'API key set' : '<em>no API key</em>');
        const badges = [];
        if (!c.enabled)  badges.push('<span class="badge abstract">disabled</span>');
        if (c.isDefault) badges.push('<span class="badge shipped">default</span>');
        if (c.core)      badges.push('<span class="badge abstract">core</span>');
        div.innerHTML = `
            <div class="row1 conn-row1">
                <span class="status-dot ${status}"></span>
                <span class="conn-name">${escapeHtml(c.displayName || c.name)}</span>
                <span class="conn-badges">${badges.join('')}</span>
            </div>
            <div class="row2 conn-id"><code>${escapeHtml(c.name)}</code></div>
            <div class="row2 conn-meta">${metaParts.join(' · ')}</div>
            <div class="row2 conn-status">${escapeHtml(statusLabel)}${c.lastTestAt ? ' · ' + escapeHtml(c.lastTestAt) : ''}</div>
        `;
        div.addEventListener('click', () => openConnection(c.name));
        list.appendChild(div);
    }
}

async function openConnection(name) {
    try {
        const c = await get('/connections/' + encodeURIComponent(name));
        state.selected = c;
        state.detailKind = 'connection';
        $('detail-panel').hidden = false;
        renderConnectionDetail();
        markListSelected(name);
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

function renderConnectionDetail() {
    const c = state.selected;
    const isNew = !!c._isNew;
    const nameDisplay = c.displayName || c.name || 'New Connection';
    $('detail-title').textContent = isNew ? 'New Connection' : nameDisplay;
    $('btn-delete').style.display = (isNew || c.core) ? 'none' : 'inline-block';
    $('btn-save').disabled = false;
    const status = c.lastTestOk === 1 ? 'green' : (c.lastTestOk === 0 ? 'red' : 'unknown');
    const statusLabel = status === 'green' ? 'tested ok' : (status === 'red' ? 'last test failed' : 'untested');
    const inlineLatency = (status === 'green' && c.lastTestLatencyMs)
        ? `<span class="status-time">${escapeHtml(c.lastTestModel || c.model)} · ${escapeHtml(String(c.lastTestLatencyMs))}ms</span>`
        : '';
    const semaphore = `
        <div class="semaphore status-${status}">
            <span class="status-dot ${status}"></span>
            <span class="status-label">${escapeHtml(statusLabel)}</span>
            ${c.lastTestAt ? `<span class="status-time">checked ${escapeHtml(c.lastTestAt)}</span>` : ''}
            ${inlineLatency}
            <button id="f-test" class="primary" type="button" ${isNew ? 'disabled' : ''}>Test connection</button>
        </div>
        ${(status === 'red' && c.lastTestError) ? `<div class="err-block">${escapeHtml(c.lastTestError)}</div>` : ''}
    `;
    const enabledYes  = c.enabled  === undefined ? true  : !!c.enabled;
    const isDefault   = !!c.isDefault;
    // Connection name is frozen post-create — only editable when _isNew.
    const nameField = isNew
        ? `<div class="field"><label>Name</label><input id="f-name" type="text" value="${escapeAttr(c.name || '')}" placeholder="my-bedrock"><div class="hint">Lowercase, alpha-start, alphanumeric + dash. Used as the lookup key — frozen after save.</div></div>`
        : `<div class="field readonly"><label>Name</label><input type="text" value="${escapeAttr(c.name)}" readonly></div>`;
    $('form').innerHTML = `
        ${nameField}
        <div class="field">
            <label>Display name</label>
            <input id="f-displayName" type="text" value="${escapeAttr(c.displayName || '')}" placeholder="AWS Bedrock (Sonnet 4)">
        </div>
        <div class="field">
            <label>Description</label>
            <textarea id="f-description">${escapeHtml(reflowProse(c.description))}</textarea>
        </div>
        <div class="field-row">
            <div class="field">
                <label>Provider</label>
                <select id="f-provider">
                    ${CONNECTION_PROVIDERS.map(p => `<option value="${p}" ${c.provider === p ? 'selected' : ''}>${p}</option>`).join('')}
                </select>
            </div>
            <div class="field">
                <label>Enabled</label>
                <select id="f-enabled">
                    <option value="true"  ${enabledYes ? 'selected' : ''}>Enabled</option>
                    <option value="false" ${enabledYes ? '' : 'selected'}>Disabled</option>
                </select>
                <div class="hint">Disabled connections are skipped by the chat runtime.</div>
            </div>
            <div class="field">
                <label>Default</label>
                <select id="f-isDefault">
                    <option value="false" ${isDefault ? '' : 'selected'}>No</option>
                    <option value="true"  ${isDefault ? 'selected' : ''}>Yes</option>
                </select>
                <div class="hint">Exactly one row is the default.</div>
            </div>
        </div>
        <div class="field-row">
            <div class="field">
                <label>Model</label>
                <input id="f-model" type="text" value="${escapeAttr(c.model || '')}" placeholder="global.anthropic.claude-sonnet-4-20250514-v1:0">
            </div>
            <div class="field">
                <label>Max tokens</label>
                <input id="f-maxTokens" type="text" value="${escapeAttr(c.maxTokens || '8192')}">
            </div>
        </div>
        <div class="field-row">
            <div class="field">
                <label>Region</label>
                <input id="f-region" type="text" value="${escapeAttr(c.region || '')}" placeholder="us-east-1 (Bedrock / Azure)">
            </div>
            <div class="field">
                <label>Base URL</label>
                <input id="f-baseURL" type="text" value="${escapeAttr(c.baseURL || '')}" placeholder="(optional override)">
            </div>
        </div>
        <div class="field">
            <label>${escapeHtml(CONNECTION_KEY_LABEL[c.provider] || 'API key')}</label>
            <input id="f-secret" type="password" placeholder="${c.hasSecret ? '(stored — paste a new value to replace)' : 'paste the API key'}" autocomplete="new-password">
            <div class="hint">Stored in the IRIS Secured Wallet (collection AgenticInteropConnections). Never echoed back through the API.</div>
        </div>
        ${isNew ? '' : semaphore}
    `;
    bindAutoSizeTextareas($('form'));
    watchFormChanges();
    if (!isNew) {
        $('f-test').addEventListener('click', async () => {
            const btn = $('f-test'); btn.disabled = true;
            try {
                const r = await post('/connections/' + encodeURIComponent(c.name) + '/test', {});
                // Re-fetch to get the persisted row state.
                state.selected = await get('/connections/' + encodeURIComponent(c.name));
                renderConnectionDetail();
                toast(r.ok ? 'Connection OK.' : 'Test failed — see details.', r.ok ? 'success' : 'error');
            } catch (e) {
                showError(e);
            } finally {
                const b2 = $('f-test'); if (b2) b2.disabled = false;
            }
        });
    }
}

// -------- Chatbots (the chatbot -> agent config layer) --------
// Each chatbot is a UI surface (a launcher injected into a host page)
// bound to an %AI.Agent. The chat surface sends the chatbot Key and the
// backend resolves the agent from it at request time — so changing which
// agent a chatbot uses is a one-row edit, no redeploy.

function renderChatbotList() {
    const list = $('list');
    if (!state.list.length) {
        list.innerHTML = '<div class="empty-state">No chatbots configured. Click + New to add one.</div>';
        return;
    }
    list.innerHTML = '';
    for (const c of state.list) {
        const div = document.createElement('div');
        div.className = 'list-item';
        div.dataset.id = c.key;
        const badges = [];
        if (!c.enabled) badges.push('<span class="badge abstract">disabled</span>');
        if (c.core)     badges.push('<span class="badge shipped">core</span>');
        div.innerHTML = `
            <div class="row1">${escapeHtml(c.name || c.key)} <span class="conn-badges">${badges.join('')}</span></div>
            <div class="row2"><code>${escapeHtml(c.key)}</code></div>
            <div class="row2 desc">agent: <code>${escapeHtml(shortName(c.agentClass || '') || '—')}</code></div>
            <div class="row2">${escapeHtml(c.hostApp || '')}</div>
        `;
        div.addEventListener('click', () => openChatbot(c.key));
        list.appendChild(div);
    }
}

async function openChatbot(key) {
    try {
        const c = await get('/chatbots/' + encodeURIComponent(key));
        if (!state.registry.agents) {
            try { const d = await get('/registry/agents'); state.registry.agents = d.agents || []; } catch (e) {}
        }
        state.selected = c;
        state.detailKind = 'chatbot';
        $('detail-panel').hidden = false;
        renderChatbotDetail();
        markListSelected(key);
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

function renderChatbotDetail() {
    const c = state.selected;
    const isNew = !!c._isNew;
    $('detail-title').textContent = isNew ? 'New Chatbot' : (c.name || c.key);
    $('btn-delete').style.display = (isNew || c.core) ? 'none' : 'inline-block';
    $('btn-save').disabled = false;
    const agents = (state.registry && state.registry.agents) || [];
    const agentOptions = agents.map(a =>
        `<option value="${escapeAttr(a.class)}" ${c.agentClass === a.class ? 'selected' : ''}>${escapeHtml(a.name || shortName(a.class))} — ${escapeHtml(a.class)}</option>`
    ).join('');
    const enabledYes = c.enabled === undefined ? true : !!c.enabled;
    const keyField = isNew
        ? `<div class="field"><label>Key</label><input id="f-key" type="text" value="${escapeAttr(c.key || '')}" placeholder="fhir-management"><div class="hint">Lowercase letters/digits/dashes, starting with a letter. The chat surface sends this key; the backend maps it to the agent. Frozen after save.</div></div>`
        : `<div class="field readonly"><label>Key</label><input type="text" value="${escapeAttr(c.key)}" readonly></div>`;
    $('form').innerHTML = `
        ${keyField}
        <div class="field">
            <label>Title</label>
            <input id="f-name" type="text" value="${escapeAttr(c.name || '')}" placeholder="FHIR Assistant">
        </div>
        <div class="field">
            <label>Agent</label>
            <select id="f-agentClass">${agentOptions || '<option value="">(no agents found)</option>'}</select>
            <div class="hint">The %AI.Agent this chatbot runs. Takes effect on the next message — no redeploy.</div>
        </div>
        <div class="field-row">
            <div class="field">
                <label>Host page</label>
                <input id="f-hostApp" type="text" value="${escapeAttr(c.hostApp || '')}" placeholder="/csp/fhir-management">
                <div class="hint">Where this chatbot's launcher is injected (informational).</div>
            </div>
            <div class="field">
                <label>Enabled</label>
                <select id="f-enabled">
                    <option value="true"  ${enabledYes ? 'selected' : ''}>Enabled</option>
                    <option value="false" ${enabledYes ? '' : 'selected'}>Disabled</option>
                </select>
            </div>
        </div>
        <div class="field">
            <label>Subtitle</label>
            <input id="f-subtitle" type="text" value="${escapeAttr(c.subtitle || '')}" placeholder="Short tagline shown under the title">
        </div>
    `;
    watchFormChanges();
}

// Phase 5 catalog admin. Renders one card per catalog (search_ens,
// search_hs) with row count, kind breakdown, test search panel,
// browse panel, and a Rebuild button. Long-running (~30s for both
// catalogs); the button shows BUILDING while it waits.
function renderCatalogList() {
    const list = $('list');
    const status = state.list[0] || {};
    list.innerHTML = '';
    const sourceNs = renderCatalogControls();
    list.appendChild(sourceNs);
    list.appendChild(renderCatalogCard('search_ens', 'Ens.* business hosts and adapters in the active interop namespace.', status.ens || {}));
    list.appendChild(renderCatalogCard('search_hs',  'HealthShare HS.* transformation classes — DTLs, FHIR/SDA3 mappers, HL7 helpers.', status.hs  || {}));
    list.appendChild(renderCatalogSearchPanel());
    list.appendChild(renderCatalogBrowsePanel());
}

function renderCatalogControls() {
    const wrap = document.createElement('div');
    wrap.className = 'list-item';
    wrap.style.cursor = 'default';
    wrap.innerHTML = `
        <div class="row1">Catalog rebuild source</div>
        <div class="row2 desc">Rebuild walks <code>%Dictionary</code> in the named source namespace. The catalog itself persists in HSCUSTOM (the install namespace); only the dictionary read is namespace-scoped.</div>
        <div class="field-row" style="margin-top:8px;">
            <div class="field" style="margin:0;">
                <label>Source namespace</label>
                <input id="f-catalog-ns" type="text" value="USER" style="max-width:200px;">
            </div>
            <div class="field" style="margin:0;">
                <label>Cap (max rows per catalog)</label>
                <input id="f-catalog-cap" type="text" value="2000" style="max-width:200px;">
            </div>
        </div>
    `;
    return wrap;
}

function renderCatalogCard(name, description, st) {
    const card = document.createElement('div');
    card.className = 'list-item';
    card.style.cursor = 'default';
    const rowsLine = st.exists
        ? `<span class="badge user">${st.rows || 0} rows indexed</span>`
        : `<span class="badge abstract">not built</span>`;
    // Kind breakdown badges
    let kindHtml = '';
    if (st.kinds && st.kinds.length) {
        kindHtml = '<div class="row2" style="margin-top:4px;display:flex;flex-wrap:wrap;gap:4px;">';
        for (const k of st.kinds) {
            kindHtml += `<span class="badge" style="font-size:10px;padding:1px 6px;">${escapeHtml(k.kind || '?')}: ${k.count}</span>`;
        }
        kindHtml += '</div>';
    }
    card.innerHTML = `
        <div class="row1">${escapeHtml(name)} ${rowsLine}</div>
        <div class="row2 desc">${escapeHtml(description)}</div>
        <div class="row2"><code>${escapeHtml(st.table || '')}</code></div>
        ${kindHtml}
        <div class="row2" style="margin-top:6px;">
            <button class="primary" data-rebuild="${name === 'search_ens' ? 'ens' : 'hs'}">Rebuild this catalog</button>
            <span class="rebuild-status" style="margin-left:10px;color:var(--muted);font-size:11px;"></span>
        </div>
    `;
    card.querySelector('button[data-rebuild]').addEventListener('click', (e) => {
        const scope = e.currentTarget.dataset.rebuild;
        rebuildCatalog(scope, e.currentTarget, card.querySelector('.rebuild-status'));
    });
    return card;
}

// Test Search panel — type a query, pick a catalog, see the ranked
// results with similarity scores. This is the most direct way to
// verify "does the agent find the right class for this question?"
function renderCatalogSearchPanel() {
    const panel = document.createElement('div');
    panel.className = 'list-item';
    panel.style.cursor = 'default';
    panel.innerHTML = `
        <div class="row1">Test search</div>
        <div class="row2 desc">Type a query to see what the agent's vector search returns. These are the exact results the agent sees at chat time.</div>
        <div class="field-row" style="margin-top:8px;">
            <div class="field" style="margin:0;flex:1;">
                <label>Query</label>
                <input id="f-search-query" type="text" placeholder="e.g. convert HL7 to FHIR" style="width:100%;">
            </div>
            <div class="field" style="margin:0;">
                <label>Catalog</label>
                <select id="f-search-catalog" style="min-width:100px;">
                    <option value="ens">search_ens</option>
                    <option value="hs">search_hs</option>
                </select>
            </div>
            <div class="field" style="margin:0;">
                <label>Top K</label>
                <input id="f-search-k" type="number" value="8" min="1" max="20" style="width:60px;">
            </div>
            <div class="field" style="margin:0;align-self:flex-end;">
                <button class="primary" id="btn-test-search">Search</button>
            </div>
        </div>
        <div id="search-results" style="margin-top:8px;"></div>
    `;
    panel.querySelector('#btn-test-search').addEventListener('click', runCatalogSearch);
    // Also run on Enter in the query input
    panel.querySelector('#f-search-query').addEventListener('keydown', (e) => {
        if (e.key === 'Enter') runCatalogSearch();
    });
    return panel;
}

async function runCatalogSearch() {
    const query = ($('f-search-query')?.value || '').trim();
    const catalog = $('f-search-catalog')?.value || 'ens';
    const k = Number($('f-search-k')?.value) || 8;
    const resultsEl = $('search-results');
    if (!query) { resultsEl.innerHTML = '<div style="color:var(--muted);font-size:12px;">Enter a query above.</div>'; return; }
    resultsEl.innerHTML = '<div style="color:var(--muted);font-size:12px;">Searching...</div>';
    try {
        const r = await post('/catalog/search', { catalog, query, k });
        if (!r.ok) { resultsEl.innerHTML = `<div style="color:var(--danger);">Error: ${escapeHtml(r.error)}</div>`; return; }
        if (!r.results || !r.results.length) { resultsEl.innerHTML = '<div style="color:var(--muted);font-size:12px;">No results.</div>'; return; }
        let html = '<table style="width:100%;border-collapse:collapse;font-size:12px;">';
        html += '<thead><tr style="text-align:left;border-bottom:1px solid var(--border);">';
        html += '<th style="padding:4px 8px;width:30px;">#</th>';
        html += '<th style="padding:4px 8px;">Class</th>';
        html += '<th style="padding:4px 8px;width:60px;">Kind</th>';
        html += '<th style="padding:4px 8px;width:60px;">Score</th>';
        html += '</tr></thead><tbody>';
        for (const res of r.results) {
            const meta = res.metadata || {};
            const cls = meta.className || '(unknown)';
            const kind = meta.kind || '';
            const score = typeof res.score === 'number' ? res.score.toFixed(4) : res.score || '';
            // Truncate text for the expandable preview
            const textPreview = (res.text || '').substring(0, 200);
            html += `<tr style="border-bottom:1px solid var(--border);cursor:pointer;" class="search-result-row">`;
            html += `<td style="padding:4px 8px;vertical-align:top;">${res.rank}</td>`;
            html += `<td style="padding:4px 8px;"><strong>${escapeHtml(cls)}</strong><div style="color:var(--muted);font-size:11px;margin-top:2px;white-space:pre-wrap;">${escapeHtml(textPreview)}${(res.text||'').length > 200 ? '...' : ''}</div></td>`;
            html += `<td style="padding:4px 8px;vertical-align:top;"><span class="badge" style="font-size:10px;">${escapeHtml(kind)}</span></td>`;
            html += `<td style="padding:4px 8px;vertical-align:top;font-family:monospace;">${escapeHtml(score)}</td>`;
            html += '</tr>';
        }
        html += '</tbody></table>';
        resultsEl.innerHTML = html;
    } catch (e) {
        resultsEl.innerHTML = `<div style="color:var(--danger);">Failed: ${escapeHtml(e.message)}</div>`;
    }
}

// Browse panel — paginated table of all entries in a catalog,
// filterable by text substring and kind.
function renderCatalogBrowsePanel() {
    const panel = document.createElement('div');
    panel.className = 'list-item';
    panel.style.cursor = 'default';
    panel.innerHTML = `
        <div class="row1">Browse catalog entries</div>
        <div class="row2 desc">View all indexed entries. Filter by class name or kind to verify coverage.</div>
        <div class="field-row" style="margin-top:8px;">
            <div class="field" style="margin:0;">
                <label>Catalog</label>
                <select id="f-browse-catalog" style="min-width:100px;">
                    <option value="ens">search_ens</option>
                    <option value="hs">search_hs</option>
                </select>
            </div>
            <div class="field" style="margin:0;flex:1;">
                <label>Filter (class name substring)</label>
                <input id="f-browse-filter" type="text" placeholder="e.g. Gateway, FHIR, Patient" style="width:100%;">
            </div>
            <div class="field" style="margin:0;">
                <label>Kind</label>
                <input id="f-browse-kind" type="text" placeholder="e.g. Gateway, FHIR-DTL" style="width:120px;">
            </div>
            <div class="field" style="margin:0;align-self:flex-end;">
                <button class="primary" id="btn-browse">Browse</button>
            </div>
        </div>
        <div id="browse-results" style="margin-top:8px;"></div>
        <div id="browse-pager" style="margin-top:6px;display:flex;gap:8px;align-items:center;"></div>
    `;
    panel.querySelector('#btn-browse').addEventListener('click', () => loadCatalogBrowse(1));
    panel.querySelector('#f-browse-filter').addEventListener('keydown', (e) => {
        if (e.key === 'Enter') loadCatalogBrowse(1);
    });
    panel.querySelector('#f-browse-kind').addEventListener('keydown', (e) => {
        if (e.key === 'Enter') loadCatalogBrowse(1);
    });
    return panel;
}

async function loadCatalogBrowse(page) {
    const catalog = $('f-browse-catalog')?.value || 'ens';
    const filter = ($('f-browse-filter')?.value || '').trim();
    const kind = ($('f-browse-kind')?.value || '').trim();
    const resultsEl = $('browse-results');
    const pagerEl = $('browse-pager');
    resultsEl.innerHTML = '<div style="color:var(--muted);font-size:12px;">Loading...</div>';
    pagerEl.innerHTML = '';
    try {
        const params = new URLSearchParams({ catalog, page, pageSize: 30 });
        if (filter) params.set('filter', filter);
        if (kind) params.set('kind', kind);
        const r = await get('/catalog/browse?' + params.toString());
        if (!r.ok) { resultsEl.innerHTML = `<div style="color:var(--danger);">Error: ${escapeHtml(r.error)}</div>`; return; }
        if (!r.entries || !r.entries.length) {
            resultsEl.innerHTML = '<div style="color:var(--muted);font-size:12px;">No entries match the filter.</div>';
            return;
        }
        let html = `<div style="font-size:11px;color:var(--muted);margin-bottom:4px;">${r.total} total entries, page ${r.page} of ${r.totalPages}</div>`;
        html += '<table style="width:100%;border-collapse:collapse;font-size:12px;">';
        html += '<thead><tr style="text-align:left;border-bottom:1px solid var(--border);">';
        html += '<th style="padding:4px 8px;">Class</th>';
        html += '<th style="padding:4px 8px;width:80px;">Kind</th>';
        html += '<th style="padding:4px 8px;">Embedded text</th>';
        html += '</tr></thead><tbody>';
        for (const entry of r.entries) {
            const meta = entry.metadata || {};
            const cls = meta.className || entry.source || '(unknown)';
            const entryKind = meta.kind || '';
            const text = (entry.text || '').substring(0, 250);
            html += '<tr style="border-bottom:1px solid var(--border);">';
            html += `<td style="padding:4px 8px;vertical-align:top;white-space:nowrap;"><strong>${escapeHtml(cls)}</strong></td>`;
            html += `<td style="padding:4px 8px;vertical-align:top;"><span class="badge" style="font-size:10px;">${escapeHtml(entryKind)}</span></td>`;
            html += `<td style="padding:4px 8px;font-size:11px;color:var(--muted);white-space:pre-wrap;">${escapeHtml(text)}${(entry.text||'').length > 250 ? '...' : ''}</td>`;
            html += '</tr>';
        }
        html += '</tbody></table>';
        resultsEl.innerHTML = html;
        // Pager buttons
        let pagerHtml = '';
        if (r.page > 1) {
            pagerHtml += `<button class="secondary" data-page="${r.page - 1}">Previous</button>`;
        }
        pagerHtml += `<span style="font-size:12px;color:var(--muted);">Page ${r.page} / ${r.totalPages}</span>`;
        if (r.page < r.totalPages) {
            pagerHtml += `<button class="secondary" data-page="${r.page + 1}">Next</button>`;
        }
        pagerEl.innerHTML = pagerHtml;
        pagerEl.querySelectorAll('button[data-page]').forEach(btn => {
            btn.addEventListener('click', () => loadCatalogBrowse(Number(btn.dataset.page)));
        });
    } catch (e) {
        resultsEl.innerHTML = `<div style="color:var(--danger);">Failed: ${escapeHtml(e.message)}</div>`;
    }
}

async function rebuildCatalog(scope, btn, statusEl) {
    const sourceNamespace = ($('f-catalog-ns')?.value || 'USER').trim();
    const cap = Number($('f-catalog-cap')?.value) || 2000;
    btn.disabled = true;
    statusEl.textContent = 'BUILDING — embedding can run 10-60 seconds...';
    try {
        const r = await post('/catalog/rebuild', { sourceNamespace, scope, cap });
        const block = scope === 'ens' ? r.ens : r.hs;
        if (block) {
            statusEl.textContent = `built -- scanned ${block.scanned}, indexed ${block.indexed} in ${block.elapsedMs}ms`;
        } else if (r.ok) {
            statusEl.textContent = 'built';
        } else {
            statusEl.textContent = 'FAILED -- ' + (r.error || 'unknown error');
        }
        toast('Catalog rebuilt.', 'success');
        // Refresh the status display
        if (state.tab === 'catalogs') loadList();
    } catch (e) {
        statusEl.textContent = 'FAILED -- ' + e.message;
        showError(e);
    } finally {
        btn.disabled = false;
    }
}


// ─── Transforms tab ──────────────────────────────────────────────
// Split-panel mapping tool. Left sidebar: SDA type browser.
// Right main area: three-column field-level trace (the star).
// Auto-selects the first SDA type so field mappings are visible
// immediately after choosing source and target formats.

let _tfData = null;          // cached inventory response
let _tfFieldCache = {};      // DTL field cache: className → response
let _tfCurrentTrace = [];    // current trace rows
let _tfActiveNode = null;    // currently-selected SDA type

async function loadTransformInventory() {
    var list = $('list');
    list.innerHTML = '<div class="empty-state">Loading transformation inventory...</div>';
    try {
        _tfData = await get('/transforms/inventory');
        _tfActiveNode = null;
        renderTransformsTab();
    } catch (e) {
        list.innerHTML = '<div class="empty-state">Failed: ' + escapeHtml(e.message) + '</div>';
    }
}

function renderTransformsTab() {
    var list = $('list');
    list.innerHTML = '';
    if (!_tfData || !_tfData.ok) {
        list.innerHTML = '<div class="empty-state">No data.</div>';
        return;
    }

    // Include SDA3 as a selectable format alongside external formats
    var formats = _tfData.formats || [];
    var allFormats = ['SDA3'].concat(formats);
    var srcOpts = '<option value="">Select...</option>';
    var tgtOpts = '<option value="">Select...</option>';
    for (var i = 0; i < allFormats.length; i++) {
        srcOpts += '<option value="' + escapeAttr(allFormats[i]) + '">' + escapeHtml(allFormats[i]) + '</option>';
        tgtOpts += '<option value="' + escapeAttr(allFormats[i]) + '">' + escapeHtml(allFormats[i]) + '</option>';
    }

    var view = document.createElement('div');
    view.className = 'tf-view';

    view.innerHTML =
        '<div class="tf-controls">' +
            '<div class="tf-ctrl-select">' +
                '<label>Data From</label>' +
                '<select id="tf-sel-src">' + srcOpts + '</select>' +
            '</div>' +
            '<div class="tf-ctrl-arrow">' +
                '<div class="tf-ctrl-arrow-line"></div>' +
                '<div class="tf-ctrl-arrow-head"></div>' +
            '</div>' +
            '<div class="tf-ctrl-select">' +
                '<label>Data To</label>' +
                '<select id="tf-sel-tgt">' + tgtOpts + '</select>' +
            '</div>' +
            '<div class="tf-ctrl-actions">' +
                '<button class="btn btn-sm" id="tf-rebuild-btn" title="Rebuild the pre-computed field mapping table from current IRIS classes">Rebuild Mappings</button>' +
                '<span class="tf-rebuild-status" id="tf-rebuild-status"></span>' +
            '</div>' +
        '</div>' +
        '<div class="tf-body" id="tf-body">' +
            '<div class="tf-empty-prompt">Select a source and target format above to explore field-level transformation mappings.</div>' +
        '</div>';

    list.appendChild(view);

    var srcSel = $('tf-sel-src');
    var tgtSel = $('tf-sel-tgt');
    if (srcSel) srcSel.addEventListener('change', tfUpdateView);
    if (tgtSel) tgtSel.addEventListener('change', tfUpdateView);

    // Wire rebuild button
    var rebuildBtn = $('tf-rebuild-btn');
    if (rebuildBtn) {
        rebuildBtn.addEventListener('click', tfDoRebuild);
    }
    // Load field-trace status
    tfLoadRebuildStatus();
}

function tfUpdateView() {
    var srcSel = $('tf-sel-src');
    var tgtSel = $('tf-sel-tgt');
    var body = $('tf-body');
    if (!body) return;

    var src = srcSel ? srcSel.value : '';
    var tgt = tgtSel ? tgtSel.value : '';
    _tfActiveNode = null;

    if (!src || !tgt) {
        body.innerHTML = '<div class="tf-empty-prompt">Select a source and target format above to explore field-level transformation mappings.</div>';
        return;
    }
    if (src === tgt) {
        body.innerHTML = '<div class="tf-empty-prompt">Source and target are the same format.</div>';
        return;
    }

    // When SDA3 is involved (half-chain), load SDA type list from backend
    // instead of computing from pipeline metadata
    if (src === 'SDA3' || tgt === 'SDA3') {
        tfUpdateViewFromTable(src, tgt, body);
        return;
    }

    var pipelines = _tfData ? _tfData.pipelines || [] : [];
    var inbound = pipelines.find(function(p) { return p.source === src && p.target === 'SDA3'; });
    var outbound = pipelines.find(function(p) { return p.source === 'SDA3' && p.target === tgt; });

    if (!inbound && !outbound) {
        body.innerHTML = '<div class="tf-empty-prompt">No transformation pipeline found for ' + escapeHtml(src) + ' to ' + escapeHtml(tgt) + '.</div>';
        return;
    }

    var trace = tfComputeTrace(inbound, outbound);
    _tfCurrentTrace = trace;

    tfRenderSplitLayout(body, trace, src, tgt);
}

// Render when SDA3 is one endpoint — queries the pre-computed table for SDA type list
async function tfUpdateViewFromTable(src, tgt, body) {
    body.innerHTML = '<div class="tf-field-loading">Loading SDA types from mapping table...</div>';

    // Query for all types available in this direction
    var url = '/transforms/field-trace?source=' + encodeURIComponent(src) +
        '&target=' + encodeURIComponent(tgt);
    try {
        var data = await get(url);
        if (!data || !data.ok || data.count === 0) {
            body.innerHTML = '<div class="tf-empty-prompt">No mappings found for ' + escapeHtml(src) + ' to ' + escapeHtml(tgt) + '. Click "Rebuild Mappings" to populate.</div>';
            return;
        }

        // Group by SDA type
        var byType = {};
        var mappings = data.mappings || [];
        for (var i = 0; i < mappings.length; i++) {
            var m = mappings[i];
            var t = m.sdaType || '(unknown)';
            if (!byType[t]) byType[t] = [];
            byType[t].push(m);
        }

        // Build trace-like structure for the sidebar
        var trace = [];
        var types = Object.keys(byType).sort();
        for (var i = 0; i < types.length; i++) {
            var rows = byType[types[i]];
            var completeCount = rows.filter(function(r) { return r.status === 'complete'; }).length;
            trace.push({
                sdaType: types[i],
                inClasses: [],
                outClasses: [],
                inMonolithic: false,
                outMonolithic: false,
                status: completeCount > 0 ? 'complete' : 'inbound-only',
                _tableRows: rows
            });
        }
        _tfCurrentTrace = trace;
        tfRenderSplitLayout(body, trace, src, tgt);

    } catch (e) {
        body.innerHTML = '<div class="tf-empty-prompt">Error loading mappings: ' + escapeHtml(e.message) + '</div>';
    }
}

// Shared split-layout renderer used by both pipeline and table paths
function tfRenderSplitLayout(body, trace, src, tgt) {
    var complete = trace.filter(function(r) { return r.status === 'complete'; }).length;
    var inOnly = trace.filter(function(r) { return r.status === 'inbound-only'; }).length;
    var outOnly = trace.filter(function(r) { return r.status === 'outbound-only'; }).length;

    var html = '<div class="tf-split">';

    // ── Left sidebar: SDA type browser
    html += '<div class="tf-sidebar" id="tf-sidebar">';
    html += '<div class="tf-sidebar-hdr">';
    html += '<div class="tf-sidebar-title">SDA3 Data Types</div>';
    html += '<input type="text" class="tf-sidebar-filter" id="tf-type-filter" placeholder="Filter types..." autocomplete="off">';
    html += '</div>';
    html += '<div class="tf-sidebar-list" id="tf-sidebar-list">';
    for (var i = 0; i < trace.length; i++) {
        var r = trace[i];
        var statusCls = r.status === 'complete' ? 'tf-type-complete' :
                        r.status === 'inbound-only' ? 'tf-type-in' : 'tf-type-out';
        html += '<div class="tf-type-item ' + statusCls + '" data-idx="' + i + '" data-sda="' + escapeAttr(r.sdaType) + '" data-search="' + escapeAttr(r.sdaType.toLowerCase()) + '">' +
            '<span class="tf-type-dot"></span>' +
            '<span class="tf-type-name">' + escapeHtml(r.sdaType) + '</span>' +
            '</div>';
    }
    html += '</div>';
    html += '<div class="tf-sidebar-footer">';
    html += '<span>' + trace.length + ' types</span>';
    html += '<span class="tf-sidebar-ct-ok">' + complete + ' complete</span>';
    if (inOnly > 0) html += '<span class="tf-sidebar-ct-in">' + inOnly + ' in only</span>';
    if (outOnly > 0) html += '<span class="tf-sidebar-ct-out">' + outOnly + ' out only</span>';
    html += '</div>';
    html += '</div>';

    // ── Right main area: field-level trace
    html += '<div class="tf-main" id="tf-main">';
    html += '<div class="tf-main-prompt">Select a data type from the list to view field-level mappings.</div>';
    html += '</div>';

    html += '</div>'; // end tf-split
    body.innerHTML = html;

    // Wire sidebar interactions
    tfWireSidebar(src, tgt);

    // Auto-select first complete type (or first type if none complete)
    var firstComplete = trace.findIndex(function(r) { return r.status === 'complete'; });
    var autoIdx = firstComplete >= 0 ? firstComplete : 0;
    if (trace.length > 0) {
        tfSelectType(autoIdx, src, tgt);
    }
}

// ── Sidebar interactions ────────────────────────────────────────

function tfWireSidebar(src, tgt) {
    // Click a type → load its field trace
    var list = $('tf-sidebar-list');
    if (list) {
        list.addEventListener('click', function(e) {
            var item = e.target.closest('.tf-type-item');
            if (!item) return;
            var idx = parseInt(item.dataset.idx);
            tfSelectType(idx, src, tgt);
        });
    }

    // Filter input
    var filter = $('tf-type-filter');
    if (filter) {
        filter.addEventListener('input', function() {
            var q = filter.value.toLowerCase().trim();
            var items = document.querySelectorAll('.tf-type-item');
            items.forEach(function(el) {
                el.style.display = (!q || el.dataset.search.indexOf(q) !== -1) ? '' : 'none';
            });
        });
    }
}

function tfSelectType(idx, src, tgt) {
    var row = _tfCurrentTrace[idx];
    if (!row) return;

    _tfActiveNode = row.sdaType;

    // Highlight active item in sidebar
    document.querySelectorAll('.tf-type-item').forEach(function(el) {
        el.classList.toggle('tf-type-active', parseInt(el.dataset.idx) === idx);
    });

    // Load field trace into main area
    var main = $('tf-main');
    if (!main) return;

    // Build title based on whether SDA3 is an endpoint or middle pivot
    var titleParts = [];
    if (src !== 'SDA3') titleParts.push(escapeHtml(src));
    titleParts.push('SDA3.' + escapeHtml(row.sdaType));
    if (tgt !== 'SDA3') titleParts.push(escapeHtml(tgt));
    var titleStr = titleParts.join('  &rarr;  ');

    main.innerHTML =
        '<div class="tf-main-hdr">' +
            '<div class="tf-main-title">' + titleStr + '</div>' +
            '<div class="tf-field-filter-wrap"><input type="text" class="tf-field-filter" id="tf-field-filter" placeholder="Filter fields..." autocomplete="off" oninput="tfDoFieldFilter()"></div>' +
        '</div>' +
        '<div id="tf-field-area"><div class="tf-field-loading">Loading field-level mappings...</div></div>';

    // If we have pre-loaded table rows from the SDA3 half-chain path, use them directly
    if (row._tableRows) {
        var model = tfTableToModel(row._tableRows);
        var tableInfo = { fromTable: true, source: src, target: tgt, sdaType: row.sdaType, count: row._tableRows.length };
        var area = $('tf-field-area');
        if (area) {
            tfRenderThreeColumns(area, model, src, tgt, tableInfo, tableInfo, row);
            tfWireFieldFilter();
        }
    } else {
        tfLoadFieldTrace(row, src, tgt);
    }
}

async function tfLoadFieldTrace(row, src, tgt) {
    var area = $('tf-field-area');
    if (!area) return;

    // ── Try pre-computed table first (instant, no parsing) ──
    var tableRows = await tfQueryTable(src, tgt, row.sdaType);
    if (tableRows && tableRows.length > 0) {
        if (_tfActiveNode !== row.sdaType) return;
        var model = tfTableToModel(tableRows);
        var tableInfo = { fromTable: true, source: src, target: tgt, sdaType: row.sdaType, count: tableRows.length };
        tfRenderThreeColumns(area, model, src, tgt, tableInfo, tableInfo, row);
        tfWireFieldFilter();
        return;
    }

    // ── Fallback: live parsing (slower but works without rebuild) ──
    var inData = null;
    var outData = null;
    var fetches = [];

    // Inbound: DTL-based or HL7 programmatic extraction
    if (row.inClasses.length > 0 && !row.inMonolithic) {
        fetches.push(tfFetchFields(row.inClasses[0].name).then(function(d) { inData = d; }));
    } else if (row.inMonolithic && src.indexOf('HL7') !== -1) {
        // HL7 programmatic: use the HL7 field extraction endpoint
        fetches.push(get('/transforms/hl7-fields?sdaType=' + encodeURIComponent(row.sdaType)).then(function(d) { inData = d; }));
    }

    // Outbound: DTL-based or HL7 programmatic extraction
    if (row.outClasses.length > 0 && !row.outMonolithic) {
        fetches.push(tfFetchFields(row.outClasses[0].name).then(function(d) { outData = d; }));
    } else if (row.outMonolithic && tgt.indexOf('HL7') !== -1) {
        fetches.push(get('/transforms/hl7-fields?sdaType=' + encodeURIComponent(row.sdaType)).then(function(d) { outData = d; }));
    }

    await Promise.all(fetches);

    if (_tfActiveNode !== row.sdaType) return; // user switched during fetch

    // HL7 data arrives pre-processed (sourceField + targetField already set);
    // DTL data needs extraction through tfExtractCleanMappings
    var inMappings = null;
    if (inData && inData.ok) {
        inMappings = inData.hl7 ? inData.mappings : tfExtractCleanMappings(inData);
    }
    var outMappings = null;
    if (outData && outData.ok) {
        outMappings = outData.hl7 ? outData.mappings : tfExtractCleanMappings(outData);
    }

    if (!inMappings && !outMappings) {
        var msg = 'No field-level mappings available for this data type. Click "Rebuild Mappings" to populate the mapping table.';
        area.innerHTML = '<div class="tf-field-loading">' + msg + '</div>';
        return;
    }

    var model = tfBuildFieldModel(inMappings, outMappings);
    tfRenderThreeColumns(area, model, src, tgt, inData, outData, row);
    tfWireFieldFilter();
}

// Convert table rows (from persistent FieldMapping) into the same model
// format that tfBuildFieldModel returns for the three-column renderer.
function tfTableToModel(tableRows) {
    var rows = [];
    for (var i = 0; i < tableRows.length; i++) {
        var r = tableRows[i];
        rows.push({
            sdaKey: r.sdaNormalized || r.sdaField,
            sdaField: r.sdaField || r.sdaNormalized,
            srcField: r.sourceField || null,
            tgtField: r.targetField || null,
            srcClass: r.sourceClass || null,
            tgtClass: r.targetClass || null,
            status: r.status || 'complete'
        });
    }
    return rows;
}

// ── Field detail panel — three-column field-level trace ──────────
// Shows the complete field journey: Source Field → SDA3 Field → Target Field
// SDA3 is always the visible center pivot. SVG connectors on both sides.

// ── Clean field extraction ──────────────────────────────────────
// For each target.X write in the DTL, find the closest source.Y reference
// looking backwards through preceding assigns. Returns one clean pair per
// unique SDA field base name.

function tfExtractCleanMappings(dtlData) {
    var assigns = (dtlData.mappings || []).filter(function(m) { return m.type === 'assign'; });
    var results = [];

    for (var i = 0; i < assigns.length; i++) {
        var tgt = assigns[i].target || '';
        if (tgt.indexOf('target.') !== 0) continue;
        var targetField = tgt.substring(7);
        if (targetField === '' || targetField === 'extension') continue;

        // Walk backwards to find the closest source.X reference
        var sourceField = null;
        for (var j = i; j >= Math.max(0, i - 8); j--) {
            var src = assigns[j].source || '';
            var match = src.match(/source\.([A-Za-z0-9_.()[\]]+)/);
            if (match) {
                sourceField = match[1].replace(/\)+$/, ''); // strip trailing )
                break;
            }
        }

        results.push({
            sourceField: sourceField || null,
            targetField: targetField
        });
    }

    // Deduplicate by target base field name (keep first occurrence)
    var seen = {};
    var deduped = [];
    for (var i = 0; i < results.length; i++) {
        var base = tfNormalizeSdaKey(results[i].targetField);
        if (!seen[base]) {
            seen[base] = true;
            deduped.push(results[i]);
        }
    }
    return deduped;
}

// Normalize an SDA field name to a base key for joining.
// Strips .Code, .Description, .SDACodingStandard, array indexes, etc.
function tfNormalizeSdaKey(field) {
    if (!field) return '';
    return field
        .replace(/\)+$/, '')           // trailing parens
        .split('.')[0]                 // base property name
        .split('(')[0]                 // strip array index
        .replace(/^\s+|\s+$/g, '');    // trim
}

// ── Three-column model builder ──────────────────────────────────
// Joins inbound (source→SDA) and outbound (SDA→target) on the SDA field name.
// Returns an array of rows, each with: { sdaField, srcField, tgtField, status }

function tfBuildFieldModel(inMappings, outMappings) {
    // Build lookup: normalized SDA key → { srcField, sdaRaw, className }
    var inBySda = {};
    if (inMappings) {
        for (var i = 0; i < inMappings.length; i++) {
            var key = tfNormalizeSdaKey(inMappings[i].targetField);
            if (key && !inBySda[key]) {
                inBySda[key] = {
                    srcField: inMappings[i].sourceField,
                    sdaRaw: inMappings[i].targetField,
                    className: inMappings[i].className || null
                };
            }
        }
    }

    // Build lookup: normalized SDA key → { tgtField, sdaRaw, className }
    var outBySda = {};
    if (outMappings) {
        for (var i = 0; i < outMappings.length; i++) {
            var key = tfNormalizeSdaKey(outMappings[i].sourceField);
            if (key && !outBySda[key]) {
                outBySda[key] = {
                    tgtField: outMappings[i].targetField,
                    sdaRaw: outMappings[i].sourceField,
                    className: outMappings[i].className || null
                };
            }
        }
    }

    // Union all SDA keys
    var allKeys = {};
    var k;
    for (k in inBySda) allKeys[k] = true;
    for (k in outBySda) allKeys[k] = true;

    var rows = [];
    var sorted = Object.keys(allKeys).sort();
    for (var i = 0; i < sorted.length; i++) {
        var sda = sorted[i];
        var inEntry = inBySda[sda];
        var outEntry = outBySda[sda];
        var sdaDisplay = (inEntry ? inEntry.sdaRaw : outEntry ? outEntry.sdaRaw : sda);
        // Clean display name
        sdaDisplay = sdaDisplay.replace(/\)+$/, '');

        var status = (inEntry && outEntry) ? 'complete' :
                     inEntry ? 'in-only' : 'out-only';

        rows.push({
            sdaKey: sda,
            sdaField: sdaDisplay,
            srcField: inEntry ? inEntry.srcField : null,
            tgtField: outEntry ? outEntry.tgtField : null,
            srcClass: inEntry ? inEntry.className : null,
            tgtClass: outEntry ? outEntry.className : null,
            status: status
        });
    }

    return rows;
}

// ── Three-column renderer ───────────────────────────────────────
// Five-part flex layout: [src-col] [left-svg] [sda-col] [right-svg] [tgt-col]

function tfRenderThreeColumns(container, model, src, tgt, inData, outData, row) {
    _tfCurrentFilterModel = model;

    if (model.length === 0) {
        container.innerHTML = '<div class="tf-field-loading">No field mappings found. Click "Rebuild Mappings" to populate.</div>';
        return;
    }

    // Sort: mapped (complete) first, then source-only, then target-only.
    // Within each group, keep alphabetical by SDA field.
    var statusOrder = { 'complete': 0, 'in-only': 1, 'out-only': 2 };
    model.sort(function(a, b) {
        var sa = statusOrder[a.status] !== undefined ? statusOrder[a.status] : 1;
        var sb = statusOrder[b.status] !== undefined ? statusOrder[b.status] : 1;
        if (sa !== sb) return sa - sb;
        return (a.sdaField || '').localeCompare(b.sdaField || '');
    });

    // Column headers
    var colSrc = (src === 'SDA3') ? null : src;
    var colSda = 'SDA3';
    var colTgt = (tgt === 'SDA3') ? null : tgt;

    // Build human-readable descriptions for each coverage status.
    // These explain what the data means in context of the chosen formats.
    var srcName = src || 'Source';
    var tgtName = tgt || 'Target';
    var descOk, descIn, descOut;
    if (colSrc && colTgt) {
        // Full chain: e.g. HL7 v2 → SDA3 → FHIR R4
        descOk  = 'Field traced end-to-end: ' + srcName + ' field maps into SDA3, and SDA3 maps out to ' + tgtName;
        descIn  = 'Field arrives from ' + srcName + ' into SDA3, but SDA3 does not map it out to ' + tgtName;
        descOut = 'Field is produced in ' + tgtName + ' from SDA3, but no ' + srcName + ' field feeds into it';
    } else if (!colSrc) {
        // SDA3 → X
        descOk  = 'SDA3 field maps to ' + tgtName;
        descIn  = 'SDA3 field exists but has no ' + tgtName + ' target';
        descOut = tgtName + ' field exists but no SDA3 source feeds it';
    } else {
        // X → SDA3
        descOk  = srcName + ' field maps into SDA3';
        descIn  = srcName + ' field exists but does not arrive in SDA3';
        descOut = 'SDA3 field exists but no ' + srcName + ' source feeds it';
    }

    // The SDA type name is included in the search index so that
    // filtering "add" while viewing "Address" still shows all rows
    var sdaContext = (row && row.sdaType) ? row.sdaType.toLowerCase() : '';

    // Count stats
    var counts = { complete: 0, inOnly: 0, outOnly: 0 };
    for (var i = 0; i < model.length; i++) {
        if (model[i].status === 'complete') counts.complete++;
        else if (model[i].status === 'in-only') counts.inOnly++;
        else counts.outOnly++;
    }

    var html = '';

    // Coverage filter bar — clickable chips that toggle row visibility
    html += '<div class="tf-coverage-bar">';
    html += '<div class="tf-coverage-label">Show:</div>';
    html += '<button class="tf-cov-chip tf-cov-active" data-cov="complete" onclick="tfToggleCov(this)" title="' + escapeAttr(descOk) + '">';
    html += '<span class="tf-cov-dot tf-cov-dot-ok"></span> End-to-end <span class="tf-cov-count">' + counts.complete + '</span></button>';
    if (counts.inOnly > 0) {
        html += '<button class="tf-cov-chip tf-cov-active" data-cov="in-only" onclick="tfToggleCov(this)" title="' + escapeAttr(descIn) + '">';
        html += '<span class="tf-cov-dot tf-cov-dot-in"></span> Inbound only <span class="tf-cov-count">' + counts.inOnly + '</span></button>';
    }
    if (counts.outOnly > 0) {
        html += '<button class="tf-cov-chip tf-cov-active" data-cov="out-only" onclick="tfToggleCov(this)" title="' + escapeAttr(descOut) + '">';
        html += '<span class="tf-cov-dot tf-cov-dot-out"></span> Outbound only <span class="tf-cov-count">' + counts.outOnly + '</span></button>';
    }
    html += '<span class="tf-cov-total">' + model.length + ' fields total</span>';
    html += '</div>';

    // Data-flow explanation
    html += '<div class="tf-flow-hint">';
    if (colSrc && colTgt) {
        html += 'Data flows: <strong>' + escapeHtml(srcName) + '</strong> (inbound) ';
        html += '&rarr; <strong>SDA3</strong> (canonical) ';
        html += '&rarr; <strong>' + escapeHtml(tgtName) + '</strong> (outbound)';
    } else if (!colSrc) {
        html += 'Data flows: <strong>SDA3</strong> (canonical) &rarr; <strong>' + escapeHtml(tgtName) + '</strong> (outbound)';
    } else {
        html += 'Data flows: <strong>' + escapeHtml(srcName) + '</strong> (inbound) &rarr; <strong>SDA3</strong> (canonical)';
    }
    html += '</div>';

    // Build table
    html += '<div class="tf-tbl-wrap" id="tf-tbl-wrap">';
    html += '<table class="tf-tbl">';

    // Header row
    html += '<thead><tr>';
    if (colSrc) html += '<th class="tf-th-src">' + escapeHtml(colSrc) + '</th>';
    html += '<th class="tf-th-sda">' + escapeHtml(colSda) + '</th>';
    if (colTgt) html += '<th class="tf-th-tgt">' + escapeHtml(colTgt) + '</th>';
    html += '</tr></thead>';

    // Body rows
    html += '<tbody>';
    var prevStatus = '';
    for (var i = 0; i < model.length; i++) {
        var r = model[i];
        var statusCls = r.status === 'complete' ? 'tf-row-ok' :
                        r.status === 'in-only' ? 'tf-row-in' : 'tf-row-out';

        // Group separator between status groups
        if (r.status !== prevStatus && prevStatus !== '') {
            var numCols = 1 + (colSrc ? 1 : 0) + (colTgt ? 1 : 0);
            var sepLabel = r.status === 'in-only' ? 'Inbound only' : 'Outbound only';
            html += '<tr class="tf-tbl-group-sep" data-cov="' + r.status + '"><td colspan="' + numCols + '">' + sepLabel + '</td></tr>';
        }
        prevStatus = r.status;

        // Search index: all visible text + the parent SDA type name + classes
        var srcLabel = r.srcField || '';
        var tgtLabel = r.tgtField || '';
        var srcCls = r.srcClass || '';
        var tgtCls = r.tgtClass || '';
        var searchIdx = (srcLabel + ' ' + r.sdaField + ' ' + tgtLabel + ' ' + sdaContext + ' ' + srcCls + ' ' + tgtCls).toLowerCase();

        html += '<tr class="tf-tbl-row ' + statusCls + '" data-idx="' + i + '" data-cov="' + r.status + '" data-search="' + escapeAttr(searchIdx) + '">';

        if (colSrc) {
            html += '<td class="tf-tbl-cell tf-tbl-src" title="' + escapeAttr(srcLabel) + '">';
            html += '<div class="tf-cell-field">' + (srcLabel ? escapeHtml(srcLabel) : '<span class="tf-tbl-empty">--</span>') + '</div>';
            if (srcCls) html += '<div class="tf-cell-class">' + escapeHtml(srcCls) + '</div>';
            html += '</td>';
        }

        html += '<td class="tf-tbl-cell tf-tbl-sda" title="' + escapeAttr(r.sdaField) + '">';
        html += escapeHtml(r.sdaField);
        html += '</td>';

        if (colTgt) {
            html += '<td class="tf-tbl-cell tf-tbl-tgt" title="' + escapeAttr(tgtLabel) + '">';
            html += '<div class="tf-cell-field">' + (tgtLabel ? escapeHtml(tgtLabel) : '<span class="tf-tbl-empty">--</span>') + '</div>';
            if (tgtCls) html += '<div class="tf-cell-class">' + escapeHtml(tgtCls) + '</div>';
            html += '</td>';
        }

        html += '</tr>';
    }
    html += '</tbody></table></div>';

    container.innerHTML = html;
}

// ── Coverage chip toggle ───────────────────────────────────────
// Each chip toggles visibility of rows with matching data-cov attribute.
// Active chips show their rows; inactive chips hide them.
function tfToggleCov(btn) {
    btn.classList.toggle('tf-cov-active');
    tfApplyCovFilter();
}
function tfApplyCovFilter() {
    var chips = document.querySelectorAll('.tf-cov-chip');
    var activeStatuses = {};
    chips.forEach(function(c) {
        if (c.classList.contains('tf-cov-active')) {
            activeStatuses[c.dataset.cov] = true;
        }
    });
    // Also respect the text filter
    var filterEl = document.getElementById('tf-field-filter');
    var q = filterEl ? filterEl.value.toLowerCase().trim() : '';

    document.querySelectorAll('.tf-tbl-row').forEach(function(tr) {
        var covMatch = !!activeStatuses[tr.dataset.cov];
        var textMatch = !q || (tr.dataset.search || '').indexOf(q) !== -1;
        tr.style.display = (covMatch && textMatch) ? '' : 'none';
    });
    // Group separators follow their group
    document.querySelectorAll('.tf-tbl-group-sep').forEach(function(sep) {
        sep.style.display = activeStatuses[sep.dataset.cov] ? '' : 'none';
    });
}


// ── Field-level text filter ─────────────────────────────────────
// Filters table rows based on the text input. Case-insensitive substring
// search across all visible columns (source, SDA, target).

// Global filter function — called via oninput="tfDoFieldFilter()" on the
// input element. Delegates to tfApplyCovFilter() which handles both text
// and coverage-chip filtering in one pass.
function tfDoFieldFilter() {
    tfApplyCovFilter();
}

// Legacy wrapper — still called by old code paths, now a no-op since
// the filter uses inline oninput and coverage chips use onclick.
function tfWireFieldFilter() { }

var _tfCurrentFilterModel = null;

// ── Field trace table (pre-computed) ────────────────────────────
// Query the persistent FieldMapping table. Falls back to live DTL/HL7
// parsing if the table is empty for the given format pair.

let _tfTableAvailable = null; // null=unknown, true/false after status check

async function tfLoadRebuildStatus() {
    var el = $('tf-rebuild-status');
    try {
        var data = await get('/transforms/field-trace/status');
        if (data && data.ok) {
            _tfTableAvailable = data.totalRows > 0;
            if (el) {
                if (data.totalRows > 0) {
                    var ts = data.lastRebuiltAt ? data.lastRebuiltAt.substring(0, 16).replace('T', ' ') : '';
                    el.textContent = data.totalRows + ' rows' + (ts ? ' (rebuilt ' + ts + ')' : '');
                    el.className = 'tf-rebuild-status tf-rebuild-ok';
                } else {
                    el.textContent = 'No data — click Rebuild';
                    el.className = 'tf-rebuild-status tf-rebuild-empty';
                }
            }
        }
    } catch (e) {
        _tfTableAvailable = false;
        if (el) {
            el.textContent = 'Status unavailable';
            el.className = 'tf-rebuild-status tf-rebuild-empty';
        }
    }
}

async function tfDoRebuild() {
    var btn = $('tf-rebuild-btn');
    var el = $('tf-rebuild-status');
    if (btn) { btn.disabled = true; btn.textContent = 'Rebuilding...'; }
    if (el) { el.textContent = 'Processing...'; el.className = 'tf-rebuild-status'; }
    try {
        var data = await post('/transforms/field-trace/rebuild', {});
        if (data && data.ok) {
            _tfTableAvailable = true;
            if (el) {
                el.textContent = data.totalRows + ' rows in ' + data.elapsedSeconds + 's';
                el.className = 'tf-rebuild-status tf-rebuild-ok';
            }
            // Refresh current view if a type is selected
            if (_tfActiveNode) {
                var srcSel = $('tf-sel-src');
                var tgtSel = $('tf-sel-tgt');
                if (srcSel && tgtSel && srcSel.value && tgtSel.value) {
                    var trace = _tfCurrentTrace;
                    var row = trace.find(function(r) { return r.sdaType === _tfActiveNode; });
                    if (row) tfLoadFieldTrace(row, srcSel.value, tgtSel.value);
                }
            }
        } else {
            if (el) { el.textContent = 'Error: ' + (data.error || 'unknown'); el.className = 'tf-rebuild-status tf-rebuild-empty'; }
        }
    } catch (e) {
        if (el) { el.textContent = 'Failed: ' + e.message; el.className = 'tf-rebuild-status tf-rebuild-empty'; }
    }
    if (btn) { btn.disabled = false; btn.textContent = 'Rebuild Mappings'; }
}

// Query table for a specific SDA type — returns model-ready array or null.
// When _tfTableAvailable is null (status unknown), try the query anyway
// since the status fetch may not have completed yet.
async function tfQueryTable(src, tgt, sdaType) {
    if (_tfTableAvailable === false) return null;
    try {
        var url = '/transforms/field-trace?source=' + encodeURIComponent(src) +
            '&target=' + encodeURIComponent(tgt) +
            '&sdaType=' + encodeURIComponent(sdaType);
        var data = await get(url);
        if (data && data.ok && data.count > 0) {
            _tfTableAvailable = true;
            return data.mappings;
        }
    } catch (e) { /* fall through to live parsing */ }
    return null;
}

// ── Trace computation (unchanged) ────────────────────────────────

function tfComputeTrace(inbound, outbound) {
    var inMap = {};
    var outMap = {};
    var inIsTyped = false;
    var outIsTyped = false;

    if (inbound) {
        var classes = inbound.classes || [];
        for (var i = 0; i < classes.length; i++) {
            var cls = classes[i];
            if (cls.isSubTransform) continue;
            var sdaType = cls.targetType || '';
            if (sdaType) {
                inIsTyped = true;
                if (!inMap[sdaType]) inMap[sdaType] = [];
                inMap[sdaType].push(cls);
            }
        }
        if (!inIsTyped) {
            inMap['*'] = [];
            for (var i = 0; i < classes.length; i++) {
                if (!classes[i].isSubTransform) inMap['*'].push(classes[i]);
            }
        }
    }

    if (outbound) {
        var classes = outbound.classes || [];
        for (var j = 0; j < classes.length; j++) {
            var cls = classes[j];
            if (cls.isSubTransform) continue;
            var sdaType = cls.sourceType || '';
            if (sdaType) {
                outIsTyped = true;
                if (!outMap[sdaType]) outMap[sdaType] = [];
                outMap[sdaType].push(cls);
            }
        }
        if (!outIsTyped) {
            outMap['*'] = [];
            for (var j = 0; j < classes.length; j++) {
                if (!classes[j].isSubTransform) outMap['*'].push(classes[j]);
            }
        }
    }

    var rows = [];

    if (inIsTyped && outIsTyped) {
        var allTypes = {};
        var key;
        for (key in inMap) allTypes[key] = true;
        for (key in outMap) allTypes[key] = true;
        var sorted = Object.keys(allTypes).sort();
        for (var t = 0; t < sorted.length; t++) {
            var sda = sorted[t];
            var inCls = inMap[sda] || [];
            var outCls = outMap[sda] || [];
            rows.push({
                sdaType: sda,
                inClasses: inCls,
                outClasses: outCls,
                sourceType: inCls.length > 0 ? (inCls[0].sourceType || '') : '',
                targetType: outCls.length > 0 ? (outCls[0].targetType || '') : '',
                status: inCls.length > 0 && outCls.length > 0 ? 'complete' :
                        inCls.length > 0 ? 'inbound-only' : 'outbound-only'
            });
        }
    } else if (inIsTyped && !outIsTyped) {
        var outMono = outMap['*'] || [];
        var sorted = Object.keys(inMap).sort();
        for (var t = 0; t < sorted.length; t++) {
            var sda = sorted[t];
            rows.push({
                sdaType: sda,
                inClasses: inMap[sda],
                outClasses: outMono,
                sourceType: inMap[sda][0].sourceType || '',
                targetType: '',
                status: 'complete',
                outMonolithic: true
            });
        }
    } else if (!inIsTyped && outIsTyped) {
        var inMono = inMap['*'] || [];
        var sorted = Object.keys(outMap).sort();
        for (var t = 0; t < sorted.length; t++) {
            var sda = sorted[t];
            rows.push({
                sdaType: sda,
                inClasses: inMono,
                outClasses: outMap[sda],
                sourceType: '',
                targetType: outMap[sda][0].targetType || '',
                status: 'complete',
                inMonolithic: true
            });
        }
    } else {
        var inMono = inMap['*'] || [];
        var outMono = outMap['*'] || [];
        rows.push({
            sdaType: '(all types)',
            inClasses: inMono,
            outClasses: outMono,
            sourceType: '',
            targetType: '',
            status: inMono.length > 0 && outMono.length > 0 ? 'complete' : 'partial',
            inMonolithic: true,
            outMonolithic: true
        });
    }

    return rows;
}

// ── DTL field fetch utility ──────────────────────────────────────

async function tfFetchFields(className) {
    if (_tfFieldCache[className]) return _tfFieldCache[className];
    try {
        var data = await get('/transforms/dtl-fields?class=' + encodeURIComponent(className));
        _tfFieldCache[className] = data;
        return data;
    } catch (e) {
        return { ok: false, error: e.message, mappings: [] };
    }
}

// Phase 7 audit trail. One scrollable table of recent audit rows
// with filter chips at the top: errors-only toggle, kind dropdown,
// limit input. Click any row to expand and see the full ErrorText
// (when present). The audit log is populated automatically by
// REST.Dispatch.OnPreDispatch / AuditEnd — every /api/agentic/*
// request lands a row.
const auditState = { errorsOnly: false, kind: '', limit: 100 };

async function loadAuditList() {
    const list = $('list');
    list.innerHTML = '<div class="empty-state">Loading audit log…</div>';
    try {
        const params = new URLSearchParams();
        params.set('limit', String(auditState.limit));
        if (auditState.errorsOnly) params.set('errorsOnly', 'true');
        if (auditState.kind) params.set('kind', auditState.kind);
        const data = await get('/audit/log?' + params.toString());
        const kindsResp = await get('/audit/kinds').catch(() => ({ kinds: [] }));
        renderAuditList(data.rows || [], kindsResp.kinds || []);
    } catch (e) {
        list.innerHTML = `<div class="empty-state">Failed: ${escapeHtml(e.message)}</div>`;
    }
}

function renderAuditList(rows, kinds) {
    const list = $('list');
    list.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.className = 'audit-wrap';
    const kindOptions = ['<option value="">all kinds</option>']
        .concat(kinds.map(k => `<option value="${escapeAttr(k)}" ${auditState.kind === k ? 'selected' : ''}>${escapeHtml(k)}</option>`))
        .join('');
    wrap.innerHTML = `
        <div class="audit-controls">
            <div class="audit-control">
                <label>Kind</label>
                <select id="f-audit-kind">${kindOptions}</select>
            </div>
            <div class="audit-control">
                <label>Errors only</label>
                <select id="f-audit-errors">
                    <option value="false" ${!auditState.errorsOnly ? 'selected' : ''}>no</option>
                    <option value="true"  ${auditState.errorsOnly ? 'selected' : ''}>yes (status &ge; 400)</option>
                </select>
            </div>
            <div class="audit-control">
                <label>Limit</label>
                <input id="f-audit-limit" type="text" value="${auditState.limit}">
            </div>
            <div class="audit-control audit-actions">
                <button id="f-audit-refresh" class="primary" type="button">Refresh</button>
                <span class="audit-summary">${rows.length} rows · most recent first</span>
            </div>
        </div>
        <table class="audit-table">
            <thead>
                <tr>
                    <th class="t-status">Status</th>
                    <th class="t-method">Method</th>
                    <th class="t-path">Path</th>
                    <th class="t-kind">Kind</th>
                    <th class="t-when">When</th>
                    <th class="t-user">User</th>
                    <th class="t-ns">Namespace</th>
                    <th class="t-ms">Duration</th>
                    <th class="t-size">Bytes (in/out)</th>
                </tr>
            </thead>
            <tbody id="audit-body"></tbody>
        </table>
    `;
    list.appendChild(wrap);
    const tbody = wrap.querySelector('#audit-body');
    if (!rows.length) {
        tbody.innerHTML = '<tr><td colspan="9" class="audit-empty">No matching audit rows.</td></tr>';
    }
    for (const r of rows) {
        const isErr = r.statusCode >= 400;
        const tr = document.createElement('tr');
        tr.className = 'audit-row' + (isErr ? ' audit-error' : '');
        tr.innerHTML = `
            <td><span class="audit-status ${isErr ? 'err' : 'ok'}">${r.statusCode}</span></td>
            <td class="t-method">${escapeHtml(r.method)}</td>
            <td class="t-path"><code>${escapeHtml(r.path)}</code></td>
            <td>${r.kind ? `<span class="badge user">${escapeHtml(r.kind)}</span>` : ''}</td>
            <td class="t-when">${escapeHtml(r.created || '')}</td>
            <td>${escapeHtml(r.username || '?')}</td>
            <td>${escapeHtml(r.namespace || '?')}</td>
            <td class="t-ms">${r.durationMs || 0}ms</td>
            <td class="t-size">${r.requestSize || 0} / ${r.responseSize || 0}</td>
        `;
        tbody.appendChild(tr);
        // Expand row click to show errorText / session / job
        const detailTr = document.createElement('tr');
        detailTr.className = 'audit-detail';
        detailTr.hidden = true;
        detailTr.innerHTML = `
            <td colspan="9">
                <div class="audit-detail-body">
                    <span><span class="dim">id:</span> ${escapeHtml(String(r.id))}</span>
                    <span><span class="dim">session:</span> ${escapeHtml(r.sessionId || '—')}</span>
                    <span><span class="dim">job:</span> ${escapeHtml(String(r.job || '—'))}</span>
                    ${r.errorText ? `<pre class="dryrun-output" style="margin:6px 0 0 0;">${escapeHtml(r.errorText)}</pre>` : ''}
                </div>
            </td>
        `;
        tbody.appendChild(detailTr);
        tr.style.cursor = 'pointer';
        tr.addEventListener('click', () => { detailTr.hidden = !detailTr.hidden; });
    }
    $('f-audit-refresh').addEventListener('click', () => {
        auditState.kind = $('f-audit-kind').value;
        auditState.errorsOnly = ($('f-audit-errors').value === 'true');
        auditState.limit = Math.max(1, Math.min(1000, Number($('f-audit-limit').value) || 100));
        loadAuditList();
    });
}

// Tokens log. One row per chat prompt: how many tokens it spent and which
// tools it called. Populated by ChatService at the end of every turn. The
// header line sums the whole filtered set (not just the shown page), so it
// answers "how much has this cost" at a glance. On this project InputTokens
// dwarfs OutputTokens because the agent's tool + skill catalog is re-sent as
// context every round — the log is the evidence for trimming bound tools.
const tokenState = { view: 'sessions', q: '', mine: false, toolsOnly: false, channel: '', ns: '', limit: 100 };

function fmtInt(n) {
    n = Number(n) || 0;
    return n.toLocaleString('en-US');
}

// Compact token count in the Claude session-panel style: 2.0M, 129.1k, 392.
function fmtTok(n) {
    n = Number(n) || 0;
    if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
    if (n >= 1e3) return (n / 1e3).toFixed(1) + 'k';
    return String(n);
}

// Duration like the panel: "7m 22s", "33s".
function fmtDur(s) {
    s = Math.round(Number(s) || 0);
    const m = Math.floor(s / 60), r = s % 60;
    return m > 0 ? (m + 'm ' + r + 's') : (r + 's');
}

// Route the Tokens tab to the session cards (default) or the per-prompt table.
async function loadTokens() {
    if (tokenState.view === 'prompts') return loadTokenList();
    return loadTokenSessions();
}

// A small two-button switch shared by both views.
function tokenViewSwitch() {
    return `
        <div class="seg" id="tok-view" style="margin-bottom:12px;">
            <button type="button" data-view="sessions" class="${tokenState.view === 'sessions' ? 'on' : ''}">Sessions</button>
            <button type="button" data-view="prompts" class="${tokenState.view === 'prompts' ? 'on' : ''}">Prompts</button>
        </div>`;
}
function wireTokenViewSwitch(root) {
    const seg = (root || document).querySelector('#tok-view');
    if (!seg) return;
    seg.querySelectorAll('button').forEach(b => b.addEventListener('click', () => {
        tokenState.view = b.dataset.view;
        loadTokens();
    }));
}

// Session summary cards — one per conversation, in the Claude Code panel
// layout. Cost/API/Active/model-mix up top, a per-model Input/Output/Cache
// breakdown below. Cache figures are 0 on the Bedrock connection (no prompt
// caching); the note says so rather than hiding the rows.
async function loadTokenSessions() {
    const list = $('list');
    list.innerHTML = '<div class="empty-state">Loading sessions…</div>';
    try {
        const p = new URLSearchParams();
        p.set('limit', '50');
        if (tokenState.mine) p.set('mine', '1');
        if (tokenState.ns === 'all') p.set('ns', 'all');
        const data = await get('/tokens/sessions?' + p.toString());
        renderTokenSessions(data.sessions || [], data.namespace || '');
    } catch (e) {
        list.innerHTML = `<div class="empty-state">Failed: ${escapeHtml(e.message)}</div>`;
    }
}

function renderTokenSessions(sessions, ns) {
    const list = $('list');
    list.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.className = 'audit-wrap';

    const controls = `
        <div class="audit-controls" style="align-items:center;">
            ${tokenViewSwitch()}
            <span class="spacer"></span>
            <div class="audit-control">
                <label>Scope</label>
                <select id="f-tok-ns">
                    <option value="" ${tokenState.ns !== 'all' ? 'selected' : ''}>this namespace</option>
                    <option value="all" ${tokenState.ns === 'all' ? 'selected' : ''}>all namespaces</option>
                </select>
            </div>
            <div class="audit-control">
                <label>Mine only</label>
                <select id="f-tok-mine">
                    <option value="false" ${!tokenState.mine ? 'selected' : ''}>no</option>
                    <option value="true"  ${tokenState.mine ? 'selected' : ''}>yes</option>
                </select>
            </div>
            <button id="f-tok-refresh" class="primary" type="button">Refresh</button>
        </div>`;

    if (!sessions.length) {
        wrap.innerHTML = controls + '<div class="empty-state">No sessions yet. Each conversation in the chat becomes a session here.</div>';
        list.appendChild(wrap);
        wireTokenSessionControls(wrap);
        return;
    }

    const cards = sessions.map(s => {
        const est = s.estimated ? '~' : '';
        // Model mix by token share, most-used first.
        const totalTok = s.models.reduce((a, m) => a + (m.inputTokens + m.outputTokens), 0) || 1;
        const mix = s.models.slice().sort((a, b) =>
            (b.inputTokens + b.outputTokens) - (a.inputTokens + a.outputTokens));
        const mixRow = mix.slice(0, 2).map(m => {
            const pct = Math.round(((m.inputTokens + m.outputTokens) / totalTok) * 100);
            return `<div class="tok-stat"><span class="dim">${escapeHtml(shortModel(m.model))}</span><span>${pct}%</span></div>`;
        }).join('');

        const breakdowns = s.models.map(m => `
            <div class="tok-break">
                <div class="tok-break-head"><span>Breakdown</span><span class="dim">${escapeHtml(shortModel(m.model))}</span></div>
                <div class="tok-break-row"><span class="dim">Input</span><span>${fmtTok(m.inputTokens)}</span></div>
                <div class="tok-break-row"><span class="dim">Output</span><span>${fmtTok(m.outputTokens)}</span></div>
                <div class="tok-break-row"><span class="dim">Cache read</span><span>${fmtTok(m.cacheReadTokens)}</span></div>
                <div class="tok-break-row"><span class="dim">Cache write</span><span>${fmtTok(m.cacheWriteTokens)}</span></div>
            </div>`).join('');

        return `
        <div class="tok-card">
            <div class="tok-card-title" title="${escapeAttr(s.title || '')}">${escapeHtml(s.title || 'Untitled conversation')}</div>
            <div class="tok-grid">
                <div class="tok-stat"><span class="dim">Cost</span><span>${est}$${(Number(s.costUsd) || 0).toFixed(2)}</span></div>
                <div class="tok-stat"><span class="dim">API</span><span>${fmtDur(s.apiSecs)}</span></div>
                <div class="tok-stat"><span class="dim">Active</span><span>${fmtDur(s.activeSecs)}</span></div>
                <div class="tok-stat"><span class="dim">Prompts</span><span>${fmtInt(s.prompts)}</span></div>
                ${mixRow}
                <div class="tok-stat"><span class="dim">Rounds</span><span>${fmtInt(s.rounds)}</span></div>
                <div class="tok-stat"><span class="dim">Tools</span><span>${fmtInt(s.tools)}</span></div>
                <div class="tok-stat"><span class="dim">Cache hit</span><span>${s.cacheHitPct}%</span></div>
            </div>
            ${breakdowns}
        </div>`;
    }).join('');

    wrap.innerHTML = controls
        + `<div class="tok-note dim">Cost is derived from public list prices and the measured token counts; a tilde marks a session whose totals include a reconstructed multi-round estimate. Cache figures are 0 because the Bedrock connection does not use prompt caching.</div>`
        + `<div class="tok-cards">${cards}</div>`;
    list.appendChild(wrap);
    wireTokenSessionControls(wrap);
}

function shortModel(m) {
    m = m || '';
    // global.anthropic.claude-sonnet-4-20250514-v1:0 -> "claude-sonnet-4"
    const seg = m.split('.').pop() || m;
    const mm = seg.match(/(claude-[a-z]+-[0-9.]+|sonnet|opus|haiku)/i);
    return mm ? mm[1] : (seg.length > 24 ? seg.slice(0, 24) : seg);
}

function wireTokenSessionControls(root) {
    wireTokenViewSwitch(root);
    const refresh = root.querySelector('#f-tok-refresh');
    if (refresh) refresh.addEventListener('click', () => {
        tokenState.ns = root.querySelector('#f-tok-ns').value;
        tokenState.mine = (root.querySelector('#f-tok-mine').value === 'true');
        loadTokenSessions();
    });
}

async function loadTokenList() {
    const list = $('list');
    list.innerHTML = '<div class="empty-state">Loading token log…</div>';
    try {
        const p = new URLSearchParams();
        p.set('limit', String(tokenState.limit));
        if (tokenState.q) p.set('q', tokenState.q);
        if (tokenState.mine) p.set('mine', '1');
        if (tokenState.toolsOnly) p.set('toolsOnly', 'true');
        if (tokenState.channel) p.set('channel', tokenState.channel);
        if (tokenState.ns === 'all') p.set('ns', 'all');
        const data = await get('/tokens?' + p.toString());
        renderTokenList(data.rows || [], data.summary || {}, data.namespace || '');
    } catch (e) {
        list.innerHTML = `<div class="empty-state">Failed: ${escapeHtml(e.message)}</div>`;
    }
}

function renderTokenList(rows, summary, ns) {
    const list = $('list');
    list.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.className = 'audit-wrap';
    wrap.innerHTML = `
        ${tokenViewSwitch()}
        <div class="audit-controls">
            <div class="audit-control" style="flex:1 1 220px;">
                <label>Search prompt / tool / user</label>
                <input id="f-tok-q" type="text" value="${escapeAttr(tokenState.q)}" placeholder="e.g. production, CreateDTL, jsmith">
            </div>
            <div class="audit-control">
                <label>Channel</label>
                <select id="f-tok-channel">
                    <option value="" ${tokenState.channel === '' ? 'selected' : ''}>all</option>
                    <option value="stream" ${tokenState.channel === 'stream' ? 'selected' : ''}>stream</option>
                    <option value="chat" ${tokenState.channel === 'chat' ? 'selected' : ''}>chat</option>
                </select>
            </div>
            <div class="audit-control">
                <label>With tools</label>
                <select id="f-tok-tools">
                    <option value="false" ${!tokenState.toolsOnly ? 'selected' : ''}>all prompts</option>
                    <option value="true"  ${tokenState.toolsOnly ? 'selected' : ''}>tool calls only</option>
                </select>
            </div>
            <div class="audit-control">
                <label>Scope</label>
                <select id="f-tok-ns">
                    <option value="" ${tokenState.ns !== 'all' ? 'selected' : ''}>this namespace</option>
                    <option value="all" ${tokenState.ns === 'all' ? 'selected' : ''}>all namespaces</option>
                </select>
            </div>
            <div class="audit-control">
                <label>Mine only</label>
                <select id="f-tok-mine">
                    <option value="false" ${!tokenState.mine ? 'selected' : ''}>no</option>
                    <option value="true"  ${tokenState.mine ? 'selected' : ''}>yes</option>
                </select>
            </div>
            <div class="audit-control">
                <label>Limit</label>
                <input id="f-tok-limit" type="text" value="${tokenState.limit}">
            </div>
            <div class="audit-control audit-actions">
                <button id="f-tok-refresh" class="primary" type="button">Refresh</button>
            </div>
        </div>
        <div class="audit-controls" style="border:none;padding-top:0;flex-direction:column;align-items:flex-start;gap:2px;">
            <span class="audit-summary">
                ${fmtInt(summary.prompts)} prompt(s) in ${escapeHtml(tokenState.ns === 'all' ? 'all namespaces' : (ns || '—'))}
                &nbsp;·&nbsp; <strong>${fmtInt(summary.totalTokens)}</strong> total tokens
                &nbsp;·&nbsp; ${fmtInt(summary.inputTokens)} in / ${fmtInt(summary.outputTokens)} out
                &nbsp;·&nbsp; ${fmtInt(summary.toolCalls)} tool call(s)
            </span>
            <span class="audit-summary dim" style="font-weight:normal;">
                A tilde (~) marks the true cost across all model rounds: a tool turn re-sends the whole context each round,
                so it bills several times the final round. Rounds = model calls; the final round's exact figure is in each row's detail.
            </span>
        </div>
        <table class="audit-table">
            <thead>
                <tr>
                    <th class="t-when">When</th>
                    <th class="t-user">User</th>
                    <th class="t-kind">Agent</th>
                    <th class="t-path">Prompt</th>
                    <th class="t-status">Tools</th>
                    <th class="t-ms" style="text-align:right;">In</th>
                    <th class="t-ms" style="text-align:right;">Out</th>
                    <th class="t-ms" style="text-align:right;">Total</th>
                    <th class="t-ms" style="text-align:right;">Rounds</th>
                    <th class="t-ms" style="text-align:right;">Latency</th>
                </tr>
            </thead>
            <tbody id="tok-body"></tbody>
        </table>
    `;
    list.appendChild(wrap);
    const tbody = wrap.querySelector('#tok-body');
    if (!rows.length) {
        tbody.innerHTML = '<tr><td colspan="10" class="audit-empty">No prompts logged yet. Every chat turn records one row here.</td></tr>';
    }
    for (const r of rows) {
        const agentShort = (r.agentClass || '').split('.').pop() || '—';
        const isErr = !r.ok;
        const est = r.estimated ? '~' : '';
        const totalCell = est
            ? `<span title="Estimated true cost across all ${r.rounds} rounds. Final round alone: ${fmtInt(r.finalRoundTokens)}.">~${fmtInt(r.totalTokens)}</span>`
            : fmtInt(r.totalTokens);
        const tr = document.createElement('tr');
        tr.className = 'audit-row' + (isErr ? ' audit-error' : '');
        tr.innerHTML = `
            <td class="t-when">${escapeHtml(r.created || '')}</td>
            <td>${escapeHtml(r.username || '?')}</td>
            <td>${escapeHtml(agentShort)}</td>
            <td class="t-path">${escapeHtml((r.promptSnippet || '').slice(0, 80))}${(r.promptLength || 0) > 80 ? '…' : ''}</td>
            <td>${r.toolCount ? `<span class="badge user">${r.toolCount}</span>` : '<span class="dim">0</span>'}</td>
            <td class="t-ms" style="text-align:right;">${est}${fmtInt(r.inputTokens)}</td>
            <td class="t-ms" style="text-align:right;">${est}${fmtInt(r.outputTokens)}</td>
            <td class="t-ms" style="text-align:right;"><strong>${totalCell}</strong></td>
            <td class="t-ms" style="text-align:right;">${r.rounds || 1}</td>
            <td class="t-ms" style="text-align:right;">${r.latencyMs || 0}ms</td>
        `;
        tbody.appendChild(tr);
        const detailTr = document.createElement('tr');
        detailTr.className = 'audit-detail';
        detailTr.hidden = true;
        const tools = (r.toolTrace || '').split(',').filter(Boolean)
            .map(t => `<span class="badge user">${escapeHtml(t.split('.').pop())}</span>`).join(' ');
        const costLine = r.estimated
            ? `<span><span class="dim">cost:</span> ~${fmtInt(r.totalTokens)} tokens across ${r.rounds} rounds (estimated) &nbsp;·&nbsp; final round alone billed ${fmtInt(r.finalRoundTokens)} exactly</span>`
            : `<span><span class="dim">cost:</span> ${fmtInt(r.totalTokens)} tokens, single round (exact)</span>`;
        detailTr.innerHTML = `
            <td colspan="10">
                <div class="audit-detail-body">
                    ${costLine}
                    <span><span class="dim">model:</span> ${escapeHtml(r.model || '—')}</span>
                    <span><span class="dim">connection:</span> ${escapeHtml(r.connection || '—')}</span>
                    <span><span class="dim">channel:</span> ${escapeHtml(r.channel || '—')}</span>
                    <span><span class="dim">namespace:</span> ${escapeHtml(r.namespace || '—')}</span>
                    <span><span class="dim">session:</span> ${escapeHtml(r.sessionId || '—')}</span>
                    <span><span class="dim">prompt chars:</span> ${fmtInt(r.promptLength)}</span>
                    ${tools ? `<div style="margin-top:6px;"><span class="dim">tools in order:</span> ${tools}</div>` : ''}
                    ${r.promptSnippet ? `<pre class="dryrun-output" style="margin:6px 0 0 0;">${escapeHtml(r.promptSnippet)}</pre>` : ''}
                </div>
            </td>
        `;
        tbody.appendChild(detailTr);
        tr.style.cursor = 'pointer';
        tr.addEventListener('click', () => { detailTr.hidden = !detailTr.hidden; });
    }
    $('f-tok-refresh').addEventListener('click', () => {
        tokenState.q = $('f-tok-q').value.trim();
        tokenState.channel = $('f-tok-channel').value;
        tokenState.toolsOnly = ($('f-tok-tools').value === 'true');
        tokenState.ns = $('f-tok-ns').value;
        tokenState.mine = ($('f-tok-mine').value === 'true');
        tokenState.limit = Math.max(1, Math.min(2000, Number($('f-tok-limit').value) || 100));
        loadTokenList();
    });
    $('f-tok-q').addEventListener('keydown', e => { if (e.key === 'Enter') $('f-tok-refresh').click(); });
    wireTokenViewSwitch();
}

async function renderToolList() {
    // Tools across ALL toolsets — both shipped (AgenticInterop.ToolSet.*)
    // and user-authored (AgenticInterop.User.ToolSet.*). Shipped tools
    // show as read-only when opened (the detail view handles that via
    // isUser branching).
    const list = $('list');
    list.innerHTML = '<div class="empty-state">Loading tools…</div>';
    if (!state.list.length) {
        list.innerHTML = '<div class="empty-state">No Tool classes found. AgenticInterop.Tool.* classes extend %AI.Tool and are registered directly by Manager.Build.</div>';
        return;
    }
    list.innerHTML = '';
    let total = 0;
    for (const ts of state.list) {
        try {
            const detail = await get('/editor/toolset/' + encodeURIComponent(ts.class));
            const tools = detail.tools || [];
            for (const t of tools) {
                const div = document.createElement('div');
                div.className = 'list-item';
                div.dataset.id = ts.class + '|' + t.name;
                div.innerHTML = `
                    <div class="row1">${escapeHtml(t.name)}</div>
                    <div class="row2"><code>${escapeHtml(ts.class)}</code></div>
                `;
                div.addEventListener('click', () => openTool(ts.class, t.name));
                list.appendChild(div);
                total += 1;
            }
        } catch (e) { /* keep going */ }
    }
    if (!total) {
        list.innerHTML = '<div class="empty-state">No tools defined. Shipped ToolSets are still empty; create a User ToolSet under the ToolSets tab to add custom tools.</div>';
    }
}

// -------- open detail --------

async function openAgent(cls) {
    try {
        const a = await get('/editor/agent/' + encodeURIComponent(cls));
        state.selected = a;
        state.detailKind = 'agent';
        $('detail-panel').hidden = false;   // unhide BEFORE render so
        renderAgentDetail();                 // bindAutoSizeTextareas can
        markListSelected(cls);               // measure scrollHeight live
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

async function openMCP(cls) {
    try {
        const m = await get('/editor/mcp/' + encodeURIComponent(cls));
        state.selected = m;
        state.detailKind = 'mcp';
        $('detail-panel').hidden = false;
        renderMCPDetail();
        markListSelected(cls);
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

async function openToolSet(cls) {
    try {
        const t = await get('/editor/toolset/' + encodeURIComponent(cls));
        state.selected = t;
        state.detailKind = 'toolset';
        $('detail-panel').hidden = false;
        renderToolSetDetail();
        markListSelected(cls);
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

async function openTool(toolset, name) {
    try {
        const t = await get('/editor/tool/' + encodeURIComponent(toolset) + '/' + encodeURIComponent(name));
        state.selected = { ...t, _toolset: toolset, _originalName: name };
        state.detailKind = 'tool';
        $('detail-panel').hidden = false;
        renderToolDetail();
        markListSelected(toolset + '|' + name);
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

// Skills are shipped, read-only. We show the registry metadata + the
// Class Source panel (which surfaces XData INSTRUCTIONS + Parameter
// TOOLS verbatim from the .cls UDL).
function openSkill(cls) {
    const s = state.registry.skills.find(x => x.class === cls);
    if (!s) { toast('Skill not in registry', 'error'); return; }
    state.selected = s;
    state.detailKind = 'skill';
    $('detail-panel').hidden = false;
    renderSkillDetail();
    markListSelected(cls);
}

// -------- detail forms --------

function renderAgentDetail() {
    const a = state.selected;
    // All agents are now editable (shipped → override, user → .cls).
    const isUser = true;
    const ro = '';
    $('detail-title').textContent = a._isNew ? 'New Agent' : (a.class || 'New Agent');
    const isUserAuthored = a._isNew || (a.class && a.class.indexOf('AgenticInterop.User.Agent.') === 0);
    $('btn-delete').style.display = (isUserAuthored && !a._isNew) ? 'inline-block' : 'none';
    $('btn-save').disabled = false;
    const classFieldHtml = a._isNew
        ? `<div class="field"><label>Class</label><input id="f-class" type="text" value="${escapeAttr(a.class)}" placeholder="AgenticInterop.User.Agent.MyAgent" autocomplete="off"><div class="hint">Must start with <code>AgenticInterop.User.Agent.</code></div></div>`
        : `<div class="field readonly"><label>Class</label><input type="text" value="${escapeAttr(a.class)}" readonly></div>`;
    a._overlayKind = 'agent';
    $('form').innerHTML = `
        ${customizedBannerHtml(a)}
        ${classFieldHtml}
        <div class="field-row">
            <div class="field">
                <label>Display name</label>
                <input id="f-name" type="text" value="${escapeAttr(a.name || '')}" ${ro}>
            </div>
            <div class="field">
                <label>Provider class</label>
                <input id="f-provider" type="text" value="${escapeAttr(a.provider || '')}" placeholder="(set in Phase 1)" ${ro}>
            </div>
        </div>
        <div class="field-row">
            <div class="field">
                <label>Temperature</label>
                <input id="f-temperature" type="text" value="${escapeAttr(a.temperature || '')}" ${ro}>
            </div>
            <div class="field">
                <label>Max iterations</label>
                <input id="f-maxIterations" type="text" value="${escapeAttr(a.maxIterations || '')}" ${ro}>
            </div>
        </div>
        <div class="field-row">
            <div class="field">
                <label>Tool binding</label>
                <select id="f-toolBinding" ${ro}>
                    <option value="mcp"${(a.toolBinding||'mcp')==='mcp'?' selected':''}>MCP (Agent -> MCP -> ToolSet -> Tool)</option>
                    <option value="bypass"${(a.toolBinding)==='bypass'?' selected':''}>Bypass (Agent -> Tool direct)</option>
                </select>
                <div class="hint">MCP enforces the full routing chain. Bypass registers tools directly, skipping MCP and ToolSet layers.</div>
            </div>
        </div>
        <div class="field">
            <label>Description</label>
            <textarea id="f-description" ${ro}>${escapeHtml(reflowProse(a.description))}</textarea>
        </div>
        <div class="field">
            <label>System prompt (XData INSTRUCTIONS, markdown)</label>
            <textarea id="f-instructions" class="tall" ${ro}>${escapeHtml(a.instructions || '')}</textarea>
        </div>
        <div class="field">
            <label>MCPs bound (${(a.mcps || []).length} of ${state.registry.mcps.length})</label>
            ${selectedChips(a.mcps)}
            <div class="checkbox-list" id="f-mcps">${renderCheckboxList(state.registry.mcps, a.mcps, 'class', isUser)}</div>
        </div>
        <div class="field">
            <label>Skills bound (${(a.skills || []).length} of ${state.registry.skills.length})</label>
            ${selectedChips(a.skills)}
            <div class="checkbox-list" id="f-skills">${renderCheckboxList(state.registry.skills, a.skills, 'class', isUser)}</div>
        </div>
        ${a.class && !a._isNew ? sourcePanelHtml(a.class) : ''}
    `;
    bindSourcePanel($('form'));
    bindAutoSizeTextareas($('form'));
    watchFormChanges();
    const aResetBtn = $('f-reset-override');
    if (aResetBtn) aResetBtn.addEventListener('click', () => resetOverride('agent', a.class, renderAgentDetail));
    if (isUser && state.registry.mcps.length === 0) loadRegistries(true).then(() => renderAgentDetail());
}

// Generic "drop the override" handler. kindPath is the URL segment
// ("mcp" / "agent" / "toolset"); rerender is the per-detail render
// function so the form refreshes after the reset.
async function resetOverride(kindPath, cls, rerender) {
    if (!confirm('Drop the customization and restore ' + cls + ' to its shipped defaults?')) return;
    try {
        const r = await post('/editor/' + kindPath + '/' + encodeURIComponent(cls) + '/reset', {});
        state.selected = r;
        toast('Reset to shipping defaults.', 'success');
        rerender();
        loadList();
    } catch (e) { showError(e); }
}

function customizedBannerHtml(entity) {
    if (!entity || !entity.customized || entity._isNew) return '';
    const dataClass = entity.class || '';
    const persistedTable = ({
        agent:   'AgenticInterop.Data.AgentOverride',
        mcp:     'AgenticInterop.Data.MCPOverride',
        toolset: 'AgenticInterop.Data.ToolSetOverride'
    })[entity._overlayKind || ''] || 'override row';
    return `
        <div class="customized-banner">
            <div>
                <strong>Customized.</strong> Saved fields are stored in <code>${escapeHtml(persistedTable)}</code> and survive <code>zpm load</code> of the upstream module.
                ${entity.updatedAt ? `Last updated ${escapeHtml(entity.updatedAt)} by ${escapeHtml(entity.updatedBy || '?')}.` : ''}
            </div>
            <button id="f-reset-override" class="danger" type="button">Reset to shipping defaults</button>
        </div>`;
}

function renderMCPDetail() {
    const m = state.selected;
    // MCPs are editable regardless of shipped/user-authored. Save
    // routing is namespace-aware: User-authored writes to .cls;
    // shipped writes to AgenticInterop.Data.MCPOverride so the
    // customization survives `zpm load` of the upstream module.
    // The "customized" badge + "Reset to shipping defaults" button
    // surface this state to the operator.
    const ro = '';
    $('detail-title').textContent = m._isNew ? 'New MCP' : (m.class || 'New MCP');
    $('btn-delete').style.display = (m.userAuthored && !m._isNew) ? 'inline-block' : 'none';
    $('btn-save').disabled = false;
    const isUser = true;   // used downstream by renderCheckboxList
    const classFieldHtml = m._isNew
        ? `<div class="field"><label>Class</label><input id="f-class" type="text" value="${escapeAttr(m.class)}" placeholder="AgenticInterop.User.MCP.MyMCP" autocomplete="off"><div class="hint">Must start with <code>AgenticInterop.User.MCP.</code></div></div>`
        : `<div class="field readonly"><label>Class</label><input type="text" value="${escapeAttr(m.class)}" readonly></div>`;
    m._overlayKind = 'mcp';
    const customizedBanner = customizedBannerHtml(m);
    $('form').innerHTML = `
        ${customizedBanner}
        ${classFieldHtml}
        <div class="field">
            <label>Name (Parameter NAME)</label>
            <input id="f-name" type="text" value="${escapeAttr(m.name || '')}" ${ro}>
        </div>
        <div class="field">
            <label>Short description (Parameter DESCRIPTION)</label>
            <textarea id="f-shortDescription" ${ro}>${escapeHtml(reflowProse(m.shortDescription))}</textarea>
            <div class="hint">Shown in the AI's tool catalog. One sentence is fine; multiple sentences are fine too. The chatbot reads this when deciding whether to use this MCP.</div>
        </div>
        <div class="field">
            <label>Class description (developer comment, behind ///)</label>
            <textarea id="f-description" ${ro}>${escapeHtml(reflowProse(m.description))}</textarea>
        </div>
        <div class="field">
            <label>ToolSets bound (${(m.toolsets || []).length} of ${state.registry.toolsets.length})</label>
            ${selectedChips(m.toolsets)}
            <div class="checkbox-list" id="f-toolsets">${renderCheckboxList(state.registry.toolsets, m.toolsets, 'class', isUser)}</div>
        </div>
        ${m.class && !m._isNew ? sourcePanelHtml(m.class) : ''}
    `;
    bindSourcePanel($('form'));
    bindAutoSizeTextareas($('form'));
    watchFormChanges();
    const resetBtn = $('f-reset-override');
    if (resetBtn) resetBtn.addEventListener('click', () => resetOverride('mcp', m.class, renderMCPDetail));
    if (isUser && state.registry.toolsets.length === 0) loadRegistries(true).then(() => renderMCPDetail());
}

async function renderToolSetDetail() {
    const t = state.selected;
    const isUser = true;
    const ro = '';
    const isUserAuthored = t._isNew || !!t.userAuthored;
    $('detail-title').textContent = t._isNew ? 'New ToolSet' : (t.class || 'New ToolSet');
    $('btn-delete').style.display = (isUserAuthored && !t._isNew) ? 'inline-block' : 'none';
    $('btn-save').disabled = false;
    t._overlayKind = 'toolset';

    if (!state._toolProviders) {
        try { state._toolProviders = (await get('/editor/tool-providers')).providers || []; }
        catch { state._toolProviders = []; }
    }
    const providers = state._toolProviders;
    const currentTools = t.tools || [];

    // Build a lookup of currently-included tools: "providerClass|name" -> true.
    // For %AI.Tool classes (toolSource=class-methods) the detail response
    // returns methods without providerClass — the class itself IS the
    // provider, so we fill in providerClass = t.class and mark all enabled.
    const includedLookup = {};
    currentTools.forEach(ct => {
        const prov = ct.providerClass || (t.toolSource === 'class-methods' ? t.class : '');
        const key = prov + '|' + ct.name;
        const isEnabled = (ct.enabled !== undefined) ? (ct.enabled !== 0) : true;
        if (isEnabled) includedLookup[key] = true;
    });

    // Merge ALL tools from ALL providers into one pool.
    // Mark each as enabled if it's in the current ToolSet's included set.
    const allTools = [];
    for (const provider of providers) {
        for (const method of (provider.methods || [])) {
            const key = provider.class + '|' + method.name;
            allTools.push({
                name: method.name,
                description: method.description || '',
                providerClass: provider.class,
                providerShort: provider.shortName,
                enabled: includedLookup[key] ? 1 : 0
            });
        }
    }
    const totalToolCount = allTools.length;

    const classFieldHtml = t._isNew
        ? `<div class="field"><label>Class</label><input id="f-class" type="text" value="${escapeAttr(t.class)}" placeholder="AgenticInterop.User.ToolSet.MyToolSet" autocomplete="off"><div class="hint">Must start with <code>AgenticInterop.User.ToolSet.</code></div></div>`
        : `<div class="field readonly"><label>Class</label><input type="text" value="${escapeAttr(t.class)}" readonly></div>`;
    $('form').innerHTML = `
        ${customizedBannerHtml(t)}
        ${classFieldHtml}
        <div class="field">
            <label>Name</label>
            <input id="f-name" type="text" value="${escapeAttr(t.name || '')}" ${ro}>
        </div>
        <div class="field">
            <label>Description</label>
            <textarea id="f-description" class="short" ${ro}>${escapeHtml(reflowProse(t.description))}</textarea>
        </div>

        <div class="ts-dual-panel">
            <div class="ts-panel ts-included">
                <div class="ts-panel-head">
                    <span class="ts-panel-title">Included tools</span>
                    <span class="ts-panel-count" id="f-inc-count">0</span>
                    <button type="button" class="link-btn" id="btn-remove-all">Remove all</button>
                </div>
                <div class="ts-panel-body" id="f-included">
                    <div class="ts-empty">No tools included yet. Add tools from the Available list below.</div>
                </div>
            </div>
            <div class="ts-panel ts-available">
                <div class="ts-panel-head">
                    <span class="ts-panel-title ts-avail-title">Available tools</span>
                    <span class="ts-panel-count" id="f-avail-count">0</span>
                    <button type="button" class="link-btn" id="btn-add-all">Add all</button>
                </div>
                <div class="ts-panel-body" id="f-available">
                    <div class="ts-empty">Select a tool provider above.</div>
                </div>
            </div>
        </div>

        <div class="field" style="margin-top:14px;">
            <div class="source-toggle" data-toggle-def>
                <span class="chev">&#9654;</span>
                <span>Framework Definition XData (XML)</span>
            </div>
            <div class="def-body" style="display:none;">
                <textarea id="f-definitionRaw" class="tall" ${ro}>${escapeHtml(t.definitionRaw || '')}</textarea>
            </div>
        </div>
        ${t.class && !t._isNew ? sourcePanelHtml(t.class) : ''}
    `;
    bindSourcePanel($('form'));
    bindAutoSizeTextareas($('form'));
    const tResetBtn = $('f-reset-override');
    if (tResetBtn) tResetBtn.addEventListener('click', () => resetOverride('toolset', t.class, renderToolSetDetail));

    // Populate the dual panels from ALL tools across all providers
    populateToolPanels(allTools);

    // Add all / Remove all
    $('btn-add-all').addEventListener('click', () => {
        document.querySelectorAll('#f-available .ts-tool-row').forEach(r => moveToolRow(r, 'include'));
        refreshToolCounts();
    });
    $('btn-remove-all').addEventListener('click', () => {
        document.querySelectorAll('#f-included .ts-tool-row').forEach(r => moveToolRow(r, 'exclude'));
        refreshToolCounts();
    });

    // Collapsible Definition XData
    const defToggle = $('form').querySelector('[data-toggle-def]');
    if (defToggle) defToggle.addEventListener('click', () => {
        const body = defToggle.nextElementSibling;
        const isOpen = body.style.display !== 'none';
        body.style.display = isOpen ? 'none' : 'block';
        defToggle.querySelector('.chev').textContent = isOpen ? '▶' : '▼';
    });

    watchFormChanges();
}

// Build one tool row element (used in both panels).
function makeToolRow(tool) {
    const desc = (tool.description || '').replace(/\r?\n/g, ' ').trim();
    const short = desc.length > 120 ? desc.substring(0, 117) + '...' : desc;
    const provLabel = tool.providerShort || (tool.providerClass ? tool.providerClass.split('.').pop() : '');
    const row = document.createElement('div');
    row.className = 'ts-tool-row';
    row.dataset.tool = tool.name;
    row.dataset.provider = tool.providerClass || '';
    row.innerHTML =
        `<span class="ts-tool-name">${escapeHtml(tool.name)}</span>` +
        (provLabel ? `<span class="ts-tool-prov">${escapeHtml(provLabel)}</span>` : '') +
        (short ? `<span class="ts-tool-desc">${escapeHtml(short)}</span>` : '') +
        `<button type="button" class="ts-tool-btn" title="Toggle"></button>`;
    return row;
}

// Fill both panels from a tools array (each has .name, .description, .enabled).
function populateToolPanels(tools) {
    const incEl = $('f-included');
    const availEl = $('f-available');
    incEl.innerHTML = '';
    availEl.innerHTML = '';

    const included = tools.filter(t => t.enabled !== 0);
    const available = tools.filter(t => t.enabled === 0);

    if (included.length === 0) {
        incEl.innerHTML = '<div class="ts-empty">No tools included. Add from Available below.</div>';
    } else {
        included.forEach(t => {
            const row = makeToolRow(t);
            row.querySelector('.ts-tool-btn').textContent = '−';  // minus
            row.querySelector('.ts-tool-btn').title = 'Remove from ToolSet';
            row.querySelector('.ts-tool-btn').addEventListener('click', () => {
                moveToolRow(row, 'exclude');
                refreshToolCounts();
            });
            incEl.appendChild(row);
        });
    }
    if (available.length === 0) {
        availEl.innerHTML = '<div class="ts-empty">All tools are included.</div>';
    } else {
        available.forEach(t => {
            const row = makeToolRow(t);
            row.querySelector('.ts-tool-btn').textContent = '+';
            row.querySelector('.ts-tool-btn').title = 'Add to ToolSet';
            row.querySelector('.ts-tool-btn').addEventListener('click', () => {
                moveToolRow(row, 'include');
                refreshToolCounts();
            });
            availEl.appendChild(row);
        });
    }
    refreshToolCounts();
}

// Move a row between panels. direction = 'include' | 'exclude'.
function moveToolRow(row, direction) {
    const incEl = $('f-included');
    const availEl = $('f-available');
    row.remove();

    // Clear empty-state placeholders
    incEl.querySelectorAll('.ts-empty').forEach(e => e.remove());
    availEl.querySelectorAll('.ts-empty').forEach(e => e.remove());

    const btn = row.querySelector('.ts-tool-btn');
    // Remove old listener by cloning
    const newBtn = btn.cloneNode(true);
    btn.replaceWith(newBtn);

    if (direction === 'include') {
        newBtn.textContent = '−';
        newBtn.title = 'Remove from ToolSet';
        newBtn.addEventListener('click', () => { moveToolRow(row, 'exclude'); refreshToolCounts(); });
        // Insert sorted by name
        const name = row.dataset.tool;
        let inserted = false;
        for (const child of incEl.children) {
            if (child.dataset.tool && child.dataset.tool.localeCompare(name) > 0) {
                incEl.insertBefore(row, child);
                inserted = true;
                break;
            }
        }
        if (!inserted) incEl.appendChild(row);
    } else {
        newBtn.textContent = '+';
        newBtn.title = 'Add to ToolSet';
        newBtn.addEventListener('click', () => { moveToolRow(row, 'include'); refreshToolCounts(); });
        const name = row.dataset.tool;
        let inserted = false;
        for (const child of availEl.children) {
            if (child.dataset.tool && child.dataset.tool.localeCompare(name) > 0) {
                availEl.insertBefore(row, child);
                inserted = true;
                break;
            }
        }
        if (!inserted) availEl.appendChild(row);
    }

    // Show empty state if a panel is now empty
    if (incEl.querySelectorAll('.ts-tool-row').length === 0) {
        incEl.innerHTML = '<div class="ts-empty">No tools included. Add from Available below.</div>';
    }
    if (availEl.querySelectorAll('.ts-tool-row').length === 0) {
        availEl.innerHTML = '<div class="ts-empty">All tools are included.</div>';
    }
}

function refreshToolCounts() {
    const inc = document.querySelectorAll('#f-included .ts-tool-row').length;
    const avail = document.querySelectorAll('#f-available .ts-tool-row').length;
    const incCount = $('f-inc-count');
    const availCount = $('f-avail-count');
    if (incCount) incCount.textContent = inc;
    if (availCount) availCount.textContent = avail;
    // Tool rows moved between panels = configuration changed
    var indicator = $('unsaved-indicator');
    if (indicator) indicator.className = 'show';
}

function renderSkillDetail() {
    const s = state.selected;
    $('detail-title').textContent = s.class;
    $('btn-delete').style.display = 'none';
    $('btn-save').disabled = true;
    $('form').innerHTML = `
        <div class="field readonly">
            <label>Class</label>
            <input type="text" value="${escapeAttr(s.class)}" readonly>
        </div>
        <div class="field readonly">
            <label>Description (developer comment)</label>
            <textarea readonly>${escapeHtml(reflowProse(s.description))}</textarea>
        </div>
        <div class="field">
            <label>ToolSets bound (Parameter TOOLS)</label>
            ${selectedChips((s.toolsets || []).map(t => typeof t === 'string' ? t : t.class))}
            <div class="hint">Skills are shipped, read-only. To change a Skill's tools, clone it under <code>AgenticInterop.User.Skill.*</code> in a future release.</div>
        </div>
        ${sourcePanelHtml(s.class)}
    `;
    bindSourcePanel($('form'));
    bindAutoSizeTextareas($('form'));
    watchFormChanges();
}

function renderToolDetail() {
    const t = state.selected;
    const isUser = (t._toolset || '').indexOf('AgenticInterop.User.ToolSet.') === 0;
    const ro = isUser ? '' : 'readonly';
    $('detail-title').innerHTML = `${escapeHtml(t._toolset)} &middot; ${escapeHtml(t.name || 'New Tool')}`;
    $('btn-delete').style.display = isUser && t._originalName ? 'inline-block' : 'none';
    $('btn-save').disabled = !isUser;
    // Build the formal-spec line ("(arg As %String, ...)") if known.
    const sigParts = [];
    if (t.classMethod) sigParts.push('ClassMethod');
    sigParts.push(t.method || t.name || '');
    let sig = sigParts.join(' ');
    if (t.formalSpec) sig += '(' + t.formalSpec + ')';
    if (t.returnType) sig += ' As ' + t.returnType;
    $('form').innerHTML = `
        <div class="field readonly">
            <label>ToolSet</label>
            <input type="text" value="${escapeAttr(t._toolset || '')}" readonly>
        </div>
        <div class="field">
            <label>Name <span class="hint-inline">— what the LLM calls when invoking this tool</span></label>
            <input id="f-name" type="text" value="${escapeAttr(t.name || '')}" ${ro}>
        </div>
        <div class="field">
            <label>Description <span class="hint-inline">— the contract the LLM reads to decide whether to call this tool</span></label>
            <textarea id="f-description" class="tall" ${ro}>${escapeHtml(reflowProse(t.description))}</textarea>
            <div class="hint">${isUser
                ? 'Edited here. Treat this as documentation written for the model, not for humans — clear inputs, side effects, output shape.'
                : 'Read-only. Source: leading <code>///</code> block on <code>' + escapeHtml((t.method || t.name) || '') + '</code> in <code>' + escapeHtml(t._toolset || '') + '</code>. The %AI framework feeds this exact text to the LLM as the tool\'s description.'}</div>
        </div>
        ${!isUser && sig.trim() ? `
        <div class="field">
            <label>Method signature</label>
            <pre class="code-block" style="white-space:pre-wrap;">${escapeHtml(sig)}</pre>
        </div>` : ''}
        <div class="field">
            <label>Input schema (JSON Schema)</label>
            <textarea id="f-inputSchema" class="tall" ${ro}>${escapeHtml(toJsonString(t.inputSchema))}</textarea>
        </div>
        <div class="field-row">
            <div class="field">
                <label>Implementation kind</label>
                <select id="f-implKind" ${ro}>
                    ${['sql','objectscript','python','rest'].map(k => `<option value="${k}" ${((t.implementation && t.implementation.kind) === k) ? 'selected' : ''}>${k}</option>`).join('')}
                </select>
            </div>
            <div class="field">
                <label>Timeout (ms)</label>
                <input id="f-timeoutMs" type="text" value="${escapeAttr(t.timeoutMs || '5000')}" ${ro}>
            </div>
            <div class="field">
                <label>Requires confirmation</label>
                <select id="f-requiresConfirmation" ${ro}>
                    <option value="false" ${!t.requiresConfirmation ? 'selected' : ''}>no</option>
                    <option value="true"  ${t.requiresConfirmation ? 'selected' : ''}>yes</option>
                </select>
            </div>
        </div>
        <div class="field">
            <label>${isUser ? 'Implementation body' : 'Source code'} <span class="hint-inline">${isUser ? '— what runs when the tool is dispatched' : '— ObjectScript method body (read-only; lives in the .cls file)'}</span></label>
            <textarea id="f-implBody" class="tall code-block" ${ro}>${escapeHtml((t.implementation && t.implementation.body) || '')}</textarea>
            ${isUser
                ? '<div class="hint">For SQL: a single statement or a parameterized query. For ObjectScript: code that sets %result. For Python: a function body. For REST: an endpoint URL or template.</div>'
                : '<div class="hint">Pulled from <code>%Dictionary.CompiledMethod.Implementation</code>. To edit, modify the <code>.cls</code> file in the source tree and recompile.</div>'}
        </div>
        ${t._toolset && t._originalName ? renderToolDryRunHtml(t) : ''}
        ${t.providerClass ? sourcePanelHtml(t.providerClass) : (t._toolset ? sourcePanelHtml(t._toolset) : '')}
    `;
    bindSourcePanel($('form'));
    bindAutoSizeTextareas($('form'));
    watchFormChanges();
    if (t._toolset && t._originalName) bindToolDryRun(t);
}

// Phase 6 — Dry Run panel. Lives at the bottom of the Tool detail
// form for tools that already exist (saved). Lets the operator paste
// an input JSON, click Run, and see the actual output the framework
// would deliver to the LLM. Mutating tools warn before firing
// because dry-run BYPASSES the confirmation gate (the operator's
// click is the explicit intent).
function renderToolDryRunHtml(t) {
    const isMutating = /^(Start|Stop|Delete|Remove|Purge|Drop|Reset|Clear|Truncate|Kill|Unmount|Deploy|Uninstall|Compile|Create|Update|Send|Patch|Put|Post|Enable|Disable|Restart|Add)[A-Z]/.test(t.name || '');
    const warning = isMutating
        ? '<div class="hint" style="color:var(--warn);margin-bottom:6px;">Mutating tool. Dry run bypasses the confirmation gate and will actually change IRIS state. Use only with safe inputs.</div>'
        : '';
    // Sample arguments come from the server (ToolService.SampleInput)
    // — curated per tool name. Falls back to {} for tools without a
    // curated sample. The user can edit before clicking Run.
    const sample = (t.sampleInput && typeof t.sampleInput === 'object')
        ? t.sampleInput
        : {};
    const hasSample = sample && Object.keys(sample).length > 0;
    const sampleHint = hasSample
        ? '<div class="hint">Pre-filled with a sample. Click <strong>Run tool</strong> to execute as-is, or edit first. Resets to the sample on every reload.</div>'
        : '<div class="hint">No curated sample for this tool. Pass an empty object <code>{}</code> if it takes no arguments, or read the <strong>Description</strong> above for the expected input shape.</div>';
    return `
        <div class="dryrun-panel">
            <div class="dryrun-head">DRY RUN</div>
            ${warning}
            <div class="field">
                <label>Input JSON ${hasSample ? '<span class="hint-inline">— pre-filled with a curated sample</span>' : ''}</label>
                <textarea id="f-dryrun-input" class="tall code-block">${escapeHtml(toJsonString(sample))}</textarea>
                ${sampleHint}
                ${hasSample ? '<div style="margin-top:6px;"><button type="button" class="link-btn" id="f-dryrun-reset">Reset to sample</button></div>' : ''}
            </div>
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
                <button id="f-dryrun-go" class="primary" type="button">Run tool</button>
                <span id="f-dryrun-status" style="color:var(--muted);font-size:11px;"></span>
            </div>
            <div class="field">
                <label>Output</label>
                <pre id="f-dryrun-output" class="dryrun-output"></pre>
            </div>
        </div>
    `;
}

function bindToolDryRun(t) {
    const goBtn = $('f-dryrun-go');
    if (!goBtn) return;
    // Reset-to-sample button (only present when a curated sample exists).
    const resetBtn = $('f-dryrun-reset');
    if (resetBtn) {
        resetBtn.addEventListener('click', () => {
            const inputEl = $('f-dryrun-input');
            if (!inputEl) return;
            inputEl.value = toJsonString(t.sampleInput || {});
            const statusEl = $('f-dryrun-status');
            if (statusEl) {
                statusEl.style.color = 'var(--muted)';
                statusEl.textContent = 'reset to sample';
                setTimeout(() => { if (statusEl.textContent === 'reset to sample') statusEl.textContent = ''; }, 1800);
            }
        });
    }
    goBtn.addEventListener('click', async () => {
        const inputEl = $('f-dryrun-input');
        const statusEl = $('f-dryrun-status');
        const outEl = $('f-dryrun-output');
        let parsed;
        try { parsed = JSON.parse(inputEl.value || '{}'); }
        catch (e) { statusEl.textContent = 'Invalid JSON: ' + e.message; statusEl.style.color = 'var(--danger)'; return; }
        goBtn.disabled = true;
        statusEl.style.color = 'var(--muted)';
        statusEl.textContent = 'running…';
        outEl.textContent = '';
        try {
            const r = await post(
                '/editor/tool/' + encodeURIComponent(t._toolset) + '/' + encodeURIComponent(t._originalName) + '/dryrun',
                { input: parsed }
            );
            if (r.ok) {
                statusEl.style.color = 'var(--success)';
                statusEl.textContent = 'OK · ' + r.elapsedMs + 'ms' + (r.timing ? ' (tool ' + r.timing + 's)' : '');
                outEl.textContent = (typeof r.output === 'string') ? r.output : JSON.stringify(r.output, null, 2);
            } else {
                statusEl.style.color = 'var(--danger)';
                statusEl.textContent = 'FAILED · ' + r.elapsedMs + 'ms';
                outEl.textContent = r.error || '(no error message)';
            }
        } catch (e) {
            statusEl.style.color = 'var(--danger)';
            statusEl.textContent = 'FAILED';
            outEl.textContent = e.message || String(e);
        } finally {
            goBtn.disabled = false;
        }
    });
}

// -------- save / delete --------

$('btn-save').addEventListener('click', async () => {
    if (!state.selected) return;
    const kind = state.detailKind;
    try {
        if (kind === 'agent') {
            await saveAgent();
        } else if (kind === 'mcp') {
            await saveMCP();
        } else if (kind === 'toolset') {
            await saveToolSet();
        } else if (kind === 'tool') {
            await saveTool();
        } else if (kind === 'connection') {
            await saveConnection();
        } else if (kind === 'chatbot') {
            await saveChatbot();
        }
    } catch (e) {
        showError(e);
    }
});

function readNewClass(prefix, kindLabel) {
    const v = ($('f-class')?.value || '').trim();
    if (!v) { toast('Class name is required.', 'error'); return null; }
    if (v.indexOf(prefix) !== 0) {
        toast(`Class name must start with ${prefix}`, 'error');
        return null;
    }
    if (v === prefix) { toast(`Add a ${kindLabel} name after the prefix.`, 'error'); return null; }
    return v;
}

async function saveAgent() {
    const a = state.selected;
    if (a._isNew) {
        const cls = readNewClass('AgenticInterop.User.Agent.', 'agent');
        if (!cls) return;
        a.class = cls;
    }
    const body = {
        name:          $('f-name').value,
        description:   $('f-description').value,
        instructions:  $('f-instructions').value,
        temperature:   $('f-temperature').value,
        maxIterations: $('f-maxIterations').value,
        toolBinding:   $('f-toolBinding').value,
        provider:      $('f-provider').value,
        mcps:          collectChecked('f-mcps'),
        skills:        collectChecked('f-skills')
    };
    const path = '/editor/agent/' + encodeURIComponent(a.class);
    const r = a._isNew ? await post('/editor/agent', { class: a.class, ...body }) : await put(path, body);
    state.selected = r;
    toast('Saved.', 'success');
    renderAgentDetail();
    clearDirtyIndicator();
    if (state.tab === 'agents') loadList();
}

async function saveMCP() {
    const m = state.selected;
    if (m._isNew) {
        const cls = readNewClass('AgenticInterop.User.MCP.', 'MCP');
        if (!cls) return;
        m.class = cls;
    }
    const body = {
        name:             $('f-name').value,
        shortDescription: $('f-shortDescription').value,
        description:      $('f-description').value,
        toolsets:         collectChecked('f-toolsets')
    };
    const path = '/editor/mcp/' + encodeURIComponent(m.class);
    const r = m._isNew ? await post('/editor/mcp', { class: m.class, ...body }) : await put(path, body);
    state.selected = r;
    toast('Saved.', 'success');
    renderMCPDetail();
    clearDirtyIndicator();
    if (state.tab === 'mcps') loadList();
}

async function saveToolSet() {
    const t = state.selected;
    if (t._isNew) {
        const cls = readNewClass('AgenticInterop.User.ToolSet.', 'ToolSet');
        if (!cls) return;
        t.class = cls;
    }

    // Collect included tools with their provider class from the dual-panel UI
    const selectedTools = [];
    document.querySelectorAll('#f-included .ts-tool-row').forEach(r => {
        selectedTools.push({ name: r.dataset.tool, providerClass: r.dataset.provider || '' });
    });

    const body = {
        name:              $('f-name').value,
        description:       $('f-description').value,
        toolsetDescription: $('f-description').value,
        selectedTools:     selectedTools
    };

    // Fallback: if no tools selected via dual-panel, check raw XData
    if (selectedTools.length === 0) {
        const defRaw = $('f-definitionRaw');
        if (defRaw && defRaw.value) body.definitionRaw = defRaw.value;
    }

    const path = '/editor/toolset/' + encodeURIComponent(t.class);
    const r = t._isNew ? await post('/editor/toolset', { class: t.class, ...body }) : await put(path, body);
    state.selected = r;
    state._toolProviders = null;
    toast('Saved. ToolSet recompiled.', 'success');
    renderToolSetDetail();
    clearDirtyIndicator();
    if (state.tab === 'toolsets') loadList();
}

async function saveConnection() {
    const c = state.selected;
    const isNew = !!c._isNew;
    const props = {
        displayName: ($('f-displayName')?.value || '').trim(),
        description: $('f-description')?.value || '',
        provider:    $('f-provider').value,
        model:       ($('f-model')?.value || '').trim(),
        region:      ($('f-region')?.value || '').trim(),
        baseURL:     ($('f-baseURL')?.value || '').trim(),
        maxTokens:   Number($('f-maxTokens')?.value || 8192) || 0,
        enabled:     ($('f-enabled')?.value || 'true') === 'true',
        isDefault:   ($('f-isDefault')?.value || 'false') === 'true'
    };
    let saved;
    if (isNew) {
        const name = ($('f-name')?.value || '').trim();
        if (!name) { toast('Name is required.', 'error'); return; }
        if (!/^[a-z][a-z0-9-]{0,99}$/.test(name)) {
            toast('Name must be lowercase, alpha-start, alphanumeric + dash.', 'error');
            return;
        }
        saved = await post('/connections', { name, ...props });
    } else {
        saved = await put('/connections/' + encodeURIComponent(c.name), props);
    }
    // Secret write goes through a separate endpoint so it never enters
    // the regular Save body / audit log.
    const secretEl = $('f-secret');
    if (secretEl && secretEl.value) {
        saved = await post('/connections/' + encodeURIComponent(saved.name) + '/secret', { value: secretEl.value });
    }
    state.selected = saved;
    toast('Saved.', 'success');
    renderConnectionDetail();
    clearDirtyIndicator();
    if (state.tab === 'connections') loadList();
}

async function saveChatbot() {
    const c = state.selected;
    const isNew = !!c._isNew;
    const body = {
        name:       ($('f-name')?.value || '').trim(),
        agentClass: $('f-agentClass')?.value || '',
        hostApp:    ($('f-hostApp')?.value || '').trim(),
        subtitle:   ($('f-subtitle')?.value || '').trim(),
        enabled:    ($('f-enabled')?.value || 'true') === 'true'
    };
    if (!body.agentClass) { toast('Pick an agent.', 'error'); return; }
    let saved;
    if (isNew) {
        const key = ($('f-key')?.value || '').trim();
        if (!key) { toast('Key is required.', 'error'); return; }
        if (!/^[a-z][a-z0-9-]{0,99}$/.test(key)) {
            toast('Key must be lowercase, alpha-start, alphanumeric + dash.', 'error');
            return;
        }
        saved = await post('/chatbots', { key, ...body });
    } else {
        saved = await put('/chatbots/' + encodeURIComponent(c.key), body);
    }
    state.selected = saved;
    toast('Saved.', 'success');
    renderChatbotDetail();
    clearDirtyIndicator();
    if (state.tab === 'chatbots') loadList();
}

async function saveTool() {
    const t = state.selected;
    const body = {
        name:                 $('f-name').value,
        description:          $('f-description').value,
        inputSchema:          parseJson($('f-inputSchema').value),
        implementation: {
            kind: $('f-implKind').value,
            body: $('f-implBody').value
        },
        timeoutMs:            Number($('f-timeoutMs').value) || 5000,
        requiresConfirmation: $('f-requiresConfirmation').value === 'true'
    };
    let r;
    if (t._originalName) {
        r = await put('/editor/tool/' + encodeURIComponent(t._toolset) + '/' + encodeURIComponent(t._originalName), body);
    } else {
        r = await post('/editor/tool/' + encodeURIComponent(t._toolset), body);
    }
    state.selected = { ...r, _toolset: t._toolset, _originalName: r.name };
    toast('Saved.', 'success');
    renderToolDetail();
    clearDirtyIndicator();
    if (state.tab === 'tools') loadList();
}

$('btn-delete').addEventListener('click', async () => {
    if (!state.selected) return;
    // window.confirm hangs the renderer in some preview contexts; use a
    // nullish check that lets us skip the prompt programmatically.
    if (typeof window.confirm === 'function' && !window.confirm('Delete this entity? This is destructive.')) return;
    const kind = state.detailKind;
    try {
        if (kind === 'agent') await del('/editor/agent/' + encodeURIComponent(state.selected.class));
        if (kind === 'mcp') await del('/editor/mcp/' + encodeURIComponent(state.selected.class));
        if (kind === 'toolset') await del('/editor/toolset/' + encodeURIComponent(state.selected.class));
        if (kind === 'tool') await del('/editor/tool/' + encodeURIComponent(state.selected._toolset) + '/' + encodeURIComponent(state.selected._originalName));
        if (kind === 'connection') await del('/connections/' + encodeURIComponent(state.selected.name));
        if (kind === 'chatbot') await del('/chatbots/' + encodeURIComponent(state.selected.key));
        toast('Deleted.', 'success');
        $('detail-panel').hidden = true;
        loadList();
    } catch (e) { showError(e); }
});

$('btn-cancel').addEventListener('click', () => {
    $('detail-panel').hidden = true;
    state.selected = null;
});

// -------- new --------

// "+ New" opens an empty editor in the right pane immediately. The class
// name is collected via the inline Class field (editable when _isNew),
// not via a browser prompt() — system dialogs interrupt the flow and
// don't fit a polished admin UI. Validation runs on Save instead.
$('btn-new').addEventListener('click', async () => {
    const tab = state.tab;
    if (tab === 'agents') {
        state.selected = { class: '', name: '', description: '', instructions: 'You are a helpful assistant.', temperature: '0.3', maxIterations: '10', mcps: [], skills: [], userAuthored: true, _isNew: true };
        state.detailKind = 'agent';
        await loadRegistries(true);
        $('detail-panel').hidden = false;
        renderAgentDetail();
        markListSelected('');
        const f = $('f-class'); if (f) f.focus();
    } else if (tab === 'mcps') {
        state.selected = { class: '', name: '', shortDescription: '', description: '', userAuthored: true, toolsets: [], _isNew: true };
        state.detailKind = 'mcp';
        await loadRegistries(true);
        $('detail-panel').hidden = false;
        renderMCPDetail();
        markListSelected('');
        const f = $('f-class'); if (f) f.focus();
    } else if (tab === 'toolsets') {
        state.selected = { class: '', name: '', description: '', userAuthored: true, tools: [], definitionRaw: '', _isNew: true };
        state.detailKind = 'toolset';
        $('detail-panel').hidden = false;
        renderToolSetDetail();
        markListSelected('');
        const f = $('f-class'); if (f) f.focus();
    } else if (tab === 'connections') {
        state.selected = {
            name: '', displayName: '', description: '', provider: 'bedrock',
            model: 'global.anthropic.claude-sonnet-4-20250514-v1:0', region: 'us-east-1',
            baseURL: '', maxTokens: 8192, enabled: true, isDefault: false, core: false,
            hasSecret: false, _isNew: true
        };
        state.detailKind = 'connection';
        $('detail-panel').hidden = false;
        renderConnectionDetail();
        markListSelected('');
        const f = $('f-name'); if (f) f.focus();
    } else if (tab === 'chatbots') {
        if (!state.registry.agents) {
            try { const d = await get('/registry/agents'); state.registry.agents = d.agents || []; } catch (e) {}
        }
        state.selected = { key: '', name: '', agentClass: 'AgenticInterop.Agent.FHIRSpecialist', hostApp: '', subtitle: '', enabled: true, core: false, _isNew: true };
        state.detailKind = 'chatbot';
        $('detail-panel').hidden = false;
        renderChatbotDetail();
        markListSelected('');
        const f = $('f-key'); if (f) f.focus();
    }
});

// Hooks invoked from inline onclick handlers
window.openTool = openTool;
window.deleteTool = async (toolset, name) => {
    if (!confirm('Delete tool ' + name + '?')) return;
    try {
        await del('/editor/tool/' + encodeURIComponent(toolset) + '/' + encodeURIComponent(name));
        toast('Deleted.', 'success');
        if (state.detailKind === 'toolset') openToolSet(toolset);
        else if (state.tab === 'tools') loadList();
    } catch (e) { showError(e); }
};
window.newToolInside = (toolset) => {
    state.selected = { _toolset: toolset, name: '', description: '', inputSchema: { type: 'object', properties: {} }, implementation: { kind: 'objectscript', body: '' }, timeoutMs: 5000, requiresConfirmation: false };
    state.detailKind = 'tool';
    renderToolDetail();
    $('detail-panel').hidden = false;
};

// -------- helpers --------

async function loadRegistries(force = false) {
    if (force || state.registry.mcps.length === 0) {
        try { state.registry.mcps = (await get('/registry/mcps')).mcps || []; } catch {}
    }
    if (force || state.registry.toolsets.length === 0) {
        try { state.registry.toolsets = (await get('/registry/toolsets')).toolsets || []; } catch {}
    }
    if (force || state.registry.skills.length === 0) {
        try { state.registry.skills = (await get('/registry/skills')).skills || []; } catch {}
    }
}

// Renders a row of green chips for the items currently bound — so the
// user can see at a glance what's selected without scanning checkboxes.
function selectedChips(values) {
    const arr = (values || []).filter(Boolean);
    if (arr.length === 0) {
        return '<div class="chip-row empty">No bindings yet.</div>';
    }
    return '<div class="chip-row">' +
        arr.map(v => `<span class="chip">${escapeHtml(typeof v === 'string' ? v : v.class || '')}</span>`).join('') +
        '</div>';
}

function renderCheckboxList(items, selected, key, editable) {
    if (!items || items.length === 0) return '<div class="empty">Loading…</div>';
    const set = new Set((selected || []).map(s => typeof s === 'string' ? s : s[key]));
    // Sort selected items to the top so the user sees current bindings
    // first; alphabetical within each group.
    const sorted = [...items].sort((a, b) => {
        const sa = set.has(a[key]) ? 0 : 1;
        const sb = set.has(b[key]) ? 0 : 1;
        if (sa !== sb) return sa - sb;
        return (a[key] || '').localeCompare(b[key] || '');
    });
    return sorted.map(item => {
        const v = item[key];
        const isSelected = set.has(v);
        const checked = isSelected ? 'checked' : '';
        const dis = editable ? '' : 'disabled';
        const cls = isSelected ? 'is-selected' : '';
        return `<label class="${cls}"><input type="checkbox" data-value="${escapeAttr(v)}" ${checked} ${dis}> <code>${escapeHtml(v)}</code> ${item.name ? '<span class="muted">' + escapeHtml(item.name) + '</span>' : ''}</label>`;
    }).join('');
}

function collectChecked(containerId) {
    const out = [];
    document.querySelectorAll('#' + containerId + ' input[type="checkbox"]').forEach(cb => {
        if (cb.checked) out.push(cb.dataset.value);
    });
    return out;
}

function showError(e) {
    const m = $('detail-msg');
    m.className = 'msg show error';
    m.textContent = e.message + (e.detail ? ' — ' + e.detail : '');
    setTimeout(() => { m.className = 'msg'; }, 8000);
    toast('Error: ' + e.message, 'error');
}

// Returns the HTML for the collapsible "Class Source" panel.
// On click of the toggle, lazy-loads the source from /api/agentic/source/:class.
function sourcePanelHtml(className) {
    return `
        <div class="source-panel">
            <div class="source-toggle" data-source-toggle="${escapeAttr(className)}">
                <span class="chev">▶</span>
                <span>Class Source</span>
                <code style="color: var(--muted); font-size: 11px;">${escapeHtml(className)}</code>
                <span class="meta" data-source-meta>Click to expand</span>
            </div>
            <div class="source-body">
                <div class="source-actions">
                    <button data-source-copy="${escapeAttr(className)}">Copy</button>
                    <button data-source-reload="${escapeAttr(className)}">Reload</button>
                </div>
                <pre data-source-pre="${escapeAttr(className)}"><span class="empty">Click to load.</span></pre>
            </div>
        </div>
    `;
}

// -------- dirty-state detection --------
// Captures a snapshot of every form input after rendering, then watches
// for changes. When anything differs, the "configuration has changed"
// indicator appears next to the Save button.

let _formSnapshot = null;

function snapshotFormState() {
    const form = $('form');
    if (!form) return '';
    const parts = [];
    form.querySelectorAll('input, textarea, select').forEach(el => {
        if (el.type === 'checkbox') {
            parts.push(el.dataset.value + ':' + (el.checked ? '1' : '0'));
        } else {
            parts.push((el.id || el.name || '') + ':' + (el.value || ''));
        }
    });
    return parts.join('|');
}

function watchFormChanges() {
    _formSnapshot = snapshotFormState();
    var indicator = $('unsaved-indicator');
    if (indicator) indicator.className = '';
    var form = $('form');
    if (!form) return;
    function check() {
        var current = snapshotFormState();
        var ind = $('unsaved-indicator');
        if (!ind) return;
        if (current !== _formSnapshot) {
            ind.className = 'show';
        } else {
            ind.className = '';
        }
    }
    form.addEventListener('input', check);
    form.addEventListener('change', check);
}

function clearDirtyIndicator() {
    _formSnapshot = snapshotFormState();
    var indicator = $('unsaved-indicator');
    if (indicator) indicator.className = '';
}

// Grow every textarea in the form to fit its content so long descriptions
// and instructions are not truncated behind an internal scrollbar. The
// CSS min-height still acts as a floor for empty fields, and `resize:
// vertical` still lets the user shrink it manually. We use rAF so the
// measurement runs after the panel is visible (openXxx unhides AFTER
// render in some flows).
function bindAutoSizeTextareas(formEl) {
    if (!formEl) return;
    // box-sizing: border-box is set globally, so el.style.height sets the
    // OUTER box. scrollHeight reports content+padding only, so we have to
    // add the border widths back — otherwise the last line is clipped by
    // the border (2px) and an internal scrollbar appears. Caller must
    // ensure the form's containing panel is visible BEFORE invoking us
    // (openXxx unhides the detail panel first), otherwise scrollHeight
    // reads 0 on a display:none textarea.
    const fit = el => {
        if (!el.isConnected) return;
        el.style.height = 'auto';
        const cs = getComputedStyle(el);
        const border = (parseFloat(cs.borderTopWidth) || 0) + (parseFloat(cs.borderBottomWidth) || 0);
        el.style.height = (el.scrollHeight + border) + 'px';
    };
    formEl.querySelectorAll('textarea').forEach(el => {
        fit(el);                                 // sync, panel is visible
        requestAnimationFrame(() => fit(el));    // safety net for late layout
        el.addEventListener('input', () => fit(el));
        el.addEventListener('focus', () => fit(el));
    });
}

// Toggle the .list-item.selected class so the user can see which row is
// currently open in the right pane. Called from every openXxx() with the
// item's stable identity (class name for Agent/MCP/ToolSet/Skill, the
// "toolset|name" pair for Tool).
function markListSelected(id) {
    const list = document.getElementById('list');
    if (!list) return;
    list.querySelectorAll('.list-item').forEach(it => {
        it.classList.toggle('selected', it.dataset.id === id);
    });
}

// Wire up toggle / copy / reload listeners after a detail is rendered.
function bindSourcePanel(formEl) {
    if (!formEl) return;
    formEl.querySelectorAll('[data-source-toggle]').forEach(toggle => {
        toggle.addEventListener('click', async () => {
            const cls = toggle.dataset.sourceToggle;
            const open = toggle.classList.toggle('open');
            toggle.querySelector('.chev').textContent = open ? '▼' : '▶';
            if (!open) return;
            const pre = formEl.querySelector(`[data-source-pre="${cssEscape(cls)}"]`);
            const meta = toggle.querySelector('[data-source-meta]');
            if (pre.dataset.loaded === '1') return;
            pre.innerHTML = '<span class="empty">Loading…</span>';
            try {
                const r = await api('/source/' + encodeURIComponent(cls));
                pre.textContent = r.source || '';
                pre.dataset.loaded = '1';
                if (meta) meta.textContent = r.lines + ' lines · ' + r.bytes + ' bytes';
            } catch (e) {
                pre.innerHTML = '<span class="err">' + escapeHtml('Load failed: ' + e.message) + '</span>';
            }
        });
    });
    formEl.querySelectorAll('[data-source-copy]').forEach(btn => {
        btn.addEventListener('click', () => {
            const cls = btn.dataset.sourceCopy;
            const pre = formEl.querySelector(`[data-source-pre="${cssEscape(cls)}"]`);
            if (pre && pre.textContent) {
                navigator.clipboard.writeText(pre.textContent).then(
                    () => toast('Source copied.', 'success'),
                    () => toast('Copy failed.', 'error')
                );
            }
        });
    });
    formEl.querySelectorAll('[data-source-reload]').forEach(btn => {
        btn.addEventListener('click', async () => {
            const cls = btn.dataset.sourceReload;
            const pre = formEl.querySelector(`[data-source-pre="${cssEscape(cls)}"]`);
            const toggle = formEl.querySelector(`[data-source-toggle="${cssEscape(cls)}"]`);
            const meta = toggle?.querySelector('[data-source-meta]');
            pre.innerHTML = '<span class="empty">Reloading…</span>';
            pre.dataset.loaded = '';
            try {
                const r = await api('/source/' + encodeURIComponent(cls));
                pre.textContent = r.source || '';
                pre.dataset.loaded = '1';
                if (meta) meta.textContent = r.lines + ' lines · ' + r.bytes + ' bytes';
                toast('Source reloaded.', 'success');
            } catch (e) {
                pre.innerHTML = '<span class="err">' + escapeHtml('Reload failed: ' + e.message) + '</span>';
            }
        });
    });
}

// Minimal CSS.escape polyfill for class-name attribute selectors.
function cssEscape(s) { return String(s).replace(/[^a-zA-Z0-9_\-]/g, c => '\\' + c); }

function shortName(cls) { return cls.split('.').slice(-1)[0]; }
function escapeHtml(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function escapeAttr(s) { return escapeHtml(s); }
// Description text in the source classes is hard-wrapped at ~60 chars
// (a side-effect of how the original ObjectScript comments / XData were
// authored). When we drop that into a wide textarea, the \n's force the
// text to break at column 60 and leave the right two-thirds of the box
// empty. reflowProse collapses every run of whitespace into a single
// space so the prose wraps at the textarea's own width — like a normal
// paragraph editor. Code fields (XML/JSON/code) keep their original
// formatting because they don't go through this helper.
function reflowProse(s) { return String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); }
function toJsonString(v) { try { return JSON.stringify(v == null ? {} : v, null, 2); } catch { return ''; } }
function parseJson(s) { try { return s ? JSON.parse(s) : {}; } catch { return {}; } }

// -------- bootstrap --------

(async () => {
    // Capture bridge auth + namespace from the parent SPA first.
    if (isViaInterop()) {
        const bridge = await fetchBridgeAuth();
        if (bridge.bearer) bridgeBearer = bridge.bearer;
        if (bridge.namespace) bridgeNamespace = bridge.namespace;
        else if (urlNamespace()) bridgeNamespace = urlNamespace();
    }
    // Validate once. After this, no auto-prompts on 401.
    try {
        await bootstrapAuth();
    } catch (e) {
        showError(e);
        return;
    }
    try {
        const ns = await get('/namespace');
        state.namespace = ns.namespace;
        $('ns-indicator').textContent = 'namespace: ' + ns.namespace + '  |  v' + ADMIN_VERSION;
    } catch {
        $('ns-indicator').textContent = 'namespace: ?';
    }
    await loadRegistries(true);
    setTab('agents');
})();
