/* Interface Specification Builder — agentic_interop
 *
 * A schema-driven questionnaire that collects everything Health Connect
 * needs to build an interface, then renders it as a [[SPEC]] prompt for
 * the Health Interop agent (AIB).
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
              { v: 'builtin', l: 'Use built-in SDA pipeline' },
              { v: 'dtl',     l: 'Custom DTL' },
              { v: 'bpl',     l: 'BPL orchestration' }
          ] },
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

/* ============================ state ============================ */

var answers = {};
var repeats = {};   // questionId -> array of row objects

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

function renderSection(sec) {
    var wrap = el('section', 'section' + (sec.collapsed ? ' collapsed' : ''));
    wrap.id = 'sec-' + sec.id;

    var head = el('div', 'section-head');
    head.appendChild(el('h3', null, sec.title));
    head.appendChild(el('span', 'tier', sec.tier));
    head.appendChild(el('span', 'caret', '▼'));
    head.addEventListener('click', function () { wrap.classList.toggle('collapsed'); });
    wrap.appendChild(head);

    if (sec.help) wrap.appendChild(el('div', 'section-help', sec.help));

    var body = el('div', 'section-body');
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
    if (q.hint) lab.appendChild(el('span', 'hint', q.hint));
    if (q.why)  lab.appendChild(el('span', 'why', q.why));
    return lab;
}

function renderQuestion(q) {
    var f = el('div', 'field');
    f.dataset.qid = q.id;

    if (q.type === 'repeat') {
        var lw = el('div', 'flabel', q.label);
        if (q.required) lw.appendChild(el('span', 'req', '*'));
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

            if (fl.type === 'select') {
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

function renderDerived() {
    var n = names();
    var d = el('div', 'derived');
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
    renderRail();
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

    return L.join('\n');
}

/* ============================ actions ============================ */

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
    var txt = buildPrompt();
    document.getElementById('pv-text').value = txt;
    document.getElementById('pv-stats').textContent =
        txt.split('\n').length + ' lines, ' + txt.length + ' characters';
    document.getElementById('preview').hidden = false;
}

function closePreview() { document.getElementById('preview').hidden = true; }

/* Hand the prompt to the chatbot for this namespace.
 *
 * Both this page and the chat run same-origin inside the Interop Editor,
 * so the prompt travels through localStorage (timestamped, single use) and
 * the parent is asked to open the chat panel. When this page is opened
 * standalone the chat is opened in a new tab instead. */
function sendToAIB(text) {
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

/* ============================ boot ============================ */

function boot() {
    // Namespace can be pre-seeded from the host page.
    var ns = qp('ns') || qp('namespace');
    if (ns) answers.namespace = ns;

    initDefaults();
    render();

    var pill = document.getElementById('ns-pill');
    pill.textContent = currentNamespace() || 'namespace not set';

    document.getElementById('btn-trial').addEventListener('click', openPreview);

    document.getElementById('btn-send').addEventListener('click', function () {
        var missing = missingRequired();
        if (missing.length) {
            // Do not block — but make the user look at it once.
            openPreview();
            toast(missing.length + ' required answer' + (missing.length > 1 ? 's' : '') +
                  ' missing — review before sending.', true);
            return;
        }
        sendToAIB(buildPrompt());
    });

    document.getElementById('btn-reset').addEventListener('click', function () {
        if (!confirm('Clear every answer and start over?')) return;
        answers = {};
        repeats = {};
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

    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && !document.getElementById('preview').hidden) closePreview();
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
