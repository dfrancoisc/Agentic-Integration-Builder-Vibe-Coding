# agentic_interop — Architecture and Build Plan

This document is the source of truth for what we are building, what constraints apply, and what order things happen in. Updated at every phase boundary. Supersedes any prior kickoff spec where they conflict.

## What this is

A configuration-driven AI Copilot for IRIS for Health. The end user opens a chatbot mounted into a post-login Angular page, asks questions in natural language about Productions, Transformations, HL7, and FHIR, and the copilot uses tools backed by IRIS to answer or act. Everything (Agents, MCP groupings, Toolsets, Tools, Skills, LLM Providers) is configurable through an admin UI — no code edits to add a tool or change a model.

Single agent in v1, named Health Interop. Multi-agent supported by data model from day one.

## Restrictions (immutable)

These are user-set rules captured at kickoff. Any deviation must be documented inline below the section it affects, with rationale.

1. Always use the %AI Framework. If a bug forces something off-framework, document the deviation here.
2. Runtime LLM separation. The chatbot uses whatever Provider the IRIS administrator configures via the admin UI. Claude Code's dev assistance is a separate connection — only acts on the chatbot when explicitly asked.
3. No icon on the IRIS login page. The chatbot launcher appears only on post-login Angular pages.
4. IPM-compliant from day one. Another developer must be able to clone the repo and `zpm load` into a clean IRIS for Health instance with no machine-specific paths anywhere.
5. Always commit changes to GitHub.
6. README current at every phase boundary.
7. Namespace-agnostic. Code must not hardcode a namespace. Detect `$namespace` at request time, respect it, display it in the chatbot UI for user verification.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Customer Angular page (post-login)                              │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  Vanilla JS chatbot (iframe or standalone).               │    │
│  │  Admin UI at /agentic/admin/.                            │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────┬───────────────────────────┘
                                       │ REST + SSE
                                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  IRIS for Health (any namespace where zpm load was run)          │
