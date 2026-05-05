# Agent Tool Catalog

Each tool below becomes one row in `AgenticInterop.Data.Tool`, dispatched at runtime by the matching executor (SQL / ObjectScript / Python / REST). Tools are surfaced to the agent through `AgenticInterop.Policy.DynamicToolDiscovery` (a `%AI.Policy.Discovery` subclass that reads the Tool table at query time — see PLAN.md "Skills" + "Dynamic tool discovery"). Each tool's `Body` references the API to invoke; the executor handles parameter binding and the standard envelope.

This file grows batch-by-batch. Tools marked `[BATCH N]` were finalised in that batch; all others are pending.

Standard output envelope for any non-streaming tool: `{ "ok": true, "data": <result>, "namespace": "<current>" }` on success, `{ "ok": false, "error": { "code": "<code>", "message": "<text>" }, "namespace": "<current>" }` on error. The current namespace is always included so the chatbot can verify the user's expected namespace matches the execution namespace.

All tools execute in the request's `$namespace` (set by the dispatch class via `new $namespace` from the request header) per restriction #7. No tool may switch namespaces internally without an explicit `namespace` argument and the user's authorization.

---

## ToolSet.Production  [BATCH 1]

Tools for production-class CRUD, lifecycle management, business host CRUD, and event/message/alert observation. Source PDFs: Configuring_Productions, Developing_Productions, Introducing_Interoperability_Productions.

### list_productions

- Description: List all productions in the current namespace, with state, last started timestamp, and basic counts. Use this when the user asks "what productions exist", "is X running", or as a discovery starting point.
- Implementation: ObjectScript
- Body: queries `Ens_Config.Production` plus `Ens.Director.GetProductionStatus()` for the running one.
- Input schema: `{}` (no inputs; namespace comes from request).
- Output schema: `{ productions: [ { name, isCurrentRunning, state, lastStarted, lastStopped, hostCount } ] }`. State values: `Running`, `Suspended`, `Troubled`, `Stopped`. Only one can be `Running` per namespace.
- Timeout: 5 seconds.
- RequiresConfirmation: false (read-only).

### get_production

- Description: Return a production's full definition (the `XData ProductionDefinition` block) plus class metadata. Use this before suggesting any modification.
- Implementation: ObjectScript
- Body: reads `%Dictionary.ClassDefinition` for the production class + parses the XData block.
- Input schema: `{ name: { type: "string", required: true, description: "Fully-qualified production class name, e.g. MyApp.MyProduction" } }`.
- Output schema: `{ name, description, productionType, actorPoolSize, items: [ { name, className, hostType, poolSize, enabled, foreground, inactivityTimeout, settings: [ { name, value } ], commentDescription } ] }`. `hostType` is one of `BusinessService`, `BusinessProcess`, `BusinessOperation` derived from the item's class hierarchy.
- Timeout: 5 seconds.
- RequiresConfirmation: false.

### create_production

- Description: Create a new production class extending `Ens.Production`. The class is created in the namespace and compiled. Returns the fully-qualified class name. Use only after the user confirms the desired package, name, and type.
- Implementation: ObjectScript (writes a new class definition then compiles).
- Body: programmatic class generation using `%Dictionary.ClassDefinition` then `$system.OBJ.Compile()`. The XData ProductionDefinition is initialised empty with `<ActorPoolSize>2</ActorPoolSize>`.
- Input schema: `{ packageName: { type: "string", required: true }, productionName: { type: "string", required: true }, description: { type: "string" }, productionType: { type: "string", enum: ["Generic","HL7"], default: "Generic" } }`.
- Output schema: `{ name, created: true }`.
- Timeout: 30 seconds.
- RequiresConfirmation: TRUE (creates a class).

### delete_production

- Description: Delete a production class. Refuses if the production is running. Refuses if the production is the only `Ens.Production` subclass without explicit user override. Use carefully.
- Implementation: ObjectScript (`$system.OBJ.Delete()`).
- Input schema: `{ name: { type: "string", required: true }, force: { type: "boolean", default: false } }`.
- Output schema: `{ name, deleted: true }`.
- Timeout: 10 seconds.
- RequiresConfirmation: TRUE.

### start_production / stop_production / recover_production

