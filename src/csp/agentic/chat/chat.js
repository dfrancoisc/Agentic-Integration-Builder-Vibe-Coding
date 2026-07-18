// agentic_interop chat — Phase 3 streaming. POSTs to
// /api/agentic/chat/stream and consumes a text/event-stream of token,
// tool_start, tool_result, tool_error, status, done, error events.
// Auth pattern matches the admin SPA: try the parent SPA's bridge
// bearer (postMessage), then localStorage Basic, fall back to an
// inline overlay if both miss.

const API = '/api/agentic';
const AUTH_KEY = 'AGENTIC_AUTH';

// Observer integration — BroadcastChannel tells any open Observer tab
// which session to connect to BEFORE the chat request fires, so the
// Observer sees every event in real-time (not replayed after the fact).
const observerChannel = (function () {
    try { return new BroadcastChannel('agentic-observer'); } catch { return null; }
})();

// [CSP cookie fix] Force credentials:'omit' on every fetch from this
// iframe. Without this, the browser's default credentials:'same-origin'
// sends the Interop Editor's CSPSESSIONID cookie with every request to
// /api/agentic/. The CSP gateway sees the stale session cookie, tries
// to validate it, FAILS, and returns 401 before ever reading the
// Authorization header we send. This caused "Your session has expired"
// on every second chat turn — the first SSE response's Set-Cookie
// poisoned all subsequent requests.
{
    const _fetch = window.fetch.bind(window);
    window.fetch = (url, opts) => _fetch(url, Object.assign({}, opts, { credentials: 'omit' }));
}

let bridgeBearer = '';
let bridgeNamespace = '';
let authValidated = false;
let pending = false;
// Conversation transcript — replayed on every turn (the backend is
// stateless across turns; see ChatService.cls comment). "New chat"
// resets this to empty.
const history = [];
// Legacy: approval tokens for the per-tool confirmation gate (now
// disabled — the agent uses conversational approval instead). Kept
// for API compatibility; the array is always empty.
let approvedTokens = [];

// Composer attachments: queued in the composer (chips visible), sent on the
// next submit, then cleared. Server-side AttachmentExtractor handles the
// same whitelist (pdf / xlsx / txt / md). 10 MB per file is a defensive
// client cap — the gateway's no-cache + the CSP multipart limit handle
// the rest.
let pendingAttachments = [];
const ATTACH_EXTS = ['.pdf', '.xlsx', '.xlsm', '.txt', '.md', '.markdown'];
const ATTACH_MAX_BYTES = 10 * 1024 * 1024;
function attachExtOK(name) {
    const lower = String(name || '').toLowerCase();
    return ATTACH_EXTS.some(e => lower.endsWith(e));
}
function formatBytes(n) {
    if (n < 1024) return n + ' B';
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
    return (n / 1048576).toFixed(1) + ' MB';
}

