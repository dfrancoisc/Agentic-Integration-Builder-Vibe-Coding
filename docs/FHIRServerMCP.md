# FHIR Server MCP — Architecture, Inventory, and Build Backlog

The end-to-end FHIR Server MCP (Tools + Skill) for the FHIR Assistant. This
document is the plan of record: it states the runtime model, inventories what
exists, and ENUMERATES what still needs to be built **before** building it.

---

## 1. Runtime model (who does what)

```
User ──▶ FHIR Assistant chatbot  (Data.Chatbot key = "fhir-management")
              │   resolves agent →  AgenticInterop.Agent.FHIRSpecialist
              │   LLM at runtime  =  the AI Settings CONNECTION (e.g. Bedrock Claude),
              │                      NOT Claude Code / not the dev-time model
              ▼
        %AI.Agent turn loop
              │  picks tools from the bound MCPs, reads the attached Skills
              ▼
        MCP.FHIRServer / MCP.BulkFHIR ──▶ ToolSet ──▶ Tool.* ClassMethods
              │
              ▼
        CORE IRIS APIs (HS.FHIRServer.*, HS.FHIRMeta.*, HS.BulkFHIR.*, SYS.*)
```

- **Claude Code (dev-time, me):** authors ObjectScript Tools, Skills, the
  Agent, REST endpoints, and UI. Compiles/tests them. Does NOT run at the
  user's runtime and does NOT "control" the FHIR server.
- **The configured Connection LLM (run-time):** drives the FHIR Assistant. It
  can only do what the **tools** expose and what the **skills** teach. So every
  capability — including metrics capture — must be a tool that returns data
  from CORE APIs, callable by that LLM.
- **Rule:** never bypass CORE. Use the documented `HS.*` / `SYS.*` methods;
  when a CORE method is buggy, record it in `FHIRServerBug.md` and only then
  work around it.

---

## 2. Current inventory (what already exists)

### MCP / ToolSet / Tool
| MCP | ToolSet | Tool class | Tools |
|---|---|---|---|
| `MCP.FHIRServer` | `ToolSet.FHIRServer` | `Tool.FHIRServer` | 26 |
| `MCP.BulkFHIR` | `ToolSet.BulkFHIR` | `Tool.BulkFHIR` | 13 |

### Skills (attached to `Agent.FHIRSpecialist`)
`Skill.FHIRServer`, `Skill.FHIRR4`, `Skill.SDA`, `Skill.BulkFHIR`,
`Skill.FHIRSQLBuilder`.

### FHIR Server tools (24) — by capability
- Discover/inspect: `DiscoverFHIRNamespaces`, `ListFHIREndpoints`, `GetFHIREndpoint`, `GetCapabilityStatement`
- Resources: `SearchFHIRResources`, `ReadFHIRResource`, `CreateFHIRResource`, `UpdateFHIRResource`, `DeleteFHIRResource`, `ValidateFHIRResource`, `ExecuteFHIRRequest`, `CountFHIRResources`
- Packages/config: `ListAvailableFHIRPackages`, `AddFHIRPackages`, `UpdateFHIREndpointConfig`, `SetFHIREndpointEnabled`
- Provisioning: `CreateFHIREndpoint`, `DeleteFHIREndpoint`, `ResetFHIRServerData`
- Loading: `LoadFHIRDirectory`, `LoadFHIRData`, `GetFHIRLoadStatus`
- **Metrics/audit:** `GetFHIRLoadMetrics`, `GetFHIRServerStats`

### Metrics/audit surface (built)
- `GetFHIRLoadMetrics` — per-load duration, resources/sec, MB/sec, bottlenecks
  (slowest files). Data source: per-file timing recorded by `LoadFHIRDirectory`
  in `^AgInt.FHIRLoad`.
- `GetFHIRServerStats` — resource counts by type (CORE FHIR `_summary=count`)
  + database sizes (CORE `SYS.Database`).
- REST `GET /api/agentic/fhir/audit` — combines both for the UI.
- UI: left slide-in **FHIR Server Audit** panel injected into the FHIR
  Management header (`/agentic/audit/`).

