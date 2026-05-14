# agentic_interop

AI Copilot for InterSystems IRIS for Health. A configuration-driven chatbot that helps integration engineers build, review, and optimize healthcare interoperability workflows through natural conversation. Built entirely on the InterSystems %AI Framework.

The copilot bridges the gap between healthcare data expertise and InterSystems platform knowledge. Instead of navigating Management Portal screens and writing ObjectScript by hand, engineers describe what they need in plain English and the copilot builds it using real IRIS APIs.

## Status

All build phases complete (Phase 0 through Phase 7). The agent has 42 tools across 5 Tool classes, 9 domain skills, streaming chat with tool-call approval cards, vector catalog search, and a full admin UI.

| Metric | Value |
|---|---|
| ObjectScript classes | 58 |
| Tool classes (%AI.Tool) | 5 (Production, Transform, Testing, Catalog, Monitoring) |
| Tools (public ClassMethods) | 42 |
| ToolSets (%AI.ToolSet) | 5 |
| MCP servers | 5 (Production, Transform, Testing, Catalog, Monitoring) |
| Skills (%AI.Agent.Skill) | 9 |
| Persistent data classes | 5 (Connection, AgentOverride, MCPOverride, ToolSetOverride, AuditLog) |

Documentation:

- [docs/PRD.md](docs/PRD.md) — Product Requirements Document (also available as [PRD.docx](docs/PRD.docx))
- [docs/PLAN.md](docs/PLAN.md) — architecture decisions, restrictions, build phases
- [docs/MIGRATION.md](docs/MIGRATION.md) — class-by-class build map
- [docs/SKILLS.md](docs/SKILLS.md) — INSTRUCTIONS markdown for each skill, distilled from IRIS for Health PDFs
- [docs/TOOLS.md](docs/TOOLS.md) — full catalog of agent tools with IRIS API mappings
- [docs/BUG.md](docs/BUG.md) — known framework bugs, workarounds, and ObjectScript gotchas

## Two personas, two experiences

The product separates two distinct user journeys:

**Developer Experience (DX)** — InterSystems engineers and partners who author the underlying capabilities: writing Tool classes in ObjectScript/Python, authoring Skill documents, building catalog embeddings. This work happens in VS Code or any IDE and ships as compiled classes inside an IPM package. Developers define what the copilot can do.

**Builder Experience (End User)** — Integration engineers inside IRIS for Health and Health Connect who configure and use the copilot: creating Agents with custom system prompts, assembling MCP Servers from available ToolSets, linking Skills to Agents, and chatting with the copilot to build productions. This work happens entirely in the IRIS Management Portal UI. Builders decide how the copilot behaves for their use case.

## Tools

The agent's capabilities are organized into 5 Tool classes (42 tools total). Each Tool class is a `%AI.Tool` subclass where every public ClassMethod is a tool the LLM can call. Tools are composed into `%AI.ToolSet` subclasses and registered with the agent at build time.

| Tool class | Tools | Purpose |
|---|---|---|
| Production | 10 | CRUD on productions, business host lifecycle (add/remove/configure/start/stop/recover), post-build validation |
| Transform | 14 | CRUD on DTL (Data Transformation Language) transformations, BPL (Business Process Language) processes, routing rules. Includes dry-run execution, HL7 schema introspection, lookup tables, SDA-FHIR DTL listing, transformation pipeline description |
| Testing | 6 | Send and validate HL7 v2 and FHIR R4 messages. Structure and semantic validation, message comparison |
| Catalog | 7 | Vector search over Ens.* and HS.* class catalogs, class introspection via %Dictionary, namespace utilities, error code and glossary lookups |
| Monitoring | 5 | Read-only queries against Ens.Util.Log and Ens.MessageHeader. Event log search, top-error grouping, message status queries, per-host throughput summaries, queue depth checks |

## Skills

Nine domain skills teach the agent IRIS-specific concepts. Each skill is a `%AI.Agent.Skill` subclass with markdown INSTRUCTIONS distilled from InterSystems documentation PDFs.

| Skill | Domain | ToolSet access |
|---|---|---|
| Productions | Production anatomy, BS/BP/BO patterns, lifecycle management | Production |
| DTL | DTL syntax, foreach, subtransforms, lookup tables, virtual documents | Transform |
| BPL | BPL activities, compensation handlers, async patterns | Transform |
| RoutingRules | Rule sets, constraints, when-conditions, dead-letter handling | Production |
| HL7v2 | Message types, segments, ACK semantics, schema navigation | Testing |
| FHIRR4 | Resources, references, search parameters, R4 bundles | Testing |
| SDA | SDA3 model as transformation hub, HL7-to-SDA-to-FHIR pipeline | Testing |
| RestInProductions | REST services and operations inside productions | Production |
| ESBPattern | Using a production as an Enterprise Service Bus | Production + Transform |

## Requirements

- InterSystems IRIS for Health 2026.2 or newer
- IPM (ZPM) installed in the target namespace
- An LLM API key you control. Anthropic direct is the reference provider. Bedrock and Azure OpenAI are configurable but see [docs/BUG.md](docs/BUG.md) for the current Bedrock tool-call hang

## Install

```bash
git clone https://github.com/dfrancoisc/agentic_interop.git
cd agentic_interop
```

In an IRIS terminal, switch to the namespace where you want the copilot installed (any namespace you have privileges in):

