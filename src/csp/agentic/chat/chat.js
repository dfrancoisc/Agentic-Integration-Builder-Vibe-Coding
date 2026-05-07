// agentic_interop chat — Phase 3 streaming. POSTs to
// /api/agentic/chat/stream and consumes a text/event-stream of token,
// tool_start, tool_result, tool_error, status, done, error events.
// Auth pattern matches the admin SPA: try the parent SPA's bridge
// bearer (postMessage), then localStorage Basic, fall back to an
// inline overlay if both miss.

const API = '/api/agentic';
const AUTH_KEY = 'AGENTIC_AUTH';

let bridgeBearer = '';
let bridgeNamespace = '';
let authValidated = false;
let pending = false;
// Conversation transcript — replayed on every turn (the backend is
// stateless across turns; see ChatService.cls comment). "New chat"
// resets this to empty.
const history = [];
// Tokens for confirmation gates the user has approved this turn.
// Cleared after each send. Matches AgenticInterop.Policy.ConfirmationGate
// .ApprovedTokens (CSV on the server side).
let approvedTokens = [];

// Curated example prompts. The empty-state shows the first 6;
// `/examples` shows the full set. Each entry is { cat, title, prompt };
// `cat` is a short uppercase category label (BUILD / TRANSFORM /
// OPERATE / etc.) shown in tiny accent text above the title — gives
// the user a fast visual scan of what kind of work the prompt is.
const EXAMPLES = [
    {
        cat: 'BUILD',
        title: "ADT-to-ORU transformation with custom mappings",
        prompt: "Build me a production that receives HL7 v2.5 ADT^A01 messages over MLLP on port 5000, transforms them to ORU^R01 messages where PID-3 maps to OBR-3, PV1-7 maps to OBR-16, and PID-5 maps to OBX-5 for the patient name observation, then routes to a downstream LIS over MLLP on port 5100. Include ACK handling and a dead-letter queue for transformation failures."
    },
    {
        cat: 'TRANSFORM',
        title: "HL7-to-FHIR conversion and FHIR Server submission",
        prompt: "Create an interface that accepts any HL7 v2 message (ADT, ORU, ORM, MDM, SIU) on a single inbound MLLP service, transforms it to the appropriate FHIR R4 resources (Patient, Encounter, Observation, ServiceRequest, DocumentReference, Appointment) using the built-in HL7-to-SDA-to-FHIR pipeline, and POSTs the resulting Bundle to our FHIR Server at https://fhir.example.com/r4. Use OAuth2 client credentials for authentication."
    },
    {
        cat: 'OPERATE',
        title: "Production error triage",
        prompt: "Review the last 2 hours of errors across all productions in the HSPROD namespace. Group them by Business Host, show the top 5 most frequent error messages with counts, identify any messages stuck in 'Suspended' or 'Error' state, and recommend remediation steps. Use the Ens.MessageHeader and Ens.Util.Log tables."
    },
    {
        cat: 'TRANSFORM',
        title: "CDA to FHIR DocumentReference pipeline",
        prompt: "Build a production that ingests C-CDA documents via a REST endpoint at /api/v1/cda, validates them against the C-CDA R2.1 schema, transforms them to FHIR R4 (Composition + DocumentReference + Binary + extracted Patient/Encounter/Condition/MedicationStatement resources) using SDA3 as the intermediate model, and persists the Bundle to our FHIR repository. Failed documents should land in a quarantine folder with a JSON error report."
    },
    {
        cat: 'BUILD',
        title: "X12 270/271 eligibility broker",
        prompt: "I need a production that receives X12 270 eligibility inquiries over SFTP from a payer partner, parses them with the EnsLib.EDI.X12 framework, calls our internal eligibility REST API (JSON), constructs the X12 271 response with proper EB segments based on coverage type, and writes the 271 back to the payer's SFTP outbound folder. Include TA1/999 acknowledgments and audit logging."
    },
    {
        cat: 'REVIEW',
        title: "DTL review and optimization",
        prompt: "Here's our current ADT_A08_to_SDA3.dtl — review it for: (1) hardcoded values that should be lookup tables, (2) missing null/empty checks on source fields, (3) incorrect handling of repeating fields like PID-3 patient identifiers, (4) MRN assigning authority logic for our 4 source EHRs (Epic, Cerner, Meditech, Athena), and (5) any segments we're dropping that we shouldn't. Suggest a refactored version."
    },
    {
        cat: 'ROUTE',
        title: "Routing rule and BPL orchestration",
        prompt: "Build a Business Process in BPL that receives inbound HL7 ORU^R01 messages, routes lab results to three destinations based on OBR-24 (producer's service section ID): 'LAB' goes to our enterprise data warehouse via JDBC, 'RAD' goes to the PACS system over DICOM, and 'CARD' goes to the cardiology module via REST. Add a parallel branch that always sends a copy to the audit archive, and handle timeouts with retry logic (3 attempts, exponential backoff)."
    },
    {
        cat: 'TUNE',
        title: "Performance troubleshooting",
        prompt: "Our HL7 inbound service HL7.Epic.ADT.Service is showing message backlog during peak hours (7-9 AM). Analyze the production: check the queue depth via Ens.Queue, look at the Pool Size on the BS and downstream BP, review SQL stats on Ens.MessageHeader for slow inserts, and check journaling and locking patterns. Recommend tuning changes (pool sizes, async vs sync, message bank archival) and provide the SMP screens or ^%SYS.MONLBL commands to validate."
    },
    {
        cat: 'EXPORT',
        title: "FHIR Bulk Data export",
        prompt: "Configure a production component to perform a FHIR Bulk Data ($export) operation against our internal FHIR repository every Sunday at 2 AM, requesting Patient, Encounter, Condition, Observation, and MedicationRequest resources for a Group ID we'll parameterize. Poll the status endpoint, download the NDJSON files when complete, decompress them, and load each resource type into a corresponding staging table for downstream OMOP transformation. Include progress logging and failure alerts to a Teams webhook."
    },
    {
        cat: 'MIGRATE',
        title: "Production deployment and migration",
        prompt: "We're migrating a Health Connect 2022.1 production from an on-prem instance to Health Connect Cloud 2025.1. Generate the deployment artifacts: (1) export the production class, all DTLs, BPLs, custom message classes, lookup tables, and credentials as a single deployment package using $system.OBJ.Export with the right qualifiers, (2) flag any deprecated APIs or settings that won't carry forward (e.g., obsolete adapters, ENSDEMO references, removed SSL config keys), (3) produce a smoke-test checklist covering inbound connectivity, message routing, transformation correctness, and outbound delivery for the first 24 hours post-cutover."
    }
];