- Description (start): Start the named production. There can be only one running production per namespace; if another is running, this fails — use stop_production first.
- Description (stop): Stop the currently running production. Use restart only when needed; running productions survive Management Portal closes.
- Description (recover): Recover a Troubled production. No-op if not Troubled.
- Implementation: ObjectScript.
- Body (start): `##class(Ens.Director).StartProduction(name)`. (stop): `##class(Ens.Director).StopProduction()`. (recover): `##class(Ens.Director).RecoverProduction()`.
- Input schema (start): `{ name: { type: "string", required: true } }`. (stop, recover): `{}`.
- Output schema: `{ ok: true, name?, state }` — state queried via `Ens.Director.GetProductionStatus()` after the action.
- Timeout: 60 seconds (productions can take time to fully stop, especially when active calls are mid-flight).
- RequiresConfirmation: TRUE for all three (lifecycle changes affect external systems).

### get_production_status

- Description: Return current production name + state + per-host states (Running, Inactive, etc.) + queue depths. Use as a quick health snapshot.
- Implementation: ObjectScript.
- Body: `Ens.Director.GetProductionStatus()` + iterate items to query each host's state and queue depth.
- Input schema: `{}`.
- Output schema: `{ productionName, productionState, items: [ { name, hostType, state, queueLength, lastActivity } ] }`.
- Timeout: 10 seconds.
- RequiresConfirmation: false.

### list_business_hosts

- Description: List all business hosts (services + processes + operations) in a named production, with status. Use when the user asks "what hosts are in X" or "which BS receive HL7 from facility Y".
- Implementation: ObjectScript.
- Body: parses `Ens_Config.Item` rows for the production.
- Input schema: `{ productionName: { type: "string", required: true }, hostTypeFilter: { type: "string", enum: ["any","BusinessService","BusinessProcess","BusinessOperation"], default: "any" } }`.
- Output schema: `{ items: [ { name, className, hostType, enabled, poolSize, category, comment } ] }`.
- Timeout: 5 seconds.
- RequiresConfirmation: false.

### add_business_host

- Description: Add a business host to a production. Validates the host class against `catalog.ens` so the agent picks the right shipped class for the requested behavior. Updates the production's XData ProductionDefinition; does not generate any new class. Configuration name must match the rules (no `| ; , : [ < > \ / & "`; no leading/trailing `! $ .`; no leading `_`; not `*`).
- Implementation: ObjectScript.
- Body: opens the production class, edits the ProductionDefinition XData via XML manipulation, recompiles.
- Input schema: `{ productionName: { type: "string", required: true }, hostType: { type: "string", enum: ["BusinessService","BusinessProcess","BusinessOperation"], required: true }, className: { type: "string", required: true }, name: { type: "string", required: true }, settings: { type: "object", description: "Map of setting name to value, e.g. {\"Port\":1972}" }, enableNow: { type: "boolean", default: false } }`.
- Output schema: `{ productionName, itemName, added: true }`.
- Timeout: 30 seconds.
- RequiresConfirmation: TRUE.

### update_business_host_settings

- Description: Modify settings on an existing business host in a production. Settings take effect immediately. Use sparingly for runtime tuning; for environment-specific values prefer System Default Settings.
- Implementation: ObjectScript.
- Body: `Ens.Director.SetItemSettingValue(itemFullName, settingName, value)` for each setting in the input. Item full name format: `productionName||itemName`.
- Input schema: `{ productionName: { type: "string", required: true }, itemName: { type: "string", required: true }, settings: { type: "object", required: true } }`.
- Output schema: `{ updated: { settingName: "newValue" }, errors: [ { setting, message } ] }`.
- Timeout: 15 seconds.
- RequiresConfirmation: TRUE.

### remove_business_host

- Description: Remove a business host from a production's XData ProductionDefinition. Does not delete the underlying class. The host's queue is preserved if not empty.
- Implementation: ObjectScript.
- Input schema: `{ productionName: { type: "string", required: true }, itemName: { type: "string", required: true } }`.
- Output schema: `{ removed: true }`.
- Timeout: 15 seconds.
- RequiresConfirmation: TRUE.

### enable_business_host / disable_business_host

- Description: Toggle the `Enabled` setting on a business host. Disabling does not stop the production; the host stays present but stops processing messages. The queue continues to accept messages while disabled.
- Implementation: ObjectScript via `Ens.Director.SetItemSettingValue(itemFullName, "Enabled", 0|1)`.
- Input schema: `{ productionName: { type: "string", required: true }, itemName: { type: "string", required: true } }`.
- Output schema: `{ enabled: true|false }`.
- Timeout: 5 seconds.
- RequiresConfirmation: TRUE for disable; false for enable (re-enable is reversible).

