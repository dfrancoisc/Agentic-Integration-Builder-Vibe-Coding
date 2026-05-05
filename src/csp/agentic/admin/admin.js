// agentic_interop admin — vanilla JS SPA against /api/agentic/*

const API = '/api/agentic';
const TABS = ['agents', 'mcps', 'toolsets', 'tools', 'skills'];

const state = {
    tab: 'agents',
    list: [],
    selected: null,    // currently-open detail (object)
    detailKind: null,  // which entity is on the right pane
    registry: { agents: [], mcps: [], toolsets: [], skills: [] },
    namespace: ''
};

const $ = (id) => document.getElementById(id);

// -------- HTTP helpers --------

async function api(path, opts = {}) {
    const res = await fetch(API + path, {
        ...opts,
        headers: {
            'Content-Type': 'application/json',
            ...(opts.headers || {})
        }
    });
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch (e) { /* keep null */ }
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
            <div class="row2">${escapeHtml(firstLine(a.description) || '—')}</div>
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
            <div class="row2">${escapeHtml(m.shortDescription || firstLine(m.description) || '—')}</div>
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
            <div class="row2">${escapeHtml(firstLine(t.description) || '—')}</div>
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
            <div class="row1">${escapeHtml(shortName(s.class))}</div>
            <div class="row2"><code>${escapeHtml(s.class)}</code></div>
            <div class="row2">${escapeHtml(firstLine(s.description) || '—')}</div>
            <div class="row2">${s.toolsets.length} toolset(s)</div>
        `;
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
            <label>MCPs</label>
            <div class="checkbox-list" id="f-mcps">${renderCheckboxList(state.registry.mcps, a.mcps, 'class', isUser)}</div>
        </div>
        <div class="field">
            <label>Skills</label>
            <div class="checkbox-list" id="f-skills">${renderCheckboxList(state.registry.skills, a.skills, 'class', isUser)}</div>
        </div>
    `;
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
        <div class="field-row">
            <div class="field">
                <label>Name (Parameter NAME)</label>
                <input id="f-name" type="text" value="${escapeAttr(m.name || '')}" ${ro}>
            </div>
            <div class="field">
                <label>Short description (Parameter DESCRIPTION)</label>
                <input id="f-shortDescription" type="text" value="${escapeAttr(m.shortDescription || '')}" ${ro}>
            </div>
        </div>
        <div class="field">
            <label>Class description</label>
            <textarea id="f-description" ${ro}>${escapeHtml(m.description || '')}</textarea>
        </div>
        <div class="field">
            <label>ToolSets bound to this MCP</label>
            <div class="checkbox-list" id="f-toolsets">${renderCheckboxList(state.registry.toolsets, m.toolsets, 'class', isUser)}</div>
        </div>
    `;
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
    `;
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
    `;
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

function renderCheckboxList(items, selected, key, editable) {
    if (!items || items.length === 0) return '<div class="empty">Loading…</div>';
    const set = new Set((selected || []).map(s => typeof s === 'string' ? s : s[key]));
    return items.map(item => {
        const v = item[key];
        const checked = set.has(v) ? 'checked' : '';
        const dis = editable ? '' : 'disabled';
        return `<label><input type="checkbox" data-value="${escapeAttr(v)}" ${checked} ${dis}> <code>${escapeHtml(v)}</code> ${item.name ? '<span style="color:var(--muted);">' + escapeHtml(item.name) + '</span>' : ''}</label>`;
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

function shortName(cls) { return cls.split('.').slice(-1)[0]; }
function firstLine(s) { if (!s) return ''; return s.split(/\r?\n/)[0]; }
function escapeHtml(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function escapeAttr(s) { return escapeHtml(s); }
function toJsonString(v) { try { return JSON.stringify(v == null ? {} : v, null, 2); } catch { return ''; } }
function parseJson(s) { try { return s ? JSON.parse(s) : {}; } catch { return {}; } }

// -------- bootstrap --------

(async () => {
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
