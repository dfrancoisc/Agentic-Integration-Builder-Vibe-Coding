# agentic_interop

AI Copilot for InterSystems IRIS for Health. A configuration-driven chatbot that helps integration engineers build, review, and optimize healthcare interoperability workflows through natural conversation. Built entirely on the InterSystems %AI Framework.

The copilot bridges the gap between healthcare data expertise and InterSystems platform knowledge. Instead of navigating Management Portal screens and writing ObjectScript by hand, engineers describe what they need in plain English and the copilot builds it using real IRIS APIs.

![Chat UI](docs/img/15_chatbot.png)

## Status

Version 1.1 ships. All build phases complete (Phase 0 through Phase 7) plus the 1.1 build-quality round: 32 new tools across Transform and Production toolsets driven by the IRIS interop docs (BPL/DTL/FHIR/Production/HL7 reference material). The agent operates under the Daniel persona -- a senior system integrator and healthcare interoperability architect who plans before building, searches before creating, and tests before declaring success.

## What's new in 1.1

- BPL builders: `BuildHL7ToFHIRBPL`, `BuildHL7ToSDABPL`, generic `UpdateBPL`, plus `ListBPLs`/`GetBPL`/`DeleteBPL` — close the gap where `CreateBPL` alone left an empty `<sequence/>` and the agent claimed success.
- DTL CRUD completeness: `GetDTL`, `DeleteDTL`, `ListHL7ToSDADTLs`, `SetCustomDTLPackage` (paired with the existing `GetCustomDTLPackage`).
- FHIR pipeline configuration: `ConfigureSDAToFHIRProcess` / `ConfigureFHIRToSDAProcess` wrap the HS.FHIR.DTL.Util.HC.* business processes with TargetConfigName, FHIRMetadataSet, FHIREndpoint, TransmissionMode, OutputToQuickStream, TransformClass.
- FHIR Lookup-table CRUD: `ListFHIRLookupTables` / `GetFHIRLookupTable` / `UpdateFHIRLookupTable` against `^HS.XF.LookupTable`, with disk persistence to the namespace-specific `Lookup.json`.
- HL7 helper tools: `ConfigureHL7TCPService`, `ConfigureHL7TCPOperation`, `ConfigureHL7Router` (Validation="" baked in to avoid the `ErrMapSegUnrecog` trap), `EnableHL7TraceOperations`, `CreateHL7SearchTable`.
- Production deployment workflow: `ListSystemDefaultSettings` / `GetSystemDefaultSetting` / `SetSystemDefaultSetting` / `DeleteSystemDefaultSetting` for the documented dev→test→live promotion via `Ens.Config.DefaultSettings` (8-step wildcard lookup), plus `GetEffectiveSetting` that resolves through the 3-source chain (production class → System Default → InitialExpression) and reports the source.
- Routing rule CRUD: `GetRoutingRule`, `DeleteRoutingRule` (alongside the existing `CreateRoutingRule` and `ListBusinessRules`).
- Runtime diagnostics: `ListProductionQueues`, `ReleaseFIFOHold`, `ReleaseAllFIFOHolds`, `ValidateScheduleSpec`, `PreviewTimestampSpec`.
- Skill expansions: HL7v2 skill grew with ACK Mode / Framing / Batch Handling / Validation Flags / Reply Code Actions / Escape Sequences / Dual-ACK / Sequence Manager reference tables. Productions skill grew with System Default Settings precedence, Reply Code Actions full grammar, Pool Size + Actor Pool Size semantics, FIFO Groups workflow, and the filename time-stamp specification reference.

| Metric | Value |
|---|---|
| ObjectScript classes | 86 |
| Agents (%AI.Agent) | 2 (Health Interop generalist, FHIR Specialist) |
| Tool classes (%AI.Tool) | 7 (Production, Transform, Testing, Catalog, Monitoring, FHIR Server, Bulk FHIR) |
| Tools (public ClassMethods) | 122 |
| ToolSets (%AI.ToolSet) | 7 |
| MCP servers | 6 (Production, Transform, Testing, Catalog, FHIR Server, Bulk FHIR) |
| Skills (%AI.Agent.Skill) | 16 domain + 1 abstract base |
| Vector catalogs | 2 (search_ens: 164 classes, search_hs: 58 classes) |
| Field-level mappings (Transformation and Mapping Catalog) | 1,538 |
| Persistent data classes | 8 (Connection, AgentOverride, MCPOverride, ToolSetOverride, AuditLog, FieldMapping, Chatbot, FHIRLoadRun) |
| Git commits | 100+ |

