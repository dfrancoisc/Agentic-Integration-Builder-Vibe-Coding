# Integration Specification Builder — High-Level Application Design

> **Working name:** Integration Specification Builder (ISB)
> **Relationship:** a new front-end application for the existing **Agentic Integration Builder** (`Agentic Integration Builder`). It does not replace the chatbot — it feeds it.
> **Platform:** InterSystems Health Connect / IRIS for Health 2026.2+, on the AI Hub (`%AI`) foundation
> **Version:** 0.1 (design for review) · July 2026
> **Grounded in:** `Agentic Integration Builder` @ `9a678b6` — tool signatures (`Tool/Production.cls`, `Tool/Transform.cls`, `Tool/Testing.cls`), the `HealthInterop.cls` INSTRUCTIONS gap-check contract, the skill catalog, and the `[[SPEC]]` workflow.

---

## 1. The idea, sharpened

### 1.1 The problem

Customers struggle to *build* interfaces. They struggle even more to **specify** them. A vague spec produces one of two bad outcomes: a long clarification loop with the agent, or — worse — an interface built on silent assumptions that fails in ways nobody notices until production (an ACK that lands nowhere, a routing rule that never matches, a DTL that emits only an MSH segment).

The attachment workflow already lets a customer upload a Statement of Work. But that only works if the SoW is *good*. Most aren't. They were written for humans, and they omit exactly the decisions Health Connect needs.

### 1.2 The reversal

Instead of hoping the customer's document contains the right information, **we define what a complete integration specification is, and give them a form that collects it.**

The critical realization is that **we do not have to invent that definition** — the agent already contains it. `HealthInterop.cls` has a mandatory "CHECK FOR GAPS" step that enumerates, in the agent's own words, every decision it must *never* silently default:

> Use your skills to catch the common easily-missed sub-decisions: **ACK target + mode for file/FTP services, dead-letter / bad-message destination and handler, retry interval + failure timeout for operations (healthcare default FailureTimeout=-1), pool size when FIFO matters, MessageSchemaCategory on the inbound service, archive path for file pickups, and the segment terminator on HL7-to-HL7 DTL targets.**

Plus the hard "never assume" list: transport, HL7 version, `MessageSchemaCategory`.

That list *is* the specification schema. The tools' input parameters are the rest of it. **The questionnaire is the agent's own gap-check list, externalized into a UI and answered up front instead of discovered mid-conversation.**

### 1.3 Why this is more than a form

Three properties make this genuinely valuable rather than just data entry:

1. **Grounded by construction.** Options are populated from the live instance and the vector catalog — real namespaces, real productions, real HL7 schema categories, real SSL configs and credentials, real candidate host classes. The customer can only specify things that exist. This eliminates a whole class of hallucination and rework *before* the agent runs.
2. **It teaches while it collects.** The form is a latent training device. A customer who fills it in three times has learned what Health Connect actually needs — ACK semantics, dead-letter strategy, FIFO implications — without reading a manual. That is a real product benefit for the non-developer Interface Engineer persona.
3. **It removes the ask-back round-trip.** Because the form pre-answers the gap-check items, the agent can go straight from spec to plan instead of spending a turn asking. Fewer turns means less latency, fewer tokens, and less chance of the conversation drifting.

### 1.4 The one tension to manage

"Simple" and "covers all of Health Connect" pull against each other. The resolution is **progressive disclosure driven by a schema**: an Essential path of ~12 questions, with Advanced sections revealed *conditionally* (no MLLP port unless transport is TCP; no ACK-target question unless the inbound is file-based and application ACKs were requested). Configurability then falls out for free — if the form is defined by a JSON schema, letting customers add/remove/relabel fields is just editing that schema.

### 1.5 We are not starting from zero

A survey of the InterSystems documentation found three existing artifacts this application should build on rather than reinvent. This materially strengthens the proposal: the questionnaire is not an InterSystems-invented novelty, it is **documented best practice made executable.**

