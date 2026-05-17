# Agentic Health Interoperability - Technical Build Specification

> Version 1.0 | May 2026 | InterSystems AI Hub  
> What InterSystems needs to build to deliver an Agentic Health Interoperability solution

---

## 1. Executive Summary

This document specifies the components InterSystems must build to deliver a production-grade Agentic Health Interoperability solution. The system is a configuration-driven AI Copilot embedded in IRIS for Health that enables integration engineers to build Productions, create Transformations, and test healthcare messages through natural-language conversation.

The solution is built on the IRIS %AI Framework (Agent, MCP, ToolSet, Tool, Skill primitives) and extends it with application-specific infrastructure: a chat UX, an admin UI, vector catalogs, a transformation data atlas, connection management, and audit/security controls.

---

## 2. Chatbot UX

### 2.1 What to build

A streaming chat interface embedded in the IRIS Management Portal that connects to a %AI.Agent via Server-Sent Events (SSE). The chatbot is the Builder's primary interface for interacting with the agent.

### 2.2 Core capabilities

**Streaming responses**
- SSE endpoint (`POST /chat/stream`) emits tokens as they arrive from the LLM
- Each token is a `data:` event with JSON payload: `{ type: "token", text: "..." }`
- Tool lifecycle events: `tool_start`, `tool_args`, `tool_result`, `tool_error`
- Turn boundary event: `{ type: "done" }`

**Tool-call cards**
- When the agent calls a tool, a card renders inline showing: tool name, arguments (collapsible), status (running/ok/error), and result (collapsible)
- Cards update in real time as tool execution progresses
- Multiple tool calls in a single turn render as a vertical stack

**Confirmation gate**
- Mutating tools (create, update, delete) pause execution and surface an Approve/Reject prompt
- The `AgenticInterop.Policy.ConfirmationGate` policy intercepts tool calls before execution
- User clicks Approve to proceed or Reject to skip
- Rejection feeds back to the agent as a tool error so it can adjust

**Conversation management**
- "New conversation" button clears context and starts fresh
- Conversation history is persisted via audit log (every user message and agent response logged)
- Top bar shows: agent name, active connection status (green/red dot), namespace

**Performance guardrails**
- `AgenticInterop.Agent.Monitor` enforces per-turn limits: 60-second deadline + 50,000 token budget
- If a turn exceeds limits, the monitor triggers a graceful stop and the agent summarizes partial results
- No single LLM call should block the UI; streaming ensures visible progress from the first token

### 2.3 Audit trail for conversations

Every conversation generates audit records:

| Field | Description |
|---|---|
| Timestamp | When the request was received |
| Username | Authenticated IRIS user |
| Namespace | Active namespace at request time |
| SessionId | Browser session identifier |
| Job | IRIS job number |
| Request | User's message text |
| Response | Agent's final response text |
| Tool calls | Array of: tool name, input JSON, output JSON, duration_ms, error (if any) |
| Total duration | End-to-end request time |
| Token usage | Prompt tokens, completion tokens, total |

The audit log is queryable from the admin UI (Audit tab) with filters by username, date range, and request kind.

---

## 3. Agent

### 3.1 What to build

A single %AI.Agent instance ("HealthInterop") that serves as the router agent. It receives user messages, decides which tools or skills to invoke, and orchestrates multi-step workflows.

### 3.2 Agent architecture

```
AgenticInterop.Agent.HealthInterop (extends %AI.Agent)
  |-- MAXITERATIONS = 25
  |-- TEMPERATURE = 0.3
  |-- System prompt: persona definition + formatting rules
  |
  |-- AgenticInterop.Agent.Manager (builds configured agent at request time)
  |     |-- Loads provider (LLM connection from Secured Wallet)
  |     |-- Binds MCP servers (or bypasses to direct tool binding)
  |     |-- Loads skills via SkillLoader
  |     |-- Attaches policies (ConfirmationGate, ToolFilter)
  |     |-- Attaches vector catalog KBs (search_ens, search_hs)
  |
  |-- AgenticInterop.Agent.Monitor (iteration callback)
  |     |-- 60s deadline per turn
  |     |-- 50K token budget per turn
  |     |-- Graceful stop on exceeded limits
  |
  |-- AgenticInterop.Agent.SkillLoader
        |-- Walks Skill.Base subclasses
        |-- Registers each as a sub-agent tool
```

