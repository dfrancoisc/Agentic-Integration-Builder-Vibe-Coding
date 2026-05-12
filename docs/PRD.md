# Health Interop AI Copilot - Product Requirements Document

## 1. Product Overview

### What it is

Health Interop AI Copilot is an AI-powered assistant embedded inside InterSystems IRIS for Health that helps integration engineers build, review, and optimize healthcare interoperability workflows through natural conversation. Instead of navigating dozens of Management Portal screens and writing ObjectScript by hand, engineers describe what they need in plain English and the copilot builds it using real IRIS APIs.

### Who it serves

System integrators and integration engineers working with IRIS for Health who need to stand up HL7, FHIR, and SDA interoperability pipelines. The primary persona has healthcare data experience but limited InterSystems platform knowledge. The copilot bridges that gap by encoding IRIS best practices into its behavior.

### How it works

A single orchestrator agent (Health Interop) receives the user's request, searches a vector catalog of IRIS classes to find the right components, presents a plan, and on approval executes the build using 48 tools organized across 5 tool classes. Nine domain skills (Productions, DTL, BPL, Routing Rules, HL7v2, FHIR R4, SDA, REST, ESB Patterns) give the agent deep knowledge of IRIS-specific concepts. The agent operates through 4 MCP servers (Production, Transform, Testing, Catalog) that scope tool access by domain.

---

## 2. Use Cases

### Use Case 1: Guided Production Build

A user types: "I need to receive ADT admission messages from our HIS and send observation reports to the downstream LIS."

**Step 1 - Prompt Refinement.** The agent identifies missing information and asks targeted questions: What HL7 version? What transport (MLLP port, file drop, TCP)? What fields need to map from ADT to ORU? What happens to messages that fail transformation? The agent guides the user to a complete specification without requiring them to know IRIS terminology.

**Step 2 - Catalog Search and Plan.** The agent calls `search_ens` and `search_hs` against the vector catalog (384-dimension embeddings over 2,500+ IRIS classes) to find the right business host classes, adapter classes, and existing transformation templates. It presents a structured plan: every component name, the class it will use (citing which catalog result and why), key settings, data flow, field mappings, and the complete test message. Ends with "Ready to build. Shall I proceed?"

**Step 3 - Build.** On approval, the agent executes in a strict sequence: CreateDTL with full XML in one call, CreateRoutingRule, CreateProduction, AddBusinessHost for each host (operations first, then routing processes, then services), StartProduction. All mutating tools require user confirmation via an inline Approve/Reject card in the chat. Target: 7 iterations, never exceeding 10 tool calls.

**Step 4 - Test and Validate.** The agent sends a test HL7 message via `SendHL7`, then runs `PostBuildValidation` which checks: production exists and is running, all hosts are enabled, no event log errors, messages flowed through the pipeline. Failed checks are fixed silently and validation re-run until all pass. The completion report shows the actual test message sent, transformation output, and field-by-field verification.

### Use Case 2: Production Review and Optimization

A user asks: "Review the LAB.Production and tell me what it does and how to improve it."

The agent calls `GetProduction` to inspect every business host, its class, settings, and connections. It calls `QueryEventLog` and `MessageSummary` for recent error patterns and throughput data. It then explains in plain language: what each host does, the data flow from source to destination, which settings are at defaults versus customized, and which features are unused (pool sizing, retry intervals, alert triggers, archive flags). Recommendations are grounded in the Ens.* catalog descriptions and the Skills knowledge base: "Your TCP service uses the default StayConnected=0 which reopens the socket on every message. For a high-volume HL7 feed, setting StayConnected=-1 keeps the connection open and reduces latency." Each recommendation cites the specific setting, its current value, the recommended value, and the expected impact.

### Use Case 3: Complex HL7-to-HL7 Transformations

A user needs to transform HL7 v2.5 ADT^A01 messages into ORU^R01 observation reports with field mappings that span multiple segments.

The agent calls `GetHL7SchemaMap` for both source (ADT_A01) and target (ORU_R01) structures before writing any DTL. This is critical because ADT_A01 has flat PID paths while ORU_R01 has nested paths like `PIDgrpgrp(1).PIDgrp.PID`. Guessed paths produce silent empty output.

