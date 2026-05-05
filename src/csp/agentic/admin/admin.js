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
const TABS = ['agents', 'mcps', 'toolsets', 'tools', 'skills'];
const AUTH_KEY = 'AGENTIC_AUTH';

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

function getStoredAuth() {
    try { return sessionStorage.getItem(AUTH_KEY) || ''; } catch { return ''; }
}
function setStoredAuth(basic) {
    try { sessionStorage.setItem(AUTH_KEY, basic); } catch {}
}
function clearStoredAuth() {
    try { sessionStorage.removeItem(AUTH_KEY); } catch {}
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
    if (stored) clearStoredAuth();
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
        // We were authenticated at bootstrap; mid-session token
        // expired. DO NOT auto-prompt — that produced the rapid-fire
        // re-prompt loop the customer flagged. Surface a toast and
        // throw; the user can manually re-trigger bootstrap by
        // refreshing the modal (close + reopen the AI Settings tab).
        authValidated = false;
        bridgeBearer = '';
        toast('Session expired — close and reopen AI Settings to sign in again.', 'error');
        const err = new Error('Authentication expired');
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
    $('list-title').textContent = ({
        agents: 'Agents', mcps: 'MCPs', toolsets: 'ToolSets', tools: 'Tools', skills: 'Skills'
    })[tab];
    $('btn-new').style.display = (tab === 'tools' || tab === 'skills') ? 'none' : 'inline-block';
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
        const isUser = a.class.indexOf('AgenticInterop.User.Agent.') === 0;
        const div = document.createElement('div');
        div.className = 'list-item';
        div.innerHTML = `
            <div class="row1">
                ${escapeHtml(a.name || shortName(a.class))}
                <span class="badge ${isUser ? 'user' : 'shipped'}">${isUser ? 'user' : 'shipped'}</span>
                ${a.abstract ? '<span class="badge abstract">abstract</span>' : ''}
            </div>
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
        const isUser = m.class.indexOf('AgenticInterop.User.MCP.') === 0;
        const div = document.createElement('div');
        div.className = 'list-item';
        div.innerHTML = `
            <div class="row1">
                ${escapeHtml(m.name || shortName(m.class))}
                <span class="badge ${isUser ? 'user' : 'shipped'}">${isUser ? 'user' : 'shipped'}</span>
            </div>
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
        const isUser = t.class.indexOf('AgenticInterop.User.ToolSet.') === 0;
        const div = document.createElement('div');
        div.className = 'list-item';
        div.innerHTML = `
            <div class="row1">
                ${escapeHtml(t.name || shortName(t.class))}
                <span class="badge ${isUser ? 'user' : 'shipped'}">${isUser ? 'user' : 'shipped'}</span>
            </div>
            <div class="row2"><code>${escapeHtml(t.class)}</code></div>
            <div class="row2 desc">${escapeHtml((t.description || '').replace(/\s+/g, ' ').trim() || '—')}</div>
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
        div.innerHTML = `
            <div class="row1">${escapeHtml(shortName(s.class))} <span class="badge shipped">shipped</span></div>
            <div class="row2"><code>${escapeHtml(s.class)}</code></div>
            <div class="row2 desc">${escapeHtml((s.description || '').replace(/\s+/g, ' ').trim() || '—')}</div>
            <div class="row2">${s.toolsets.length} toolset(s)</div>
        `;
        div.addEventListener('click', () => openSkill(s.class));
        list.appendChild(div);
    }
}

async function renderToolList() {
    // Tools across all toolsets — fetch each one (only user-authored show full tool list)
    const list = $('list');
    list.innerHTML = '<div class="empty-state">Loading tools…</div>';
    const userToolsets = state.list.filter(t => t.class.indexOf('AgenticInterop.User.ToolSet.') === 0);
    if (!userToolsets.length) {
        list.innerHTML = '<div class="empty-state">No user-authored ToolSets yet. Create one under the ToolSets tab to start adding tools.</div>';
        return;
    }
    list.innerHTML = '';
    for (const ts of userToolsets) {
        try {
            const detail = await get('/editor/toolset/' + encodeURIComponent(ts.class));
            const tools = detail.tools || [];
            for (const t of tools) {
                const div = document.createElement('div');
                div.className = 'list-item';
                div.innerHTML = `
                    <div class="row1">${escapeHtml(t.name)}</div>
                    <div class="row2">${escapeHtml(t.description || '—')}</div>
                    <div class="row2"><code>${escapeHtml(ts.class)}</code></div>
                    <div class="row2">kind: ${escapeHtml((t.implementation && t.implementation.kind) || '—')}</div>
                `;
                div.addEventListener('click', () => openTool(ts.class, t.name));
                list.appendChild(div);
            }
        } catch (e) { /* keep going */ }
    }
    if (!list.children.length) {
        list.innerHTML = '<div class="empty-state">No tools yet. Open a user-authored ToolSet to add some.</div>';
    }
}

// -------- open detail --------

async function openAgent(cls) {
    try {
        const a = await get('/editor/agent/' + encodeURIComponent(cls));
        state.selected = a;
        state.detailKind = 'agent';
        renderAgentDetail();
        $('detail-panel').hidden = false;
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

async function openMCP(cls) {
    try {
        const m = await get('/editor/mcp/' + encodeURIComponent(cls));
        state.selected = m;
        state.detailKind = 'mcp';
        renderMCPDetail();
        $('detail-panel').hidden = false;
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

async function openToolSet(cls) {
    try {
        const t = await get('/editor/toolset/' + encodeURIComponent(cls));
        state.selected = t;
        state.detailKind = 'toolset';
        renderToolSetDetail();
        $('detail-panel').hidden = false;
    } catch (e) { toast('Load failed: ' + e.message, 'error'); }
}

async function openTool(toolset, name) {
    try {
        const t = await get('/editor/tool/' + encodeURIComponent(toolset) + '/' + encodeURIComponent(name));
        state.selected = { ...t, _toolset: toolset, _originalName: name };
        state.detailKind = 'tool';
        renderToolDetail();
        $('detail-panel').hidden = false;
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
    renderSkillDetail();
    $('detail-panel').hidden = false;
}

// -------- detail forms --------

function renderAgentDetail() {
    const a = state.selected;
    const isUser = a.class.indexOf('AgenticInterop.User.Agent.') === 0;
    const ro = isUser ? '' : 'readonly';
    $('detail-title').textContent = a.class || 'New Agent';
    $('btn-delete').style.display = isUser ? 'inline-block' : 'none';
    $('btn-save').disabled = !isUser;
    $('form').innerHTML = `
        <div class="field readonly">
            <label>Class</label>
            <input type="text" value="${escapeAttr(a.class)}" readonly>
        </div>
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
            <textarea id="f-description" ${ro}>${escapeHtml(a.description || '')}</textarea>
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
    if (isUser && state.registry.mcps.length === 0) loadRegistries(true).then(() => renderAgentDetail());
}