**1. The "production spreadsheet" is already an official interface intake template.**
*(`Best Practices for Creating Productions` §2.3)* — one row per application feed, with columns: **Feed** · **Application** (including *who to contact* about issues) · **Name** (unique 3–6 character short name) · **Type** (protocol) · **Connection** (IP and port) · **Sends** · **Receives** · **ACKs**. It even carries the guidance our form needs: a message structure routed differently per destination *"should be listed multiple times, with a note regarding the differences,"* and the ACKs column must record *"Should the production generate the ACKs and NACKs, or will the receiving application do so?"* Sections S1, S3 and S4 should be recognisably this spreadsheet, expanded.

**2. A machine-consumable interface-route schema already exists.**
*(`HL7 Productivity Tools` §2 — the HL7 Production Generator)* — a configuration file of naming conventions plus an **items file where one row = one interface route**, using the column grammar `S:` / `S:A:` / `S:H:` (service, service adapter, service host), `O:` / `O:A:` / `O:H:` (operation), `P:` (router), `R:` (rule), `T:` (transformation), plus bare columns `SourceType`, `SourceSchema`, `TargetType`, `TargetSchema`, `ServiceType`, `OperationType`. `EnsLib.InteropTools.HL7.ProductionGenerator.Load()` turns it into a production, and is re-runnable to update one. This is InterSystems' own canonical representation of "one interface route" — our output should be able to emit it (see §7).

**3. Naming conventions and modularity rules are prescribed, not optional.**
*(`Best Practices` §2.4–2.5)* — `From<SourceApp>` · `To<TargetApp>` · `<SourceApp>Router` · `<SourceApp>Rules` · `<SourceApp><SrcType>To<TargetApp><TgtType>`; and structurally: **one business service per sending application, one routing process per business service, one business operation per receiving application.** The documentation is emphatic about why — *"Each addition to a routing process that is already in production might require you to retest and validate hundreds of existing rules."* The form should generate names automatically from these rules and shape its repeatable groups to enforce the modularity model.

Two further documented assets are worth wiring in later: the **HL7 Message Analyzer** (`##class(EnsLib.InteropTools.HL7.MessageAnalyzer).Interactive()`), which derives a custom schema from a folder of real sample messages — the empirical path when a customer has no implementation guide at all; and the four **deployment checklists** (capacity/performance, robustness, security, maintenance) in `Preparing to Create Productions` §2, which map directly onto our non-functional sections S8–S13.

---

## 2. Where it sits

```
┌──────────────────────────────────────────────────────────────┐
│  Integration Specification Builder   /agentic/spec/          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Schema-driven questionnaire (sections → questions)     │  │
│  │ Options pre-filled from environment + vector catalog   │  │
│  └────────────────────────────────────────────────────────┘  │
│                            │ answers (JSON)                  │
│                            ▼                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Spec Renderer → [[SPEC]] block + ## Confirmed defaults │  │
│  │                 + <questionnaire> JSON payload         │  │
│  └────────────────────────────────────────────────────────┘  │
└────────────────────────────┬─────────────────────────────────┘
                             │ POST /api/agentic/chat/stream
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Existing chatbot  /agentic/chat/  →  HealthInterop agent    │
│  NEW: Skill.InterfaceSpec interprets the questionnaire       │
│  → Spec Card (Approve/Edit) → plan → gate → build → validate │
└──────────────────────────────────────────────────────────────┘
```

**Nothing downstream changes.** The form emits into the `[[SPEC]]` contract the agent already understands, renders as the existing Spec Card, and enters the existing plan → approve → build → validate loop. The new Skill teaches the agent to read a *structured* questionnaire rather than prose.

---

## 3. Design principles