### CORE methods used (so far)
`HS.FHIRServer.ServiceAdmin.*` (EndpointExists, GetEndpointList,
GetInstanceIdForEndpoint, GetInstanceConfigData, IsEndpointEnabled,
SetEndpointEnabled, SetInstanceConfigData, DecommissionInstance),
`HS.FHIRServer.Installer.*` (InstallInstance, UninstallInstance, Reset,
AddPackagesToInstance, InstallNamespace), `HS.FHIRServer.Service.EnsureInstance`
+ `DispatchRequest`, `HS.FHIRServer.Tools.DataLoader.SubmitResourceFiles`,
`HS.FHIRMeta.Storage.Package.GetAllPackages`, `SYS.Database` (Size),
`Config.Databases:List`.

---

## 3. Known limitations of the current metrics (honest)

1. **Ingestion metrics only cover loads done through `LoadFHIRDirectory`.**
   Data ingested by any other path (BFC ingestion, direct REST `POST`, the FHIR
   Management UI, `LoadFHIRData`) is NOT timed — those paths don't record into
   `^AgInt.FHIRLoad`.
2. **No persisted history / trend.** `^AgInt.FHIRLoad` holds recent runs only;
   there is no durable run log to compare loads over time or chart growth.
3. **No query/throughput-at-rest performance metric** (search latency, index
   build status).
4. **Storage matching is heuristic** (DB name contains the namespace name).

---

## 4. Build backlog — ENUMERATED (review before I build)

Each item: what, why, the CORE/source it uses, the artifact (Tool/Skill/UI/Data),
and status. Nothing below is built yet unless marked DONE.

### A. Persisted ingestion run log + history tool
- **What:** a persistent class `AgenticInterop.Data.FHIRLoadRun` (one row per
  load: namespace, endpoint, jobId, started/finished, files, resources,
  durationSec, resources/sec, MB, status). `LoadFHIRDirectory` writes a row on
  completion. New tool `ListFHIRLoadRuns(namespace, limit)` returns history.
- **Why:** durable metrics + trends; survive global cleanup; power a history
  table in the audit panel.
- **Artifact:** Data class + 1 tool + loader hook.

### B. FHIR query/performance probe tool
- **What:** `GetFHIRQueryPerformance(url, resourceType, namespace)` — runs a
  small set of representative CORE FHIR searches (e.g. `_summary=count`, a
  paged search) and reports elapsed ms per query; reports pending index builds
  (CORE `IndicesTask` / build status) if available.
- **Why:** answers "is the server fast / are indexes built" at rest, not just
  at load time.
- **Artifact:** 1 tool (CORE FHIR search timing + index status).

### C. Storage growth snapshot + history
- **What:** `SnapshotFHIRStorage(namespace)` records DB sizes (CORE
  `SYS.Database`) into a `Data.FHIRStorageSnapshot` row; `GetFHIRStorageTrend`
  returns the series. Optionally a scheduled task to snapshot daily.
- **Why:** show storage growth over time in the panel.
- **Artifact:** Data class + 1–2 tools (+ optional task).

### C-alt (researched — NOT building). Capture ingestion for ALL paths
- **Question:** is there a CORE-sanctioned hook/counter so any ingestion
  (REST/BFC/UI), not just `LoadFHIRDirectory`, is timed/counted?
- **Research finding (introspected in the FHIR namespace):** NO supported
  ingestion event or per-load counter exists.
  - `HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy` exposes only
    framework internals (`%IncrementCount`, `%AddToSaveSet`, `%OnAddToSaveSet`)
    and config methods (`SaveServiceConfigData`, `Update`) — no create/update
    ingestion hook.
  - `HS.FHIRServer.Storage.JsonAdvSQL.Interactions` has `SearchMatchCount`,
    `isSelectCountAllowed`, `GetPatientStatus` — search/count helpers, not an
    ingestion counter or event.