```objectscript
ZN "<your-namespace>"
zpm "load /path/to/agentic_interop"
```

The module installs all 58 classes, two web apps (`/agentic/` for the UI, `/api/agentic/` for REST), seed data, and the curated class catalog into the namespace where you ran `zpm load`. To install in multiple namespaces, run the command once per namespace.

## After install

1. Open the admin UI at `http://<host>:<web-port>/agentic/admin/`.
2. Connections tab — add an LLM Connection. Paste the API key. The key is stored in the IRIS Secured Wallet (`%Wallet.KeyValue` collection `AgenticInteropConnections`), never in plaintext.
3. Click "Test connection". Green status with model and latency means the wire path works.
4. Catalogs tab — click "Rebuild this catalog" on `search_ens` and `search_hs`. Pick `xls` source for the curated InterSystems Class Catalog ingestion. The knowledge bases power vector search inside the chat.
5. The chatbot button appears in the Angular host page when a user is logged in. The active namespace is shown at the top of the chatbot window and enforced by the access gate before any chat call runs.

## Chatbot experience

The chat UI streams responses token-by-token via Server-Sent Events (SSE). Tool calls render as inline cards showing the tool name, arguments, status, and collapsible result. Mutating tools (production creation, DTL compilation, etc.) pause with an inline Approve / Reject prompt before executing.

Key features:
- Conversation history rail with search, resume, and rename
- Starter prompts for common use cases (build a production, review settings, create a transformation)
- Plan presentation with explicit user approval before any build
- Post-build validation checklist (production running, hosts enabled, no errors, messages flowed)
- Build completion and test execution reports with per-component detail
- Full audit trail of every tool invocation (visible in the admin Audit tab)

## Admin UI

The admin UI provides configuration pages for all entities. No code edits required to add a tool, change a model, or reconfigure an agent.

| Page | Purpose |
|---|---|
| Connections | LLM provider configuration with masked secret input, live test button, green/red status |
| Agents | System prompt editor, temperature, max iterations, MCP and skill attachment |
| MCPs | ToolSet selection per MCP server |
| ToolSets | Include/exclude tools from any Tool class via dual-panel selector |
| Tools | Browse tool catalog with descriptions, parameter signatures, and dry-run panel |
| Skills | Markdown INSTRUCTIONS editor for each domain skill |
| Catalogs | Vector catalog rebuild trigger, source selection (XLS or %Dictionary) |
| Audit | Searchable log of every tool invocation with input, output, duration, and error detail |

## Mount API — embedding the chatbot

The chat UI lives at `/agentic/chat/index.html`. Two integration modes:

**Iframe mode (recommended).** Set `iframe.src = '/agentic/chat/index.html?via=interop&namespace=' + currentNamespace`. The chat captures the parent SPA's IRIS JWT via `postMessage` (no second login), sends `X-IRIS-Namespace` on every request, and refuses access (403) if the user lacks database-level read on the target namespace.

**Standalone mode.** Open `/agentic/chat/index.html` directly. The page shows an inline credentials overlay on first visit; credentials persist in `localStorage`.

The chat UI is a vanilla JS module with no build step. Customization points:
- `src/csp/agentic/chat/chat.css` — colors, layout, font
- `src/csp/agentic/chat/chat.js` — SSE event handling
- `src/csp/agentic/admin/index.html` + `admin.js` — admin SPA

## Operations runbook

**Daily.** No action required. The chat surface is self-serve and the audit log captures every request.

**On chat failure.**
1. Admin - Audit tab - toggle "Errors only". Recent failures show with verbatim error text.
2. Check the Connection's last test status. A red Connection means the LLM provider rejected credentials or model.
3. The 60-second deadline / 50,000-token budget on `agent.Run` (see `AgenticInterop.Agent.Monitor`) caps any single chat turn. "Agent deadline exceeded" means the LLM took too long. Try a narrower question or split into steps.

**On approval card stuck.** The user's chat tab must be open. Click APPROVE to continue or REJECT to cancel. The agent acknowledges rejections and asks how to proceed.

**Rebuilding catalogs.** After installing a different IRIS for Health version, click Rebuild on each catalog from the admin Catalogs tab. The XLS source is shipped in the repo; the dictionary source walks the live `%Dictionary` of the current namespace.

**Wallet rotation.** Connections tab - open a connection - paste new API key - Save. The previous secret is overwritten (no orphan rows).

**Cross-namespace.** The dispatch class compiles in the install namespace. To chat against a different namespace, the `X-IRIS-Namespace` header routes tool execution there after validating user access.

## Known issues

See [docs/BUG.md](docs/BUG.md) for details on:
- `%AI.Agent.Skill.%OnNew` JSON marshaling bug (workaround: `AgenticInterop.Skill.Base`)
- Bedrock tool-result round-trip hang (workaround: use Anthropic direct provider)
- `%AI` include file not visible outside %SYS (workaround: inlined macro values)
- ObjectScript language gotchas (QUIT in blocks, comment syntax, numeric comparisons)

## Development

All 7 build phases are complete. See [docs/PLAN.md](docs/PLAN.md) for architecture details and [docs/MIGRATION.md](docs/MIGRATION.md) for the class-by-class build map.

The runtime container used for local development is `iris-agentic` on ports 21972 (super) / 22773 (web) / 23773 (xDBC), separate from any other IRIS containers on the host.

## License

TBD.
