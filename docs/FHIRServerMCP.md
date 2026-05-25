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
| `MCP.FHIRServer` | `ToolSet.FHIRServer` | `Tool.FHIRServer` | 24 |
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

### C-alt (decision needed). Capture ingestion for ALL paths
- **Option:** a CORE-sanctioned hook so any ingestion (REST/BFC/UI) is counted,
  not just `LoadFHIRDirectory`. Likely a thin subclass/observer of the
  InteractionsStrategy, or reading the FHIR server's own counters if exposed.
- **Trade-off:** more invasive; needs research into whether CORE exposes a
  supported ingestion counter/event. **Recommend: research-and-document first**
  (it may be that point-in-time `GetFHIRServerStats` + run log is enough).

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

## 5. Status legend
- DONE: GetFHIRLoadMetrics, GetFHIRServerStats, /fhir/audit, audit panel,
  CORE refactor (GetAllPackages), FHIRServerBug.md.
- TO BUILD (awaiting approval): A, B, C, C-alt (research), D, E.