// Slash commands. Each runs a side-channel action (no LLM call) and
// renders a synthetic message into the chat. `/help` lists them all.
const SLASH_COMMANDS = {
    '/examples': { desc: 'Show all suggested prompts.', run: cmdExamples },
    '/example':  { desc: 'Alias for /examples.',         run: cmdExamples },
    '/help':     { desc: 'List slash commands.',         run: cmdHelp },
    '/clear':    { desc: 'Start a new conversation (clears history).', run: cmdClear },
    '/namespace':{ desc: 'Show the active IRIS namespace and access.', run: cmdNamespace },
    '/connection':{desc: 'Show the active LLM connection.',           run: cmdConnection },
    '/tools':    { desc: 'List the tools the router agent can call.', run: cmdTools },
    '/whoami':   { desc: 'Show the authenticated user + session info.',run: cmdWhoami }
};

// Visible (non-alias) commands for the autocomplete menu.
const SLASH_MENU_ITEMS = Object.entries(SLASH_COMMANDS)
    .filter(([k]) => k !== '/example')   // hide alias
    .map(([cmd, info]) => ({ cmd, desc: info.desc }));

// ============================================================
// Slash-command autocomplete menu
// ============================================================
let slashMenuEl = null;
let slashActiveIdx = -1;
let slashFiltered = [];

function buildSlashMenu() {
    if (slashMenuEl) return;
    slashMenuEl = document.createElement('div');
    slashMenuEl.className = 'slash-menu';
    slashMenuEl.id = 'slash-menu';
    slashMenuEl.hidden = true;
    // Insert inside composer-shell so it positions relative to it.
    document.querySelector('.composer-shell').appendChild(slashMenuEl);

    // Two handlers for click: mousedown prevents the textarea blur
    // from hiding the menu prematurely, and click actually runs the
    // command. Both are needed because some browsers (and Playwright)
    // fire blur between mousedown and click.
    slashMenuEl.addEventListener('mousedown', (e) => {
        if (e.target.closest('.slash-menu-item')) e.preventDefault();
    });
    slashMenuEl.addEventListener('click', (e) => {
        const item = e.target.closest('.slash-menu-item');
        if (!item) return;
        const cmd = item.dataset.cmd;
        $('input').value = '';
        hideSlashMenu();
        maybeRunSlashCommand(cmd);
        $('input').focus();
    });

    // Click outside both input and menu dismisses the menu.
    document.addEventListener('click', (e) => {
        if (!slashMenuVisible()) return;
        if (slashMenuEl.contains(e.target)) return;
        if (e.target === $('input')) return;
        hideSlashMenu();
    });
}

function showSlashMenu(filter) {
    if (!slashMenuEl) buildSlashMenu();
    const q = (filter || '').toLowerCase();
    slashFiltered = SLASH_MENU_ITEMS.filter(it => it.cmd.startsWith(q));
    if (slashFiltered.length === 0) {
        hideSlashMenu();
        return;
    }
    slashActiveIdx = 0;
    slashMenuEl.innerHTML =
        '<div class="slash-menu-head">Commands</div>' +
        slashFiltered.map((it, i) =>
            '<div class="slash-menu-item' + (i === 0 ? ' active' : '') +
            '" data-cmd="' + it.cmd + '" data-idx="' + i + '">' +
            '<span class="slash-cmd">' + it.cmd + '</span>' +
            '<span class="slash-desc">' + it.desc + '</span>' +
            '</div>'
        ).join('');
    slashMenuEl.hidden = false;
}

function hideSlashMenu() {
    if (!slashMenuEl) return;
    slashMenuEl.hidden = true;
    slashActiveIdx = -1;
    slashFiltered = [];
}

function slashMenuVisible() {
    return slashMenuEl && !slashMenuEl.hidden;
}

function slashMenuNav(dir) {
    if (!slashMenuVisible() || slashFiltered.length === 0) return;
    const items = slashMenuEl.querySelectorAll('.slash-menu-item');
    if (items[slashActiveIdx]) items[slashActiveIdx].classList.remove('active');
    slashActiveIdx = (slashActiveIdx + dir + slashFiltered.length) % slashFiltered.length;
    if (items[slashActiveIdx]) {
        items[slashActiveIdx].classList.add('active');
        items[slashActiveIdx].scrollIntoView({ block: 'nearest' });
    }
}

function slashMenuSelect() {
    if (!slashMenuVisible() || slashActiveIdx < 0) return false;
    const chosen = slashFiltered[slashActiveIdx];
    if (!chosen) return false;
    $('input').value = '';
    hideSlashMenu();
    maybeRunSlashCommand(chosen.cmd);
    $('input').focus();
    return true;
}

function renderEmptyState(target) {
    target = target || $('messages');
    target.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.className = 'empty-state';
    wrap.id = 'empty-state';
    const six = EXAMPLES.slice(0, 6);
    const tile = (e, i) =>
        `<button class="example" data-example-idx="${i}" type="button">` +
            `<span class="ex-cat">${escapeHtml(e.cat || '')}</span>` +
            `<span class="ex-arrow">&rarr;</span>` +
            `<span class="ex-title">${escapeHtml(e.title)}</span>` +
        `</button>`;
    wrap.innerHTML =
        '<p class="hero-eyebrow">Health Interop &middot; Copilot</p>' +
        '<h1 class="hero-title">How can I help?</h1>' +
        '<p class="hero-sub">Describe your interoperability goal in plain English &mdash; or pick a starter below. ' +
        'The agent reaches into IRIS for Health to read productions, validate messages, and propose changes. ' +
        'Mutating actions always pause for your approval.</p>' +
        '<div class="example-grid">' + six.map(tile).join('') + '</div>' +
        '<p class="hero-tip">Type <code class="kbd">/help</code> for shortcuts &middot; ' +
        '<code class="kbd">/examples</code> for ' + EXAMPLES.length + ' suggestions</p>';
    target.appendChild(wrap);
}

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
        function finish(p) { if (done) return; done = true; resolve(p || {}); }
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

const $ = (id) => document.getElementById(id);

function getStoredAuth() { try { return localStorage.getItem(AUTH_KEY) || ''; } catch { return ''; } }
function setStoredAuth(v) { try { localStorage.setItem(AUTH_KEY, v); } catch {} }

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

