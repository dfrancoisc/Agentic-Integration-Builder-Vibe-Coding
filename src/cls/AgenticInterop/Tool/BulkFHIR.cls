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
            Set out.notes = "This is the PROGRAMMATIC (nested) config that HS.BulkFHIR.Installer consumes via CreateOrUpdateBFCConfig — NOT the flattened format the FHIR Management UI 'Import JSON' uses. Structure: top level = name, endpoint_url (RELATIVE, unique, e.g. /bulkFHIR/r4a), auto_start, authorized_users[], core_fhir_package, is_inactive, plus three adapter+config pairs. auth_adapter+auth_config = how export CLIENTS authenticate TO the BFC (Auth.BasicAuth.Adapter with {} | Auth.OAuth.Adapter with {bfc_client_name, clients:[{name, authentication_method: client_secret_post|private_key_jwt}], introspect}). fetch_adapter+fetch_config = how BFC pulls FROM the source: fetch_config.endpoint_url = SOURCE FHIR endpoint; patient_export/group_export/system_export, resource_types, http_timeout (default 180), max_req_per_sec, worker_jobs, working_directory, flush_interval_mins all live INSIDE fetch_config; and fetch_config.client_auth_adapter+client_auth_config = how BFC authenticates to the source (ClientAuth.BasicAuth=http_credential_id+ssl_configuration | ClientAuth.OAuth/SMARTBackendService=ssl_configuration+client_name+grant_type+fetch_token_scopes+fetch_token_credential_id+audience_property | ClientAuth.XAPIKey=ssl_configuration+x_api_key_credential_id). storage_adapter+storage_config = Storage.File (directory, file_url, expire_after_mins default 1440, max_file_size default 1000000) for ndjson OR Storage.Ingestion (fhir_endpoint = TARGET FHIR server, integrity_check, failed_files_directory, file_url) for direct ingest. Provide nested objects matching each chosen adapter's config class fields above."
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
/// This is the PROGRAMMATIC nested envelope (what HS.BulkFHIR.Installer
/// consumes) — NOT the flattened format the FHIR Management UI "Import JSON"
/// screen uses. patient_export/group_export/system_export, resource_types,
/// and client_auth_* live INSIDE fetch_config; expire_after_mins/
/// max_file_size live inside storage_config.
///
/// config: the BFC config envelope (object or JSON string), e.g.
///   {
///     "name": "dsfranco-pull",
///     "endpoint_url": "/bulkfhir/r4",
///     "auto_start": true,
///     "core_fhir_package": "hl7.fhir.r4.core@4.0.1",
///     "auth_adapter": "HS.BulkFHIR.Auth.BasicAuth.Adapter",
///     "auth_config": {},
///     "fetch_adapter": "HS.BulkFHIR.Fetch.PureFHIR.Adapter",
///     "fetch_config": { "endpoint_url": "<SOURCE FHIR endpoint>",
///        "resource_types": ["Patient","Observation"],
///        "patient_export": true, "system_export": true,
///        "http_timeout": 180, "worker_jobs": 4,
///        "client_auth_adapter": "HS.BulkFHIR.ClientAuth.BasicAuth.Adapter",
///        "client_auth_config": { "ssl_configuration": "<SSL>",
///           "http_credential_id": "<credentialId>" } },
///     "storage_adapter": "HS.BulkFHIR.Storage.Ingestion.Adapter",
///     "storage_config": { "fhir_endpoint": "<TARGET FHIR endpoint>",
///        "integrity_check": true }
///   }
/// (For ndjson output instead of ingestion, use storage_adapter
/// "HS.BulkFHIR.Storage.File.Adapter" with storage_config
/// { "directory": "<server path>", "file_url": "/file",
///   "expire_after_mins": 1440, "max_file_size": 1000000 }.)
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