## Features

- Streaming chat with Server-Sent Events (SSE) -- token-by-token responses with inline tool-call cards
- 122 tools across 7 domains: Production, Transform, Testing, Catalog, Monitoring, FHIR Server, Bulk FHIR
- FHIR Server Audit panel: a left-nav menu in the FHIR Management app showing FHIR server storage (the per-endpoint repository databases via CORE `SYS.Database`, not the namespace DB), resource counts by type (CORE FHIR `_summary=count`), and ingestion performance (duration, resources/sec, bottlenecks) — backed by `GET /api/agentic/fhir/audit`
- Load FHIR Data menu: a left-nav menu in the FHIR Management app to upload FHIR JSON files to a server-readable staging folder (`mgr/Temp/agentic-fhir-upload/`), so the FHIR Assistant can then load them into a FHIR server with `LoadFHIRDirectory` — backed by `POST/GET/DELETE /api/agentic/fhir/upload`
- 16 domain skills covering Productions, DTL, BPL, Routing Rules, HL7v2, FHIR R4, FHIR Interop (production-to-FHIR-server connectivity), FHIR Server, Bulk FHIR, FHIR SQL Builder, SDA, REST, ESB, X12/HIPAA, CDA/C-CDA, and Adapters
- FHIR Specialist agent: a dedicated FHIR platform agent (FHIR Server MCP + Bulk FHIR MCP + Catalog, with the FHIR Server / FHIR R4 / SDA / Bulk FHIR / FHIR SQL Builder skills) alongside the generalist Health Interop agent
- Chatbot configuration layer: bind each chatbot surface to an agent in the admin "Chatbots" tab (the chat resolves its agent from the chatbot key at request time — no redeploy). Ships an Interop chatbot (Health Interop, in the Interop Editor) and a FHIR Management chatbot (FHIR Specialist, a launcher button injected into the header of the shipped `/csp/fhir-management` FHIR Server Management page)
- Confirmation gate on every mutating tool -- create, update, delete, compile, start, stop all require explicit user approval before executing
- Semantic vector search over the IRIS class library (164 Business Hosts, 58 transformation classes) using FastEmbed 384-dimensional embeddings and HNSW index
- Transformation and Mapping Catalog with 1,538 pre-computed field-level mappings across HL7 v2, SDA3, FHIR R4, CDA, and X12
- Configuration-driven admin UI -- no code edits needed to add a tool, change a model, or reconfigure an agent
- LLM connection management with Secured Wallet storage for API keys -- never in plaintext, never in SQL tables, never in source code, never returned by REST endpoints
- Audit trail for every API request (method, path, status, duration, user, namespace)
- Namespace-agnostic: install once per namespace, tools execute in the namespace specified by the request header
- IPM (ZPM) package for one-command install and upgrade
- Source control integration: agent-created artifacts flow through %SourceControl hooks into the Git/CI/CD pipeline
- 60-second deadline and 50,000-token budget per chat turn -- no runaway costs or infinite loops
- Overlay pattern for configuration persistence across IPM upgrades (user edits survive package reload)

## Four personas, four experiences

### Developer

Builds agent infrastructure: writes Tool classes in ObjectScript, authors Skill documents with INSTRUCTIONS, builds vector catalog embeddings, packages and deploys via IPM. Work happens in VS Code and ships as compiled classes. The Developer defines what the copilot can do.

| Attribute | Detail |
|---|---|
| Primary interface | VS Code with InterSystems ObjectScript extension, terminal |
| Security scope | Full %DB access, %Dictionary write, source control, IPM packaging |
| Deliverable | Compiled classes inside an IPM package that the AI Hub Admin configures |

### AI Hub Admin

Configures all AI settings through the admin UI: creates agents with custom system prompts, assembles MCP Servers from available ToolSets, links Skills to Agents, manages LLM connections, builds vector catalogs, reviews audit logs. Assigns Interface Engineer and Operator roles to end users. The AI Hub Admin decides how the copilot behaves -- no code editing required.