function showLoginOverlay(message) {
    return new Promise((resolve) => {
        const existing = document.getElementById('agentic-login-overlay');
        if (existing) existing.remove();
        const overlay = document.createElement('div');
        overlay.id = 'agentic-login-overlay';
        overlay.style.cssText =
            'position:fixed;inset:0;background:rgba(15,17,21,0.85);z-index:9999;' +
            'display:flex;align-items:center;justify-content:center;color:#e6e8eb;';
        overlay.innerHTML =
            '<form id="agentic-login-form" style="background:#161a21;border:1px solid #2a313c;border-radius:6px;padding:24px;width:340px;display:flex;flex-direction:column;gap:12px;">' +
            '<div style="font-weight:600;font-size:14px;">Sign in to AI Chatbot</div>' +
            '<div style="color:#8b95a6;font-size:12px;line-height:1.4;">' + (message || 'Enter your IRIS credentials.') + '</div>' +
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

async function bootstrapAuth() {
    if (authValidated) return;
    if (bridgeBearer && await probeAuth(bridgeBearer)) { authValidated = true; return; }
    bridgeBearer = '';
    const stored = getStoredAuth();
    if (stored && await probeAuth(stored)) { authValidated = true; return; }
    await showLoginOverlay();
    authValidated = true;
}

function authHeader() { return bridgeBearer || getStoredAuth(); }

function toast(msg, kind = '') {
    const t = $('toast');
    t.textContent = msg;
    t.className = 'toast' + (kind ? ' ' + kind : '');
    t.hidden = false;
    setTimeout(() => { t.hidden = true; }, 3500);
}

// Build an empty assistant message bubble. Returns the DOM nodes the
// stream loop appends to: text node for tokens, container for tool
// cards, meta line populated on `done`.
function newAssistantBubble() {
    const empty = $('empty-state');
    if (empty) empty.remove();
    const wrap = document.createElement('div');
    wrap.className = 'message assistant';
    const role = document.createElement('span');
    role.className = 'role';
    role.textContent = 'health interop';
    wrap.appendChild(role);
    const tools = document.createElement('div');
    tools.className = 'tool-stack';
    wrap.appendChild(tools);
    const text = document.createElement('div');
    text.className = 'text';
    wrap.appendChild(text);
    const cursor = document.createElement('span');
    cursor.className = 'caret';
    text.appendChild(cursor);
    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.hidden = true;
    wrap.appendChild(meta);
    $('messages').appendChild(wrap);
    $('messages').scrollTop = $('messages').scrollHeight;
    return { wrap, tools, text, cursor, meta };
}

function appendUserMessage(content) {
    const empty = $('empty-state');
    if (empty) empty.remove();
    const el = document.createElement('div');
    el.className = 'message user';
    const role = document.createElement('span');
    role.className = 'role';
    role.textContent = 'you';
    el.appendChild(role);
    el.appendChild(document.createTextNode(content));
    $('messages').appendChild(el);
    $('messages').scrollTop = $('messages').scrollHeight;
    return el;
}

function appendErrorMessage(text) {
    const el = document.createElement('div');
    el.className = 'message error';
    const role = document.createElement('span');
    role.className = 'role';
    role.textContent = 'error';
    el.appendChild(role);
    el.appendChild(document.createTextNode(text));
    $('messages').appendChild(el);
    $('messages').scrollTop = $('messages').scrollHeight;
}

// Tool-call card. Status starts at "running"; transitions to ok/error
// when the matching tool_result/tool_error event arrives. No icons,
// no emojis — colored dot + uppercase text label only, per the
// InterSystems internal style preference.
function newToolCard(stack, name) {
    const card = document.createElement('details');
    card.className = 'tool-card status-running';
    card.open = false;
    const summary = document.createElement('summary');
    const dot = document.createElement('span');
    dot.className = 'status-dot running';
    summary.appendChild(dot);
    const label = document.createElement('span');
    label.className = 'tool-name';
    label.textContent = name;
    summary.appendChild(label);
    const status = document.createElement('span');
    status.className = 'tool-status';
    status.textContent = 'RUNNING';
    summary.appendChild(status);
    card.appendChild(summary);
    const body = document.createElement('div');
    body.className = 'tool-body';
    const argsBlock = document.createElement('pre');
    argsBlock.className = 'tool-args';
    argsBlock.textContent = '';
    body.appendChild(argsBlock);
    const resultBlock = document.createElement('pre');
    resultBlock.className = 'tool-result';
    resultBlock.textContent = '';
    body.appendChild(resultBlock);
    card.appendChild(body);
    stack.appendChild(card);
    return { card, argsBlock, resultBlock, status, dot };
}

// Render an Approve / Reject card for a pending mutating tool call.
// The card is open by default (the user needs to act); APPROVE adds
// the token to the next request and re-fires the same tool intent;
// REJECT just dismisses the card. No icons or emojis — uppercase
// text labels + colored dot, same convention as the running tool
// card.
function newApprovalCard(stack, payload) {
    const card = document.createElement('details');
    card.className = 'tool-card status-pending';
    card.open = true;
    const summary = document.createElement('summary');
    const dot = document.createElement('span');
    dot.className = 'status-dot pending';
    summary.appendChild(dot);
    const label = document.createElement('span');
    label.className = 'tool-name';
    label.textContent = payload.tool || '(unknown tool)';
    summary.appendChild(label);
    const status = document.createElement('span');
    status.className = 'tool-status';
    status.textContent = 'AWAITING APPROVAL';
    summary.appendChild(status);
    card.appendChild(summary);
    const body = document.createElement('div');
    body.className = 'tool-body';
    const msg = document.createElement('div');
    msg.className = 'tool-confirm-msg';
    msg.textContent = payload.message || 'This tool changes IRIS state. Approve to run, reject to cancel.';
    body.appendChild(msg);
    const argsBlock = document.createElement('pre');
    argsBlock.className = 'tool-args';
    try {
        argsBlock.textContent = typeof payload.arguments === 'string'
            ? payload.arguments
            : JSON.stringify(payload.arguments || {}, null, 2);
    } catch { argsBlock.textContent = String(payload.arguments || ''); }
    body.appendChild(argsBlock);
    const actions = document.createElement('div');
    actions.className = 'tool-actions';
    const approve = document.createElement('button');
    approve.type = 'button';
    approve.className = 'btn-approve';
    approve.textContent = 'APPROVE';
    const reject = document.createElement('button');
    reject.type = 'button';
    reject.className = 'btn-reject';
    reject.textContent = 'REJECT';
    actions.appendChild(approve);
    actions.appendChild(reject);
    body.appendChild(actions);
    card.appendChild(body);
    stack.appendChild(card);

    approve.addEventListener('click', () => {
        if (pending) return;
        approve.disabled = true;
        reject.disabled = true;
        card.className = 'tool-card status-approving';
        dot.className = 'status-dot running';
        status.textContent = 'APPROVED — RUNNING';
        approvedTokens.push(payload.token);
        // Re-fire the user's intent so the agent retries the tool.
        send('Approved. Please proceed with the action above.');
    });
    reject.addEventListener('click', () => {
        approve.disabled = true;
        reject.disabled = true;
        card.className = 'tool-card status-error';
        dot.className = 'status-dot error';
        status.textContent = 'REJECTED';
        // No backend call — the model already received the deny last
        // turn and has explained it. The user can type a follow-up.
    });

    return { card, status, dot };
}

function setToolStatus(card, kind) {
    card.card.className = 'tool-card status-' + kind;
    card.dot.className = 'status-dot ' + kind;
    card.status.textContent = kind.toUpperCase();
}

// Read a Server-Sent Events response body and yield {event, data}
// objects. Buffers across chunk boundaries so multi-line events arrive
// intact regardless of how the network frames the bytes.
async function* readSSE(res) {
    const reader = res.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buf = '';
    while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        let idx;
        while ((idx = buf.indexOf('\n\n')) !== -1) {
            const block = buf.slice(0, idx);
            buf = buf.slice(idx + 2);
            let event = 'message';
            const dataLines = [];
            for (const line of block.split('\n')) {
                if (line.startsWith(':')) continue;
                if (line.startsWith('event: ')) { event = line.slice(7).trim(); continue; }
                if (line.startsWith('data: ')) { dataLines.push(line.slice(6)); continue; }
            }
            const dataStr = dataLines.join('\n');
            if (dataStr === '' && event === 'message') continue;
            let data = null;
            try { data = dataStr ? JSON.parse(dataStr) : null; } catch { data = dataStr; }
            yield { event, data };
        }
    }
}

async function send(message) {
    if (pending) return;
    pending = true;
    $('btn-send').disabled = true;
    $('input').disabled = true;
    appendUserMessage(message);
    const bubble = newAssistantBubble();
    const toolCardsByName = new Map();
    let assistantText = '';
    try {
        // Send the active namespace as X-IRIS-Namespace so the
        // Dispatch.OnPreDispatch gate fires. If the user has no
        // permission for that namespace, the gate refuses with 403
        // BEFORE the chat method runs.
        const headers = { 'Content-Type': 'application/json', 'Authorization': authHeader() };
        if (bridgeNamespace) headers['X-IRIS-Namespace'] = bridgeNamespace;
        // Pull the approved tokens captured since the last send and
        // clear the queue — they apply to THIS turn only.
        const tokensThisTurn = approvedTokens.slice();
        approvedTokens = [];
        const res = await fetch(API + '/chat/stream', {
            method: 'POST',
            headers,
            body: JSON.stringify({ message, history, approvedTokens: tokensThisTurn })
        });
        if (res.status === 401) {
            authValidated = false;
            throw new Error('Authorization rejected.');
        }
        if (res.status === 403) {
            const j = await res.json().catch(() => ({}));
            throw new Error('Access denied to namespace ' + (j.namespace || '?') + '. Your IRIS user (' + (j.user || $('ns-value').textContent) + ') does not have permission to operate in this namespace.');
        }
        if (res.status === 400) {
            const j = await res.json().catch(() => ({}));
            throw new Error((j.error || 'Bad request') + (j.namespace ? ': ' + j.namespace : ''));
        }
        if (!res.ok) {
            throw new Error('HTTP ' + res.status);
        }
        for await (const { event, data } of readSSE(res)) {
            if (event === 'token' && data && typeof data.text === 'string') {
                assistantText += data.text;
                bubble.cursor.before(document.createTextNode(data.text));
                $('messages').scrollTop = $('messages').scrollHeight;
            } else if (event === 'tool_start' && data && data.name) {
                const card = newToolCard(bubble.tools, data.name);
                if (data.args) {
                    try { card.argsBlock.textContent = JSON.stringify(data.args, null, 2); }
                    catch { card.argsBlock.textContent = String(data.args); }
                }
                toolCardsByName.set(data.name, card);
            } else if (event === 'tool_result' && data && data.name) {
                const card = toolCardsByName.get(data.name);
                if (card) {
                    setToolStatus(card, 'ok');
                    if (data.result !== undefined) {
                        try { card.resultBlock.textContent = typeof data.result === 'string' ? data.result : JSON.stringify(data.result, null, 2); }
                        catch { card.resultBlock.textContent = String(data.result); }
                    }
                }
            } else if (event === 'tool_error' && data && data.name) {
                const card = toolCardsByName.get(data.name);
                if (card) {
                    setToolStatus(card, 'error');
                    card.resultBlock.textContent = data.error || '(unknown error)';
                    card.card.open = true;
                }
            } else if (event === 'tool_confirm' && data && data.token) {
                // Mutating tool was blocked by ConfirmationGate. Render
                // an Approve / Reject card; user clicks drive the next
                // turn.
                newApprovalCard(bubble.tools, data);
            } else if (event === 'status') {
                // Reserved for live progress updates. No UI surface yet.
            } else if (event === 'done' && data) {
                const replayInfo = (data.turnsReplayed > 0) ? ' · replayed ' + data.turnsReplayed + ' prior' : '';
                const toolInfo = data.toolTrace ? ' · tools: ' + data.toolTrace : '';
                bubble.meta.textContent =
                    (data.connection || '') + ' · ' + (data.model || '') +
                    ' · ' + (data.latencyMs || '?') + 'ms' + toolInfo +
                    ' · ns:' + (data.namespace || '') + replayInfo;
                bubble.meta.hidden = false;
                if (data.connection) updateConnectionPill(data.connection);
            } else if (event === 'error' && data) {
                throw new Error((data.error || 'Stream error') + (data.stage ? ' [stage: ' + data.stage + ']' : ''));
            }
        }
        bubble.cursor.remove();
        // Persist the turn for replay on the next message.
        history.push({ role: 'user', content: message });
        history.push({ role: 'assistant', content: assistantText });
        // Snapshot the conversation into localStorage so the history
        // rail picks it up. Idempotent — first turn assigns an id,
        // subsequent turns overwrite the same row and float it to top.
        persistCurrentConv();
    } catch (e) {
        bubble.cursor.remove();
        bubble.wrap.classList.add('errored');
        appendErrorMessage(e.message || String(e));
    } finally {
        pending = false;
        $('btn-send').disabled = false;
        $('input').disabled = false;
        $('input').focus();
    }
}

function updateConnectionPill(name) {
    const pill = $('conn-pill');
    if (!pill) return;
    if (name) {
        pill.classList.remove('unknown');
        $('conn-value').textContent = name;
    } else {
        pill.classList.add('unknown');
        $('conn-value').textContent = 'not configured';
    }
}

// Resolve the default Connection at boot so the pill shows the right
// name BEFORE the user sends the first message. Reads /connections,
// finds the row with isDefault=1 (and enabled=1). If none, marks the
// pill "not configured" so the operator knows to set one up.
async function resolveDefaultConnection() {
    try {
        const r = await fetch(API + '/connections', {
            headers: { Authorization: authHeader(), Accept: 'application/json' }
        });
        if (!r.ok) { updateConnectionPill(''); return; }
        const j = await r.json();
        const list = (j && j.connections) || [];
        let pick = list.find(c => c.isDefault && c.enabled);
        if (!pick) pick = list.find(c => c.enabled);
        if (!pick) pick = list[0];
        updateConnectionPill(pick ? pick.name : '');
    } catch {
        updateConnectionPill('');
    }
}

function setNamespacePill(ns) {
    const pill = $('ns-pill');
    if (ns) {
        pill.classList.remove('unknown');
        $('ns-value').textContent = ns;
    } else {
        pill.classList.add('unknown');
        $('ns-value').textContent = 'unknown';
    }
}

$('composer').addEventListener('submit', (e) => {
    e.preventDefault();
    const txt = $('input').value.trim();
    if (!txt) return;
    $('input').value = '';
    hideSlashMenu();
    // Slash commands run side-channel — they must NOT round-trip
    // through send(), the LLM, or the conversation history. The
    // dispatcher below renders a synthetic system card and returns.
    if (maybeRunSlashCommand(txt)) return;
    send(txt);
});

// Show / filter the slash-command autocomplete when the user types
// a "/" at the start of a line. Hides when the text doesn't match.
$('input').addEventListener('input', () => {
    const val = $('input').value;
    if (val.startsWith('/') && val.indexOf('\n') === -1) {
        showSlashMenu(val);
    } else {
        hideSlashMenu();
    }
});
// Blur hides the menu after a brief delay — long enough for the
// mousedown preventDefault on the menu to cancel the blur when the
// user is clicking an item, short enough to feel instant otherwise.
$('input').addEventListener('blur', () => { setTimeout(hideSlashMenu, 200); });

$('input').addEventListener('keydown', (e) => {
    // When the slash menu is visible, arrow keys navigate and
    // Enter / Tab select the highlighted command.
    if (slashMenuVisible()) {
        if (e.key === 'ArrowDown') {
            e.preventDefault();
            slashMenuNav(1);
            return;
        }
        if (e.key === 'ArrowUp') {
            e.preventDefault();
            slashMenuNav(-1);
            return;
        }
        if (e.key === 'Enter' || e.key === 'Tab') {
            e.preventDefault();
            slashMenuSelect();
            return;
        }
        if (e.key === 'Escape') {
            e.preventDefault();
            hideSlashMenu();
            return;
        }
    }
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        $('composer').dispatchEvent(new Event('submit', { cancelable: true }));
    }
});

$('btn-new-chat').addEventListener('click', () => {
    startNewConversation();
});

// Delegated handler — clicking any .example tile (initial empty
// state OR /examples panel) loads its full prompt into the composer
// and focuses the textarea. The user can edit and Enter to send, or
// hit Enter as-is. The data-example-idx attribute points into the
// EXAMPLES array so we don't have to round-trip the full prompt
// through the DOM.
function loadExampleByIdx(idx) {
    const ex = EXAMPLES[idx];
    if (!ex) return;
    $('input').value = ex.prompt;
    $('input').focus();
    const inp = $('input');
    inp.selectionStart = inp.selectionEnd = inp.value.length;
}
$('messages').addEventListener('click', (e) => {
    const tile = e.target.closest('[data-example-idx]');
    if (!tile) return;
    loadExampleByIdx(+tile.dataset.exampleIdx);
});
$('messages').addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    const tile = e.target.closest('[data-example-idx]');
    if (!tile) return;
    e.preventDefault();
    loadExampleByIdx(+tile.dataset.exampleIdx);
});

