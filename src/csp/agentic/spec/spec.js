/* Interface Specification Builder — Agentic Integration Builder
 *
 * A schema-driven questionnaire that collects everything Health Connect
 * needs to build an interface, then renders it as a [[SPEC]] prompt for
 * the Agentic Integration Builder (AIB) agent (AIB).
 *
 * Design notes:
 *  - SCHEMA below is DATA. Every question maps to a real tool parameter or
 *    to one of the agent's documented "gap check" items (the decisions
 *    HealthInterop.cls says it must never silently default). Making it data
 *    is what allows customers to add/remove/relabel fields later without
 *    touching this file's logic.
 *  - "Not sure" is a first-class answer. It routes the item into the spec's
 *    Open questions instead of inventing a default.
 *  - Naming follows Best Practices for Creating Productions §2.5
 *    (From<Src> / To<Tgt> / <Src>Router / <Src>Rules / <Src><T>To<Tgt><T>).
 *
 * Two exits:
 *  - Output Trial  → renders the prompt into an editable preview.
 *  - Send it to AIB → hands the prompt to the chatbot for this namespace.
 */
(function () {
'use strict';

var UNSURE = '__unsure__';
var HANDOFF_KEY = 'agentic:spec:prefill';

/* ============================ helpers ============================ */

function qp(name) {
    try { return new URLSearchParams(window.location.search).get(name) || ''; }
    catch (e) { return ''; }
}

function el(tag, cls, txt) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (txt != null) n.textContent = txt;
    return n;
}

function toast(msg, isErr) {
    var t = document.getElementById('toast');
    t.textContent = msg;
    t.className = isErr ? 'err' : '';
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(function () { t.hidden = true; }, 3200);
}

/* Options shared by several transport questions. */
var TRANSPORTS = [
    { v: 'tcp',  l: 'MLLP / TCP' },
    { v: 'file', l: 'File' },
    { v: 'ftp',  l: 'FTP / SFTP' },
    { v: 'http', l: 'HTTP / REST' },
    { v: 'sql',  l: 'SQL polling' },
    { v: 'mqtt', l: 'MQTT' }
];

var STANDARDS = [
    { v: 'hl7v2', l: 'HL7 v2' },
    { v: 'fhir',  l: 'FHIR R4' },
    { v: 'x12',   l: 'X12 / HIPAA' },
    { v: 'cda',   l: 'CDA / C-CDA' },
    { v: 'sda',   l: 'SDA3' },
    { v: 'flat',  l: 'Delimited / flat file' },
    { v: 'xml',   l: 'XML / JSON' }
];

var HL7_VERSIONS = ['2.3.1', '2.4', '2.5', '2.5.1', '2.6', '2.7', '2.7.1', '2.8'];

var HL7_TYPES = [
    'ADT_A01', 'ADT_A03', 'ADT_A04', 'ADT_A08', 'ORU_R01', 'ORM_O01',
    'OML_O21', 'SIU_S12', 'MDM_T02', 'DFT_P03', 'VXU_V04', 'ACK'
];

/* ============================ the schema ============================ */

var SCHEMA = [

/* ---------- S1 identity ---------- */
{
    id: 'identity', title: 'Interface identity', tier: 'Essential',
    help: 'Who owns this interface, and where does it get built. The short name seeds every generated artifact name.',
    questions: [
        { id: 'name', label: 'Interface name', type: 'text', required: true,
          hint: 'Plain language, e.g. "HIS admissions to LIS"' },
        { id: 'shortName', label: 'Short name', type: 'text', required: true,
          hint: '3-6 characters, used to generate artifact names (e.g. ADTLIS)',
          why: 'Best Practices for Creating Productions §2.3 — the "Name" column',
          validate: function (v) {
              if (!/^[A-Za-z][A-Za-z0-9]{2,5}$/.test(v)) return '3-6 characters, letters and digits, starting with a letter';
              return '';
          } },
        { id: 'purpose', label: 'What should this interface do?', type: 'textarea', required: true,
          hint: 'One or two sentences in business terms. This becomes the specification Overview.' },
        { id: 'namespace', label: 'Target namespace', type: 'text', required: true,
          hint: 'Where the production is built. Must be a Foundation namespace for healthcare interfaces.' },
        { id: 'production', label: 'Production class name', type: 'text', required: true,
          hint: 'Existing production to extend, or a new one, e.g. USER.Productions.ADTLIS' },
        { id: 'owner', label: 'Owner / who to contact about this feed', type: 'text',
          why: 'Best Practices §2.3 — the "Application" column asks for a contact' },
        { id: 'environment', label: 'Environment', type: 'radio', default: 'dev',
          options: [{ v: 'dev', l: 'Development' }, { v: 'test', l: 'Test' }, { v: 'prod', l: 'Production' }] }
    ]
},

/* ---------- S2 pattern ---------- */
{
    id: 'pattern', title: 'Integration pattern', tier: 'Essential',
    help: 'Shapes the rest of the form. Fan-out and routing patterns make the routing section mandatory.',
    questions: [
        { id: 'pattern', label: 'Which pattern fits best?', type: 'radio', required: true, default: 'p2p',
          options: [
              { v: 'p2p',      l: 'Point to point' },
              { v: 'fanout',   l: 'One to many (fan-out)' },
              { v: 'fanin',    l: 'Many to one' },
              { v: 'route',    l: 'Route and transform' },
              { v: 'pass',     l: 'Passthrough / ESB' },
              { v: 'enrich',   l: 'Enrichment (lookup or SQL)' }
          ] }
    ]
},

/* ---------- S3 source ---------- */
{
    id: 'source', title: 'Source (inbound)', tier: 'Essential',
    help: 'Where the data comes from, in what format, over what transport, and what acknowledgment the sender expects.',
    questions: [
        { id: 'srcSystem', label: 'Source system name', type: 'text', required: true,
          hint: 'The sending application, e.g. Epic, Cerner, the HIS' },
        { id: 'srcStandard', label: 'Data standard', type: 'radio', required: true, default: 'hl7v2',
          options: STANDARDS },

        { id: 'srcHl7Version', label: 'HL7 schema category', type: 'select', required: true, default: '2.5',
          options: HL7_VERSIONS.map(function (v) { return { v: v, l: v }; }),
          when: function (a) { return a.srcStandard === 'hl7v2'; },
          hint: 'Set as MessageSchemaCategory on the inbound service.',
          why: 'Agent gap item — without MessageSchemaCategory no routing rule ever matches' },

        { id: 'srcMsgTypes', label: 'Message types / trigger events', type: 'checkbox',
          options: HL7_TYPES.map(function (v) { return { v: v, l: v }; }),
          when: function (a) { return a.srcStandard === 'hl7v2'; },
          required: true, hint: 'Pick every structure this interface must accept.' },

        { id: 'srcFormatOther', label: 'Message / document types', type: 'text',
          when: function (a) { return a.srcStandard && a.srcStandard !== 'hl7v2'; },
          hint: 'e.g. 837P claims, Patient + Encounter resources, CCD documents' },

        { id: 'srcZseg', label: 'Custom Z-segments or a site-specific schema?', type: 'radio', default: 'no',
          when: function (a) { return a.srcStandard === 'hl7v2'; },
          options: [{ v: 'no', l: 'No, standard schema' }, { v: 'yes', l: 'Yes' }, { v: UNSURE, l: 'Not sure' }] },

        { id: 'srcTransport', label: 'Inbound transport', type: 'radio', required: true, options: TRANSPORTS,
          why: 'Agent never-assume item — transport is never guessed' },

        /* transport-conditional */
        { id: 'srcPort', label: 'Listening port', type: 'number', required: true,
          when: function (a) { return a.srcTransport === 'tcp'; } },
        { id: 'srcFraming', label: 'Framing', type: 'select', default: 'MLLP',
          options: ['MLLP', 'Flexible', 'AsciiLF', 'AsciiCR', 'None'].map(function (v) { return { v: v, l: v }; }),
          when: function (a) { return a.srcTransport === 'tcp'; } },
        { id: 'srcFilePath', label: 'Inbound directory', type: 'text', required: true,
          when: function (a) { return a.srcTransport === 'file' || a.srcTransport === 'ftp'; },
          hint: 'e.g. /data/hl7/in/' },
        { id: 'srcFileSpec', label: 'File pattern', type: 'text', default: '*.hl7',
          when: function (a) { return a.srcTransport === 'file' || a.srcTransport === 'ftp'; } },
        { id: 'srcArchivePath', label: 'Archive directory', type: 'text',
          when: function (a) { return a.srcTransport === 'file' || a.srcTransport === 'ftp'; },
          hint: 'Where consumed files are kept. Leave blank to delete after read.',
          why: 'Agent gap item — archive path for file pickups' },
        { id: 'srcFtpServer', label: 'FTP / SFTP server', type: 'text', required: true,
          when: function (a) { return a.srcTransport === 'ftp'; } },
        { id: 'srcHttpEndpoint', label: 'Endpoint path or port', type: 'text', required: true,
          when: function (a) { return a.srcTransport === 'http'; } },
        { id: 'srcSqlQuery', label: 'Polling query', type: 'textarea', required: true,
          when: function (a) { return a.srcTransport === 'sql'; } },
        { id: 'srcMqttTopic', label: 'Topic', type: 'text', required: true,
          when: function (a) { return a.srcTransport === 'mqtt'; } },

        /* acknowledgments — the canonical trap */
        { id: 'ackMode', label: 'Acknowledgment mode', type: 'radio', default: 'Immediate',
          when: function (a) { return a.srcStandard === 'hl7v2'; },
          options: [
              { v: 'Never',         l: 'Never' },
              { v: 'Immediate',     l: 'Immediate' },
              { v: 'Application',   l: 'Application' },
              { v: 'MSH-determined', l: 'MSH-determined' },
              { v: UNSURE,          l: 'Not sure' }
          ],
          why: 'Agent gap item — ACK mode for file/FTP services' },
        { id: 'ackTarget', label: 'Where should ACKs be written?', type: 'text', required: true,
          when: function (a) {
              return a.srcStandard === 'hl7v2' && a.ackMode === 'Application' &&
                     (a.srcTransport === 'file' || a.srcTransport === 'ftp');
          },
          hint: 'A file service has no return channel, so application ACKs need a destination, e.g. /data/hl7/ack/',
          why: 'AckTargetConfigNames — without it the ACK silently lands nowhere' },

        /* Catalog-backed: pick the exact class if you already know it.
         * Leave blank and the agent searches the catalog and proposes one. */
        { id: 'srcHostClass', label: 'Inbound business service class', type: 'catalog',
          catalog: 'ens', kinds: ['BS'],
          pickTitle: 'Choose an inbound business service',
          pickNote: 'Business services indexed on this instance. Leave unset to let the agent choose based on your transport and format.',
          hint: 'Optional. Choose from the catalog if you already know which service class you want.' },
        { id: 'srcAdapter', label: 'Inbound adapter class', type: 'catalog',
          catalog: 'ens', kinds: ['IBA'],
          pickTitle: 'Choose an inbound adapter',
          pickNote: 'Inbound adapters indexed on this instance. Most business services already carry the right adapter — set this only when you need a specific one.',
          hint: 'Optional. Only needed when the service does not imply the adapter you want.' },

        { id: 'fifo', label: 'Must messages be processed strictly in order (FIFO)?', type: 'radio', default: 'yes',
          options: [{ v: 'yes', l: 'Yes' }, { v: 'no', l: 'No' }, { v: UNSURE, l: 'Not sure' }],
          why: 'Agent gap item — FIFO forces Pool Size 1' },

        { id: 'volume', label: 'Expected volume', type: 'text',
          hint: 'e.g. 20,000 messages/day, peak 3,000/hour' }
    ]
},

/* ---------- S4 destinations ---------- */
{
    id: 'targets', title: 'Destinations (outbound)', tier: 'Essential',
    help: 'One entry per receiving application. Best Practices §2.4 prescribes one business operation per receiving application.',
    questions: [
        { id: 'targets', label: 'Destinations', type: 'repeat', required: true,
          addLabel: 'Add a destination', itemLabel: 'Destination',
          fields: [
              { id: 'name', label: 'Target system name', type: 'text', required: true, hint: 'e.g. LIS, PACS, the data warehouse' },
              { id: 'standard', label: 'Output format', type: 'select', default: 'hl7v2', options: STANDARDS },
              { id: 'msgType', label: 'Output message type', type: 'text', hint: 'e.g. ORU_R01. Leave blank if unchanged from source.' },
              { id: 'transport', label: 'Transport', type: 'select', required: true, options: TRANSPORTS },
              { id: 'endpoint', label: 'Destination address', type: 'text', required: true,
                hint: 'Host:port for TCP, directory for file, URL for REST' },
              { id: 'filter', label: 'Which messages go here?', type: 'text',
                hint: 'e.g. only ADT_A01 where MSH:4 = USDMC. Leave blank for everything.' },
              { id: 'hostClass', label: 'Outbound business operation class', type: 'catalog',
                catalog: 'ens', kinds: ['BO'],
                pickTitle: 'Choose an outbound business operation',
                pickNote: 'Business operations indexed on this instance. Leave unset to let the agent choose based on the transport and format above.',
                hint: 'Optional — choose from the catalog if you know it.' },
              { id: 'adapter', label: 'Outbound adapter class', type: 'catalog',
                catalog: 'ens', kinds: ['OBA'],
                pickTitle: 'Choose an outbound adapter',
                pickNote: 'Outbound adapters indexed on this instance. Most operations already carry the right adapter.',
                hint: 'Optional.' },
              { id: 'transform', label: 'Needs a transformation?', type: 'select', default: 'no',
                options: [{ v: 'no', l: 'No, send as received' }, { v: 'yes', l: 'Yes' }] },
              { id: 'retry', label: 'Retry interval (seconds)', type: 'number', default: '30' },
              { id: 'failTimeout', label: 'Failure timeout (seconds)', type: 'text', default: '-1',
                hint: '-1 means retry forever. Recommended for healthcare where delivery is critical.',
                why: 'Agent gap item — healthcare default FailureTimeout=-1' }
          ] }
    ]
},

/* ---------- S5 routing + errors ---------- */
{
    id: 'routing', title: 'Routing and error handling', tier: 'Essential',
    help: 'What happens to messages that do not match, fail validation, or fail to transform.',
    questions: [
        { id: 'deadLetter', label: 'Dead-letter destination', type: 'text', required: true,
          hint: 'Where unroutable or bad messages go, e.g. /data/hl7/deadletter/',
          why: 'Agent gap item — dead-letter / bad-message destination and handler' },
        { id: 'onTransformError', label: 'If a transformation fails', type: 'radio', default: 'Suspend',
          options: [
              { v: 'Suspend', l: 'Suspend the message' },
              { v: 'Log',     l: 'Log and continue' },
              { v: 'Ignore',  l: 'Ignore' },
              { v: UNSURE,    l: 'Not sure' }
          ] },
        { id: 'alertOnError', label: 'Alert on error?', type: 'radio', default: 'yes',
          options: [{ v: 'yes', l: 'Yes' }, { v: 'no', l: 'No' }] },
        { id: 'alertTo', label: 'Who should be alerted?', type: 'text',
          when: function (a) { return a.alertOnError === 'yes'; },
          hint: 'Email address or operations group' }
    ]
},

/* ---------- S6 transformation ---------- */
{
    id: 'transform', title: 'Transformation and mapping', tier: 'Recommended',
    help: 'The single biggest source of ambiguity in an interface spec. Every mapping you state here is one the agent does not have to guess.',
    questions: [
        { id: 'needsTransform', label: 'Does any message need transforming?', type: 'radio', required: true, default: 'yes',
          options: [{ v: 'yes', l: 'Yes' }, { v: 'no', l: 'No, passthrough' }, { v: UNSURE, l: 'Not sure' }] },
        { id: 'approach', label: 'Preferred approach', type: 'radio', default: 'auto',
          when: function (a) { return a.needsTransform === 'yes'; },
          options: [
              { v: 'auto',    l: 'Let the agent decide' },
              { v: 'builtin', l: 'Use an existing transformation' },
              { v: 'dtl',     l: 'Build a custom DTL' },
              { v: 'bpl',     l: 'BPL orchestration' }
          ] },

        /* Reuse before build. InterSystems ships hundreds of transformation
         * classes; the catalog is how an engineer finds the one that already
         * does the job instead of commissioning a new DTL. */
        { id: 'transformClass', label: 'Existing transformation to use', type: 'catalog',
          catalog: 'hs',
          when: function (a) { return a.needsTransform === 'yes'; },
          pickTitle: 'Available transformations',
          pickNote: 'Transformation classes indexed on this instance, with what each one does. Pick one to reuse it; leave unset and the agent searches for the best match and proposes it.',
          hint: 'Optional. Browse to see every transformation available on this instance and what it does.' },
        { id: 'mappings', label: 'Field mappings', type: 'repeat',
          when: function (a) { return a.needsTransform === 'yes'; },
          addLabel: 'Add a mapping', itemLabel: 'Mapping',
          fields: [
              { id: 'action', label: 'Action', type: 'select', default: 'copy-field',
                options: [
                    { v: 'copy-segment',        l: 'Copy a whole segment' },
                    { v: 'copy-field',          l: 'Copy a field' },
                    { v: 'set',                 l: 'Set a constant' },
                    { v: 'concat',              l: 'Concatenate' },
                    { v: 'copy-all-components', l: 'Copy all components' }
                ] },
              { id: 'source', label: 'Source path', type: 'text', hint: 'e.g. PID:PatientName or PID:19' },
              { id: 'target', label: 'Target path', type: 'text', required: true, hint: 'e.g. PID:5 or OBX:5' },
              { id: 'value',  label: 'Value / rule', type: 'text',
                hint: 'Constant value, or the rule in plain language (e.g. strip dashes)' }
          ] },
        { id: 'lookups', label: 'Code translations needed', type: 'textarea',
          when: function (a) { return a.needsTransform === 'yes'; },
          hint: 'e.g. gender: Male to M, Female to F, Unknown to U. One per line.' },
        { id: 'segTerminator', label: 'HL7-to-HL7 output: stamp a segment terminator?', type: 'radio', default: 'yes',
          when: function (a) { return a.needsTransform === 'yes' && a.srcStandard === 'hl7v2'; },
          options: [{ v: 'yes', l: 'Yes (recommended)' }, { v: 'no', l: 'No' }],
          why: 'Agent gap item — a create=new HL7 target with no terminator writes only the MSH segment' }
    ]
},

/* ---------- S7 testing ---------- */
{
    id: 'testing', title: 'Testing and acceptance', tier: 'Recommended',
    help: 'How everyone agrees the interface works. The agent builds and sends a test message as the final build step.',
    questions: [
        { id: 'testMessage', label: 'Sample message or key fields to populate', type: 'textarea',
          hint: 'Paste a sample, or list the fields that must be present in a test message.' },
        { id: 'acceptance', label: 'Acceptance criteria', type: 'textarea',
          hint: 'e.g. an ADT_A01 arriving on port 5000 produces an ORU_R01 in /data/out with PID:3 populated.' }
    ]
},

/* ---------- S8 deployment ---------- */
{
    id: 'deploy', title: 'Deployment and change control', tier: 'Advanced',
    collapsed: true,
    help: 'How this interface moves between environments.',
    questions: [
        { id: 'promotion', label: 'Promotion path', type: 'text', default: 'dev to test to production',
          hint: 'Settings that vary per environment become System Default Settings.' },
        { id: 'sourceControl', label: 'Is source control configured in this namespace?', type: 'radio', default: UNSURE,
          options: [{ v: 'yes', l: 'Yes' }, { v: 'no', l: 'No' }, { v: UNSURE, l: 'Not sure' }] }
    ]
}

];

/* ==================== catalog picker ====================
 * The instance's own indexed catalogs — 164 Ens and EnsLib business hosts
 * and adapters, 58 HS transformation classes — each with the curated
 * description the agent itself searches. An engineer who already knows
 * which class they want picks it here, and the agent uses it instead of
 * choosing one. Everything is read-only: browsing the catalog changes
 * nothing on the instance. */

var catalogCache = {};   // 'ens' | 'hs' -> [entries]
var catalogDesc  = {};   // className -> description, for the inline caption

function catKindLabel(k) {
    return ({
        BS: 'Business service', BO: 'Business operation', BP: 'Business process',
        IBA: 'Inbound adapter', OBA: 'Outbound adapter', MSG: 'Message',
        UTL: 'Utility', DTL: 'Transformation', BPL: 'Business process',
        PRD: 'Production', SCH: 'Schema', 'FHIR-DTL': 'FHIR transformation',
        'CDA-Mapping': 'CDA mapping', Gateway: 'Gateway', API: 'API',
        'HS-Message': 'Message', 'FHIR-Interop': 'FHIR interop'
    })[k] || k || '';
}

/* The catalog text is "ClassName — Kind. Purpose: … When to use: …".
 * Strip the leading class name so the list is not redundant. */
function catDescription(entry) {
    var t = String(entry.text || '');
    var cls = (entry.metadata && entry.metadata.className) || entry.source || '';
    if (cls && t.indexOf(cls) === 0) t = t.slice(cls.length).replace(/^\s*[—-]\s*/, '');
    return t.trim();
}

async function loadCatalog(name) {
    if (catalogCache[name]) return catalogCache[name];
    var headers = {};
    var auth = authHeader();
    if (auth) headers['Authorization'] = auth;
    var ns = currentNamespace();
    if (ns) headers['X-IRIS-Namespace'] = ns;

    var res = await fetch(API + '/catalog/browse?catalog=' + encodeURIComponent(name) +
                          '&pageSize=500&_t=' + Date.now(),
                          { headers: headers, credentials: 'include' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    var j = await res.json();
    var entries = (j.entries || []).map(function (e) {
        var md = e.metadata || {};
        var cls = md.className || e.source || '';
        var d = catDescription(e);
        if (cls) catalogDesc[cls] = d;
        return { cls: cls, kind: md.kind || '', desc: d, pkg: md.package || '' };
    }).filter(function (e) { return e.cls; });
    entries.sort(function (a, b) { return a.cls.localeCompare(b.cls); });
    catalogCache[name] = entries;
    return entries;
}

var cpState = { onPick: null, entries: [], kinds: null };

async function openCatalogPicker(opts) {
    cpState.onPick = opts.onPick;
    cpState.kinds = opts.kinds || null;
    document.getElementById('cp-title').textContent = opts.title || 'Choose from the catalog';
    document.getElementById('cp-note').innerHTML = opts.note || '';
    document.getElementById('cp-q').value = '';
    document.getElementById('cp-list').innerHTML =
        '<div class="cp-empty">Loading the catalog…</div>';
    document.getElementById('catpick').hidden = false;

    try {
        var all = await loadCatalog(opts.catalog);
        cpState.entries = cpState.kinds
            ? all.filter(function (e) { return cpState.kinds.indexOf(e.kind) >= 0; })
            : all;
        renderCatalogList('');
        document.getElementById('cp-q').focus();
    } catch (e) {
        document.getElementById('cp-list').innerHTML =
            '<div class="cp-empty">Could not load the catalog: ' + e.message +
            '.<br>If this page is open on its own, sign in through the chat first.</div>';
        document.getElementById('cp-count').textContent = '';
    }
}

function renderCatalogList(q) {
    var list = document.getElementById('cp-list');
    var needle = String(q || '').toLowerCase().trim();
    var rows = cpState.entries.filter(function (e) {
        if (!needle) return true;
        return (e.cls + ' ' + e.desc).toLowerCase().indexOf(needle) >= 0;
    });
    document.getElementById('cp-count').textContent =
        rows.length + ' of ' + cpState.entries.length;
    list.innerHTML = '';
    if (!rows.length) {
        list.appendChild(el('div', 'cp-empty', 'Nothing matches "' + q + '".'));
        return;
    }
    rows.slice(0, 300).forEach(function (e) {
        var b = el('button', 'cp-item');
        b.type = 'button';
        var top = el('span', 'cp-cls', e.cls);
        top.appendChild(el('span', 'cp-kind', catKindLabel(e.kind)));
        b.appendChild(top);
        if (e.desc) b.appendChild(el('span', 'cp-desc', e.desc));
        b.addEventListener('click', function () {
            var cb = cpState.onPick;
            closeCatalogPicker();
            if (cb) cb(e);
        });
        list.appendChild(b);
    });
}

function closeCatalogPicker() {
    document.getElementById('catpick').hidden = true;
    cpState.onPick = null;
}

/* ============================ state ============================ */

var answers = {};
var repeats = {};   // questionId -> array of row objects

/* Which sections are expanded. Held here rather than read off the DOM
 * because render() rebuilds the form on every answer change — reading the
 * DOM meant a section silently snapped shut whenever you picked a radio.
 * Everything starts collapsed: the page opens as a short, readable index
 * of the work rather than a wall of inputs. */
var sectionOpen = {};

function initDefaults() {
    SCHEMA.forEach(function (sec) {
        sec.questions.forEach(function (q) {
            if (q.type === 'repeat') {
                repeats[q.id] = [blankRow(q)];
            } else if (q.default !== undefined && answers[q.id] === undefined) {
                answers[q.id] = q.default;
            } else if (q.type === 'checkbox' && answers[q.id] === undefined) {
                answers[q.id] = [];
            }
        });
    });
}

function blankRow(q) {
    var row = {};
    q.fields.forEach(function (f) { row[f.id] = f.default !== undefined ? f.default : ''; });
    return row;
}

function visible(q) { return !q.when || !!q.when(answers); }

function answered(q) {
    if (q.type === 'repeat') {
        var rows = repeats[q.id] || [];
        return rows.some(function (r) {
            return q.fields.some(function (f) { return f.required && String(r[f.id] || '').trim(); });
        });
    }
    var v = answers[q.id];
    if (Array.isArray(v)) return v.length > 0;
    return String(v == null ? '' : v).trim() !== '';
}

function missingRequired() {
    var out = [];
    SCHEMA.forEach(function (sec) {
        sec.questions.forEach(function (q) {
            if (!q.required || !visible(q)) return;
            if (!answered(q)) out.push({ sec: sec, q: q });
        });
    });
    return out;
}

/* ============================ rendering ============================ */

function render() {
    var form = document.getElementById('form');
    form.innerHTML = '';
    SCHEMA.forEach(function (sec) { form.appendChild(renderSection(sec)); });
    renderRail();
    renderProgress();
}

/* Required-question tally for one section, counting only what is visible. */
function sectionScore(sec) {
    var reqs = sec.questions.filter(function (q) { return q.required && visible(q); });
    var done = reqs.filter(answered).length;
    var opt  = sec.questions.filter(function (q) { return !q.required && visible(q) && answered(q); }).length;
    return { req: reqs.length, done: done, optional: opt };
}

function renderSection(sec) {
    var open = !!sectionOpen[sec.id];
    var wrap = el('section', 'section' + (open ? '' : ' collapsed'));
    wrap.id = 'sec-' + sec.id;

    var s = sectionScore(sec);
    var head = el('div', 'section-head');
    head.appendChild(el('h3', null, sec.title));
    head.appendChild(el('span', 'tier', sec.tier));

    // Progress chip — makes the collapsed view an index you can act on
    // rather than just a list of names.
    if (s.req > 0) {
        var chip = el('span', 'sec-chip' + (s.done === s.req ? ' ok' : ''), s.done + '/' + s.req);
        chip.title = s.done + ' of ' + s.req + ' required answers complete';
        head.appendChild(chip);
    } else if (s.optional > 0) {
        head.appendChild(el('span', 'sec-chip ok', String(s.optional)));
    }

    head.appendChild(el('span', 'caret', '▼'));
    head.addEventListener('click', function () {
        sectionOpen[sec.id] = !sectionOpen[sec.id];
        wrap.classList.toggle('collapsed', !sectionOpen[sec.id]);
    });
    wrap.appendChild(head);

    if (sec.help) wrap.appendChild(el('div', 'section-help', sec.help));

    var body = el('div', 'section-body grid2');

    // Escape hatch: mapping work beyond a simple table belongs in the
    // dedicated visual tool, not in this form.
    if (sec.id === 'transform') body.appendChild(renderAtlas());

    sec.questions.forEach(function (q) {
        if (!visible(q)) return;
        body.appendChild(renderQuestion(q));
    });

    // derived artifact names, shown on the identity section
    if (sec.id === 'identity') body.appendChild(renderDerived());

    wrap.appendChild(body);
    return wrap;
}

function labelFor(q) {
    var lab = el('label', null, q.label);
    if (q.required) lab.appendChild(el('span', 'req', '*'));
    if (seededFields[q.id]) lab.appendChild(el('span', 'seeded-tag', 'verify'));
    if (q.hint) lab.appendChild(el('span', 'hint', q.hint));
    if (q.why)  lab.appendChild(el('span', 'why', q.why));
    return lab;
}

/* Short controls sit two-per-row; anything that needs room (prose, option
 * groups, repeating rows, catalog pickers) spans the full width. This is
 * what reclaims the horizontal space an open section was wasting. */
function isCompact(q) {
    return q.type === 'text' || q.type === 'number' || q.type === 'select';
}

function renderQuestion(q) {
    var f = el('div', 'field' + (isCompact(q) ? '' : ' wide') +
                      (seededFields[q.id] ? ' seeded' : ''));
    f.dataset.qid = q.id;

    if (q.type === 'repeat') {
        var lw = el('div', 'flabel', q.label);
        if (q.required) lw.appendChild(el('span', 'req', '*'));
        if (seededFields[q.id]) lw.appendChild(el('span', 'seeded-tag', 'verify'));
        if (q.hint) lw.appendChild(el('span', 'hint', q.hint));
        f.appendChild(lw);
        f.appendChild(renderRepeat(q));
        return f;
    }

    f.appendChild(labelFor(q));

    var v = answers[q.id];

    if (q.type === 'text' || q.type === 'number') {
        var inp = document.createElement('input');
        inp.type = q.type === 'number' ? 'number' : 'text';
        inp.value = v == null ? '' : v;
        inp.addEventListener('input', function () {
            answers[q.id] = inp.value;
            validateField(f, q, inp.value);
            renderProgress();
        });
        inp.addEventListener('change', maybeRerender(q));
        f.appendChild(inp);

    } else if (q.type === 'catalog') {
        f.appendChild(catalogControl({
            value: v == null ? '' : v,
            catalog: q.catalog,
            kinds: q.kinds,
            title: q.pickTitle || q.label,
            note: q.pickNote || '',
            placeholder: q.placeholder || 'Not chosen — the agent will select one',
            onChange: function (cls) { answers[q.id] = cls; rerender(); }
        }));

    } else if (q.type === 'textarea') {
        var ta = document.createElement('textarea');
        ta.value = v == null ? '' : v;
        ta.addEventListener('input', function () { answers[q.id] = ta.value; renderProgress(); });
        f.appendChild(ta);

    } else if (q.type === 'select') {
        var sel = document.createElement('select');
        (q.options || []).forEach(function (o) {
            var op = document.createElement('option');
            op.value = o.v; op.textContent = o.l;
            if (String(v) === String(o.v)) op.selected = true;
            sel.appendChild(op);
        });
        if (v == null || v === '') { answers[q.id] = sel.value; }
        sel.addEventListener('change', function () {
            answers[q.id] = sel.value;
            rerender();
        });
        f.appendChild(sel);

    } else if (q.type === 'radio' || q.type === 'checkbox') {
        var box = el('div', 'opts');
        (q.options || []).forEach(function (o) {
            var isCheck = q.type === 'checkbox';
            var on = isCheck ? (Array.isArray(v) && v.indexOf(o.v) >= 0) : String(v) === String(o.v);
            var lab = el('label', 'opt' + (on ? ' on' : ''));
            var inp2 = document.createElement('input');
            inp2.type = isCheck ? 'checkbox' : 'radio';
            inp2.name = q.id;
            inp2.checked = on;
            inp2.addEventListener('change', function () {
                if (isCheck) {
                    var arr = Array.isArray(answers[q.id]) ? answers[q.id].slice() : [];
                    var i = arr.indexOf(o.v);
                    if (inp2.checked && i < 0) arr.push(o.v);
                    if (!inp2.checked && i >= 0) arr.splice(i, 1);
                    answers[q.id] = arr;
                } else {
                    answers[q.id] = o.v;
                }
                rerender();
            });
            lab.appendChild(inp2);
            lab.appendChild(document.createTextNode(o.l));
            box.appendChild(lab);
        });
        f.appendChild(box);
    }

    return f;
}

/* Shared control for any catalog-backed field, used by both top-level
 * questions and repeat sub-fields: a read-only class name, a Browse button,
 * and the catalog's own description of whatever was chosen. */
function catalogControl(cfg) {
    var wrap = el('div');
    var row = el('div', 'cat-field');

    var inp = document.createElement('input');
    inp.type = 'text';
    inp.readOnly = true;
    inp.value = cfg.value || '';
    inp.placeholder = cfg.placeholder || '';
    row.appendChild(inp);

    var browse = el('button', 'btn sm', 'Browse');
    browse.type = 'button';
    browse.addEventListener('click', function () {
        openCatalogPicker({
            catalog: cfg.catalog, kinds: cfg.kinds,
            title: cfg.title, note: cfg.note,
            onPick: function (e) { cfg.onChange(e.cls); }
        });
    });
    row.appendChild(browse);

    if (cfg.value) {
        var clr = el('button', 'btn ghost sm', 'Clear');
        clr.type = 'button';
        clr.addEventListener('click', function () { cfg.onChange(''); });
        row.appendChild(clr);
    }

    wrap.appendChild(row);
    if (cfg.value && catalogDesc[cfg.value]) {
        wrap.appendChild(el('div', 'cat-desc', catalogDesc[cfg.value]));
    }
    return wrap;
}

function maybeRerender(q) {
    return function () { if (q.id === 'shortName' || q.id === 'srcSystem') rerender(); };
}

function validateField(fieldEl, q, val) {
    if (!q.validate) return true;
    var msg = String(val).trim() ? q.validate(val) : '';
    fieldEl.classList.toggle('invalid', !!msg);
    return !msg;
}

function renderRepeat(q) {
    var host = el('div');
    var rows = repeats[q.id] || (repeats[q.id] = [blankRow(q)]);

    rows.forEach(function (row, idx) {
        var item = el('div', 'repeat-item');
        var head = el('div', 'repeat-item-head');
        head.appendChild(el('span', null, (q.itemLabel || 'Item') + ' ' + (idx + 1)));
        if (rows.length > 1) {
            var del = el('button', 'linkbtn danger', 'Remove');
            del.type = 'button';
            del.addEventListener('click', function () { rows.splice(idx, 1); rerender(); });
            head.appendChild(del);
        }
        item.appendChild(head);

        var grid = el('div', 'repeat-row');
        q.fields.forEach(function (fl) {
            var sub = el('div', 'field');
            var lab = el('label', null, fl.label);
            if (fl.required) lab.appendChild(el('span', 'req', '*'));
            if (fl.hint) lab.appendChild(el('span', 'hint', fl.hint));
            if (fl.why)  lab.appendChild(el('span', 'why', fl.why));
            sub.appendChild(lab);

            if (fl.type === 'catalog') {
                sub.appendChild(catalogControl({
                    value: row[fl.id] || '',
                    catalog: fl.catalog, kinds: fl.kinds,
                    title: fl.pickTitle || fl.label, note: fl.pickNote || '',
                    placeholder: fl.placeholder || 'Not chosen — the agent will select one',
                    onChange: function (cls) { row[fl.id] = cls; rerender(); }
                }));
            } else if (fl.type === 'select') {
                var sel = document.createElement('select');
                (fl.options || []).forEach(function (o) {
                    var op = document.createElement('option');
                    op.value = o.v; op.textContent = o.l;
                    if (String(row[fl.id]) === String(o.v)) op.selected = true;
                    sel.appendChild(op);
                });
                if (!row[fl.id]) row[fl.id] = sel.value;
                sel.addEventListener('change', function () { row[fl.id] = sel.value; renderProgress(); });
                sub.appendChild(sel);
            } else {
                var inp = document.createElement('input');
                inp.type = fl.type === 'number' ? 'number' : 'text';
                inp.value = row[fl.id] == null ? '' : row[fl.id];
                inp.addEventListener('input', function () { row[fl.id] = inp.value; renderProgress(); });
                sub.appendChild(inp);
            }
            grid.appendChild(sub);
        });
        item.appendChild(grid);
        host.appendChild(item);
    });

    var add = el('button', 'linkbtn', '+ ' + (q.addLabel || 'Add'));
    add.type = 'button';
    add.addEventListener('click', function () { rows.push(blankRow(q)); rerender(); });
    var actions = el('div', 'repeat-actions');
    actions.appendChild(add);
    host.appendChild(actions);
    return host;
}

/* Artifact names derived from the documented naming conventions. */
function names() {
    var s = (answers.shortName || '').trim() || 'IFACE';
    var src = (answers.srcSystem || '').trim().replace(/[^A-Za-z0-9]/g, '') || s;
    return {
        service: 'From' + src,
        router:  src + 'Router',
        rules:   (answers.production || 'USER') + '.Rules.' + src + 'Rules',
        dtlBase: src
    };
}

/* Data Atlas hand-off. The questionnaire's mapping table is deliberately
 * simple — good for a handful of rules, wrong for a 200-row field mapping.
 * Rather than grow the form into a mapping tool, hand the user to the
 * dedicated one and let them come back. Dummy for now: no target is wired
 * up, so the button acknowledges the click and does nothing else. */
function renderAtlas() {
    var box = el('div', 'atlas-box wide');
    var txt = el('div', 'atlas-txt');
    txt.innerHTML = 'Mapping something complex? <b>Data Atlas</b> is the visual tool for ' +
        'building transformations field by field. Work there and come back &mdash; anything ' +
        'you build is available to this specification.';
    box.appendChild(txt);
    var b = el('button', 'btn atlas', 'GO TO DATA ATLAS');
    b.type = 'button';
    b.title = 'Open Data Atlas to build transformations visually';
    b.addEventListener('click', function () {
        // Placeholder for now — there is no Data Atlas target wired up, and
        // opening some other page would be worse than doing nothing. When a
        // real URL exists, pass it as ?atlas=<url> and this navigates.
        var url = qp('atlas');
        if (url) { window.open(url, '_blank'); toast('Opening Data Atlas in a new tab.'); return; }
        toast('Data Atlas would open here. Not wired up yet.');
    });
    box.appendChild(b);
    return box;
}

function renderDerived() {
    var n = names();
    var d = el('div', 'derived wide');
    var t = document.createElement('table');
    var rows = [
        ['Business service', n.service],
        ['Routing process', n.router],
        ['Routing rule set', n.rules],
        ['Business operations', 'To<TargetName> (one per destination)']
    ];
    rows.forEach(function (r) {
        var tr = document.createElement('tr');
        var td1 = document.createElement('td'); td1.textContent = r[0];
        var td2 = document.createElement('td');
        var c = document.createElement('code'); c.textContent = r[1];
        td2.appendChild(c);
        tr.appendChild(td1); tr.appendChild(td2);
        t.appendChild(tr);
    });
    d.appendChild(el('div', 'muted', 'Artifact names generated from the InterSystems naming conventions. The agent will use these exact names.'));
    d.appendChild(t);
    return d;
}

function renderRail() {
    var rail = document.getElementById('rail');
    rail.innerHTML = '';
    SCHEMA.forEach(function (sec) {
        var reqs = sec.questions.filter(function (q) { return q.required && visible(q); });
        var done = reqs.filter(answered).length;
        var cls = reqs.length === 0 ? '' : (done === reqs.length ? 'done' : 'todo');
        var b = el('button', cls);
        b.type = 'button';
        b.appendChild(el('span', 'dot'));
        b.appendChild(el('span', null, sec.title));
        b.addEventListener('click', function () {
            var t = document.getElementById('sec-' + sec.id);
            if (t) { t.classList.remove('collapsed'); t.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
        });
        rail.appendChild(b);
    });
}

/* Open a section and put the cursor on a specific question. Used by the
 * "Still needed" list, which is only useful if it takes you there. */
function jumpTo(secId, qid) {
    sectionOpen[secId] = true;
    render();
    var sec = document.getElementById('sec-' + secId);
    if (sec) sec.classList.remove('collapsed');
    var f = document.querySelector('.field[data-qid="' + qid + '"]');
    var target = f || sec;
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    if (f) {
        var ctl = f.querySelector('input:not([readonly]), textarea, select');
        if (ctl) setTimeout(function () { try { ctl.focus({ preventScroll: true }); } catch (e) {} }, 260);
        f.classList.add('flash');
        setTimeout(function () { f.classList.remove('flash'); }, 1200);
    }
}

/* The right column's lower half: everything still required, grouped by
 * section and clickable. With the form collapsed by default this is the
 * main way a user knows where the remaining work is. */
function renderTodo() {
    var host = document.getElementById('todo-list');
    if (!host) return;
    var missing = missingRequired();
    host.innerHTML = '';

    if (!missing.length) {
        var ok = el('div', 'todo-done');
        ok.appendChild(el('div', 'todo-done-t', 'Ready to send'));
        ok.appendChild(el('div', null, 'Every required answer is complete. Use Output Trial to review the specification, or send it straight to the agent.'));
        host.appendChild(ok);
        return;
    }

    var bySec = [];
    missing.forEach(function (m) {
        var g = bySec.filter(function (x) { return x.sec === m.sec; })[0];
        if (!g) { g = { sec: m.sec, items: [] }; bySec.push(g); }
        g.items.push(m.q);
    });

    bySec.forEach(function (g) {
        host.appendChild(el('div', 'todo-sec', g.sec.title));
        g.items.forEach(function (q) {
            var b = el('button', 'todo-item', q.label);
            b.type = 'button';
            b.title = 'Go to this question';
            b.addEventListener('click', function () { jumpTo(g.sec.id, q.id); });
            host.appendChild(b);
        });
    });
}

function renderProgress() {
    var total = 0, done = 0;
    SCHEMA.forEach(function (sec) {
        sec.questions.forEach(function (q) {
            if (!q.required || !visible(q)) return;
            total++;
            if (answered(q)) done++;
        });
    });
    document.getElementById('progress').textContent = done + ' of ' + total + ' required answered';
    var bar = document.getElementById('progress-bar');
    if (bar) bar.style.width = (total ? Math.round(done / total * 100) : 0) + '%';
    renderRail();
    renderTodo();
}

var rerenderPending = false;
function rerender() {
    if (rerenderPending) return;
    rerenderPending = true;
    setTimeout(function () { rerenderPending = false; render(); }, 0);
}

/* ============================ prompt generation ============================ */

function isUnsure(v) { return v === UNSURE; }

function labelOf(q, v) {
    var o = (q.options || []).filter(function (x) { return String(x.v) === String(v); })[0];
    return o ? o.l : v;
}

function findQ(id) {
    for (var i = 0; i < SCHEMA.length; i++) {
        var qs = SCHEMA[i].questions;
        for (var j = 0; j < qs.length; j++) if (qs[j].id === id) return qs[j];
    }
    return null;
}

function transportLabel(v) {
    var t = TRANSPORTS.filter(function (x) { return x.v === v; })[0];
    return t ? t.l : v;
}
function standardLabel(v) {
    var t = STANDARDS.filter(function (x) { return x.v === v; })[0];
    return t ? t.l : v;
}

function buildPrompt() {
    var a = answers;
    var n = names();
    var open = [];       // open questions
    var confirmed = [];  // confirmed defaults
    var L = [];

    var title = a.name || 'New interface';

    L.push('[[SPEC]]');
    L.push('# Project Specification: ' + title);
    L.push('');

    /* ---- Overview ---- */
    L.push('## Overview');
    var ov = a.purpose || 'Build a healthcare interface in InterSystems Health Connect.';
    L.push(ov.trim());
    L.push('');
    L.push('Target namespace: ' + (a.namespace || 'not specified') +
           '. Production: ' + (a.production || 'not specified') +
           '. Environment: ' + (a.environment || 'dev') + '.');
    if (a.owner) L.push('Owner / contact for this feed: ' + a.owner + '.');
    L.push('');

    /* ---- Exercises ---- */
    L.push('## Exercises');
    L.push('');
    L.push('### 1. ' + title);

    var srcDesc = (a.srcSystem || 'the source system') + ' sending ' + standardLabel(a.srcStandard || 'hl7v2');
    if (a.srcStandard === 'hl7v2') {
        srcDesc += ' ' + (a.srcHl7Version || '2.5');
        var types = Array.isArray(a.srcMsgTypes) ? a.srcMsgTypes : [];
        if (types.length) srcDesc += ' (' + types.join(', ') + ')';
    } else if (a.srcFormatOther) {
        srcDesc += ' (' + a.srcFormatOther + ')';
    }
    srcDesc += ' over ' + transportLabel(a.srcTransport || '');

    L.push('- Goal: ' + (a.purpose || title));
    L.push('- Inputs: ' + srcDesc);

    /* inbound transport detail */
    var inbound = [];
    if (a.srcTransport === 'tcp') {
        inbound.push('listening port ' + (a.srcPort || 'not specified'));
        if (a.srcFraming) inbound.push('framing ' + a.srcFraming);
    }
    if (a.srcTransport === 'file' || a.srcTransport === 'ftp') {
        inbound.push('inbound directory ' + (a.srcFilePath || 'not specified'));
        if (a.srcFileSpec) inbound.push('file pattern ' + a.srcFileSpec);
        if (a.srcArchivePath) inbound.push('archive to ' + a.srcArchivePath);
    }
    if (a.srcTransport === 'ftp' && a.srcFtpServer) inbound.push('server ' + a.srcFtpServer);
    if (a.srcTransport === 'http' && a.srcHttpEndpoint) inbound.push('endpoint ' + a.srcHttpEndpoint);
    if (a.srcTransport === 'sql' && a.srcSqlQuery) inbound.push('polling query: ' + a.srcSqlQuery.replace(/\s+/g, ' ').trim());
    if (a.srcTransport === 'mqtt' && a.srcMqttTopic) inbound.push('topic ' + a.srcMqttTopic);
    if (inbound.length) L.push('- Inbound transport detail: ' + inbound.join('; '));

    // Explicit class choices override the agent's own catalog search.
    if (a.srcHostClass) L.push('- Inbound business service class (chosen from the catalog): ' + a.srcHostClass);
    if (a.srcAdapter)   L.push('- Inbound adapter class (chosen from the catalog): ' + a.srcAdapter);

    /* outputs */
    var tgts = (repeats.targets || []).filter(function (t) { return String(t.name || '').trim(); });
    if (tgts.length) {
        L.push('- Outputs:');
        tgts.forEach(function (t) {
            var line = '  - ' + t.name + ' — ' + standardLabel(t.standard) +
                       (t.msgType ? ' ' + t.msgType : '') +
                       ' over ' + transportLabel(t.transport) +
                       ' at ' + (t.endpoint || 'address not specified');
            if (t.transform === 'yes') line += '; requires transformation';
            if (t.hostClass) line += '; use business operation class ' + t.hostClass;
            if (t.adapter)   line += '; adapter ' + t.adapter;
            L.push(line);
        });
    } else {
        L.push('- Outputs: not specified');
        open.push('No destination was specified. Where should messages be delivered?');
    }

    /* transformation rules */
    if (a.needsTransform === 'yes') {
        L.push('- Transformation rules:');
        var maps = (repeats.mappings || []).filter(function (m) { return String(m.target || '').trim(); });
        if (maps.length) {
            maps.forEach(function (m) {
                var line = '  - ';
                if (m.action === 'set')                  line += 'Set ' + m.target + ' to ' + (m.value || '(value not given)');
                else if (m.action === 'copy-segment')     line += 'Copy segment ' + (m.source || '?') + ' to ' + m.target;
                else if (m.action === 'concat')           line += 'Concatenate ' + (m.source || '?') + ' into ' + m.target + (m.value ? ' (' + m.value + ')' : '');
                else if (m.action === 'copy-all-components') line += 'Copy all components of ' + (m.source || '?') + ' to ' + m.target;
                else                                     line += 'Copy ' + (m.source || '?') + ' to ' + m.target;
                if (m.value && m.action !== 'set' && m.action !== 'concat') line += ' — ' + m.value;
                L.push(line);
            });
        } else {
            L.push('  - Transformation is required but no field mappings were provided.');
            open.push('Which fields must be mapped from source to target? No field mappings were supplied.');
        }
        if (a.lookups && a.lookups.trim()) {
            L.push('- Code translations (lookup tables):');
            a.lookups.split('\n').forEach(function (l) {
                if (l.trim()) L.push('  - ' + l.trim());
            });
        }
        if (a.transformClass) {
            L.push('- Use the existing transformation class ' + a.transformClass +
                   ' (chosen from the catalog) rather than creating a new one.');
        }
        if (a.approach && a.approach !== 'auto') {
            var ap = { builtin: 'Use the built-in SDA pipeline', dtl: 'Use a custom DTL', bpl: 'Use a BPL orchestration' }[a.approach];
            if (ap) L.push('- Preferred approach: ' + ap);
        }
    } else if (a.needsTransform === 'no') {
        L.push('- Transformation rules: none. Messages pass through unchanged.');
    } else {
        open.push('Is a transformation required? This was left as "not sure".');
    }

    /* routing rules */
    L.push('- Routing rules:');
    if (tgts.length) {
        tgts.forEach(function (t) {
            L.push('  - Route to ' + t.name + ': ' + (String(t.filter || '').trim() || 'all messages'));
        });
    }
    L.push('  - Anything unroutable or failing validation goes to the dead-letter destination ' +
           (a.deadLetter || '(not specified)') + '.');

    /* acceptance */
    var acc = (a.acceptance || '').trim();
    L.push('- Acceptance criteria: ' + (acc || 'The production starts, all hosts are enabled, a test message flows end to end with no event-log errors, and every mapped field is populated in the output.'));
    L.push('');

    /* ---- Confirmed defaults ---- */
    // These pre-answer the agent's documented gap-check items so it does not
    // have to spend a turn asking.
    if (a.srcStandard === 'hl7v2') {
        confirmed.push('MessageSchemaCategory on the inbound service: ' + (a.srcHl7Version || '2.5'));
        if (isUnsure(a.ackMode)) {
            open.push('Which acknowledgment mode should the inbound service use (Never, Immediate, Application, MSH-determined)?');
        } else if (a.ackMode) {
            var ackLine = 'Acknowledgment mode: ' + a.ackMode;
            if (a.ackTarget) ackLine += '; ACKs written to ' + a.ackTarget;
            else if (a.ackMode === 'Application' && (a.srcTransport === 'file' || a.srcTransport === 'ftp')) {
                open.push('Application ACKs were requested on a file-based inbound service, which has no return channel. Where should the ACKs be written?');
            }
            confirmed.push(ackLine);
        }
        if (a.segTerminator === 'yes' && a.needsTransform === 'yes') {
            confirmed.push('HL7-to-HL7 target: stamp a CR segment terminator so the full message is written, not just the MSH segment');
        }
        confirmed.push('Validation on the HL7 routing engine: empty (accept real-world out-of-order segments)');
    }

    if (isUnsure(a.fifo)) {
        open.push('Must messages be processed strictly in order (FIFO)? This determines pool sizing.');
    } else if (a.fifo === 'yes') {
        confirmed.push('Ordering: FIFO required, so Pool Size 1 on the inbound service');
    } else if (a.fifo === 'no') {
        confirmed.push('Ordering: FIFO not required, pool size may be tuned for throughput');
    }

    if (a.deadLetter) confirmed.push('Dead-letter / bad-message destination: ' + a.deadLetter);

    if (tgts.length) {
        var r = tgts[0];
        confirmed.push('Outbound retry: retry interval ' + (r.retry || '30') +
                       's, failure timeout ' + (r.failTimeout || '-1') +
                       (String(r.failTimeout) === '-1' ? ' (retry forever — healthcare default)' : ''));
    }

    if (a.srcArchivePath) confirmed.push('Archive path for file pickups: ' + a.srcArchivePath);
    else if (a.srcTransport === 'file' || a.srcTransport === 'ftp') {
        confirmed.push('Archive path: none — consumed files are deleted after read');
    }

    if (isUnsure(a.onTransformError)) {
        open.push('What should happen when a transformation fails (suspend, log and continue, or ignore)?');
    } else if (a.onTransformError) {
        confirmed.push('On transformation error: ' + a.onTransformError);
    }

    if (a.alertOnError === 'yes') {
        confirmed.push('Alert on error: enabled' + (a.alertTo ? ', notify ' + a.alertTo : ''));
        if (!a.alertTo) open.push('Alerting is enabled but no recipient was given. Who should receive alerts?');
    }

    if (a.srcZseg === 'yes') {
        open.push('The source uses custom Z-segments or a site-specific schema. Can you supply the schema definition, or should it be derived from sample messages?');
    } else if (isUnsure(a.srcZseg)) {
        open.push('Does the source use custom Z-segments or a site-specific HL7 schema?');
    }

    if (isUnsure(a.sourceControl)) {
        open.push('Is source control configured in this namespace? If not, artifacts created here will not be version-tracked.');
    }

    if (a.volume) confirmed.push('Expected volume: ' + a.volume);

    /* naming */
    confirmed.push('Artifact naming (InterSystems conventions): business service ' + n.service +
                   ', routing process ' + n.router + ', rule set ' + n.rules +
                   ', one business operation per destination named To<TargetName>');

    L.push('## Confirmed defaults');
    if (confirmed.length) {
        confirmed.forEach(function (c) { L.push('- ' + c); });
    } else {
        L.push('- None specified.');
    }
    L.push('');

    /* ---- Open questions ---- */
    L.push('## Open questions');
    if (open.length) {
        open.forEach(function (o, i) { L.push((i + 1) + '. ' + o); });
    } else {
        L.push('None — every required decision was specified above.');
    }
    L.push('');

    /* ---- Build tasks ---- */
    L.push('## Build tasks (post-approval)');
    var tasks = [];
    if (a.needsTransform === 'yes') tasks.push('Data transformation for the source-to-target mapping described above');
    if (a.lookups && a.lookups.trim()) tasks.push('Lookup table(s) for the code translations listed above');
    tasks.push('Routing rule set covering every destination plus the dead-letter fallback');
    tasks.push('Production containing the inbound service, the routing process, one operation per destination, and a dead-letter operation');
    tasks.push('All host and adapter settings configured, and every referenced directory created');
    tasks.push('Start the production, send a test message, and validate end to end');
    tasks.forEach(function (t, i) { L.push((i + 1) + '. ' + t); });

    L.push('[[/SPEC]]');

    // Share the derived confirmed-defaults / open-questions with buildJson so
    // the prose and the JSON can never disagree about them.
    lastMeta = { confirmed: confirmed.slice(), open: open.slice() };

    return L.join('\n');
}

/* Confirmed defaults and open questions are derived while rendering the
 * prose. buildJson needs the same two lists, so it re-derives them here
 * rather than duplicating the (order-dependent) logic. */
var lastMeta = { confirmed: [], open: [] };

function collectDerived() {
    buildPrompt();
    return lastMeta;
}

/* ==================== canonical JSON payload ====================
 * The machine-readable half of the output. Keys are named after the
 * things the agent's tools actually take (schemaCategory, ackMode,
 * poolSize, failureTimeout, ...) so the agent maps answers to tool
 * arguments directly instead of inferring them from prose.
 * Anything the user left as "not sure" is omitted here and surfaced in
 * openQuestions — an absent key means "ask", never "assume". */

function buildJson() {
    var a = answers;
    var n = names();
    var meta = collectDerived();   // { confirmed:[], open:[] }

    function val(v) {
        if (v == null) return undefined;
        if (isUnsure(v)) return undefined;
        var s = String(v).trim();
        return s === '' ? undefined : v;
    }

    /* Answer-by-id, but only if that question is currently VISIBLE.
     * Defaults are seeded for every question up front, including ones behind
     * a `when` predicate, so reading answers directly would leak (for example)
     * the File branch's fileSpec into a TCP source. Visibility is the same
     * condition the user actually saw, so it is the right gate. */
    function av(qid) {
        var q = findQ(qid);
        if (!q || !visible(q)) return undefined;
        return val(a[qid]);
    }

    var src = {
        system:         val(a.srcSystem),
        standard:       val(a.srcStandard),
        schemaCategory: av('srcHl7Version'),
        messageTypes:   (visible(findQ('srcMsgTypes')) && Array.isArray(a.srcMsgTypes) && a.srcMsgTypes.length) ? a.srcMsgTypes : undefined,
        documentTypes:  av('srcFormatOther'),
        customSchema:   visible(findQ('srcZseg')) ? (a.srcZseg === 'yes' ? true : (a.srcZseg === 'no' ? false : undefined)) : undefined,
        transport:      val(a.srcTransport),
        port:           av('srcPort'),
        framing:        av('srcFraming'),
        filePath:       av('srcFilePath'),
        fileSpec:       av('srcFileSpec'),
        archivePath:    av('srcArchivePath'),
        ftpServer:      av('srcFtpServer'),
        httpEndpoint:   av('srcHttpEndpoint'),
        sqlQuery:       av('srcSqlQuery'),
        mqttTopic:      av('srcMqttTopic'),
        hostClass:      av('srcHostClass'),
        adapterClass:   av('srcAdapter'),
        ackMode:        av('ackMode'),
        ackTarget:      av('ackTarget'),
        fifoRequired:   a.fifo === 'yes' ? true : (a.fifo === 'no' ? false : undefined),
        poolSize:       a.fifo === 'yes' ? 1 : undefined,
        volume:         val(a.volume)
    };

    var dests = (repeats.targets || [])
        .filter(function (t) { return String(t.name || '').trim(); })
        .map(function (t) {
            return {
                name:           t.name,
                standard:       val(t.standard),
                messageType:    val(t.msgType),
                transport:      val(t.transport),
                endpoint:       val(t.endpoint),
                hostClass:      val(t.hostClass),
                adapterClass:   val(t.adapter),
                routeWhen:      val(t.filter) || 'all',
                needsTransform: t.transform === 'yes',
                retryInterval:  val(t.retry),
                failureTimeout: val(t.failTimeout)
            };
        });

    var maps = (repeats.mappings || [])
        .filter(function (m) { return String(m.target || '').trim(); })
        .map(function (m) {
            return {
                action: m.action,
                source: val(m.source),
                target: m.target,
                value:  val(m.value)
            };
        });

    var lookups = (a.lookups || '').split('\n')
        .map(function (l) { return l.trim(); })
        .filter(Boolean);

    var payload = {
        specVersion: '1.0',
        generatedBy: 'InterSystems Integration Spec Questionnaire',
        interface: {
            name:        val(a.name),
            shortName:   val(a.shortName),
            purpose:     val(a.purpose),
            namespace:   val(a.namespace),
            production:  val(a.production),
            environment: val(a.environment),
            owner:       val(a.owner),
            pattern:     val(a.pattern)
        },
        derivedNames: {
            businessService: n.service,
            routingProcess:  n.router,
            ruleSet:         n.rules,
            operationPrefix: 'To'
        },
        source: src,
        destinations: dests.length ? dests : undefined,
        routing: {
            deadLetter:       val(a.deadLetter),
            onTransformError: val(a.onTransformError),
            alertOnError:     a.alertOnError === 'yes' ? true : (a.alertOnError === 'no' ? false : undefined),
            alertRecipients:  val(a.alertTo),
            validation:       a.srcStandard === 'hl7v2' ? '' : undefined
        },
        transformation: {
            required:          a.needsTransform === 'yes' ? true : (a.needsTransform === 'no' ? false : undefined),
            approach:          (av('approach') && a.approach !== 'auto') ? a.approach : undefined,
            reuseClass:        av('transformClass'),
            mappings:          maps.length ? maps : undefined,
            codeTranslations:  lookups.length ? lookups : undefined,
            stampSegmentTerminator: visible(findQ('segTerminator'))
                                    ? (a.segTerminator === 'yes' ? true : (a.segTerminator === 'no' ? false : undefined))
                                    : undefined
        },
        testing: {
            sampleMessage: val(a.testMessage),
            acceptance:    val(a.acceptance)
        },
        deployment: {
            promotionPath: val(a.promotion),
            sourceControl: a.sourceControl === 'yes' ? true : (a.sourceControl === 'no' ? false : undefined)
        },
        confirmedDefaults: meta.confirmed,
        openQuestions: meta.open
    };

    // Drop undefined / empty containers so the agent never sees noise.
    return JSON.parse(JSON.stringify(payload, function (k, v) {
        if (v === undefined) return undefined;
        if (v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0) return undefined;
        return v;
    }));
}

/* ============================ output assembly ============================ */

function buildOutput(mode) {
    var prompt = buildPrompt();
    if (mode === 'prompt') return prompt;

    var json = JSON.stringify(buildJson(), null, 2);
    if (mode === 'json') {
        return 'Build the integration described by this specification.\n\n' +
               '<integration_spec format="json">\n' + json + '\n</integration_spec>\n\n' +
               'Read the JSON as the authoritative specification. Present a plan and wait ' +
               'for my approval before building anything. Ask about every entry in ' +
               'openQuestions rather than assuming a value.';
    }

    // both — prose for the human and the Spec Card, JSON as the source of truth
    return prompt + '\n\n' +
        '<integration_spec format="json">\n' + json + '\n</integration_spec>\n\n' +
        'The JSON above is the authoritative specification; the text above it is the ' +
        'human-readable rendering of the same answers. Where they differ, trust the JSON. ' +
        'A key that is absent was not specified — ask, do not assume.';
}

/* ============================ actions ============================ */

var previewFormat = 'both';

function openPreview() {
    var missing = missingRequired();
    var note = document.getElementById('pv-note');
    if (missing.length) {
        note.innerHTML = '<b>' + missing.length + ' required answer' + (missing.length > 1 ? 's are' : ' is') +
            ' still missing.</b> The prompt below is still usable &mdash; anything unanswered becomes an open ' +
            'question for the agent rather than a silent assumption. Missing: ' +
            missing.map(function (m) { return m.q.label; }).join(', ') + '.';
    } else {
        note.innerHTML = '<b>All required answers are complete.</b> Review the specification below, edit it if you ' +
            'like, then send it. The agent will present a plan and wait for your approval before building anything.';
    }
    renderOutput();
    document.getElementById('preview').hidden = false;
}

var FORMAT_WHY = {
    both:   'Recommended — the agent trusts the JSON, you and the approval card read the text.',
    prompt: 'Human-readable only. The agent infers values from prose.',
    json:   'Machine-readable only. Fastest for the agent, least readable for you.'
};

function renderOutput() {
    var txt = buildOutput(previewFormat);
    document.getElementById('pv-text').value = txt;
    // Persist every distinct specification the questionnaire produces.
    // Fire-and-forget: a failed save must never block review or sending.
    saveRun('trial', txt);
    document.getElementById('pv-stats').textContent =
        txt.split('\n').length + ' lines, ' + txt.length + ' characters';
    document.getElementById('pv-why').textContent = FORMAT_WHY[previewFormat] || '';
    var seg = document.getElementById('pv-format');
    [].forEach.call(seg.querySelectorAll('button'), function (b) {
        b.classList.toggle('on', b.dataset.fmt === previewFormat);
    });
}

function closePreview() { document.getElementById('preview').hidden = true; }

/* Hand the prompt to the chatbot for this namespace.
 *
 * Both this page and the chat run same-origin inside the Interop Editor,
 * so the prompt travels through localStorage (timestamped, single use) and
 * the parent is asked to open the chat panel. When this page is opened
 * standalone the chat is opened in a new tab instead. */
function sendToAIB(text) {
    saveRun('sent', text);
    var payload = {
        text: text,
        ns: currentNamespace(),
        ts: Date.now()
    };
    try {
        localStorage.setItem(HANDOFF_KEY, JSON.stringify(payload));
    } catch (e) {
        toast('Could not hand the specification to the chatbot: ' + e.message, true);
        return;
    }

    var embedded = false;
    try { embedded = window.parent && window.parent !== window; } catch (e) { embedded = false; }

    if (embedded) {
        try {
            window.parent.postMessage({ type: 'agentic:spec:send', namespace: currentNamespace() }, '*');
            closePreview();
            toast('Sent to the Agentic Integration Builder.');
            return;
        } catch (e) { /* fall through to new tab */ }
    }

    var url = '/agentic/chat/index.html?prefill=1&t=' + Date.now();
    var ns = currentNamespace();
    if (ns) url += '&namespace=' + encodeURIComponent(ns);
    window.open(url, '_blank');
    closePreview();
    toast('Opened the chatbot with your specification.');
}

function currentNamespace() {
    return (answers.namespace || '').trim() || qp('ns') || qp('namespace') || '';
}

/* ==================== describe-it-first (prompt -> form) ====================
 * The reverse of this page's normal direction. The user describes the
 * integration in prose; a lean extractor agent maps it onto the schema and
 * the form fills itself in. The user then VERIFIES — seeded fields are
 * visually marked, and nothing is built from the description itself. */

var API = '/api/agentic';
var AUTH_KEY = 'AGENTIC_AUTH';       // shared with the chat, so one login covers both
var EXTRACTOR = 'AgenticInterop.Agent.SpecExtractor';

var bridgeBearer = '';
var seededFields = {};   // fieldId -> true, for the "verify this" highlight

/* The host page (Interop Editor) holds the SPA's IRIS JWT. Ask for it the
 * same way chat.js does, so the questionnaire authenticates without a
 * second login. Falls back to whatever the chat stored locally. */
function fetchBridgeAuth() {
    return new Promise(function (resolve) {
        var done = false;
        function finish(p) { if (done) return; done = true; resolve(p || {}); }
        function listener(e) {
            var d = e.data || {};
            if (d && d.type === 'agentic:auth:response') {
                window.removeEventListener('message', listener);
                finish(d);
            }
        }
        window.addEventListener('message', listener);
        try { window.parent.postMessage({ type: 'agentic:auth:request' }, '*'); } catch (e) {}
        setTimeout(function () { window.removeEventListener('message', listener); finish({}); }, 1500);
    });
}

function authHeader() {
    if (bridgeBearer) return bridgeBearer;
    try { return localStorage.getItem(AUTH_KEY) || ''; } catch (e) { return ''; }
}

/* Serialize the CURRENT schema for the model — ids, types and the exact
 * option values it is allowed to return. Sent with every request rather
 * than baked into the agent, so a customer who adds, removes or relabels a
 * field gets correct extraction with no backend change. */
function schemaForLLM() {
    var out = [];
    SCHEMA.forEach(function (sec) {
        var qs = [];
        sec.questions.forEach(function (q) {
            var e = { id: q.id, label: q.label, type: q.type };
            if (q.options) e.allowedValues = q.options.map(function (o) { return o.v; });
            if (q.type === 'repeat') {
                e.rowFields = q.fields.map(function (f) {
                    var g = { id: f.id, label: f.label, type: f.type };
                    if (f.options) g.allowedValues = f.options.map(function (o) { return o.v; });
                    return g;
                });
            }
            qs.push(e);
        });
        out.push({ section: sec.id, title: sec.title, questions: qs });
    });
    return out;
}

/* Worked examples for the Example button. Demo material, but deliberately
 * realistic: each one is phrased the way an integration engineer actually
 * describes a feed, and each exercises a different path through the
 * extractor — TCP vs file, one destination vs several, HL7-to-HL7 vs
 * HL7-to-FHIR, mappings, code translations, ACK targets, dead-lettering.
 * Example 1 is the Epic-to-Quest case the product is scoped around. */
var DEMOS = [
    {
        title: 'Epic to Quest — the driving use case',
        text: 'Epic sends us HL7 v2.5 ADT^A01 admission messages over MLLP on port 5000. ' +
              'Quest needs them over MLLP at 10.20.4.15:6100, transformed to ORU^R01. ' +
              'From PID:3 take only the MRN whose assigning authority is USDMC, strip the ' +
              'dashes out of the SSN in PID:19, and set the sending application MSH:3 to EPIC. ' +
              'Messages for the same patient must stay in order. Anything that fails goes to ' +
              '/data/hl7/deadletter/ and should alert integration-ops@hospital.org.'
    },
    {
        title: 'File-based ADT routing, one to many, with ACKs',
        text: 'We pick up HL7 v2.5.1 ADT files from /data/hl7/in/ matching *.hl7 and archive ' +
              'them to /data/hl7/archive/. Route ADT^A01 and ADT^A08 to the LIS at ' +
              '10.1.4.22:6000 over MLLP, and also write a copy as files to ' +
              '/data/warehouse/out/ for the reporting warehouse. Only route messages where ' +
              'MSH:4 is USDMC. Translate the gender code: Male to M, Female to F, Unknown to U. ' +
              'We need application acknowledgments written to /data/hl7/ack/. Bad messages go ' +
              'to /data/hl7/deadletter/.'
    },
    {
        title: 'HL7 to FHIR pipeline',
        text: 'Take any HL7 v2.5.1 ADT or ORU message arriving on MLLP port 5100 and convert ' +
              'it to FHIR R4 using the built-in HL7 to SDA to FHIR pipeline, then POST the ' +
              'bundle to our FHIR server at https://fhir.internal.example.org/r4. Keep ' +
              'messages in order for the same patient. Anything that fails validation goes to ' +
              '/data/hl7/deadletter/ and should raise an alert to integration-ops@hospital.org.'
    },
    {
        title: 'Lab orders and results',
        text: 'Receive ORM^O01 lab orders from the EMR over MLLP on port 5200 and forward them ' +
              'to the lab system at 10.30.1.40:7100. Results come back as ORU^R01 on port 5201 ' +
              'and get written as files to /data/results/out/. Set OBX:11 to F for final ' +
              'results and copy the ordering provider from PV1:7 into OBR:16. Failures go to ' +
              '/data/hl7/deadletter/.'
    }
];
var demoIndex = -1;

function loadDemo() {
    demoIndex = (demoIndex + 1) % DEMOS.length;
    var d = DEMOS[demoIndex];
    var ta = document.getElementById('seed-text');
    ta.value = d.text;
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    seedNotes(null);
    seedStatus('Example ' + (demoIndex + 1) + ' of ' + DEMOS.length + ' — ' + d.title +
               '. Click Fill the form.', '');
    ta.scrollTop = 0;
}

function seedStatus(msg, kind, busy) {
    var el0 = document.getElementById('seed-status');
    el0.className = kind || '';
    el0.innerHTML = '';
    if (busy) el0.appendChild(el('span', 'spinner'));
    el0.appendChild(el('span', null, msg));
    el0.hidden = false;
}

function seedNotes(notes) {
    var box = document.getElementById('seed-notes');
    if (!notes || !notes.length) { box.hidden = true; return; }
    box.innerHTML = '';
    box.appendChild(el('b', null, 'Could not determine — please fill in'));
    var ul = document.createElement('ul');
    notes.forEach(function (n) { ul.appendChild(el('li', null, String(n))); });
    box.appendChild(ul);
    box.hidden = false;
}

/* Pull the JSON object out of the model's reply. The extractor is told to
 * return bare JSON, but models sometimes wrap it in a fence anyway, so
 * tolerate that rather than failing the whole flow. */
function parseExtraction(text) {
    if (!text) return null;
    var s = String(text).trim();
    s = s.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, '').trim();
    var start = s.indexOf('{');
    if (start < 0) return null;
    var depth = 0, inStr = false, esc = false;
    for (var i = start; i < s.length; i++) {
        var c = s[i];
        if (inStr) {
            if (esc) esc = false;
            else if (c === '\\') esc = true;
            else if (c === '"') inStr = false;
            continue;
        }
        if (c === '"') inStr = true;
        else if (c === '{') depth++;
        else if (c === '}') { depth--; if (depth === 0) { s = s.slice(start, i + 1); break; } }
    }
    try { return JSON.parse(s); } catch (e) { return null; }
}

/* Apply an extraction to the form. Only known ids are accepted, and an
 * option-backed field only accepts a listed value — a hallucinated field or
 * value is dropped rather than silently corrupting the form. */
function applyExtraction(data) {
    var applied = 0, rejected = [];
    seededFields = {};

    /* Normalise before applying. Models routinely put a multi-select field
     * (message types) under `repeats` because it holds several values, and
     * occasionally put a repeat group under `answers`. Both are the model
     * being reasonable about ambiguous wording, not a failure — so route by
     * what the SCHEMA says the field is, rather than dropping the value. */
    var ans = Object.assign({}, (data && data.answers) || {});
    var reps0 = Object.assign({}, (data && data.repeats) || {});
    Object.keys(reps0).forEach(function (id) {
        var q = findQ(id);
        if (q && q.type !== 'repeat') { ans[id] = reps0[id]; delete reps0[id]; }
    });
    Object.keys(ans).forEach(function (id) {
        var q = findQ(id);
        if (q && q.type === 'repeat' && Array.isArray(ans[id])) { reps0[id] = ans[id]; delete ans[id]; }
    });
    data = { answers: ans, repeats: reps0, notes: data && data.notes };
    Object.keys(ans).forEach(function (id) {
        var q = findQ(id);
        if (!q) { rejected.push(id); return; }
        var v = ans[id];
        if (q.options && q.type !== 'checkbox') {
            var ok = q.options.some(function (o) { return String(o.v) === String(v); });
            if (!ok) { rejected.push(id + '=' + v); return; }
        }
        if (q.type === 'checkbox') {
            var arr = Array.isArray(v) ? v : [v];
            arr = arr.filter(function (x) {
                return q.options.some(function (o) { return String(o.v) === String(x); });
            });
            if (!arr.length) { rejected.push(id); return; }
            answers[id] = arr;
        } else {
            answers[id] = v;
        }
        seededFields[id] = true;
        applied++;
    });

    var reps = reps0;
    Object.keys(reps).forEach(function (id) {
        var q = findQ(id);
        if (!q || q.type !== 'repeat' || !Array.isArray(reps[id]) || !reps[id].length) return;
        var rows = [];
        reps[id].forEach(function (src) {
            if (!src || typeof src !== 'object') return;
            var row = blankRow(q);
            var touched = false;
            q.fields.forEach(function (f) {
                if (src[f.id] === undefined || src[f.id] === null) return;
                var v = src[f.id];
                if (f.options) {
                    var ok = f.options.some(function (o) { return String(o.v) === String(v); });
                    if (!ok) { rejected.push(id + '.' + f.id + '=' + v); return; }
                }
                row[f.id] = v;
                touched = true;
            });
            if (touched) rows.push(row);
        });
        if (rows.length) { repeats[id] = rows; seededFields[id] = true; applied += rows.length; }
    });

    return { applied: applied, rejected: rejected };
}

async function seedFromPrompt() {
    var text = document.getElementById('seed-text').value.trim();
    if (!text) { seedStatus('Describe the interface first.', 'err'); return; }

    var btn = document.getElementById('seed-go');
    btn.disabled = true;
    seedNotes(null);
    seedStatus('Reading your description…', '', true);

    var message =
        'QUESTIONNAIRE SCHEMA:\n' + JSON.stringify(schemaForLLM()) +
        '\n\nDESCRIPTION:\n' + text +
        '\n\nReturn only the JSON object described in your instructions.';

    var headers = { 'Content-Type': 'application/json' };
    var auth = authHeader();
    if (auth) headers['Authorization'] = auth;
    var ns = currentNamespace();
    if (ns) headers['X-IRIS-Namespace'] = ns;

    try {
        var res = await fetch(API + '/chat?_t=' + Date.now(), {
            method: 'POST',
            headers: headers,
            credentials: 'include',
            body: JSON.stringify({ message: message, agentClass: EXTRACTOR, history: [] })
        });
        if (res.status === 401 || res.status === 403) {
            seedStatus('Not authorized. Open the chat once to sign in, then retry.', 'err');
            return;
        }
        if (!res.ok) { seedStatus('Request failed (HTTP ' + res.status + ').', 'err'); return; }

        var j = await res.json();
        if (!j.ok) { seedStatus(j.error ? String(j.error).slice(0, 160) : 'Extraction failed.', 'err'); return; }

        var data = parseExtraction(j.response);
        if (!data) { seedStatus('Could not read the response as structured data. Try rephrasing.', 'err'); return; }

        var r = applyExtraction(data);
        render();
        document.getElementById('form-pane').scrollTop = 0;

        if (!r.applied) {
            seedStatus('Nothing definite to fill in from that description.', 'err');
        } else {
            seedStatus(r.applied + ' field' + (r.applied > 1 ? 's' : '') + ' filled in — please verify.', 'ok');
        }
        var notes = Array.isArray(data.notes) ? data.notes.slice() : [];
        if (r.rejected.length) notes.push('Ignored ' + r.rejected.length + ' value(s) that did not match the form.');
        seedNotes(notes);
    } catch (e) {
        seedStatus('Could not reach the agent: ' + e.message, 'err');
    } finally {
        btn.disabled = false;
    }
}

/* ==================== saved runs ====================
 * Every specification this questionnaire generates is persisted with the
 * answers that produced it, so a run can be reloaded into the form or its
 * prompt re-read later. Saving is a side effect of generating or sending —
 * the user never has to remember to do it.
 *
 * Both halves are kept deliberately: the prompt alone cannot repopulate
 * the form, and the answers alone do not record what was actually sent
 * (the preview is editable). */

var lastSavedPrompt = '';   // avoids a new row each time Output Trial is re-opened unchanged

function apiHeaders(json) {
    var h = {};
    if (json) h['Content-Type'] = 'application/json';
    var auth = authHeader();
    if (auth) h['Authorization'] = auth;
    var ns = currentNamespace();
    if (ns) h['X-IRIS-Namespace'] = ns;
    return h;
}

/* Persist the current run. status: 'trial' when generated, 'sent' when
 * handed to the agent. Failure is reported but never blocks the user --
 * losing a saved copy must not stop them sending a specification. */
async function saveRun(status, promptText) {
    if (status === 'trial' && promptText === lastSavedPrompt) return null;

    var total = 0, done = 0;
    SCHEMA.forEach(function (sec) {
        sec.questions.forEach(function (q) {
            if (!q.required || !visible(q)) return;
            total++; if (answered(q)) done++;
        });
    });

    var body = {
        interfaceName: answers.name || '(unnamed)',
        shortName:     answers.shortName || '',
        namespace:     currentNamespace(),
        outputFormat:  previewFormat,
        status:        status,
        completeness:  done + '/' + total,
        templateKey:   'default',
        templateVersion: '1',
        answers:       { answers: answers, repeats: repeats },
        prompt:        promptText
    };

    try {
        var res = await fetch(API + '/spec/responses?_t=' + Date.now(), {
            method: 'POST', headers: apiHeaders(true),
            credentials: 'include', body: JSON.stringify(body)
        });
        if (!res.ok) { console.warn('spec save failed: HTTP ' + res.status); return null; }
        var j = await res.json();
        lastSavedPrompt = promptText;
        return j.id || null;
    } catch (e) {
        console.warn('spec save failed:', e.message);
        return null;
    }
}

async function openSaved() {
    document.getElementById('saved').hidden = false;
    document.getElementById('sv-list').innerHTML =
        '<div class="cp-empty">Loading saved specifications…</div>';
    await refreshSaved();
}

async function refreshSaved() {
    var mine = document.getElementById('sv-mine').checked ? '1' : '0';
    var list = document.getElementById('sv-list');
    try {
        var res = await fetch(API + '/spec/responses?mine=' + mine + '&_t=' + Date.now(),
                              { headers: apiHeaders(false), credentials: 'include' });
        if (res.status === 401 || res.status === 403) {
            list.innerHTML = '<div class="cp-empty">Not authorized. Open the chat once to sign in, then retry.</div>';
            return;
        }
        if (!res.ok) { list.innerHTML = '<div class="cp-empty">Could not load (HTTP ' + res.status + ').</div>'; return; }
        var j = await res.json();
        savedRows = j.responses || [];
        renderSaved();
    } catch (e) {
        list.innerHTML = '<div class="cp-empty">Could not reach the server: ' + e.message + '</div>';
    }
}

var savedRows = [];

function renderSaved() {
    var q = (document.getElementById('sv-q').value || '').toLowerCase().trim();
    var rows = savedRows.filter(function (r) {
        if (!q) return true;
        return ((r.interfaceName || '') + ' ' + (r.shortName || '') + ' ' + (r.username || ''))
               .toLowerCase().indexOf(q) >= 0;
    });
    document.getElementById('sv-count').textContent = rows.length + ' of ' + savedRows.length;

    var list = document.getElementById('sv-list');
    list.innerHTML = '';
    if (!rows.length) {
        list.appendChild(el('div', 'cp-empty',
            savedRows.length ? 'Nothing matches that filter.'
                             : 'No saved specifications yet. Generate one with Output Trial.'));
        return;
    }
    rows.forEach(function (r) {
        var item = el('div', 'sv-item');
        var main = el('div', 'sv-main');
        var name = el('div', 'sv-name', r.interfaceName || '(unnamed)');
        name.appendChild(el('span', 'sv-tag ' + (r.status === 'sent' ? 'sent' : 'trial'),
                            r.status === 'sent' ? 'sent to agent' : 'draft'));
        main.appendChild(name);
        main.appendChild(el('div', 'sv-meta',
            [r.createdAt, r.username, r.namespace,
             r.completeness ? r.completeness + ' answered' : '',
             r.outputFormat].filter(Boolean).join('  ·  ')));
        item.appendChild(main);

        var acts = el('div', 'sv-actions');
        var load = el('button', 'btn sm', 'Load');
        load.type = 'button';
        load.title = 'Restore these answers into the form';
        load.addEventListener('click', function () { loadRun(r.id); });
        acts.appendChild(load);

        var del = el('button', 'btn ghost sm', 'Delete');
        del.type = 'button';
        del.addEventListener('click', function () { deleteRun(r.id, r.interfaceName); });
        acts.appendChild(del);

        item.appendChild(acts);
        list.appendChild(item);
    });
}

async function loadRun(id) {
    try {
        var res = await fetch(API + '/spec/responses/' + encodeURIComponent(id) + '?_t=' + Date.now(),
                              { headers: apiHeaders(false), credentials: 'include' });
        if (!res.ok) { toast('Could not load that specification (HTTP ' + res.status + ').', true); return; }
        var j = await res.json();
        var a = j.answers || {};
        if (!a.answers) { toast('That saved run has no answers to restore.', true); return; }

        answers = a.answers;
        repeats = a.repeats || {};
        seededFields = {};
        // Any repeat group the saved run did not carry still needs one blank row.
        SCHEMA.forEach(function (sec) {
            sec.questions.forEach(function (q) {
                if (q.type === 'repeat' && (!repeats[q.id] || !repeats[q.id].length)) {
                    repeats[q.id] = [blankRow(q)];
                }
            });
        });
        lastSavedPrompt = j.prompt || '';
        closeSaved();
        render();
        document.getElementById('form-pane').scrollTop = 0;
        toast('Loaded "' + (j.interfaceName || 'specification') + '". Review before sending.');
    } catch (e) {
        toast('Could not load: ' + e.message, true);
    }
}

async function deleteRun(id, name) {
    if (!confirm('Delete the saved specification "' + (name || id) + '"?')) return;
    try {
        var res = await fetch(API + '/spec/responses/' + encodeURIComponent(id), {
            method: 'DELETE', headers: apiHeaders(false), credentials: 'include'
        });
        if (!res.ok) { toast('Delete failed (HTTP ' + res.status + ').', true); return; }
        await refreshSaved();
        toast('Deleted.');
    } catch (e) {
        toast('Delete failed: ' + e.message, true);
    }
}

function closeSaved() { document.getElementById('saved').hidden = true; }

/* ============================ boot ============================ */

async function boot() {
    // Namespace can be pre-seeded from the host page.
    var ns = qp('ns') || qp('namespace');
    if (ns) answers.namespace = ns;

    // Capture the host SPA's JWT up front so "Fill the form" works on the
    // first click rather than failing once and succeeding on retry.
    try {
        var bridge = await fetchBridgeAuth();
        if (bridge && bridge.bearer) bridgeBearer = bridge.bearer;
        if (!ns && bridge && bridge.namespace) answers.namespace = bridge.namespace;
    } catch (e) {}

    initDefaults();
    render();

    var pill = document.getElementById('ns-pill');
    pill.textContent = currentNamespace() || 'namespace not set';

    document.getElementById('btn-trial').addEventListener('click', openPreview);

    // Describe-it-first: prose in, structured form out, user verifies.
    document.getElementById('seed-go').addEventListener('click', seedFromPrompt);
    document.getElementById('seed-demo').addEventListener('click', loadDemo);
    document.getElementById('seed-text').addEventListener('keydown', function (e) {
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') seedFromPrompt();
    });
    document.getElementById('seed-clear').addEventListener('click', function () {
        document.getElementById('seed-text').value = '';
        document.getElementById('seed-status').hidden = true;
        document.getElementById('seed-notes').hidden = true;
        demoIndex = -1;   // next Example starts the cycle again at the first one
    });

    document.getElementById('btn-send').addEventListener('click', function () {
        var missing = missingRequired();
        if (missing.length) {
            // Do not block — but make the user look at it once.
            openPreview();
            toast(missing.length + ' required answer' + (missing.length > 1 ? 's' : '') +
                  ' missing — review before sending.', true);
            return;
        }
        sendToAIB(buildOutput(previewFormat));
    });

    // Output-format selector inside the preview.
    document.getElementById('pv-format').addEventListener('click', function (e) {
        var b = e.target.closest('button[data-fmt]');
        if (!b) return;
        previewFormat = b.dataset.fmt;
        renderOutput();
    });

    document.getElementById('btn-reset').addEventListener('click', function () {
        if (!confirm('Clear every answer and start over?')) return;
        answers = {};
        repeats = {};
        seededFields = {};
        document.getElementById('seed-status').hidden = true;
        document.getElementById('seed-notes').hidden = true;
        var ns2 = qp('ns') || qp('namespace');
        if (ns2) answers.namespace = ns2;
        initDefaults();
        render();
        toast('Form cleared.');
    });

    document.getElementById('pv-close').addEventListener('click', closePreview);
    document.getElementById('pv-back').addEventListener('click', closePreview);
    document.getElementById('pv-send').addEventListener('click', function () {
        sendToAIB(document.getElementById('pv-text').value);
    });
    document.getElementById('pv-copy').addEventListener('click', function () {
        var ta = document.getElementById('pv-text');
        ta.select();
        try {
            navigator.clipboard.writeText(ta.value);
            toast('Specification copied to the clipboard.');
        } catch (e) {
            document.execCommand('copy');
            toast('Specification copied.');
        }
    });

    document.getElementById('expand-all').addEventListener('click', function () {
        SCHEMA.forEach(function (s) { sectionOpen[s.id] = true; });
        render();
    });
    document.getElementById('collapse-all').addEventListener('click', function () {
        SCHEMA.forEach(function (s) { sectionOpen[s.id] = false; });
        render();
        document.getElementById('form-pane').scrollTop = 0;
    });

    document.getElementById('open-saved').addEventListener('click', openSaved);
    document.getElementById('sv-close').addEventListener('click', closeSaved);
    document.getElementById('sv-cancel').addEventListener('click', closeSaved);
    document.getElementById('sv-q').addEventListener('input', renderSaved);
    document.getElementById('sv-mine').addEventListener('change', refreshSaved);
    document.getElementById('saved').addEventListener('click', function (e) {
        if (e.target.id === 'saved') closeSaved();
    });

    // Catalog picker wiring
    document.getElementById('cp-close').addEventListener('click', closeCatalogPicker);
    document.getElementById('cp-cancel').addEventListener('click', closeCatalogPicker);
    document.getElementById('cp-q').addEventListener('input', function (e) {
        renderCatalogList(e.target.value);
    });
    document.getElementById('catpick').addEventListener('click', function (e) {
        if (e.target.id === 'catpick') closeCatalogPicker();
    });

    document.addEventListener('keydown', function (e) {
        if (e.key !== 'Escape') return;
        if (!document.getElementById('saved').hidden) { closeSaved(); return; }
        if (!document.getElementById('catpick').hidden) { closeCatalogPicker(); return; }
        if (!document.getElementById('preview').hidden) closePreview();
    });

    // Keep the namespace pill in step with the namespace answer.
    setInterval(function () {
        var v = currentNamespace() || 'namespace not set';
        if (pill.textContent !== v) pill.textContent = v;
    }, 600);
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();

})();