| Attribute | Detail |
|---|---|
| Primary interface | IRIS Management Portal -- AI Hub admin UI at /agentic/admin/ |
| Security scope | %ISCMgtPortal group membership, /api/agentic/ endpoints, Secured Wallet write for API keys |
| Deliverable | A fully configured agent ready for end users, with appropriate tool access per role |

### Interface Engineer (End User -- dev-time)

Uses the chatbot to create new integration artifacts: productions, DTLs (Data Transformation Language classes), BPLs (Business Process Language classes), routing rules, lookup tables. This is a dev-time role -- the Interface Engineer authors new content that flows through source control and CI/CD into deployment. Tool access includes all mutating tools: create_production, add_business_host, create_dtl, compile_dtl, create_routing_rule, start_production, stop_production.

| Attribute | Detail |
|---|---|
| Primary interface | Chatbot at /agentic/chat/index.html (standalone or embedded in the Interop Editor) |
| Security scope | Chat access plus create/update/delete permissions on interoperability classes. All mutating operations require explicit approval. Changes flow through source control hooks |
| Deliverable | New or modified productions, transformations, and routing rules -- exported to source control |

### Operator (End User -- run-time)

Uses the chatbot to monitor, triage, and review existing integrations at run-time. The Operator does not create new productions or DTLs -- they observe, diagnose, and recommend. Can adjust operational settings (pool size, throttle, retry intervals) but not structural changes (add/remove hosts, create classes). Structural changes escalate to the Interface Engineer.

| Attribute | Detail |
|---|---|
| Primary interface | Chatbot at /agentic/chat/index.html (standalone or embedded in the Interop Editor) |
| Security scope | Chat access plus read-only access to production configurations and monitoring data |
| Deliverable | Diagnosis reports, remediation recommendations, settings adjustments, modernization advice |

### Interface Engineer vs Operator: Tool Access

| Tool Category | Int. Eng. | Operator | Examples |
|---|---|---|---|
| Create/Update/Delete | Yes | No | create_production, create_dtl, add_business_host |
| Start/Stop | Yes | No | start_production, stop_production |
| Compile | Yes | No | compile_dtl |
| Read/Inspect | Yes | Yes | get_production, list_dtls, describe_class |
| Monitoring | Yes | Yes | query_event_log, top_errors, queue_status |
| Search | Yes | Yes | search_ens, search_hs |
| Testing | Yes | Limited | send_hl7, validate_hl7_structure |
| Settings adjustment | Yes | Yes (operational only) | update_business_host_settings (pool size, throttle, retry) |

## Use cases by persona

### Developer (5 use cases)

1. **Write a new Tool class.** A developer writes an ObjectScript class extending %AI.Tool with public ClassMethods that become callable tools. Each method has a JSON Schema for input/output and a description that serves as the LLM's contract. The developer ships the class in the IPM package and the AI Hub Admin makes it available to end users through ToolSet configuration.

2. **Author a domain Skill.** A developer distills InterSystems documentation into a markdown INSTRUCTIONS document for a specific domain (DTL syntax, BPL activities, HL7 v2 segment anatomy). The skill is packaged as a %AI.Agent.Skill subclass. When the LLM needs domain knowledge, it invokes the skill rather than carrying all knowledge in the system prompt -- saving thousands of tokens per request.

3. **Build and refresh vector catalogs.** A developer writes the catalog builder class (AgenticInterop.Catalog.Builder) that walks %Dictionary.ClassDefinition for Business Hosts and transformation classes, extracts curated prose descriptions, and feeds them into %AI.RAG.KnowledgeBase for embedding. The catalog is rebuilt when IRIS is upgraded or new classes are added.

4. **Extend the MCP layer.** A developer creates a new %AI.MCP.Service subclass to expose a new domain of tools (for example, a Monitoring MCP for production health metrics). The MCP groups related ToolSets and is registered in the agent configuration through the admin UI.

5. **Package and deploy via IPM.** A developer maintains the module.xml that defines the IPM package: ObjectScript classes, seed data, web application definitions, install/uninstall hooks. A single `zpm "load /path/to/agentic_interop"` command installs all 86 classes, two web apps, seed data, and the curated class catalog into any namespace.

### AI Hub Admin (5 use cases)