### 3.3 Configuration (runtime, not compile-time)

All agent parameters are configurable at runtime through override tables:

| Parameter | Default | Configurable via |
|---|---|---|
| System prompt | Shipped class INSTRUCTIONS | Admin UI Agent editor |
| Temperature | 0.3 | Admin UI slider |
| Max iterations | 25 | Admin UI input |
| Bound MCPs | All 4 | Admin UI checkbox list |
| Bound skills | All 12 | Admin UI checkbox list |
| LLM provider | bedrock-default | Admin UI dropdown |
| Tool binding | MCP chain | Admin UI radio (mcp/bypass) |

### 3.4 Overlay pattern

Shipped class defaults + user customizations must both survive across upgrades:

- **Shipped classes** (in source control): define base parameters, compile with `zpm load`
- **Override tables** (`AgenticInterop.Data.AgentOverride`, `MCPOverride`, `ToolSetOverride`): store admin UI changes in SQL tables
- **Overlay merge** (`AgenticInterop.Editor.Overlay`): at build time, layers override values on top of compiled defaults
- **Reset**: "Reset to defaults" button deletes the override row, restoring shipped values

---

## 4. Skills

### 4.1 What to build

Declarative sub-agents that package domain knowledge as markdown INSTRUCTIONS. The main agent delegates domain-specific questions to the appropriate skill rather than answering from general training data.

### 4.2 Skill catalog (v1)

| Skill | Domain | Content source |
|---|---|---|
| Productions | Production anatomy, BS/BP/BO patterns, settings | IRIS documentation |
| DTL | Data Transformation Language syntax, foreach, subtransforms, virtual documents | IRIS documentation |
| BPL | Business Process Language activities, compensation, async patterns | IRIS documentation |
| RoutingRules | Rule sets, constraints, when conditions, HL7 routing | IRIS documentation |
| HL7v2 | Message types, segments, ACK semantics, composite types (XAD, XPN, CX) | HL7 v2 specification |
| FHIRR4 | Resources, references, search params, FHIR server operations | FHIR R4 specification |
| SDA | SDA3 model, common pitfalls, mapping to FHIR, canonical patient record | IRIS documentation |
| RestInProductions | RESTful services inside productions, HTTP adapters | IRIS documentation |
| ESBPattern | Enterprise Service Bus patterns, routing, message transformation | Architecture guides |
| X12 | X12 transaction sets, EDI healthcare claims | X12 specification |
| CDA | Clinical Document Architecture, CCD, C-CDA | CDA specification |
| Adapters | Inbound/outbound adapters, TCP, HTTP, SOAP, file, FTP | IRIS documentation |

### 4.3 Skill registration mechanism

Skills extend `AgenticInterop.Skill.Base` (not `%AI.Agent.Skill` directly -- see Lessons Learned for the bug workaround). At agent build time, `SkillLoader` discovers all `Skill.Base` subclasses, instantiates them, and registers them as tools in the agent's tool catalog.

The LLM sees each skill as a callable tool: `skill_productions(question: "How do I add a Business Service to a production?")`. The skill runs as a sub-agent with its own INSTRUCTIONS context and returns a specialist answer.

---

## 5. MCP Servers

### 5.1 What to build

Four internal MCP (Model Context Protocol) servers that group related capabilities into named service domains. Each MCP maps to one or more ToolSets.

### 5.2 MCP catalog (v1)

| MCP Server | ToolSets | Purpose |
|---|---|---|
| `mcp.production` | Production | CRUD productions, business hosts, settings, start/stop |
| `mcp.transform` | Transform | CRUD DTL/BPL, routing rules, lookup tables, HL7 schema introspection |
| `mcp.testing` | Testing | Send HL7/FHIR messages, validate structure/semantics, compare messages |
| `mcp.catalog` | Catalog, Monitoring | Vector search, class introspection, namespace info, event log, throughput |