│                                                                  │
│  CSP web apps (created at install time):                         │
│    /agentic/        — static JS bundle (Type 1 CSP app)          │
│    /api/agentic/    — REST (Type 2, UseSession=0)                │
│                                                                  │
│  AgenticInterop.REST.Dispatch reads X-IRIS-Namespace header,     │
│  validates user has access, does `new $namespace` to honor it.   │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  AgenticInterop.Agent.HealthInterop (extends %AI.Agent)    │  │
│  │  Router agent with Daniel persona (system integrator).     │  │
│  │  Tool catalog = 15 Skill classes (as sub-agent tools) plus │  │
│  │  cross-cutting tools (get_user_namespace, search_ens,      │  │
│  │  search_hs).                                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                ▼                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Skills (each one a %AI.Agent.Skill subclass — declarative │  │
│  │  sub-agent with PDF-grounded INSTRUCTIONS):                │  │
│  │   • Skill.Productions     → ToolSet.Production             │  │
│  │   • Skill.DTL             → ToolSet.Transform              │  │
│  │   • Skill.BPL             → ToolSet.Transform              │  │
│  │   • Skill.RoutingRules    → ToolSet.Production             │  │
│  │   • Skill.HL7v2           → ToolSet.Testing                │  │
│  │   • Skill.FHIRR4          → ToolSet.Testing                │  │
│  │   • Skill.SDA             → ToolSet.Testing                │  │
│  │   • Skill.RestInProductions → ToolSet.Production           │  │
│  │   • Skill.ESBPattern      → ToolSet.Production + Transform │  │
│  │   • Skill.X12             → ToolSet.Testing                │  │
│  │   • Skill.CDA             → ToolSet.Transform              │  │
│  │   • Skill.Adapters        → ToolSet.Production             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                ▼                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Five logical "MCP groupings" — surfaced to admin UI as    │  │
│  │  MCP rows; backed at runtime by direct ToolSet calls       │  │
│  │  (no HTTP loopback). Each grouping is one %AI.ToolSet:     │  │
│  │   • AgenticInterop.ToolSet.Production                      │  │
│  │   • AgenticInterop.ToolSet.Transform                       │  │
│  │   • AgenticInterop.ToolSet.Testing                         │  │
│  │   • AgenticInterop.ToolSet.Catalog                         │  │
│  │   • AgenticInterop.ToolSet.Monitoring                      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                ▼                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Tool implementations (per-row in Tool table):             │  │
│  │   • SQL                                                    │  │
│  │   • ObjectScript class methods                             │  │
│  │   • Embedded Python class methods                          │  │
│  │   • REST wrappers                                          │  │
│  │  Dispatched by AgenticInterop.Tool.* executors.            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                ▼                                 │
│  IRIS native stores in current namespace:                        │
│   • Secured Wallet (LLM API keys)                                │
│   • SQL tables (config rows, conversations, audit)               │
│   • Vector tables (catalog.ens, catalog.hs — FastEmbed 384d)     │
│   • Live Productions / DTL / BPL the agent operates on           │
└──────────────────────────────────────────────────────────────────┘
```

Binding rules enforced by the data model:
- Agent (1) → MCPs (N)
- MCP (1) → ToolSets (N)
- ToolSet (1) → Tools (N)
- Skill (N) ↔ Agent (N)
- Provider (1) → Agent (N)

MCP class strategy — REVISED 2026-05-05:
- MCPs are real `%AI.MCP.Service` subclasses. The framework already has the right abstraction; inventing a parallel "logical MCP only" concept duplicated state and lost the wire-protocol exit.
- For in-process use, transport is opt-in. `%AI.MCP.Service.LoadToolSetsToManager(toolMgr, spec)` populates a ToolMgr from a CSV of ToolSet class names without binding anything to a CSP URL. No HTTP loopback.
- A thin `AgenticInterop.MCP.Base [ Abstract ]` extends `%AI.MCP.Service` and adds `Parameter NAME`, `Parameter DESCRIPTION`, `Parameter TOOLSETS`, and a `RegisterToAgent(agent)` classmethod. Each concrete MCP is a Base subclass.
- If a customer later wants to expose a specific MCP to external agents, the work is mechanical: add one CSP route mapping. No code changes inside the MCP class.

## Data model — class as data

The four primary configuration entities (Agent, MCP, ToolSet, Tool) are NOT %Persistent rows. They are class definitions, manipulated via the IRIS `%Dictionary.*` write APIs. This was the explicit user requirement: "the class will be updated based on the configuration".

This means the source of truth for an Agent / MCP / ToolSet / Tool is its compiled class. The admin UI reads via SQL queries against `%Dictionary.Compiled*` and writes via `%Dictionary.*Definition.%Save()` followed by `$system.OBJ.Compile()`. Runtime instantiation uses the class system directly — no extra serialization layer.

Read/write API summary (verified against IRIS for Health 2026.2 AI 162.0):

| Concept | Read (UI list/show) | Write (UI save) |
|---|---|---|
| Class itself | `SELECT … FROM %Dictionary.CompiledClass` | `%Dictionary.ClassDefinition.%New(name)` → set `Super`/`Description` → `%Save()` → `$system.OBJ.Compile(name,"ck-d")` |
| Parameter (e.g. TOOLSETS) | `SELECT … FROM %Dictionary.CompiledParameter WHERE parent = ?` and/or `$parameter(class, name)` | `%Dictionary.ParameterDefinition.%OpenId(class\|\|name)` → set `Default` → `%Save()` → recompile |
| XData (e.g. Definition, INSTRUCTIONS) | `SELECT … FROM %Dictionary.CompiledXData` then read the `Data` stream | `%Dictionary.XDataDefinition.%OpenId(class\|\|name)` → write to `Data` stream → `%Save()` → recompile |

Caveat: after a `%Save()` + recompile, `%Dictionary.CompiledParameter.%OpenId()` returns the previous (cached) value in the same process. The runtime `$parameter()` macro and SQL queries against `%Dictionary.Compiled*` see the new value immediately. The editor services therefore use SQL on read paths, never `%OpenId` for verification. (See memory note: "OpenId hits process-local OREF cache".)

The remaining classes do still use %Persistent (chat sessions, audit, LLM connections — these have row-level lifecycle, not class-level shape):

| Class | Purpose |
|---|---|
| AgenticInterop.Data.Connection | LLM connection config (provider/model/region/baseURL/maxTokens/enabled/isDefault) plus last-test result. Secret lives in IRIS Secured Wallet, never in the row. SQL alias `AgenticInterop_Data.LLMConnection` because "Connection" is reserved. |
| AgenticInterop.Connections | Facade for Connection rows + secrets. Modeled on the `Catalog.Connections` pattern from new-interoperability-health: List/Get/Create/Update/Delete + SetSecret/HasSecret/ClearSecret/Test/GetProvider, with idempotent wallet bootstrap and a seeded `bedrock-default` core row. Uses %AI.Provider.Create + ChatComplete for the live test call (universal across openai/anthropic/bedrock/gemini/azure-openai/nim — no per-kind boto3 code). |
| AgenticInterop.Data.Conversation | Chat session header |
| AgenticInterop.Data.Message | Chat message rows |
| AgenticInterop.Data.ToolInvocation | Audit trail per tool call |

Shipped vs user-authored namespace separation:
- `AgenticInterop.MCP.*` / `AgenticInterop.ToolSet.*` — shipped via IPM, version-controlled. UI shows these read-only with a "Clone & Edit" action.
- `AgenticInterop.User.MCP.*` / `AgenticInterop.User.ToolSet.*` — user-authored at runtime, persisted only inside IRIS.DAT, exportable via UI button. Full CRUD here.

## Admin UI — per-entity field specs

The admin UI reaches each class via the editor REST API (`AgenticInterop.Editor.*` services, mounted under `/api/agentic/editor/`). One page per entity type. Field spec for each:

### Agent

Each Agent class extends `%AI.Agent`. The shipped instance is `AgenticInterop.Agent.HealthInterop`. Users may clone it under `AgenticInterop.User.Agent.<Name>`.

| UI field | Storage | Editable |
|---|---|---|
| Class name | class identifier | on create only |
| Display name | `Parameter NAME` | yes |
| Description | class `Description` | yes |
| System prompt | `XData INSTRUCTIONS` (markdown) | yes |
| Provider | `Parameter PROVIDER` (CSV-of-class is wrong here — single class) | yes (dropdown of registered Provider rows) |
| Temperature | `Parameter TEMPERATURE` | yes |
| MaxIterations | `Parameter MAXITERATIONS` | yes |
| MCPs | `Parameter MCPS` (CSV of MCP class names) | yes (multi-select from registered MCPs) |
| Skills | `Parameter SKILLS` (CSV of Skill class names) | yes (multi-select from registered Skills) |
| Test action | runs `Manager.Diagnose(provider)` and shows the result | n/a |

### MCP

Each MCP extends `AgenticInterop.MCP.Base` (which itself extends `%AI.MCP.Service`).

| UI field | Storage | Editable |
|---|---|---|
| Class name | class identifier | on create only |
| Name | `Parameter NAME` | yes |
| Description | `Parameter DESCRIPTION` | yes |
| ToolSets | `Parameter TOOLSETS` (CSV of ToolSet class names) | yes (multi-select from registered ToolSets) |
| Tool list (read-only) | flattened from each member ToolSet's XData Definition | computed |

### ToolSet

Each ToolSet extends `%AI.ToolSet` directly (no middle base — see BUG.md for why MCP needs a Base but ToolSet does not).

| UI field | Storage | Editable |
|---|---|---|
| Class name | class identifier | on create only |
| Name | `Parameter NAME` | yes |
| Description | class `Description` | yes |
| Tools | `XData ToolManifest` (JSON; sibling of framework's XML `Definition`) | yes (table editor; one row per tool) |

### Tool

A Tool is one entry inside its parent ToolSet's `XData ToolManifest` JSON. There is no separate class per Tool. The UI edits the JSON object in-place.

Why a separate XData (`ToolManifest`) instead of putting tools in the framework's `Definition` XData: `%AI.ToolSet.Definition` is XML and parsed at compile time by a generator on `%AI.ToolSet`. Stuffing JSON into Definition breaks compilation (SAX error). Storing the editor's tool list in a sibling `ToolManifest` XData keeps the framework happy and gives us a shape the UI can render directly. Phase 4 translates `ToolManifest` entries into the framework's `Definition` (XML) plus generated class methods or Rust refs, at which point the tools become actually invokable. Until Phase 4 lands, `ToolManifest` is metadata only — round-trips with the UI but is not seen by the agent.

| UI field | Storage | Editable |
|---|---|---|
| Name | `tools[i].name` | yes |
| Description | `tools[i].description` | yes |
| Input schema | `tools[i].inputSchema` (JSON Schema object) | yes |
| Implementation kind | `tools[i].implementation.kind` (one of: `sql`, `objectscript`, `python`, `rest`) | yes |
| Body | `tools[i].implementation.body` (string) | yes (kind-aware editor) |
| Timeout (ms) | `tools[i].timeoutMs` | yes |
| Requires confirmation | `tools[i].requiresConfirmation` (boolean) | yes |
| Dry-run action | calls `Editor.ToolService.DryRun(toolSet, toolName, args)` and shows result | n/a |

### Skill

Each Skill extends `AgenticInterop.Skill.Base` (the `%OnNew` workaround).

| UI field | Storage | Editable |
|---|---|---|
| Class name | class identifier | on create only |
| Name | `XData SUMMARY` `name` field | yes |
| Description | `XData SUMMARY` `description` field | yes |
| Instructions | `XData INSTRUCTIONS` (markdown) | yes |
| ToolSets | `Parameter TOOLS` (CSV of ToolSet class names) | yes (multi-select from registered ToolSets) |

### Provider

Provider rows are %Persistent (see Phase 1). Field spec captured there.

## Skills

Skills are %AI.Agent.Skill SUBCLASSES — declarative sub-agents shipped with the IPM module as code. They are NOT user-editable markdown rows. The router agent registers them as tools via its ToolManager; the parent LLM decides when to invoke each one based on the description in each Skill's XData SUMMARY.

This satisfies restriction #1 (always use the %AI Framework) — Skill is the framework's first-class concept for declarative sub-agent specialists.

The agent operates under the Daniel persona — a senior system integrator and healthcare interoperability architect. The persona document (docs/system_integrator_persona.md) defines identity, expertise, working philosophy, and behavioral rules. The system prompt references this persona and all twelve skills.

The twelve v1 skill classes (in src/cls/AgenticInterop/Skill/):

| Skill class | Sub-agent toolset access | Source PDFs |
|---|---|---|
| Productions | ToolSet.Production | Introducing + Preparing + Configuring + Developing + Best_Practices + Managing + Monitoring + DICOM + MFT + Virtual_Documents |
| DTL | ToolSet.Transform | Developing_DTL_Transformations + DTL chapters of Business_Process_and_DTL_Reference |
| BPL | ToolSet.Transform | Developing_BPL_Processes + BPL chapters of Business_Process_and_DTL_Reference |
| RoutingRules | ToolSet.Production | Developing_Business_Rules |
| HL7v2 | ToolSet.Testing | (curated from existing iris-hl7-v2 skill + HL7 sections of attached PDFs) |
| FHIRR4 | ToolSet.Testing | (curated from existing iris-fhir skill) |
| SDA | ToolSet.Testing | (curated from existing iris-sda skill) |
| RestInProductions | ToolSet.Production | Using_REST_Services_and_Operations_in_Productions |
| ESBPattern | ToolSet.Production + ToolSet.Transform | Using_a_Production_as_an_ESB |
| X12 | ToolSet.Testing | HIPAA EDI (270/271/276/277/278/834/835/837), envelope structures, SEF schema loading, virtual property paths, search tables |
| CDA | ToolSet.Transform | CDA/C-CDA document structure, XSLT pipelines (not DTLs), import/export profiles, SDA intermediary pattern |
| Adapters | ToolSet.Production | File/TCP/MLLP/HTTP/REST/FTP/SFTP/SQL/JDBC/MQTT/SOAP adapter selection matrix, key settings, passthrough classes |

Each Skill's INSTRUCTIONS XData is distilled strictly from the source PDFs and existing curated skills — no hallucinated APIs, no invented class names. Source citations live in docs/SKILLS.md alongside each skill's content.

Latency note (per ai-hub-skills): each skill invocation is an additional LLM round-trip, sub-agents run sequentially. For our domain this is the right trade — focused expertise per domain beats one giant system prompt.

## Provider strategy

The %AI.Provider abstraction means the app is provider-agnostic. The customer picks via admin UI; the system swaps with no code change.

Reference dev provider: Anthropic direct (`provider.Create("anthropic", {"api_key": "@{wallet.AgenticInteropSecrets.AnthropicKey}"})`). Confirmed working with %AI.Agent tool calls in 2026.2 AI 162.0.

Bedrock: configurable via the same admin UI. KNOWN ISSUE — the %AI.Agent tool-result round-trip hangs at the Rust HTTP layer when sending a `tool_result` message back to Bedrock. Reproduces on `agent.Run()` and `agent.StreamChat()`, model-independent and endpoint-independent. Open WRC ticket; root cause below the ObjectScript surface, so we cannot patch it from app code. Bedrock chat-without-tools works fine. The Provider table will accept Bedrock rows from day one; the chat will hang on the first tool call until the upstream fix lands.

Azure OpenAI: configurable, untested in this project; expected to work with tools per ai-hub-framework capability matrix.

LLM testing during development: live testing happens in the admin UI with the user's own API key. Unit tests use a mocked Provider stub so CI doesn't depend on external services.

## Catalogs

Two FastEmbed-backed `%AI.RAG.KnowledgeBase` instances. FastEmbed is bundled (no API key, 384-dim, AllMiniLML6V2 ONNX), satisfying restriction "no external dependencies for core functionality".

| Catalog | Tool name | Rows | Used by |
|---|---|---|---|
| catalog.ens | search_ens | ~180 | ToolSet.Production, ToolSet.Testing |
| catalog.hs  | search_hs  | ~50  | ToolSet.Transform, ToolSet.Testing |

Source data: `InterSystems_IRIS_Health_Complete_Class_Catalog.xlsx` (13 sheets, 8-column schema: Class Name, Namespace, Package, Type, Abstract, Purpose, When to Use, Key Settings). Classification per-row by Namespace/Package column rather than by sheet, since some sheets straddle both catalogs. The XLS is shipped as a seed under `seeds/` in the repo; ingest is idempotent and triggerable from the admin UI.

The vector tables are created in the install namespace (per restriction 7). Multi-namespace customers get one catalog per install.

## Build phases

Each phase ends with a working slice and a commit + push to dfrancoisc/agentic_interop. README updated at every phase boundary (restriction 6).

### Phase 0 — Skeleton + IPM compliance
- Repo structure under `src/cls/AgenticInterop/...` matching MIGRATION.md
- module.xml registers the package and creates two CSP apps (`/agentic/`, `/api/agentic/`)
- AgenticInterop.REST.Dispatch with a `/health` route returning `{"ok": true, "namespace": "<current>"}`
- AgenticInterop.REST.NamespaceAPI returning the current `$namespace`
- Sample host HTML under `src/csp/agentic/index.html` that loads the React bundle (placeholder content for now)
- README install instructions verified by uninstalling + reinstalling on iris-agentic
- Definition of done: `zpm "load ."` from a clean IRIS namespace creates the apps; `curl http://localhost:22773/api/agentic/health` returns 200 with namespace info.