- **Conclusion:** capturing all-path ingestion timing would require subclassing
  / overriding the InteractionsStrategy's interaction handling — invasive,
  version-fragile, and not a supported extension point for metrics. **Decision:
  do NOT build it.** Instead:
  - path-INDEPENDENT state (counts, storage size) is already covered by
    `GetFHIRServerStats` (point-in-time, CORE);
  - loader-based throughput/bottlenecks are covered by `GetFHIRLoadMetrics` +
    the `FHIRLoadRun` history (item A).
  This limitation is stated in `FHIRServerBug.md` (ENV) and in the skill.

### D. Audit panel enhancements (UI)
- **What:** add a load-history table (from A), a storage-trend mini-chart (from
  C), a per-endpoint selector, and a manual "Snapshot now" action.
- **Why:** the "collect all information ... so we can improve it" dashboard.
- **Artifact:** `/agentic/audit/index.html` additions.

### E. Skill documentation of the metrics workflow
- **What:** extend `Skill.FHIRServer` so the agent knows WHEN to call each
  metrics tool and how to interpret/explain bottlenecks, throughput, storage,
  and remediation advice.
- **Why:** the LLM only uses tools well if the skill teaches the workflow.
- **Artifact:** `Skill.FHIRServer` INSTRUCTIONS.

### F. Docs
- **What:** keep `TOOLS.md`, this file, and `FHIRServerBug.md` current for every
  new tool; document each tool's input/output and CORE source.
- **Status:** ongoing.

---

## 5b. Behavior + UI refinements (what + why)

1. **Agent plans before creating an endpoint (prompt).** Symptom: asked to
   "create a FHIR server", the agent called `CreateFHIREndpoint` with blind
   defaults (in `HSCUSTOM`, the app namespace) and then rambled about unrelated
   production tools (`CreateProduction`/`AddBusinessHost`). Fix: FHIRSpecialist
   INSTRUCTIONS now require a PLAN-and-CLARIFY flow for endpoint creation —
   discover the foundation namespace, propose `namespace`/`url`/`packages`/
   `strategy`, ASK for anything unspecified, state the exact parameters, then
   create only on confirmation; verify with `GetCapabilityStatement`. Also:
   never invent requirements / unrelated tools, no "I understand your concern"
   filler. Why: build endpoints correctly, not with guessed defaults.
2. **MCP chain confirmed (Agent → MCP → ToolSet → Tools + Skills).**
   `Agent.FHIRSpecialist`: `TOOLBINDING=mcp`; `MCPS=MCP.FHIRServer,MCP.BulkFHIR,
   MCP.Catalog`; `SKILLS=` 5 skills. `Manager.Build` registers via the MCP path
   (`bindingMode=mcp` → `MCP.RegisterToAgent` → ToolSet → Tool). The live
   transcript proves it (the agent called FHIRServer + Catalog tools through the
   chain). No bypass.
3. **Audit menu moved to the LEFT NAV.** The first cut put an Audit button in
   the page header; the request was the LEFT navigation menu. The FHIR
   Management app is third-party Angular Material (`mat-sidenav` >
   `mat-nav-list` > `mat-list-item`). CORE/UI note: there is no server-side API
   to add a nav item to a shipped Angular app, so `inject.js` adds it by DOM
   injection — `ensureSideNavAudit()` finds the sidenav nav-list, clones an
   existing `mat-list-item` for styling, relabels it "FHIR Audit", strips its
   router link, and binds it to open the audit panel. The header button is kept
   as a fallback entry point. Gated to the `fhir-management` chatbot and hidden
   on the login screen.
4. **Audit always targets the FHIR foundation namespace, never HSCUSTOM.** The
   `/fhir/audit` handler resolves the target server-side: honor the requested
   namespace only if it is itself a FHIR namespace; else prefer one with a FHIR
   endpoint (`DiscoverFHIRNamespaces`); else any FHIR foundation namespace
   (`collectNamespaces(fhirOnly)`); only then fall back. So even when the
   picker/dispatch namespace is `HSCUSTOM`, the audit reports the `FHIR`
   namespace where the server lives (verified: requested HSCUSTOM -> audited
   FHIR, storage shows the FHIR database). The response carries both `namespace`
   (audited) and `requestedNamespace`.

## 5c. Load FHIR Data menu (upload to a server folder)