| # | Principle | Consequence |
|---|---|---|
| 1 | **The questionnaire is the gap-check list** | Every question traces to a tool parameter or a documented agent gap item. No question exists "because it seems useful." |
| 2 | **Grounded options, not free text** | Anything that could be enumerated from the instance or catalog is a dropdown, not a textbox. |
| 3 | **Progressive disclosure** | Essential / Recommended / Advanced tiers. Conditional reveal. Never show an irrelevant question. |
| 4 | **Recommend, don't blank** | Every field with a defensible healthcare default is pre-set to it, labelled *"recommended — change if needed"* (mirrors the agent's own behavior). |
| 5 | **Schema-driven = configurable** | The form is data. Customers edit sections, labels, options, and defaults without code. |
| 6 | **Unknown is a valid answer** | "I don't know" routes the item into the spec's **Open questions** so the agent asks — far better than a wrong guess. |
| 7 | **Emit into the existing contract** | Output is a valid `[[SPEC]]` block. No new agent path, no new approval UX. |
| 8 | **Follow documented InterSystems convention** | Names auto-generated per `Best Practices` §2.5; form structure enforces the §2.4 modularity model; output can emit the Production Generator items-file grammar. We implement the documented practice rather than inventing a parallel one. |

---

## 4. The questionnaire model

### 4.1 Structure

A template is a versioned JSON document:

```
Template
 └── Section[]        id, title, help, tier, condition
      └── Question[]  id, label, help, type, tier, required,
                      options | optionsSource, default, condition,
                      mapsTo   ← the tool parameter / setting it feeds
```

`mapsTo` is the important field: it binds each answer to the concrete Health Connect artifact it produces (e.g. `service.Adapter.Port`, `service.Host.MessageSchemaCategory`, `router.Host.BadMessageHandler`). This is what makes the renderer deterministic and the skill's job easy.

Question types: `text`, `textarea`, `number`, `select`, `multiselect`, `checkbox`, `radio`, `repeatable-group`, `key-value-table`, `mapping-table`, `file-upload`.

### 4.2 Tiers

- **Essential** — the ~12 questions without which nothing can be built. Always visible.
- **Recommended** — has a safe healthcare default, pre-filled, collapsed but one click away.
- **Advanced** — expert settings, hidden unless expanded or made relevant by a condition.

### 4.3 Section-by-section field taxonomy

Every field below traces to a real tool parameter or agent gap item. `E` = Essential, `R` = Recommended, `A` = Advanced.

#### S1 — Interface identity & deployment
| Field | Tier | Type / source | Maps to |
|---|---|---|---|
| Interface name | E | text | production/host naming |
| **Short name (3–6 chars)** | E | text, validated | naming convention seed ← *`Best Practices` §2.3 "Name" column* |
| Business purpose | E | textarea | spec Overview |
| **Contact / owner for this feed** | R | text | ← *`Best Practices` §2.3 "Application" column* |
| Target namespace | E | select ← live namespaces, **Foundation-validated** | `X-IRIS-Namespace` |
| Production | E | select ← `ListProductions` + "Create new" | `CreateProduction.name` |
| Environment | R | radio: dev/test/prod | System Default Settings scope |
| Owner / requester, go-live date | A | text, date | spec metadata |

#### S2 — Integration pattern
| Field | Tier | Type | Notes |
|---|---|---|---|
| Pattern | E | radio | Point-to-point · One-to-many fan-out · Many-to-one · Route + transform · ESB passthrough · Request-reply · Enrichment (lookup/SQL) |

Pattern drives which later sections appear (fan-out ⇒ routing section becomes mandatory; enrichment ⇒ S7 appears).