### 5.3 Transport

MCP servers run in-process (no HTTP loopback). Registration uses `UseToolSet()` calls at agent build time. Wire transport (HTTP/SSE) is architecturally supported but not used in v1.

### 5.4 Binding chain

```
Agent
  --> MCP Server (mcp.production)
        --> ToolSet (Production)
              --> Tool (list_productions)
              --> Tool (create_production)
              --> Tool (add_business_host)
              --> ...
```

In "bypass" mode, the agent binds ToolSets directly (skipping MCPs) for simpler deployments.

---

## 6. Tools

### 6.1 What to build

42 tools across 5 tool classes that implement the agent's capabilities. Each tool is a method with `[Tool]` annotation, JSON Schema input/output, and a natural-language description.

### 6.2 Tool catalog

**Production tools (10):**
list_productions, get_production, create_production, delete_production, start_production, stop_production, add_business_host, remove_business_host, update_business_host_settings, PostBuildValidation

**Transform tools (14):**
list_dtls, get_dtl, create_dtl, update_dtl, compile_dtl, delete_dtl, list_bpls, create_bpl, list_routing_rules, create_routing_rule, list_lookup_tables, crud_lookup_table, introspect_hl7_schema, trace_sda_fhir_pipeline

**Testing tools (6):**
send_hl7, send_fhir, validate_hl7_structure, validate_fhir_resource, compare_messages, BuildAndSendHL7TestMessage

**Catalog tools (7):**
search_ens, search_hs, describe_class, get_namespace, list_classes, lookup_reference, search_glossary

**Monitoring tools (5):**
query_event_log, group_errors, message_status, throughput_stats, queue_depth

### 6.3 Tool description quality

Tool descriptions are LLM-facing contracts. They follow this format:
- Imperative verb opening ("List all productions in the current namespace")
- Scope statement ("Returns production name, status, and item count")
- Side effects ("This tool creates a new production class. Requires confirmation.")
- Input expectations ("Expects a valid HL7 v2 message string with pipe delimiters")

### 6.4 Tool policies

**ConfirmationGate**: Mutating tools (create, update, delete, start, stop) pause execution and surface an Approve/Reject prompt in the chat UI before proceeding.

**ToolFilter**: Strips framework waste tools (FileSystem, SQL, ShellTools) from the LLM tool catalog before each request. Without this filter, the LLM receives 60+ generic tools that dilute the healthcare-specific ones and waste tokens.

### 6.5 Dry-run support

Non-mutating tools support dry-run from the admin UI: the Builder enters input JSON, clicks Execute, and sees the output. This enables tool validation without chat context.

---

## 7. Catalogs using Vector Search

### 7.1 What to build

Two semantic search catalogs that index the IRIS class library so the agent can find relevant Business Hosts, adapters, and transformation classes by natural-language query.

### 7.2 Catalog specifications

| Catalog | Name | Scope | Source |
|---|---|---|---|
| Ens.* | `search_ens` | Business Hosts, Services, Processes, Operations, Adapters | `%Dictionary.ClassDefinition` for Ens.* superclass hierarchy |
| HS.* | `search_hs` | Health-specific transformations, FHIR mappers, SDA helpers | `%Dictionary.ClassDefinition` for HS.* classes |

### 7.3 Technical implementation

- **Embedding model**: FastEmbed (384-dimensional vectors, bundled with IRIS)
- **Vector storage**: `%AI.RAG.KnowledgeBase` with HNSW index
- **Query path**: `%AI.ToolMgr.ExecuteTool(kbName, args)` (the only working query path -- SQL `EMBEDDING()` does not work with bundled FastEmbed)
- **Document format**: Curated prose descriptions (class name + description + superclass + key parameters), not raw method signatures
- **Rebuild**: Triggered from admin UI or scheduled; walks `%Dictionary` and re-embeds all documents

### 7.4 Embedding quality considerations

Auto-generated accessor methods and structural boilerplate drown out semantic signal in 384-dim embeddings. The builder strips these and keeps only curated prose: class description, purpose statement, key parameters, and message types. This dramatically improves search relevance.

