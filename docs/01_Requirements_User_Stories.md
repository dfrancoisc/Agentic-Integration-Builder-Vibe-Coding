# Agentic Agentic Interoperability Buildererability - Requirements and User Stories

> Version 3.0 | May 2026 | InterSystems AI Hub  
> Platform: InterSystems IRIS for Health 2026.2+, %AI Framework build 162.0

---

## 1. Introduction

### 1.1 Product Vision

A configuration-driven AI Copilot for InterSystems IRIS for Health that helps integration engineers build Productions, create Transformations, test HL7/FHIR messages, and explore the IRIS class catalog -- entirely through natural-language conversation or a structured admin UI.

The copilot bridges the gap between healthcare data expertise and InterSystems platform knowledge. Instead of navigating Management Portal screens and writing ObjectScript by hand, engineers describe what they need in plain English and the copilot builds it using real IRIS APIs.

### 1.2 The %AI Framework Foundation

The entire solution is built on the InterSystems %AI Framework -- the native AI infrastructure shipped with IRIS for Health 2026.2. The framework provides six core primitives that the copilot uses directly:

| %AI Primitive | Role in the Copilot |
|---|---|
| %AI.Agent | The central orchestrator. One agent instance ("HealthInterop") receives user messages, decides which tools or skills to invoke, and orchestrates multi-step workflows |
| %AI.MCP.Service | Model Context Protocol servers that group related capabilities into named service domains (Production, Transform, Testing, Catalog) |
| %AI.ToolSet | Tool grouping classes that organize tools by domain. Each ToolSet maps to one MCP server |
| %AI.Tool | Individual tool implementations. Each public ClassMethod in a Tool class is a callable tool with JSON Schema input/output |
| %AI.Agent.Skill | Declarative sub-agents that package domain knowledge as markdown INSTRUCTIONS. The main agent delegates domain questions to the appropriate skill |
| %AI.RAG.KnowledgeBase | Vector storage with HNSW index for semantic search over the IRIS class library (Business Hosts, adapters, transformation classes) |

The copilot does not replace or modify the %AI Framework. It builds on top of it -- every Agent, MCP, ToolSet, Tool, and Skill is a standard %AI subclass that the framework manages natively.

### 1.3 Framework Extensions

During development, we encountered three bugs in the %AI Framework that required application-level workarounds. These are extensions, not modifications -- the framework classes are untouched.

**Extension 1: AgenticInterop.Skill.Base (workaround for %AI.Agent.Skill %OnNew bug)**

The %AI.Agent.Skill %OnNew method passes a %DynamicObject to $ZF (the Foreign Function Interface call to the Rust LLM bridge), but the bridge expects a JSON string. This throws a <FUNCTION> error that prevents any skill from being instantiated. We created AgenticInterop.Skill.Base that overrides %OnNew to serialize the object before the $ZF call. All 15 domain skills extend this base class instead of %AI.Agent.Skill directly.

**Extension 2: Anthropic direct provider (workaround for Bedrock tool-result hang)**

When the agent calls a tool and receives the result, the Rust bridge hangs indefinitely when sending the tool result back to the AWS Bedrock Converse API. The hang occurs below the ObjectScript API surface. We switched to the Anthropic direct provider, which works correctly. The same agent, tools, and skills work without any code changes -- only the LLM connection configuration changes.

**Extension 3: AgenticInterop.Policy.ToolFilter (framework tool cleanup)**

The %AI Framework exposes default tools (FileSystem, SQL, ShellTools) that are irrelevant for healthcare interoperability and waste LLM tokens. The ToolFilter policy strips these before each LLM call, leaving only the 118 healthcare-specific tools the agent should see.

---

## 2. Personas

The system serves four distinct personas. The End User role is split into Interface Engineer and Operator because the distinction affects which tools are available, which permissions are required, and whether the agent operates as a dev-time or run-time tool.

### 2.1 Developer

| Attribute | Detail |
|---|---|
| Role | Builds agent infrastructure: writes Tool classes in ObjectScript, authors Skill documents with INSTRUCTIONS, builds vector catalog embeddings, packages and deploys via IPM |
| Primary interface | VS Code with InterSystems ObjectScript extension, terminal |
| Security scope | Full %DB access, %Dictionary write, source control, IPM packaging |
| Deliverable | Compiled classes inside an IPM package that the AI Hub Admin configures |

The Developer defines what the copilot can do. They write the code that implements tools, skills, and MCP servers. Their work happens in VS Code and ships as compiled classes.

### 2.2 AI Hub Admin

| Attribute | Detail |
|---|---|
| Role | Configures all AI settings: creates agents with custom system prompts, assembles MCP Servers from available ToolSets, links Skills to Agents, manages LLM connections, builds vector catalogs, reviews audit logs. Assigns Interface Engineer and Operator roles to end users |
| Primary interface | IRIS Management Portal -- AI Hub admin UI at /agentic/admin/ |
| Security scope | %ISCMgtPortal group membership, /api/agentic/ endpoints, Secured Wallet write for API keys |
| Deliverable | A fully configured agent ready for end users to interact with, with appropriate tool access per role |

The AI Hub Admin decides how the copilot behaves. They configure the agent's personality, which tools are available, which skills are loaded, and which LLM provider powers the responses. They also control which tools are available to Interface Engineers versus Operators through ToolSet configuration and role-based tool filtering. No code editing required -- everything is configuration through the admin UI.

### 2.3 End User: Interface Engineer

| Attribute | Detail |
|---|---|
| Role | Uses the chatbot to create new integration artifacts: productions, DTLs, BPLs, routing rules, lookup tables. This is a dev-time role -- the Interface Engineer authors new content that will be deployed |
| Primary interface | Chatbot at /agentic/chat/index.html (standalone or embedded in the Interop Editor) |
| Security scope | Chat access plus create/update/delete permissions on interoperability classes. All mutating operations require explicit approval via the confirmation gate. Changes flow through source control hooks |
| Deliverable | New or modified productions, transformations, and routing rules -- exported to source control |
| Primary use cases | UC-1 (Build Productions), UC-3 (Create Transformations) |

The Interface Engineer creates new integration artifacts through conversation. Because Interface Engineers create and modify class definitions, their work triggers source control hooks (see Section 10) and feeds into the CI/CD pipeline. Interface Engineer tool access includes create_production, add_business_host, create_dtl, compile_dtl, create_routing_rule, and other mutating tools.

### 2.4 End User: Operator

| Attribute | Detail |
|---|---|
| Role | Uses the chatbot to monitor, triage, and review existing integrations at run-time. The Operator does not create new productions or DTLs -- they observe, diagnose, and recommend |
| Primary interface | Chatbot at /agentic/chat/index.html (standalone or embedded in the Interop Editor) |
| Security scope | Chat access plus read-only access to production configurations and monitoring data. May adjust operational settings (pool size, throttle, retry intervals) but not structural changes (add/remove hosts, create classes) |
| Deliverable | Diagnosis reports, remediation recommendations, settings adjustments, modernization advice |
| Primary use cases | UC-2 (Review and Improve Existing Productions) |

