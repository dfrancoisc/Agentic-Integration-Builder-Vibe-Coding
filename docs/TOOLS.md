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

## ToolSet.Production extensions  [BATCH 2]

These extend the Production toolset with tools learned from Best_Practices, Managing, and Monitoring PDFs.

### get_auto_start / set_auto_start

- Description (get): Return the auto-start configuration for the current namespace — the production set to auto-start (if any), the Relative Startup Priority, and the cluster-wide override flag (EnsembleAutoStart).
- Description (set): Configure or disable auto-start for a production. Strongly recommended for live deployments per IRIS best practices.
- Implementation: ObjectScript via the Auto-Start Production page's underlying APIs (`Ens.Director.SetAutoStart()` family).
- Input schema (set): `{ productionName: { type: "string" }, relativeStartupPriority: { type: "integer", default: 0 }, disable: { type: "boolean", default: false, description: "Set to true to disable auto-start in this namespace" } }`.
- Output schema: `{ productionName, relativeStartupPriority, autoStartEnabled, ensembleAutoStartGlobal }`.
- Timeout: 5 seconds. RequiresConfirmation: TRUE for set.

### list_shutdown_groups / set_shutdown_group

- Description: Manage Production Shutdown Groups (integers, lower number stops first; default 2). Sequenced shutdown adds latency — important to know for time-sensitive failover plans.
- Implementation: ObjectScript reads/writes `^Ens.Configuration.ShutdownGroups` (or equivalent persisted store).
- Input schema (set): `{ productionName: { type: "string", required: true }, shutdownGroup: { type: "integer", required: true } }`.
- Timeout: 5 seconds. RequiresConfirmation: TRUE for set.

### deploy_production

- Description: Apply an XML deployment package to update or install a production. Saves a rollback file, disables affected components, imports + compiles (rolls back on compile error), updates settings, re-enables. Use only with explicit user confirmation since it modifies running production state.
- Implementation: ObjectScript via `Ens.Deployment.Deploy()`-family methods.
- Input schema: `{ deploymentXmlPath: { type: "string", required: true }, targetProductionName: { type: "string" }, rollbackFile: { type: "string", required: true }, deploymentLogFile: { type: "string", required: true } }`.
- Output schema: `{ ok, deploymentId, rollbackFile, log: [...] }`.
- Timeout: 600 seconds. RequiresConfirmation: TRUE.

### rollback_deployment / get_deployment_history

- Description (rollback): Apply a rollback file from a prior deployment to revert changes.
- Description (history): List recent deployments with status, timestamp, deploying user, deployment notes.
- Implementation: ObjectScript via the Deployment Changes pages' underlying APIs.
- Input schema (rollback): `{ rollbackFile: { type: "string", required: true } }`.
- Input schema (history): `{ limit: { type: "integer", default: 20 } }`.
- Timeout: 600 sec rollback / 5 sec history. RequiresConfirmation: TRUE for rollback only.

### purge_production_data

- Description: Run a production data purge. Honors the documented Purge Management Data settings: NumberOfDaysToKeep, BodiesToo, KeepIntegrity, TypesToPurge, optionalMessageLimitToConfigItems, optionalMessageWorkQueueCategory, plus startDateTime / doNotDeleteEndDateTime UTC overrides.
- Implementation: ObjectScript via `Ens.Util.MessagePurge.Purge()` for messages; `Ens.Util.Tasks.Purge` for the broader purge.
- Input schema: `{ types: { type: "array", items: "string", description: "Events / Messages / Business Processes / Rule Logs / I/O Logs / Host Monitor Data / Managed Alerts" }, daysToKeep: { type: "integer", default: 7 }, bodiesToo: { type: "boolean", default: false }, keepIntegrity: { type: "boolean", default: true }, limitToConfigItems: { type: "array", items: "string" }, workQueueCategory: { type: "string" }, workQueueBatchSize: { type: "integer", minimum: 10000 }, startDateTimeUtc: { type: "string" }, doNotDeleteEndDateTimeUtc: { type: "string" }, dryRun: { type: "boolean", default: false, description: "Estimate counts without deleting" } }`.
- Output schema: `{ deletedByType: { Events: N, Messages: N, ... }, durationMs, journalBytesGenerated }`.
- Timeout: 1800 seconds. RequiresConfirmation: TRUE — purges are irreversible. Default the LLM to dryRun=true unless the user explicitly confirms a destructive purge.

### schedule_purge

- Description: Schedule recurring production data purges via the Task Manager (`Ens.Util.Tasks.Purge`).
- Implementation: ObjectScript via `%SYS.Task` API.
- Input schema: same fields as `purge_production_data` plus `{ taskName: { type: "string", required: true }, intervalHours: { type: "integer", required: true }, startTime: { type: "string", description: "ISO time of day to run, e.g. 02:00:00" } }`.
- Timeout: 5 seconds. RequiresConfirmation: TRUE.

### get_production_states_summary

- Description: System-wide production summary — equivalent to the Production System Monitor page. Useful as a one-call health check.
- Implementation: ObjectScript aggregating `Ens.Director.GetProductionStatus()` across namespaces, plus throughput counters from `^IRIS.Temp.EnsMetrics`.
- Input schema: `{}`.
- Output schema: `{ productionsRunning, productionsSuspendedOrTroubled, incomingMessagesLast30s, outgoingMessagesLast30s, lastIncomingTime, lastOutgoingTime, totalProductionJobs, mostActiveQueues: [...], seriousSystemAlerts, productionAlerts, productionErrors }`.
- Timeout: 10 seconds. RequiresConfirmation: false.

### get_queue_status / get_active_jobs / get_suspended_messages

- Description: Per-host or per-production queue depths, in-flight jobs, suspended-message details. Mirror Interoperability > Monitor > Queues / Jobs / View > Suspended Messages.
- Implementation: SQL against `Ens.Queue`-related globals + `Ens_Util.Log` for status.
- Input schema (queue/jobs): `{ productionName: { type: "string" }, hostName: { type: "string" } }`. (suspended): `{ productionName: { type: "string" }, since: { type: "string" }, limit: { type: "integer", default: 100 } }`.
- Output schema: standard query envelope.
- Timeout: 10 seconds. RequiresConfirmation: false.

### get_business_rule_log / get_business_process_instances

- Description: View recent business rule executions with reason, return value, error info; or list active/completed BPL business process instances with primary request, session, status.
- Implementation: SQL against `Ens.Rule.Log` / `Ens.BusinessProcess`, `Ens.BusinessProcessBPL`.
- Input schema (rule log): `{ ruleName: { type: "string" }, sessionId: { type: "string" }, errorsOnly: { type: "boolean", default: false }, since: { type: "string" }, limit: { type: "integer", default: 100 } }`. (BP instances): `{ configurationName: { type: "string" }, sessionId: { type: "string" }, primaryRequestId: { type: "string" }, completedFilter: { type: "string", enum: ["all", "completed", "in_progress"] } }`.
- Output schema: standard query envelope plus link fields.
- Timeout: 10 seconds. RequiresConfirmation: false.

