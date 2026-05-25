/// %AI.Tool source for the Bulk FHIR Coordinator (BFC) — list, inspect,
/// create/configure, start, and monitor BFC configurations and exports.
/// Each public ClassMethod is auto-discovered by the %AI framework as a
/// tool. Composed into AgenticInterop.ToolSet.BulkFHIR.
///
/// WHAT BFC ACTUALLY DOES (do not let the model invent otherwise): a BFC
/// configuration FETCHES FHIR resources FROM a source FHIR endpoint (via
/// a fetch adapter — native $export, or $everything) and writes them to a
/// STORAGE adapter: either an "Output File Server" (ndjson files) or a
/// "FHIR Repository" (INGESTS into a target FHIR server). The source is
/// always a FHIR ENDPOINT, never a folder of files. To load a directory
/// of FHIR files into a server, that is the FHIR DataLoader
/// (AgenticInterop.Tool.FHIRServer.LoadFHIRData), NOT BFC.
///
/// Backed by HS.BulkFHIR.Installer (ConfigureConfigElseSaveInactive,
/// Export), HS.BulkFHIR.Configuration (stored configs), and
/// HS.BulkFHIR.ExportManager / HS.BulkFHIR.Session (export runs).
/// Requires the %HS_BFC_Administrator role for create/configure/start.
///
/// Namespace-safe like AgenticInterop.Tool.FHIRServer: ToolStart/ToolDone
/// run in the dispatch namespace; HS.BulkFHIR.* calls run in the target
/// namespace, restored before ToolDone.
Class AgenticInterop.Tool.BulkFHIR Extends %AI.Tool
{

/// X-IRIS-Namespace the chat surface attached, or the dispatch namespace. Internal.
ClassMethod %TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// Honor an explicit namespace arg, else the chat-scoped namespace. Internal.
ClassMethod %ResolveNs(namespace As %String = "") As %String [ Internal ]
{
    If $get(namespace) '= "" { Quit namespace }
    Quit ..%TargetNs()
}

/// Render a value that might be a %Status into error text, else "". Internal.
ClassMethod %SCErr(sc) As %String [ Internal ]
{
    If $get(sc) = "" { Quit "" }
    If sc = 1 { Quit "" }
    Set t = ""
    Try { If $system.Status.IsError(sc) { Set t = $extract($system.Status.GetErrorText(sc), 1, 500) } } Catch  {}
    Quit t
}

/// Non-% property names of a class as a %DynamicArray of {name,type}. Internal.
ClassMethod %ClassProps(pClass As %String) As %DynamicArray [ Internal ]
{
    Set arr = []
    Try {
        Set co = ##class(%Dictionary.CompiledClass).%OpenId(pClass)
        If $isobject(co) {
            For i=1:1:co.Properties.Count() {
                Set p = co.Properties.GetAt(i)
                If $extract(p.Name) = "%" { Continue }
                Set o = {}
                Set o.name = p.Name
                Set o.type = p.Type
                Do arr.%Push(o)
            }
        }
    } Catch  {}
    Quit arr
}

/// List the Bulk FHIR Coordinator configurations in a namespace. CALL
/// THIS to answer "what BFC configs exist", "list bulk FHIR endpoints".
/// Read-only.
///
/// namespace: optional target namespace (a FHIR-enabled foundation namespace).
///
/// Returns: { ok, namespace, configs:[{name, endpoint, fetchAdapter,
/// storageAdapter, inactive}], total }.
ClassMethod ListBFCConfigs(namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListBFCConfigs")
    Set out = {}
    Set out.tool = "list_bfc_configs"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.configs = []
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.BulkFHIR.Configuration") {
            Set out.ok = 1
            Set out.total = 0
            Set out.message = "Bulk FHIR Coordinator is not available in namespace " _ targetNs _ " (HS.BulkFHIR not mapped)."
        } Else {
            Set count = 0
            Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, BFCEndpoint FROM HS_BulkFHIR.Configuration ORDER BY Name")
            While rs.%Next() {
                Set c = {}
                Set c.name = rs.%Get("Name")
                Set c.endpoint = rs.%Get("BFCEndpoint")
                ; Pull adapter summary from the stored config envelope.
                Try {
                    Set cfgObj = ##class(HS.BulkFHIR.Configuration).GetConfiguration(c.endpoint)
                    If $isobject(cfgObj), $isobject(cfgObj.Configuration) {
                        Set env = cfgObj.Configuration
                        Set c.fetchAdapter = $select(env.%IsDefined("fetch_adapter"):env.fetch_adapter, 1:"")
                        Set c.storageAdapter = $select(env.%IsDefined("storage_adapter"):env.storage_adapter, 1:"")
                        Set c.inactive = $select(env.%IsDefined("is_inactive"):''env.is_inactive, 1:"")
                    }
                } Catch  {}
                Do out.configs.%Push(c)
                Set count = count + 1
            }
            Set out.total = count
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListBFCConfigs", out)
    Quit out
}

/// Get one BFC configuration's full envelope (fetch source, storage,
/// auth, flags). CALL THIS to inspect or before editing a config.
/// Read-only.
///
/// endpoint:  the BFC endpoint_url (e.g. "/bulkfhir/r4"); also accepts
///            the config name.
/// namespace: optional target namespace.
///
/// Returns: { ok, namespace, endpoint, found, config?(object) }.
ClassMethod GetBFCConfig(endpoint As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetBFCConfig")
    Set out = {}
    Set out.tool = "get_bfc_config"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.endpoint = $get(endpoint)
    If $get(endpoint) = "" {
        Set out.ok = 0
        Set out.error = "Pass `endpoint` (the BFC endpoint_url or config name)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetBFCConfig", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.BulkFHIR.Configuration") {
            Set out.ok = 0
            Set out.error = "Bulk FHIR Coordinator is not available in namespace " _ targetNs _ "."
        } Else {
            Set cfgObj = ##class(HS.BulkFHIR.Configuration).GetConfiguration(endpoint)
            If '$isobject(cfgObj) {
                ; Fall back: resolve endpoint by config Name via SQL.
                Set ep = ""
                Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT BFCEndpoint FROM HS_BulkFHIR.Configuration WHERE Name = ?", endpoint)
                If rs.%Next() { Set ep = rs.%Get("BFCEndpoint") }
                If ep '= "" { Set cfgObj = ##class(HS.BulkFHIR.Configuration).GetConfiguration(ep) }
            }
            If '$isobject(cfgObj) {
                Set out.ok = 1
                Set out.found = 0
                Set out.error = "No BFC config for '" _ endpoint _ "' in namespace " _ targetNs _ "."
            } Else {
                Set out.found = 1
                If $isobject(cfgObj.Configuration) { Set out.config = cfgObj.Configuration }
                Set out.ok = 1
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetBFCConfig", out)
    Quit out
}

/// Return the live schema for building a BFC configuration: the top-level
/// envelope fields, the available fetch / storage / client-auth / auth
/// adapter classes, and each adapter config's fields (introspected from
/// the running instance). CALL THIS BEFORE CreateOrUpdateBFCConfig so the
/// config you build is valid. Read-only.
///
/// namespace: optional target namespace.
///
/// Returns: { ok, envelope:[...], fetchAdapters:[{adapter, configClass,
/// fields}], storageAdapters:[...], clientAuthAdapters:[...],
/// authAdapters:[...], notes }.
ClassMethod GetBFCConfigSchema(namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetBFCConfigSchema")
    Set out = {}
    Set out.tool = "get_bfc_config_schema"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.BulkFHIR.API.Data.Config") {
            Set out.ok = 0
            Set out.error = "Bulk FHIR Coordinator is not available in namespace " _ targetNs _ "."
        } Else {
            Set out.envelope = ..%ClassProps("HS.BulkFHIR.API.Data.Config")
            ; fetch adapters: adapter class -> config class
            Set out.fetchAdapters = []
            Set fa("HS.BulkFHIR.Fetch.BulkFHIR.Adapter") = "HS.BulkFHIR.Fetch.BulkFHIR.Config"
            Set fa("HS.BulkFHIR.Fetch.PureFHIR.Adapter") = "HS.BulkFHIR.Fetch.PureFHIR.Config"
            Set fa("HS.BulkFHIR.Fetch.ODS.Adapter") = "HS.BulkFHIR.Fetch.ODS.Config"
            Set k = $order(fa(""))
            While k '= "" {
                Set e = {}
                Set e.adapter = k
                Set e.configClass = fa(k)
                Set e.fields = ..%ClassProps(fa(k))
                Do out.fetchAdapters.%Push(e)
                Set k = $order(fa(k))
            }
            ; storage adapters
            Set out.storageAdapters = []
            Set sa("HS.BulkFHIR.Storage.File.Adapter") = "HS.BulkFHIR.Storage.File.Config"
            Set sa("HS.BulkFHIR.Storage.Ingestion.Adapter") = "HS.BulkFHIR.Storage.Ingestion.Config"
            Set k = $order(sa(""))
            While k '= "" {
                Set e = {}
                Set e.adapter = k
                Set e.configClass = sa(k)
                Set e.fields = ..%ClassProps(sa(k))
                Do out.storageAdapters.%Push(e)
                Set k = $order(sa(k))
            }
            ; client-auth adapters (how BFC authenticates to the SOURCE)
            Set out.clientAuthAdapters = []
            Set ca("HS.BulkFHIR.ClientAuth.OAuth.Adapter") = "HS.BulkFHIR.ClientAuth.OAuth.Config"
            Set ca("HS.BulkFHIR.ClientAuth.BasicAuth.Adapter") = "HS.BulkFHIR.ClientAuth.BasicAuth.Config"
            Set ca("HS.BulkFHIR.ClientAuth.SMARTBackendService.Adapter") = "HS.BulkFHIR.ClientAuth.SMARTBackendService.Config"
            Set ca("HS.BulkFHIR.ClientAuth.XAPIKey.Adapter") = "HS.BulkFHIR.ClientAuth.XAPIKey.Config"
            Set k = $order(ca(""))
            While k '= "" {
                Set e = {}
                Set e.adapter = k
                Set e.configClass = ca(k)
                Set e.fields = ..%ClassProps(ca(k))
                Do out.clientAuthAdapters.%Push(e)
                Set k = $order(ca(k))
            }
            ; auth adapters (how export CLIENTS authenticate to the BFC endpoint)
            Set out.authAdapters = []
            Set au("HS.BulkFHIR.Auth.OAuth.Adapter") = "HS.BulkFHIR.Auth.OAuth.Config"
            Set au("HS.BulkFHIR.Auth.BasicAuth.Adapter") = "HS.BulkFHIR.Auth.BasicAuth.Config"
            Set k = $order(au(""))
            While k '= "" {
                Set e = {}
                Set e.adapter = k
                Set e.configClass = au(k)
                Set e.fields = ..%ClassProps(au(k))
                Do out.authAdapters.%Push(e)
                Set k = $order(au(k))
            }
            Set out.notes = "fetch_config.endpoint_url is the SOURCE FHIR endpoint to pull from. storage = File (ndjson output) OR Ingestion (storage_config.fhir_endpoint = TARGET FHIR server to ingest into). auth_* = how export clients authenticate to the BFC endpoint; fetch_config.client_auth_* = how BFC authenticates to the source. Provide nested objects matching each chosen adapter's config class fields."
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetBFCConfigSchema", out)
    Quit out
}

