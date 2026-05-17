# Agentic Health Interoperability - Requirements and User Stories

> Version 1.0 | May 2026 | InterSystems AI Hub  
> Platform: InterSystems IRIS for Health 2026.2+, %AI Framework build 162.0

---

## 1. Introduction

This document defines the end-to-end requirements and user stories for the Agentic Health Interoperability project. The system enables two distinct personas to build, configure, and operate AI-powered agents for healthcare interoperability tasks inside InterSystems IRIS for Health.

**Product vision**: A configuration-driven AI Copilot that helps integration engineers build Productions, create Transformations, test HL7/FHIR messages, and explore the IRIS class catalog -- entirely through natural-language conversation or a structured admin UI.

### 1.1 Personas

| Persona | Role | Primary interface | Security scope |
|---|---|---|---|
| **Developer** | Builds agent infrastructure, writes custom tools, deploys packages | VS Code + ObjectScript extension + terminal | Full %DB access, %Dictionary write, source control, IPM packaging |
| **Builder** | Configures agents, skills, connections, reviews mappings, operates the chatbot | IRIS Management Portal (admin UI + chatbot) | Restricted to /api/agentic/ endpoints, no direct SQL or class compilation |

---

## 2. Core Use Cases

The Agentic Health Interoperability Copilot addresses three primary use cases that cover the full lifecycle of healthcare integration work inside IRIS for Health. Each use case represents a category of tasks that integration engineers perform daily and that the agent can accelerate through natural-language conversation.

### 2.1 Use Case 1: Build Productions

The most common task for an integration engineer is building new Productions -- the runtime message-processing pipelines in IRIS for Health. A Production consists of Business Services (inbound), Business Processes (routing/orchestration), and Business Operations (outbound), wired together with settings, routing rules, and message transformations.

The agent assists the Builder through the entire production lifecycle:

- **Discovery**: The Builder describes their integration goal in plain English (e.g., "build a production that receives ADT messages over MLLP, transforms them to FHIR R4, and sends them to a REST endpoint"). The agent searches the Ens.* vector catalog to find the right Business Host classes (EnsLib.HL7.Service.TCPService, EnsLib.FHIR.Operation.REST, etc.).
- **Proposal**: The agent presents a production layout -- which hosts to add, what settings to configure, which adapters to use -- and asks the Builder to approve before making changes.
- **Build**: Upon approval, the agent creates the production class, adds each Business Host with appropriate settings, creates routing rules, and compiles everything. Each mutating step goes through the confirmation gate.
- **Validation**: The agent runs PostBuildValidation to check for configuration errors, sends a test HL7 message through the pipeline, and verifies that messages flow end-to-end without errors.

**Tools involved**: search_ens, describe_class, create_production, add_business_host, update_business_host_settings, create_routing_rule, start_production, stop_production, PostBuildValidation, BuildAndSendHL7TestMessage

**Example prompts**:
- "Build a complete production that receives HL7 v2.5 ADT^A01 admission messages over an inbound folder, transforms each ADT into an ORU^R01 observation report, routes the transformed messages to an outbound folder, and sends failures to a dead-letter folder."
- "I need a production that receives X12 270 eligibility inquiries over SFTP, calls our internal eligibility REST API, constructs the X12 271 response, and writes it back to the payer's SFTP outbound folder."

### 2.2 Use Case 2: Review and Improve Existing Productions

Integration engineers inherit productions built by others, or maintain productions that were built months or years ago. They need to understand what a production does, identify problems, and find opportunities to modernize it using newer IRIS features and best practices.

The agent helps the Builder review and optimize existing integrations:

- **Error Triage**: The agent queries the Event Log and Message Header tables to find recent errors, groups them by Business Host, identifies the most frequent error messages, and recommends remediation steps. It can spot suspended or errored messages that need manual intervention.
- **Production Health Assessment**: The agent inspects the production configuration, checks queue depths, reviews throughput statistics, and identifies bottlenecks. It can recommend settings changes (pool size, throttle, retry intervals) based on what it observes.
- **DTL Review**: The agent reviews Data Transformation Language (DTL) definitions and identifies hardcoded values that should be lookup tables, missing null checks on source fields, incorrect handling of repeating fields, and segments being dropped. It suggests refactored versions with explanations.
- **Modernization Advice**: The agent knows about newer IRIS features (via Skills) and can recommend upgrades -- for example, replacing a custom BPL with a built-in DTL, using record maps instead of custom parsers, or adopting the HL7-to-SDA-to-FHIR pipeline instead of point-to-point transformations.

**Tools involved**: get_production, query_event_log, top_errors, query_message_status, message_summary, queue_status, describe_class, list_dtls, get_dtl

**Skills involved**: Productions, DTL, BPL, Adapters, ESBPattern

**Example prompts**:
- "Review the last 2 hours of errors across all productions. Group them by Business Host, show the top 5 most frequent error messages with counts, identify messages stuck in Suspended or Error state, and recommend remediation steps."
- "Review our current ADT_A08_to_SDA3 DTL for: hardcoded values that should be lookup tables, missing null checks on source fields, incorrect handling of repeating PID-3 identifiers, and segments we are dropping that we should not."

### 2.3 Use Case 3: Create and Optimize Transformations

Data Transformations are the heart of healthcare interoperability. Integration engineers spend most of their time writing, debugging, and optimizing DTL (Data Transformation Language) and BPL (Business Process Language) definitions that convert messages between formats -- HL7 v2 to SDA3, SDA3 to FHIR R4, CDA to SDA3, and more.

The agent assists the Builder with transformation work at every stage:

- **Pipeline Discovery**: The agent traces the full transformation pipeline for any format pair (e.g., HL7 v2 to FHIR R4) showing which IRIS classes handle each step, what intermediate formats are used, and where the data flows. The Transformation and Mapping Catalog (Transforms tab) provides this information visually at the field level.
- **DTL Creation**: The agent creates new DTL definitions by first searching the HS.* catalog for existing transformations that handle the same or similar format pair, then scaffolding a new DTL with the correct source/target classes and document types. It can populate field mappings based on the Transformation and Mapping Catalog mappings.
- **Schema Introspection**: The agent can introspect HL7 v2 message schemas (segments, fields, components) and FHIR R4 resource structures so the Builder understands what data is available at each point in the pipeline. It knows about composite types (XAD for addresses, XPN for names, CX for identifiers) and can show sub-field level detail.
- **Dry-Run Testing**: The agent can execute a DTL against a sample message (DryRunDTL) to verify the transformation produces the expected output without deploying to a production. It can compare before/after messages field by field.
- **Cross-Format Mapping Insights**: Through the Transformation and Mapping Catalog, the agent (and the Builder via the admin UI) can see exactly which HL7 fields map through SDA3 to FHIR, which fields are inbound-only (arrive but don't continue), and which are outbound-only (produced in the target but not sourced from the input). This enables gap analysis before writing any code.

**Tools involved**: list_dtls, create_dtl, update_dtl, compile_dtl, dry_run_dtl, list_sda_fhir_dtls, describe_transformation_pipeline, get_hl7_schema_map, get_hl7_segment_fields, search_hs, compare_messages

**Skills involved**: DTL, HL7v2, FHIRR4, SDA, CDA, X12

**Example prompts**:
- "Create an interface that accepts any HL7 v2 message (ADT, ORU, ORM, MDM, SIU) on a single inbound MLLP service, transforms it to the appropriate FHIR R4 resources using the built-in HL7-to-SDA-to-FHIR pipeline, and POSTs the resulting Bundle to our FHIR Server."
- "Build a production that ingests C-CDA documents via a REST endpoint, validates them against the C-CDA R2.1 schema, transforms them to FHIR R4 Composition + DocumentReference + Patient/Encounter/Condition resources using SDA3 as the intermediate model, and persists the Bundle to our FHIR repository."

---

## 3. Developer Experience

### 2.1 Overview

Developers work exclusively through VS Code with the InterSystems ObjectScript extension. They write classes (Agent, MCP, ToolSet, Tool, Skill), compile them, and deploy via IPM. The admin UI is not their primary interface -- their deliverable is code that the Builder configures.

### 2.2 Security Requirements

| Requirement | Implementation |
|---|---|
| Authentication | IRIS native users with role-based access (%Developer role) |
| Source control | Git integration via VS Code; all classes under `src/cls/` |
| Secret management | IRIS Secured Wallet (collection: `AgenticInteropConnections`). No plaintext secrets in code, tables, or globals |
| API key isolation | Runtime LLM credentials are separate from development LLM (Claude Code). The agent's Bedrock/Anthropic key is stored in the Wallet, never in source |
| Namespace isolation | Code is namespace-agnostic (`$namespace` resolved at request time). No hardcoded namespace references |
| IPM packaging | `zpm load` on a clean instance must produce a working system. Shipped classes survive upgrades; user customizations survive in override tables |

### 2.3 User Stories

#### US-D01: Create a new Tool

**As a** Developer,  
**I want to** write an ObjectScript class that extends %AI.Tool with defined parameters (NAME, DESCRIPTION, INPUT, OUTPUT),  
**So that** the tool appears in the agent's catalog and can be invoked during chat conversations.

**Acceptance criteria:**
- Tool class compiles without errors
- Tool appears in the admin UI Tools tab after compilation
- Tool description follows the contract format: imperative verb, scope, side effects, expected inputs
- Tool input/output schemas are valid JSON Schema
- Tool includes at least one happy-path unit test

**Technical notes:**
- Tools live under `AgenticInterop.Tool.*` and extend `%AI.Tool`
- Each tool class can contain multiple tools (methods with the `[Tool]` annotation)
- Tool methods receive input as `%DynamicObject` and return output as `%DynamicObject`
- Mutating tools (create, update, delete) must set `RequiresConfirmation = 1`

#### US-D02: Create a new Skill (declarative sub-agent)

**As a** Developer,  
**I want to** write a Skill class with INSTRUCTIONS content (markdown text up to 32K characters),  
**So that** the agent can delegate domain-specific questions to a specialist sub-agent.

**Acceptance criteria:**
- Skill class extends `AgenticInterop.Skill.Base` (not `%AI.Agent.Skill` directly -- see bug workaround)
- INSTRUCTIONS parameter contains domain knowledge in plain prose (no markdown bold)
- Skill registers automatically via `SkillLoader` at agent build time
- Builder can override INSTRUCTIONS content in the admin UI without code changes

**Technical notes:**
- 12 shipped skills: Productions, DTL, BPL, RoutingRules, HL7v2, FHIRR4, SDA, RestInProductions, ESBPattern, X12, CDA, Adapters
- Skills are loaded as sub-agent tools: the LLM calls `skill_productions(question)` and gets a specialist answer
- Skills content was sourced from InterSystems PDF documentation (HL7, FHIR, SDA guides)

#### US-D03: Create a new MCP Server

**As a** Developer,  
**I want to** write an MCP Server class that groups related ToolSets under a named service,  
**So that** Builders can enable/disable entire capability domains (Production, Transform, Testing, Catalog) from the admin UI.

**Acceptance criteria:**
- MCP class extends `AgenticInterop.MCP.Base` (which extends `%AI.MCP.Service`)
- Parameters: NAME, DESCRIPTION, TOOLSETS (comma-separated list of ToolSet class names)
- MCP appears in the admin UI MCPs tab after compilation

#### US-D04: Deploy via IPM

**As a** Developer,  
**I want to** package the entire project as an IPM module (`agentic-interop`),  
**So that** a Builder can install it on any IRIS for Health 2026.2+ instance with `zpm "install agentic-interop"`.

**Acceptance criteria:**
- `module.xml` defines all sources, CSP applications, seed data, and install hooks
- `zpm load` on a clean HSCUSTOM namespace produces a working system
- Install hooks: CSP timeout patch applied, Interop Editor patched with AI buttons
- Uninstall hooks: Interop Editor reverted to original state

#### US-D05: Write custom tool implementations

**As a** Developer,  
**I want to** implement tools using SQL statements, ObjectScript class methods, or Embedded Python,  
**So that** I can leverage the best language for each task.

**Acceptance criteria:**
- SQL tools execute parameterized queries (no string concatenation for user input)
- ObjectScript tools use `$namespace` for namespace-agnostic operation
- Python tools use `##class(%SYS.Python).Import()` for LLM/MCP glue
- All tools handle errors gracefully and return structured error objects

#### US-D06: Build and maintain vector catalogs

**As a** Developer,  
**I want to** rebuild the Ens.* and HS.* vector catalogs from `%Dictionary`,  
**So that** the agent can semantically search for Business Hosts, adapters, and transformation classes.

**Acceptance criteria:**
- `AgenticInterop.Catalog.Builder` walks `%Dictionary.ClassDefinition` for relevant superclasses
- Embeddings use FastEmbed (384-dim HNSW vectors) via `%AI.RAG.KnowledgeBase`
- Curated prose descriptions (not auto-generated accessor signatures) feed the embeddings
- Catalog rebuild can be triggered from admin UI or scheduled

---

## 4. Builder Experience

### 4.1 Overview

Builders work through the IRIS Management Portal. They configure agents, manage LLM connections, review transformation mappings, tune skills, and operate the chatbot. No code editing required.

The admin UI is a vanilla JavaScript SPA served at `/agentic/admin/`. It communicates with `/api/agentic/` REST endpoints using JWT or Basic authentication.

### 4.2 Security Requirements

| Requirement | Implementation |
|---|---|
| Authentication | IRIS native auth (Basic or JWT). No UI element visible before login |
| Authorization | Role-based: `%ISCMgtPortal` group membership required |
| Audit | Every REST request logged to `AgenticInterop.Data.AuditLog` with username, namespace, session, job, path, method, status, duration |
| Secret handling | API keys entered in masked input, stored in IRIS Secured Wallet. Never displayed back, never logged |
| Session isolation | `UseSession=0` on all REST classes. No CSRF cookies. Bearer token per request |

### 4.3 User Stories -- Admin UI

#### US-B01: Configure an LLM Connection

**As a** Builder,  
**I want to** create an LLM connection (provider, model, region, API key) and test it,  
**So that** the agent can communicate with the LLM provider.

**Acceptance criteria:**
- Connection form: provider dropdown (OpenAI, Anthropic, Bedrock, Gemini, Azure OpenAI, NIM), model, region, base URL, max tokens
- API key entered in masked input, stored in Secured Wallet on Save
- "Test Connection" button sends a minimal test call and shows latency + model name on success, error text on failure
- Connection status indicator: green (tested OK), red (test failed), gray (untested)
- One connection can be marked as default
- Connections tab in admin UI: list all, create, edit, delete, test

Screenshot reference: Connections tab showing connection list with status indicators

#### US-B02: Configure the Agent

**As a** Builder,  
**I want to** customize the agent's system prompt, temperature, max iterations, bound MCPs, and skills,  
**So that** the agent behaves according to our integration requirements.

**Acceptance criteria:**
- Agent editor: name, description, instructions (textarea), temperature slider, max iterations
- MCP binding: checkbox list of available MCP servers
- Skill binding: checkbox list of available skills
- Provider selection: dropdown of configured connections
- Tool binding mode: MCP chain (Agent -> MCP -> ToolSet -> Tool) or bypass (Agent -> Tool directly)
- Changes saved as override rows (survive IPM upgrades)
- "Reset to defaults" button restores shipped class values

Screenshot reference: Agent editor showing HealthInterop configuration

#### US-B03: Configure MCP Servers

**As a** Builder,  
**I want to** enable/disable MCP servers and customize their descriptions,  
**So that** I can control which capability domains the agent has access to.

**Acceptance criteria:**
- MCP list: name, description, bound ToolSets
- Edit: name, short description, long description, ToolSets selection
- Changes persist as override rows

#### US-B04: Configure ToolSets and Tools

**As a** Builder,  
**I want to** view and customize ToolSets and their individual tools,  
**So that** I can tune tool descriptions, toggle tools on/off, and dry-run tools.

**Acceptance criteria:**
- ToolSet list: name, description, tool count
- ToolSet editor: name, description, tool manifest (JSON)
- Tool list: name, description, input/output schema, implementation type
- Tool dry-run: input JSON, execute, see output (non-mutating tools only)
- Tool descriptions are LLM-facing contracts -- invest in clarity

Screenshot reference: Tools tab showing the 42 tools across 5 classes

#### US-B05: Configure Skills

**As a** Builder,  
**I want to** view and edit the INSTRUCTIONS content for each skill,  
**So that** I can refine the agent's domain knowledge without Developer involvement.

**Acceptance criteria:**
- Skill list: name, class, description
- Skill editor: INSTRUCTIONS textarea (up to 32K characters)
- Changes saved as override (original shipped content preserved)
- 12 shipped skills covering: Productions, DTL, BPL, Routing Rules, HL7 v2, FHIR R4, SDA, REST in Productions, ESB Patterns, X12, CDA, Adapters

Screenshot reference: Skills tab showing skill list and editor

#### US-B06: Review Transformation Mappings (Transformation and Mapping Catalog)

**As a** Builder,  
**I want to** explore field-level mappings between HL7 v2, SDA3, and FHIR R4 formats,  
**So that** I can understand how data flows through the transformation pipeline and identify which IRIS classes handle each mapping.

**Acceptance criteria:**
- Format selection: Data From (HL7 v2, FHIR R4, FHIR STU3, CDA, X12, SDA3) and Data To
- SDA3 type sidebar: browse all SDA data types (Address, Allergy, Encounter, etc.)
- Field-level table: Source Field -> SDA3 -> Target Field, with sub-field detail (PID.11.3 City, not just PID-11)
- Coverage filter chips: End-to-end (green), Inbound only (blue), Outbound only (yellow) -- clickable toggles
- IRIS class names shown inline: inbound class (e.g. HS.Gateway.HL7.HL7ToSDA3) and outbound class (e.g. HS.FHIR.DTL.SDA3.vR4.Address.Address)
- Data flow explanation: "Data flows: HL7 v2 (inbound) -> SDA3 (canonical) -> FHIR R4 (outbound)"
- Text filter: search across field names, SDA types, and class names
- Pre-computed table: 1538 rows rebuilt on demand (~0.2s)
- Mapped rows sorted first for immediate visibility

Screenshot reference: Transforms tab showing HL7 v2 -> SDA3.Address -> FHIR R4 with class names

#### US-B07: Browse Vector Catalogs

**As a** Builder,  
**I want to** search the Ens.* and HS.* vector catalogs to find Business Hosts, adapters, and transformation classes,  
**So that** I can understand what's available in the IRIS class library.

**Acceptance criteria:**
- Catalog status: row count, last rebuild timestamp
- Rebuild button: triggers full re-index from %Dictionary
- Browse: paginated list of indexed classes with descriptions
- Search: semantic query against 384-dim embeddings, returns top-K results with scores

Screenshot reference: Catalogs tab showing catalog status and search

#### US-B08: View Audit Log

**As a** Builder,  
**I want to** view the audit trail of all API requests,  
**So that** I can track who did what, when, and how long it took.

**Acceptance criteria:**
- Audit log: timestamp, username, method, path, status, duration, request/response size
- Filter by kind (registry, editor, chat, health, namespace)
- Filter by username, date range
- Error details shown for failed requests

Screenshot reference: Audit tab showing request log

### 4.4 User Stories -- Chatbot

#### US-B09: Chat with the Agent

**As a** Builder,  
**I want to** type a natural-language request (e.g. "build me a production that ingests ADT messages and routes them to two downstream systems"),  
**So that** the agent searches catalogs, proposes hosts, asks for confirmation, creates the production, sends a test HL7 message, and validates the result.

**Acceptance criteria:**
- SSE streaming: tokens appear in real time, no loading spinner
- Tool calls render as cards: tool name, arguments, status (running/ok/error), collapsible result
- Mutating tool calls pause with an inline Approve/Reject prompt (ConfirmationGate policy)
- No single LLM turn exceeds 90 seconds (Monitor enforces 60s deadline + 50K token budget)
- Complex tasks broken into multiple short turns with visible progress
- Top bar: agent name, connection status, "New conversation" button

Screenshot reference: Chat interface showing streaming response with tool-call cards

#### US-B10: Review Conversation History

**As a** Builder,  
**I want to** review past conversations in the audit log,  
**So that** I can see what the user asked, what tools the agent called, and what the outcomes were.

**Acceptance criteria:**
- Every chat turn logged in audit with kind=chat
- Tool invocations include: tool name, input, output, duration, error
- Builder can trace a complete conversation from request to final response

---

## 5. End-to-End Scenario

This scenario demonstrates the full system working end-to-end:

1. **Developer** writes a new Tool class that creates HL7 routing rules, compiles it, and deploys via `zpm load`
2. **Builder** opens the admin UI, sees the new tool in the Tools tab, reviews its description
3. **Builder** opens the Transforms tab, selects HL7 v2 -> FHIR R4, reviews Address field mappings to understand the data flow
4. **Builder** opens the chatbot and asks: "Build me a production that receives ADT^A04 messages via MLLP, transforms patient demographics to FHIR R4, and sends them to a REST endpoint"
5. **Agent** searches the Ens.* catalog for appropriate Business Hosts (EnsLib.HL7.Service.TCPService, EnsLib.FHIR.Operation.REST)
6. **Agent** proposes the production layout and asks the Builder to approve
7. **Builder** clicks Approve
8. **Agent** creates the production, adds the hosts, configures settings
9. **Agent** builds and sends a test HL7 ADT^A04 message
10. **Agent** validates the result and reports success
11. **Builder** reviews the audit log to see the complete trace

---

## 6. Non-Functional Requirements

| Requirement | Target |
|---|---|
| Response latency | First token in < 2 seconds; full response in < 90 seconds per turn |
| Concurrent users | 5 simultaneous chat sessions (single IRIS instance) |
| Catalog rebuild | < 30 seconds for full Ens.* + HS.* re-index |
| Field mapping rebuild | < 1 second for full HL7/SDA3/FHIR trace (1538 rows) |
| Availability | System operational whenever IRIS is running; no external dependencies except LLM provider |
| Data retention | Audit logs retained indefinitely; no automatic purge |
| Browser support | Chrome 120+, Edge 120+, Firefox 120+ (ES2020 baseline) |

---

## Appendix A: Admin UI Tab Summary

| Tab | Purpose | Entity count |
|---|---|---|
| Agents | Agent configuration (system prompt, MCPs, skills, provider) | 1 (HealthInterop) |
| MCPs | MCP server enable/disable and description | 4 (Production, Transform, Testing, Catalog) |
| ToolSets | ToolSet grouping and description | 5 (Production, Transform, Testing, Catalog, Monitoring) |
| Tools | Individual tool schemas and dry-run | 42 tools |
| Skills | Skill INSTRUCTIONS editor | 12 skills |
| Connections | LLM provider credentials and health check | N (user-configured) |
| Catalogs | Vector catalog status, rebuild, search | 2 (Ens.*, HS.*) |
| Transforms | Field-level mapping explorer (Transformation and Mapping Catalog) | 1538 pre-computed rows |
| Audit | Request audit trail | All API calls |