// ============================================================
// Slash commands. Run side-channel — never sent to the LLM.
// ============================================================

function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function appendSystemCard(html) {
    const card = document.createElement('div');
    card.className = 'system-card';
    card.innerHTML = html;
    const empty = $('empty-state');
    if (empty) empty.remove();
    $('messages').appendChild(card);
    $('messages').scrollTop = $('messages').scrollHeight;
}

// Tiny JSON GET helper for slash commands. Inherits the auth header
// + namespace bridge the chat stream uses so the dispatch gate sees
// the same identity. Throws on non-2xx so callers can render the
// HTTP error verbatim into a system card.
async function api(path, init) {
    init = init || {};
    init.headers = Object.assign({
        'Authorization': authHeader(),
        'Accept': 'application/json'
    }, init.headers || {});
    if (bridgeNamespace) init.headers['X-IRIS-Namespace'] = bridgeNamespace;
    init.cache = 'no-store';
    const r = await fetch(API + path, init);
    if (!r.ok) {
        let body = '';
        try { body = await r.text(); } catch {}
        throw new Error('HTTP ' + r.status + (body ? ' — ' + body.slice(0, 240) : ''));
    }
    return r.json();
}

function cmdHelp() {
    const rows = Object.entries(SLASH_COMMANDS)
        .filter(([k]) => k !== '/example')   // hide the alias
        .map(([cmd, info]) => `<tr><td><code>${escapeHtml(cmd)}</code></td><td>${escapeHtml(info.desc)}</td></tr>`)
        .join('');
    appendSystemCard(`
        <div class="system-card-head">slash commands</div>
        <table class="system-table"><tbody>${rows}</tbody></table>
    `);
}