/// Create or update an Interoperability credential (username/password) so
/// BFC can authenticate to a source FHIR server, or so export clients can
/// authenticate to BFC with Basic auth. Idempotent (overwrites). MUTATING
/// (ensure_ — treated as create). Requires the logged-in user to have
/// rights to manage Ens credentials; otherwise reports the security error.
/// The password is never echoed back.
///
/// credentialId: the credential id to reference from a BFC config
///               (fetch_config.client_auth_config.http_credential_id).
/// username / password: the Basic-auth username and password.
/// namespace: optional target namespace (credentials are namespace-scoped).
///
/// Returns: { ok, credentialId, namespace, message, error? }.
ClassMethod EnsureInteropCredential(credentialId As %String, username As %String, password As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("EnsureInteropCredential")
    Set out = {}
    Set out.tool = "ensure_interop_credential"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.credentialId = $get(credentialId)
    If ($get(credentialId) = "") || ($get(username) = "") {
        Set out.ok = 0
        Set out.error = "Pass `credentialId` and `username` (and `password`)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureInteropCredential", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } Else {
            Set sc = ##class(Ens.Config.Credentials).SetCredential(credentialId, username, $get(password), 1)
            Set scErr = ..%SCErr(sc)
            If scErr '= "" {
                Set out.ok = 0
                Set out.error = scErr
            } Else {
                Set out.ok = 1
                Set out.message = "Credential '" _ credentialId _ "' set in " _ targetNs _ ". Reference it from a BFC config as client_auth_config.http_credential_id."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureInteropCredential", out)
    Quit out
}

/// Ensure a server-side directory exists for BFC File (ndjson) output.
/// Idempotent. MUTATING (ensure_).
///
/// path: absolute server path (created with parents if missing).
///
/// Returns: { ok, path, existed, message, error? }.
ClassMethod EnsureStorageDirectory(path As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("EnsureStorageDirectory")
    Set out = {}
    Set out.tool = "ensure_storage_directory"
    Set out.path = $get(path)
    If $get(path) = "" {
        Set out.ok = 0
        Set out.error = "Pass `path` (server-side directory)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureStorageDirectory", out)
        Quit out
    }
    Try {
        If ##class(%Library.File).DirectoryExists(path) {
            Set out.ok = 1
            Set out.existed = 1
            Set out.message = "Directory already exists: " _ path
        } Else {
            If ##class(%Library.File).CreateDirectoryChain(path) {
                Set out.ok = 1
                Set out.existed = 0
                Set out.message = "Created directory: " _ path
            } Else {
                Set out.ok = 0
                Set out.error = "Failed to create directory: " _ path _ " (check filesystem permissions)."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureStorageDirectory", out)
    Quit out
}

/// Ensure an SSL/TLS configuration exists (a client config for HTTPS to a
/// secured source FHIR server). Idempotent. MUTATING (ensure_). Operates
/// in %SYS; requires the logged-in user to have %Admin_Secure; otherwise
/// reports the security error. Reference the name from a BFC config as
/// client_auth_config.ssl_configuration.
///
/// name: the SSL config name.
///
/// Returns: { ok, name, existed, message, error? }.
ClassMethod EnsureSSLConfig(name As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("EnsureSSLConfig")
    Set out = {}
    Set out.tool = "ensure_ssl_config"
    Set dispNs = $namespace
    Set out.name = $get(name)
    If $get(name) = "" {
        Set out.ok = 0
        Set out.error = "Pass `name` (SSL config name)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureSSLConfig", out)
        Quit out
    }
    New $namespace
    Try {
        Set $namespace = "%SYS"
        If ##class(Security.SSLConfigs).Exists(name) {
            Set out.ok = 1
            Set out.existed = 1
            Set out.message = "SSL config '" _ name _ "' already exists."
        } Else {
            Kill props
            Set props("Enabled") = 1
            Set sc = ##class(Security.SSLConfigs).Create(name, .props)
            Set scErr = ..%SCErr(sc)
            If scErr '= "" {
                Set out.ok = 0
                Set out.error = scErr
            } Else {
                Set out.ok = 1
                Set out.existed = 0
                Set out.message = "SSL config '" _ name _ "' created (client TLS defaults). Reference it from a BFC config as client_auth_config.ssl_configuration."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureSSLConfig", out)
    Quit out
}

/// Ensure the SMART Backend Services OAuth setup for BFC: configure the
/// internal OAuth server if absent, and (when clientName + issuerUrl are
/// supplied) create the OAuth client BFC uses to authenticate to the
/// source. Idempotent. MUTATING (ensure_). Requires %Admin_Secure on the
/// logged-in user; otherwise reports the security error.
///
/// clientName: optional OAuth client to create (BFC fetch client).
/// issuerUrl:  the OAuth server issuer URL (required to create a client).
/// grantType:  default "client_credentials" (SMART backend services).
/// namespace:  optional target namespace.
///
/// Returns: { ok, serverReady, serverCreated?, clientCreated?, issuerUrl?, message, error? }.
ClassMethod EnsureBFCOAuth(clientName As %String = "", issuerUrl As %String = "", grantType As %String = "client_credentials", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("EnsureBFCOAuth")
    Set out = {}
    Set out.tool = "ensure_bfc_oauth"
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
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.HC.OAuth2.Server.Installer") {
            Set out.ok = 0
            Set out.error = "OAuth server installer not available in namespace " _ targetNs _ "."
        } Else {
            Set exists = 0
            Try { Set exists = ##class(HS.HC.OAuth2.Server.Installer).DoesOAuthServerExist() } Catch  {}
            If 'exists {
                Set sc = ##class(HS.HC.OAuth2.Server.Installer).ConfigureInternalOAuthServer(0)
                Set scErr = ..%SCErr(sc)
                If scErr '= "" {
                    Set out.ok = 0
                    Set out.error = "Configure internal OAuth server failed: " _ scErr
                    Set out.serverReady = 0
                }
                Set out.serverCreated = 'out.%IsDefined("ok")
            }
            If 'out.%IsDefined("ok") {
                Set out.serverReady = ''##class(HS.HC.OAuth2.Server.Installer).DoesOAuthServerExist()
                If ($get(clientName) '= "") {
                    If $get(issuerUrl) = "" {
                        Set out.ok = 1
                        Set out.clientCreated = 0
                        Set out.message = "OAuth server ready. Pass `issuerUrl` to create the OAuth client '" _ clientName _ "' (SMART backend services)."
                    } Else {
                        Set out.issuerUrl = issuerUrl
                        Set created = ""
                        Set sc2 = ##class(HS.BulkFHIR.Installer).AutoCreateOAuthClient(clientName, issuerUrl, $listbuild(grantType), "", "BFC fetch client", .created)
                        Set scErr2 = ..%SCErr(sc2)
                        If scErr2 '= "" {
                            Set out.ok = 0
                            Set out.clientCreated = 0
                            Set out.error = "AutoCreateOAuthClient failed: " _ scErr2
                        } Else {
                            Set out.ok = 1
                            Set out.clientCreated = 1
                            Set out.message = "OAuth server ready and client '" _ clientName _ "' created. Reference it from a BFC config (client_auth_config.client_name)."
                        }
                    }
                } Else {
                    Set out.ok = 1
                    Set out.message = "OAuth server " _ $select(out.serverReady:"ready", 1:"NOT ready") _ ". Pass clientName + issuerUrl to also create the BFC OAuth client."
                }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureBFCOAuth", out)
    Quit out
}