/// Create or update a Bulk FHIR Coordinator configuration. MUTATING
/// (create_ prefix). Pass the full config envelope; the server validates
/// it and either activates it or saves it INACTIVE if it cannot be fully
/// configured yet (e.g. the source/target FHIR server is unreachable).
/// Call GetBFCConfigSchema first to build a valid config.
///
/// config: the BFC config envelope (object or JSON string), e.g.
///   {
///     "name": "dsfranco-pull",
///     "endpoint_url": "/bulkfhir/r4",
///     "auto_start": true,
///     "auth_adapter": "HS.BulkFHIR.Auth.BasicAuth.Adapter",
///     "auth_config": { ... },
///     "fetch_adapter": "HS.BulkFHIR.Fetch.PureFHIR.Adapter",
///     "fetch_config": { "endpoint_url": "<SOURCE FHIR endpoint>",
///        "client_auth_adapter": "HS.BulkFHIR.ClientAuth.BasicAuth.Adapter",
///        "client_auth_config": { ... }, "system_export": true },
///     "storage_adapter": "HS.BulkFHIR.Storage.Ingestion.Adapter",
///     "storage_config": { "fhir_endpoint": "<TARGET FHIR endpoint>" }
///   }
/// namespace: optional target namespace.
///
/// Returns: { ok, name, endpoint, active, savedInactive, error?, message }.
ClassMethod CreateOrUpdateBFCConfig(config, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("CreateOrUpdateBFCConfig")
    Set out = {}
    Set out.tool = "create_or_update_bfc_config"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    ; Parse the config envelope.
    Set cfg = config
    If '$isobject(cfg) {
        If $get(config) = "" {
            Set out.ok = 0
            Set out.error = "Pass `config` (the BFC config envelope). Call GetBFCConfigSchema first."
            Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateOrUpdateBFCConfig", out)
            Quit out
        }
        Try { Set cfg = ##class(%DynamicAbstractObject).%FromJSON(config) } Catch  { Set cfg = "" }
    }
    If '$isobject(cfg) {
        Set out.ok = 0
        Set out.error = "Invalid `config` JSON."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateOrUpdateBFCConfig", out)
        Quit out
    }
    Set out.name = $select(cfg.%IsDefined("name"):cfg.name, 1:"")
    Set out.endpoint = $select(cfg.%IsDefined("endpoint_url"):cfg.endpoint_url, 1:"")
    If (out.name = "") || (out.endpoint = "") {
        Set out.ok = 0
        Set out.error = "Config must include `name` and `endpoint_url`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateOrUpdateBFCConfig", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.BulkFHIR.Installer") {
            Set out.ok = 0
            Set out.error = "Bulk FHIR Coordinator is not available in namespace " _ targetNs _ "."
        } Else {
            Set savedInactive = 0
            Set sc = $$$OK
            Set sc = ##class(HS.BulkFHIR.Installer).ConfigureConfigElseSaveInactive(cfg, .savedInactive)
            Set scErr = ..%SCErr(sc)
            If scErr '= "" {
                Set out.ok = 0
                Set out.error = scErr
            } Else {
                Set out.ok = 1
                Set out.savedInactive = ''savedInactive
                Set out.active = '''savedInactive
                If savedInactive {
                    Set out.message = "Config '" _ out.name _ "' saved INACTIVE — it could not be fully configured (commonly the source/target FHIR server is unreachable, or a credential/SSL/OAuth prerequisite is missing). Fix the dependency, then re-save."
                } Else {
                    Set out.message = "BFC config '" _ out.name _ "' configured and active at " _ out.endpoint _ "."
                }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 500)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateOrUpdateBFCConfig", out)
    Quit out
}

/// Start a Bulk FHIR export for a configured BFC endpoint. MUTATING
/// (start_ prefix). The config must already exist and be active. BFC
/// fetches from the configured source FHIR endpoint and writes to the
/// configured storage (ndjson files or ingestion into the target server).
///
/// endpoint:  the BFC endpoint_url of an existing active config.
/// namespace: optional target namespace.
///
/// Returns: { ok, endpoint, result?, message?, error? }.
ClassMethod StartBFCExport(endpoint As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("StartBFCExport")
    Set out = {}
    Set out.tool = "start_bfc_export"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.endpoint = $get(endpoint)
    If $get(endpoint) = "" {
        Set out.ok = 0
        Set out.error = "Pass `endpoint` (the BFC endpoint_url of an active config)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("StartBFCExport", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.BulkFHIR.Installer") {
            Set out.ok = 0
            Set out.error = "Bulk FHIR Coordinator is not available in namespace " _ targetNs _ "."
        } Else {
            Set res = ##class(HS.BulkFHIR.Installer).Export(endpoint)
            Set scErr = ..%SCErr(res)
            If scErr '= "" {
                Set out.ok = 0
                Set out.error = scErr
            } Else {
                If $isvalidnum(res) { Set out.result = res }
                ElseIf $isobject(res) { Try { Set out.result = res.%ToJSON() } Catch  {} }
                ElseIf $get(res) '= "", res '= 1 { Set out.result = res }
                Set out.ok = 1
                Set out.message = "Export started for BFC endpoint " _ endpoint _ ". Use ListBFCExports / GetBFCExportStatus to monitor."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 500)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("StartBFCExport", out)
    Quit out
}

/// List recent Bulk FHIR export sessions in a namespace. Read-only.
///
/// namespace: optional target namespace.
///
/// Returns: { ok, namespace, exports:[{id, status, ...}], total }.
ClassMethod ListBFCExports(namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListBFCExports")
    Set out = {}
    Set out.tool = "list_bfc_exports"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.exports = []
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.BulkFHIR.Session") {
            Set out.ok = 1
            Set out.total = 0
            Set out.message = "Bulk FHIR Coordinator is not available in namespace " _ targetNs _ "."
        } Else {
            Set count = 0
            Try {
                Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 25 ID FROM HS_BulkFHIR.Session ORDER BY ID DESC")
                While rs.%Next() {
                    Set e = {}
                    Set e.id = rs.%Get("ID")
                    Try { Set e.status = ##class(HS.BulkFHIR.ExportManager).SessionRunningStatus(e.id) } Catch  {}
                    Do out.exports.%Push(e)
                    Set count = count + 1
                }
            } Catch  {}
            Set out.total = count
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListBFCExports", out)
    Quit out
}

/// Check the running status of a Bulk FHIR export session. Read-only.
///
/// sessionId: the export session id (from ListBFCExports / StartBFCExport).
/// namespace: optional target namespace.
///
/// Returns: { ok, sessionId, status, error? }.
ClassMethod GetBFCExportStatus(sessionId As %Integer, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetBFCExportStatus")
    Set out = {}
    Set out.tool = "get_bfc_export_status"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.sessionId = $get(sessionId)
    If $get(sessionId) = "" {
        Set out.ok = 0
        Set out.error = "Pass `sessionId` (from ListBFCExports)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetBFCExportStatus", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.BulkFHIR.ExportManager") {
            Set out.ok = 0
            Set out.error = "Bulk FHIR Coordinator is not available in namespace " _ targetNs _ "."
        } Else {
            Set out.status = ##class(HS.BulkFHIR.ExportManager).SessionRunningStatus(sessionId)
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetBFCExportStatus", out)
    Quit out
}

}