function cmdExamples() {
    const tile = (e, i) =>
        `<button class="example" data-example-idx="${i}" type="button">` +
            `<span class="ex-cat">${escapeHtml(e.cat || '')}</span>` +
            `<span class="ex-arrow">&rarr;</span>` +
            `<span class="ex-title">${escapeHtml(e.title)}</span>` +
        `</button>`;
    const tiles = EXAMPLES.map(tile).join('');
    appendSystemCard(
        '<div class="system-card-head">' + EXAMPLES.length + ' starter prompts</div>' +
        '<p class="muted">Click any tile to load it into the composer.</p>' +
        '<div class="example-grid example-grid-wide">' + tiles + '</div>'
    );
}

function cmdClear() {
    startNewConversation();
}

async function cmdNamespace() {
    const ns = bridgeNamespace || $('ns-value').textContent || '(unknown)';
    let dispatchNs = '?';
    try { const j = await api('/namespace'); dispatchNs = j.namespace || '?'; } catch {}
    appendSystemCard(`
        <div class="system-card-head">namespace</div>
        <table class="system-table"><tbody>
            <tr><td>chat scope</td><td><code>${escapeHtml(ns)}</code> <span class="muted">(sent as X-IRIS-Namespace)</span></td></tr>
            <tr><td>dispatch ns</td><td><code>${escapeHtml(dispatchNs)}</code> <span class="muted">(where the AgenticInterop classes live; tools switch internally)</span></td></tr>
        </tbody></table>
    `);
}