### Phase 1 — Connection layer + admin UI (DONE 2026-05-03)
- AgenticInterop.Data.Connection (persistent, name-keyed, `LLMConnection` SQL alias)
- AgenticInterop.Connections facade (List/Get/Create/Update/Delete + SetSecret/HasSecret/ClearSecret + Test + GetProvider). Idempotent wallet bootstrap (Security.Resources + %Wallet.Collection); seeds a `bedrock-default` core row.
- AgenticInterop.Editor.ConnectionService thin REST wrapper.
- Routes: `GET/POST /api/agentic/connections`, `GET/PUT/DELETE /api/agentic/connections/:name`, `POST /api/agentic/connections/:name/secret`, `POST /api/agentic/connections/:name/test`.
- Secrets in real IRIS Secured Wallet (`%Wallet.KeyValue` collection `AgenticInteropConnections`, resource `AgenticInteropConnections`). Stored as JSON `{"value":"<key>"}`.
- Test endpoint runs `%AI.Provider.Create(provider, settings).ChatComplete(model, [{role:user, content:"reply with the single word ok"}], 0.0, 16)` — works for all 6 kinds (openai/anthropic/bedrock/gemini/azure-openai/nim) without per-kind code. Bedrock-specific: settings use `bearer_token` (not `api_key`); `AWS_BEARER_TOKEN_BEDROCK` and `AWS_REGION` env vars set via `$system.Util.SetEnviron` so the Rust LLM library picks them up.
- Admin SPA "Connections" tab with list (status dot, enabled/default/core badges), detail form (name, displayName, description, provider, enabled, isDefault, model, maxTokens, region, baseURL, masked secret), and a live "Test connection" button that posts to `/test` and renders green/red with model + latency or verbatim error.
- Definition of done: paste a Bedrock bearer through the UI, click Test connection, see green semaphore with model + latency. ✓ verified live (3008ms round-trip to Sonnet 4).