### get_io_archive

- Description: Read I/O archive for hosts that have `Archive IO` enabled. Useful for diagnosing wire-level adapter issues.
- Implementation: SQL against `Ens.Util.IOLog` and the four subclass tables (`IOLogFile`, `IOLogObj`, `IOLogStream`, `IOLogXMLObj`).
- Input schema: `{ hostName: { type: "string" }, since: { type: "string" }, ioType: { type: "string", enum: ["any","File","Obj","Stream","XMLObj"] }, limit: { type: "integer", default: 50 } }`.
- Timeout: 10 seconds. RequiresConfirmation: false.

### get_interface_maps / find_interface_references

- Description (maps): Returns all unique routes a message can take through the production (Service → Process → Rule → Transformation → Operation), per the Interface Maps utility. Each row is one path. Useful for "which BS calls which BO via which rule".
- Description (references): Find all places a named component (BPL, business rule, DTL, HL7 schema, lookup table, utility function) is referenced. Search inside business host configs, BPL diagrams, DTLs, business rules.
- Implementation: ObjectScript via the Interface Maps / Interface References page APIs.
- Input schema (maps): `{ productionName: { type: "string" }, search: { type: "string" }, componentTypes: { type: "array", items: "string", default: ["service","process","rule","transformation","operation"] }, categoryFilter: { type: "string" }, exportFormat: { type: "string", enum: ["json","csv","xml","html"], default: "json" } }`.
- Input schema (references): `{ componentName: { type: "string", required: true }, componentType: { type: "string", enum: ["bpl","rule","dtl","hl7_schema","lookup_table","utility_function"], required: true }, resultTypes: { type: "array", items: "string", default: ["business_hosts","bpl","rules","dtls"] } }`.
- Timeout: 15 seconds. RequiresConfirmation: false.

### list_workflow_roles / list_workflow_users / list_workflow_tasks

- Description: View workflow role definitions, user assignments, and task statuses (Unassigned/Assigned/Completed/Cancelled/Discarded). Status colors per Managing_Productions.
- Implementation: SQL + ObjectScript via the workflow APIs.
- Input schema (tasks): `{ status: { type: "string", enum: ["any","unassigned","assigned","completed","cancelled","discarded"] }, role: { type: "string" }, assignedTo: { type: "string" }, since: { type: "string" }, limit: { type: "integer", default: 100 } }`.
- Output schema: standard query envelope.
- Timeout: 5 seconds. RequiresConfirmation: false.

### assign_workflow_task / cancel_workflow_task

- Description: Supervisor actions on workflow tasks. Reassign or cancel. Cannot be undone.
- Implementation: ObjectScript via the workflow Manager APIs.
- Input schema (assign): `{ taskId: { type: "string", required: true }, assignToUsername: { type: "string", required: true }, priority: { type: "integer" }, subject: { type: "string" } }`.
- Input schema (cancel): `{ taskId: { type: "string", required: true } }`.
- Timeout: 5 seconds. RequiresConfirmation: TRUE.

### list_subscribers / create_subscription / delete_subscription

- Description: Manage publish/subscribe routing. Topics use `A.B.C.D` form (max 50 chars per subtopic) with `*` wildcard for full subtopics.
- Implementation: ObjectScript via `EnsLib.PubSub.Utils`.
- Input schema (create): `{ subscriberId: { type: "string", required: true }, topic: { type: "string", required: true }, domain: { type: "string" } }`.
- Timeout: 5 seconds. RequiresConfirmation: TRUE for create/delete.

### get_alert_management_state / acknowledge_managed_alert / escalate_managed_alert

- Description: Managed alert framework operations — view current alert assignments, acknowledge, escalate. Backed by `Ens.Alerting.AlertManager`, `Ens.Alerting.NotificationManager`, `Ens.Alerting.AlertMonitor`.
- Implementation: ObjectScript via `Ens.Alerting.ManagedAlert` API.
- Input schema (state): `{ assignedTo: { type: "string" }, status: { type: "string", enum: ["open","ack","escalated","resolved"] }, since: { type: "string" }, limit: { type: "integer", default: 50 } }`.
- Input schema (ack/escalate): `{ alertId: { type: "string", required: true }, note: { type: "string" }, escalateTo: { type: "string", description: "Required for escalate" } }`.
- Timeout: 5 seconds. RequiresConfirmation: TRUE for ack and escalate.

### resend_message / discard_message / resubmit_with_edits

- Description: Operator actions on individual messages. Resend creates a new header (new message ID) targeting the original or a different destination. Discard marks a queued/suspended message as Discarded (does not delete). Resubmit re-runs through the original business host with edited body.
- Implementation: ObjectScript via the Message Viewer's underlying APIs.
- Input schema: `{ messageId: { type: "string", required: true }, newTarget: { type: "string", description: "For resend; default = original target" }, editedBody: { type: "object", description: "For resubmit_with_edits" } }`.
- Required permissions: `%Ens_MessageResend:USE` for resend, `%Ens_MessageDiscard:USE` for discard, `%Ens_MessageEditResend:USE` for resubmit.
- Timeout: 30 seconds. RequiresConfirmation: TRUE for all three.

---

## ToolSet.Transform  [BATCH 2 + BATCH 3 — DTL + BPL + Business/Routing Rules]

DTL CRUD plus dry-run testing. Source PDF: Developing_DTL_Transformations.

### list_dtls

