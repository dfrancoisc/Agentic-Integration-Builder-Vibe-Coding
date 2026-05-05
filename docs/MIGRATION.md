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
| Agent | src/cls/AgenticInterop/Data/Agent.cls | %Persistent, %JSON.Adaptor | Agent definition: name, system prompt, model, temperature, refs to Provider, MCPServers, Skills | 1 |
| MCPServer | src/cls/AgenticInterop/Data/MCPServer.cls | %Persistent, %JSON.Adaptor | Logical MCP grouping (UI only — no HTTP). Holds list of Toolsets | 1 |
| Toolset | src/cls/AgenticInterop/Data/Toolset.cls | %Persistent, %JSON.Adaptor | Maps a config row to a runtime ToolSet class name + display metadata | 1 |
| Tool | src/cls/AgenticInterop/Data/Tool.cls | %Persistent, %JSON.Adaptor | Tool def: name, description, input/output schema, implementation kind, body, timeout, RequiresConfirmation | 1 |
| Skill | src/cls/AgenticInterop/Data/Skill.cls | %Persistent, %JSON.Adaptor | Markdown content injected into agent system prompt | 1 |
| Conversation | src/cls/AgenticInterop/Data/Conversation.cls | %Persistent, %JSON.Adaptor | Chat session header (id, agent, namespace, opened-at) | 2 |
| Message | src/cls/AgenticInterop/Data/Message.cls | %Persistent, %JSON.Adaptor | Chat messages tied to a Conversation | 2 |
| ToolInvocation | src/cls/AgenticInterop/Data/ToolInvocation.cls | %Persistent, %JSON.Adaptor | Audit row per tool call: input, output, duration, error | 4 |

## %AI.Agent + %AI.ToolSet implementations

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| HealthInterop | src/cls/AgenticInterop/Agent/HealthInterop.cls | %AI.Agent | The single agent class. Declarative XData INSTRUCTIONS, Parameter TOOLSETS = "AgenticInterop.ToolSet.Catalog,..." | 2 |
| Production | src/cls/AgenticInterop/ToolSet/Production.cls | %AI.ToolSet | Production CRUD tools — Includes from inline methods + Production.Tool.* if needed | 4 |
| Transform | src/cls/AgenticInterop/ToolSet/Transform.cls | %AI.ToolSet | DTL/BPL CRUD + lookup tables | 4 |
| Testing | src/cls/AgenticInterop/ToolSet/Testing.cls | %AI.ToolSet | HL7/FHIR send + validate (against an isolated test production by default) | 4 |
| Catalog | src/cls/AgenticInterop/ToolSet/Catalog.cls | %AI.ToolSet | search_ens, search_hs (RAG-backed); describe_class | 2 (stub), 5 (real) |

## Agent runtime

| Class | Path | Extends | Purpose | Phase |
|---|---|---|---|---|
| Manager | src/cls/AgenticInterop/Agent/Manager.cls | %RegisteredObject | Loads Data.Agent → builds %AI.Agent (calls %Init, attaches toolsets, registers Skills into system prompt). Caches per-conversation. | 2 |
| Runtime | src/cls/AgenticInterop/Agent/Runtime.cls | %RegisteredObject | Wraps agent.Run() with the iteration monitor. Emits SSE events for token + tool-lifecycle (Phase 3+). | 2 (sync), 3 (SSE) |
| Monitor | src/cls/AgenticInterop/Agent/Monitor.cls | %RegisteredObject | Iteration callback object: deadline, token budget, optional SSE writer. Pattern from ai-hub-iteration-monitor skill. | 2 |
| SkillLoader | src/cls/AgenticInterop/Agent/SkillLoader.cls | %RegisteredObject | Loads Data.Skill rows → injects markdown blocks into agent system prompt | 2 |

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

Tables created in install namespace.

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