function renderMCPDetail() {
    const m = state.selected;
    const isUser = m.userAuthored;
    const ro = isUser ? '' : 'readonly';
    $('detail-title').textContent = m.class || 'New MCP';
    $('btn-delete').style.display = isUser ? 'inline-block' : 'none';
    $('btn-save').disabled = !isUser;
    $('form').innerHTML = `
        <div class="field readonly">
            <label>Class</label>
            <input type="text" value="${escapeAttr(m.class)}" readonly>
        </div>
        <div class="field">
            <label>Name (Parameter NAME)</label>
            <input id="f-name" type="text" value="${escapeAttr(m.name || '')}" ${ro}>
        </div>
        <div class="field">
            <label>Short description (Parameter DESCRIPTION)</label>
            <textarea id="f-shortDescription" ${ro}>${escapeHtml(m.shortDescription || '')}</textarea>
            <div class="hint">Shown in the AI's tool catalog. One sentence is fine; multiple sentences are fine too. The chatbot reads this when deciding whether to use this MCP.</div>
        </div>
        <div class="field">
            <label>Class description (developer comment, behind ///)</label>
            <textarea id="f-description" ${ro}>${escapeHtml(m.description || '')}</textarea>
        </div>
        <div class="field">
            <label>ToolSets bound (${(m.toolsets || []).length} of ${state.registry.toolsets.length})</label>
            ${selectedChips(m.toolsets)}
            <div class="checkbox-list" id="f-toolsets">${renderCheckboxList(state.registry.toolsets, m.toolsets, 'class', isUser)}</div>
        </div>
        ${m.class && !m._isNew ? sourcePanelHtml(m.class) : ''}
    `;
    bindSourcePanel($('form'));
    if (isUser && state.registry.toolsets.length === 0) loadRegistries(true).then(() => renderMCPDetail());
}