1. **Configure an LLM connection.** An AI Hub Admin opens the Connections tab, pastes an API key into the masked input, selects the provider type (Anthropic, Bedrock, Azure OpenAI), and clicks "Test connection." The key is stored in the IRIS Secured Wallet -- never in plaintext. A green status with model name and latency confirms the wire path works. A red status shows the verbatim error.

2. **Assemble an agent with custom behavior.** An AI Hub Admin creates an agent profile with a custom system prompt, selects which MCP servers are bound, attaches relevant skills, and sets temperature and max iterations. Different agent profiles can be created for Interface Engineer and Operator roles, each with different ToolSet bindings that enforce which tools are available.

3. **Build vector catalogs for a namespace.** An AI Hub Admin navigates to the Catalogs tab, selects the source namespace, and clicks "Rebuild this catalog" on search_ens and search_hs. The knowledge bases are populated with curated class descriptions from %Dictionary. A test search field lets the admin verify relevance before making the catalog available to end users.

4. **Review the audit trail.** An AI Hub Admin opens the Audit tab to see every API request: method, path, HTTP status, duration, user, namespace. An "Errors only" toggle filters to failures. The audit captures both successful tool executions and rejected requests, providing full traceability for compliance and debugging.

5. **Manage ToolSet visibility per role.** An AI Hub Admin includes or excludes specific tools from a ToolSet, then binds that ToolSet to either the Interface Engineer or Operator agent profile. This controls which tools the LLM can call for each role -- Operators cannot access create/delete/compile tools even if the user crafts a prompt that requests them.

### Interface Engineer (5 use cases)

1. **Build a production from a natural-language description.** An Interface Engineer opens the chatbot and describes the integration: "Build a production that receives ADT^A01 messages via MLLP, transforms patient demographics to FHIR R4, and sends them to a REST endpoint." The agent searches the Ens.* catalog for the right Business Hosts, proposes a production layout for approval, creates the production with all hosts and settings, sends a test HL7 message, and validates the result end-to-end. Every mutating step requires explicit approval.

2. **Create a DTL transformation.** An Interface Engineer asks "Create a DTL that maps PID fields from an ADT message to a FHIR Patient resource." The agent introspects the HL7 v2.5.1 schema at sub-field level, searches the HS.* catalog for existing SDA-to-FHIR mappers, creates the DTL with correct source and target classes, compiles it, and dry-runs it against a sample message. The Transformation and Mapping Catalog provides field-level gap analysis showing which source fields map through SDA3 to FHIR and which have no outbound mapping.

3. **Add Business Hosts to an existing production.** An Interface Engineer asks "Add an SMTP operation to the Lab Results production so we can email PDF reports." The agent searches the catalog for email-capable operations, proposes EnsLib.EMail.OutboundAdapter with appropriate settings, adds it to the production, and configures the routing rule to send messages to the new operation.

4. **Create routing rules with conditions.** An Interface Engineer describes "Route ADT messages by message type: A01 goes to Admissions, A08 goes to Updates, everything else goes to the dead-letter queue." The agent creates the routing rule set with the specified conditions, compiles it, and adds it to the production's business process.

5. **Trace data flow and create an end-to-end interface.** An Interface Engineer asks "Show me how patient address fields flow from HL7 v2 PID.11 through SDA3 to FHIR R4 Patient.address." The agent uses the Transformation and Mapping Catalog to trace PID.11 sub-fields (Street, City, State, ZIP) through SDA3 Address properties to FHIR Address elements, identifies any coverage gaps, then builds the complete interface (service, process, DTL, operation) in one conversation.

### Operator (5 use cases)

1. **Triage production errors.** An Operator asks "Show me the errors in the last 2 hours across all productions." The agent queries the event log, groups errors by Business Host and error type, identifies the most frequent failures, and recommends remediation steps (restart a host, check connectivity, review a DTL for null-handling issues). No mutating actions are taken without Interface Engineer escalation.

2. **Assess production health.** An Operator asks "How healthy is the ADT Inbound production?" The agent checks queue depths, throughput rates, error counts, suspended messages, and host status. It presents a summary with specific metrics and highlights any hosts that are degraded, suspended, or accumulating queued messages.

3. **Review a DTL for common issues.** An Operator asks "Review the PatientDemographics DTL for issues." The agent reads the DTL definition and checks for common problems: hardcoded values that should use lookup tables, missing null checks on optional fields, repeating-field handling bugs, deprecated API usage. The Operator gets a report with specific recommendations that an Interface Engineer can implement.