#### S3 — Source (inbound)
| Field | Tier | Type / source | Maps to |
|---|---|---|---|
| Source system name / vendor | E | text | naming, spec |
| Data standard | E | select: HL7 v2 · FHIR R4 · X12 · CDA/C-CDA · SDA3 · Delimited/flat · XML/JSON · DICOM · Custom | host class family |
| **HL7 schema category** | E | select ← installed schemas (`2.3.1…2.8`, custom `MyApp:2.5`) | `MessageSchemaCategory` ← *agent gap item* |
| Message types / trigger events | E | multiselect (ADT^A01, ORU^R01, …) | routing constraints, `docName` |
| Custom Z-segments? + schema file | A | checkbox + upload | custom schema load |
| **Transport** | E | select: MLLP/TCP · File · FTP/SFTP · HTTP/REST · SOAP · SQL poll · MQTT | service class ← *agent never-assume item* |
| ↳ TCP: Port | E | number | `Adapter.Port` |
| ↳ TCP: Framing, JobPerConnection, StayConnected, AllowedIPAddresses, SSLConfig | R/A | select ← framing enum; SSL ← configured SSL configs | `ConfigureHL7TCPService` |
| ↳ File: FilePath, FileSpec | E | text (`*.hl7`) | `Adapter.FilePath/FileSpec` |
| ↳ **File: ArchivePath** | R | text | `ArchivePath` ← *agent gap item* |
| ↳ File: WorkPath, Charset | A | text/select | adapter |
| ↳ FTP: server, port, path, Credentials, SSLConfig, passive | E/R | text + select ← credentials registry | FTP adapter |
| ↳ REST/HTTP: endpoint, port, auth (none/Basic/OAuth), SSLConfig | E/R | mixed | REST service |
| ↳ SQL: DSN, Query, poll interval | E | select ← DSNs + textarea | SQL adapter |
| ↳ MQTT: Url, Topic, ClientID, QOS, CleanSession | E/R | mixed | MQTT adapter |
| **ACK mode** | E | select: Never · Immediate · Application · MSH-determined | `AckMode` ← *agent gap item* |
| **ACK target** (shown only if file/FTP + Application) | E* | select ← hosts / "create ack operation" | `AckTargetConfigNames` ← *the canonical trap* |
| Batch handling + AutoBatchParentSegs | R | select pair | `BatchHandling` (flag duplicate-output default) |
| Validation flags | A | text (default `""`) | `Validation=""` recommended |
| Expected volume / peak / message size | R | number | informs pool sizing |
| **Ordering (FIFO) required?** | R | checkbox | `PoolSize=1` ← *agent gap item* |
| Availability window / schedule | A | text | `Schedule` |

#### S4 — Destinations (repeatable group, 1..n)
| Field | Tier | Type / source | Maps to |
|---|---|---|---|
| Target system name | E | text | host name |
| Output format | E | select (same standards list) | operation class |
| Transport + settings | E | conditional (mirrors S3, outbound variants) | `ConfigureHL7TCPOperation` etc. |
| Which messages route here | E | condition builder (message type, MSH:4 sending facility, field predicate) | routing rule constraint/condition |
| Transformation applied | R | select ← S6 mappings / none | `<send transform=…>` |
| Reply expected / ReplyCodeActions | R | checkbox + text (healthcare default) | `GetReply`, `ReplyCodeActions` |
| **Retry interval + Failure timeout** | R | number (default `-1`) | ← *agent gap item; healthcare default `FailureTimeout=-1`* |

#### S5 — Routing, filtering & dead-letter
| Field | Tier | Type | Maps to |
|---|---|---|---|
| Routing rules | E (if >1 target) | rule table: name · when · send to · transform | `CreateRoutingRule` XML |
| Filter / suppress rules | R | rule table | rule `<when>` without send |
| **Dead-letter / bad-message destination** | E | select ← hosts / "create file operation" | `BadMessageHandler` ← *agent gap item* |
| On transform error | R | select: Log · Ignore · Suspend · Disable · BangError | `ActOnTransformError` |