async function cmdConnection() {
    try {
        const j = await api('/connections');
        const list = (j && j.connections) || [];
        const def = list.find(c => c.isDefault && c.enabled) || list.find(c => c.enabled) || list[0];
        if (!def) {
            appendSystemCard(`<div class="system-card-head">connection</div><p class="muted">No connections configured. Open the admin to add one.</p>`);
            return;
        }
        const last = def.lastTestOk === 1 ? 'tested ok' : (def.lastTestOk === 0 ? 'last test failed' : 'untested');
        appendSystemCard(`
            <div class="system-card-head">active LLM connection</div>
            <table class="system-table"><tbody>
                <tr><td>name</td><td><code>${escapeHtml(def.name)}</code></td></tr>
                <tr><td>provider</td><td><code>${escapeHtml(def.provider)}</code></td></tr>
                <tr><td>model</td><td><code>${escapeHtml(def.model || '')}</code></td></tr>
                <tr><td>region</td><td><code>${escapeHtml(def.region || '—')}</code></td></tr>
                <tr><td>status</td><td>${escapeHtml(last)}${def.lastTestLatencyMs ? ` · ${def.lastTestLatencyMs}ms` : ''}</td></tr>
            </tbody></table>
        `);
    } catch (e) {
        appendSystemCard(`<div class="system-card-head">connection</div><p>${escapeHtml(e.message)}</p>`);
    }
}

async function cmdTools() {
    var head = '<tr><td colspan="2" style="padding-top:10px;color:var(--accent);font:600 10px ui-monospace,Menlo,monospace;text-transform:uppercase;letter-spacing:0.10em;">';
    var mut = ' <span class="badge-mute">mutating</span>';
    appendSystemCard(
        '<div class="system-card-head">tools the agent can call</div>' +
        '<p class="muted">Auto-discovered from <code>%AI.Tool</code> subclasses. Names are PascalCase per the IRIS framework idiom. Read-only tools fire freely; mutating tools route through the confirmation gate so you approve each action.</p>' +
        '<table class="system-table"><tbody>' +
            head + 'Catalog (AgenticInterop.Tool.Catalog)</td></tr>' +
            '<tr><td><code>GetUserNamespace</code></td><td>Returns the namespace this chat is scoped to.</td></tr>' +
            '<tr><td><code>ListUserAccessibleNamespaces</code></td><td>Namespaces the user can read.</td></tr>' +
            '<tr><td><code>DescribeClass</code></td><td>Read <code>%Dictionary</code> metadata for any compiled class.</td></tr>' +
            '<tr><td><code>ExplainStatus</code></td><td>Decode a serialized IRIS %Status string.</td></tr>' +
            '<tr><td><code>LookupErrorCode</code></td><td>Numeric IRIS error code (~4500 entries from the InterSystems Error Reference).</td></tr>' +
            '<tr><td><code>LookupGlossaryTerm</code></td><td>InterSystems Glossary of Terms (~250 entries).</td></tr>' +
            '<tr><td><code>SearchApiIndex</code></td><td>Search the InterSystems Detailed API Index (~80 topic pages).</td></tr>' +
            '<tr><td><code>SearchEns</code></td><td>Vector search across <code>Ens.*</code> hosts and adapters.</td></tr>' +
            '<tr><td><code>SearchHs</code></td><td>Vector search across <code>HS.*</code> transformation classes.</td></tr>' +
            head + 'Production (AgenticInterop.Tool.Production)</td></tr>' +
            '<tr><td><code>ListProductions</code></td><td>Inventory productions.</td></tr>' +
            '<tr><td><code>GetProduction</code></td><td>Show a production\'s hosts and per-host settings.</td></tr>' +
            '<tr><td><code>StartProduction</code>' + mut + '</td><td>Start a named production.</td></tr>' +
            '<tr><td><code>StopProduction</code>' + mut + '</td><td>Stop the active production.</td></tr>' +
            '<tr><td><code>CreateProduction</code>' + mut + '</td><td>Create an empty production class.</td></tr>' +
            '<tr><td><code>DeleteProduction</code>' + mut + '</td><td>Delete a production class.</td></tr>' +
            '<tr><td><code>AddBusinessHost</code>' + mut + '</td><td>Add a Service / Process / Operation to a production.</td></tr>' +
            '<tr><td><code>RemoveBusinessHost</code>' + mut + '</td><td>Remove a host from a production.</td></tr>' +
            '<tr><td><code>UpdateBusinessHostSettings</code>' + mut + '</td><td>Modify settings on an existing host.</td></tr>' +
            head + 'Testing (AgenticInterop.Tool.Testing)</td></tr>' +
            '<tr><td><code>ValidateHL7Structure</code></td><td>Parse an HL7 v2 message; returns headers, segment count, schema validity.</td></tr>' +
            '<tr><td><code>ValidateHL7Semantics</code></td><td>Schema-aware HL7 v2 validation against a DocType.</td></tr>' +
            '<tr><td><code>ValidateFHIRResource</code></td><td>Structural check on a FHIR R4 JSON resource.</td></tr>' +
            '<tr><td><code>CompareMessages</code></td><td>Diff two HL7 v2 messages segment-by-segment, field-by-field.</td></tr>' +
            '<tr><td><code>SendHL7</code>' + mut + '</td><td>Push an HL7 message into a configured Business Service.</td></tr>' +
            '<tr><td><code>SendFHIR</code>' + mut + '</td><td>HTTP POST a FHIR resource to an external endpoint.</td></tr>' +
            head + 'Transform (AgenticInterop.Tool.Transform)</td></tr>' +
            '<tr><td><code>ListDTLs</code></td><td>List Data Transformation Language classes.</td></tr>' +
            '<tr><td><code>ListLookupTables</code></td><td>List lookup tables defined in the namespace.</td></tr>' +
            '<tr><td><code>ListBusinessRules</code></td><td>List business / routing rule classes.</td></tr>' +
            '<tr><td><code>DryRunDTL</code></td><td>Run a DTL transformation in-process and return the result.</td></tr>' +
            '<tr><td><code>CompileDTL</code>' + mut + '</td><td>Recompile a DTL class.</td></tr>' +
            '<tr><td><code>CreateDTL</code>' + mut + '</td><td>Create a DTL skeleton.</td></tr>' +
            '<tr><td><code>UpdateDTL</code>' + mut + '</td><td>Replace the body of a DTL\'s &lt;transform&gt; XData and recompile.</td></tr>' +
            '<tr><td><code>CreateBPL</code>' + mut + '</td><td>Create a BPL skeleton.</td></tr>' +
            '<tr><td><code>ValidateBPL</code>' + mut + '</td><td>Compile a BPL class to verify the &lt;process&gt; XML.</td></tr>' +
            head + 'Monitoring (AgenticInterop.Tool.Monitoring)</td></tr>' +
            '<tr><td><code>QueryEventLog</code></td><td>Query Ens.Util.Log for errors/warnings/info by time and host.</td></tr>' +
            '<tr><td><code>TopErrors</code></td><td>Top N most frequent errors grouped by host and text.</td></tr>' +
            '<tr><td><code>QueryMessageStatus</code></td><td>Find messages by status (Error, Suspended, Queued, Deferred).</td></tr>' +
            '<tr><td><code>MessageSummary</code></td><td>Message counts by status and by host (dashboard view).</td></tr>' +
            '<tr><td><code>QueueStatus</code></td><td>Queue depths for all active business hosts.</td></tr>' +
        '</tbody></table>' +
        '<p class="muted" style="margin-top:10px;">36 tools across 5 <code>%AI.Tool</code> providers, plus 9 Skills as sub-agent tools and 2 vector-search tools. Catalog tools backed by the seeded IRIS reference PDFs (~4900 records). Browse the registry with descriptions, schemas, and dry-run under <strong>Configuration &rarr; Tools</strong>.</p>'
    );
}