### Phase 2 — Single ToolSet + Skill scaffolding + non-streaming chat (DONE 2026-05-04)
- AgenticInterop.ToolSet.Catalog with a stub `search_ens(query)` returning fake data
- AgenticInterop.Agent.HealthInterop wired to the Anthropic provider, slim system prompt (router pattern)
- AgenticInterop.Agent.Manager + Runtime + Monitor + SkillLoader (iteration deadline, token budget, no streaming yet)
- All nine `AgenticInterop.Skill.*` classes scaffolded — XData SUMMARY (yaml metadata) and Parameter TOOLS set, XData INSTRUCTIONS body grows as PDF batches are read
- One Skill (Productions) loaded into the router agent for the smoke test
- ChatAPI returning full response (non-SSE)
- Definition of done: ask "show me running productions", router invokes Productions skill, sub-agent invokes `search_ens`, response returned.

### Phase 3 — Streaming + tool-call telemetry + namespace-in-UI (DONE 2026-05-04)
- SSE chat endpoint with token + tool-lifecycle events
- React chat with tool-call cards
- Active namespace shown in chatbot header; first message includes the namespace
- Definition of done: stream chat with tool calls visible in real time; refuse if user lacks namespace access.

### Phase 4 — Remaining MCP groupings + confirmation gate (DONE 2026-05-04)
- AgenticInterop.ToolSet.Production / Transform / Testing with their initial tools
- AgenticInterop.Policy.ConfirmationGate (Authorization policy) for tools with RequiresConfirmation = 1
- React inline Approve / Reject UI
- Definition of done: a mutating tool pauses with the inline prompt; rejection cancels the iteration cleanly.

