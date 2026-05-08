// agentic_interop admin — vanilla JS SPA against /api/agentic/*
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
const TABS = ['agents', 'mcps', 'toolsets', 'tools', 'skills', 'connections', 'catalogs', 'audit'];
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
    document.body.dataset.layout = (tab === 'audit' || tab === 'catalogs') ? 'full' : 'split';
    $('list-title').textContent = ({
        agents: 'Agents', mcps: 'MCPs', toolsets: 'ToolSets', tools: 'Tools', skills: 'Skills', connections: 'Connections', catalogs: 'Catalogs', audit: 'Audit'
    })[tab];
    $('btn-new').style.display = (tab === 'tools' || tab === 'skills' || tab === 'catalogs' || tab === 'audit') ? 'none' : 'inline-block';
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
        } else if (state.tab === 'catalogs') {
            const data = await get('/catalog/status');
            state.list = [data];
            renderCatalogList();
        } else if (state.tab === 'audit') {
            await loadAuditList();
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
    if (!state.list.length) { list.innerHTML = '<div class="empty-state">No ToolSets.</div>'; return; }
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

async function renderToolList() {
    // Tools across ALL toolsets — both shipped (AgenticInterop.ToolSet.*)
    // and user-authored (AgenticInterop.User.ToolSet.*). Shipped tools
    // show as read-only when opened (the detail view handles that via
    // isUser branching).
    const list = $('list');
    list.innerHTML = '<div class="empty-state">Loading tools…</div>';
    if (!state.list.length) {
        list.innerHTML = '<div class="empty-state">No ToolSets registered. The framework manifest seeds the shipped set on install — if you see this, run the install routine again.</div>';
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

    // Build a lookup of currently-included tools: "providerClass|name" -> true
    const includedLookup = {};
    currentTools.forEach(ct => {
        const key = (ct.providerClass || '') + '|' + ct.name;
        if (ct.enabled !== 0) includedLookup[key] = true;
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
        provider:      $('f-provider').value,
        mcps:          collectChecked('f-mcps'),
        skills:        collectChecked('f-skills')
    };
    const path = '/editor/agent/' + encodeURIComponent(a.class);
    const r = a._isNew ? await post('/editor/agent', { class: a.class, ...body }) : await put(path, body);
    state.selected = r;
    toast('Saved.', 'success');
    renderAgentDetail();
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
    if (state.tab === 'connections') loadList();
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
        $('ns-indicator').textContent = 'namespace: ' + ns.namespace;
    } catch {
        $('ns-indicator').textContent = 'namespace: ?';
    }
    await loadRegistries(true);
    setTab('agents');
})();