/// Delete a Bulk FHIR Coordinator configuration (and the web app/endpoint
/// it generated). MUTATING (delete_ prefix) and DESTRUCTIVE — confirm with
/// the user first. Backed by HS.BulkFHIR.Installer.Delete, which takes the
/// config NAME; this tool also accepts the endpoint_url and resolves it to
/// the name. Requires the %HS_BFC_Administrator role.
///
/// nameOrEndpoint: the config Name OR its endpoint_url.
/// namespace: optional target namespace.
///
/// Returns: { ok, name, namespace, message, error? }.
ClassMethod DeleteBFCConfig(nameOrEndpoint As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("DeleteBFCConfig")
    Set out = {}
    Set out.tool = "delete_bfc_config"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    If $get(nameOrEndpoint) = "" {
        Set out.ok = 0
        Set out.error = "Pass `nameOrEndpoint` (the BFC config name or endpoint_url)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteBFCConfig", out)
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
            ; Installer.Delete takes the config Name; resolve from name or endpoint.
            Set cfgName = nameOrEndpoint
            Set found = 0
            Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM HS_BulkFHIR.Configuration WHERE Name = ? OR BFCEndpoint = ?", nameOrEndpoint, nameOrEndpoint)
            If rs.%Next() { Set cfgName = rs.%Get("Name"), found = 1 }
            Set out.name = cfgName
            If 'found {
                Set out.ok = 0
                Set out.error = "No BFC config named or endpointed '" _ nameOrEndpoint _ "' in namespace " _ targetNs _ "."
            } Else {
                Set sc = ##class(HS.BulkFHIR.Installer).Delete(cfgName)
                Set scErr = ..%SCErr(sc)
                If scErr '= "" {
                    Set out.ok = 0
                    Set out.error = scErr
                } Else {
                    Set out.ok = 1
                    Set out.message = "Deleted BFC config '" _ cfgName _ "' in " _ targetNs _ "."
                }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteBFCConfig", out)
    Quit out
}

