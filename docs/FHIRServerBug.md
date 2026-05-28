# FHIR Server — Bug & CORE-API Findings Log

Bugs, CORE-API quirks, and environment gotchas found while building the FHIR Server
MCP (Tools + Skill) for the agentic_interop FHIR Assistant.

**Methodology (project rule):** use the InterSystems **CORE** methods first
(`HS.FHIRServer.*`, `HS.FHIRMeta.*`, `HS.BulkFHIR.*`, `SYS.*`). When a CORE method
misbehaves, **document the bug here**, then bypass only if there is no CORE
alternative — and record the bypass.

Severity: 🔴 CORE API bug · 🟠 CORE API quirk (works, but trap) · 🟡 our tool bug · ⚪ environment/design

---

## 🔴 CORE-1 — `HS.FHIRServer.Installer.InstallInstance` declares `pPackageList:%String` but requires a `%List`

- **CORE method:** `HS.FHIRServer.Installer.InstallInstance(pAppKey, pStrategyClass, pPackageList:%String, ...)`
- **Symptom:** passing the package list as a comma-separated string
  (`"hl7.fhir.r4.core@4.0.1,hl7.fhir.us.core@3.1.0"`) fails with
  `ERROR #5809: Object to Load not found, class 'HS.FHIRMeta.Storage.Package',
  ID 'hl7.fhir.r4.core@4.0.1,hl7.fhir.us.core@3.1.0'` — the whole string is treated
  as a single package id.
- **Root cause:** the parameter is *declared* `%String`, but `InstallInstance` →
  `AddInstanceToRepo` → `HS.FHIRMeta.Storage.Package.ResolvePackageList(idList:%List)`
  actually expects a `$listbuild` **%List**. `ResolvePackageList` wraps a bare string
  as a single-element list, so one package works but a CSV of several does not.
- **Workaround:** build a real `%List` before calling — split the CSV and
  `$listbuild` each id. (`Set pkgList = pkgList _ $listbuild(onePkg)`.)
- **Status:** worked around in `Tool.FHIRServer.CreateFHIREndpoint` (commit `c54f5ee`).

## 🟠 CORE-2 — FHIR Server installer/admin methods are VOID and throw (no `%Status` return)

- **CORE methods (all return type `[]` = void):** `HS.FHIRServer.Installer.InstallInstance`,
  `UninstallInstance`, `Reset`, `InstallNamespace`, `AddPackagesToInstance`;
  `HS.FHIRServer.ServiceAdmin.SetInstanceConfigData`, `SetEndpointEnabled`,
  `DecommissionInstance`; `HS.BulkFHIR.Installer.Delete`.
- **Symptom:** calling them as `Set sc = ##class(...).Method(...)` raises
  `<COMMAND> Function must return a value` — and it fires **after** the operation
  has already run, so the work succeeds but the caller reports failure.
- **Root cause:** unlike most IRIS APIs, these are procedures that **throw on error**
  (`$$$ThrowStatus` / `$$$ThrowFHIR`) and return nothing on success. They are not
  `%Status` functions.
- **Correct CORE usage (not a bypass):** call with `Do`, wrap in `Try/Catch`, and
  confirm success with a CORE query — e.g. `HS.FHIRServer.ServiceAdmin.EndpointExists(url)`.
- **Status:** fixed across `Tool.FHIRServer` (`AddFHIRPackages`, `UpdateFHIREndpointConfig`,
  `SetFHIREndpointEnabled`, `DeleteFHIREndpoint`, `ResetFHIRServerData`, `CreateFHIREndpoint`)
  and `Tool.BulkFHIR.DeleteBFCConfig` (commits `c54f5ee`, `70ec260`, `7e1138b`).
  Verified end to end: create / add-packages / update-config / enable / disable /
  reset / delete all return `ok=1`.

## 🟠 CORE-3 — `HS.BulkFHIR.Installer.Export(url)` does NOT run an export

