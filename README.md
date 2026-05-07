# agentic_interop

Internal AI Copilot for InterSystems IRIS for Health. A configuration-driven chatbot that helps developers and integration engineers CRUD Productions, CRUD Transformations, and Test HL7/FHIR data inside any IRIS for Health namespace they have access to. Built entirely on the InterSystems %AI Framework.

## Status

Phase 5 (monitoring tools). The agent has 36 tools across 5 ToolSets, streaming chat with tool-call approval cards, vector catalog search, and a configuration-driven admin UI with cross-provider ToolSet editing. See:

- [docs/PLAN.md](docs/PLAN.md) — architecture decisions, restrictions, build phases
- [docs/MIGRATION.md](docs/MIGRATION.md) — class-by-class build map
- [docs/SKILLS.md](docs/SKILLS.md) — INSTRUCTIONS markdown for each `AgenticInterop.Skill.*` class, distilled from the IRIS for Health PDFs (grows batch-by-batch as PDFs are read)
- [docs/TOOLS.md](docs/TOOLS.md) — full catalog of agent tools, each one mapped to its IRIS API and source citation

## Tools

The agent's capabilities are organized into 5 ToolSet families (36 tools total). Each ToolSet is a `%AI.ToolSet` subclass that composes one or more `%AI.Tool` provider classes. The ToolSet editor in the admin UI supports cross-provider tool selection — any tool from any `%AI.Tool` class can be added to any ToolSet.

| ToolSet | Tools | Purpose |
|---|---|---|
| Catalog | 7 | Vector search over the Ens.* and HS.* class catalogs (powered by `%AI.RAG.KnowledgeBase`). Find the right Business Host, adapter, DTL, or HS utility for a given requirement. |
| Monitoring | 5 | Read-only queries against `Ens.Util.Log` and `Ens.MessageHeader`. Event log search, top-error grouping, message-status queries, per-host throughput summaries, and queue-depth checks. |
| Production | 9 | CRUD on productions, business host lifecycle (add/remove/enable/disable/start/stop), production start/stop/recover, and configuration reads. |
| Testing | 6 | Send and validate HL7 v2, FHIR R4, and SDA messages. Structure and semantic validation, message comparison, sample message retrieval. Sandbox-isolated by default. |
| Transform | 9 | CRUD on DTL transformations, BPL processes, business rules, and routing rules. Includes dry-run execution, static analysis, lookup table management, and compilation. |

## Requirements

- InterSystems IRIS for Health 2026.2 or newer
- IPM (ZPM) installed in the target namespace
- An LLM API key you control. Anthropic direct is the reference dev provider; Bedrock and Azure OpenAI are configurable but see [docs/PLAN.md](docs/PLAN.md) "Provider strategy" for the current Bedrock + tool-call hang status.

## Install

```bash
git clone https://github.com/dfrancoisc/agentic_interop.git
cd agentic_interop
```

In an IRIS terminal, switch to the namespace where you want the copilot installed (any namespace you have privileges in — HSCUSTOM, USER, a custom one):

```objectscript
ZN "<your-namespace>"
zpm "load /path/to/agentic_interop"
```

The module installs all classes, web apps, REST endpoints, and vector tables into the namespace where you ran `zpm load`. To install in multiple namespaces, run the command once per namespace.

## After install

1. Open the admin UI at `http://<host>:<web-port>/agentic/admin/`.
2. Connections tab — add an LLM Connection. Paste the API key. The key is stored in the IRIS Secured Wallet (`%Wallet.KeyValue` collection `AgenticInteropConnections`), never in plaintext.
3. Click "Test connection". Green status with model + latency means the wire path works.
4. Catalogs tab — click "Rebuild this catalog" on `search_ens` and `search_hs`. Pick `xls` source for the curated InterSystems Class Catalog ingestion (~1s). The KBs power vector search inside the chat.
5. The chatbot button appears in the Angular host page when a user is logged in. The active namespace is shown at the top of the chatbot window and is enforced by the access gate before any chat call runs.

## Mount API — embedding the chatbot in an Angular host page

The chat UI lives at `/agentic/chat/index.html`. It supports two integration modes:

**Iframe mode (recommended).** Set `iframe.src = '/agentic/chat/index.html?via=interop&namespace=' + currentNamespace`. The chat will:

- Capture the parent SPA's IRIS JWT via `postMessage` so no second login is required (the `/api/agentic` REST app shares `JWTAuthEnabled=1` and `GroupById=%ISCMgtPortal` with `/api/interop-editors`).
- Send `X-IRIS-Namespace: <currentNamespace>` on every chat request. The dispatch's access gate refuses (403) if the authenticated user lacks `%DB_<defaultDB>:Read` on the namespace's default database.
- Stream tokens via SSE into the message bubble. Tool-call cards render inline with their args, status, and result; mutating tools surface an Approve / Reject card.

**Standalone mode.** Open `/agentic/chat/index.html` directly. The page falls back to an inline credentials overlay; credentials persist in `localStorage` so the prompt only appears once per browser.

The chat UI is a vanilla TypeScript-style ES module — no build step. To customize:

- `src/csp/agentic/chat/chat.css` — colors, layout, font.
- `src/csp/agentic/chat/chat.js` — SSE event handling. Add a new `case` in the event dispatch for any custom event the server emits.
- `src/csp/agentic/admin/index.html` + `admin.js` — admin SPA, separate page.

## Operations runbook

**Daily.** No action required — the chat surface is self-serve and the audit log captures every request.

**On chat failure.**

1. Open admin → Audit tab → toggle "Errors only". The most recent failures show with their verbatim `ErrorText` once expanded.
2. Cross-reference with the Connection's "last test" status. A red Connection means the LLM provider rejected the credentials or model — re-test from the Connections tab.
3. The 60s deadline / 50k token budget on `agent.Run` (see [`AgenticInterop.Agent.Monitor`](src/cls/AgenticInterop/Agent/Monitor.cls)) caps any single chat turn — `Agent deadline exceeded` in the response means the LLM took too long, often because of the documented Bedrock tool-result framework hang. Try a narrower question or split it into steps.

**On approval card stuck "AWAITING APPROVAL".** The user's chat tab needs to be open to receive the approval click. Once they click APPROVE the next chat turn carries the matching token in `approvedTokens` and the gate lets the tool run. REJECT clears the card; the model already received the deny error and continues the conversation.

**Rebuilding catalogs.** After a `zpm load` of a different IRIS for Health version, click Rebuild on each catalog from the admin Catalogs tab. The XLS source (`/opt/agentic_interop/seeds/catalog.xlsx`) is shipped in the repo and re-deployed by the IPM module. The dictionary source walks the live `%Dictionary` of whichever namespace you pick.

**Wallet rotation.** Connections tab → open a connection → paste a new value into the API-key field → Save. The previous secret is overwritten in the Wallet (no orphan rows left behind).

**Cross-namespace install.** The dispatch class (`AgenticInterop.REST.Dispatch`) is only compiled in the install namespace (default HSCUSTOM). To serve chat against a different namespace, set the `X-IRIS-Namespace` header on the chat request — the dispatch stays in HSCUSTOM, validates the user's access to the requested namespace, and per-tool handlers switch to the target namespace internally.

## Development

See [docs/PLAN.md](docs/PLAN.md) "Build phases" for the current phase and what is unlocked next.

The runtime container used for local development is `iris-agentic` on ports 21972 (super) / 22773 (web) / 23773 (xDBC), separate from any other IRIS containers on the host. Login `_SYSTEM` / `Agentic1!`.

## License

TBD.