The Operator focuses on run-time concerns: error triage, throughput monitoring, queue depth analysis, and production health assessment. They can recommend changes (refactor this DTL, add a dead-letter queue, increase pool size) but structural changes require an Interface Engineer. Operator tool access includes get_production, query_event_log, top_errors, message_summary, queue_status, and other read/monitoring tools.

### 2.5 Interface Engineer vs Operator: Tool Access

The distinction between Interface Engineer and Operator is enforced through tool availability. The AI Hub Admin configures which ToolSets are available to each role:

| Tool Category | Int. Eng. | Operator | Examples |
|---|---|---|---|
| Create/Update/Delete | Yes | No | create_production, create_dtl, add_business_host, create_routing_rule |
| Start/Stop | Yes | No | start_production, stop_production |
| Compile | Yes | No | compile_dtl |
| Read/Inspect | Yes | Yes | get_production, list_dtls, describe_class |
| Monitoring | Yes | Yes | query_event_log, top_errors, message_summary, queue_status |
| Search | Yes | Yes | search_ens, search_hs |
| Testing | Yes | Limited | send_hl7, validate_hl7_structure (Operators can validate but not send to live productions) |
| Settings adjustment | Yes | Yes (operational only) | update_business_host_settings (Operators limited to pool size, throttle, retry -- not adapter reconfiguration) |

This separation matters for security: the Operator's agent instance cannot create or modify class definitions, which means it cannot accidentally (or through prompt injection) alter production behavior. The AI Hub Admin enforces this by binding different ToolSets to Interface Engineer-mode and Operator-mode agent configurations.

---

## 3. Building the Foundation: Vector Catalogs

Before the copilot can help end users build productions or create transformations, it needs to know what Business Hosts, adapters, and transformation classes are available in the IRIS class library. This knowledge comes from two semantic search catalogs built with IRIS Vector Search.

### 3.1 Why Vector Catalogs

Integration engineers face a discovery problem: IRIS for Health ships hundreds of Business Host classes (services, processes, operations) and transformation classes (DTL, SDA helpers, FHIR mappers). Finding the right class for a given requirement means searching documentation, browsing %Dictionary, or asking a colleague. The vector catalogs solve this by embedding curated descriptions of every relevant class into a searchable vector index.

When an end user asks "build a production that receives HL7 messages over TCP", the agent searches the Ens.* catalog for "HL7 TCP inbound service" and gets back EnsLib.HL7.Service.TCPService as the top result -- without the user needing to know the exact class name.

### 3.2 The Ens.* Catalog (164 Business Hosts and Adapters)

The search_ens catalog indexes every class extending Ens.Host, Ens.BusinessService, Ens.BusinessProcess, Ens.BusinessOperation, Ens.OutboundAdapter, and Ens.InboundAdapter. For each class, the builder extracts:

- Class name and description
- Superclass hierarchy
- Key configurable parameters (the ones a user would set, not internal flags)
- Message types accepted and produced

The extraction uses %Dictionary.ClassDefinition as the source of truth, not documentation or spreadsheets. Curated prose descriptions feed the embeddings -- auto-generated accessor methods and structural boilerplate are stripped to avoid drowning out the semantic signal in the 384-dimensional embedding space.

### 3.3 The HS.* Catalog (58 Transformation Classes)

The search_hs catalog indexes HealthShare-specific transformation classes: DTL classes, FHIR mappers, SDA helpers, and HL7 gateways under the HS.* hierarchy. This catalog powers the transformation use case: when the agent needs to find existing transformations for a format pair, it searches search_hs rather than listing every DTL class in the namespace.

### 3.4 Technical Implementation

| Attribute | Detail |
|---|---|
| Embedding model | FastEmbed (384-dimensional vectors, bundled with IRIS) |
| Vector storage | %AI.RAG.KnowledgeBase with HNSW index |
| Query path | %AI.ToolMgr.ExecuteTool(kbName, args) -- the only working path. SQL EMBEDDING() does not work with bundled FastEmbed |
| Document format | Curated prose descriptions (class name + description + superclass + key parameters), not raw class dumps |
| Rebuild trigger | Admin UI Catalogs tab or API call |

### 3.5 Building and Rebuilding Catalogs

The AI Hub Admin builds the catalogs from the admin UI Catalogs tab. Each catalog shows its row count, last rebuild timestamp, kind breakdown (by superclass), and provides a test search panel for validating search quality.

Catalogs should be rebuilt when IRIS is upgraded (new classes may be available) or when the catalog builder logic changes. For all other cases, the persistent HNSW index serves queries without rebuilding.

---

## 4. Building the Foundation: LLM Connections

The copilot requires an LLM provider to generate responses. The AI Hub Admin configures LLM connections through the admin UI -- no environment variables, no config files, no code changes.

### 4.1 Supported Providers

| Provider | Config Fields | Secret Field |
|---|---|---|
| AWS Bedrock | region, model | AWS_BEARER_TOKEN_BEDROCK |
| Anthropic | model, base URL | ANTHROPIC_API_KEY |
| OpenAI | model, base URL | OPENAI_API_KEY |
| Azure OpenAI | endpoint, deployment, API version | AZURE_OPENAI_API_KEY |
| Google Gemini | model, region | GEMINI_API_KEY |
| NVIDIA NIM | model, base URL | NIM_API_KEY |

### 4.2 Connection Lifecycle

1. **Create**: The AI Hub Admin enters connection details in the admin UI Connections tab -- provider type, model name, region, base URL
2. **Store secret**: The API key is entered in a masked input field. On Save, the key is written to the IRIS Secured Wallet under collection AgenticInteropConnections. The key is never stored in SQL tables, globals, or source code
3. **Test**: The "Test Connection" button sends a minimal completion request (1 token) to the configured provider. On success, it displays the model name and response latency. On failure, it shows the error text verbatim
4. **Status**: Green dot (last test OK), red dot (last test failed), gray dot (never tested)
5. **Bind**: The agent configuration references a connection by name. At request time, the Manager loads the secret from the Wallet and configures the LLM client

### 4.3 Security: The IRIS Secured Wallet

All API keys are stored exclusively in the IRIS Secured Wallet (%Wallet.KeyValue collection AgenticInteropConnections). The security invariants are:

- API keys are NEVER stored in SQL tables, globals, or source code
- API keys are NEVER returned by any REST endpoint (not even masked)
- API keys are NEVER logged in the audit trail
- The only storage location is the IRIS Secured Wallet
- Connection test results (including error messages from the provider) ARE logged for debugging

---

## 5. Core Use Cases