- Description: List all DTL transformations in the current namespace, distinguishing DTL transformations (extend `Ens.DataTransformDTL`, editable in DTL Editor) from custom transformations (extend `Ens.DataTransform`, IDE-only).
- Implementation: SQL against `%Dictionary.ClassDefinition` filtering by `Super = 'Ens.DataTransformDTL'` or `Ens.DataTransform`.
- Input schema: `{ packagePrefix: { type: "string" } }`.
- Output schema: `{ dtls: [ { name, kind: "dtl"|"custom", sourceClass, targetClass, sourceDocType, targetDocType, description, lastCompiled, isCompiled } ] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### get_dtl

- Description: Return a DTL class's full XData transform block + transformation settings (Mode, Report Errors, Treat empty repeating fields as null, Allow empty segments in target, Language).
- Implementation: ObjectScript reading `%Dictionary.XDataDefinition`.
- Input schema: `{ name: { type: "string", required: true } }`.
- Output schema: `{ name, sourceClass, targetClass, sourceDocType, targetDocType, mode, reportErrors, treatEmptyRepeatingAsNull, allowEmptySegmentsInTarget, language, pythonImports, xdataXml, actions: [ { type, attributes, comment, language } ] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### create_dtl

- Description: Scaffold a new DTL class extending `Ens.DataTransformDTL` with the specified source and target classes. Refuses to use reserved package names (Demo, Ens, EnsLib, EnsPortal, CSPX). Optionally pre-populates with `<assign>` actions for matching property names.
- Implementation: ObjectScript class generation + `$system.OBJ.Compile()`.
- Input schema: `{ packageName: { type: "string", required: true }, name: { type: "string", required: true }, description: { type: "string" }, sourceClass: { type: "string", required: true, description: "Use EnsLib.HL7.Message for HL7, EnsLib.EDI.X12.Document for X12, EnsLib.EDI.ASTM.Document for ASTM, EnsLib.EDI.EDIFACT.Document for EDIFACT, EnsLib.EDI.XML.Document for XML, or any custom message class" }, sourceDocType: { type: "string", description: "Required if sourceClass is a virtual document" }, targetClass: { type: "string", required: true }, targetDocType: { type: "string" }, mode: { type: "string", enum: ["new","copy","existing"], default: "new" }, language: { type: "string", enum: ["objectscript","python"], default: "objectscript" }, autoMapMatchingFields: { type: "boolean", default: false } }`.
- Output schema: `{ name, created: true, isCompiled }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE (creates a class).

### update_dtl_body / update_dtl_settings

- Description (body): Replace the XData transform block with a new validated XML body. Refuses XML that doesn't parse as a `<transform>` element with valid action children. Refuses elements/attributes outside the documented set.
- Description (settings): Update transformation-level settings (mode, language, reportErrors, etc.) without touching the body.
- Implementation: ObjectScript editing the class XData via `%Dictionary.XDataDefinition` then recompiling.
- Input schema (body): `{ name: { type: "string", required: true }, transformXml: { type: "string", required: true }, autoCompile: { type: "boolean", default: true } }`.
- Output schema: `{ updated: true, compileErrors: [...] }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE.

### delete_dtl

- Description: Delete a DTL class. Refuses if the DTL is referenced anywhere — checks via the Interface References pattern.
- Implementation: ObjectScript via `$system.OBJ.Delete()` after reference check.
- Input schema: `{ name: { type: "string", required: true }, force: { type: "boolean", default: false, description: "Override the reference check — destructive" } }`.
- Output schema: `{ deleted: true, references: [...] }`.
- Timeout: 15 seconds. RequiresConfirmation: TRUE.

### compile_dtl

- Description: Compile the DTL class. Returns errors if any.
- Implementation: `$system.OBJ.Compile(name, "ck")`.
- Input schema: `{ name: { type: "string", required: true } }`.
- Output schema: `{ ok, errors: [ { line, message } ], warnings: [...] }`.
- Timeout: 30 seconds. RequiresConfirmation: false (compilation is idempotent).

### validate_dtl

- Description: Static analysis of a DTL: checks for missing assignments to required target properties, references to non-existent source/target properties, untranslated TODO comments in `<annotation>`, `<code>` blocks that take locks without releasing them, `<sql>` queries without fully-qualified table names, `<assign action='clear|append|insert'/>` on virtual documents (invalid), missing `BuildMap()` after virtual-document REMOVE actions.
- Implementation: ObjectScript walking the parsed transform XML against the source/target class metadata.
- Input schema: `{ name: { type: "string", required: true } }`.
- Output schema: `{ findings: [ { severity: "error"|"warning"|"info", actionIndex, message, suggestion } ] }`.
- Timeout: 10 seconds. RequiresConfirmation: false.

### run_dtl

- Description: Dry-run the DTL with a sample source message. Returns the transformed target plus any traces and errors. Equivalent to the Test Transform wizard.
- Implementation: ObjectScript invoking `Transform()` on the DTL class with the sample message instantiated.
- Input schema: `{ name: { type: "string", required: true }, sourceMessage: { type: "object", description: "Object form for standard messages, raw text for EDI/virtual documents" }, sourceFormat: { type: "string", enum: ["object","raw"], default: "object" }, aux: { type: "object", description: "aux variable contents (for DTLs that read aux.BusinessRuleName etc.)" } }`.
- Output schema: `{ ok, target: { object or raw text }, traces: [ "..." ], status, executionTimeMs }`.
- Timeout: 30 seconds. RequiresConfirmation: false (dry-run, no side effects).

### list_lookup_tables / read_lookup_table / set_lookup_entry / delete_lookup_entry

- Description: Manage lookup tables used by `Lookup()` / `Exists()` utility functions in DTL and business rules. Stored in `^Ens.LookupTable`.
- Implementation: ObjectScript via `Ens.Util.LookupTable` API.
- Input schema (read): `{ tableName: { type: "string", required: true }, key: { type: "string", description: "Optional — return single entry instead of full table" } }`.
- Input schema (set): `{ tableName: { type: "string", required: true }, key: { type: "string", required: true }, value: { type: "string", required: true } }`.
- Input schema (delete): `{ tableName: { type: "string", required: true }, key: { type: "string", required: true } }`.
- Timeout: 5 seconds. RequiresConfirmation: TRUE for set/delete.

### import_lookup_table / export_lookup_table

- Description: Import/export lookup tables in the new XML format (with `<Document name="X.LUT">` wrapper). Note legacy format support: legacy files import via `import_lookup_table_legacy` (merges with existing rather than replaces).
- Implementation: ObjectScript via `$system.OBJ.Load()` / `$system.OBJ.Export()` for the LUT global subscript.
- Input schema (import): `{ filePath: { type: "string", required: true }, replaceExisting: { type: "boolean", default: false } }`.
- Input schema (export): `{ tableName: { type: "string", required: true }, filePath: { type: "string", required: true } }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE for import.

### list_bpl_processes / get_bpl

- Description (list): All `Ens.BusinessProcessBPL` subclasses in the namespace. Distinguishes regular BPLs from Component BPLs (`Component=true` on `<process>`).
- Description (get): Full BPL XData block + parsed activity tree + `<context>` properties + `<process>` request/response classes.
- Implementation: SQL against `%Dictionary.ClassDefinition` filtered on `Super = 'Ens.BusinessProcessBPL'` + ObjectScript for XData parsing.
- Input schema (list): `{ packagePrefix: { type: "string" } }`. (get): `{ name: { type: "string", required: true } }`.
- Output schema (get): `{ name, requestClass, responseClass, contextSuperClass, isComponent, language, contextProperties: [ { name, type, initialExpression } ], xdataXml, activities: [ { type, name, attributes, children } ], compileErrors: [...] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### create_bpl

- Description: Scaffold a new BPL class extending `Ens.BusinessProcessBPL` with empty `<process>` containing `<sequence>`. Optionally pre-populates `<context>` properties.
- Implementation: ObjectScript class generation + `$system.OBJ.Compile()`.
- Input schema: `{ packageName: { type: "string", required: true }, name: { type: "string", required: true }, requestClass: { type: "string", required: true }, responseClass: { type: "string", required: true }, contextSuperClass: { type: "string", description: "Optional shared context base" }, contextProperties: { type: "array", items: { type: "object", properties: { name: { type: "string" }, type: { type: "string" }, initialExpression: { type: "string" } } } }, language: { type: "string", enum: ["objectscript","python"], default: "objectscript" }, isComponent: { type: "boolean", default: false } }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE.

### update_bpl_body

- Description: Replace the XData BPL block with new validated XML. Validates that root element is `<process>`, that all activities are documented elements, that indirection (`@`) appears only on the four allowed attribute slots (call name, call target, sync calls, transform class), and that fault strings inside `<throw>` are properly nested-quoted.
- Implementation: ObjectScript edit + recompile.
- Input schema: `{ name: { type: "string", required: true }, processXml: { type: "string", required: true }, autoCompile: { type: "boolean", default: true } }`.
- Output schema: `{ updated, compileErrors: [...] }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE.

### delete_bpl / compile_bpl / validate_bpl

- Description (delete): Delete a BPL class. Checks references first (Interface References pattern).
- Description (compile): Compile + return errors.
- Description (validate): Static analysis. Checks: undeclared `context` property references, unmatched `<call>` names in `<sync calls=...>`, missing `<faulthandlers>` for likely-faulting `<call>` chains, locks/transactions opened in `<code>` without release in same block, `Pool Size = 0` BPL on a critical path (FIFO trap), `<throw>` fault expression not double-quoted.
- Implementation: ObjectScript via `$system.OBJ.Delete()`, `$system.OBJ.Compile()`, custom static analyzer.
- Input schema: `{ name: { type: "string", required: true }, force: { type: "boolean", default: false } }`.
- Timeout: 15–30 seconds. RequiresConfirmation: TRUE for delete.

### list_business_rules / get_business_rule

- Description: List `Ens.Rule.Definition` subclasses + their context, production binding, rule sets count, last modified. Get returns the full `<ruleDefinition>` XData.
- Implementation: SQL + XData parsing.
- Input schema (list): `{ packagePrefix: { type: "string" }, contextClass: { type: "string", description: "Filter by ruleDefinition context" } }`.
- Output schema (get): `{ name, alias, contextClass, production, ruleSets: [ { name, effectiveBegin, effectiveEnd, rules: [ { name, disabled, constraints: [...], whens: [ { condition, actions: [...] } ], otherwise: [...] } ] } ] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### create_routing_rule / create_general_rule

- Description: Scaffold a new `Ens.Rule.Definition` class. Routing rule uses context `EnsLib.MsgRouter.RoutingEngine` (or `EnsLib.MsgRouter.VDocRoutingEngine` for HL7/X12/etc.). General rule uses the BPL's `.Context` companion class. Both create one empty `<ruleSet>` with one empty `<rule>`.
- Implementation: ObjectScript class generation + `$system.OBJ.Compile()`.
- Input schema (routing): `{ packageName: { type: "string", required: true }, name: { type: "string", required: true }, alias: { type: "string" }, routerType: { type: "string", enum: ["EnsLib.MsgRouter.RoutingEngine","EnsLib.MsgRouter.VDocRoutingEngine","EnsLib.HL7.MsgRouter.RoutingEngine","EnsLib.EDI.X12.MsgRouter.RoutingEngine","EnsLib.EDI.EDIFACT.MsgRouter.RoutingEngine"], default: "EnsLib.MsgRouter.RoutingEngine" }, productionName: { type: "string" }, ruleAssistClass: { type: "string", description: "Defaults to EnsLib.MsgRouter.RuleAssist" } }`.
- Input schema (general): `{ packageName: { type: "string", required: true }, name: { type: "string", required: true }, contextClass: { type: "string", required: true } }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE.

### update_rule_body / delete_rule / compile_rule

- Description: Same shape as DTL/BPL — replace XData, delete (with reference check), compile + return errors.
- Implementation: ObjectScript class edit / `$system.OBJ.Delete` / Compile.
- Input schema (update): `{ name: { type: "string", required: true }, ruleDefinitionXml: { type: "string", required: true }, autoCompile: { type: "boolean", default: true } }`.
- Timeout: 15–30 seconds. RequiresConfirmation: TRUE for update/delete.

### evaluate_rule

- Description: Dry-run a routing or general rule against a sample message. Returns which constraint matched, which `<when>`/`<otherwise>` fired, and what the rule would have done. Equivalent to the Test button in the Rule Editor — does NOT actually send messages.
- Implementation: ObjectScript via `Ens.Rule.Definition.Evaluate()` with the `Test` flag.
- Input schema: `{ ruleName: { type: "string", required: true }, sampleSource: { type: "string", description: "Config name for the source constraint" }, messageInput: { type: "string", description: "Raw HL7/X12 text or JSON for object messages" }, messageInputKind: { type: "string", enum: ["raw","object","headerId","bodyId"], default: "raw" }, contextOverrides: { type: "object", description: "Override context properties for the test" } }`.
- Output schema: `{ ruleSetName, ruleName, constraintMatched, branchFired: "when_n" | "otherwise" | "none", reason, returnValue, sendActions: [ { transform, target } ], traces: [...] }`.
- Required permissions: `%Ens_RuleLog:USE`, `%Ens_TestingService:USE`, SQL SELECT on `Ens_Rule.log` and `Ens_Rule.DebugLog`.
- Timeout: 15 seconds. RequiresConfirmation: false.

### enable_rule / disable_rule

- Description: Toggle the `disabled` attribute on a specific `<rule>` inside a rule definition. Use during incident response to silence a misbehaving rule without removing it.
- Implementation: ObjectScript edit of the XData + recompile.
- Input schema: `{ ruleDefinitionName: { type: "string", required: true }, ruleName: { type: "string", required: true } }`.
- Timeout: 10 seconds. RequiresConfirmation: TRUE.

### list_rule_assist_classes

- Description: Return available `Ens.Rule.Assist` subclasses for the routerType selection. Some message routers ship their own assist class (e.g. `EnsLib.HL7.MsgRouter.RuleAssist`) that adds HL7-specific helpers in the editor.
- Implementation: SQL against `%Dictionary.ClassDefinition` for subclasses of `Ens.Rule.Assist`.
- Input schema: `{}`.
- Timeout: 3 seconds. RequiresConfirmation: false.

---

## ToolSet.ESB  [BATCH 3 — service registry]

Tools for the ESB pattern (Public + External Service Registry). Source PDF: Using_a_Production_as_an_ESB. Routes through ToolSet.Production at the agent level.

### list_registered_services / get_registered_service

- Description: Query the Public Service Registry — services the ESB exposes to clients. Returns name, alias, endpoint, protocol, message format, schema, status, version, namespace, owner, contact, description, attached files. Identical shape to the public REST API at `GET /v1/services`.
- Implementation: ObjectScript via `EnsLib.ServiceRegistry.Public.API`-equivalent calls (or SQL against the registry table).
- Input schema (list): `{ selector: { type: "object", description: "name, protocol, status, namespace filters" }, limit: { type: "integer", default: 50 } }`. (get): `{ id: { type: "string", required: true } }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### register_service / update_service / unregister_service

- Description: CRUD on the Public Service Registry. Registering a service exposes it to clients via the public REST API.
- Implementation: ObjectScript via `EnsLib.ServiceRegistry.Public.*` API.
- Input schema (register): `{ name: { type: "string", required: true }, alias: { type: "string" }, endpoint: { type: "string", required: true }, protocol: { type: "string", enum: ["REST","SOAP","HTTP","HL7","FHIR","TCP","File","FTP"] }, messageFormat: { type: "string" }, schema: { type: "string" }, version: { type: "string" }, namespace: { type: "string" }, owner: { type: "string" }, contact: { type: "string" }, description: { type: "string" }, files: { type: "array", items: "string", description: "Paths to WSDLs/schemas to attach" }, status: { type: "string", enum: ["Active","Inactive"], default: "Active" }, customFields: { type: "object" } }`.
- Required permission: `%Ens_ESB_Administrator:USE` (or `%EnsRole_ESBAdministrator` role).
- Timeout: 15 seconds. RequiresConfirmation: TRUE.

### list_external_services / get_external_service / register_external_service

- Description: External Service Registry — services the ESB CONSUMES on behalf of clients. Same shape as Public Service Registry, used by ESB hosts at runtime to resolve "logical service alias → actual endpoint".
- Implementation: ObjectScript via `EnsLib.ServiceRegistry.External.*` API.
- Input schema: same as Public Registry.
- Timeout: 5–15 seconds. RequiresConfirmation: TRUE for register.

### lookup_service_by_alias

- Description: Runtime lookup — given a logical alias from the External Service Registry, return the current endpoint + protocol + auth config. Used by ESB hosts (and tools) to avoid hardcoding target host names.
- Implementation: ObjectScript via `EnsLib.ServiceRegistry.External.Resolve(alias)`.
- Input schema: `{ alias: { type: "string", required: true } }`.
- Output schema: `{ alias, endpoint, protocol, version, status }`.
- Timeout: 3 seconds. RequiresConfirmation: false.

---

## ToolSet.Testing  [BATCH 4]

Tools for sending and validating HL7 v2, FHIR R4, SDA, DICOM messages, plus generic REST testing. Source PDFs: Using_REST_Services_and_Operations_in_Productions, Using_Virtual_Documents_in_Productions, Routing_DICOM_Documents_in_Productions, Enabling_Productions_to_Use_Managed_File_Transfer_Services. Operations are sandbox-isolated by default.

### ensure_test_production / list_test_productions

- Description: Identify or create a sandboxed test production for safe `send_*` operations. The agent never sends test traffic into a customer's running production by default — it routes into a per-namespace test production with file-based services/operations (the live/test toggle pattern from Best_Practices).
- Implementation: ObjectScript: scan productions for ones tagged `Category=test` or with name suffix `_TestProduction`; if none exists, scaffold one with empty config.
- Input schema (ensure): `{ namespace: { type: "string", description: "Default = current namespace" } }`.
- Output schema: `{ productionName, exists, isRunning }`.
- Timeout: 10 seconds. RequiresConfirmation: TRUE (creates a class).

### send_hl7

- Description: Send an HL7 v2 message into a target service. Default target is the test production's `EnsLib.HL7.Service.File` (file drop). For wire testing, allow `targetType: "tcp"` to use `EnsLib.HL7.Service.TCPService` with explicit confirmation. Returns the resulting Ens.MessageHeader id so the agent can call `get_message_trace` to inspect the flow.
- Implementation: ObjectScript: instantiate `EnsLib.HL7.Message` from raw text, call the target service's `OnProcessInput` (file mode) or actually deliver via MLLP (TCP mode).
- Input schema: `{ message: { type: "string", required: true, description: "Raw HL7 v2 text" }, targetService: { type: "string", description: "Defaults to the test production's HL7 file service" }, targetType: { type: "string", enum: ["file","tcp"], default: "file" }, schemaCategory: { type: "string", description: "e.g. 2.5" } }`.
- Output schema: `{ ok, messageId, sessionId, deliveredTo }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE for `targetType=tcp`; false for file (sandboxed).

### send_fhir

- Description: Send a FHIR R4 resource or bundle to an endpoint. Default target is the IRIS FHIR Server's REST endpoint (`/csp/healthshare/{ns}/fhir/r4/...`). Supports POST (create), PUT (update), DELETE, and bundle (transaction/batch) submissions.
- Implementation: ObjectScript via `%Net.HttpRequest` against the local FHIR Server endpoint; or via `HS.FHIRServer.Interop.Service` if testing through a production.
- Input schema: `{ resource: { type: "object", description: "FHIR resource or Bundle as JSON" }, method: { type: "string", enum: ["POST","PUT","DELETE","GET"], default: "POST" }, resourceType: { type: "string" }, resourceId: { type: "string" }, endpoint: { type: "string", description: "Default = local FHIR Server" } }`.
- Output schema: `{ ok, statusCode, locationHeader, responseBody }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE for non-default endpoint.

### send_sda

- Description: Send an SDA3 container into a target SDA-receiving service. Used in HealthShare-style workflows.
- Implementation: ObjectScript: build `HS.SDA3.Container` from JSON or XML, send via `HS.Gateway.SDA3.SDA3Operation` or directly into a test process.
- Input schema: `{ container: { type: "object", description: "SDA3 container as JSON or XML" }, format: { type: "string", enum: ["json","xml"], default: "json" }, targetService: { type: "string" } }`.
- Output schema: `{ ok, messageId }`.
- Timeout: 30 seconds. RequiresConfirmation: TRUE.

### send_dicom

- Description: Send a DICOM message (typically a C-STORE) over TCP to a `EnsLib.DICOM.Service.TCP` host, or read a DICOM file through `EnsLib.DICOM.Service.File`. Requires negotiated association context.
- Implementation: ObjectScript via `EnsLib.DICOM.File` to load + the operation's send method.
- Input schema: `{ filePath: { type: "string" }, dicomContent: { type: "string" }, targetService: { type: "string", required: true }, associationContext: { type: "string", description: "AssociationContext class name; default = test production's standard context" } }`.
- Output schema: `{ ok, messageId, ackStatus }`.
- Timeout: 60 seconds. RequiresConfirmation: TRUE.

### send_mft_file / list_mft_folder / download_mft_file

- Description: Send a file to an MFT service (Box / Dropbox / Kiteworks), list a remote folder, or download a file. Useful for end-to-end MFT-pass-through testing.
- Implementation: ObjectScript via `%MFT.Box`, `%MFT.Dropbox`, `%MFT.Kiteworks` API.
- Input schema (send): `{ provider: { type: "string", enum: ["Box","Dropbox","Kiteworks"], required: true }, mftConnectionName: { type: "string", required: true }, localFilePath: { type: "string", required: true }, remoteFolder: { type: "string", required: true }, remoteFilename: { type: "string" } }`.
- Input schema (list): `{ provider, mftConnectionName, remoteFolder }`.
- Input schema (download): `{ provider, mftConnectionName, remoteFolder, remoteFilename, localDestination }`.
- Output schema: depends on operation.
- Timeout: 60 seconds for send/download, 15 for list. RequiresConfirmation: TRUE for send/download.

### validate_hl7_structure

- Description: Validate an HL7 v2 message against its declared schema (e.g., `2.5:ADT_A01`). Reports missing required segments, fields, or datatypes. No side effects.
- Implementation: ObjectScript: instantiate `EnsLib.HL7.Message`, check `BuildMapStatus`, then call validation per the host's `Validation` setting flags (`d`, `m`, `s` etc.).
- Input schema: `{ message: { type: "string", required: true }, schemaCategory: { type: "string", description: "e.g. 2.5; auto-detect from MSH-12 if omitted" }, docType: { type: "string", description: "e.g. ADT_A01; auto-detect from MSH-9 if omitted" }, validationFlags: { type: "string", default: "dms" } }`.
- Output schema: `{ ok, valid, buildMapStatus, errors: [ { segment, field, code, message } ] }`.
- Timeout: 10 seconds. RequiresConfirmation: false.

### validate_hl7_semantics

- Description: Beyond structure, run profile-based semantic checks (e.g., MRN must be 7 digits, MessageType must be in a whitelist, sender facility must match a lookup table). Driven by an optional rule set.
- Implementation: ObjectScript: invoke a per-profile `Ens.Rule.Definition` against the parsed message.
- Input schema: `{ message: { type: "string", required: true }, profile: { type: "string", description: "Name of validation rule definition class" } }`.
- Output schema: `{ ok, valid, ruleHits: [ { ruleName, severity, message } ] }`.
- Timeout: 15 seconds. RequiresConfirmation: false.

### validate_fhir_resource

- Description: Run `$validate` on a FHIR R4 resource. Checks against the resource's profile (or a custom profile if supplied). Returns OperationOutcome with issues.
- Implementation: ObjectScript: POST to `/fhir/r4/{ResourceType}/$validate` on the local FHIR Server, OR call `HS.FHIRServer.Util.Validator` directly.
- Input schema: `{ resource: { type: "object", required: true }, profile: { type: "string", description: "Custom profile URL" } }`.
- Output schema: `{ ok, valid, issues: [ { severity, code, diagnostics, location } ] }`.
- Timeout: 15 seconds. RequiresConfirmation: false.

### compare_messages

- Description: Diff two messages of the same type. For HL7 / X12 / EDIFACT: segment-level diff. For FHIR: JSON diff. For SDA: per-entry diff. Used to verify a DTL produces the expected output.
- Implementation: ObjectScript: parse both, walk virtual property paths or JSON paths.
- Input schema: `{ messageA: { type: "string", required: true }, messageB: { type: "string", required: true }, format: { type: "string", enum: ["hl7","x12","edifact","fhir","sda","auto"], default: "auto" } }`.
- Output schema: `{ identical, differences: [ { path, valueA, valueB } ] }`.
- Timeout: 10 seconds. RequiresConfirmation: false.

### test_rest_endpoint

- Description: Send a generic HTTP request (GET/POST/PUT/DELETE) to an external REST endpoint via the production's HTTP outbound adapter pattern. Useful for testing the network path before wiring up a `EnsLib.REST.Operation`.
- Implementation: ObjectScript via `%Net.HttpRequest` configured per the input.
- Input schema: `{ method: { type: "string", enum: ["GET","POST","PUT","DELETE","PATCH"], required: true }, url: { type: "string", required: true }, headers: { type: "object" }, body: { type: "string" }, contentType: { type: "string", default: "application/json" }, expectedStatusCodes: { type: "array", items: "integer" } }`.
- Output schema: `{ ok, statusCode, headers, body, elapsedMs }`.
- Timeout: 60 seconds. RequiresConfirmation: TRUE for non-GET methods.

### get_test_message_samples

- Description: Return curated sample messages for HL7 v2 (ADT_A01, ORM_O01, ORU_R01, MDM_T02, etc.), FHIR R4 (Patient, Observation, Bundle), SDA3 (Container with Patient + Encounter + Observation), DICOM. Useful when the user asks for a quick test message without writing one from scratch.
- Implementation: SQL against `AgenticInterop_Catalog.TestSamples` (seeded by Catalog.HsBuilder per the catalog plan).
- Input schema: `{ format: { type: "string", enum: ["hl7","fhir","sda","dicom"], required: true }, messageType: { type: "string", description: "ADT_A01, Patient, etc." } }`.
- Output schema: `{ samples: [ { name, message, description, source } ] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### get_iris_fhir_capability_statement

- Description: Return the local FHIR Server's CapabilityStatement. Useful for "what FHIR operations does this server support" / "is `$everything` enabled" queries.
- Implementation: ObjectScript via GET `/fhir/r4/metadata`.
- Input schema: `{ endpoint: { type: "string", description: "Default = local FHIR Server" } }`.
- Output schema: `{ ok, capabilityStatement: { ... } }`.
- Timeout: 10 seconds. RequiresConfirmation: false.

---

## ToolSet.Production extensions  [BATCH 4 — DICOM + MFT + Virtual Documents helpers]

These extend the Production toolset with batch 4 specifics. They live alongside the existing Production tools.

### list_dicom_associations / get_dicom_association / create_dicom_association

- Description: Manage DICOM associations (`EnsLib.DICOM.Util.AssociationContext` rows). Each association declares one or more presentation contexts (abstract syntax + transfer syntax pairs).
- Implementation: ObjectScript via `EnsLib.DICOM.Util.AssociationContext.ImportAssociation()` / programmatic creation.
- Input schema (create): `{ name: { type: "string", required: true }, presentationContexts: { type: "array", items: { type: "object", properties: { abstractSyntax: { type: "string" }, transferSyntaxes: { type: "array", items: "string" } } } } }`.
- Output schema: `{ ok, associationName }`.
- Timeout: 10 seconds. RequiresConfirmation: TRUE for create.

### list_mft_connections / register_mft_connection

- Description: View / create the OAuth 2.0 client configurations IRIS uses to talk to Box / Dropbox / Kiteworks. These are referenced by `MFTConnectionName` on MFT business hosts.
- Implementation: ObjectScript via `%SYS.MFT.Connection.{Box,Dropbox,Kiteworks}` API.
- Input schema (register): `{ provider: { type: "string", enum: ["Box","Dropbox","Kiteworks"], required: true }, name: { type: "string", required: true }, clientId: { type: "string", required: true }, clientSecret: { type: "string", required: true, description: "Stored in IRIS Secured Wallet" }, redirectUri: { type: "string" } }`.
- Output schema: `{ ok, connectionName }`.
- Timeout: 10 seconds. RequiresConfirmation: TRUE.

### list_search_tables / get_search_table_indexes / rebuild_search_table_index

- Description: View virtual-document search tables (`EnsLib.HL7.SearchTable`, `EnsLib.EDI.X12.SearchTable`, custom subclasses). Rebuild indexes when the search table definition changes (the framework re-indexes incoming messages but historical messages need explicit rebuild).
- Implementation: ObjectScript via `Ens.SearchTableBase.Rebuild*()` methods.
- Input schema (rebuild): `{ searchTableClass: { type: "string", required: true }, range: { type: "object", properties: { from: { type: "string" }, to: { type: "string" } }, description: "Time range to rebuild; default = all" } }`.
- Output schema: `{ ok, recordsRebuilt, durationMs }`.
- Timeout: 600 seconds. RequiresConfirmation: TRUE.

### list_schema_categories / get_schema_structure / import_custom_schema

- Description: View loaded HL7 / X12 / EDIFACT / ASTM / XML schema categories. Get a specific document structure within a category. Import a custom schema XML.
- Implementation: ObjectScript via `EnsLib.HL7.Schema`, `EnsLib.EDI.X12.Schema`, etc.
- Input schema (get structure): `{ category: { type: "string", required: true, description: "e.g. 2.5 or MyApp:2.5" }, docType: { type: "string", required: true, description: "e.g. ADT_A01" }, format: { type: "string", enum: ["hl7","x12","edifact","astm","xml"], default: "hl7" } }`.
- Input schema (import): `{ schemaXml: { type: "string", required: true }, format: { type: "string", required: true } }`.
- Timeout: 5–30 seconds. RequiresConfirmation: TRUE for import.

---

## ToolSet.Reference  [BATCH 5 — error / CPF / API discovery]

Reference utilities sourced from Configuration_Parameter_File_Reference.pdf, Detailed_API_Index.pdf, InterSystems_Error_Reference.pdf, InterSystems_Glossary_of_Terms.pdf. These are exposed at the main agent level (cross-cutting), not behind a Skill, because every Skill benefits from them.

### lookup_error_code

- Description: Look up an InterSystems error code (`<Ens>ErrXxx`, `<%SYS>YyyError`, numeric system codes 5000-5999, etc.) and return its catalog entry: code, domain, formal description, and the substitution placeholders. Use whenever the chatbot has an opaque `%Status` and the user asks "what does this mean?".
- Implementation: SQL against `AgenticInterop_Catalog.ErrorReference` (a vector table seeded by Catalog.HsBuilder from InterSystems_Error_Reference.pdf). Falls back to `$system.Status.GetErrorCodes()` + `$system.Status.GetOneStatusText()` for runtime status objects.
- Input schema: `{ errorCode: { type: "string", required: true, description: "e.g. <Ens>ErrFailureTimeout, ErrProductionAlreadyRunning, 5002, %Status XML serialization" }, includeSimilar: { type: "boolean", default: false, description: "Return up to 5 similar error codes by name fuzzy match" } }`.
- Output schema: `{ code, domain, description, placeholders: [ "%1", "%2" ], examplesOfPlaceholders: { "%1": "Production name", ... }, category: "Production lifecycle | Connections | DTL | BPL | EDI | HL7 | X12 | Workflow | XPath | System", commonCauses: [...], remediation: [...], similarErrors: [...] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### explain_status

- Description: Decode a serialized `%Status` (the XML-shaped string IRIS returns from any failed call). Returns the chain of error codes + their descriptions + a suggested next action. Better than lookup_error_code when the user pastes a raw status — handles nested errors.
- Implementation: ObjectScript via `$system.Status.GetErrorCodes()`, `$system.Status.GetErrorTexts()`, `$system.Status.DisplayError()` then enrichment from the local error catalog.
- Input schema: `{ statusXml: { type: "string", required: true } }`.
- Output schema: `{ codes: [ "code1", "code2" ], texts: [ "...", "..." ], rootCauseSuggestion: "...", relatedSkills: [ "skill.productions", "skill.dtl" ] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### get_cpf_parameter

- Description: Read a CPF parameter from the running IRIS instance. Read-only; safe. Use for "what's the EnsembleAutoStart setting?" or "what namespaces are interop-enabled?".
- Implementation: ObjectScript via the `Config.*` API package — `Config.Startup.Get()`, `Config.Namespaces.Get()`, `Config.Map.Get()`, etc., or directly `^%SYS("CONFIG", section, key)`.
- Input schema: `{ section: { type: "string", required: true, description: "[Startup], [Namespaces], [config], [Map], [Journal], [Logging], [SQL], [Monitor], etc." }, key: { type: "string", description: "Parameter name; omit to list all keys in the section" } }`.
- Output schema: `{ section, key, value, defaultValue, description, validRange }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

### list_cpf_sections

- Description: List all CPF sections in the current iris.cpf with their key counts. Useful for navigation when the user doesn't know which section a parameter lives in.
- Implementation: ObjectScript via `Config.*` discovery.
- Input schema: `{}`.
- Output schema: `{ sections: [ { name, keyCount, description } ] }`.
- Timeout: 3 seconds. RequiresConfirmation: false.

### set_cpf_parameter

- Description: WRITE a CPF parameter. Almost all CPF changes require IRIS restart, and many affect more than just interoperability. The chatbot REFUSES this without explicit user confirmation including "yes I understand a restart may be required".
- Implementation: ObjectScript via the `Config.*` API package's `Modify()` methods. Triggers `^%SYS("CONFIG"...)` updates and writes back to iris.cpf.
- Input schema: `{ section: { type: "string", required: true }, key: { type: "string", required: true }, value: { type: "string", required: true }, restartConfirmed: { type: "boolean", required: true, description: "User must confirm awareness that IRIS may need restart" } }`.
- Output schema: `{ ok, oldValue, newValue, restartRequired, restartReason }`.
- Required permissions: `%Admin_Manage:USE`, `%Admin_Operate:USE`.
- Timeout: 15 seconds. RequiresConfirmation: TRUE (always).

### search_api_index

- Description: Search the curated InterSystems API Index (Tools/APIs by topic). Returns matching topics with their available tools, classes, and pointers to the relevant skill section. Better than raw `describe_class` when the user asks "how do I work with X" — surfaces the conceptual entry point.
- Implementation: SQL against `AgenticInterop_Catalog.ApiIndex` (vector table seeded from Detailed_API_Index.pdf). Topics include: HL7 Messages, FHIR Resources, SDA Documents, X12, EDIFACT, ASTM, DICOM, MFT, JSON, JMS, Kafka, RabbitMQ, MQTT, MQ, Cloud Storage, Email, FTP, HTTP, LDAP, SAP, Siebel, SOAP, SQL, TCP/IP, Telnet, Pipe, CDA Documents, Healthcare Data, IHE, Productions, Tasks, Auditing, Encryption, TLS, X.509 Certificates, Security Items, Web Gateway, Namespaces, Globals, Routines, Classes, Files, Directories, Locks, Memory, Processes, CPUs, Servers, Versions, Locales, Date/Time, Macros, Includes, Regular Expressions, GUIDs, IP Addresses, URLs, MIME, Python, OS Commands, etc.
- Input schema: `{ query: { type: "string", required: true }, limit: { type: "integer", default: 5 } }`.
- Output schema: `{ hits: [ { topic, description, availableTools: [...], availableClasses: [...], relevantSkill, score } ] }`.
- Timeout: 10 seconds. RequiresConfirmation: false.

### lookup_glossary_term

- Description: Look up an InterSystems-specific term from the official Glossary. Use when the user mentions a term and the chatbot wants to confirm precise meaning before answering. Authoritative for terms like CPF, OREF, OID, Row ID, primary persistent superclass, principal device, KDC, etc.
- Implementation: SQL against `AgenticInterop_Catalog.Glossary` (vector table seeded from InterSystems_Glossary_of_Terms.pdf).
- Input schema: `{ term: { type: "string", required: true }, fuzzyMatch: { type: "boolean", default: true, description: "Allow approximate matching" } }`.
- Output schema: `{ term, category: "Objects | InterSystems SQL | System | ObjectScript | UNIX | Java | Network | etc.", definition, relatedTerms: [...] }`.
- Timeout: 5 seconds. RequiresConfirmation: false.

---

## ToolSet.Monitoring  [BATCH 6 — production diagnostics]

Read-only tools for querying production event logs, message headers, error summaries, and queue depths. Source class: `AgenticInterop.Tool.Monitoring`. All tools execute SQL against `Ens.Util.Log` and `Ens.MessageHeader` in the active namespace.

### QueryEventLog

- Description: Query the Ens.Util.Log (Event Log) for recent errors, warnings, or info entries. Call this when the user asks about errors, warnings, event log, "what went wrong", "why is my message failing", or any production troubleshooting question.
- Implementation: SQL against `Ens_Util.Log`.
- Body: parameterised query with type filter (mapped to numeric Type column: 1=error, 2=warning, 3=info, 4=trace, 5=assert), time window, optional configName filter. Returns up to `maxRows` entries ordered by TimeLogged DESC.
- Input schema: `{ type: { type: "string", enum: ["error","warning","info","trace","assert","all"], default: "error" }, hours: { type: "integer", default: 2, minimum: 1, maximum: 168 }, configName: { type: "string", description: "Optional business host name filter (exact match)" }, maxRows: { type: "integer", default: 50, minimum: 1, maximum: 200 } }`.
- Output schema: `{ ok, namespace, type, hours, rows: [ { id, timeLogged, type, configName, sourceConfigName, text, sessionId, job } ], total, truncated }`.
- Timeout: 10 seconds.
- RequiresConfirmation: false (read-only).

### TopErrors

- Description: Get the top N most frequent errors from Ens.Util.Log grouped by business host and error text. Call this when the user asks "top errors", "most common failures", "error summary", or "group errors by host".
- Implementation: SQL against `Ens_Util.Log` with GROUP BY ConfigName, Text and COUNT(*).
- Body: filters to Type=1 (error), groups by ConfigName + Text, orders by count descending.
- Input schema: `{ hours: { type: "integer", default: 2, minimum: 1, maximum: 168 }, topN: { type: "integer", default: 10, minimum: 1, maximum: 50 } }`.
- Output schema: `{ ok, namespace, hours, groups: [ { configName, text, count, firstSeen, lastSeen } ], totalErrors }`.
- Timeout: 10 seconds.
- RequiresConfirmation: false (read-only).

### QueryMessageStatus

- Description: Query Ens.MessageHeader for messages in a specific status. Call this when the user asks about "stuck messages", "suspended messages", "errored messages", "message status", "what messages failed", or message-level troubleshooting.
- Implementation: SQL against `Ens.MessageHeader`.
- Body: parameterised query filtering by Status and time window. Returns up to `maxRows` headers ordered by TimeCreated DESC.
- Input schema: `{ status: { type: "string", enum: ["Error","Suspended","Deferred","Queued","all"], default: "Error" }, hours: { type: "integer", default: 2, minimum: 1, maximum: 168 }, maxRows: { type: "integer", default: 50, minimum: 1, maximum: 200 } }`.
- Output schema: `{ ok, namespace, status, hours, rows: [ { id, timeCreated, status, sourceConfigName, targetConfigName, sourceBusinessType, targetBusinessType, messageBodyClassName, isError, errorStatus, sessionId, priority } ], total, truncated }`.
- Timeout: 10 seconds.
- RequiresConfirmation: false (read-only).

### MessageSummary

- Description: Summarize message counts by status and business host for the given time window. Call this for "message summary", "how many messages processed", "production throughput", "message volume", or dashboard-style overview queries.
- Implementation: SQL against `Ens.MessageHeader` (two queries: one grouped by Status, one grouped by TargetConfigName with Completed/Errored/Total breakdown).
- Input schema: `{ hours: { type: "integer", default: 2, minimum: 1, maximum: 168 } }`.
- Output schema: `{ ok, namespace, hours, byStatus: [ { status, count } ], byHost: [ { configName, completed, errored, total } ], grandTotal }`.
- Timeout: 10 seconds.
- RequiresConfirmation: false (read-only).

### QueueStatus

- Description: Check queue depths for all active business hosts. Call this when the user asks "are queues backing up", "queue depth", "is anything stuck", or production health checks.
- Implementation: SQL against `Ens.MessageHeader` filtering Status='Queued', grouped by TargetConfigName.
- Input schema: `{}` (no inputs; namespace comes from request).
- Output schema: `{ ok, namespace, queues: [ { configName, count } ], totalQueued }`.
- Timeout: 5 seconds.
- RequiresConfirmation: false (read-only).