- **CORE method:** `HS.BulkFHIR.Installer.Export(pBFCurl) ReturnType HS.BulkFHIR.API.Data.Config`
- **Symptom:** a "start export" that silently does nothing.
- **Root cause:** the entire implementation is `return ##class(HS.BulkFHIR.Configuration).GetConfiguration(pBFCurl)`
  — it is a config **getter**, despite the name `Export`.
- **Reality:** a Bulk FHIR export is **initiated by the bulk-data client over REST**
  (`GET|POST <bfcEndpoint>/$export`) per the Bulk Data IG. There is no server-side
  "start export" class method (`ExportManager` only has `SessionRunningStatus` /
  `FlushSession` / `FinalizeSession`; `Service.DoSessionStart`/`OnStart` are internal
  REST-handler entry points).
- **Workaround:** `Tool.BulkFHIR.StartBFCExport` now verifies the config is ACTIVE and
  returns the exact `$export` REST kickoff (system/Patient/Group paths, Accept header,
  scopes, poll URL) instead of calling `Export`. (commit `7e1138b`).

## ⚪ ENV-1 — A FHIR endpoint can only be created in a FHIR **foundation** namespace

- **Symptom:** `CreateFHIREndpoint` in `HSCUSTOM` fails in
  `HS.FHIRMeta.Storage.Package.ResolvePackageList` (#5809 / `<UNDEFINED>repoManager`).
- **Root cause:** `HSCUSTOM` has the FHIR metadata package **files on disk**
  (`ListAvailableFHIRPackages` returns `/usr/irissys/dev/fhir/fhir-metadata/packages/...`)
  but **none registered**. Only the `FHIR` foundation namespace has registered packages
  (`HS.FHIRMeta.Storage.Package.GetAllPackages()` → `hl7.fhir.r4.core@4.0.1`,
  `hl7.fhir.us.core@3.1.0`, …).
- **Guidance:** create endpoints in a foundation namespace (`FHIR`); the FHIR Assistant
  namespace picker now steers there (see OUR-2).

## ⚪ ENV-2 — Bulk FHIR fetches FHIR ENDPOINTS, not folders; and the host desktop is not in the container

- BFC's fetch adapter takes a FHIR `endpoint_url` (`$export`/`$everything`), never a
  directory — a folder of bundles is not a FHIR server.
- To load a directory of FHIR files into a server, use `LoadFHIRDirectory`
  (CORE `HS.FHIRServer.Tools.DataLoader.SubmitResourceFiles`), and the path must be on
  the **IRIS server filesystem**. The `iris-agentic` container has **no volume mounts**,
  so the macOS Desktop is invisible inside it — copy in (`docker cp`) or mount.
- Synthea load order: per-patient bundles use conditional references to Organizations/
  Practitioners/Locations exported in separate `hospitalInformation*` /
  `practitionerInformation*` bundles, which must load **first** (else `ConditionalRefNotResolved`).
  `LoadFHIRDirectory` orders infrastructure bundles first.

## ⚪ ENV-3 — No CORE ingestion event/counter (ingestion timing is loader-only)

The IRIS FHIR Server has no supported hook or counter to time/count resource
ingestion across paths. Introspection (FHIR namespace):
`HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy` exposes only framework
internals (`%IncrementCount`, `%AddToSaveSet`) + config methods; `Interactions`
has `SearchMatchCount` / `GetPatientStatus` (search helpers), not an ingestion
counter. So ingestion throughput/bottleneck metrics (`GetFHIRLoadMetrics`,
`Data.FHIRLoadRun`) are captured ONLY for loads done via `LoadFHIRDirectory`.
Data ingested via REST / BFC / the FHIR Management UI is not timed — use
`GetFHIRServerStats` (path-independent point-in-time counts + storage size) for
those. Capturing all paths would require subclassing the InteractionsStrategy
(invasive, version-fragile) — deliberately NOT done. See `FHIRServerMCP.md` §4 C-alt.

## ⚪ ENV-4 — FHIR server size ≠ namespace database size

The namespace default database (`/usr/irissys/mgr/FHIR/`, ~1175 MB) holds the
namespace code + the FHIR metadata packages — it is large even with NO FHIR
server installed. The FHIR SERVER's actual data lives in DEDICATED repository
databases created per endpoint, named `<NS>X####R` (resources) and `<NS>X####V`
(versions) — e.g. `FHIRX0007R` / `FHIRX0007V`. So to report "FHIR server size",
`GetFHIRServerStats` measures only the `<NS>X####R/V` repository databases (CORE
`SYS.Database.Size`) and EXCLUDES the namespace default DB (name = `<NS>`). With
no endpoint there are no repo databases → server storage = 0 (correct), not 1175
MB. Verified: pattern `^<NS>X[0-9]+[RV]$` matches `FHIRX0007R`/`V`, excludes
`FHIR`; `GetFHIRServerStats(FHIR)` with no endpoint reports 0 MB.

## 🟡 OUR-1 — `%AI.ToolSet.%Discover()` is baked at compile time

- **Symptom:** a newly added tool method is invisible to the agent even after recompiling
  the `Tool` class.
- **Root cause:** `%Discover()` is generated into the **compiled ToolSet** from the
  included `Tool`'s methods at *toolset* compile time. Recompiling the Tool alone leaves
  the ToolSet's tool list stale; `DependsOn` only orders compilation, it does not cascade.
- **Workaround:** always recompile the `ToolSet` after editing a `Tool`
  (`$system.OBJ.Compile("AgenticInterop.ToolSet.X","ckd")`); verify with
  `ToolSet.%New().%Discover().tools.%Size()`. (Fixed 7 silently-missing tools incl.
  `LoadFHIRDirectory`.)

## 🟡 OUR-2 — FHIR namespace picker showed `HSCUSTOM` + "unknown"

- **Symptom:** the FHIR Assistant's namespace picker listed `HSCUSTOM` and a literal
  "unknown" instead of the `FHIR` foundation namespace.
- **Root cause:** `REST.Dispatch.IsFhirNamespace` keyed off an existing endpoint
  (`ServiceAdmin.GetEndpointList()`); with no endpoint (between create/delete) the
  FHIR-only list was empty, and `chat.js` fell back to the dispatch namespace
  (`HSCUSTOM`) + an "unknown" placeholder.
- **Fix:** detect a foundation namespace by **registered metadata packages** (the durable
  signal) via the CORE method `HS.FHIRMeta.Storage.Package.GetAllPackages()`; `chat.js`
  no longer shows "unknown" or auto-selects a non-FHIR namespace. (commit `52ebe47`;
  CORE-method refactor follows.)

## 🟡 OUR-3 — `%AI` framework passes `""` for omitted optional params, so ObjectScript defaults don't apply (broke Synthea load ordering)

- **Symptom:** loading a Synthea directory through the FHIR Assistant failed with
  `<HSFHIRErr>ConditionalRefNotResolved` on (nearly) every file — e.g. 32 of 108
  done, 32 failed — even though the folder contained the `hospitalInformation` and
  `practitionerInformation` bundles and `LoadFHIRDirectory` defaults `infraFirst=1`.
- **Root cause:** the load order was alphabetical, NOT infrastructure-first. The tool
  signature is `LoadFHIRDirectory(url, directory, infraFirst As %Boolean = 1, ...)`, but
  when the model omits `infraFirst` the **%AI framework passes it as `""`** (not omitted),
  so the ObjectScript default of `1` never applies and `If infraFirst` is false. Patient
  bundles loaded before the Organizations/Practitioners they reference by **conditional
  reference** (`Organization?identifier=...`), which the server resolves against the
  store → not found → `ConditionalRefNotResolved`. (`done` ticked up only when
  `hospitalInformation` finally came up in alphabetical position.) This is why the same
  data loaded fine in earlier dev runs — those called the tool with `infraFirst=1`
  explicitly; the regression only appears through the agent.
- **FHIR fact:** Synthea cross-bundle references (patient → hospital/practitioner) are
  **conditional references** resolved against persisted data, so the infrastructure
  bundles MUST be ingested before the patient bundles.
- **Fix:** normalize the flag at the top of `LoadFHIRDirectory` — treat `""`/unspecified
  as ON, only OFF when explicitly `0`/`false`:
  `Set infraFirst = $select($get(infraFirst)="":1, ...="true":1, ...="false":0, 1:+infraFirst)`.
  Verified by dry-run: with `infraFirst=""` the order is now hospitalInformation →
  practitionerInformation → patients.
- **General lesson:** never rely on an ObjectScript parameter default for a `%AI` tool —
  the framework supplies `""` for any optional the model omits. Normalize every optional
  at the method top.

## Note — `GetEndpointList()` returning empty is NOT a bug

Investigated as a suspected CORE bug; it was correct — the endpoint had genuinely been
deleted (user-initiated, confirmed in `messages.log`: `FHIRX0007R/V` dismounted). It is
consistent with `EndpointExists`. Recorded here so it is not re-investigated.

## ⚪ ENV-5 — OAuthClientName / SessionId on HS.FHIRServer.Interop.HTTPOperation are NOT settings

- **Symptom:** an outbound FHIR HTTP operation logs
  `ErrProductionSettingInvalid: Production setting 'OAuthClientName' for item ... is invalid`
  on every production start (also `SessionId`). Setting them via a System Default Setting
  (`Ens.Config.DefaultSettings`) does NOT help — same validation, same error.
- **Root cause:** `OAuthClientName` and `SessionId` are inherited PROPERTIES of
  `HS.FHIRServer.API.RestClient`, not declared in the host's `SETTINGS` parameter
  (which exposes only `ServiceName` + the inherited `Ens.BusinessOperation` settings).
  The Ens settings-validation pass rejects any name not in `SETTINGS`, regardless of
  whether it comes from the production-item Settings list or from System Default Settings.
- **How OAuth is REALLY wired (authoritative — `HS.FHIRServer.Interop.HTTPOperation.
  ProcessOAuth2` source):** the OAuth client name + session are read at runtime from the
  INCOMING request's `AdditionalInfo`:
  - `pFHIRRequest.AdditionalInfo.GetAt("USER:OAuthClient")` → the `OAuth2.Client` name
  - `pFHIRRequest.AdditionalInfo.GetAt("SessionId")` → the session id
  - then `##class(%SYS.OAuth2.AccessToken).IsAuthorized(oauthClientName, sessionId, ...)`
  - alternatives: `AdditionalInfo("USER:OAuthToken")` (token directly) or
    `AdditionalInfo("USER:TokenId")` (cached token id in HSSYSLOCALTEMP).
  The BPL/process that builds the `HS.FHIRServer.Interop.Request` must
  `request.AdditionalInfo.SetAt("<OAuth2.Client name>", "USER:OAuthClient")` (+ session id)
  BEFORE the request reaches the HTTP operation.
- **Second trap:** do NOT put the OAuth client name in the adapter `Credentials` setting.
  `Credentials` expects an IRIS credentials-registry entry (username/password); an OAuth
  client name there fails with `ErrNoCredentials: Unable to find Credentials for ID name`.
- **What IS valid on the HTTP operation host:** Adapter settings `HTTPServer`, `HTTPPort`,
  `URL`, `SSLConfig` only.
- **System Default Settings (`Ens.Config.DefaultSettings`, deployable via
  `Ens.Util.SettingsDocument` .ESD) — verified working for VALID settings:** defaulting
  `HTTPServer` to a per-environment value produced 0 errors and applied cleanly. Use it to
  promote HTTPServer/URL/SSLConfig/ports across dev→test→prod instead of hard-coding them.
- **Guard shipped:** `AgenticInterop.Tool.Production.RuntimeOnlyHostSetting()` +
  AddBusinessHost / UpdateBusinessHostSettings now strip `OAuthClientName`/`SessionId`
  Host settings on FHIR HTTP operation hosts and report them under `skippedSettings`,
  so the agent can no longer reintroduce the `ErrProductionSettingInvalid` error.
