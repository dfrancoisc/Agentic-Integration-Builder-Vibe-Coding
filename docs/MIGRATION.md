# agentic_interop — Class Build Map

The full plan-to-repo mapping for every class, web app, vector table, and seed file the build will create. Updated BEFORE any class is written or moved (per the user's "build class-mapping tables before refactors" rule).

Conventions:
- All classes live under `src/cls/AgenticInterop/...` with the file path mirroring the class name.
- All classes extend `%RegisteredObject` unless noted.
- Persistent classes additionally extend `%JSON.Adaptor`.
- Embedded Python is preferred for boto3 / anthropic SDK / openpyxl / json-schema validation; ObjectScript for IRIS-native ops.
- Phase column = the build phase that creates the class. See docs/PLAN.md "Build phases".

## Persistent data model (`AgenticInterop.Data.*`)

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Provider | src/cls/AgenticInterop/Data/Provider.cls | %Persistent, %JSON.Adaptor | LLM provider rows: name, kind, non-secret config JSON, WalletRef, semaphore status | 1 |
| Agent | src/cls/AgenticInterop/Data/Agent.cls | %Persistent, %JSON.Adaptor | Agent definition: name, system prompt, model, temperature, ref to Provider, list of MCPServer refs, and Skills as a `list of %String` (each entry is a fully-qualified %AI.Agent.Skill subclass name like "AgenticInterop.Skill.Productions") | 1 |
| MCPServer | src/cls/AgenticInterop/Data/MCPServer.cls | %Persistent, %JSON.Adaptor | Logical MCP grouping (UI only — no HTTP). Holds list of Toolsets | 1 |
| Toolset | src/cls/AgenticInterop/Data/Toolset.cls | %Persistent, %JSON.Adaptor | Maps a config row to a runtime ToolSet class name + display metadata | 1 |
| Tool | src/cls/AgenticInterop/Data/Tool.cls | %Persistent, %JSON.Adaptor | Tool def: name, description, input/output schema, implementation kind, body, timeout, RequiresConfirmation | 1 |
| (Data.Skill REMOVED) | — | — | Skills are %AI.Agent.Skill SUBCLASSES (code-defined, shipped with the IPM module), NOT user-editable data rows. The Data.Agent table holds a string-list of Skill class names that the runtime instantiates and adds to the parent agent's ToolManager. See "Skill classes" section below. | — |
| Conversation | src/cls/AgenticInterop/Data/Conversation.cls | %Persistent, %JSON.Adaptor | Chat session header (id, agent, namespace, opened-at) | 2 |
| Message | src/cls/AgenticInterop/Data/Message.cls | %Persistent, %JSON.Adaptor | Chat messages tied to a Conversation | 2 |
| ToolInvocation | src/cls/AgenticInterop/Data/ToolInvocation.cls | %Persistent, %JSON.Adaptor | Audit row per tool call: input, output, duration, error | 4 |

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

## Wallet + Provider integration

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Vault | src/cls/AgenticInterop/Wallet/Vault.cls | %RegisteredObject | Helpers around %Wallet.Collection / %Wallet.KeyValue. Idempotent secret-write API. Reads via SettingStore @{wallet.X.Y} placeholders. | 1 |
| Factory | src/cls/AgenticInterop/Provider/Factory.cls | %RegisteredObject | Maps Data.Provider row → %AI.Provider (resolves @{wallet.X.Y} via SettingStore). Also runs healthcheck (1-token chat completion) and updates Status/LastError on the Data.Provider row. | 1 |

## Tool execution layer

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Registry | src/cls/AgenticInterop/Tool/Registry.cls | %RegisteredObject | Loads Data.Tool rows → builds the per-tool dispatch entries that ToolSets pick up via Include or programmatic AddTool | 4 |
| SqlExecutor | src/cls/AgenticInterop/Tool/SqlExecutor.cls | %RegisteredObject | Runs SQL bodies against the current $namespace, returns standard envelope | 4 |
| ObjectScriptExecutor | src/cls/AgenticInterop/Tool/ObjectScriptExecutor.cls | %RegisteredObject | Calls a class method by ##class()/$classmethod from the Tool.Body reference | 4 |
| PythonExecutor | src/cls/AgenticInterop/Tool/PythonExecutor.cls | %RegisteredObject | Imports a Python module/class via %SYS.Python, calls method, marshals JSON | 4 |
| RestExecutor | src/cls/AgenticInterop/Tool/RestExecutor.cls | %RegisteredObject | Calls an external/internal REST endpoint with the Tool.Body URL template | 4 |
| Monitoring | src/cls/AgenticInterop/Tool/Monitoring.cls | %AI.Tool | 5 read-only SQL tools (QueryEventLog, TopErrors, QueryMessageStatus, MessageSummary, QueueStatus) querying Ens_Util.Log and Ens.MessageHeader | 5 |
| Production | src/cls/AgenticInterop/Tool/Production.cls | %AI.Tool | 9 production lifecycle + host CRUD tools (ListProductions, GetProduction, CreateProduction, DeleteProduction, StartProduction, StopProduction, AddBusinessHost, RemoveBusinessHost, UpdateBusinessHostSettings) | 4 |
| Testing | src/cls/AgenticInterop/Tool/Testing.cls | %AI.Tool | 6 HL7/FHIR validation + send tools (ValidateHL7Structure, ValidateHL7Semantics, ValidateFHIRResource, CompareMessages, SendHL7, SendFHIR) | 4 |
| Transform | src/cls/AgenticInterop/Tool/Transform.cls | %AI.Tool | 9 DTL/BPL/rule CRUD tools (ListDTLs, ListLookupTables, ListBusinessRules, DryRunDTL, CompileDTL, CreateDTL, UpdateDTL, CreateBPL, ValidateBPL) | 4 |
| Catalog | src/cls/AgenticInterop/Tool/Catalog.cls | %AI.Tool | 9 introspection + vector search tools (GetUserNamespace, ListUserAccessibleNamespaces, DescribeClass, ExplainStatus, LookupErrorCode, LookupGlossaryTerm, SearchApiIndex, SearchEns, SearchHs) | 2 (stub), 5 (real) |

## Catalog (RAG)

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| EnsBuilder | src/cls/AgenticInterop/Catalog/EnsBuilder.cls | %RegisteredObject | Reads XLS sheets relevant to Ens (Business Services/Processes/Operations + Adapters + Productions). Uses Embedded Python (openpyxl). Idempotent. | 5 |
| HsBuilder | src/cls/AgenticInterop/Catalog/HsBuilder.cls | %RegisteredObject | Reads XLS sheets relevant to HS (DTL/BPL/Schema/REST/Utilities). Idempotent. | 5 |
| EnsKnowledgeBase | src/cls/AgenticInterop/Catalog/EnsKnowledgeBase.cls | %RegisteredObject | %AI.RAG.KnowledgeBase wiring (FastEmbed + IRIS VectorStore) for catalog.ens table. Tool name: search_ens | 5 |
| HsKnowledgeBase | src/cls/AgenticInterop/Catalog/HsKnowledgeBase.cls | %RegisteredObject | Same shape for catalog.hs. Tool name: search_hs | 5 |

## REST surface (`AgenticInterop.REST.*`)

| Class | Path | Extends | URL prefix | Purpose | Phase |
|---|---|---|---|---|---|
| Dispatch | src/cls/AgenticInterop/REST/Dispatch.cls | %CSP.REST | /api/agentic/ | UrlMap router. Reads X-IRIS-Namespace header, validates access, does `new $namespace`. UseSession=0. | 0 |
| HealthAPI | src/cls/AgenticInterop/REST/HealthAPI.cls | %CSP.REST | /api/agentic/health | Returns {ok, namespace, version} | 0 |
| NamespaceAPI | src/cls/AgenticInterop/REST/NamespaceAPI.cls | %CSP.REST | /api/agentic/namespace | Returns current namespace + user-accessible namespaces list | 0 |
| ProviderAPI | src/cls/AgenticInterop/REST/ProviderAPI.cls | %CSP.REST | /api/agentic/v1/providers | CRUD + /healthcheck + /secret | 1 |
| ConfigAPI | src/cls/AgenticInterop/REST/ConfigAPI.cls | %CSP.REST | /api/agentic/v1/{agents,mcps,toolsets,tools,skills} | CRUD for the five entity tables | 1 (agents/mcps), 4 (rest) |
| ChatAPI | src/cls/AgenticInterop/REST/ChatAPI.cls | %CSP.REST | /api/agentic/v1/chat | POST conversations + SSE messages | 2 (sync), 3 (SSE) |
| CatalogAPI | src/cls/AgenticInterop/REST/CatalogAPI.cls | %CSP.REST | /api/agentic/v1/catalog | search_ens, search_hs, rebuild | 5 |

## Policies

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| ConfirmationGate | src/cls/AgenticInterop/Policy/ConfirmationGate.cls | %AI.Policy.Authorization | Pauses execution for any tool with RequiresConfirmation = 1; surfaces approve/reject prompt to UI via SSE | 4 |
| AuditToInvocation | src/cls/AgenticInterop/Policy/AuditToInvocation.cls | %AI.Policy.Audit | Persists every tool call to Data.ToolInvocation | 4 |

## CSP web apps (registered via module.xml)

| URL | Type | Namespace | DispatchClass | Phase |
|---|---|---|---|---|
| /agentic/ | 1 (CSP files) | install ns | (static React bundle from src/csp/agentic/) | 0 |
| /api/agentic/ | 2 (REST) | install ns | AgenticInterop.REST.Dispatch | 0 |

Both web apps created with `UseSession="0"` (CSP iframe deadlock workaround documented in project memory). NAMESPACE attribute defaults to the install namespace — no `<Namespace>` override in module.xml.

## Vector tables (created by Catalog builders)

| Table | Schema | Dimensions | Created by | Phase |
|---|---|---|---|---|
| AgenticInterop_Catalog.Ens | id, text, vector, metadata, source, plus promoted fields: package, type, abstract | 384 (FastEmbed AllMiniLML6V2) | Catalog.EnsBuilder.Build() | 5 |
| AgenticInterop_Catalog.Hs | same shape | 384 | Catalog.HsBuilder.Build() | 5 |
| AgenticInterop_Catalog.ErrorReference | id, text, vector, metadata (errorCode, domain, category, placeholders) | 384 | Catalog.ReferenceBuilder.BuildErrors() | 5 |
| AgenticInterop_Catalog.Glossary | id, text, vector, metadata (term, category, relatedTerms) | 384 | Catalog.ReferenceBuilder.BuildGlossary() | 5 |
| AgenticInterop_Catalog.ApiIndex | id, text, vector, metadata (topic, availableTools, availableClasses, relevantSkill) | 384 | Catalog.ReferenceBuilder.BuildApiIndex() | 5 |

Tables created in install namespace.

`Catalog.ReferenceBuilder` (added in Phase 5 alongside EnsBuilder/HsBuilder) ingests the four reference PDFs (Configuration_Parameter_File_Reference, Detailed_API_Index, InterSystems_Error_Reference, InterSystems_Glossary_of_Terms) into these vector tables. Same FastEmbed embedder, same `%AI.RAG.KnowledgeBase` pattern, exposed as `search_errors`, `search_glossary`, `search_api_index` tools. Wired into ToolSet.Reference.

## Frontend (not %AI Framework, but part of the IPM ship)

| Path | Purpose | Phase |
|---|---|---|
| frontend/ | Vite + React 18 + TypeScript source. Built output goes to src/csp/agentic/ for IPM packaging | 0 (scaffold), 2-7 (build out) |
| frontend/src/main.tsx | Entry point; exports `window.AgenticInterop.mount(rootEl, opts)` | 0 |
| frontend/src/api/* | Typed REST client | 1 |
| frontend/src/features/chat/* | Chat UI + SSE | 2-3 |
| frontend/src/features/admin/* | One list + form page per entity | 1, 4-6 |
| src/csp/agentic/index.html | Sample host HTML for testing the bundle without an Angular shell | 0 |

## Seeds

| Path | Purpose | Phase |
|---|---|---|
| seeds/InterSystems_IRIS_Health_Complete_Class_Catalog.xlsx | XLS used by Catalog builders. Copy from /Users/dfranco/Desktop/... before Phase 5 | 5 (used) |

## What does NOT exist in this repo

- Customer Angular shell (the customer brings their own).
- Any namespace that the customer hasn't created themselves.
- Any LLM API key. All keys live in the Secured Wallet at runtime, never in source.
- Any Bedrock or other provider hardcoded — all selected via admin UI Provider rows.