function renderToolSetDetail() {
    const t = state.selected;
    const isUser = t.userAuthored;
    const ro = isUser ? '' : 'readonly';
    $('detail-title').textContent = t.class || 'New ToolSet';
    $('btn-delete').style.display = isUser ? 'inline-block' : 'none';
    $('btn-save').disabled = !isUser;
    const tools = t.tools || [];
    const toolsHtml = tools.length === 0
        ? '<tr class="empty-row"><td colspan="4">No tools yet.</td></tr>'
        : tools.map(tool => `
            <tr>
                <td><strong>${escapeHtml(tool.name)}</strong></td>
                <td>${escapeHtml(tool.description || '—')}</td>
                <td><code>${escapeHtml((tool.implementation && tool.implementation.kind) || '—')}</code></td>
                <td class="actions-cell">
                    <button onclick="openTool('${escapeAttr(t.class)}','${escapeAttr(tool.name)}')">Edit</button>
                    <button class="danger" onclick="deleteTool('${escapeAttr(t.class)}','${escapeAttr(tool.name)}')">Delete</button>
                </td>
            </tr>`).join('');
    $('form').innerHTML = `
        <div class="field readonly">
            <label>Class</label>
            <input type="text" value="${escapeAttr(t.class)}" readonly>
        </div>
        <div class="field">
            <label>Name (Parameter NAME)</label>
            <input id="f-name" type="text" value="${escapeAttr(t.name || '')}" ${ro}>
        </div>
        <div class="field">
            <label>Class description</label>
            <textarea id="f-description" ${ro}>${escapeHtml(t.description || '')}</textarea>
        </div>
        <div class="field">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
                <label style="margin:0;">Tools (XData ToolManifest)</label>
                ${isUser ? `<button class="primary" onclick="newToolInside('${escapeAttr(t.class)}')">+ Tool</button>` : ''}
            </div>
            <table class="tools-table">
                <thead><tr><th>Name</th><th>Description</th><th>Kind</th><th></th></tr></thead>
                <tbody>${toolsHtml}</tbody>
            </table>
            <div class="hint">Tools are stored in the ToolSet's XData ToolManifest (JSON). Phase 4 will translate these entries into the framework's XML Definition for runtime invocation.</div>
        </div>
        <div class="field">
            <label>Framework Definition XData (XML, advanced)</label>
            <textarea id="f-definitionRaw" class="tall" ${ro}>${escapeHtml(t.definitionRaw || '')}</textarea>
            <div class="hint">Edited by the framework's compile-time generator. Leave alone unless you know what you're doing.</div>
        </div>
        ${t.class && !t._isNew ? sourcePanelHtml(t.class) : ''}
    `;
    bindSourcePanel($('form'));
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
            <textarea readonly>${escapeHtml(s.description || '')}</textarea>
        </div>
        <div class="field">
            <label>ToolSets bound (Parameter TOOLS)</label>
            ${selectedChips((s.toolsets || []).map(t => typeof t === 'string' ? t : t.class))}
            <div class="hint">Skills are shipped, read-only. To change a Skill's tools, clone it under <code>AgenticInterop.User.Skill.*</code> in a future release.</div>
        </div>
        ${sourcePanelHtml(s.class)}
    `;
    bindSourcePanel($('form'));
}

function renderToolDetail() {
    const t = state.selected;
    const isUser = (t._toolset || '').indexOf('AgenticInterop.User.ToolSet.') === 0;
    const ro = isUser ? '' : 'readonly';
    $('detail-title').textContent = `${t._toolset} · ${t.name || 'New Tool'}`;
    $('btn-delete').style.display = isUser && t._originalName ? 'inline-block' : 'none';
    $('btn-save').disabled = !isUser;
    $('form').innerHTML = `
        <div class="field readonly">
            <label>ToolSet</label>
            <input type="text" value="${escapeAttr(t._toolset || '')}" readonly>
        </div>
        <div class="field">
            <label>Name</label>
            <input id="f-name" type="text" value="${escapeAttr(t.name || '')}" ${ro}>
        </div>
        <div class="field">
            <label>Description</label>
            <textarea id="f-description" ${ro}>${escapeHtml(t.description || '')}</textarea>
        </div>
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
            <label>Implementation body</label>
            <textarea id="f-implBody" class="tall" ${ro}>${escapeHtml((t.implementation && t.implementation.body) || '')}</textarea>
            <div class="hint">For SQL: a single statement or a parameterized query. For ObjectScript: code that sets %result. For Python: a function body. For REST: an endpoint URL or template.</div>
        </div>
        ${t._toolset ? sourcePanelHtml(t._toolset) : ''}
    `;
    bindSourcePanel($('form'));
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
        }
    } catch (e) {
        showError(e);
    }
});

async function saveAgent() {
    const a = state.selected;
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
    const body = {
        name:           $('f-name').value,
        description:    $('f-description').value,
        definitionRaw:  $('f-definitionRaw').value
    };
    const path = '/editor/toolset/' + encodeURIComponent(t.class);
    const r = t._isNew ? await post('/editor/toolset', { class: t.class, ...body }) : await put(path, body);
    state.selected = r;
    toast('Saved.', 'success');
    renderToolSetDetail();
    if (state.tab === 'toolsets') loadList();
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

$('btn-new').addEventListener('click', async () => {
    const tab = state.tab;
    if (tab === 'agents') {
        const cls = prompt('Class name (must start with AgenticInterop.User.Agent.):', 'AgenticInterop.User.Agent.MyAgent');
        if (!cls) return;
        state.selected = { class: cls, name: '', description: '', instructions: 'You are a helpful assistant.', temperature: '0.3', maxIterations: '10', mcps: [], skills: [], _isNew: true };
        state.detailKind = 'agent';
        await loadRegistries(true);
        renderAgentDetail();
        $('detail-panel').hidden = false;
    }
    if (tab === 'mcps') {
        const cls = prompt('Class name (must start with AgenticInterop.User.MCP.):', 'AgenticInterop.User.MCP.MyMCP');
        if (!cls) return;
        state.selected = { class: cls, name: '', shortDescription: '', description: '', userAuthored: true, toolsets: [], _isNew: true };
        state.detailKind = 'mcp';
        await loadRegistries(true);
        renderMCPDetail();
        $('detail-panel').hidden = false;
    }
    if (tab === 'toolsets') {
        const cls = prompt('Class name (must start with AgenticInterop.User.ToolSet.):', 'AgenticInterop.User.ToolSet.MyToolSet');
        if (!cls) return;
        state.selected = { class: cls, name: '', description: '', userAuthored: true, tools: [], definitionRaw: '', _isNew: true };
        state.detailKind = 'toolset';
        renderToolSetDetail();
        $('detail-panel').hidden = false;
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
function firstLine(s) { if (!s) return ''; return s.split(/\r?\n/)[0]; }
function escapeHtml(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function escapeAttr(s) { return escapeHtml(s); }
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