### Phase 5 — Catalog builders + real vector search + monitoring tools (DONE 2026-05-06)
- XLS ingester (Embedded Python via openpyxl) → catalog.ens / catalog.hs vector tables
- AgenticInterop.Catalog.SearchToolSet exposing search_ens / search_hs
- Refresh button in admin UI
- AgenticInterop.ToolSet.Monitoring + AgenticInterop.Tool.Monitoring (5 read-only SQL query tools: QueryEventLog, TopErrors, QueryMessageStatus, MessageSummary, QueueStatus)
- Cross-provider tool selection in ToolSet editor (any tool from any %AI.Tool class can be added to any ToolSet)
- Definition of done: ask a question requiring catalog lookup, agent calls the right catalog tool, returns relevant classes. Monitoring questions answered via SQL queries against Ens.Util.Log and Ens.MessageHeader.

### Phase 6 — Admin UI completion (DONE 2026-05-06)
- All entity CRUD pages (Agents, MCPs, Toolsets, Tools, Skills, Connections)
- Tool form with Dry-run panel
- Skill editor (markdown)
- Definition of done: every entity creatable / editable / deletable from the UI.

### Phase 7 — Polish + handover (DONE 2026-05-07)
- Audit trail UI for ToolInvocation
- Error reporting page
- Mount API documentation for customers integrating into their Angular shell
- Operations runbook
- Ghost code cleanup, docs audit, IPM compliance
- Definition of done: another developer can clone, install, configure, and use without asking for help.