### start_business_host / stop_business_host

- Description: Temporarily start or stop a single host without modifying the production class. Useful when the production is under source control. Only available for hosts with `Pool Size > 1` or business-process/operation hosts using the queue invocation.
- Implementation: ObjectScript via management portal action APIs (`Ens.Director.TempStopItem` / `TempStartItem`-style).
- Input schema: `{ productionName: { type: "string", required: true }, itemName: { type: "string", required: true } }`.
- Output schema: `{ ok: true }`.
- Timeout: 30 seconds.
- RequiresConfirmation: TRUE.

### get_event_log

- Description: Return recent Event Log entries for the production or a specific host. Filter by type (Info, Warning, Error, Alert, Trace, Assert, Status) and time. Use when troubleshooting "why is X failing".
- Implementation: SQL.
- Body: `SELECT TimeLogged, Type, ConfigName, Text FROM Ens_Util.Log WHERE ConfigName = ? AND TimeLogged >= ? AND Type IN (...) ORDER BY TimeLogged DESC FETCH FIRST :limit ROWS ONLY` (parameterised).
- Input schema: `{ configName: { type: "string", description: "Production or item name; * for all" }, since: { type: "string", description: "ISO-8601 timestamp" }, types: { type: "array", items: "string" }, limit: { type: "integer", default: 50 } }`.
- Output schema: standard query envelope.
- Timeout: 10 seconds.
- RequiresConfirmation: false.

### get_message_trace

- Description: Return the visual-trace view of a message — its session, all related messages (request/response chains), and timing. Use this to answer "what happened to message X" or "trace this transaction".
- Implementation: SQL + ObjectScript helpers.
- Body: queries `Ens.MessageHeader` joined to `Ens.MessageBody` for the session ID derived from the message ID.
- Input schema: `{ messageId: { type: "string", required: true } }`.
- Output schema: `{ sessionId, messages: [ { id, type, source, target, status, timeCreated, timeProcessed, bodyClassName, bodyPreview } ] }`.
- Timeout: 10 seconds.
- RequiresConfirmation: false.

### search_messages

- Description: Search the message log by criteria (host, status, body text, time window). Returns message headers; pair with `get_message_trace` for full traces.
- Implementation: SQL.
- Body: parameterised query against `Ens.MessageHeader` joined to search-table classes when applicable.
- Input schema: `{ source: { type: "string" }, target: { type: "string" }, status: { type: "string", enum: ["Created","Queued","Delivered","Completed","Suspended","Discarded","Error","Aborted","Deferred"] }, timeFrom: { type: "string" }, timeTo: { type: "string" }, limit: { type: "integer", default: 50 } }`.
- Output schema: standard query envelope.
- Timeout: 15 seconds.
- RequiresConfirmation: false.

### get_alerts

- Description: List unresolved Ens.Alert entries for the production. Includes alert type (QueueCountAlert, QueueWaitAlert, DeadJobAlert, custom), text, source host, and timestamp.
- Implementation: SQL.
- Body: `SELECT Id, TimeLogged, ConfigName, Text FROM Ens_Util.Log WHERE Type = 'Alert' AND ResolutionTime IS NULL ORDER BY TimeLogged DESC`.
- Input schema: `{ since: { type: "string" }, limit: { type: "integer", default: 100 } }`.
- Output schema: standard query envelope plus per-row `parsedAlertType` (the prefix before `:` if present).
- Timeout: 5 seconds.
- RequiresConfirmation: false.

### ack_alert

- Description: Acknowledge / mark an alert as resolved. Required for managed-alert workflows (Ens.Alerting.AlertManager).
- Implementation: ObjectScript via `Ens.Alerting.ManagedAlert` API.
- Input schema: `{ alertId: { type: "string", required: true }, resolution: { type: "string" } }`.
- Output schema: `{ acknowledged: true }`.
- Timeout: 5 seconds.
- RequiresConfirmation: TRUE.

### get_production_settings / get_host_settings / get_adapter_settings

- Description: Return the resolved settings for a production / host / adapter, showing each value's source (production definition / system defaults / class default) — corresponds to the Production Configuration page color coding (black / blue / green).
- Implementation: ObjectScript via `Ens.Director.GetProductionSettings`, `GetHostSettings`, `GetAdapterSettings`.
- Input schema (production): `{ productionName: { type: "string", required: true } }`. (host/adapter): `{ itemFullName: { type: "string", required: true, description: "Format: productionName||itemName" } }`.
- Output schema: `{ settings: [ { name, value, source } ] }`.
- Timeout: 5 seconds.
- RequiresConfirmation: false.