4. **Compare messages before and after transformation.** An Operator asks "Compare this inbound HL7 ADT with the outbound FHIR Patient to verify the demographics mapped correctly." The agent parses both messages, aligns the fields using the Transformation and Mapping Catalog, and highlights discrepancies -- fields that changed unexpectedly, fields that were expected but are missing, and fields with format differences.

5. **Monitor throughput and recommend tuning.** An Operator asks "The Lab Results production seems slow -- what's the bottleneck?" The agent checks throughput summaries, queue depths across all hosts, and host pool sizes. It identifies the bottleneck (for example, a single-threaded operation with a growing queue) and recommends operational adjustments the Operator can make directly (increase pool size, adjust retry interval) versus structural changes that require an Interface Engineer.

## Admin UI

The admin UI provides configuration pages for all entities. No code edits required to add a tool, change a model, or reconfigure an agent.

![Admin UI - Agent editor](docs/img/02_agent_detail.png)

| Tab | Purpose |
|---|---|
| Agents | System prompt editor, temperature, max iterations, MCP and skill attachment |
| MCPs | MCP server enable/disable, ToolSet selection |
| ToolSets | Include/exclude tools from any Tool class |
| Tools | Browse tool catalog with descriptions, parameter signatures, and dry-run panel |
| Skills | INSTRUCTIONS editor for each domain skill |
| Connections | LLM provider configuration with masked secret input, live test button, green/red status |
| Chatbots | Bind each chatbot surface to an %AI.Agent (key → agent + host page + title); ships the Interop and FHIR Management chatbots |
| Catalogs | Vector catalog rebuild, source namespace selection, test search, browse entries |
| Transforms | Field-level mapping explorer (Transformation and Mapping Catalog) across HL7 v2, SDA3, FHIR R4, CDA, X12 |
| Audit | Searchable log of every API request with method, path, status, duration, user, namespace |

## Transformation and Mapping Catalog (Transforms tab)

A visual field-level mapping explorer showing how data flows between external formats through the SDA3 canonical model. SDA3 is the universal pivot in IRIS for Health -- all external formats (HL7 v2, FHIR R4, CDA, X12) map through it.

![Transformation and Mapping Catalog](docs/img/13_transforms_hl7_fhir.png)

Features:
- Format pair selection: HL7 v2, FHIR R4, FHIR STU3, CDA, X12, SDA3
- Sub-field level detail: PID.11.3 City, not just PID-11 PatientAddress
- IRIS class names inline: which class handles each direction (e.g., HS.Gateway.HL7.HL7ToSDA3, HS.FHIR.DTL.SDA3.vR4.Address.Address)
- Coverage filter chips: End-to-end, Inbound only, Outbound only
- 110 SDA3 data types browsable in the sidebar
- 1,538 pre-computed rows, rebuilt on demand in ~0.2 seconds

## Tools

The agent's capabilities are organized into 7 Tool classes (122 tools total). Each Tool class is a `%AI.Tool` subclass where every public ClassMethod is a tool the LLM can call.

| Tool class | Tools | Purpose |
|---|---|---|
| Production | 29 | Production class CRUD, host lifecycle (Add/Remove/Update/Start/Stop/PostBuildValidation), routing-rule CRUD, HL7 helper builders (TCP service/operation, router with Validation=""), HS.Util.Trace.Operations enabler, System Default Settings CRUD + GetEffectiveSetting (production → SystemDefault → InitialExpression chain), Ens.Queue diagnostics, ReleaseFIFOHold/ReleaseAllFIFOHolds, PreviewTimestampSpec (Ens.Util.File.CreateTimestamp), ValidateScheduleSpec |
| Transform | 30 | DTL CRUD + DryRunDTL + BuildDTLXml + SetCustomDTLPackage + ListHL7ToSDADTLs + ListSDAFHIRDTLs, BPL CRUD + UpdateBPL + BuildHL7ToFHIRBPL + BuildHL7ToSDABPL + ValidateBPL, ConfigureSDAToFHIRProcess + ConfigureFHIRToSDAProcess, FHIR Lookup table CRUD (List/Get/Update against ^HS.XF.LookupTable), CreateHL7SearchTable, HL7 schema introspection (GetHL7SchemaMap, GetHL7SegmentFields), DescribeTransformationPipeline |
| Testing | 8 | Send and validate HL7 v2 and FHIR R4 messages, build test messages, compare messages |
| Catalog | 7 | Vector search over Ens.* and HS.* catalogs, class introspection, namespace utilities, glossary |
| Monitoring | 5 | Event log search, top-error grouping, message status, throughput summaries, queue depth |
| FHIR Server | 26 | Discover FHIR-enabled foundation namespaces, inspect/configure endpoints, CapabilityStatement, metadata packages, resource search/read/CRUD/$validate, ordered async directory load (+ status + ingestion metrics + durable run history), bulk load, data reset, storage/performance audit, query-performance probe, guarded endpoint provisioning |
| Bulk FHIR | 13 | Bulk FHIR Coordinator (BFC): list/get/schema/create/configure/activate/delete configs, start exports, monitor sessions, and provision prerequisites end to end (storage directory, SSL/TLS config, interop credential, SMART-backend OAuth server + client) — fetch from a source FHIR endpoint to ndjson or ingest into a target FHIR server |