async function cmdWhoami() {
    try {
        const j = await api('/whoami');
        appendSystemCard(`
            <div class="system-card-head">session</div>
            <table class="system-table"><tbody>
                <tr><td>user</td><td><code>${escapeHtml(j.username || '?')}</code></td></tr>
                <tr><td>namespace (chat scope)</td><td><code>${escapeHtml(bridgeNamespace || '?')}</code></td></tr>
                <tr><td>namespace (dispatch)</td><td><code>${escapeHtml(j.namespace || '?')}</code></td></tr>
                <tr><td>session id</td><td><code>${escapeHtml(j.sessionId || '—')}</code></td></tr>
            </tbody></table>
        `);
    } catch (e) {
        appendSystemCard(`<div class="system-card-head">session</div><p>${escapeHtml(e.message)}</p>`);
    }
}

// ============================================================
// Conversation store. Past chats are persisted in localStorage
// (browser-scoped — server-side persistence is a separate ticket;
// the audit trail still captures every turn server-side via
// HealthInterop.Data.Conversation, but the rail here is the user's
// quick-resume surface).
//
// Schema:
//   localStorage['AGENTIC_CONVS'] = JSON.stringify([
//     { id, title, createdAt, updatedAt, messages: [{role, content}] },
//     ...
//   ])
//
// We cap at 100 conversations to stay well under the typical 5MB
// localStorage budget. Trimming policy: oldest by updatedAt drops first.
// ============================================================

const CONV_KEY = 'AGENTIC_CONVS';
const RAIL_KEY = 'AGENTIC_RAIL';
let currentConvId = null;

