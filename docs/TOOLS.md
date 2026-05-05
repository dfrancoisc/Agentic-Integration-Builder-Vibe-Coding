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

## ToolSet.Testing  [PENDING — batch 4]