The agent builds the complete DTL XML in a single `CreateDTL` call with all field mappings, not iterative `UpdateDTL` calls which burn rate-limited API tokens. It then runs `DryRunDTL` with a sample message to verify every mapped field produces output. If any field is empty, the agent checks the schema paths and corrects them. For complex scenarios (conditional logic, repeating segments, lookup tables), the agent uses the DTL skill knowledge to generate `foreach` blocks, subtransform references, and lookup table entries.

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
| Anti-fabrication | No claimed success without tool confirmation | If CreateProduction was not called, no production exists; every claim of success must be backed by a tool result |
| Error transparency | Failures reported honestly with actionable detail | If a test fails (ok=0, errors in event log), the agent reports the failure with the specific error, not a generic "something went wrong" |

### 3.4 User Experience

| Requirement | Description |
|---|---|
| Streaming chat | Token-by-token SSE streaming; no full-response waits. Every response streams. Break complex tasks into multiple short LLM turns with visible progress |
| Tool call visibility | Each tool call renders as a card showing: tool name, arguments, status (running/ok/error), collapsible result. Users see what the agent is doing in real time |
| Confirmation gates | Mutating tools (create, update, delete, start, stop) pause with an inline Approve/Reject prompt. The user always controls what changes IRIS state |
| Guided prompting | 10 curated example prompts across 8 categories (Build, Transform, Operate, Review, Route, Tune, Export, Migrate) teach users what the copilot can do and model good prompt structure |
| Connection health | A semaphore (green/red dot) shows LLM provider status. If red, chat input is disabled and the error is shown inline. Click the dot to see the full error message |
| Admin configurability | All entities (Agents, MCPs, ToolSets, Tools, Skills, Connections) are viewable and editable in the admin UI without touching code |
| No jargon without gloss | First use of any InterSystems acronym (DTL, BPL, SDA, MLLP, etc.) includes a one-line explanation. Healthcare acronyms (HL7, FHIR, ADT) are fine bare |

### 3.5 Architecture: Agents, MCPs, and Tools

#### Agent: Health Interop (Orchestrator)

The single router agent that receives every user message. It does not answer domain questions directly. Instead it dispatches to the right combination of tools and skills. Configuration: temperature 0.3, max 25 iterations, 9 attached skills.

Behavior rules:
- Research before planning (mandatory catalog search in iteration 0)
- Plan before building (present component list, wait for approval)
- Build silently on approval (call tools without narrating each step)
- Validate after building (PostBuildValidation is mandatory, never skipped)
- Parallel tool batching (independent tools in one round-trip to minimize iterations)

#### MCP Servers (4)

| MCP | Domain | Key Tools |
|---|---|---|
| Production | Production lifecycle, business host CRUD, monitoring | CreateProduction, AddBusinessHost, StartProduction, StopProduction, GetProduction, ListProductions, PostBuildValidation, QueryEventLog, MessageSummary |
| Transform | DTL/BPL authoring, routing rules, HL7 schema introspection | CreateDTL, CreateBPL, CreateRoutingRule, CompileDTL, DryRunDTL, GetHL7SchemaMap, ListDTLs |
| Testing | Message send and validation | SendHL7, SendFHIR, ValidateHL7, ValidateFHIR, CompareMessages |
| Catalog | Vector search, class introspection, namespace context | search_ens, search_hs, DescribeClass, GetUserNamespace, SearchApiIndex |

#### Tool Classes (5, 48 tools total)

| Tool Class | Count | Scope |
|---|---|---|
| Tool.Production | 10 | Production CRUD, host management, lifecycle, post-build validation |
| Tool.Transform | 14 | DTL/BPL/Routing Rule CRUD, HL7 schema maps, compile, dry-run |
| Tool.Testing | 6 | Send HL7/FHIR, validate structure, compare messages |
| Tool.Catalog | 8 | Vector search, class describe, namespace, status decode, glossary |
| Tool.Monitoring | 6 | Event log queries, message headers, queue depths, error analysis |

#### Skills (9 domain knowledge documents)

Productions, DTL, BPL, Routing Rules, HL7v2, FHIR R4, SDA, REST in Productions, ESB Patterns. Each skill is a markdown document injected into the agent's system prompt that teaches IRIS-specific concepts, common patterns, and anti-patterns.

#### Catalog Vector Search (2 indexes)

| Catalog | Content | Records | Embedding |
|---|---|---|---|
| Ens Catalog (search_ens) | Business hosts, adapters, services, processes, operations | 1,200+ classes | FastEmbed AllMiniLML6V2, 384 dimensions |
| HS Catalog (search_hs) | Health-specific transformations, FHIR/SDA/HL7 DTLs, mappers | 1,300+ classes | FastEmbed AllMiniLML6V2, 384 dimensions |

Search is mandatory before any build. The catalog contains instance-specific class descriptions, key settings, and recommendations that LLM training data does not have. The agent must cite which catalog result it chose and why.