## Skills

Fifteen domain skills teach the agent IRIS-specific concepts. Each skill is a `%AI.Agent.Skill` subclass with markdown INSTRUCTIONS distilled from InterSystems documentation.

| Skill | Domain |
|---|---|
| Productions | Production anatomy, BS/BP/BO patterns, lifecycle management |
| DTL | DTL syntax, foreach, subtransforms, lookup tables, virtual documents |
| BPL | BPL activities, compensation handlers, async patterns |
| RoutingRules | Rule sets, constraints, when-conditions, dead-letter handling |
| HL7v2 | Message types, segments, ACK semantics, schema navigation |
| FHIRR4 | Resources, references, search parameters, R4 bundles |
| FHIRServer | FHIR R4 server build/admin: discover foundation namespace, endpoints, config, metadata packages, resource CRUD/search/$validate, CapabilityStatement, guarded provisioning |
| BulkFHIR | Bulk FHIR Coordinator config + `$export` (system/Patient/Group), SMART Backend Services, fetch/storage adapters, async REST flow |
| FHIRSQLBuilder | Project FHIR data into relational SQL (Analysis → Spec → Projection), columns/subtables/filters, query over SQL/JDBC/ODBC |
| SDA | SDA3 model as transformation hub, HL7-to-SDA-to-FHIR pipeline |
| RestInProductions | REST services and operations inside productions |
| ESBPattern | Using a production as an Enterprise Service Bus |
| X12 | HIPAA EDI transactions, envelope structures, schemas |
| CDA | CDA/C-CDA documents, XSLT pipelines, SDA conversion |
| Adapters | File/TCP/HTTP/REST/FTP/SQL/MQTT/SOAP adapter selection and configuration |

## Vector Catalogs

Two semantic search catalogs index the IRIS class library so the agent can find relevant Business Hosts, adapters, and transformation classes by natural-language query.

![Catalogs](docs/img/11_catalogs.png)

| Catalog | Classes | Scope |
|---|---|---|
| search_ens | 164 | Business Hosts, Services, Processes, Operations, Adapters from the Ens.* hierarchy |
| search_hs | 58 | HealthShare transformations, FHIR mappers, SDA helpers, HL7 gateways |

Technical details:
- Embedding model: FastEmbed (384-dimensional vectors, bundled with IRIS)
- Vector storage: `%AI.RAG.KnowledgeBase` with HNSW index
- Query path: `%AI.ToolMgr.ExecuteTool(kbName, args)` (SQL `EMBEDDING()` does not work with bundled FastEmbed)
- Document format: curated prose descriptions (class name + description + superclass + key parameters), not raw class dumps

## Chatbot experience

The chat UI streams responses token-by-token via Server-Sent Events (SSE). Tool calls render as inline cards showing the tool name, arguments, status, and collapsible result. Mutating tools (production creation, DTL compilation, etc.) pause with an inline Approve / Reject prompt before executing.

Key features:
- Conversation history rail with search, resume, and rename
- Starter prompts for common use cases (Build, Transform, Operate, Review)
- Plan presentation with explicit user approval before any build
- Post-build validation checklist (production running, hosts enabled, no errors, messages flowed)
- Monitor enforces 60-second deadline + 50,000 token budget per turn
- Full audit trail of every tool invocation (visible in the admin Audit tab)