## Chatbot UI quality bar

The chatbot UI is the core deliverable and must work perfectly regardless of where it is loaded — iframe in an Angular page, standalone page, or any future surface. The UI is vanilla JS with no build step, handling its own state, errors, retries, and lifecycle. Never assume properties of the host page beyond what the documented iframe contract guarantees.

This applies across phases. The phase column below indicates when each chatbot capability ships, but every shipped capability must be production-quality at that point — no placeholder UI, no broken states, no half-working flows.

## Open items

- Customer Angular shell — none provided. Phase 0 ships a sample host HTML so dev works. Customers embed the chatbot via iframe (`/agentic/chat/index.html`) in their own Angular page; we do not own that integration.
- Multi-namespace install ergonomics: install once per target namespace. Future enhancement could add a "deploy to all my namespaces" admin action.
- mcp.testing isolation default: recommend always-isolated test production by default (configurable).

## Known risks

- Bedrock + tools hang (above). Workaround: pick another provider in the admin UI. The app keeps shipping; Bedrock rows just won't function until WRC fix lands.
- IRIS for Health 2026.1 vs 2026.2: kickoff spec mentioned both. We target 2026.2 because that is what the dev container ships and what the %AI Framework class catalog used for design verification was extracted from.
- FastEmbed memory: bundled ONNX runs in-process; first-time load is a few hundred MB. Document in README ops section once we hit Phase 5.