---

## 8. Data Atlas (Transformation Catalog and Mappings)

### 8.1 What to build

A visual field-level mapping explorer that shows how data flows between external formats (HL7 v2, FHIR R4, CDA, X12) through the SDA3 canonical model. This is the "Data Atlas" -- a reference tool for integration engineers.

### 8.2 Data flow model

```
HL7 v2 (inbound)  -->  SDA3 (canonical)  -->  FHIR R4 (outbound)
  PID.11.3 City    -->  City               -->  city
  PID.11.6 Country -->  Country            -->  country
  PID.11.4 State   -->  State              -->  state
```

SDA3 is the universal pivot: all external formats map through it. The Data Atlas shows both directions (inbound and outbound) and identifies fields that are:
- **End-to-end**: traced from source through SDA3 to target
- **Inbound only**: arrives in SDA3 but has no outbound target
- **Outbound only**: produced in the target but has no inbound source

### 8.3 Pre-computed field mapping table

`AgenticInterop.Data.FieldMapping` stores 1538 pre-computed rows joining HL7/FHIR/CDA/X12 fields through SDA3. Built by `TransformService.RebuildFieldMappings()` in ~0.2 seconds.

**Data sources:**
- HL7 -> SDA3: Programmatic extraction from `HS.Gateway.HL7.HL7ToSDA3` ObjectScript methods
- SDA3 -> FHIR: DTL class analysis via `HS.FHIR.DTL.SDA3.vR4.*` with backward-walk algorithm for intermediate variables
- Sub-field enrichment: Static lookup mapping composite HL7 types (XAD, XPN, CX, XTN) to component-level fields (PID.11.3 City instead of PID-11 PatientAddress)

### 8.4 UI features

- Format pair selection: any combination of HL7 v2, FHIR R4, FHIR STU3, CDA, X12, SDA3
- SDA3 type sidebar: 110 data types, browsable and filterable
- Coverage filter chips: clickable toggles for End-to-end / Inbound only / Outbound only
- IRIS class names inline: shows which class handles each direction of the mapping
- Text filter: search across field names, SDA types, class names
- Data flow explanation line with contextual format names
- Mapped rows sorted first for immediate visibility

---

## 9. Connection Management

### 9.1 What to build

A multi-provider LLM connection manager that stores credentials securely and provides health-check (connection test) functionality.

### 9.2 Supported providers

| Provider | Config fields | Secret field |
|---|---|---|
| AWS Bedrock | region, model | AWS_BEARER_TOKEN_BEDROCK (Wallet) |
| Anthropic | model, base URL | ANTHROPIC_API_KEY (Wallet) |
| OpenAI | model, base URL | OPENAI_API_KEY (Wallet) |
| Azure OpenAI | endpoint, deployment, API version | AZURE_OPENAI_API_KEY (Wallet) |
| Google Gemini | model, region | GEMINI_API_KEY (Wallet) |
| NVIDIA NIM | model, base URL | NIM_API_KEY (Wallet) |

### 9.3 Connection lifecycle

1. **Create**: Builder enters connection details in admin UI
2. **Store secret**: API key sent to `POST /connections/:name/secret`, written to IRIS Secured Wallet under collection `AgenticInteropConnections`
3. **Test**: `POST /connections/:name/test` sends a minimal completion request (1 token) to the configured provider, records latency, model, and error
4. **Status**: green (last test OK), red (last test failed), gray (never tested)
5. **Bind**: Agent configuration references a connection by name; at build time, Manager loads the secret from Wallet and configures the LLM client

### 9.4 Security invariants

- API keys are NEVER stored in SQL tables, globals, or source code
- API keys are NEVER returned by any REST endpoint
- API keys are NEVER logged in audit trail
- The only storage location is the IRIS Secured Wallet
- Connection test results (including error messages) ARE logged for debugging

---

## 10. Audit and Security

### 10.1 Authentication

| Method | Use case |
|---|---|
| Basic auth | Direct admin UI access (standalone mode) |
| JWT Bearer | Embedded access from Interop Editor (token passed via postMessage bridge) |