/// Activate or deactivate a BFC configuration (the home page Active toggle).
/// An INACTIVE config cannot run exports and rejects all export requests.
/// Use this to ACTIVATE a config that was saved INACTIVE after you fixed a
/// missing prerequisite, or to take a config offline. MUTATING (set_ prefix);
/// deactivating is disruptive, so confirm first. Activating re-runs the full
/// configure (HS.BulkFHIR.Installer.ConfigureConfigElseSaveInactive), so the
/// prerequisites must be in place; if it still cannot configure, the config
/// stays INACTIVE and that is reported.
///
/// endpoint:  the BFC endpoint_url (or config name).
/// active:    1 to activate (default), 0 to deactivate.
/// namespace: optional target namespace.
///
/// Returns: { ok, endpoint, active, savedInactive, message, error? }.
ClassMethod SetBFCConfigActive(endpoint As %String, active As %Boolean = 1, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("SetBFCConfigActive")
    Set out = {}
    Set out.tool = "set_bfc_config_active"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.endpoint = $get(endpoint)
    If $get(endpoint) = "" {
        Set out.ok = 0
        Set out.error = "Pass `endpoint` (the BFC endpoint_url or config name)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("SetBFCConfigActive", out)
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
            Set cfgObj = ##class(HS.BulkFHIR.Configuration).GetConfiguration(endpoint)
            If '$isobject(cfgObj) {
                Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT BFCEndpoint FROM HS_BulkFHIR.Configuration WHERE Name = ?", endpoint)
                If rs.%Next() { Set cfgObj = ##class(HS.BulkFHIR.Configuration).GetConfiguration(rs.%Get("BFCEndpoint")) }
            }
            If ('$isobject(cfgObj)) || ('$isobject(cfgObj.Configuration)) {
                Set out.ok = 0
                Set out.error = "No BFC config for '" _ endpoint _ "' in namespace " _ targetNs _ "."
            } Else {
                Set env = cfgObj.Configuration
                Set env."is_inactive" = ''(active = 0)
                Set savedInactive = 0
                Set sc = ##class(HS.BulkFHIR.Installer).ConfigureConfigElseSaveInactive(env, .savedInactive)
                Set scErr = ..%SCErr(sc)
                If scErr '= "" {
                    Set out.ok = 0
                    Set out.error = scErr
                } Else {
                    Set out.savedInactive = ''savedInactive
                    Set out.active = ('savedInactive) && (active '= 0)
                    If active = 0 {
                        Set out.message = "BFC config '" _ endpoint _ "' deactivated."
                    } ElseIf savedInactive {
                        Set out.message = "Activation attempted but the config saved INACTIVE — a prerequisite is still missing or the source/target FHIR server is unreachable. Fix it and retry."
                    } Else {
                        Set out.message = "BFC config '" _ endpoint _ "' is now active."
                    }
                    Set out.ok = 1
                }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("SetBFCConfigActive", out)
    Quit out
}

}