#### S6 — Transformation & mapping
| Field | Tier | Type | Maps to |
|---|---|---|---|
| Transformation required? | E | checkbox | — |
| Source → target format pair | E | derived from S3/S4 | `DescribeTransformationPipeline` |
| Approach | R | radio: Built-in SDA pipeline · Custom DTL · Passthrough · BPL orchestration | tool selection |
| Field mappings | E | mapping table **or spreadsheet upload** — rows: source path · target path · action (copy-segment · copy-field · set constant · concat · copy-all-components) · value · condition | `BuildDTLXml.mappingsJson` |
| Code translations | R | key-value table or upload | lookup tables |
| **Segment terminator (HL7→HL7)** | R | checkbox, default on | ← *agent gap item; the "only MSH written" trap* |
| Fields to suppress / exclude | A | multiselect | DTL |

> The mapping table maps **1:1** onto `BuildDTLXml`'s five action kinds. This is the single highest-value part of the form — field mappings are the most common source of spec ambiguity, and a structured table removes it entirely.

#### S7 — Enrichment (conditional on pattern)
Source table/query, match keys, fields to enrich, behavior on lookup miss (alert / dead-letter / pass through).

#### S8 — Error handling, alerting & operations
Alert on error; alert recipients / `Ens.Alert` route; alert grace period; queue count & wait alerts; trace level; suspend vs. discard policy.

#### S9 — Performance & reliability
Pool size (default = CPU count; forced to 1 if FIFO), actor pool size, throughput target, latency SLA, HA/failover expectations.

#### S10 — Security
SSL/TLS configs, credentials, OAuth client + scope, IP allow-list, PHI sensitivity, de-identification requirement.

#### S11 — Persistence & retention
Message retention/purge policy, archiving, **search tables** (property · expression · docType · type) → `CreateHL7SearchTable`.

#### S12 — Testing & acceptance
Sample messages (upload), test scenarios, acceptance criteria, sign-off owner, test namespace → drives `BuildAndSendHL7TestMessage`.

#### S13 — Deployment & change control
Promotion path (dev→test→prod), which settings vary per environment → **System Default Settings**, source control expectations, naming conventions. Sections S8–S13 collectively answer the four documented deployment checklists in `Preparing to Create Productions` §2 (capacity/performance, robustness, security, maintenance).

### 4.4 Structure enforces the documented modularity model

The form's shape is not arbitrary — it encodes `Best Practices` §2.4:

- **One business service per sending application.** S3 is captured once per source; a second inbound port justifies a second interface, not a second service on the same one.
- **One routing process per business service.** The router in S5 is scoped to this interface, never shared. The documentation is explicit that a single large shared router is the anti-pattern.
- **One business operation per receiving application.** S4 is a repeatable group — each destination produces its own operation.

Names are then **auto-generated and shown read-only** (with an override): service `From<SourceApp>`, operation `To<TargetApp>`, router `<SourceApp>Router`, rule set `<SourceApp>Rules`, transform `<SourceApp><SrcType>To<TargetApp><TgtType>`. This removes a whole category of naming drift, and matters practically because the agent's build sequence requires that artifact names stay identical between plan and build.

### 4.5 The Essential path

For a first-time user the form should ask only these, with everything else defaulted and collapsed:

1. Interface name · 2. Business purpose · 3. Namespace · 4. Production · 5. Pattern
6. Source standard + HL7 version · 7. Message types · 8. Source transport + its one or two required settings
9. Destination(s) + transport · 10. Transformation needed? (+ mappings if yes)
11. Dead-letter destination · 12. ACK mode

Everything else is pre-answered with recommended healthcare defaults and shown as a reviewable summary before submission.

---

## 5. Environment & catalog-driven prefill

