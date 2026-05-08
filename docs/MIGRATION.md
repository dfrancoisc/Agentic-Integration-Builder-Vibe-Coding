# agentic_interop — Class Build Map

The full plan-to-repo mapping for every class, web app, vector table, and seed file the build will create. Updated BEFORE any class is written or moved (per the user's "build class-mapping tables before refactors" rule).

Conventions:
- All classes live under `src/cls/AgenticInterop/...` with the file path mirroring the class name.
- All classes extend `%RegisteredObject` unless noted.
- Persistent classes additionally extend `%JSON.Adaptor`.
- Embedded Python is preferred for boto3 / anthropic SDK / openpyxl / json-schema validation; ObjectScript for IRIS-native ops.
- Phase column = the build phase that creates the class. See docs/PLAN.md "Build phases".

## Persistent data model (`AgenticInterop.Data.*`)

The primary configuration entities (Agent, MCP, ToolSet) are class definitions, not %Persistent rows (see PLAN.md "Data model — class as data"). The overlay tables below store admin UI overrides that diverge from compiled class defaults.

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Connection | src/cls/AgenticInterop/Data/Connection.cls | %Persistent, %JSON.Adaptor | LLM connection config (provider/model/region/baseURL/maxTokens/enabled/isDefault) plus last-test result. SQL alias `AgenticInterop_Data.LLMConnection`. Secret in IRIS Secured Wallet. | 1 |
| AgentOverride | src/cls/AgenticInterop/Data/AgentOverride.cls | %Persistent, %JSON.Adaptor | Admin UI overrides for Agent class parameters (system prompt, temperature, MCPS, SKILLS, MaxIterations) | 6 |
| MCPOverride | src/cls/AgenticInterop/Data/MCPOverride.cls | %Persistent, %JSON.Adaptor | Admin UI overrides for MCP class parameters (TOOLSETS) | 6 |
| ToolSetOverride | src/cls/AgenticInterop/Data/ToolSetOverride.cls | %Persistent, %JSON.Adaptor | Admin UI overrides for ToolSet class parameters (tool list) | 6 |
| AuditLog | src/cls/AgenticInterop/Data/AuditLog.cls | %Persistent, %JSON.Adaptor | Audit row per REST request + tool call: user, namespace, action, input, output, duration, error | 4 |

## %AI.Agent + %AI.ToolSet implementations

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| HealthInterop | src/cls/AgenticInterop/Agent/HealthInterop.cls | %AI.Agent | The single main agent (the "router"). Declarative XData INSTRUCTIONS keeps it slim — its tool catalog is the Skill classes below + a few cross-cutting tools (get_user_namespace, search_ens, search_hs). Domain expertise lives in the Skills, not in this prompt. | 2 |
| Production | src/cls/AgenticInterop/ToolSet/Production.cls | %AI.ToolSet | Production CRUD tools — Includes from inline methods + Production.Tool.* if needed | 4 |
| Transform | src/cls/AgenticInterop/ToolSet/Transform.cls | %AI.ToolSet | DTL/BPL CRUD + lookup tables | 4 |
| Testing | src/cls/AgenticInterop/ToolSet/Testing.cls | %AI.ToolSet | HL7/FHIR send + validate (against an isolated test production by default) | 4 |
| Catalog | src/cls/AgenticInterop/ToolSet/Catalog.cls | %AI.ToolSet | search_ens, search_hs (RAG-backed); describe_class | 2 (stub), 5 (real) |
| Monitoring | src/cls/AgenticInterop/ToolSet/Monitoring.cls | %AI.ToolSet | QueryEventLog, TopErrors, QueryMessageStatus, MessageSummary, QueueStatus (read-only SQL diagnostics) | 5 |

## Skill classes (%AI.Agent.Skill subclasses — declarative sub-agents registered as tools on the main agent)

Each Skill class has Parameter TOOLS pointing at the toolsets the sub-agent can use, XData SUMMARY (YAML metadata, including the description the parent LLM reads to decide when to invoke), and XData INSTRUCTIONS (markdown system prompt distilled strictly from the IRIS for Health PDFs — see docs/SKILLS.md for the full content with citations). Phase 2 scaffolds empty classes; their INSTRUCTIONS get populated as I read the PDFs in batches and commit per-batch.

| Class | Path | TOOLS parameter | Source PDFs | Phase |
|---|---|---|---|---|
| Productions | src/cls/AgenticInterop/Skill/Productions.cls | AgenticInterop.ToolSet.Production | Introducing_Interoperability_Productions, Preparing_to_Create_Productions, Configuring_Productions, Developing_Productions, Best_Practices_for_Creating_Productions, Managing_Productions, Monitoring_Productions | 2 (scaffold), filled per-batch |
| DTL | src/cls/AgenticInterop/Skill/DTL.cls | AgenticInterop.ToolSet.Transform | Developing_DTL_Transformations, Business_Process_and_Data_Transformation_Language_Reference (DTL chapters) | 2 (scaffold), batch 2 |
| BPL | src/cls/AgenticInterop/Skill/BPL.cls | AgenticInterop.ToolSet.Transform | Developing_BPL_Processes, Business_Process_and_Data_Transformation_Language_Reference (BPL chapters) | 2 (scaffold), batch 3 |
| RoutingRules | src/cls/AgenticInterop/Skill/RoutingRules.cls | AgenticInterop.ToolSet.Production | Developing_Business_Rules | 2 (scaffold), batch 3 |
| HL7v2 | src/cls/AgenticInterop/Skill/HL7v2.cls | AgenticInterop.ToolSet.Testing | (existing iris-hl7-v2 skill + relevant PDF chapters) | 2 (scaffold), batch 4 |
| FHIRR4 | src/cls/AgenticInterop/Skill/FHIRR4.cls | AgenticInterop.ToolSet.Testing | (existing iris-fhir skill + relevant PDF chapters) | 2 (scaffold), batch 4 |
| SDA | src/cls/AgenticInterop/Skill/SDA.cls | AgenticInterop.ToolSet.Testing | (existing iris-sda skill) | 2 (scaffold), batch 4 |
| RestInProductions | src/cls/AgenticInterop/Skill/RestInProductions.cls | AgenticInterop.ToolSet.Production | Using_REST_Services_and_Operations_in_Productions | 2 (scaffold), batch 4 |
| ESBPattern | src/cls/AgenticInterop/Skill/ESBPattern.cls | AgenticInterop.ToolSet.Production,AgenticInterop.ToolSet.Transform | Using_a_Production_as_an_ESB | 2 (scaffold), batch 3 |

The PDFs Routing_DICOM_Documents_in_Productions, Enabling_Productions_to_Use_Managed_File_Transfer_Services, and Using_Virtual_Documents_in_Productions are read in batch 4 and their content is distributed into the matching Skill INSTRUCTIONS above (e.g., DICOM into Productions, MFT into Productions, virtual documents into Productions/HL7v2) rather than producing standalone Skill classes — per the user's narrowed skill list.

## Agent runtime

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Manager | src/cls/AgenticInterop/Agent/Manager.cls | %RegisteredObject | Loads Data.Agent → builds %AI.Agent (calls %Init, attaches toolsets, registers Skills into system prompt). Caches per-conversation. | 2 |
| Runtime | src/cls/AgenticInterop/Agent/Runtime.cls | %RegisteredObject | Wraps agent.Run() with the iteration monitor. Emits SSE events for token + tool-lifecycle (Phase 3+). | 2 (sync), 3 (SSE) |
| Monitor | src/cls/AgenticInterop/Agent/Monitor.cls | %RegisteredObject | Iteration callback object: deadline, token budget, optional SSE writer. Pattern from ai-hub-iteration-monitor skill. | 2 |
| SkillLoader | src/cls/AgenticInterop/Agent/SkillLoader.cls | %RegisteredObject | Reads Data.Agent.Skills (string-list of class names), instantiates each %AI.Agent.Skill subclass, sets `skill.ParentAgent = agent`, calls `agent.ToolManager.AddTool(skill)`. Skills then appear as tools in the parent's catalog. | 2 |

## Connection + Provider integration

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Connections | src/cls/AgenticInterop/Connections.cls | %RegisteredObject | Facade for Connection rows + secrets. List/Get/Create/Update/Delete + SetSecret/HasSecret/ClearSecret/Test/GetProvider. Idempotent wallet bootstrap (Security.Resources + %Wallet.Collection). Uses %AI.Provider.Create + ChatComplete for live test. | 1 |

## Tool implementation classes (`AgenticInterop.Tool.*` — each extends `%AI.Tool`)

Each public ClassMethod is auto-discovered by the %AI framework as a tool. Composed into ToolSets via `<Include Class="..."/>`.

| Class | Path | Tools | Phase |
|---|---|---|---|
| Production | src/cls/AgenticInterop/Tool/Production.cls | ListProductions, GetProduction, CreateProduction, DeleteProduction, StartProduction, StopProduction, AddBusinessHost, RemoveBusinessHost, UpdateBusinessHostSettings | 4 |
| Transform | src/cls/AgenticInterop/Tool/Transform.cls | ListDTLs, ListLookupTables, ListBusinessRules, DryRunDTL, CompileDTL, CreateDTL, UpdateDTL, CreateBPL, ValidateBPL, ListSDAFHIRDTLs, DescribeTransformationPipeline, GetCustomDTLPackage | 4 |
| Testing | src/cls/AgenticInterop/Tool/Testing.cls | ValidateHL7Structure, ValidateHL7Semantics, ValidateFHIRResource, CompareMessages, SendHL7, SendFHIR | 4 |
| Catalog | src/cls/AgenticInterop/Tool/Catalog.cls | GetUserNamespace, ListUserAccessibleNamespaces, DescribeClass, ExplainStatus, LookupErrorCode, LookupGlossaryTerm, SearchApiIndex | 2 (stub), 5 (real) |
| Monitoring | src/cls/AgenticInterop/Tool/Monitoring.cls | QueryEventLog, TopErrors, QueryMessageStatus, MessageSummary, QueueStatus | 5 |

## Catalog (RAG)

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Builder | src/cls/AgenticInterop/Catalog/Builder.cls | %RegisteredObject | Builds both search_ens and search_hs KnowledgeBases from XLS (openpyxl) or %Dictionary. Creates %AI.RAG.KnowledgeBase instances with FastEmbed + VectorStore. Idempotent. | 5 |
| Attach | src/cls/AgenticInterop/Catalog/Attach.cls | %RegisteredObject | At agent build time, registers search_ens / search_hs KnowledgeBase tools on the agent's ToolManager when the underlying tables are populated. | 5 |

## REST surface

All routes live in a single `AgenticInterop.REST.Dispatch` class (%CSP.REST UrlMap) at `/api/agentic/`. Service logic is delegated to `AgenticInterop.Editor.*` service classes.

| Class | Path | Purpose | Phase |
|---|---|---|---|
| Dispatch | src/cls/AgenticInterop/REST/Dispatch.cls | UrlMap router. X-IRIS-Namespace header, access gate, audit logging. UseCookies=0 + no sessions/CSRF. | 0 |
| Editor.ChatService | src/cls/AgenticInterop/Editor/ChatService.cls | SSE chat streaming, tool-call approval, conversation lifecycle | 2-3 |
| Editor.ConnectionService | src/cls/AgenticInterop/Editor/ConnectionService.cls | Connection CRUD + secret + test | 1 |
| Editor.AgentService | src/cls/AgenticInterop/Editor/AgentService.cls | Agent class read + overlay write | 6 |
| Editor.MCPService | src/cls/AgenticInterop/Editor/MCPService.cls | MCP class read + overlay write | 6 |
| Editor.ToolSetService | src/cls/AgenticInterop/Editor/ToolSetService.cls | ToolSet class read + overlay write, cross-provider tool selection | 6 |
| Editor.ToolService | src/cls/AgenticInterop/Editor/ToolService.cls | Tool read + dry-run | 6 |
| Editor.CatalogService | src/cls/AgenticInterop/Editor/CatalogService.cls | Catalog rebuild + vector search | 5 |
| Editor.AuditService | src/cls/AgenticInterop/Editor/AuditService.cls | Audit trail query | 7 |
| Editor.RegistryService | src/cls/AgenticInterop/Editor/RegistryService.cls | Class registry for dropdowns (agents/mcps/toolsets/skills) | 6 |
| Editor.SourceService | src/cls/AgenticInterop/Editor/SourceService.cls | XData/source text read for editor | 6 |

## Policies

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| ConfirmationGate | src/cls/AgenticInterop/Policy/ConfirmationGate.cls | %AI.Policy.Authorization | Pauses execution for mutating tools (start_*, delete_*, etc. or requires_confirmation: true); surfaces approve/reject prompt to UI via SSE. Pre-approved tokens bypass the gate. | 4 |

## CSP web apps (registered via module.xml)

| URL | Type | Namespace | DispatchClass | Phase |
|---|---|---|---|---|
| /agentic/ | 1 (CSP files) | install ns | (static JS/HTML/CSS from src/csp/agentic/) | 0 |
| /api/agentic/ | 2 (REST) | install ns | AgenticInterop.REST.Dispatch | 0 |

Both web apps created with `UseCookies="0"` + no sessions/CSRF (the CSP gateway creates sessions on the first SSE POST, then CSRF validation rejects the next POST — fully stateless avoids this). NAMESPACE attribute defaults to the install namespace — no `<Namespace>` override in module.xml.

## Vector tables (created by Catalog builders)

| Table | KB tool name | Dimensions | Created by | Phase |
|---|---|---|---|---|
| (managed by %AI.RAG) | search_ens | 384 (FastEmbed AllMiniLML6V2) | Catalog.Builder.Build("ens", ...) | 5 |
| (managed by %AI.RAG) | search_hs | 384 | Catalog.Builder.Build("hs", ...) | 5 |

## Reference seed tables (SQL, not vector)

| Table | Created by | Phase |
|---|---|---|
| AgenticInterop_Reference.ErrorCode | Reference.Loader from error_codes.json | 5 |
| AgenticInterop_Reference.GlossaryTerm | Reference.Loader from glossary.json | 5 |
| AgenticInterop_Reference.ApiTopic | Reference.Loader from api_topics.json | 5 |

Reference data is seeded from JSON files (src/seed/) by `AgenticInterop.Reference.Loader`. These are SQL tables queried by `Tool.Catalog` methods (LookupErrorCode, LookupGlossaryTerm, SearchApiIndex), not vector KBs.

## Frontend (vanilla JS — no build step, part of the IPM ship)

| Path | Purpose | Phase |
|---|---|---|
| src/csp/agentic/chat/ | Chat UI (vanilla JS + CSS). Loads as iframe or standalone. SSE streaming. | 0 (scaffold), 2-7 (build out) |
| src/csp/agentic/admin/ | Admin SPA (vanilla JS + CSS). Entity CRUD, catalog management, audit trail. | 1, 4-7 |
| src/csp/agentic/inject.js | Script injected into the IRIS Interop Editor to add AI buttons | 0 |

## Seeds

| Path | Purpose | Phase |
|---|---|---|
| seeds/InterSystems_IRIS_Health_Complete_Class_Catalog.xlsx | XLS used by Catalog builders. Copy from /Users/dfranco/Desktop/... before Phase 5 | 5 (used) |

## What does NOT exist in this repo

- Customer Angular shell (the customer brings their own).
- Any namespace that the customer hasn't created themselves.
- Any LLM API key. All keys live in the Secured Wallet at runtime, never in source.
- Any Bedrock or other provider hardcoded — all selected via admin UI Provider rows.
