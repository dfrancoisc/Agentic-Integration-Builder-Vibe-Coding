# Health Interop AI Copilot - Product Requirements Document

## 1. Product Overview

### What it is

Health Interop AI Copilot is an AI-powered assistant embedded inside InterSystems IRIS for Health that helps integration engineers build, review, and optimize healthcare interoperability workflows through natural conversation. Instead of navigating dozens of Management Portal screens and writing ObjectScript by hand, engineers describe what they need in plain English and the copilot builds it using real IRIS APIs.

### Who it serves

System integrators and integration engineers working with IRIS for Health who need to stand up HL7, FHIR, and SDA interoperability pipelines. The primary persona has healthcare data experience but limited InterSystems platform knowledge. The copilot bridges that gap by encoding IRIS best practices into its behavior.

### How it works

A single orchestrator agent (Health Interop) receives the user's request, searches a vector catalog of IRIS classes to find the right components, presents a plan, and on approval executes the build using tools organized across toolsets. Domain skills (e.g., Productions, DTL, BPL, Routing Rules, HL7v2, FHIR R4, SDA, REST) give the agent deep knowledge of IRIS-specific concepts. The agent operates through MCP servers (e.g., Production, Transform, Testing, Catalog) that scope tool access by domain.

### Two personas, two experiences

The product separates two distinct user journeys:

**Developer Experience (DX)** - InterSystems engineers and partners who author the underlying capabilities: writing Tool classes in ObjectScript/Python, authoring Skill documents, building catalog embeddings. This work happens in VS Code (or any IDE) and ships as compiled classes inside an IPM package. Developers define what the copilot can do.

**Builder Experience (End User)** - Integration engineers inside IRIS for Health and Health Connect who configure and use the copilot: creating Agents with custom system prompts, assembling MCP Servers from available Toolsets, linking Skills to Agents, and chatting with the copilot to build productions. This work happens entirely in the IRIS Management Portal UI. Builders decide how the copilot behaves for their use case.

---

## 2. Use Cases

### Use Case 1: Guided Production Build (Simple to Complex)

A user types: "I need to receive ADT admission messages from our HIS and send observation reports to the downstream LIS."

**Step 1 - Prompt Refinement.** The agent identifies missing information and asks targeted questions: What HL7 version? What transport (MLLP port, file drop, TCP)? What fields need to map from ADT to ORU? What happens to messages that fail transformation? What is the throughput expected? Do you need OAuth integration? The agent guides the user to a complete specification without requiring them to know IRIS terminology.

**Step 2 - Catalog Search and Plan.** The agent calls a catalog (e.g., Ens.* and HS.* classes) - a vector database, for example - to find the right business host classes, adapter classes, and existing transformation templates. It presents a structured plan: every component name, the class it will use (citing which catalog result and why), key settings, data flow, field mappings, and the complete test message. Ends with "Ready to build. Shall I proceed?"

**Step 3 - Build.** On approval, the agent executes in a strict sequence: Call MCP Servers and Tools to build the production end to end. Number of tool calls must be defined (less than 10 based on experience). For complex productions this includes:

- DTL (Data Transformation Language) with complete field mappings, foreach blocks for repeating segments, conditional logic, and subtransform references
- BPL (Business Process Language) for orchestration workflows with compensation handlers, async callbacks, and code activities
- Routing Rules with constraint-based message routing, transform chaining, and dead-letter handling
- Lookup Tables for code mappings (e.g., facility codes, provider identifiers, insurance plan maps)
- HL7 Schema validation ensuring source and target structure paths are correct before any mapping
- FHIR resource construction for R4 bundles, references, and search parameter configuration
- SDA (Summary Document Architecture) as the intermediary hub for cross-format transformations (HL7 to SDA to FHIR)

The tools must understand these artifacts as a connected system, not isolated components. A routing rule references a DTL by class name, a DTL references lookup tables by name, a BPL calls sub-DTLs and routes to specific business hosts. The build sequence enforces these dependencies.

**Step 4 - Test and Validate.** The agent creates sample messages (1 to 10 based on customer request) and sends test HL7 messages to the Business Service indicated in the production to check if: production exists and is running, all hosts are enabled, no event log errors, messages flowed through the pipeline. Failed checks are fixed silently and validation re-run until all pass. The completion report shows the actual test message sent, transformation output, and other metrics like transformation time, end-to-end time, and errors.