| Option source | Backed by | Populates |
|---|---|---|
| Namespaces | `GetUserNamespace` + namespace list | S1 namespace |
| Productions | `ListProductions` | S1 production |
| Existing business hosts | `GetProduction` | ACK target, dead-letter target, routing targets |
| HL7 schema categories | installed schemas | S3 schema category |
| Candidate host classes | **`search_ens` vector catalog** | transport → recommended class, shown with rationale |
| Existing transformations | **`search_hs`** + `ListDTLs` / `ListSDAFHIRDTLs` | S6 reuse-before-create |
| Lookup tables | `ListLookupTables` | S6 code translations |
| SSL configs / credentials | IRIS security registry | S3/S4/S10 |
| HL7 schema paths | `GetHL7SchemaMap` | S6 mapping table autocomplete |
| Foundation namespace check | `HS.Util.Installer.ConfigItem` | S1 — warn if the chosen namespace is not a Foundation namespace (required for healthcare productions) |
| Derived custom schema | **HL7 Message Analyzer** (`EnsLib.InteropTools.HL7.MessageAnalyzer`) | S3 — the "I have no spec, only sample messages" path |

Two of these deserve emphasis:

- **`search_ens` turns transport into a recommendation.** The user picks "MLLP/TCP"; the form calls the catalog and shows *"Recommended: `EnsLib.HL7.Service.TCPService` — matched from your instance catalog"*. The user never types a class name.
- **`GetHL7SchemaMap` powers mapping autocomplete.** When the user builds the field-mapping table, source and target path pickers are populated with the *exact* `dtlPath` values for the chosen message structures. This structurally prevents the guessed-path failure the agent's prompt warns about (flat `PID:` vs nested `PIDgrpgrp(1).PIDgrp.PID`).

---

## 6. Configurability

Customers can add, remove, relabel, reorder, and re-default anything, because the form is data.

- **Template editor** in the admin UI: edit sections/questions, change labels and help text, set defaults, mark tier, define conditions, and choose an option source.
- **Versioned templates** — editing creates a new version; submitted responses record the template version they were captured against.
- **Archetype library** — ship several starting templates rather than one giant form: *HL7 v2 feed*, *HL7 one-to-many routing*, *HL7→FHIR pipeline*, *X12 claims*, *CDA ingest*, *File drop / passthrough*, *REST integration*. Each is the same schema with different sections enabled.
- **Guardrail:** questions carrying a `mapsTo` that the build tools require are marked **system-required** — customers may relabel or re-help them, but not delete them. Deleting `MessageSchemaCategory` would silently reintroduce the exact failure the form exists to prevent.

---

## 7. Output contract

On submit the application emits **three layers in one message**:

1. **The `[[SPEC]] … [[/SPEC]]` block** in the agent's existing template — `# Project Specification`, `## Overview`, `## Exercises` (Goal / Inputs / Outputs / Transformation rules / Routing rules / Acceptance criteria), `## Open questions`, `## Build tasks (post-approval)`. Renders as the existing Spec Card with Approve/Edit.
2. **A `## Confirmed defaults` section** *(new)* — explicitly pre-answering the seven commonly-missed sub-decisions, so the agent skips its ask-back turn:
   ```
   ## Confirmed defaults
   - ACK mode: Application; ACK target: ADT.Ack.File (/data/hl7-ack/)
   - Dead-letter: DeadLetter.File (/data/deadletter/)
   - Retry interval 30s; FailureTimeout -1 (healthcare default)
   - Pool size 1 (FIFO ordering required)
   - MessageSchemaCategory: 2.5.1
   - Archive path: /data/archive/
   - HL7→HL7 target segment terminator: CR (stamped)
   ```
3. **A machine-readable payload** — the canonical answers, wrapped like the existing attachment convention so the agent sees it as structured data:
   ```
   <questionnaire template="hl7-feed" version="3">{ …answers JSON… }</questionnaire>
   ```

Anything the user answered "I don't know" appears under **Open questions** — never as a silent default.

### 7.1 A fourth output: the Production Generator items file

Because the questionnaire captures one row per interface route, it can *also* export the **HL7 Production Generator items file** (`HL7 Productivity Tools` §2) — the CSV grammar InterSystems already ships a generator for:

```
ServiceName,ServiceType,OperationName,OperationType,SourceSchema,SourceType,TargetSchema,TargetType,
S:A:FileSpec,S:H:MessageSchemaCategory,O:H:FailureTimeout,P:Category,RuleDisabled,NoTransformation
```