All REST endpoints require authentication. `UnauthenticatedEnabled=0` on the `/api/agentic/` web application. No UI element is visible before login.

### 10.2 Audit log

Every REST request is captured in `AgenticInterop.Data.AuditLog`:

```
Property Created As %TimeStamp
Property Username As %String
Property Namespace As %String
Property SessionId As %String
Property Job As %String
Property Method As %String     // GET, POST, PUT, DELETE
Property Path As %String       // /api/agentic/chat/stream
Property StatusCode As %Integer
Property RequestSize As %Integer
Property ResponseSize As %Integer
Property DurationMs As %Integer
Property ErrorText As %String
Property Kind As %String       // registry, editor.agent, chat, etc.
```

### 10.3 Security policies

**ToolFilter policy**: Removes framework-default tools (FileSystem, SQL, ShellTools) from the LLM's tool catalog. Without this, the LLM could theoretically access file system operations or raw SQL execution.

**ConfirmationGate policy**: Mutating operations require explicit user approval before execution. The agent cannot create, modify, or delete Productions, DTLs, or routing rules without the Builder clicking Approve.

### 10.4 Namespace isolation

All code uses `$namespace` at request time. No hardcoded namespace references. The system works in any namespace where the classes are installed (typically HSCUSTOM for Health Connect installations).

---

## 11. Performance Requirements

| Metric | Target | How achieved |
|---|---|---|
| First token latency | < 2 seconds | SSE streaming, no buffering |
| Turn completion | < 90 seconds | Monitor callback: 60s deadline + 50K token budget |
| Catalog search | < 500ms | Pre-built HNSW vector index, in-process query |
| Field mapping load | < 100ms | Pre-computed SQL table (1538 rows), indexed by format pair + SDA type |
| Field mapping rebuild | < 1 second | Batch insert with SQL, process-private globals for temp data |
| Catalog rebuild | < 30 seconds | Batch %Dictionary walk + FastEmbed |
| Chat UI render | < 100ms | Vanilla JS (no framework overhead), SSE event handler |
| Admin UI load | < 500ms | Vanilla JS SPA, single CSS + JS file |
| Concurrent users | 5 simultaneous sessions | Per-process agent instances, no shared state |
| Token efficiency | < 50K tokens per complex task | ToolFilter removes waste tools, curated skill content, no markdown formatting overhead |

### 11.1 Token reduction strategies

1. **ToolFilter policy**: Strips 15+ framework waste tools before each LLM call, saving ~3K tokens per request
2. **Skill content curation**: Concise, task-oriented prose instead of verbose documentation. No markdown bold (shows as `**` in chat)
3. **No universal context blocks**: System prompt does not repeat deployment or catalog info on every turn (BuildAugmentedMessage prepends once)
4. **Short tool descriptions**: Imperative verb + scope + side effects. No verbose explanations
5. **Monitor token budget**: 50K cap prevents runaway conversations from consuming unlimited tokens

---

## 12. Implementation Summary

| Component | Classes | Status |
|---|---|---|
| Agent | 4 classes (HealthInterop, Manager, Monitor, SkillLoader) | Built |
| MCP Servers | 5 classes (Base + 4 servers) | Built |
| ToolSets | 5 classes | Built |
| Tools | 5 classes, 42 tools | Built |
| Skills | 13 classes (Base + 12 skills) | Built |
| Data model | 6 persistent classes | Built |
| REST API | 1 dispatcher + 13 service classes | Built |
| Admin UI | 3 HTML + 2 JS + 2 CSS files | Built |
| Chat UI | 1 HTML + 1 JS + 1 CSS file | Built |
| Vector catalogs | 2 classes (Builder, Attach) | Built |
| Data Atlas | 2 classes (TransformService, FieldMapping) | Built |
| Policies | 2 classes (ConfirmationGate, ToolFilter) | Built |
| Install hooks | 2 classes (CSPTimeoutPatch, InteropEditorPatch) | Built |
| IPM package | module.xml | Built |
| **Total** | **61 ObjectScript classes, 8 web files, 95 commits** | |