**Step 5 - Catalog Update.** After a successful build, any new DTL, BPL, or routing rule classes created during the session are automatically indexed into the HS.* catalog. This ensures the next user who asks for a similar transformation can discover and reuse what was just built, rather than creating it from scratch. The catalog grows with every successful build.

### Use Case 2: Production Review and Optimization

A user asks: "Review the LAB.Production and tell me what it does and how to improve it."

The agent calls MCP Server and Tools (e.g., `Production` and `GetProduction`) to inspect every business host, its class, settings, and connections. It calls MCP Server and Tools (e.g., `QueryEventLog` and `MessageSummary`) for recent error patterns and throughput data. It then explains in plain language: what each host does, the data flow from source to destination, which settings are at defaults versus customized, and which features are unused (pool sizing, retry intervals, alert triggers, archive flags). Recommendations are grounded in the Ens.* catalog descriptions and the Skills knowledge base: "Your TCP service uses the default StayConnected=0 which reopens the socket on every message. For a high-volume HL7 feed, setting StayConnected=-1 keeps the connection open and reduces latency." Each recommendation cites the specific setting, its current value, the recommended value, the expected impact, and possibly the link to the documentation.

### Use Case 3: Complex HL7-to-HL7 Transformations

A user needs to transform HL7 v2.5 ADT^A01 messages into ORU^R01 observation reports with field mappings that span multiple segments.

The agent calls MCP Server and Tools (e.g., `GetHL7SchemaMap`) for both source (ADT_A01) and target (ORU_R01) structures before writing any DTL. This is critical because ADT_A01 has flat PID paths while ORU_R01 has nested paths like `PIDgrpgrp(1).PIDgrp.PID`. Guessed paths produce silent empty output.

The agent builds the complete DTL XML (e.g., `CreateDTL`) with all field mappings. By experience, do not use iterative `UpdateDTL` calls which burn rate-limited API tokens. It then runs testing tools with a sample message to verify every mapped field produces output. If any field is empty, the agent checks the schema paths and corrects them. For complex scenarios (conditional logic, repeating segments, lookup tables), the agent uses the DTL skill knowledge to generate `foreach` blocks, subtransform references, and lookup table entries.

---

## 3. Product Requirements

### 3.1 Performance

| Requirement | Target | Rationale |
|---|---|---|
| Time to first token | Under 3 seconds | Users lose confidence if the chat feels unresponsive after sending a message |
| Full production build (plan + approve + build + test) | Under 90 seconds wall clock | The 7-iteration target with parallel tool batching must complete within the LLM provider's rate limits |
| Catalog vector search latency | Under 500ms per query | search_ens and search_hs run in the first iteration; slow search delays the entire plan phase |
| Tool execution (non-streaming) | Under 5 seconds per tool | Each tool has a 5-30 second timeout; most should complete well under that |
| SSE stream delivery | No gaps longer than 2 seconds | Token-by-token streaming with tool-call lifecycle events; gaps make the UI feel frozen |
| Concurrent chat sessions | 10+ simultaneous users | Each session is an independent agent instance; IRIS process pooling must handle the load |

### 3.2 Scalability

| Requirement | Target | Rationale |
|---|---|---|
| Catalog size | 5,000+ classes indexed | Current catalogs cover Ens.* and HS.* classes; must scale as customers add custom classes |
| Catalog auto-growth | New artifacts indexed after every successful build | DTLs, BPLs, and routing rules created by the copilot are added to the HS.* catalog automatically so future sessions can discover and reuse them |
| Tool count per agent | 50+ tools without degradation | Currently 48 tools across 5 classes; adding new tool classes must not degrade prompt token budget |
| Namespace independence | Any namespace on the instance | Tools execute in the user's selected namespace via X-IRIS-Namespace header; no hardcoded namespace references |
| LLM provider flexibility | Bedrock, Anthropic, Azure OpenAI | Provider is user-configurable with connection health checks; switching providers must not require code changes |
| Skill extensibility | Add new skills without redeployment | Skills are loaded dynamically from class parameters; new Skill.Base subclasses register automatically |

### 3.3 Quality of Outputs