This is strategically useful for three reasons:

1. **A non-AI fallback path.** A customer who cannot or will not run an LLM against their instance can still take the questionnaire output and feed it to `EnsLib.InteropTools.HL7.ProductionGenerator.Load()`. The form delivers value with or without the agent.
2. **Validation of our own output.** If the questionnaire cannot fill the items-file columns, it is missing something the platform considers essential — a useful completeness check on the schema.
3. **Coarse-to-fine build.** The generator can scaffold the skeleton deterministically; the agent then layers on the parts the generator does not handle (DTL field mappings, rule logic, lookup tables) — where it adds the most value. Worth evaluating as the default build strategy.

---

## 8. The new Skill

**`AgenticInterop.Skill.InterfaceSpec`** (`name: interface_spec`), following the established pattern: `Extends AgenticInterop.Skill.Base`, `Parameter TOOLS`, `XData SUMMARY` (yaml), `XData INSTRUCTIONS` (markdown). Registered by appending to `Parameter SKILLS` on `HealthInterop` (and optionally `DEFAULTSKILLS` on `SkillLoader`).

Its INSTRUCTIONS must teach four things:

**1. How to read the questionnaire.** The `<questionnaire>` payload is authoritative and takes precedence over prose. Each answer's `mapsTo` names the artifact/setting it produces.

**2. How to translate answers into Health Connect artifacts.** The mapping table from answer → host class → host/adapter setting split → which tool builds it. This is where the skill earns its keep: transport `MLLP/TCP` + standard `HL7 v2` ⇒ `EnsLib.HL7.Service.TCPService` via `ConfigureHL7TCPService`, with `Port` at Adapter level and `MessageSchemaCategory` at Host level.

**3. Cross-field validation rules** — the combinations that are individually valid but jointly broken. These are the highest-value content in the skill:

| Condition | Required consequence |
|---|---|
| File/FTP inbound + `AckMode=Application` | `AckTargetConfigNames` destination is mandatory |
| Downstream does HL7→SDA | schema category must be `2.5.1` |
| More than one destination | router + compiled rule class + `BusinessRuleName` required |
| Any HL7 routing engine | `Validation=""` |
| FIFO ordering required | `PoolSize=1` |
| HL7→HL7 DTL with `create='new'` | segment terminator must be stamped |
| Routing rule for a transforming flow | constraint matches the **incoming** type; DTL goes on `<send>` |
| Any HL7 inbound service | `MessageSchemaCategory` set, else no rule ever matches |
| Any file host path | `EnsureDirectory` for inbound, outbound, archive, dead-letter |

**4. What to do with gaps.** Unanswered or "unknown" items are surfaced as focused questions *before* planning — never silently defaulted. If `## Confirmed defaults` is present, do not re-ask those items.

---

## 9. Application architecture

**UI** — new CSP page at `/agentic/spec/` (vanilla JS + CSS, matching the existing admin/chat dark theme; no framework, no icons per house style). Left rail = sections with completion state; main pane = current section; sticky footer = *Review spec* / *Send to agent*.

**REST** (under the existing `/api/agentic/` dispatcher, `UseSession=0`):
| Endpoint | Purpose |
|---|---|
| `GET /spec/templates` · `GET/PUT /spec/templates/:id` | template CRUD (versioned) |
| `GET /spec/options/:source` | prefill lookups (namespaces, productions, hosts, schemas, SSL, credentials, catalog search) |
| `POST /spec/responses` · `GET/PUT /spec/responses/:id` | save/resume a draft answer set |
| `POST /spec/responses/:id/render` | answers → `[[SPEC]]` + Confirmed defaults + JSON payload |
| `POST /spec/responses/:id/submit` | hand off to chat |