## Requirements

- InterSystems IRIS for Health 2026.2 or newer
- IPM (ZPM) installed in the target namespace
- An LLM API key you control. Anthropic direct is the reference provider. Bedrock and Azure OpenAI are configurable but see [docs/BUG.md](docs/BUG.md) for the current Bedrock tool-call hang

## Install

```bash
git clone https://github.com/dfrancoisc/agentic_interop.git
cd agentic_interop
```

In an IRIS terminal, switch to the namespace where you want the copilot installed:

```objectscript
ZN "<your-namespace>"
zpm "load /path/to/agentic_interop"
```

The module installs all 86 classes, two web apps (`/agentic/` for the UI, `/api/agentic/` for REST), seed data, and the curated class catalog. To install in multiple namespaces, run the command once per namespace.

## After install

1. Open the admin UI at `http://<host>:<web-port>/agentic/admin/`.
2. Connections tab -- add an LLM Connection. Paste the API key. The key is stored in the IRIS Secured Wallet (`%Wallet.KeyValue` collection `AgenticInteropConnections`), never in plaintext.
3. Click "Test connection". Green status with model and latency means the wire path works.
4. Catalogs tab -- click "Rebuild this catalog" on `search_ens` and `search_hs`. The knowledge bases power vector search inside the chat.
5. Open the chatbot at `http://<host>:<web-port>/agentic/chat/index.html` or via the AI button in the Interop Editor.

## Embedding the chatbot in your own app (optional)

You do not need this for the in-product experience. The IPM install already embeds the chatbot for you: the `InteropEditorPatch` and `FHIRManagementPatch` Activate hooks inject the chat launcher into the Interop Editor and the FHIR Server Management page automatically (both are reverted on uninstall). After `zpm load`, just open the AI button in those portals — there is no manual mount step.

This section applies only if you want to embed the chat into a *different* application of your own. The chat UI is a standalone page at `/agentic/chat/index.html`, integrated one of two ways:

**Iframe mode (recommended).** Set `iframe.src = '/agentic/chat/index.html?via=interop&namespace=' + currentNamespace`. The chat captures the parent SPA's IRIS JWT via `postMessage` (no second login), sends `X-IRIS-Namespace` on every request, and refuses access (403) if the user lacks database-level read on the target namespace.

**Standalone mode.** Open `/agentic/chat/index.html` directly. The page shows an inline credentials overlay on first visit; credentials persist in `localStorage`.

## Operations runbook

**Daily.** No action required. The chat surface is self-serve and the audit log captures every request.

**On chat failure.**
1. Admin - Audit tab - toggle "Errors only". Recent failures show with verbatim error text.
2. Check the Connection's last test status. A red Connection means the LLM provider rejected credentials or model.
3. The 60-second deadline / 50,000-token budget on `agent.Run` (see `AgenticInterop.Agent.Monitor`) caps any single chat turn. "Agent deadline exceeded" means the LLM took too long. Try a narrower question or split into steps.

**On approval card stuck.** The user's chat tab must be open. Click APPROVE to continue or REJECT to cancel. The agent acknowledges rejections and asks how to proceed.

**Rebuilding catalogs.** After installing a different IRIS for Health version, click Rebuild on each catalog from the admin Catalogs tab.

**Wallet rotation.** Connections tab - open a connection - paste new API key - Save. The previous secret is overwritten.

**Cross-namespace.** The `X-IRIS-Namespace` header routes tool execution to the specified namespace after validating user access.

## Known issues

See [docs/BUG.md](docs/BUG.md) and [docs/03_Lessons_Learned.md](docs/03_Lessons_Learned.md) for details on:
- `%AI.Agent.Skill.%OnNew` JSON marshaling bug (workaround: `AgenticInterop.Skill.Base`)
- Bedrock tool-result round-trip hang (workaround: use Anthropic direct provider)
- `%FromJSON` instance method returns empty string (workaround: use class-method form)
- `$get()` on `%DynamicObject` throws `<INVALID CLASS>` (workaround: use `$select` with `%IsDefined`)
- CSP `UseSession` deadlock on REST endpoints (workaround: set `UseSession=0`)
- `%OpenId` returns stale data in cross-process polling (workaround: use SQL queries)
- ObjectScript language gotchas (QUIT in blocks, comment syntax, numeric comparisons)

## License

TBD.