---

## ToolSet.Catalog  [BATCH 1 PARTIAL — search tools added in batch 4 / phase 5]

The catalog toolset depends on the FastEmbed-backed `%AI.RAG.KnowledgeBase` instances (catalog.ens, catalog.hs) seeded from `InterSystems_IRIS_Health_Complete_Class_Catalog.xlsx`. These tools are stubbed in Phase 2 (returning fake data) and wired to real RAG in Phase 5. Their schemas are stable from Batch 1.

### search_ens

- Description: Vector-search the Ens.* catalog (HL7 + Production-related — Business Services, Business Processes, Business Operations, Inbound + Outbound Adapters, Productions, relevant message classes). Use this when the user asks "which BS sends HL7 over MLLP", "what adapter handles SFTP", "is there a stock class for X".
- Implementation: ObjectScript via `%AI.ToolMgr.ExecuteTool("search_ens", { query, k })`. Wraps the registered RAG tool.
- Input schema: `{ query: { type: "string", required: true }, k: { type: "integer", default: 5, minimum: 1, maximum: 20 } }`.
- Output schema: `{ hits: [ { className, namespace, packageName, type, abstract, purpose, whenToUse, keySettings, score } ] }`.
- Timeout: 10 seconds.
- RequiresConfirmation: false.

### search_hs

- Description: Vector-search the HS.* catalog (FHIR + Transformations — DTL Transforms, BPL Processes, Schema Data Model, REST/SOAP, Utilities). Use when the user asks "is there a stock DTL for HL7 to FHIR", "which class converts SDA to HL7v2", "where is the FHIR validator".
- Implementation, input/output schema, timeout, requires_confirmation: same shape as `search_ens`, different KB.

### describe_class

- Description: Return raw `%Dictionary.ClassDefinition` info for a class — super, abstract, parameters, properties, methods. Use when search returns a candidate and the user wants details before committing.
- Implementation: SQL against `%Dictionary.ClassDefinition`, `%Dictionary.PropertyDefinition`, `%Dictionary.MethodDefinition`, `%Dictionary.ParameterDefinition`.
- Input schema: `{ className: { type: "string", required: true } }`.
- Output schema: `{ name, super, abstract, description, parameters: [...], properties: [...], methods: [...] }`.
- Timeout: 5 seconds.
- RequiresConfirmation: false.

### describe_catalog_entry

- Description: Return the catalog row for a specific class (`Class Name, Namespace, Package, Type, Abstract, Purpose, When to Use, Key Settings`) — the curated description from the InterSystems_IRIS_Health_Complete_Class_Catalog.xlsx. Use when the user wants the editor's "When to Use" guidance rather than the raw class definition.
- Implementation: SQL against `AgenticInterop_Catalog.Ens` or `AgenticInterop_Catalog.Hs` depending on which catalog the row lives in.
- Input schema: `{ className: { type: "string", required: true } }`.
- Output schema: row contents.
- Timeout: 5 seconds.
- RequiresConfirmation: false.

---

## ToolSet.Cross-cutting  [BATCH 1]

These tools are exposed on the main agent (router) directly, not behind a Skill, because every interaction needs them.

### get_user_namespace

- Description: Return the current request's namespace. The chatbot calls this first and shows the value in its header so the user can verify they are operating in the expected namespace.
- Implementation: ObjectScript: `$namespace`.
- Input schema: `{}`.
- Output schema: `{ namespace }`.
- Timeout: 1 second.
- RequiresConfirmation: false.

### list_user_accessible_namespaces

- Description: Return the list of namespaces the requesting user has access to (filtered by `%Service_Login` resource and namespace-level permissions). Used in the chatbot's namespace-switcher dropdown.
- Implementation: ObjectScript via `%SYS.Namespace.ListAll()` filtered by user privileges.
- Input schema: `{}`.
- Output schema: `{ namespaces: [ { name, isInteroperabilityEnabled } ] }`.
- Timeout: 5 seconds.
- RequiresConfirmation: false.

---

## ToolSet.Transform  [PENDING — batches 2 + 3]

## ToolSet.Testing  [PENDING — batch 4]