**Data**
- `Data.SpecTemplate` — Id, Key, Version, Title, Body (JSON schema), Status, CreatedAt
- `Data.SpecResponse` — Id, TemplateKey, TemplateVersion, Namespace, Username, Answers (JSON), Status (draft/submitted), SessionId, CreatedAt
- Reuse existing `Data.ChatSpec` for the accepted specification — no new approval model.

**Handoff** — `submit` opens the chat with `?spec=<responseId>`; the chat fetches the rendered text and posts it as the first turn to `/chat/stream`. The agent replies with the Spec Card, and the existing Approve → plan → gate → build → validate flow proceeds untouched.

**Security** — inherits everything: authenticated IRIS user, `X-IRIS-Namespace` validation, audit logging of every request, Foundation-namespace protection, and the confirmation gate on every mutation. The form itself is **read-only against the instance** — it only *reads* environment metadata to populate options. It creates nothing.

---

## 10. Phasing

| Phase | Deliverable | Value at end |
|---|---|---|
| **P0** | Static questionnaire (hard-coded Essential template) + renderer + manual copy into chat | Proves the spec quality improvement immediately |
| **P1** | Environment & catalog prefill (`search_ens`, schema categories, hosts, productions) | Grounded options; the "wow" demo |
| **P2** | `Skill.InterfaceSpec` + automatic handoff to chat | End-to-end: form → spec → plan → build |
| **P3** | Template editor + versioning + system-required guardrails | Customer configurability |
| **P4** | Archetype library + mapping-spreadsheet import + `GetHL7SchemaMap` autocomplete | Scales across interface types |

P0–P2 is the MVP and is worth demoing on its own.

---

## 11. Open questions

1. **Separate IPM module or part of `Agentic Integration Builder`?** Bundling is simpler; separating aligns with the independent-update goal in [`Product_Requirements_Integration_Agentic_Builder.md`](Product_Requirements_Integration_Agentic_Builder.md) §9 Distribution and Deployment. *Recommendation: same repo, separate module manifest, so it can ship on its own cadence.*
2. **Does the form replace or complement document upload?** *Recommendation: complement — best flow is upload the SoW, let the agent pre-populate the questionnaire from it, then have the human correct and complete it. That is strictly better than either alone, and should be the P4+ target.*
3. **One template or an archetype library from day one?** *Recommendation: one Essential template in P0; archetypes at P4.*
4. **How opinionated should defaults be?** Healthcare defaults (`FailureTimeout=-1`, `Validation=""`, `PoolSize=1` under FIFO) are strong opinions. *Recommendation: apply them, always labelled and always overridable.*
5. **Should the form write anything directly** (e.g. create directories, create the production shell) or remain strictly read-only? *Recommendation: strictly read-only — all mutation stays behind the agent's confirmation gate.*
6. **Field-mapping capture at scale** — a 200-row mapping table is painful in a web form. Spreadsheet import is likely mandatory, not optional, for real interfaces.
7. **Should the Production Generator do the scaffolding?** (§7.1) Deterministic skeleton from CSV, agent for the intelligent parts. *Recommendation: prototype both in P2 and compare — if the generator is reliable it reduces token cost, agent iterations, and failure surface substantially.*
8. **Do we adopt the documented naming conventions as mandatory or default?** *Recommendation: default and overridable — but auto-generated, so the common case is correct without the user thinking about it.*
9. **Sample-message onboarding.** Should "I have no spec, only messages" invoke the HL7 Message Analyzer to derive a custom schema before the questionnaire is filled? This is a strong differentiator for greenfield customers and directly implements `Best Practices` §2.2 guidance.

---

## 12. Why this is the right next application

It attacks the problem *upstream* of the one we already solved. The Agentic Integration Builder made building fast; specification is now the bottleneck, and it is the step where the most expensive errors are introduced. This application makes a complete, grounded, machine-readable specification the **default output** of a customer's thinking — and because it emits into the existing spec contract, it is additive rather than disruptive to everything already built.