Problem: the FHIR server's DataLoader (`LoadFHIRDirectory`) can only read files
on the IRIS server filesystem, and the container has no mount to the user's
machine — so host files were unreachable without `docker cp`. CORE note: there
is no FHIR API for "upload host files to the server", so this is a small
file-staging feature, separate from the FHIR repository.

- REST (`Dispatch`): `POST /api/agentic/fhir/upload` (multipart) writes the
  uploaded `.json` files to a server staging folder
  `<mgr>/Temp/agentic-fhir-upload/` using the CORE CSP upload API
  (`%request.NextMimeData`/`CountMimeData`/`GetMimeData` → `%Stream.FileBinary`).
  Files are owned by the IRIS process user, so the FHIR server can read them (no
  chmod/root needed, unlike docker cp). `GET` lists the folder; `DELETE` clears
  it. It does NOT POST into the FHIR repository — staging only.
- UI: a "Load FHIR Data" item in the FHIR Management left nav opens a panel
  (`/agentic/upload/`) with a multi-file picker, Upload, the resulting server
  folder path, the staged-files list, a Clear button, and the exact instruction
  to then tell the FHIR Assistant to load that folder (`LoadFHIRDirectory`,
  which orders infrastructure bundles first). The folder path has a copy
  button (clipboard API with an execCommand fallback for non-secure http)
  so the user can paste it straight into the chatbot.
- Verified end to end via curl: POST stages a file at
  `/usr/irissys/mgr/Temp/agentic-fhir-upload/` (owned by irisowner), GET lists
  it, DELETE clears it.

## 5d. Live load progress bar in chat (what + why)

Why: `LoadFHIRDirectory` runs the load as a background `Job` and returns a
`jobId` + `total` immediately (a large Synthea set takes minutes — far longer
than a single chat turn, and chat must never block, per the no-timeouts rule).
The user wants to SEE how far along the load is, not read a wall of text.

How: the load already records progress in `^AgInt.FHIRLoad(jobId, "total"/"done"/
"failed"/"status"/"current")` in the dispatch namespace (status: queued →
running → completed|error; `done`/`failed` increment per file). We surface it:

- REST (`Dispatch`): `GET /api/agentic/fhir/load/status?jobId=...` reads that
  global directly (no Observer/tool-log spam from frequent polls) and returns
  `{ ok, found, status, total, filesDone, filesFailed, done, percent, current?,
  error? }`. Verified: percent computed correctly; route registered (401 unauth).
- Chat UI (`chat.js`): when a `tool_result` for `LoadFHIRDirectory` carries a
  `jobId` (and `ok`, not `dryRun`), it renders a progress bar inside the
  assistant message and polls the status endpoint every ~1.5s, animating the
  fill and showing "N of M files" + the current file, until `completed`/`error`.
  Styles in `chat.css` (`.fhir-load*`), themed; no icons/emoji. Decoupled from
  the chat turn, so minutes-long loads are not bound by the turn deadline.
- Agent: `LoadFHIRDirectory`'s result message and `GetFHIRLoadStatus`'s doc now
  tell the agent the chat shows the bar — report that the load started + the
  count, then stop; do NOT poll `GetFHIRLoadStatus` in a loop.
- Reset: the Audit panel has a "Clear metrics" button backed by
  `DELETE /api/agentic/fhir/load/history`, which kills `^AgInt.FHIRLoad` and
  empties `Data.FHIRLoadRun` (metrics only — never the loaded FHIR resources),
  so the audit can start fresh.

## 5. Status legend
- DONE: GetFHIRLoadMetrics, GetFHIRServerStats, /fhir/audit, audit panel,
  CORE refactor (GetAllPackages), FHIRServerBug.md.
- DONE (approved build): A (Data.FHIRLoadRun + ListFHIRLoadRuns + loader hook),
  B (GetFHIRQueryPerformance), E (skill metrics workflow).
- RESEARCHED — not building: C-alt (no supported CORE ingestion hook; see above).
- DEFERRED (not approved this round): C (storage-growth history), D (audit-panel
  history table / trend chart).
- Tool count: FHIRServer 26, BulkFHIR 13 (86 total).