function loadConvList() {
    try {
        const raw = localStorage.getItem(CONV_KEY);
        const parsed = raw ? JSON.parse(raw) : [];
        return Array.isArray(parsed) ? parsed : [];
    } catch { return []; }
}
function saveConvList(list) {
    try {
        const trimmed = list
            .slice()
            .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
            .slice(0, 100);
        localStorage.setItem(CONV_KEY, JSON.stringify(trimmed));
    } catch (e) {
        // Likely QuotaExceeded — drop the oldest half and retry once.
        try {
            const half = list.slice(0, Math.max(1, Math.floor(list.length / 2)));
            localStorage.setItem(CONV_KEY, JSON.stringify(half));
        } catch {}
    }
}
function genConvId() {
    return 'c_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 6);
}
function deriveTitle(messages) {
    const first = (messages || []).find(m => m.role === 'user');
    if (!first) return 'Untitled chat';
    const t = String(first.content || '').replace(/\s+/g, ' ').trim();
    if (!t) return 'Untitled chat';
    return t.length > 64 ? (t.slice(0, 64) + '…') : t;
}
function formatRelative(ts) {
    if (!ts) return '';
    const now = Date.now();
    const d = Math.max(0, now - ts);
    if (d < 60000) return 'just now';
    if (d < 3600000) {
        const m = Math.round(d / 60000);
        return m + ' min ago';
    }
    const date = new Date(ts);
    const today = new Date(); today.setHours(0,0,0,0);
    if (date >= today) {
        return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    }
    const yest = new Date(today); yest.setDate(yest.getDate() - 1);
    if (date >= yest) return 'yesterday';
    const wk = new Date(today); wk.setDate(wk.getDate() - 6);
    if (date >= wk) return date.toLocaleDateString(undefined, { weekday: 'short' });
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

// Snapshot the current in-memory `history` into the store. Called
// after every completed turn (in send()'s `done` branch). Idempotent —
// safe to call repeatedly. Reorders the conversation to the top.
function persistCurrentConv() {
    if (!history.length) return;
    const list = loadConvList();
    const now = Date.now();
    let row;
    if (currentConvId) {
        const idx = list.findIndex(c => c.id === currentConvId);
        if (idx >= 0) {
            row = list[idx];
            list.splice(idx, 1);
        }
    }
    if (!row) {
        currentConvId = currentConvId || genConvId();
        row = { id: currentConvId, title: deriveTitle(history), createdAt: now, updatedAt: now, messages: history.slice() };
    } else {
        row.messages = history.slice();
        if (!row.title || row.title === 'Untitled chat') row.title = deriveTitle(history);
        row.updatedAt = now;
    }
    list.unshift(row);
    saveConvList(list);
    renderRail();
}

function startNewConversation() {
    currentConvId = null;
    history.length = 0;
    approvedTokens = [];
    const m = $('messages');
    if (m) m.innerHTML = '<div class="empty-state" id="empty-state"></div>';
    renderEmptyState();
    renderRail();
    const inp = $('input');
    if (inp) inp.focus();
}

function loadConversation(id) {
    const list = loadConvList();
    const conv = list.find(c => c.id === id);
    if (!conv) return;
    currentConvId = id;
    history.length = 0;
    approvedTokens = [];
    const m = $('messages');
    m.innerHTML = '';
    for (const msg of (conv.messages || [])) {
        if (!msg || !msg.role) continue;
        history.push({ role: msg.role, content: msg.content || '' });
        if (msg.role === 'user') {
            appendUserMessage(msg.content || '');
        } else if (msg.role === 'assistant') {
            const bubble = newAssistantBubble();
            bubble.cursor.remove();
            bubble.text.appendChild(document.createTextNode(msg.content || ''));
        }
    }
    renderRail();
    const inp = $('input');
    if (inp) inp.focus();
}

function deleteConversation(id) {
    const list = loadConvList().filter(c => c.id !== id);
    saveConvList(list);
    if (id === currentConvId) {
        startNewConversation();
    } else {
        renderRail();
    }
}

function renderRail() {
    const list = loadConvList();
    const railList = $('rail-list');
    const railCount = $('rail-count');
    if (!railList || !railCount) return;
    railCount.textContent = list.length ? String(list.length) : '';
    if (list.length === 0) {
        railList.innerHTML = '<div class="rail-empty">No saved chats yet.<br>Start a conversation below &mdash; your past sessions will appear here, this browser only.</div>';
        return;
    }
    const rows = list.map(conv => {
        const active = conv.id === currentConvId ? ' active' : '';
        const cnt = (conv.messages || []).filter(m => m.role === 'user').length;
        const turnLbl = cnt + ' turn' + (cnt === 1 ? '' : 's');
        return (
            '<div class="rail-item' + active + '" data-conv-id="' + escapeHtml(conv.id) + '" tabindex="0">' +
                '<span class="ri-title">' + escapeHtml(conv.title || 'Untitled chat') + '</span>' +
                '<span class="ri-meta">' +
                    '<span>' + escapeHtml(formatRelative(conv.updatedAt || conv.createdAt)) + '</span>' +
                    '<span class="ri-dot">&middot;</span>' +
                    '<span>' + turnLbl + '</span>' +
                '</span>' +
                '<button class="ri-del" type="button" data-del-id="' + escapeHtml(conv.id) + '" title="Delete this chat">Del</button>' +
            '</div>'
        );
    });
    railList.innerHTML = rows.join('');
}

function setupHistoryRail() {
    const btn = $('btn-toggle-history');
    const railList = $('rail-list');
    // Restore prior open/closed state.
    let stored = 'open';
    try { stored = localStorage.getItem(RAIL_KEY) || 'open'; } catch {}
    document.body.setAttribute('data-rail', stored === 'closed' ? 'closed' : 'open');
    if (btn) {
        btn.classList.toggle('active', stored !== 'closed');
        btn.addEventListener('click', () => {
            const cur = document.body.getAttribute('data-rail') === 'closed' ? 'closed' : 'open';
            const next = cur === 'closed' ? 'open' : 'closed';
            document.body.setAttribute('data-rail', next);
            btn.classList.toggle('active', next === 'open');
            try { localStorage.setItem(RAIL_KEY, next); } catch {}
        });
    }
    if (railList) {
        railList.addEventListener('click', (e) => {
            const delBtn = e.target.closest('[data-del-id]');
            if (delBtn) {
                e.stopPropagation();
                const id = delBtn.getAttribute('data-del-id');
                if (window.confirm('Delete this saved chat?')) deleteConversation(id);
                return;
            }
            const item = e.target.closest('[data-conv-id]');
            if (item) loadConversation(item.getAttribute('data-conv-id'));
        });
        railList.addEventListener('keydown', (e) => {
            if (e.key !== 'Enter' && e.key !== ' ') return;
            const item = e.target.closest('[data-conv-id]');
            if (!item) return;
            e.preventDefault();
            loadConversation(item.getAttribute('data-conv-id'));
        });
    }
}

// Returns true iff the message was handled as a slash command.
function maybeRunSlashCommand(message) {
    const trimmed = message.trim();
    if (!trimmed.startsWith('/')) return false;
    const cmd = trimmed.split(/\s+/)[0].toLowerCase();
    const entry = SLASH_COMMANDS[cmd];
    if (!entry) {
        appendSystemCard(`<div class="system-card-head">unknown command</div><p>No slash command named <code>${escapeHtml(cmd)}</code>. Type <code class="kbd">/help</code> for the list.</p>`);
        return true;
    }
    Promise.resolve().then(() => entry.run(trimmed)).catch(e => appendSystemCard(`<div class="system-card-head">error</div><p>${escapeHtml(e.message || String(e))}</p>`));
    return true;
}

(async () => {
    if (isViaInterop()) {
        const bridge = await fetchBridgeAuth();
        if (bridge.bearer) bridgeBearer = bridge.bearer;
        if (bridge.namespace) bridgeNamespace = bridge.namespace;
        else if (urlNamespace()) bridgeNamespace = urlNamespace();
    } else if (urlNamespace()) {
        bridgeNamespace = urlNamespace();
    }
    try { await bootstrapAuth(); } catch (e) { toast(e.message, 'error'); return; }
    // Show the USER'S working namespace, not the dispatch's $namespace
    // (which is always HSCUSTOM — the install namespace). The chat
    // sends X-IRIS-Namespace: bridgeNamespace so the gate + per-tool
    // switching ALWAYS operate on the user's namespace; the pill
    // should mirror that. Only fall back to /namespace if no bridge
    // value was provided (standalone use, no parent SPA, no URL hint).
    if (bridgeNamespace) {
        setNamespacePill(bridgeNamespace);
    } else {
        try {
            const r = await fetch(API + '/namespace', { headers: { Authorization: authHeader() } });
            const j = await r.json();
            setNamespacePill(j.namespace || '');
        } catch {
            setNamespacePill('');
        }
    }
    // Resolve the default LLM connection up-front so the pill shows
    // the active connection name from page load, not after the first
    // chat reply.
    resolveDefaultConnection();
    // Paint the empty state — 6 example chips + a /examples hint.
    // index.html ships an empty <div id="empty-state"></div>; the
    // tiles + intro copy live in JS so EXAMPLES is the single source
    // of truth.
    renderEmptyState();
    // Pre-build the slash-command autocomplete menu so it's ready
    // the instant the user types "/".
    buildSlashMenu();
    // Wire the history rail (toggle button + click delegation) and
    // paint the saved-conversations list. Past chats are localStorage-
    // scoped to this browser; the audit trail still captures every
    // turn server-side via HealthInterop.Data.Conversation.
    setupHistoryRail();
    renderRail();
    $('input').focus();
})();