| Requirement | Target | Rationale |
|---|---|---|
| Catalog grounding | Every component choice cites a catalog search result | Prevents the LLM from hallucinating class names; the catalog contains instance-specific descriptions and class recommendations that training data does not have |
| Schema accuracy | Zero guessed HL7/FHIR paths | GetHL7SchemaMap is mandatory before any DTL involving EnsLib.HL7.Message; paths must use exact dtlPath values from schema results |
| Build correctness | PostBuildValidation passes on first run for standard use cases | The validation checklist (production running, hosts enabled, no errors, messages flowed) must catch build issues before the user discovers them |
| DTL completeness | One-shot DTL creation with all field mappings | The complete DTL XML is built in a single CreateDTL call; iterative UpdateDTL calls cause provider rate limiting and incomplete transforms |
| Cross-artifact integrity | Routing rules reference compiled DTLs, BPLs reference valid hosts | Tools must validate that referenced classes exist and are compiled before wiring them into a production; dangling references cause silent runtime failures |
| Anti-fabrication | No claimed success without tool confirmation | If CreateProduction was not called, no production exists; every claim of success must be backed by a tool result |
| Error transparency | Failures reported honestly with actionable detail | If a test fails (ok=0, errors in event log), the agent reports the failure with the specific error, not a generic "something went wrong" |

### 3.4 User Experience

#### 3.4.1 Builder Experience (End Users in IRIS for Health)

Builders work inside the IRIS Management Portal. They do not write code. Their experience is entirely configuration-driven through the admin UI.

| Requirement | Description |
|---|---|
| Agent configuration | Create and configure Agents: write or edit system prompts, set temperature and iteration limits, select which MCP Servers and Skills to attach. The builder defines the agent's personality and capabilities without touching ObjectScript |
| MCP Server assembly | Create MCP Servers by selecting from available Toolsets. Each MCP scopes a domain (Production, Transform, Testing, Catalog). The builder decides which tool groups the agent can access |
| Toolset browsing | Browse available Toolsets and their individual Tools in the admin UI. See tool names, descriptions, and parameter signatures. Understand what each tool does at a high level before including it in an MCP |
| Skill attachment | View available Skills (read-only) and attach them to Agents. Each skill teaches the agent domain knowledge. The builder selects which knowledge domains are relevant for their use case |
| Connection management | Configure LLM provider connections (Bedrock, Anthropic, Azure OpenAI) with a visual health semaphore. Paste API keys into a masked input. Click "Test" to verify. Green/red dot shows status at a glance |
| Chat experience | Streaming chat with tool-call cards, confirmation gates for mutating operations, guided example prompts, and a conversation history rail. The builder interacts with the copilot they configured |
| Audit visibility | View the audit trail of all copilot actions: which tools were called, what arguments were passed, what results came back, how long each operation took |

#### 3.4.2 Developer Experience (DX - VS Code / IDE)

Developers author the building blocks that builders configure. Their work produces compiled classes that ship in an IPM package.

| Requirement | Description |
|---|---|
| Tool authoring | Write %AI.Tool subclasses in ObjectScript or Embedded Python. Each public ClassMethod becomes a tool the LLM can call. The method's Description comment becomes the tool description the LLM sees. The FormalSpec defines the parameters. Developers invest in high-quality descriptions because they are the contract with the LLM |
| Skill authoring | Write markdown documents as XData blocks in Skill.Base subclasses. Each skill teaches the agent a domain (HL7 segment anatomy, DTL foreach patterns, SDA-as-hub rule). Skills are versioned in source control alongside the code |
| Catalog seeding | Build and maintain the vector catalogs. Walk %Dictionary for Ens.* and HS.* classes, curate descriptions, generate embeddings, persist to vector tables. The catalog is the agent's memory of what IRIS can do |
| Testing and dry-run | Test individual tools via the dry-run panel (admin UI) or programmatically via the /editor/tool/:toolset/:name/dryrun endpoint. Every tool gets at least one happy-path test |
| IPM packaging | All classes, skills, reference data, and install hooks ship as a single IPM module. The module installs into any IRIS for Health or Health Connect namespace. No manual class imports |

### 3.5 Tool Depth: What the Tools Must Understand

The agent is only as capable as its tools. For end-to-end production building, the tools must deeply understand the interconnected IRIS artifacts:

| Domain | What the tools must do | Why it matters |
|---|---|---|
| Productions | Create production classes, add/remove/configure business hosts with correct settings targets (Host vs Adapter level), manage lifecycle (start/stop/recover) | A misconfigured setting target (e.g., Port at Host level instead of Adapter level) is silently ignored. The tool must know the difference |
| DTL | Build complete DTL XML with field mappings, foreach blocks for repeating segments, subtransform references, conditional assign actions, virtual document paths | DTLs are the most common artifact. A partial DTL (missing fields, wrong paths) produces silent empty output that the user won't catch until production |
| BPL | Generate BPL XML with activities (assign, call, code, transform, rule), compensation handlers, async patterns, context properties | Complex routing and orchestration logic lives in BPL. Without BPL tools, the agent can only build simple point-to-point flows |
| Routing Rules | Create routing rule XML with constraint-based routing (message class, doc type), transform chaining, multi-destination routing, dead-letter fallback | Every HL7 routing engine requires a compiled rule class and BusinessRuleName setting. Missing either causes an OnProcessInput crash |
| Lookup Tables | Create and populate lookup tables for code mappings (facility codes, insurance plans, provider identifiers) | Real-world transformations depend on lookup tables for value translation. Without them, DTLs can only do structural mapping, not semantic mapping |
| HL7 Schemas | Introspect schema structures for any message type and version, return exact segment paths with nested group navigation (PIDgrpgrp, ORCgrp, OBXgrp) | ADT_A01 and ORU_R01 have fundamentally different path structures. Guessing paths guarantees empty output |
| FHIR R4 | Construct FHIR resources, validate against profiles, handle references and contained resources, configure search parameters | FHIR is the target format for modern interoperability. Tools must understand resource relationships and validation rules |
| SDA | Know the SDA3 model as the transformation hub, understand the HL7-to-SDA-to-FHIR pipeline, reference built-in HS.FHIR.DTL.SDA3.vR4.* DTLs | IRIS never converts directly between wire formats. SDA is always the intermediary. Tools that skip SDA produce architecturally incorrect pipelines |
| Catalog | Vector search across 2,500+ IRIS classes, class introspection via %Dictionary, auto-index new artifacts after successful builds | The catalog prevents hallucination and enables reuse. Without auto-indexing, the catalog goes stale after the first build session |

### 3.6 Architecture: Agents, MCPs, Tools, and Skills

#### Agent: Health Interop (Orchestrator)

The single router agent that receives every user message. It does not answer domain questions directly. Instead it dispatches to the right combination of tools and skills.

Behavior rules:
- Research before planning (mandatory catalog search in iteration 0)
- Plan before building (present component list, wait for approval)
- Build silently on approval (call tools without narrating each step)
- Validate after building (PostBuildValidation is mandatory, never skipped)
- Parallel tool batching (independent tools in one round-trip to minimize iterations)
- Update catalog after building (new DTLs, BPLs, routing rules are indexed for future reuse)

#### MCP Servers

| MCP | Domain | Key Tools |
|---|---|---|
| Production | Production lifecycle, business host CRUD, monitoring | CreateProduction, AddBusinessHost, StartProduction, StopProduction, GetProduction, ListProductions, PostBuildValidation, QueryEventLog, MessageSummary |
| Transform | DTL/BPL authoring, routing rules, HL7 schema introspection, lookup tables | CreateDTL, CreateBPL, CreateRoutingRule, CompileDTL, DryRunDTL, GetHL7SchemaMap, ListLookupTables, ListSDAFHIRDTLs, DescribeTransformationPipeline |
| Testing | Message send and validation | SendHL7, SendFHIR, ValidateHL7, ValidateFHIR, CompareMessages |
| Catalog | Vector search, class introspection, namespace context, catalog maintenance | search_ens, search_hs, DescribeClass, GetUserNamespace, SearchApiIndex, IndexNewArtifacts |

#### Skills (domain knowledge documents)

Productions, DTL, BPL, Routing Rules, HL7v2, FHIR R4, SDA, REST in Productions, ESB Patterns. Each skill is a markdown document injected into the agent's system prompt that teaches IRIS-specific concepts, common patterns, and anti-patterns. Skills are authored by developers (DX) and attached to agents by builders (End User UI).

#### Catalog Vector Search

| Catalog | Content | Embedding |
|---|---|---|
| Ens Catalog (search_ens) | Business hosts, adapters, services, processes, operations | FastEmbed AllMiniLML6V2, 384 dimensions |
| HS Catalog (search_hs) | Health-specific transformations, FHIR/SDA/HL7 DTLs, mappers | FastEmbed AllMiniLML6V2, 384 dimensions |

Search is mandatory before any build. The catalog contains instance-specific class descriptions, key settings, and recommendations that LLM training data does not have. The catalog auto-grows: new DTLs, BPLs, and routing rules created during a build session are embedded and indexed so the next session can discover them.