## Current stats (2026-05-14)

| Metric | Value |
|---|---|
| ObjectScript classes | 82 |
| Tool classes (%AI.Tool) | 7 |
| Tools (public ClassMethods) | 118 |
| ToolSets (%AI.ToolSet) | 7 |
| MCP servers (%AI.MCP.Service) | 6 (+ MCP.Base abstract) |
| Skills (%AI.Agent.Skill) | 15 domain + 1 abstract base |
| Agents (%AI.Agent) | 2 (HealthInterop, FHIRSpecialist) |
| Persistent data classes | 8 |
| IPM module version | 1.1.0 |

## Product Requirements Document

The full PRD is at [docs/PRD.md](PRD.md) (also available as [PRD.docx](PRD.docx)). It covers:

- Three primary use cases: guided production build, production review and optimization, complex HL7-to-HL7 transformations
- Performance, scalability, and quality requirements with specific targets
- DX (Developer Experience) vs Interface Engineer (End User) persona separation
- Tool depth requirements across 12 artifact domains (Productions, DTL, BPL, Routing Rules, Lookup Tables, HL7 Schemas, FHIR R4, SDA, Catalog, X12/HIPAA, CDA/C-CDA, Adapters)
- Daniel system integrator persona (docs/system_integrator_persona.md) defining agent identity, expertise, and behavioral rules
- Chatbot experience requirements (conversation lifecycle, memory, access control, streaming, guided interaction, reports, audit)
- Architecture: Agents, MCPs, Tools, Skills, and Catalog vector search

## Notes for a developer reading this for the first time

- MCPs are real `%AI.MCP.Service` subclasses (revised 2026-05-05 — see "MCP class strategy" above). Transport is opt-in: in-process consumers call `LoadToolSetsToManager` directly, no HTTP loopback. The earlier "logical-only" model was dropped because it duplicated framework state and forfeited the wire-protocol exit.
- The agent never has hardcoded provider credentials. Always resolved through the Wallet via `@{wallet.AgenticInteropSecrets.<KeyName>}` placeholders at runtime.
- The four primary configuration entities (Agent, MCP, ToolSet, Tool) are class definitions, not %Persistent rows. Source of truth is the compiled class. Read via SQL on `%Dictionary.Compiled*`; write via `%Dictionary.*Definition.%Save()` + `$system.OBJ.Compile()`. Read-after-write must use SQL or `$parameter()`, not `%OpenId` (process-local OREF cache).
- All multi-class refactors must update docs/MIGRATION.md before the code change, not after.
- `AgenticInterop.Skill.Base` is a workaround for an `%AI.Agent.Skill.%OnNew` framework bug — see docs/BUG.md. It can be deleted when the upstream fix lands.
- Known framework bugs and ObjectScript language gotchas are documented in [docs/BUG.md](BUG.md). Read it before writing new code — it will save debugging time.
- The agent operates under the Daniel persona (docs/system_integrator_persona.md). The persona defines identity, core expertise (healthcare standards, IRIS platform, adapters, transformation pipelines, security), working philosophy (research first, optimize for out-of-the-box, plan thoroughly), knowledge sources (skills, catalogs, docs, community, tool results), and behavioral rules (direct answers, backtick formatting, no fabrication, mandatory testing).