The copilot addresses three primary use cases that cover the full lifecycle of healthcare integration work inside IRIS for Health. Each use case maps to a primary End User persona (Interface Engineer or Operator).

### 5.1 Use Case 1: Build Productions (Interface Engineer)

The most common task for an integration engineer is building new Productions -- the runtime message-processing pipelines in IRIS for Health. A Production consists of Business Services (inbound), Business Processes (routing/orchestration), and Business Operations (outbound), wired together with settings, routing rules, and message transformations.

The agent assists the Interface Engineer through the entire production lifecycle:

- **Discovery**: The Interface Engineer describes their integration goal in plain English (e.g., "build a production that receives ADT messages over MLLP, transforms them to FHIR R4, and sends them to a REST endpoint"). The agent searches the Ens.* vector catalog to find the right Business Host classes (EnsLib.HL7.Service.TCPService, EnsLib.FHIR.Operation.REST, etc.).
- **Proposal**: The agent presents a production layout -- which hosts to add, what settings to configure, which adapters to use -- and asks the Interface Engineer to approve before making changes.
- **Build**: Upon approval, the agent creates the production class, adds each Business Host with appropriate settings, creates routing rules, and compiles everything. Each mutating step goes through the confirmation gate.
- **Validation**: The agent runs PostBuildValidation to check for configuration errors, sends a test HL7 message through the pipeline, and verifies that messages flow end-to-end without errors.
- **Source Control**: After successful build, the newly created classes (production definition, routing rules) are captured by Health Connect Cloud source control hooks and exported to the Git repository for CI/CD review (see Section 10).

**Tools involved**: search_ens, describe_class, create_production, add_business_host, update_business_host_settings, create_routing_rule, start_production, stop_production, PostBuildValidation, BuildAndSendHL7TestMessage

**Skills involved**: Productions, Adapters, HL7v2, RoutingRules

**Example prompts**:
- "Build a complete production that receives HL7 v2.5 ADT^A01 admission messages over an inbound folder, transforms each ADT into an ORU^R01 observation report, routes the transformed messages to an outbound folder, and sends failures to a dead-letter folder."
- "I need a production that receives X12 270 eligibility inquiries over SFTP, calls our internal eligibility REST API, constructs the X12 271 response, and writes it back to the payer's SFTP outbound folder."

### 5.2 Use Case 2: Review and Improve Existing Productions (Operator, with Interface Engineer escalation)

Integration engineers inherit productions built by others, or maintain productions that were built months or years ago. They need to understand what a production does, identify problems, and find opportunities to modernize it using newer IRIS features and best practices.

This use case spans both personas. The Operator handles the read-only investigative work (error triage, health assessment, throughput analysis). When the investigation reveals changes that need to be made (refactor a DTL, add a dead-letter queue, restructure routing rules), those changes escalate to the Interface Engineer.

**Operator activities (read-only, run-time):**

- **Error Triage**: The agent queries the Event Log and Message Header tables to find recent errors, groups them by Business Host, identifies the most frequent error messages, and recommends remediation steps. It can spot suspended or errored messages that need manual intervention.
- **Production Health Assessment**: The agent inspects the production configuration, checks queue depths, reviews throughput statistics, and identifies bottlenecks. It can recommend settings changes (pool size, throttle, retry intervals) based on what it observes.
- **Operational Settings Adjustment**: The Operator can adjust operational settings (pool size, throttle, retry intervals, call interval) through the agent without Interface Engineer involvement. These are runtime tuning changes, not structural modifications.

**Interface Engineer activities (mutating, dev-time):**

- **DTL Review and Refactoring**: The agent reviews Data Transformation Language (DTL) definitions and identifies hardcoded values that should be lookup tables, missing null checks on source fields, incorrect handling of repeating fields, and segments being dropped. It suggests refactored versions with explanations. Implementing the refactored DTL requires Interface Engineer permissions.
- **Modernization**: The agent knows about newer IRIS features (via Skills) and can recommend upgrades -- for example, replacing a custom BPL with a built-in DTL, using record maps instead of custom parsers, or adopting the HL7-to-SDA-to-FHIR pipeline instead of point-to-point transformations. Implementing these changes requires Interface Engineer permissions.

**Tools involved (Operator)**: get_production, query_event_log, top_errors, query_message_status, message_summary, queue_status, describe_class, list_dtls, get_dtl

**Tools involved (Interface Engineer escalation)**: update_business_host_settings, update_dtl, compile_dtl, create_routing_rule

**Skills involved**: Productions, DTL, BPL, Adapters, ESBPattern

**Example prompts (Operator)**:
- "Review the last 2 hours of errors across all productions. Group them by Business Host, show the top 5 most frequent error messages with counts, identify messages stuck in Suspended or Error state, and recommend remediation steps."
- "What is the throughput of the ADT_Router process over the last 24 hours? Are there any queue depth spikes?"

**Example prompts (Interface Engineer)**:
- "Review our current ADT_A08_to_SDA3 DTL for: hardcoded values that should be lookup tables, missing null checks on source fields, incorrect handling of repeating PID-3 identifiers, and segments we are dropping that we should not."
- "Refactor the ADT routing to use the built-in HL7-to-SDA-to-FHIR pipeline instead of our custom point-to-point DTLs."

### 5.3 Use Case 3: Create and Optimize Transformations (Interface Engineer)

Data Transformations are the heart of healthcare interoperability. Integration engineers spend most of their time writing, debugging, and optimizing DTL (Data Transformation Language) and BPL (Business Process Language) definitions that convert messages between formats -- HL7 v2 to SDA3, SDA3 to FHIR R4, CDA to SDA3, and more.

The agent assists the Interface Engineer with transformation work at every stage:

- **Pipeline Discovery**: The agent traces the full transformation pipeline for any format pair (e.g., HL7 v2 to FHIR R4) showing which IRIS classes handle each step, what intermediate formats are used, and where the data flows. The Transformation and Mapping Catalog (Transforms tab in the admin UI) provides this information visually at the field level.
- **DTL Creation**: The agent creates new DTL definitions by first searching the HS.* catalog for existing transformations that handle the same or similar format pair, then scaffolding a new DTL with the correct source/target classes and document types. It can populate field mappings based on the Transformation and Mapping Catalog.
- **Schema Introspection**: The agent can introspect HL7 v2 message schemas (segments, fields, components) and FHIR R4 resource structures so the Interface Engineer understands what data is available at each point in the pipeline. It knows about composite types (XAD for addresses, XPN for names, CX for identifiers) and can show sub-field level detail.
- **Dry-Run Testing**: The agent can execute a DTL against a sample message (DryRunDTL) to verify the transformation produces the expected output without deploying to a production. It can compare before/after messages field by field.
- **Cross-Format Mapping Insights**: Through the Transformation and Mapping Catalog, the agent (and the AI Hub Admin via the admin UI) can see exactly which HL7 fields map through SDA3 to FHIR, which fields are inbound-only (arrive but don't continue), and which are outbound-only (produced in the target but not sourced from the input). This enables gap analysis before writing any code.
- **Source Control**: After creating or modifying DTLs and BPLs, the source control hooks capture the new class definitions and export them to Git for CI/CD review (see Section 10).

**Tools involved**: list_dtls, create_dtl, update_dtl, compile_dtl, dry_run_dtl, list_sda_fhir_dtls, describe_transformation_pipeline, get_hl7_schema_map, get_hl7_segment_fields, search_hs, compare_messages

**Skills involved**: DTL, HL7v2, FHIRR4, SDA, CDA, X12

**Example prompts**:
- "Create an interface that accepts any HL7 v2 message (ADT, ORU, ORM, MDM, SIU) on a single inbound MLLP service, transforms it to the appropriate FHIR R4 resources using the built-in HL7-to-SDA-to-FHIR pipeline, and POSTs the resulting Bundle to our FHIR Server."
- "Build a production that ingests C-CDA documents via a REST endpoint, validates them against the C-CDA R2.1 schema, transforms them to FHIR R4 Composition + DocumentReference + Patient/Encounter/Condition resources using SDA3 as the intermediate model, and persists the Bundle to our FHIR repository."

---

## 6. Developer Experience

### 6.1 Overview

Developers work exclusively through VS Code with the InterSystems ObjectScript extension. They write classes (Agent, MCP, ToolSet, Tool, Skill), compile them, and deploy via IPM. The admin UI is not their primary interface -- their deliverable is code that the AI Hub Admin configures.

### 6.2 User Stories

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
- Tool specifies whether it is available to Interface Engineer, Operator, or both roles

**Technical notes:**
- Tools live under AgenticInterop.Tool.* and extend %AI.Tool
- Each tool class can contain multiple tools (methods with the [Tool] annotation)
- Tool methods receive input as %DynamicObject and return output as %DynamicObject
- Mutating tools (create, update, delete) must set RequiresConfirmation = 1
- Each tool must validate the authenticated user's permissions before executing (see Section 9.3)

#### US-D02: Create a new Skill (declarative sub-agent)

**As a** Developer,  
**I want to** write a Skill class with INSTRUCTIONS content (markdown text up to 32K characters),  
**So that** the agent can delegate domain-specific questions to a specialist sub-agent.

**Acceptance criteria:**
- Skill class extends AgenticInterop.Skill.Base (not %AI.Agent.Skill directly -- see Section 1.3 for the bug workaround)
- INSTRUCTIONS parameter contains domain knowledge in plain prose (no markdown bold)
- Skill registers automatically via SkillLoader at agent build time
- AI Hub Admin can override INSTRUCTIONS content in the admin UI without code changes

**Technical notes:**
- 12 shipped skills: Productions, DTL, BPL, RoutingRules, HL7v2, FHIRR4, SDA, RestInProductions, ESBPattern, X12, CDA, Adapters
- Skills are loaded as sub-agent tools: the LLM calls skill_productions(question) and gets a specialist answer
- Skills content was sourced from InterSystems PDF documentation (HL7, FHIR, SDA guides)

#### US-D03: Create a new MCP Server

**As a** Developer,  
**I want to** write an MCP Server class that groups related ToolSets under a named service,  
**So that** AI Hub Admins can enable/disable entire capability domains (Production, Transform, Testing, Catalog) from the admin UI.

**Acceptance criteria:**
- MCP class extends AgenticInterop.MCP.Base (which extends %AI.MCP.Service)
- Parameters: NAME, DESCRIPTION, TOOLSETS (comma-separated list of ToolSet class names)
- MCP appears in the admin UI MCPs tab after compilation

#### US-D04: Deploy via IPM

**As a** Developer,  
**I want to** package the entire project as an IPM module (agentic-interop),  
**So that** an AI Hub Admin can install it on any IRIS for Health 2026.2+ instance with zpm "install agentic-interop".

**Acceptance criteria:**
- module.xml defines all sources, CSP applications, seed data, and install hooks
- zpm load on a clean namespace produces a working system
- Install hooks: CSP timeout patch applied, Interop Editor patched with AI buttons
- Uninstall hooks: Interop Editor reverted to original state

#### US-D05: Write custom tool implementations

**As a** Developer,  
**I want to** implement tools using SQL statements, ObjectScript class methods, or Embedded Python,  
**So that** I can leverage the best language for each task.

**Acceptance criteria:**
- SQL tools execute parameterized queries (no string concatenation for user input)
- ObjectScript tools use $namespace for namespace-agnostic operation
- Python tools use ##class(%SYS.Python).Import() for LLM/MCP glue
- All tools handle errors gracefully and return structured error objects
- All mutating tools check the authenticated user's permissions before executing

#### US-D06: Build and maintain vector catalogs

**As a** Developer,  
**I want to** rebuild the Ens.* and HS.* vector catalogs from %Dictionary,  
**So that** the agent can semantically search for Business Hosts, adapters, and transformation classes.

**Acceptance criteria:**
- AgenticInterop.Catalog.Builder walks %Dictionary.ClassDefinition for relevant superclasses
- Embeddings use FastEmbed (384-dim HNSW vectors) via %AI.RAG.KnowledgeBase
- Curated prose descriptions (not auto-generated accessor signatures) feed the embeddings
- Catalog rebuild can be triggered from admin UI or scheduled

#### US-D07: Implement permission-aware tools

**As a** Developer,  
**I want to** write tools that validate the authenticated user's permissions before executing,  
**So that** the LLM agent cannot bypass the user's security constraints even if the tool is technically available.

**Acceptance criteria:**
- Every mutating tool receives the authenticated username from the REST layer
- The tool checks the user's roles and database privileges before executing (e.g., $System.Security.Check())
- If the user lacks permission, the tool returns a structured error explaining which permission is missing
- The agent receives this error and explains to the user what happened (not a silent failure)
- Foundation namespace (HSLIB, HSSYS, ENSLIB) writes are always rejected regardless of user role

---

## 7. AI Hub Admin Experience

### 7.1 Overview

AI Hub Admins work through the IRIS Management Portal. They configure agents, manage LLM connections, review transformation mappings, tune skills, and prepare the copilot for end users. No code editing required.

The admin UI is a vanilla JavaScript SPA served at /agentic/admin/. It communicates with /api/agentic/ REST endpoints using JWT or Basic authentication. Every action is logged to the audit trail.

### 7.2 Configure the Agent

The AI Hub Admin customizes the agent's system prompt, temperature, max iterations, bound MCPs, and skills so that the agent behaves according to the organization's integration requirements.

- Agent editor: name, description, instructions (textarea), temperature slider, max iterations
- MCP binding: checkbox list of available MCP servers
- Skill binding: checkbox list of available skills
- Provider selection: dropdown of configured connections
- Tool binding mode: MCP chain (Agent -> MCP -> ToolSet -> Tool) or bypass (Agent -> Tool directly)
- Changes saved as override rows (survive IPM upgrades)
- "Reset to defaults" button restores shipped class values

Note: The AI Hub Admin can configure separate agent profiles for Interface Engineer and Operator roles, each with different ToolSet bindings. This enforces the privilege separation described in Section 2.5.

### 7.3 Configure MCP Servers

The AI Hub Admin enables/disables MCP servers and customizes their descriptions to control which capability domains the agent has access to.

Six MCP servers ship out of the box:
- mcp.production: CRUD productions, business hosts, settings, start/stop, routing rules, HL7 host builders, System Default Settings, FIFO recovery, timestamp/schedule helpers
- mcp.transform: CRUD DTL/BPL, FHIR Process config, FHIR Lookup tables, HL7 search tables, HL7 schema introspection
- mcp.testing: Send HL7/FHIR messages, validate structure/semantics, compare messages
- mcp.catalog: Vector search, class introspection, namespace info, glossary, error-code lookup
- mcp.fhirserver: FHIR R4 endpoint discovery and configuration, CapabilityStatement, metadata packages, resource CRUD/search/$validate, async directory load with run history
- mcp.bulkfhir: Bulk FHIR Coordinator config CRUD, $export sessions, SMART backend OAuth + SSL + credential provisioning

### 7.4 Configure ToolSets and Tools

The AI Hub Admin views and customizes ToolSets and their individual tools -- tuning descriptions, toggling tools on/off, and dry-running tools to verify behavior.

- ToolSet list: name, description, tool count
- Tool list: name, description, input/output schema, implementation type
- Tool dry-run: input JSON, execute, see output (non-mutating tools only)
- Tool descriptions are LLM-facing contracts -- clear descriptions lead to better tool selection

118 tools across 7 Tool classes (composed into 7 ToolSets):
- Production (29 tools): list/get/create/delete productions, add/remove/update business hosts, start/stop, PostBuildValidation, routing-rule CRUD, ConfigureHL7TCPService / ConfigureHL7TCPOperation / ConfigureHL7Router (Validation="" baked in), EnableHL7TraceOperations, System Default Settings CRUD, GetEffectiveSetting, ListProductionQueues, ReleaseFIFOHold / ReleaseAllFIFOHolds, PreviewTimestampSpec, ValidateScheduleSpec, EnsureDirectory.
- Transform (30 tools): DTL CRUD + DryRunDTL + BuildDTLXml + SetCustomDTLPackage + ListHL7ToSDADTLs + ListSDAFHIRDTLs, BPL CRUD + ValidateBPL + BuildHL7ToFHIRBPL + BuildHL7ToSDABPL, ConfigureSDAToFHIRProcess / ConfigureFHIRToSDAProcess, FHIR Lookup table CRUD, CreateHL7SearchTable, GetHL7SchemaMap, GetHL7SegmentFields, ListLookupTables, DescribeTransformationPipeline.
- Testing (8 tools): send_hl7, send_fhir, validate_hl7_structure, BuildAndSendHL7TestMessage, ...
- Catalog (7 tools): search_ens, search_hs, describe_class, get_namespace, ...
- Monitoring (5 tools): query_event_log, group_errors, message_status, throughput_stats, queue_status.
- FHIR Server (26 tools): endpoint inspect/config, CapabilityStatement, metadata packages, resource CRUD/search/$validate, async directory load + ingestion metrics + run history.
- Bulk FHIR (13 tools): Bulk FHIR Coordinator (BFC) config CRUD, $export sessions, SMART backend OAuth + SSL + credential provisioning.

### 7.5 Configure Skills

The AI Hub Admin views and edits the INSTRUCTIONS content for each skill, refining the agent's domain knowledge without Developer involvement.

15 shipped domain skills (plus AgenticInterop.Skill.Base, the abstract %OnNew workaround class):

| Skill | Domain |
|---|---|
| Productions | Production anatomy, BS/BP/BO patterns, lifecycle management |
| DTL | DTL syntax, foreach, subtransforms, lookup tables, virtual documents |
| BPL | BPL activities, compensation handlers, async patterns |
| RoutingRules | Rule sets, constraints, when-conditions, dead-letter handling |
| HL7v2 | Message types, segments, ACK semantics, schema navigation |
| FHIRR4 | Resources, references, search parameters, R4 bundles |
| SDA | SDA3 model as transformation hub, HL7-to-SDA-to-FHIR pipeline |
| RestInProductions | REST services and operations inside productions |
| ESBPattern | Using a production as an Enterprise Service Bus |
| X12 | HIPAA EDI transactions, envelope structures, schemas |
| CDA | CDA/C-CDA documents, XSLT pipelines, SDA conversion |
| Adapters | File/TCP/HTTP/REST/FTP/SQL/MQTT/SOAP adapter selection and configuration |

### 7.6 Review Transformation Mappings (Transformation and Mapping Catalog)

The Transforms tab provides a visual field-level mapping explorer showing how data flows between external formats (HL7 v2, FHIR R4, CDA, X12) through the SDA3 canonical model.

SDA3 is the universal pivot in IRIS for Health -- all external formats map through it. The Transformation and Mapping Catalog shows both directions (inbound and outbound) and identifies:
- End-to-end fields: traced from source through SDA3 to target
- Inbound only fields: arrive in SDA3 but have no outbound target
- Outbound only fields: produced in the target but not sourced from the input

Features:
- Format pair selection: any combination of HL7 v2, FHIR R4, FHIR STU3, CDA, X12, SDA3
- SDA3 type sidebar: 110 data types, browsable and filterable
- Sub-field level detail: PID.11.3 City, not just PID-11 PatientAddress
- IRIS class names inline: which class handles each direction of the mapping
- Coverage filter chips: End-to-end (green), Inbound only (blue), Outbound only (yellow)
- Text filter: search across field names, SDA types, class names
- 1,538 pre-computed rows, rebuilt on demand in ~0.2 seconds

### 7.7 Browse Vector Catalogs

The AI Hub Admin manages vector catalogs from the Catalogs tab:
- Catalog status: row count, kind breakdown, last rebuild timestamp
- Rebuild button: triggers full re-index from %Dictionary
- Browse: paginated list of indexed classes with descriptions
- Search: semantic query against 384-dim embeddings, returns top-K results with scores

### 7.8 View Audit Log

The Audit tab shows all API requests with filters by kind (registry, editor, chat, health, namespace) and username.

Every REST request is captured with: timestamp, username, namespace, session ID, job, HTTP method, path, status code, request/response size, duration, error text (if any), and kind classification.

### 7.9 User Stories Covered by the AI Hub Framework

The following capabilities are required by this project but are expected to be provided by the AI Hub framework itself rather than implemented in the application layer. They are listed here to ensure coverage tracking:

| Story | Requirement | Expected Coverage |
|---|---|---|
| US-H01 | Agent lifecycle management (create, configure, delete agents) | AI Hub admin UI |
| US-H02 | MCP server registration and discovery | AI Hub framework (%AI.MCP.Service) |
| US-H03 | Tool schema validation and registration | AI Hub framework (%AI.Tool) |
| US-H04 | LLM provider abstraction (Bedrock, Anthropic, OpenAI, etc.) | AI Hub framework (LLM bridge) |
| US-H05 | SSE streaming from agent to client | AI Hub framework (%AI.Agent.StreamChat) |
| US-H06 | Conversation state management across turns | AI Hub framework (%AI.Agent conversation context) |
| US-H07 | Role-based access control for AI Hub admin operations | AI Hub framework (to be confirmed) |
| US-H08 | Source control hook integration for class changes | Health Connect Cloud (%SourceControl hooks) |

If any of these are not provided by the framework, they must be built at the application layer. The current implementation includes application-level workarounds for US-H04 (Bedrock hang) and US-H07 (custom role checks).

---

## 8. End User Experience

### 8.1 The Chatbot

The End User (Interface Engineer or Operator) interacts with the copilot through a streaming chat interface. The chatbot is available at /agentic/chat/index.html (standalone) or embedded in the Interop Editor via an AI button (iframe mode).

Key capabilities:
- SSE streaming: tokens appear in real time, no loading spinner
- Tool calls render as inline cards: tool name, arguments, status (running/ok/error), collapsible result
- Mutating tool calls pause with an inline Approve/Reject prompt (ConfirmationGate policy)
- Conversation history rail with search, resume, and rename
- Starter prompts organized by use case: Build, Transform, Operate, Review
- Top bar shows agent name, connection status, and "New Chat" button

### 8.2 Performance Guardrails

- Monitor enforces 60-second deadline + 50,000 token budget per turn
- Complex tasks broken into multiple short turns with visible progress at each phase
- If a turn exceeds limits, the monitor triggers a graceful stop and the agent summarizes partial results

### 8.3 Interface Engineer User Stories

#### US-E01: Build a production through conversation

**As a** Interface Engineer,  
**I want to** describe an integration requirement in plain English and have the agent build the production,  
**So that** I can create working integrations without manually navigating the Management Portal.

**Acceptance criteria:**
- Agent searches catalogs for appropriate Business Hosts
- Agent proposes a production layout and waits for approval
- Each mutating step goes through the confirmation gate
- PostBuildValidation runs after build to verify configuration
- Test message sent through the pipeline to verify end-to-end flow
- Newly created classes are captured by source control hooks (if configured)

#### US-E02: Create a transformation through conversation

**As a** Interface Engineer,  
**I want to** describe a data transformation requirement and have the agent scaffold the DTL,  
**So that** I can create transformations with the correct source/target classes and field mappings.

**Acceptance criteria:**
- Agent searches HS.* catalog for existing transformations
- Agent creates DTL with correct source/target document types
- Dry-run executes against sample data before deployment
- Compiled DTL is captured by source control hooks (if configured)

### 8.4 Operator User Stories

#### US-E03: Triage production errors

**As an** Operator,  
**I want to** ask the agent to review recent errors and group them by cause,  
**So that** I can quickly identify systemic issues and prioritize remediation.

**Acceptance criteria:**
- Agent queries Event Log for recent errors (no mutating operations)
- Results grouped by Business Host and error message
- Suspended and errored messages identified
- Remediation steps recommended (but not automatically applied)
- Agent does NOT have access to create/delete tools in Operator mode

#### US-E04: Assess production health

**As an** Operator,  
**I want to** ask the agent for a health assessment of a running production,  
**So that** I can identify bottlenecks and tuning opportunities without reading raw metrics.

**Acceptance criteria:**
- Agent inspects production configuration, queue depths, and throughput
- Agent recommends operational settings changes (pool size, throttle, retry)
- Agent can apply operational settings adjustments if the Operator approves
- Agent cannot make structural changes (add/remove hosts, create classes)

---

## 9. Audit and Security Requirements

### 9.1 Authentication

| Method | Use Case |
|---|---|
| Basic auth | Direct admin UI and chatbot access (standalone mode) |
| JWT Bearer | Embedded access from Interop Editor (token passed via postMessage bridge) |

All REST endpoints require authentication. UnauthenticatedEnabled=0 on the /api/agentic/ web application. No UI element (banner, button, link, modal, or text) is visible before login.

### 9.2 Authorization and Role-Based Access

- AI Hub Admin operations require %ISCMgtPortal group membership
- End User chat access requires authenticated IRIS user
- Interface Engineer-mode tools (create, update, delete, compile, start, stop) require specific roles assigned by the AI Hub Admin
- Operator-mode tools (read, monitor, query) require basic authenticated access
- Mutating operations (create, update, delete) require explicit Approve from the End User via the ConfirmationGate policy -- the agent cannot modify the system without user consent
- Cross-namespace access validated via database-level read permissions and X-IRIS-Namespace header

### 9.3 LLM Service Identity and Permission Delegation

The LLM agent executes tool calls within the IRIS process. This creates a critical security requirement: the agent must NEVER bypass the authenticated user's permissions, even if the agent's service identity has broader access.

**The principle**: The agent acts on behalf of the authenticated user, not on its own behalf. Every tool call is executed under the authenticated user's security context. If the user cannot perform an action through the Management Portal, the agent must not perform it either.

**Implementation requirements:**

- Every tool receives the authenticated username from the REST layer (extracted from Basic auth or JWT)
- Before executing a mutating operation, the tool checks the user's roles and database privileges via $System.Security.Check() or equivalent
- If the user lacks the required permission, the tool returns a structured error: { "error": { "code": "PERMISSION_DENIED", "message": "User 'jsmith' does not have %DB_WRITE access to namespace PRODUCTION", "required_permission": "%DB_WRITE" } }
- The agent surfaces this error to the user in plain language: "I cannot create that production because your account does not have write access to this namespace. Please contact your administrator."
- The audit log records both the attempted action and the permission denial

**Example scenarios:**

| User Request | User Has Permission? | Agent Behavior |
|---|---|---|
| "Create a new production" | Yes (%DB_WRITE on target namespace) | Agent proceeds with confirmation gate |
| "Create a new production" | No (read-only access) | Agent explains the user lacks write permission |
| "Create an OAuth 2.0 client" | No (requires %Admin_Secure) | Agent explains the user needs security admin privileges |
| "Query the event log" | Yes (any authenticated user) | Agent executes the read-only query |
| "Start a production" | Yes (Ens.* role) | Agent proceeds with confirmation gate |
| "Modify classes in HSLIB" | No (Foundation namespace) | Agent explains Foundation namespaces are read-only |

### 9.4 Namespace Constraints

Not all namespaces are equal. IRIS for Health distinguishes between Foundation namespaces (shipped with the product) and non-Foundation namespaces (created by users for their integration work).

**Foundation namespaces** (HSLIB, HSSYS, ENSLIB, and others marked as Foundation):
- Always read-only for the agent, regardless of user permissions
- The agent can search and inspect classes in Foundation namespaces (for catalog queries and class introspection)
- The agent MUST NOT create, modify, or delete any class definition in a Foundation namespace
- This is a hard constraint -- the ConfirmationGate cannot override it

**Non-Foundation namespaces** (HSCUSTOM, user-created namespaces):
- The agent respects the authenticated user's database-level permissions
- Users with %DB_WRITE can create and modify classes (through the agent with confirmation)
- Users with read-only access can inspect and search but not modify
- The $namespace variable is resolved at request time from the X-IRIS-Namespace header

**Implementation**: Every mutating tool must:
1. Resolve the target namespace from the request context
2. Check whether the namespace is a Foundation namespace (via $System.OBJ.IsFoundation() or equivalent)
3. If Foundation: reject with a clear error, regardless of user permissions
4. If non-Foundation: check user's database privileges on that namespace
5. If permitted: proceed through the confirmation gate
6. If denied: return a structured permission error

### 9.5 Interface Engineer vs Operator Privilege Separation

The security distinction between Interface Engineer and Operator is enforced at two levels:

**Level 1: Tool availability (configured by AI Hub Admin)**
- The AI Hub Admin binds different ToolSets to Interface Engineer-mode and Operator-mode agent configurations
- Operator agents do not have access to mutating tools (create_production, create_dtl, compile_dtl, etc.)
- Even if an Operator user has database-level write access, the agent cannot call tools that are not bound to the Operator configuration
- This prevents prompt injection attacks from escalating Operator sessions to Interface Engineer-level access

**Level 2: Permission validation (enforced by tools)**
- Even in Interface Engineer mode, every mutating tool validates the user's permissions before executing
- An Interface Engineer user without %DB_WRITE on a specific namespace cannot create classes there
- The ConfirmationGate provides a third layer: the user must explicitly approve each mutating action

### 9.6 Audit Logging

Every REST request is captured in AgenticInterop.Data.AuditLog:

| Field | Description |
|---|---|
| Created | When the request was received |
| Username | Authenticated IRIS user |
| Namespace | Active namespace at request time |
| SessionId | Browser session identifier |
| Job | IRIS job number |
| Method | GET, POST, PUT, DELETE |
| Path | /api/agentic/chat/stream, /api/agentic/registry/agents, etc. |
| StatusCode | HTTP response status |
| RequestSize | Bytes received |
| ResponseSize | Bytes sent |
| DurationMs | End-to-end request time in milliseconds |
| ErrorText | Error message (if status >= 400), including permission denials |
| Kind | Classification: registry, editor.agent, chat, namespace, health |

The audit log is queryable from the admin UI Audit tab with filters by kind, username, and date range. Every chat conversation, configuration change, catalog operation, and permission denial is traced.

### 9.7 Secret Management

All API keys and credentials are stored in the IRIS Secured Wallet (%Wallet.KeyValue, collection AgenticInteropConnections). Security invariants:
- API keys are NEVER stored in SQL tables, globals, or source code
- API keys are NEVER returned by any REST endpoint
- API keys are NEVER logged in the audit trail
- The Wallet is the single source of truth for secrets
- Connection test results (including provider error messages) ARE logged for debugging

### 9.8 Security Policies

**ConfirmationGate policy**: Mutating tools (create, update, delete, start, stop) pause execution and surface an Approve/Reject prompt in the chat UI before executing. The agent cannot modify productions, transformations, or routing rules without the End User clicking Approve. This is the last line of defense after permission checks and namespace validation.

**ToolFilter policy**: Strips framework-default tools (FileSystem, SQL, ShellTools) from the LLM's tool catalog before each request. Without this filter, the LLM receives 60+ generic tools that could theoretically access file system operations or raw SQL execution. The filter reduces the catalog to the 118 healthcare-specific tools defined by the project. This policy also prevents the LLM from using tools that could bypass the permission model (e.g., raw SQL execution that sidesteps class-level access checks).

---

## 10. Source Control and Change Control Integration

### 10.1 The Problem

When the agent creates a new production, DTL, BPL, or routing rule, it is creating or modifying IRIS class definitions. These class changes must flow through the same change control process as any manual edit -- version control tracking, peer review, and CI/CD validation. Without source control integration, agent-created artifacts become invisible to the deployment pipeline.

### 10.2 Health Connect Cloud Source Control Model

Health Connect Cloud provides version control hooks via the %SourceControl framework. These hooks:
- Intercept class save and compile events
- Export class definitions to a local Git repository
- Track which user made which change
- Feed into a GitLab-based CI/CD pipeline that validates, tests, and deploys changes across environments (dev -> staging -> production)

The agent's work must integrate with this model. Agent-created artifacts are NOT a special case -- they follow the same path as manually created artifacts.

### 10.3 Integration Requirements

**Artifact capture**: When the agent creates or modifies a class (production, DTL, BPL, routing rule, lookup table), the %SourceControl hooks fire automatically because the agent uses standard IRIS APIs ($System.OBJ.Compile, %Dictionary) that trigger the hooks.

**User attribution**: Changes are attributed to the authenticated user (the Interface Engineer), not to the agent's service account. The source control hooks capture the $username from the IRIS process context. Since the REST layer sets the process context to the authenticated user, the commit is attributed correctly.

**No bypass**: The agent does not use any mechanism that would bypass source control hooks. It does not write directly to globals, manipulate ^ROUTINE or ^oddDEF, or use any undocumented internal API. All class modifications go through the documented %Dictionary and $System.OBJ APIs.

### 10.4 CI/CD Pipeline Flow

```
Interface Engineer asks agent to create a production
  --> Agent creates class via $System.OBJ.Compile()
    --> %SourceControl hook fires
      --> Class definition exported to local Git working directory
        --> Interface Engineer (or automated process) commits and pushes to GitLab
          --> CI/CD pipeline runs: lint, validate, test
            --> On success: deploy to staging/production
```

### 10.5 User Stories

#### US-SC01: Agent-created artifacts appear in source control

**As a** Interface Engineer,  
**I want** the productions, DTLs, and BPLs that the agent creates to be captured by source control hooks,  
**So that** they flow through the same CI/CD pipeline as manually created artifacts.

**Acceptance criteria:**
- Agent uses standard IRIS APIs ($System.OBJ.Compile, %Dictionary) for all class operations
- %SourceControl hooks fire on every class save and compile
- Exported class definitions appear in the local Git working directory
- Changes are attributed to the authenticated user, not the agent

**Coverage note:** This story is primarily covered by the Health Connect Cloud %SourceControl framework. The agent's responsibility is to use standard APIs that trigger the hooks (not to implement source control itself).

#### US-SC02: Agent reports source control status

**As a** Interface Engineer,  
**I want** the agent to report whether source control captured the new classes after a build,  
**So that** I know whether my changes are tracked.

**Acceptance criteria:**
- After creating or compiling classes, the agent checks whether %SourceControl hooks are active in the namespace
- If active: the agent reports "Classes exported to source control"
- If not active: the agent warns "Source control is not configured in this namespace -- changes are not version-tracked"

#### US-SC03: Agent respects source control locks

**As a** Interface Engineer,  
**I want** the agent to respect source control locks on classes,  
**So that** it does not modify a class that another user has locked for editing.

**Acceptance criteria:**
- Before modifying a class, the agent checks whether the class is locked by another user
- If locked: the agent reports "This class is locked by [user]. Cannot modify."
- If unlocked: the agent proceeds with the normal confirmation gate flow

---

## 11. End-to-End Scenario

This scenario demonstrates all four personas working together:

1. **Developer** writes a new Tool class that creates HL7 routing rules, compiles it, and deploys via zpm load
2. **AI Hub Admin** opens the admin UI, sees the new tool in the Tools tab, reviews its description and tests it with the dry-run panel
3. **AI Hub Admin** configures Interface Engineer and Operator agent profiles with appropriate ToolSet bindings
4. **AI Hub Admin** goes to the Connections tab, verifies the LLM connection shows a green status dot
5. **AI Hub Admin** opens the Catalogs tab, verifies both catalogs (search_ens: 164 classes, search_hs: 58 classes) are indexed
6. **AI Hub Admin** opens the Transforms tab, selects HL7 v2 -> FHIR R4, reviews Address field mappings to verify the Transformation and Mapping Catalog is populated
7. **Interface Engineer** opens the chatbot and asks: "Build me a production that receives ADT^A04 messages via MLLP, transforms patient demographics to FHIR R4, and sends them to a REST endpoint"
8. **Agent** validates that the Interface Engineer has %DB_WRITE permission on the target namespace
9. **Agent** searches the Ens.* catalog for appropriate Business Hosts (EnsLib.HL7.Service.TCPService, EnsLib.FHIR.Operation.REST)
10. **Agent** proposes the production layout and asks the Interface Engineer to approve
11. **Interface Engineer** clicks Approve
12. **Agent** creates the production, adds the hosts, configures settings. Source control hooks capture each class change
13. **Agent** builds and sends a test HL7 ADT^A04 message
14. **Agent** validates the result and reports success, confirms source control captured the changes
15. **Operator** opens the chatbot the next day and asks: "How is the ADT production performing? Any errors in the last 24 hours?"
16. **Agent** queries the Event Log (read-only), reports throughput statistics and any issues
17. **Operator** asks: "Increase the pool size on the TCPService to 3" -- the agent adjusts the operational setting after approval
18. **AI Hub Admin** reviews the audit log to see the complete trace of all actions by both Interface Engineer and Operator

---

## 12. Non-Functional Requirements

| Requirement | Target |
|---|---|
| Response latency | First token in < 2 seconds; full response in < 90 seconds per turn |
| Concurrent users | 5 simultaneous chat sessions (single IRIS instance) |
| Catalog rebuild | < 30 seconds for full Ens.* + HS.* re-index |
| Field mapping rebuild | < 1 second for full HL7/SDA3/FHIR trace (1,538 rows) |
| Availability | System operational whenever IRIS is running; no external dependencies except LLM provider |
| Data retention | Audit logs retained indefinitely; no automatic purge |
| Browser support | Chrome 120+, Edge 120+, Firefox 120+ (ES2020 baseline) |
| Permission check latency | < 10ms per tool call (cached role lookups) |

---

## Appendix A: Admin UI Tab Summary

| Tab | Purpose | Persona | Entity Count |
|---|---|---|---|
| Agents | Agent configuration (system prompt, MCPs, skills, provider) | AI Hub Admin | 2 (HealthInterop, FHIRSpecialist) |
| MCPs | MCP server enable/disable and description | AI Hub Admin | 6 (Production, Transform, Testing, Catalog, FHIRServer, BulkFHIR) |
| ToolSets | ToolSet grouping and description | AI Hub Admin | 7 (Production, Transform, Testing, Catalog, Monitoring, FHIRServer, BulkFHIR) |
| Tools | Individual tool schemas and dry-run | AI Hub Admin | 118 tools |
| Skills | Skill INSTRUCTIONS editor | AI Hub Admin | 15 domain skills |
| Connections | LLM provider credentials and health check | AI Hub Admin | N (user-configured) |
| Catalogs | Vector catalog status, rebuild, search | AI Hub Admin | 2 (Ens.*, HS.*) |
| Transforms | Field-level mapping explorer (Transformation and Mapping Catalog) | AI Hub Admin / End User | 1,538 pre-computed rows |
| Chatbots | Bind each chatbot surface to an agent (key → agent + host page + title) | AI Hub Admin | 2 (Interop, FHIR Management) |
| Audit | Request audit trail | AI Hub Admin | All API calls |

## Appendix B: %AI Framework Primitives Used

| Framework Class | Application Subclass | Purpose |
|---|---|---|
| %AI.Agent | AgenticInterop.Agent.HealthInterop + FHIRSpecialist | Main + FHIR-specialist agent instances |
| %AI.MCP.Service | AgenticInterop.MCP.Base + 6 servers | MCP server grouping |
| %AI.ToolSet | 7 ToolSet classes | Tool grouping by domain |
| %AI.Tool | 7 Tool classes (118 methods) | Individual tool implementations |
| %AI.Agent.Skill | AgenticInterop.Skill.Base + 15 domain skills | Domain knowledge sub-agents |
| %AI.RAG.KnowledgeBase | search_ens, search_hs | Vector search catalogs |
| %AI.ToolMgr | Used at query time | RAG query execution |
| %AI.Agent.Policy | ConfirmationGate, ToolFilter | Security and token policies |

## Appendix C: Security Enforcement Layers

The agent's actions pass through four enforcement layers before any mutation occurs:

| Layer | Enforced By | What It Checks |
|---|---|---|
| 1. Tool availability | AI Hub Admin (ToolSet binding) | Is this tool bound to the user's agent profile (Interface Engineer vs Operator)? |
| 2. Namespace validation | Tool implementation | Is the target namespace non-Foundation? Does the user have database access? |
| 3. Permission delegation | Tool implementation | Does the authenticated user have the required IRIS role for this operation? |
| 4. User confirmation | ConfirmationGate policy | Did the user click Approve for this specific mutating action? |

A mutating action must pass all four layers. A failure at any layer prevents execution and returns a clear error to the agent, which explains the denial to the user.