// Curated example prompts. The empty-state shows the first 6;
// `/examples` shows the full set. Each entry is { cat, title, prompt };
// `cat` is a short uppercase category label (BUILD / TRANSFORM /
// OPERATE / etc.) shown in tiny accent text above the title — gives
// the user a fast visual scan of what kind of work the prompt is.
//
// User-defined examples are stored in localStorage under
// AGENTIC_USER_EXAMPLES and merged after the built-in set.
const USER_EXAMPLES_KEY = 'AGENTIC_USER_EXAMPLES';
function loadUserExamples() {
    try { return JSON.parse(localStorage.getItem(USER_EXAMPLES_KEY) || '[]'); }
    catch { return []; }
}
function saveUserExamples(arr) {
    try { localStorage.setItem(USER_EXAMPLES_KEY, JSON.stringify(arr)); } catch {}
}
const BUILTIN_EXAMPLES = [
    {
        cat: 'BUILD',
        title: "ADT-to-ORU transformation with file output",
        prompt: "Build me a complete production called ADT.ToORU.FileProduction that does the following:\n\n" +
            "**Inbound**\n" +
            "Pick up HL7 v2.5 ADT^A01 admission messages from the folder /tmp/hl7-in/. The Business Service should watch that directory, process each .hl7 file it finds, and move the original file to an archive subfolder after processing. Use the 2.5 schema category for parsing. Generate an application accept (AA) acknowledgment for every message that parses successfully, and an application reject (AR) for anything that fails schema validation.\n\n" +
            "Use this message to test:\n\n" +
            "MSH|^~\\&|EPIC|MAIN-HOSP|LIS|LAB-SYS|20260522143027||ADT^A01^ADT_A01|MSG-20260522-00471|P|2.5|||AL|NE|USA|ASCII|en^English^ISO639\n" +
            "EVN|A01|20260522142800|20260522143000||ADMIN^Richardson^Nancy^M^^RN|20260522142500\n" +
            "PID|1||MRN-88402^^^MAIN-HOSP^MR~SSN-321654987^^^SSA^SS||Nakamura^Kenji^Takeshi^^^^L~Nakamura^Ken^^^^A||19870314|M|||2200 Coral Way^^Miami^FL^33145^USA^H~PO Box 9012^^Miami^FL^33101^USA^M||^PRN^PH^^1^305^5559012~^PRN^CP^^1^786^5553344|^WPN^PH^^1^305^5558800|en^English^ISO639|M|BUD||SSN-321654987|||N^Non-Hispanic^HL70189||N||||||N\n" +
            "PD1|||MAIN CAMPUS^^12345|ATTEND-4401^Reeves^Samantha^L^Dr.^MD^L\n" +
            "NK1|1|Nakamura^Yuki^M^^^^L|SPO^Spouse^HL70063|2200 Coral Way^^Miami^FL^33145^USA^H|^PRN^PH^^1^305^5559013||EC^Emergency Contact^HL70131\n" +
            "NK1|2|Nakamura^Hiroshi^^^^^L|FTH^Father^HL70063|445 Biscayne Blvd^^Miami^FL^33132^USA^H|^PRN^PH^^1^305^5551234||NK^Next of Kin^HL70131\n" +
            "PV1|1|I|4-EAST^4E-201^A^MAIN-HOSP^^^^4TH FLOOR EAST||||ATTEND-4401^Reeves^Samantha^L^Dr.^MD^L|REFER-7702^Patel^Ravi^K^Dr.^MD^L|CONSULT-3309^Johannsen^Erik^^Dr.^DO^L|MED||||7|ADM-0042^Williams^Tara^R^^NP^L||VN-660234^^^MAIN-HOSP^VN|SELF|||||||||||||||||||ADMIT||ACTIVE|||20260522142800\n" +
            "PV2|||^Chest pain with shortness of breath||||||20260523|1||||||||||||N\n" +
            "AL1|1|DA^Drug Allergy^HL70127|PENICILLIN^Penicillin^NDC|MO^Moderate^HL70128|Hives and rash|20190615\n" +
            "AL1|2|FA^Food Allergy^HL70127|SHELLFISH^Shellfish^LOCAL|SV^Severe^HL70128|Anaphylaxis|20150301\n" +
            "DG1|1|ICD10|R07.9^Chest pain, unspecified^ICD10||20260522142800|A\n" +
            "DG1|2|ICD10|R06.0^Dyspnea^ICD10||20260522142800|A\n" +
            "IN1|1|BCBS-FL-PPO^^BCBS|BCBS-FL-001|Blue Cross Blue Shield of Florida|PO Box 1798^^Jacksonville^FL^32231^USA|^PRN^PH^^1^800^5551234||GRP-MH-40021||||20260101|20261231||COM^Commercial^HL70086|Nakamura^Kenji^T^^^^L|SEL^Self^HL70063|19870314|2200 Coral Way^^Miami^FL^33145^USA^H|||1||||||||||||||ACT-44021\n" +
            "GT1|1||Nakamura^Kenji^Takeshi^^^^L||2200 Coral Way^^Miami^FL^33145^USA^H|^PRN^PH^^1^305^5559012||19870314|M||SEL^Self^HL70063\n\n" +
            "This message has values in every field the transformation touches, plus extra segments (NK1, AL1, DG1, IN1, GT1) that should NOT appear in the output ORU — if any of those leak through, the DTL is copying too much.\n\n" +
            "**Transformation — ADT^A01 to ORU^R01**\n" +
            "Create a DTL called ADT.ToORU.Transform that converts each ADT^A01 into an ORU^R01 observation report. The mapping rules are:\n\n" +
            "- Copy MSH from source to target, but change MSH:9 (MessageType) to ORU^R01 and set MSH:12 (VersionID) to 2.5\n" +
            "- Map PID:3 (PatientIdentifierList) into OBR:3 (FillerOrderNumber) — take the first repetition's ID value\n" +
            "- Map PV1:7 (AttendingDoctor) into OBR:16 (OrderingProvider) — carry all components (ID, family name, given name, suffix, prefix, degree)\n" +
            "- Create one OBX segment:\n" +
            "  - OBX:1 (SetID) = 1\n" +
            "  - OBX:2 (ValueType) = ST (string)\n" +
            "  - OBX:3 (ObservationIdentifier) = PATNAME^Patient Name^L\n" +
            "  - OBX:5 (ObservationValue) = the full patient name from PID:5 (concatenate family name, given name, and middle name separated by spaces)\n" +
            "  - OBX:11 (ObservationResultStatus) = F (final)\n" +
            "- Copy PID as-is into the ORU's PID (so the patient demographics travel with the report)\n" +
            "- Set OBR:4 (UniversalServiceIdentifier) to ADT-OBS^Admission Observation^L\n" +
            "- Set OBR:7 (ObservationDateTime) to the value from EVN:2 (RecordedDateTime) if it exists, otherwise use the current timestamp\n\n" +
            "Compile the DTL after creating it.\n\n" +
            "**Routing**\n" +
            "Add a routing engine Business Process called ADT.ToORU.Router. Create a compiled business rule called ADT.ToORU.RoutingRule with these conditions:\n\n" +
            "1. Rule 1 — \"Route ORU to outbound\": If the message type (MSH:9.1) equals ORU and the message event (MSH:9.2) equals R01, send to the outbound file operation (see below). This is the normal path after successful transformation.\n" +
            "2. Rule 2 — \"Dead letter\": This is the default/otherwise rule — any message that does not match Rule 1 (including messages that failed transformation or arrived with an unexpected type) gets sent to the dead-letter file operation.\n\n" +
            "The routing engine should apply the transformation ADT.ToORU.Transform before evaluating routing rules, so the inbound ADT arrives, gets transformed to ORU, and then the rules decide where the ORU goes.\n\n" +
            "**Outbound**\n" +
            "Create a file-based Business Operation called ADT.ToORU.FileOut that writes each ORU^R01 message to the folder /tmp/hl7-out/. Use the filename pattern ORU_%Y%m%d%H%M%S_%MessageID%.hl7 so each file is unique. Overwrite mode off.\n\n" +
            "**Dead Letter**\n" +
            "Create a second file-based Business Operation called ADT.ToORU.DeadLetter that writes failed or unroutable messages to /tmp/dead-letter/. Use the filename pattern DL_%Y%m%d%H%M%S_%MessageID%.hl7.\n\n" +
            "**Final Steps**\n" +
            "After everything is created and compiled:\n\n" +
            "1. Start the production with all five hosts enabled\n" +
            "2. Send the ADT^A01 test message above through the inbound path to verify end-to-end flow\n" +
            "3. Validate that the ORU^R01 appeared in /tmp/hl7-out/, that the OBR:3 filler order number matches the original PID:3, and that the OBX:5 contains the patient name\n" +
            "4. Check the Event Log for any errors or warnings\n" +
            "5. Give me a summary of what was built, what was tested, and whether it all passed"
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
// Merged list: built-in + user-defined. Rebuilt on add/remove.
let EXAMPLES = BUILTIN_EXAMPLES.concat(loadUserExamples());
function rebuildExamples() { EXAMPLES = BUILTIN_EXAMPLES.concat(loadUserExamples()); }

// Slash commands. Each runs a side-channel action (no LLM call) and
// renders a synthetic message into the chat. `/help` lists them all.
const SLASH_COMMANDS = {
    '/examples': { desc: 'Show all suggested prompts.', run: cmdExamples },
    '/example':  { desc: 'Alias for /examples.',         run: cmdExamples },
    '/addexample':{ desc: 'Add a custom prompt to /examples.', run: cmdAddExample },
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
        '<p class="hero-eyebrow">' + escapeHtml(CHATBOT_TITLE || 'Agentic Interoperability Builder') + ' &middot; Copilot</p>' +
        '<h1 class="hero-title">How can I help?</h1>' +
        '<p class="hero-sub">Describe your interoperability goal in plain English &mdash; or pick a starter below. ' +
        'The agent reaches into IRIS for Health to read productions, validate messages, and build integrations. ' +
        'It presents a plan before making changes and waits for your go-ahead.</p>' +
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
function urlChatbot() {
    try { return new URLSearchParams(window.location.search).get('chatbot') || ''; }
    catch { return ''; }
}
function urlTitle() {
    try { return new URLSearchParams(window.location.search).get('title') || ''; }
    catch { return ''; }
}
// Which chatbot this surface is. The backend maps this key to an %AI.Agent
// (Chatbot config layer); empty falls back to the default agent.
const CHATBOT = urlChatbot();
const CHATBOT_TITLE = urlTitle();

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
            '<div style="font-weight:600;font-size:14px;">Sign in to the Agentic Interoperability Builder</div>' +
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
    // 1. Try existing bridge bearer
    if (bridgeBearer && await probeAuth(bridgeBearer)) { authValidated = true; return; }
    bridgeBearer = '';
    // 2. Trust stored Basic auth without re-probing (transient 401s
    //    from the CSP gateway would cause a false negative)
    const stored = getStoredAuth();
    if (stored) { authValidated = true; return; }
    // 3. Re-fetch bridge bearer from parent SPA — the old one expired
    //    but the parent may have a fresh JWT. This is the critical path
    //    for users who opened the chatbot via the Interop Editor and
    //    never manually logged in (no stored Basic auth).
    if (isViaInterop()) {
        const bridge = await fetchBridgeAuth();
        if (bridge.bearer) {
            bridgeBearer = bridge.bearer;
            if (await probeAuth(bridgeBearer)) { authValidated = true; return; }
            bridgeBearer = '';
        }
    }
    // 4. Nothing worked.
    //    Bridge users (via Interop Editor) should NEVER see a login
    //    form — they authenticated in the parent SPA. If the parent
    //    session expired, a manual login creates conflicting
    //    credentials. Show an inline error instead.
    if (isViaInterop()) {
        authValidated = true;  // suppress further bootstrap attempts
        return;                // caller detects auth failure via 401
    }
    // Standalone users (direct URL, no parent SPA) get the login form
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
//
// Layout:
//   [role label]
//   [tool-group — single collapsible "N actions" summary]
//     [individual tool cards inside, only visible when expanded]
//   [text — the assistant's response]
//   [meta — friendly completion line + collapsible technical details]
function newAssistantBubble() {
    const empty = $('empty-state');
    if (empty) empty.remove();
    const wrap = document.createElement('div');
    wrap.className = 'message assistant';
    const role = document.createElement('span');
    role.className = 'role';
    role.textContent = 'health interop';
    wrap.appendChild(role);
    // Tool group: a single <details> that wraps all tool cards.
    // The summary line ("N actions completed") updates as cards arrive.
    // Individual tool cards are hidden inside until the user clicks.
    const toolGroup = document.createElement('details');
    toolGroup.className = 'tool-group';
    toolGroup.hidden = true;
    const toolSummary = document.createElement('summary');
    toolSummary.className = 'tool-group-summary';
    const toolDot = document.createElement('span');
    toolDot.className = 'status-dot running';
    toolSummary.appendChild(toolDot);
    const toolLabel = document.createElement('span');
    toolLabel.className = 'tool-group-label';
    toolLabel.textContent = 'Working...';
    toolSummary.appendChild(toolLabel);
    toolGroup.appendChild(toolSummary);
    const tools = document.createElement('div');
    tools.className = 'tool-stack';
    toolGroup.appendChild(tools);
    wrap.appendChild(toolGroup);
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
    return { wrap, toolGroup, toolSummary, toolDot, toolLabel, tools, text, cursor, meta };
}

// Post-process a streamed text div: convert markdown-style formatting
// to real HTML. Runs once after the stream finishes so it doesn't slow
// down token rendering. Handles: **bold**, *italic*, `code`, headings
// (## / ###), bullet lists (- item / * item), and numbered lists.
function formatBubbleText(textDiv) {
    const raw = textDiv.textContent || '';
    if (!raw.trim()) return;
    // Collapse runs of 3+ blank lines down to one paragraph gap
    const lines = raw.split('\n');
    const parts = [];
    let inList = false;
    let listType = '';
    let lastWasBreak = false;
    // Track how many numbered items we've emitted so that when sub-bullets
    // or blank lines interrupt a numbered list and we have to close/reopen
    // the <ol>, we use start="N" to continue the numbering. Reset on
    // headings or regular paragraphs (= a new logical section).
    let olCounter = 0;

    for (let i = 0; i < lines.length; i++) {
        let line = lines[i];

        // Headings: ## or ### at start of line
        if (/^###\s+(.+)/.test(line)) {
            if (inList) { parts.push(listType === 'ul' ? '</ul>' : '</ol>'); inList = false; }
            olCounter = 0;
            parts.push('<h4 class="chat-h">' + fmtInline(line.replace(/^###\s+/, '')) + '</h4>');
            lastWasBreak = false;
            continue;
        }
        if (/^##\s+(.+)/.test(line)) {
            if (inList) { parts.push(listType === 'ul' ? '</ul>' : '</ol>'); inList = false; }
            olCounter = 0;
            parts.push('<h3 class="chat-h">' + fmtInline(line.replace(/^##\s+/, '')) + '</h3>');
            lastWasBreak = false;
            continue;
        }

        // Bullet list: - item or * item (but not **bold**)
        if (/^\s*[-*]\s+(.+)/.test(line) && !/^\s*\*\*/.test(line)) {
            if (!inList || listType !== 'ul') {
                if (inList) parts.push(listType === 'ul' ? '</ul>' : '</ol>');
                parts.push('<ul class="chat-list">');
                inList = true; listType = 'ul';
            }
            parts.push('<li>' + fmtInline(line.replace(/^\s*[-*]\s+/, '')) + '</li>');
            lastWasBreak = false;
            continue;
        }

        // Numbered list: 1. item — uses olCounter + start attr so that
        // sub-bullets between items don't reset to "1."
        if (/^\s*\d+\.\s+(.+)/.test(line)) {
            olCounter++;
            if (!inList || listType !== 'ol') {
                if (inList) parts.push(listType === 'ul' ? '</ul>' : '</ol>');
                parts.push('<ol class="chat-list" start="' + olCounter + '">');
                inList = true; listType = 'ol';
            }
            parts.push('<li>' + fmtInline(line.replace(/^\s*\d+\.\s+/, '')) + '</li>');
            lastWasBreak = false;
            continue;
        }

        // Empty line — close list, emit at most one paragraph gap
        if (line.trim() === '') {
            if (inList) { parts.push(listType === 'ul' ? '</ul>' : '</ol>'); inList = false; }
            if (!lastWasBreak) { parts.push('<div class="chat-gap"></div>'); lastWasBreak = true; }
            continue;
        }

        // Regular line with inline formatting — resets numbered-list counter
        olCounter = 0;
        lastWasBreak = false;
        parts.push('<p class="chat-p">' + fmtInline(line) + '</p>');
    }

    if (inList) parts.push(listType === 'ul' ? '</ul>' : '</ol>');

    // Join without newlines — the CSS controls spacing, not whitespace.
    // The .text div switches to white-space:normal once formatted.
    textDiv.innerHTML = parts.join('');
    textDiv.classList.add('formatted');
}

// Inline formatting: **bold**, *italic*, `code`, and bare class names
function fmtInline(text) {
    // Escape HTML first
    let s = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    // `code` spans
    s = s.replace(/`([^`]+)`/g, '<code class="chat-code">$1</code>');
    // **bold**
    s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    // *italic* (but not inside already-processed tags)
    s = s.replace(/(?<!\w)\*([^*]+)\*(?!\w)/g, '<em>$1</em>');
    return s;
}

function appendUserMessage(content, attachments) {
    const empty = $('empty-state');
    if (empty) empty.remove();
    const el = document.createElement('div');
    el.className = 'message user';
    const role = document.createElement('span');
    role.className = 'role';
    role.textContent = 'you';
    el.appendChild(role);
    // Show a small "Attached:" line above the message text so the user
    // sees in the transcript that they sent files. The actual file
    // contents are not shown here — the agent's reply will quote them.
    if (attachments && attachments.length) {
        const names = Array.prototype.map.call(attachments, function (f) { return f.name; }).join(', ');
        const att = document.createElement('div');
        att.className = 'user-attachments';
        att.textContent = 'Attached: ' + names;
        el.appendChild(att);
    }
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

// Human-readable tool name: "CreateProduction" → "Create Production",
// "UpdateDTL" → "Update DTL", "ValidateHL7Structure" → "Validate HL7 Structure"
function readableToolName(name) {
    return (name || '')
        .replace(/([a-z])([A-Z])/g, '$1 $2')
        .replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2')
        .replace(/([0-9])([A-Z])/g, '$1 $2');
}

// Flatten a nested object into key: value lines for display.
// Nested objects get dot-separated keys. Long strings (>200 chars)
// show a length summary. Arrays show as comma-separated values.
function flattenArgs(obj, prefix, lines) {
    if (!obj || typeof obj !== 'object') return;
    const entries = Array.isArray(obj) ? obj.map((v, i) => [i, v]) : Object.entries(obj);
    for (const [k, v] of entries) {
        const key = prefix ? prefix + '.' + k : String(k);
        if (v === null || v === undefined) continue;
        if (Array.isArray(v)) {
            lines.push(key + ': ' + v.join(', '));
        } else if (typeof v === 'object') {
            flattenArgs(v, key, lines);
        } else if (typeof v === 'string' && v.length > 200) {
            lines.push(key + ': (' + v.length + ' chars)');
        } else {
            lines.push(key + ': ' + v);
        }
    }
}

// Format tool arguments as human-readable text instead of raw JSON.
function formatToolArgs(args) {
    if (!args || typeof args !== 'object') return String(args || '');
    const lines = [];
    flattenArgs(args, '', lines);
    return lines.join('\n');
}

// Format tool result for display — try to make it readable.
function formatToolResult(result) {
    if (result === null || result === undefined) return '';
    if (typeof result === 'string') {
        // Try parsing as JSON for readable display
        if (result.length > 0 && (result[0] === '{' || result[0] === '[')) {
            try {
                const obj = JSON.parse(result);
                const lines = [];
                flattenArgs(obj, '', lines);
                return lines.join('\n') || result;
            } catch { return result; }
        }
        return result;
    }
    if (typeof result === 'object') {
        const lines = [];
        flattenArgs(result, '', lines);
        return lines.join('\n');
    }
    return String(result);
}

// Tool-call card. Status starts at "running"; transitions to ok/error
// when the matching tool_result/tool_error event arrives. No icons,
// no emojis — colored dot + uppercase text label only, per the
// InterSystems internal style preference. Tool name is displayed in
// readable form; args and results are formatted as plain key:value
// pairs, not JSON.
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
    label.textContent = readableToolName(name);
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

// Live progress bar for a background FHIR directory load. LoadFHIRDirectory
// returns a jobId + totalFiles and runs the load in a background job; we poll
// /fhir/load/status until the job reaches a terminal state (completed|error)
// and animate the bar. This is decoupled from the chat turn, so large loads
// (minutes) are not bound by the turn deadline.
const fhirLoadBars = new Set();
function startFhirLoadProgress(bubble, result) {
    const jobId = result.jobId;
    if (!jobId || fhirLoadBars.has(jobId)) return;
    fhirLoadBars.add(jobId);
    const total0 = Number(result.totalFiles || result.total || 0);
    const dest = result.url || 'the FHIR server';

    const box = document.createElement('div');
    box.className = 'fhir-load';
    const head = document.createElement('div');
    head.className = 'fhir-load-head';
    head.textContent = 'Loading FHIR data into ' + dest;
    box.appendChild(head);
    const track = document.createElement('div');
    track.className = 'fhir-load-track';
    const fill = document.createElement('div');
    fill.className = 'fhir-load-fill';
    fill.style.width = '0%';
    track.appendChild(fill);
    box.appendChild(track);
    const count = document.createElement('div');
    count.className = 'fhir-load-count';
    count.textContent = total0 ? ('0 of ' + total0 + ' files') : 'Starting...';
    box.appendChild(count);

    // Place the bar above the assistant's completion text.
    bubble.wrap.insertBefore(box, bubble.text);
    $('messages').scrollTop = $('messages').scrollHeight;

    let fails = 0;
    const startedAt = Date.now();
    const MAX_MS = 60 * 60 * 1000; // hard stop after 1h
    function finish(state, msg) {
        box.classList.add(state === 'error' ? 'is-error' : 'is-done');
        if (state !== 'error') fill.style.width = '100%';
        count.textContent = msg;
    }
    async function poll() {
        if (Date.now() - startedAt > MAX_MS) { finish('error', 'Stopped tracking after 1 hour.'); return; }
        let d;
        try {
            const r = await fetch(API + '/fhir/load/status?jobId=' + encodeURIComponent(jobId), { headers: { Authorization: authHeader() }, cache: 'no-store' });
            if (!r.ok) throw new Error('HTTP ' + r.status);
            d = await r.json();
            fails = 0;
        } catch (e) {
            fails++;
            if (fails >= 8) { finish('error', 'Lost connection to the load job.'); return; }
            setTimeout(poll, 2000);
            return;
        }
        const tot = Number(d.total || total0 || 0);
        const done = Number(d.done != null ? d.done : ((d.filesDone || 0) + (d.filesFailed || 0)));
        const pct = d.percent != null ? Number(d.percent) : (tot ? Math.round(done / tot * 100) : 0);
        fill.style.width = Math.max(0, Math.min(100, pct)) + '%';
        const failedTxt = d.filesFailed ? (', ' + d.filesFailed + ' failed') : '';
        const st = String(d.status || '').toLowerCase();
        if (st === 'completed' || st === 'done') {
            finish('done', 'Loaded ' + (d.filesDone != null ? d.filesDone : done) + ' of ' + tot + ' files' + failedTxt + '.');
            return;
        }
        if (st === 'error') {
            finish('error', 'Load failed' + failedTxt + (d.error ? ': ' + d.error : '') + ' (' + done + ' of ' + tot + ' done).');
            return;
        }
        // queued / running
        let line = done + ' of ' + tot + ' files' + failedTxt;
        if (d.current) { line += ' — ' + String(d.current).slice(0, 48); }
        count.textContent = line;
        setTimeout(poll, 1500);
    }
    poll();
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

async function send(message, attachments) {
    if (pending) return;
    pending = true;
    $('btn-send').disabled = true;
    $('input').disabled = true;
    const hasAttachments = !!(attachments && attachments.length);
    appendUserMessage(message, attachments);
    const bubble = newAssistantBubble();
    const toolCardsByName = new Map();
    let assistantText = '';
    try {
        // Send the active namespace as X-IRIS-Namespace so the
        // Dispatch.OnPreDispatch gate fires. If the user has no
        // permission for that namespace, the gate refuses with 403
        // BEFORE the chat method runs.
        // When attachments are present we send multipart/form-data and the
        // browser MUST be the one to set the Content-Type header (so it
        // includes the multipart boundary). Do not set it ourselves.
        const headers = { 'Authorization': authHeader() };
        if (!hasAttachments) headers['Content-Type'] = 'application/json';
        if (bridgeNamespace) headers['X-IRIS-Namespace'] = bridgeNamespace;
        // Pull the approved tokens captured since the last send and
        // clear the queue — they apply to THIS turn only.
        const tokensThisTurn = approvedTokens.slice();
        approvedTokens = [];
        // Cache-bust: append a unique ?_t= so the browser opens a fresh
        // TCP connection instead of reusing the keep-alive socket from the
        // previous SSE stream. The CSP gateway maintains connection-level
        // auth state that becomes stale after a long SSE response closes,
        // causing 401 on the next request over the same socket.
        // Generate observer session ID and broadcast it to any open
        // Observer tab BEFORE the fetch. The Observer connects to the
        // stream for this ID immediately, so it sees every event live
        // — including session_start, provider resolution, MCP/skill
        // loading — instead of replaying them after the fact.
        const observerId = crypto.randomUUID();
        if (observerChannel) {
            try { observerChannel.postMessage({ type: 'session', id: observerId }); } catch {}
        }
        // Build a fresh body each retry — FormData (when attachments) is a
        // one-shot stream, so it must be reconstructed each time fetch
        // consumes one. The JSON path is also rebuilt for consistency.
        const payload = { message, history, approvedTokens: tokensThisTurn, observerId, chatbot: CHATBOT };
        const bodyMaker = () => {
            if (hasAttachments) {
                const fd = new FormData();
                fd.append('body', JSON.stringify(payload));
                for (let i = 0; i < attachments.length; i++) {
                    fd.append('files', attachments[i], attachments[i].name);
                }
                return fd;
            }
            return JSON.stringify(payload);
        };
        const streamUrl = API + '/chat/stream?_t=' + Date.now();
        let res = await fetch(streamUrl, {
            method: 'POST',
            headers,
            body: bodyMaker()
        });
        // 401 recovery: the CSP session or bridge bearer expired.
        // Try increasingly aggressive recovery before showing the
        // login modal. The user must NEVER see a sign-in prompt for
        // a transient auth failure during an active conversation.
        if (res.status === 401) {
            // Retry 1: re-send same auth on a brand new URL (forces new
            // TCP socket, bypasses any stale gateway connection state)
            headers['Authorization'] = authHeader();
            res = await fetch(API + '/chat/stream?_t=' + Date.now(), {
                method: 'POST', headers,
                body: bodyMaker()
            });
        }
        if (res.status === 401) {
            // Retry 2: re-fetch bridge bearer from parent SPA
            if (isViaInterop()) {
                const bridge = await fetchBridgeAuth();
                if (bridge.bearer) {
                    bridgeBearer = bridge.bearer;
                    headers['Authorization'] = bridgeBearer;
                    res = await fetch(API + '/chat/stream?_t=' + Date.now(), {
                        method: 'POST', headers,
                        body: bodyMaker()
                    });
                }
            }
        }
        if (res.status === 401) {
            // Retry 3: try stored Basic auth with a /whoami warmup
            const stored = getStoredAuth();
            if (stored) {
                await fetch(API + '/whoami?_t=' + Date.now(), {
                    headers: { Authorization: stored }, cache: 'no-store'
                });
                headers['Authorization'] = stored;
                res = await fetch(API + '/chat/stream?_t=' + Date.now(), {
                    method: 'POST', headers,
                    body: bodyMaker()
                });
            }
        }
        if (res.status === 401) {
            // All silent retries exhausted.
            if (isViaInterop()) {
                // Bridge users: NEVER show a login modal — the parent
                // SPA owns auth. Tell the user to refresh that page.
                // Include token age info if available from the bridge.
                let detail = '';
                try {
                    const ba = await fetchBridgeAuth();
                    if (ba.tokenSecondsLeft !== undefined && ba.tokenSecondsLeft < 0) {
                        detail = ' The authentication token expired ' + Math.abs(Math.floor(ba.tokenSecondsLeft)) + 's ago.';
                    }
                } catch {}
                throw new Error('Your session has expired.' + detail + ' Please close this panel, refresh the Interop Editor page (Ctrl+Shift+R or Cmd+Shift+R), and re-open the chatbot.');
            }
            // Standalone users: one last chance via the login form
            authValidated = false;
            await showLoginOverlay();
            authValidated = true;
            headers['Authorization'] = authHeader();
            res = await fetch(API + '/chat/stream?_t=' + Date.now(), {
                method: 'POST', headers,
                body: bodyMaker()
            });
        }
        if (res.status === 401) {
            authValidated = false;
            throw new Error('Authorization rejected. Please reload the page and sign in again.');
        }
        if (res.status === 403) {
            const j = await res.json().catch(() => ({}));
            throw new Error('Access denied to namespace ' + (j.namespace || '?') + '. Your IRIS user (' + (j.user || currentNs()) + ') does not have permission to operate in this namespace.');
        }
        if (res.status === 400) {
            const j = await res.json().catch(() => ({}));
            throw new Error((j.error || 'Bad request') + (j.namespace ? ': ' + j.namespace : ''));
        }
        if (!res.ok) {
            throw new Error('HTTP ' + res.status);
        }
        let toolCount = 0;
        let toolErrors = 0;
        for await (const { event, data } of readSSE(res)) {
            if (event === 'token' && data && typeof data.text === 'string') {
                assistantText += data.text;
                bubble.cursor.before(document.createTextNode(data.text));
                $('messages').scrollTop = $('messages').scrollHeight;
            } else if (event === 'tool_start' && data && data.name) {
                // Show the tool group as soon as the first tool fires
                bubble.toolGroup.hidden = false;
                toolCount++;
                bubble.toolLabel.textContent = toolCount === 1
                    ? '1 action running...'
                    : toolCount + ' actions running...';
                const card = newToolCard(bubble.tools, data.name);
                if (data.args) {
                    try {
                        const argsObj = typeof data.args === 'string' ? JSON.parse(data.args) : data.args;
                        card.argsBlock.textContent = formatToolArgs(argsObj);
                    } catch { card.argsBlock.textContent = String(data.args); }
                }
                toolCardsByName.set(data.name, card);
            } else if (event === 'tool_result' && data && data.name) {
                const card = toolCardsByName.get(data.name);
                if (card) {
                    setToolStatus(card, 'ok');
                    if (data.result !== undefined) {
                        card.resultBlock.textContent = formatToolResult(data.result);
                    }
                }
                // A FHIR directory load started -> show a live progress bar
                // that polls the background job until it finishes.
                try {
                    let rr = data.result;
                    if (typeof rr === 'string') { try { rr = JSON.parse(rr); } catch (e) { rr = null; } }
                    if (rr && rr.jobId && rr.ok && !rr.dryRun &&
                        (data.name === 'LoadFHIRDirectory' || rr.tool === 'load_fhir_directory')) {
                        startFhirLoadProgress(bubble, rr);
                    }
                } catch (e) {}
            } else if (event === 'tool_error' && data && data.name) {
                toolErrors++;
                const card = toolCardsByName.get(data.name);
                if (card) {
                    setToolStatus(card, 'error');
                    card.resultBlock.textContent = data.error || '(unknown error)';
                    card.card.open = true;
                }
            } else if (event === 'tool_confirm' && data && data.token) {
                bubble.toolGroup.hidden = false;
                newApprovalCard(bubble.tools, data);
            } else if (event === 'status' && data) {
                // Live progress updates — rate limit waits, phase changes, etc.
                if (data.message) {
                    bubble.toolGroup.hidden = false;
                    bubble.toolLabel.textContent = data.message;
                    bubble.toolDot.className = 'status-dot pending';
                    $('messages').scrollTop = $('messages').scrollHeight;
                }
            } else if (event === 'done' && data) {
                // Finalize the tool group summary
                if (toolCount > 0) {
                    bubble.toolDot.className = toolErrors > 0
                        ? 'status-dot error'
                        : 'status-dot ok';
                    const label = toolErrors > 0
                        ? toolCount + ' actions completed, ' + toolErrors + ' with errors'
                        : toolCount + (toolCount === 1 ? ' action' : ' actions') + ' completed';
                    bubble.toolLabel.textContent = label;
                }
                // Friendly completion line
                const secs = data.latencyMs ? (data.latencyMs / 1000).toFixed(1) : '?';
                const ns = data.namespace || '';
                let metaHtml = 'Completed in ' + secs + 's';
                if (ns) metaHtml += ' on ' + ns;
                // Technical details behind a collapsible toggle
                const details = [];
                if (data.connection) details.push(data.connection);
                if (data.model) {
                    // Shorten the model name: strip vendor prefix and version hash
                    const shortModel = (data.model || '').replace(/^global\.anthropic\./, '').replace(/-v\d+:\d+$/, '');
                    details.push(shortModel);
                }
                if (data.toolTrace) details.push(data.toolTrace);
                if (data.turnsReplayed > 0) details.push('replayed ' + data.turnsReplayed + ' prior turns');
                if (details.length > 0) {
                    metaHtml += ' <span class="meta-toggle" onclick="this.parentElement.querySelector(\'.meta-details\').hidden=!this.parentElement.querySelector(\'.meta-details\').hidden">(details)</span>';
                    metaHtml += '<span class="meta-details" hidden>' + details.join(' · ') + '</span>';
                }
                bubble.meta.innerHTML = metaHtml;
                bubble.meta.hidden = false;
                if (data.connection) updateConnectionPill(data.connection);
            } else if (event === 'error' && data) {
                throw new Error((data.error || 'Stream error') + (data.stage ? ' [stage: ' + data.stage + ']' : ''));
            }
        }
        bubble.cursor.remove();
        // Post-process: convert markdown-style formatting in the
        // streamed text into real HTML so the user sees proper bold,
        // headings, and bullets instead of raw asterisks.
        formatBubbleText(bubble.text);
        // Attachment workflow: if the assistant wrapped a Project
        // Specification in [[SPEC]] … [[/SPEC]] markers, replace those
        // markers with a structured card carrying Approve / Edit buttons.
        maybeRenderSpecCard(bubble, assistantText);
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

function ensureNsOption(ns) {
    const sel = $('ns-select');
    if (!sel || !ns) return;
    for (let i = 0; i < sel.options.length; i++) { if (sel.options[i].value === ns) return; }
    const o = document.createElement('option'); o.value = ns; o.textContent = ns; sel.appendChild(o);
}
// The namespace the chatbot is operating in (drives X-IRIS-Namespace).
function currentNs() {
    if (bridgeNamespace) return bridgeNamespace;
    const sel = $('ns-select');
    return (sel && sel.value) ? sel.value : '';
}
function setNamespacePill(ns) {
    const pill = $('ns-pill');
    const sel = $('ns-select');
    if (ns) {
        pill.classList.remove('unknown');
        if (sel) { ensureNsOption(ns); sel.value = ns; }
    } else {
        pill.classList.add('unknown');
    }
}
// Namespace picker — list the namespaces the user can access and let them
// choose which one the chatbot operates in. The choice persists per
// chatbot and is sent as X-IRIS-Namespace on every request. The server
// access-gates each namespace, so the picker only respects boundaries.
const NS_KEY = 'AGENTIC_NS_' + (CHATBOT || 'default');
async function loadNamespaces() {
    const sel = $('ns-select');
    if (!sel) return;
    let list = [], current = '', fhirOnly = false;
    try {
        const r = await fetch(API + '/namespaces' + (CHATBOT ? '?chatbot=' + encodeURIComponent(CHATBOT) : ''), { headers: { Authorization: authHeader() } });
        if (r.ok) { const j = await r.json(); list = j.namespaces || []; current = j.current || ''; fhirOnly = !!j.fhirOnly; }
    } catch (e) {}
    sel.innerHTML = '';
    if (!list.length) {
        // Empty list. For a FHIR-only picker this means no FHIR foundation
        // namespace exists — do NOT fall back to the dispatch namespace
        // (e.g. HSCUSTOM is not a FHIR namespace) or show a bogus "unknown".
        const o = document.createElement('option'); o.value = '';
        o.textContent = fhirOnly ? 'No FHIR server found' : 'unknown';
        o.disabled = true; sel.appendChild(o);
    }
    for (const ns of list) {
        const o = document.createElement('option'); o.value = ns; o.textContent = ns; sel.appendChild(o);
    }
    // Selection precedence: persisted choice > bridge/URL hint > dispatch.
    // For a FHIR-only picker, only select namespaces that are actually in the
    // FHIR list — never auto-select the dispatch namespace (HSCUSTOM).
    let want = '';
    try { want = localStorage.getItem(NS_KEY) || ''; } catch (e) {}
    if (want && list.length && list.indexOf(want) < 0) want = '';
    if (!want && bridgeNamespace && (!fhirOnly || list.indexOf(bridgeNamespace) >= 0)) want = bridgeNamespace;
    if (!want && (!fhirOnly || list.indexOf(current) >= 0)) want = current;
    if (!want && fhirOnly && list.length) want = list[0];
    if (want) { ensureNsOption(want); sel.value = want; bridgeNamespace = want; }
    setNamespacePill(bridgeNamespace);
    sel.addEventListener('change', () => {
        bridgeNamespace = sel.value || '';
        try { localStorage.setItem(NS_KEY, bridgeNamespace); } catch (e) {}
        setNamespacePill(bridgeNamespace);
    });
}

$('composer').addEventListener('submit', (e) => {
    e.preventDefault();
    const txt = $('input').value.trim();
    // Allow a turn with attachments and no message text (the agent will
    // synthesize a spec from the attachments alone).
    if (!txt && !pendingAttachments.length) return;
    $('input').value = '';
    hideSlashMenu();
    // Slash commands run side-channel — they must NOT round-trip
    // through send(), the LLM, or the conversation history. The
    // dispatcher below renders a synthetic system card and returns.
    // Slash commands ignore attachments by design.
    if (txt && maybeRunSlashCommand(txt)) return;
    const filesThisTurn = pendingAttachments.slice();
    pendingAttachments = [];
    renderAttachChips();
    send(txt, filesThisTurn);
});

// ---------- composer attachments: chips + picker + drag-drop ----------

function renderAttachChips() {
    const el = $('attach-chips');
    if (!el) return;
    if (!pendingAttachments.length) {
        el.innerHTML = '';
        el.hidden = true;
        return;
    }
    el.hidden = false;
    el.innerHTML = '';
    pendingAttachments.forEach((f, idx) => {
        const chip = document.createElement('span');
        chip.className = 'attach-chip';
        const name = document.createElement('span');
        name.className = 'attach-chip-name';
        name.textContent = f.name;
        const size = document.createElement('span');
        size.className = 'attach-chip-size';
        size.textContent = formatBytes(f.size);
        const x = document.createElement('button');
        x.type = 'button';
        x.className = 'attach-chip-x';
        x.textContent = '×';
        x.title = 'Remove';
        x.addEventListener('click', () => {
            pendingAttachments.splice(idx, 1);
            renderAttachChips();
        });
        chip.appendChild(name);
        chip.appendChild(size);
        chip.appendChild(x);
        el.appendChild(chip);
    });
}

function tryAddAttachment(file) {
    if (!file || !file.name) return false;
    if (!attachExtOK(file.name)) {
        toast('Unsupported: ' + file.name + ' — accept pdf, xlsx, txt, md.', 'err');
        return false;
    }
    if (file.size > ATTACH_MAX_BYTES) {
        toast(file.name + ' is ' + formatBytes(file.size) + ' — 10 MB per file maximum.', 'err');
        return false;
    }
    // Dedupe by name+size so the same file dropped twice doesn't double up.
    if (pendingAttachments.some(p => p.name === file.name && p.size === file.size)) {
        return false;
    }
    pendingAttachments.push(file);
    renderAttachChips();
    return true;
}

if ($('btn-attach')) {
    $('btn-attach').addEventListener('click', () => $('file-picker').click());
}
if ($('file-picker')) {
    $('file-picker').addEventListener('change', (e) => {
        const files = e.target.files;
        if (files) for (let i = 0; i < files.length; i++) tryAddAttachment(files[i]);
        e.target.value = ''; // allow re-selecting the same file later
    });
}

// Drag-and-drop on the composer shell and the messages area, so the user
// can drop a PDF anywhere in the chat panel and have it queue up as an
// attachment for the next message. drag-over class outlines the composer
// to confirm the drop target.
(function wireDropZones() {
    const targets = ['composer-shell', 'messages'].map(id => $(id)).filter(Boolean);
    const shell = $('composer-shell');
    let depth = 0;
    targets.forEach(el => {
        el.addEventListener('dragenter', (e) => {
            if (!e.dataTransfer || !e.dataTransfer.types) return;
            if (!Array.prototype.includes.call(e.dataTransfer.types, 'Files')) return;
            e.preventDefault();
            depth++;
            if (shell) shell.classList.add('drag-over');
        });
        el.addEventListener('dragover', (e) => {
            if (!e.dataTransfer || !e.dataTransfer.types) return;
            if (!Array.prototype.includes.call(e.dataTransfer.types, 'Files')) return;
            e.preventDefault();
        });
        el.addEventListener('dragleave', () => {
            depth = Math.max(0, depth - 1);
            if (depth === 0 && shell) shell.classList.remove('drag-over');
        });
        el.addEventListener('drop', (e) => {
            if (!e.dataTransfer || !e.dataTransfer.files || !e.dataTransfer.files.length) return;
            e.preventDefault();
            depth = 0;
            if (shell) shell.classList.remove('drag-over');
            for (let i = 0; i < e.dataTransfer.files.length; i++) {
                tryAddAttachment(e.dataTransfer.files[i]);
            }
        });
    });
})();

// Auto-grow: expand textarea height to fit content (up to CSS max-height),
// shrink back when text is removed. Also runs when a prompt is loaded
// from /examples. The user can still drag the resize handle to override.
// ---------- spec card (Project Specification with Approve / Edit) ----------
// The assistant wraps a synthesized Project Specification in
// [[SPEC]] … [[/SPEC]] markers (per its INSTRUCTIONS). After the streamed
// text has been markdown-formatted, scan the raw text for those markers and
// replace the marker pair in the bubble with a structured card carrying
// two actions:
//   Approve, build it -> sends "approve, build it" as the next user message.
//   Edit              -> loads the spec markdown into the composer input so
//                        the user can revise it inline and send the changes.
// The agent's prompt handles the rest.

function maybeRenderSpecCard(bubble, rawText) {
    if (!rawText || rawText.indexOf('[[SPEC]]') < 0) return;
    const re = /\[\[SPEC\]\]([\s\S]*?)\[\[\/SPEC\]\]/;
    const m = re.exec(rawText);
    if (!m) return;
    const specMarkdown = m[1].trim();
    const before = rawText.slice(0, m.index);
    const after = rawText.slice(m.index + m[0].length);
    // Rebuild the bubble: before-text + card + after-text. Each free-text
    // segment is markdown-rendered with the existing formatter so the rest
    // of the assistant response still looks correct.
    bubble.text.innerHTML = '';
    appendFormatted(bubble.text, before);
    bubble.text.appendChild(buildSpecCard(specMarkdown));
    appendFormatted(bubble.text, after);
}

function appendFormatted(parent, text) {
    if (!text || !text.trim()) return;
    const tmp = document.createElement('div');
    tmp.textContent = text;
    try { formatBubbleText(tmp); } catch (e) {}
    while (tmp.firstChild) parent.appendChild(tmp.firstChild);
}

function buildSpecCard(specMarkdown) {
    const card = document.createElement('div');
    card.className = 'spec-card';
    card.dataset.specMarkdown = specMarkdown;

    const head = document.createElement('div');
    head.className = 'spec-card-head';
    const label = document.createElement('span');
    label.className = 'label';
    label.textContent = 'Project Specification — draft';
    head.appendChild(label);
    card.appendChild(head);

    const body = document.createElement('div');
    body.className = 'spec-card-body';
    appendFormatted(body, specMarkdown);
    card.appendChild(body);

    const actions = document.createElement('div');
    actions.className = 'spec-card-actions';
    actions.appendChild(makeBtn('approve', 'Approve, build it', () => specApprove(card)));
    actions.appendChild(makeBtn('edit', 'Edit', () => specEdit(card)));
    card.appendChild(actions);
    return card;
}

function makeBtn(cls, text, onClick) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = cls;
    b.textContent = text;
    b.addEventListener('click', onClick);
    return b;
}

function specApprove(card) {
    card.querySelectorAll('button').forEach(b => b.disabled = true);
    $('input').value = 'approve, build it';
    $('composer').dispatchEvent(new Event('submit', { cancelable: true }));
}

function specEdit(card) {
    const specMarkdown = card.dataset.specMarkdown || '';
    // Load the spec back into the composer so the user can revise inline and
    // hit Send. We wrap it with a short instruction so the agent treats the
    // result as the new authoritative spec text rather than free-form text.
    $('input').value =
        'Revise the Project Specification to match the text below exactly, then re-emit it inside [[SPEC]] markers so I can review:\n\n' +
        specMarkdown;
    $('input').focus();
    try { autoGrow($('input')); } catch (e) {}
}

function autoGrow(el) {
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, el.parentElement.clientHeight * 0.6 || 9999) + 'px';
}

// Show / filter the slash-command autocomplete when the user types
// a "/" at the start of a line. Hides when the text doesn't match.
$('input').addEventListener('input', () => {
    autoGrow($('input'));
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
    const inp = $('input');
    inp.value = ex.prompt;
    inp.focus();
    inp.selectionStart = inp.selectionEnd = inp.value.length;
    autoGrow(inp);
}
$('messages').addEventListener('click', (e) => {
    // Delete button on user-defined examples
    const delBtn = e.target.closest('[data-delete-user-idx]');
    if (delBtn) {
        e.stopPropagation();
        const userIdx = +delBtn.dataset.deleteUserIdx;
        const userList = loadUserExamples();
        if (userIdx >= 0 && userIdx < userList.length) {
            userList.splice(userIdx, 1);
            saveUserExamples(userList);
            rebuildExamples();
            toast('Prompt removed.');
            // Re-render /examples if the card is still visible
            const card = delBtn.closest('.system-card');
            if (card) { card.remove(); cmdExamples(); }
        }
        return;
    }
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
    let r = await fetch(API + path, init);
    // Silent 401 retry — same pattern as send(). Never show login
    // modal for transient CSP session expiry during slash commands.
    if (r.status === 401) {
        // Try stored Basic auth first
        const stored = getStoredAuth();
        if (stored) {
            init.headers['Authorization'] = stored;
            r = await fetch(API + path, init);
        }
    }
    if (r.status === 401 && isViaInterop()) {
        // Re-fetch bridge bearer from parent SPA
        const bridge = await fetchBridgeAuth();
        if (bridge.bearer) {
            bridgeBearer = bridge.bearer;
            init.headers['Authorization'] = bridgeBearer;
            r = await fetch(API + path, init);
        }
    }
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
    const userExamples = loadUserExamples();
    const tile = (e, i) => {
        const isUser = i >= BUILTIN_EXAMPLES.length;
        const userIdx = i - BUILTIN_EXAMPLES.length;
        return `<button class="example${isUser ? ' user-example' : ''}" data-example-idx="${i}" type="button">` +
            `<span class="ex-cat">${escapeHtml(e.cat || '')}</span>` +
            (isUser ? `<span class="ex-delete" data-delete-user-idx="${userIdx}" title="Remove this prompt">x</span>` : '') +
            `<span class="ex-arrow">&rarr;</span>` +
            `<span class="ex-title">${escapeHtml(e.title)}</span>` +
        `</button>`;
    };
    const tiles = EXAMPLES.map(tile).join('');
    appendSystemCard(
        '<div class="system-card-head">' + EXAMPLES.length + ' starter prompts' +
            (userExamples.length ? ' (' + userExamples.length + ' custom)' : '') +
        '</div>' +
        '<p class="muted">Click a tile to load it. Use <code class="kbd">/addexample</code> to save your own prompts.</p>' +
        '<div class="example-grid example-grid-wide">' + tiles + '</div>'
    );
}

// /addexample — show a modal form where the user types a category,
// title, and prompt. Saves to localStorage and rebuilds EXAMPLES.
function cmdAddExample() {
    const existing = document.getElementById('agentic-addex-overlay');
    if (existing) existing.remove();
    const overlay = document.createElement('div');
    overlay.id = 'agentic-addex-overlay';
    overlay.style.cssText =
        'position:fixed;inset:0;background:rgba(15,17,21,0.85);z-index:9999;' +
        'display:flex;align-items:center;justify-content:center;color:#e6e8eb;';
    const formStyle = 'background:#161a21;border:1px solid #2a313c;border-radius:6px;padding:24px;width:480px;max-width:90vw;display:flex;flex-direction:column;gap:12px;';
    const inputStyle = 'width:100%;background:#0b0d11;color:#e6e8eb;border:1px solid #2a313c;border-radius:4px;padding:8px;font:inherit;margin-top:4px;';
    const labelStyle = 'color:#8b95a6;font-size:11px;text-transform:uppercase;letter-spacing:0.04em;';
    overlay.innerHTML =
        `<form id="agentic-addex-form" style="${formStyle}">` +
        '<div style="font-weight:600;font-size:14px;">Add a custom prompt</div>' +
        '<div style="color:#8b95a6;font-size:12px;line-height:1.4;">This prompt will appear in /examples and the home screen. Stored in your browser.</div>' +
        `<label style="${labelStyle}">Category (e.g. BUILD, TRANSFORM, REVIEW)` +
          `<input id="addex-cat" type="text" maxlength="20" placeholder="BUILD" style="${inputStyle}">` +
        '</label>' +
        `<label style="${labelStyle}">Title (short description)` +
          `<input id="addex-title" type="text" maxlength="120" placeholder="My custom integration" style="${inputStyle}" required>` +
        '</label>' +
        `<label style="${labelStyle}">Prompt (the full text sent to the agent)` +
          `<textarea id="addex-prompt" rows="6" placeholder="Build a production that..." style="${inputStyle}resize:vertical;min-height:80px;" required></textarea>` +
        '</label>' +
        '<div style="display:flex;gap:8px;justify-content:flex-end;">' +
          '<button type="button" id="addex-cancel" style="background:transparent;border:1px solid #2a313c;color:#8b95a6;padding:8px 16px;border-radius:4px;cursor:pointer;font:13px system-ui;">Cancel</button>' +
          '<button type="submit" style="background:#3b82f6;border:1px solid #3b82f6;color:#fff;padding:8px 16px;border-radius:4px;cursor:pointer;font:600 13px system-ui;">Save</button>' +
        '</div>' +
        '</form>';
    document.body.appendChild(overlay);
    overlay.querySelector('#addex-cancel').addEventListener('click', () => overlay.remove());
    overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
    overlay.querySelector('#addex-title').focus();
    overlay.querySelector('#agentic-addex-form').addEventListener('submit', (e) => {
        e.preventDefault();
        const cat = (overlay.querySelector('#addex-cat').value || 'CUSTOM').trim().toUpperCase();
        const title = overlay.querySelector('#addex-title').value.trim();
        const prompt = overlay.querySelector('#addex-prompt').value.trim();
        if (!title || !prompt) return;
        const userList = loadUserExamples();
        userList.push({ cat, title, prompt, userDefined: true });
        saveUserExamples(userList);
        rebuildExamples();
        overlay.remove();
        toast('Prompt saved. Use /examples to see it.');
    });
}

function cmdClear() {
    startNewConversation();
}

async function cmdNamespace() {
    const ns = bridgeNamespace || currentNs() || '(unknown)';
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
        '<p class="muted">Auto-discovered from <code>%AI.Tool</code> subclasses. Names are PascalCase per the IRIS framework idiom. The agent presents a plan before calling mutating tools and waits for your approval.</p>' +
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
    // Populate the namespace picker (accessible namespaces) and apply the
    // persisted / bridge / dispatch selection. The chosen namespace is
    // sent as X-IRIS-Namespace on every request — no silent default.
    await loadNamespaces();
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
    // The Interface Specification Builder stages a completed specification
    // in localStorage and asks the host page to open this chat. Consume it
    // here — after auth and namespace resolution — so the very first turn
    // carries the spec. Single use: the key is removed before sending, and
    // anything older than 2 minutes is discarded as stale.
    consumeSpecHandoff();
})();

function consumeSpecHandoff() {
    const SPEC_HANDOFF_KEY = 'agentic:spec:prefill';
    let raw;
    try { raw = localStorage.getItem(SPEC_HANDOFF_KEY); } catch { return; }
    if (!raw) return;
    try { localStorage.removeItem(SPEC_HANDOFF_KEY); } catch {}

    let payload;
    try { payload = JSON.parse(raw); } catch { return; }
    if (!payload || !payload.text) return;
    // Stale guard: only honour a handoff staged in the last 2 minutes.
    if (payload.ts && (Date.now() - payload.ts) > 120000) return;

    // Honour the namespace the specification was written against.
    if (payload.ns) {
        const sel = $('ns-select');
        if (sel) { ensureNsOption(payload.ns); sel.value = payload.ns; }
        bridgeNamespace = payload.ns;
        setNamespacePill(payload.ns);
    }

    $('input').value = payload.text;
    $('composer').dispatchEvent(new Event('submit', { cancelable: true }));
}
