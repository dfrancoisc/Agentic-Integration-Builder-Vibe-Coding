/// %AI.Tool source for the FHIR Server toolset — discover, inspect,
/// operate, configure, and (when explicitly asked) provision the FHIR R4
/// server that ships with IRIS for Health / Health Connect foundation
/// namespaces. Each public ClassMethod is auto-discovered by the %AI
/// framework as a tool — the method name is the tool name the LLM sees.
/// Composed into AgenticInterop.ToolSet.FHIRServer via
/// <Include Class="AgenticInterop.Tool.FHIRServer"/> (Pattern 5, ai-hub-tools).
///
/// DESIGN RULE (do not violate): a foundation namespace already HAS the
/// FHIR Server defined. The agent must DISCOVER the existing FHIR-enabled
/// namespace + endpoint first (DiscoverFHIRNamespaces / ListFHIREndpoints)
/// and manage what is already there. Provisioning (CreateFHIREndpoint) is
/// an explicit capability that refuses to touch an endpoint that already
/// exists — it never reinstalls or duplicates a live server.
///
/// Namespace safety: AgenticInterop.* classes are NOT mapped into system
/// foundation namespaces (e.g. the FHIR namespace), so ToolStart/ToolDone
/// run in the dispatch namespace and we switch into the target namespace
/// only around the HS.FHIRServer.* calls, restoring before ToolDone.
///
/// Mutating tools use mutating verb prefixes (Create/Update/Delete/Add/
/// Set) so AgenticInterop.Policy.ConfirmationGate can gate them.
Class AgenticInterop.Tool.FHIRServer Extends %AI.Tool
{

/// Resolve the namespace this tool call targets — the X-IRIS-Namespace
/// header the chat surface attaches, or the dispatch namespace. Internal.
ClassMethod %TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// If an explicit namespace arg was passed, honor it; else fall back to
/// the chat-scoped namespace. Internal.
ClassMethod %ResolveNs(namespace As %String = "") As %String [ Internal ]
{
    If $get(namespace) '= "" { Quit namespace }
    Quit ..%TargetNs()
}

/// Resolve the live FHIR service engine for an endpoint URL in the
/// CURRENT namespace. Returns "" on success (svc set by reference),
/// otherwise a human-readable error string. Internal.
ClassMethod %Service(url As %String, Output svc) As %String [ Internal ]
{
    Set svc = ""
    Set err = ""
    Try {
        If '##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRServer.ServiceAdmin") {
            Set err = "Namespace " _ $namespace _ " is not FHIR-enabled (HS.FHIRServer not available)."
            Quit
        }
        If '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set err = "No FHIR endpoint at '" _ url _ "' in namespace " _ $namespace _ ". Call ListFHIREndpoints / DiscoverFHIRNamespaces first."
            Quit
        }
        ; Documented in-process entry point: EnsureInstance(endpointUrl).
        ; Safe to call before every request; returns the singleton service.
        Set svc = ##class(HS.FHIRServer.Service).EnsureInstance(url)
        If '$isobject(svc) { Set err = "Could not instantiate the FHIR service for endpoint: " _ url }
    } Catch ex {
        Set err = $extract(ex.DisplayString(), 1, 300)
    }
    Quit err
}

/// Execute one FHIR interaction against a local endpoint via the
/// in-process engine (no HTTP, no auth round-trip). Assumes the caller
/// has already switched $namespace to the endpoint's namespace. Returns
/// { ok, httpStatus, resourceType?, body?(object), location?, etag?,
/// resourceId?, error? }. Internal.
ClassMethod %Interaction(url As %String, method As %String, path As %String, query As %String = "", bodyObj = "") As %DynamicObject [ Internal ]
{
    Set r = {}
    Set svc = ""
    Set serr = ..%Service(url, .svc)
    If serr '= "" { Set r.ok = 0 Set r.error = serr Quit r }
    Try {
        Set req = ##class(HS.FHIRServer.API.Data.Request).%New()
        Set req.RequestMethod = $zconvert(method, "U")
        Set req.RequestPath = path
        If $get(query) '= "" { Set req.QueryString = query }
        Set req.RequestFormatCode = "JSON"
        Set req.ResponseFormatCode = "JSON"
        If $isobject(bodyObj) { Set req.Json = bodyObj }
        Do svc.DispatchRequest(req, .resp)
        Set r.httpStatus = +resp.Status
        Set r.ok = ((+resp.Status >= 200) && (+resp.Status < 300))
        If resp.Location '= "" { Set r.location = resp.Location }
        If resp.ETag '= "" { Set r.etag = resp.ETag }
        If resp.Id '= "" { Set r.resourceId = resp.Id }
        If $isobject(resp.Json) {
            Set r.body = resp.Json
            If resp.Json.%IsDefined("resourceType") { Set r.resourceType = resp.Json.resourceType }
        }
    } Catch ex {
        Set r.ok = 0
        Set r.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit r
}

/// Parse a resource argument that may arrive as a %DynamicObject or a
/// JSON string. Uses the class-method %FromJSON form (instance form is
/// broken on this build). Returns the object or "" on failure. Internal.
ClassMethod %ParseResource(resource) As %DynamicObject [ Internal ]
{
    If $isobject(resource) { Quit resource }
    If $get(resource) = "" { Quit "" }
    Set obj = ""
    Try { Set obj = ##class(%DynamicAbstractObject).%FromJSON(resource) } Catch  {}
    Quit obj
}

/// Convert a CSV string or %DynamicArray of package ids into a $LIST.
/// Internal.
ClassMethod %ToList(val) As %List [ Internal ]
{
    Set out = ""
    If $isobject(val) {
        Try {
            Set it = val.%GetIterator()
            While it.%GetNext(.k, .v) { If $get(v) '= "" { Set out = out _ $listbuild(v) } }
        } Catch  {}
        Quit out
    }
    If $get(val) = "" { Quit out }
    For i=1:1:$length(val, ",") {
        Set p = $zstrip($piece(val, ",", i), "<>W")
        If p '= "" { Set out = out _ $listbuild(p) }
    }
    Quit out
}

/// Render a value that might be a %Status into error text, or "" when it
/// is empty / OK / not a status. Internal.
ClassMethod %SCErr(sc) As %String [ Internal ]
{
    If $get(sc) = "" { Quit "" }
    If sc = 1 { Quit "" }
    Set t = ""
    Try { If $system.Status.IsError(sc) { Set t = $extract($system.Status.GetErrorText(sc), 1, 400) } } Catch  {}
    Quit t
}

/// Scan every namespace the user can read and report which are
/// FHIR-enabled foundation namespaces with at least one installed FHIR
/// endpoint. CALL THIS FIRST for any FHIR Server task — it locates the
/// foundation namespace where FHIR is already defined so later tools can
/// target it. Read-only.
///
/// Returns: { ok, namespaces:[{namespace, endpoints:[url], endpointCount}], total, message? }.
ClassMethod DiscoverFHIRNamespaces() As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("DiscoverFHIRNamespaces")
    Set out = {}
    Set out.tool = "discover_fhir_namespaces"
    Set dispNs = $namespace
    Set out.namespaces = []
    New $namespace
    Try {
        Set list = ""
        Do List^%SYS.NAMESPACE(.list)
        Set systemNs = ",%SYS,IRISSYS,IRISTEMP,IRISLIB,IRISLOCALDATA,HSLIB,HSSYS,HSSYSLOCALTEMP,DOCBOOK,ENSLIB,"
        Set count = 0
        Set ns = $order(list(""))
        While ns '= "" {
            If systemNs '[ ("," _ $zconvert(ns, "U") _ ",") {
                Set nsOk = 1
                Try { Set $namespace = ns } Catch  { Set nsOk = 0 }
                If nsOk {
                    Set hasFhir = 0
                    Try { Set hasFhir = ##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRServer.ServiceAdmin") } Catch  {}
                    If hasFhir {
                        Set eps = []
                        Set epList = ""
                        Try { Set epList = ##class(HS.FHIRServer.ServiceAdmin).GetEndpointList() } Catch  {}
                        If $listvalid(epList) {
                            For ei=1:1:$listlength(epList) { Do eps.%Push($list(epList, ei)) }
                        }
                        If eps.%Size() > 0 {
                            Set entry = {}
                            Set entry.namespace = ns
                            Set entry.endpoints = eps
                            Set entry.endpointCount = eps.%Size()
                            Do out.namespaces.%Push(entry)
                            Set count = count + 1
                        }
                    }
                }
                Set $namespace = dispNs
            }
            Set ns = $order(list(ns))
        }
        Set out.total = count
        Set out.ok = 1
        If count = 0 {
            Set out.message = "No FHIR-enabled namespace with an installed endpoint was found. A foundation namespace with a FHIR Server is required; CreateFHIREndpoint can provision one if you have privileges."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("DiscoverFHIRNamespaces", out)
    Quit out
}

/// List the FHIR endpoints installed in a namespace, with each endpoint's
/// enabled state, FHIR version, metadata packages, strategy, and key
/// config. CALL THIS to answer "what FHIR servers / endpoints exist
/// here". Read-only.
///
/// namespace: optional target namespace; defaults to the chat namespace.
///
/// Returns: { ok, namespace, endpoints:[{url, enabled, instanceId,
/// fhirVersion, metadataPackages, strategy, resourceValidation, debugMode}], total, message? }.
ClassMethod ListFHIREndpoints(namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListFHIREndpoints")
    Set out = {}
    Set out.tool = "list_fhir_endpoints"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.endpoints = []
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRServer.ServiceAdmin") {
            Set out.ok = 1
            Set out.total = 0
            Set out.message = "Namespace " _ targetNs _ " is not FHIR-enabled. Use DiscoverFHIRNamespaces to find a foundation namespace."
        } Else {
            Set epList = ##class(HS.FHIRServer.ServiceAdmin).GetEndpointList()
            Set count = 0
            If $listvalid(epList) {
                For ei=1:1:$listlength(epList) {
                    Set u = $list(epList, ei)
                    Set ep = {}
                    Set ep.url = u
                    Try { Set ep.enabled = ''##class(HS.FHIRServer.ServiceAdmin).IsEndpointEnabled(u) } Catch  { Set ep.enabled = "" }
                    Set iid = ""
                    Try { Set iid = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceIdForEndpoint(u) } Catch  {}
                    Set ep.instanceId = iid
                    Try {
                        Set cfg = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceConfigData(iid)
                        If $isobject(cfg) {
                            Set ep.fhirVersion = cfg.FHIRVersion
                            Set ep.metadataPackages = cfg.FHIRMetadataSet
                            Set ep.strategy = cfg.InteractionsStrategyClass
                            Set ep.resourceValidation = cfg.ResourceValidation
                            Set ep.debugMode = cfg.DebugMode
                        }
                    } Catch  {}
                    Do out.endpoints.%Push(ep)
                    Set count = count + 1
                }
            }
            Set out.total = count
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListFHIREndpoints", out)
    Quit out
}

/// Describe one FHIR endpoint in full: enabled state, instance id, and
/// every configurable setting (FHIR version, metadata packages, strategy,
/// debug mode, search page sizes, max results, validation level, prefer
/// handling, session timeout). CALL THIS when the user asks about a
/// specific endpoint's configuration. Read-only.
///
/// url:       the endpoint cspUrl (e.g., "/csp/healthshare/fhir/fhir/r4").
/// namespace: optional target namespace.
///
/// Returns: { ok, namespace, url, exists, enabled?, instanceId?, config?{...} }.
ClassMethod GetFHIREndpoint(url As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetFHIREndpoint")
    Set out = {}
    Set out.tool = "get_fhir_endpoint"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl). List them with ListFHIREndpoints."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIREndpoint", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRServer.ServiceAdmin") {
            Set out.ok = 0
            Set out.error = "Namespace " _ targetNs _ " is not FHIR-enabled."
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 1
            Set out.exists = 0
            Set out.error = "No endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } Else {
            Set out.exists = 1
            Try { Set out.enabled = ''##class(HS.FHIRServer.ServiceAdmin).IsEndpointEnabled(url) } Catch  {}
            Set iid = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceIdForEndpoint(url)
            Set out.instanceId = iid
            Set cfg = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceConfigData(iid)
            If $isobject(cfg) {
                Set c = {}
                Set c.fhirVersion = cfg.FHIRVersion
                Set c.metadataPackages = cfg.FHIRMetadataSet
                Set c.strategy = cfg.InteractionsStrategyClass
                Set c.debugMode = cfg.DebugMode
                Set c.defaultSearchPageSize = cfg.DefaultSearchPageSize
                Set c.maxSearchPageSize = cfg.MaxSearchPageSize
                Set c.maxSearchResults = cfg.MaxSearchResults
                Set c.maxConditionalDeleteResults = cfg.MaxConditionalDeleteResults
                Set c.fhirSessionTimeout = cfg.FHIRSessionTimeout
                Set c.defaultPreferHandling = cfg.DefaultPreferHandling
                Set c.resourceValidation = cfg.ResourceValidation
                Set c.searchFiltering = ''cfg.SearchFiltering
                Set c.requiredResource = cfg.RequiredResource
                Set out.config = c
            }
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIREndpoint", out)
    Quit out
}

/// Fetch a FHIR endpoint's CapabilityStatement (the FHIR `metadata`
/// interaction) — the authoritative declaration of what the server
/// supports. By default returns a summary (FHIR version, software, and
/// the list of supported resource types); pass full=1 for the entire
/// CapabilityStatement document. CALL THIS for "what does this FHIR
/// server support", "what resources / interactions are enabled". Read-only.
///
/// url:       endpoint cspUrl.
/// full:      1 to embed the entire CapabilityStatement (large); default 0.
/// namespace: optional target namespace.
///
/// Returns: { ok, url, fhirVersion?, software?, resourceTypes:[...],
/// resourceTypeCount, capabilityStatement?, httpStatus?, error? }.
ClassMethod GetCapabilityStatement(url As %String, full As %Boolean = 0, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetCapabilityStatement")
    Set out = {}
    Set out.tool = "get_capability_statement"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.resourceTypes = []
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetCapabilityStatement", out)
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
            Set r = ..%Interaction(url, "GET", "metadata")
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            If 'r.ok {
                Set out.ok = 0
                Set out.error = $select(r.%IsDefined("error"):r.error, 1:"metadata interaction failed (HTTP " _ out.httpStatus _ ")")
            } Else {
                Set b = r.body
                Set out.fhirVersion = $select($isobject(b)&&b.%IsDefined("fhirVersion"):b.fhirVersion, 1:"")
                If $isobject(b)&&b.%IsDefined("software")&&$isobject(b.software) {
                    Set out.software = $select(b.software.%IsDefined("name"):b.software.name, 1:"") _ " " _ $select(b.software.%IsDefined("version"):b.software.version, 1:"")
                }
                Set rtc = 0
                If $isobject(b)&&b.%IsDefined("rest")&&$isobject(b.rest) {
                    Set restIt = b.rest.%GetIterator()
                    If restIt.%GetNext(.rk, .restEntry) {
                        If $isobject(restEntry)&&restEntry.%IsDefined("resource")&&$isobject(restEntry.resource) {
                            Set resIt = restEntry.resource.%GetIterator()
                            While resIt.%GetNext(.k2, .resEntry) {
                                If $isobject(resEntry)&&resEntry.%IsDefined("type") {
                                    Do out.resourceTypes.%Push(resEntry.type)
                                    Set rtc = rtc + 1
                                }
                            }
                        }
                    }
                }
                Set out.resourceTypeCount = rtc
                If +$get(full) { Set out.capabilityStatement = b }
                Set out.ok = 1
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetCapabilityStatement", out)
    Quit out
}

/// Count resources in a FHIR endpoint's repository. Pass a resourceType
/// for a single count, or omit it to survey a set of common clinical
/// resource types. Uses the `_summary=count` search so it is cheap.
/// CALL THIS for "how many Patients are there", "what data is in this
/// FHIR server". Read-only.
///
/// url:          endpoint cspUrl.
/// resourceType: optional FHIR resource type (e.g., "Patient").
/// namespace:    optional target namespace.
///
/// Returns single: { ok, url, resourceType, total }.
/// Returns survey: { ok, url, counts:[{resourceType, count}], totalResources }.
ClassMethod CountFHIRResources(url As %String, resourceType As %String = "", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("CountFHIRResources")
    Set out = {}
    Set out.tool = "count_fhir_resources"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("CountFHIRResources", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf $get(resourceType) '= "" {
            Set r = ..%Interaction(url, "GET", resourceType, "_summary=count")
            Set out.resourceType = resourceType
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            If r.ok && $isobject(r.body) && r.body.%IsDefined("total") {
                Set out.total = r.body.total
                Set out.ok = 1
            } Else {
                Set out.ok = 0
                Set out.error = $select(r.%IsDefined("error"):r.error, 1:"count failed (HTTP " _ out.httpStatus _ ")")
            }
        } Else {
            Set out.counts = []
            Set out.totalResources = 0
            Set types = $listbuild("Patient", "Encounter", "Observation", "Condition", "MedicationRequest", "Procedure", "AllergyIntolerance", "Immunization", "DiagnosticReport", "DocumentReference", "Organization", "Practitioner")
            For ti=1:1:$listlength(types) {
                Set t = $list(types, ti)
                Set rr = ..%Interaction(url, "GET", t, "_summary=count")
                If rr.ok && $isobject(rr.body) && rr.body.%IsDefined("total") {
                    Set n = +rr.body.total
                    If n > 0 {
                        Set c = {}
                        Set c.resourceType = t
                        Set c.count = n
                        Do out.counts.%Push(c)
                        Set out.totalResources = out.totalResources + n
                    }
                }
            }
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("CountFHIRResources", out)
    Quit out
}

/// Search a FHIR endpoint's repository for resources of a given type.
/// CALL THIS for "find patients named X", "show observations for patient
/// Y", or any query against stored resources. Read-only.
///
/// url:          endpoint cspUrl.
/// resourceType: FHIR resource type (e.g., "Patient").
/// query:        FHIR search query string WITHOUT the leading "?"
///               (e.g., "name=smith&birthdate=ge1980-01-01"). Optional.
/// count:        page size (_count); default 10.
/// namespace:    optional target namespace.
///
/// Returns: { ok, url, resourceType, total?, resourceCount,
/// resources:[{resourceType, id}], httpStatus, error? }.
ClassMethod SearchFHIRResources(url As %String, resourceType As %String, query As %String = "", count As %Integer = 10, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("SearchFHIRResources")
    Set out = {}
    Set out.tool = "search_fhir_resources"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.resourceType = $get(resourceType)
    Set out.resources = []
    If ($get(url) = "") || ($get(resourceType) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl) and `resourceType`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("SearchFHIRResources", out)
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
            Set q = $get(query)
            If +$get(count) > 0 { Set q = q _ $select(q'="":"&", 1:"") _ "_count=" _ (+count) }
            Set r = ..%Interaction(url, "GET", resourceType, q)
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            If 'r.ok {
                Set out.ok = 0
                Set out.error = $select(r.%IsDefined("error"):r.error, 1:"search failed (HTTP " _ out.httpStatus _ ")")
                If $isobject(r.body) { Set out.outcome = r.body }
            } Else {
                Set b = r.body
                If $isobject(b) && b.%IsDefined("total") { Set out.total = b.total }
                Set rc = 0
                If $isobject(b) && b.%IsDefined("entry") && $isobject(b.entry) {
                    Set it = b.entry.%GetIterator()
                    While it.%GetNext(.k, .e) {
                        Set res = $select($isobject(e)&&e.%IsDefined("resource"):e.resource, 1:"")
                        If $isobject(res) {
                            Set item = {}
                            Set item.resourceType = $select(res.%IsDefined("resourceType"):res.resourceType, 1:"")
                            Set item.id = $select(res.%IsDefined("id"):res.id, 1:"")
                            Do out.resources.%Push(item)
                            Set rc = rc + 1
                        }
                    }
                }
                Set out.resourceCount = rc
                Set out.ok = 1
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("SearchFHIRResources", out)
    Quit out
}

/// Read a single FHIR resource by type and id (the FHIR `read`
/// interaction). CALL THIS for "show me Patient 123", "fetch this
/// resource". Read-only.
///
/// url:          endpoint cspUrl.
/// resourceType: FHIR resource type.
/// id:           the resource logical id.
/// namespace:    optional target namespace.
///
/// Returns: { ok, url, resourceType, id, resource?(object), httpStatus, error?, outcome? }.
ClassMethod ReadFHIRResource(url As %String, resourceType As %String, id As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ReadFHIRResource")
    Set out = {}
    Set out.tool = "read_fhir_resource"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.resourceType = $get(resourceType)
    Set out.id = $get(id)
    If ($get(url) = "") || ($get(resourceType) = "") || ($get(id) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url`, `resourceType`, and `id`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("ReadFHIRResource", out)
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
            Set r = ..%Interaction(url, "GET", resourceType _ "/" _ id)
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            If r.ok {
                Set out.resource = r.body
                Set out.ok = 1
            } Else {
                Set out.ok = 0
                Set out.error = $select(r.%IsDefined("error"):r.error, 1:"read failed (HTTP " _ out.httpStatus _ ")")
                If $isobject(r.body) { Set out.outcome = r.body }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ReadFHIRResource", out)
    Quit out
}

/// Create a new FHIR resource in the endpoint's repository (the FHIR
/// `create` interaction — HTTP POST). MUTATING (create_ prefix). The
/// resource must include a `resourceType`; the server assigns the id.
///
/// url:       endpoint cspUrl.
/// resource:  the FHIR R4 resource as a JSON object or string.
/// namespace: optional target namespace.
///
/// Returns: { ok, created, url, resourceType, id?, location?, resource?(object), httpStatus, error?, outcome? }.
ClassMethod CreateFHIRResource(url As %String, resource, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("CreateFHIRResource")
    Set out = {}
    Set out.tool = "create_fhir_resource"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set obj = ..%ParseResource(resource)
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateFHIRResource", out)
        Quit out
    }
    If '$isobject(obj) {
        Set out.ok = 0
        Set out.error = "Pass `resource` as a FHIR R4 JSON object or string with a resourceType."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateFHIRResource", out)
        Quit out
    }
    Set rt = $select(obj.%IsDefined("resourceType"):obj.resourceType, 1:"")
    If rt = "" {
        Set out.ok = 0
        Set out.error = "Resource is missing required `resourceType`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateFHIRResource", out)
        Quit out
    }
    Set out.resourceType = rt
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } Else {
            Set r = ..%Interaction(url, "POST", rt, "", obj)
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            If r.ok {
                Set out.created = 1
                Set out.id = $select(r.%IsDefined("resourceId"):r.resourceId, 1:"")
                If r.%IsDefined("location") { Set out.location = r.location }
                If $isobject(r.body) { Set out.resource = r.body }
                Set out.ok = 1
            } Else {
                Set out.created = 0
                Set out.ok = 0
                Set out.error = $select(r.%IsDefined("error"):r.error, 1:"create failed (HTTP " _ out.httpStatus _ ")")
                If $isobject(r.body) { Set out.outcome = r.body }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateFHIRResource", out)
    Quit out
}

/// Update (replace) an existing FHIR resource by id (the FHIR `update`
/// interaction — HTTP PUT). MUTATING (update_ prefix). The resource
/// body's id is forced to match the id argument.
///
/// url:          endpoint cspUrl.
/// resourceType: FHIR resource type.
/// id:           the resource logical id to replace.
/// resource:     the full updated FHIR resource (JSON object or string).
/// namespace:    optional target namespace.
///
/// Returns: { ok, updated, url, resourceType, id, resource?(object), httpStatus, error?, outcome? }.
ClassMethod UpdateFHIRResource(url As %String, resourceType As %String, id As %String, resource, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("UpdateFHIRResource")
    Set out = {}
    Set out.tool = "update_fhir_resource"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.resourceType = $get(resourceType)
    Set out.id = $get(id)
    Set obj = ..%ParseResource(resource)
    If ($get(url) = "") || ($get(resourceType) = "") || ($get(id) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url`, `resourceType`, `id`, and `resource`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("UpdateFHIRResource", out)
        Quit out
    }
    If '$isobject(obj) {
        Set out.ok = 0
        Set out.error = "Pass `resource` as a FHIR R4 JSON object or string."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("UpdateFHIRResource", out)
        Quit out
    }
    ; FHIR update requires body id to match the URL id.
    Set obj.id = id
    If 'obj.%IsDefined("resourceType") { Set obj.resourceType = resourceType }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } Else {
            Set r = ..%Interaction(url, "PUT", resourceType _ "/" _ id, "", obj)
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            If r.ok {
                Set out.updated = 1
                If $isobject(r.body) { Set out.resource = r.body }
                Set out.ok = 1
            } Else {
                Set out.updated = 0
                Set out.ok = 0
                Set out.error = $select(r.%IsDefined("error"):r.error, 1:"update failed (HTTP " _ out.httpStatus _ ")")
                If $isobject(r.body) { Set out.outcome = r.body }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("UpdateFHIRResource", out)
    Quit out
}

/// Delete a FHIR resource by id (the FHIR `delete` interaction — HTTP
/// DELETE). MUTATING (delete_ prefix). Removes the resource from the
/// repository.
///
/// url:          endpoint cspUrl.
/// resourceType: FHIR resource type.
/// id:           the resource logical id to delete.
/// namespace:    optional target namespace.
///
/// Returns: { ok, deleted, url, resourceType, id, httpStatus, error?, outcome? }.
ClassMethod DeleteFHIRResource(url As %String, resourceType As %String, id As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("DeleteFHIRResource")
    Set out = {}
    Set out.tool = "delete_fhir_resource"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.resourceType = $get(resourceType)
    Set out.id = $get(id)
    If ($get(url) = "") || ($get(resourceType) = "") || ($get(id) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url`, `resourceType`, and `id`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteFHIRResource", out)
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
            Set r = ..%Interaction(url, "DELETE", resourceType _ "/" _ id)
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            If r.ok {
                Set out.deleted = 1
                Set out.ok = 1
            } Else {
                Set out.deleted = 0
                Set out.ok = 0
                Set out.error = $select(r.%IsDefined("error"):r.error, 1:"delete failed (HTTP " _ out.httpStatus _ ")")
                If $isobject(r.body) { Set out.outcome = r.body }
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteFHIRResource", out)
    Quit out
}

/// Validate a FHIR resource against the server using the `$validate`
/// operation — runs the endpoint's real validator (structure, cardinality,
/// terminology, and profiles). This is stronger than client-side
/// structural checks. CALL THIS for "is this resource valid for this
/// server", "validate against US Core". Read-only (no resource is stored).
///
/// url:       endpoint cspUrl.
/// resource:  FHIR R4 resource (JSON object or string) to validate.
/// profile:   optional canonical profile URL to validate against.
/// namespace: optional target namespace.
///
/// Returns: { ok, valid, url, resourceType, issues:[{severity, code,
/// diagnostics, location}], httpStatus, outcome?(object), error? }.
ClassMethod ValidateFHIRResource(url As %String, resource, profile As %String = "", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ValidateFHIRResource")
    Set out = {}
    Set out.tool = "validate_fhir_resource"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.issues = []
    Set obj = ..%ParseResource(resource)
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("ValidateFHIRResource", out)
        Quit out
    }
    If '$isobject(obj) {
        Set out.ok = 0
        Set out.error = "Pass `resource` as a FHIR R4 JSON object or string."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("ValidateFHIRResource", out)
        Quit out
    }
    Set rt = $select(obj.%IsDefined("resourceType"):obj.resourceType, 1:"")
    Set out.resourceType = rt
    If rt = "" {
        Set out.ok = 0
        Set out.error = "Resource is missing required `resourceType`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("ValidateFHIRResource", out)
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
            Set q = $select($get(profile)'="":"profile=" _ profile, 1:"")
            Set r = ..%Interaction(url, "POST", rt _ "/$validate", q, obj)
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            Set b = r.body
            If $isobject(b) { Set out.outcome = b }
            ; $validate returns an OperationOutcome. valid = no error/fatal issues.
            Set hasError = 0
            If $isobject(b) && b.%IsDefined("issue") && $isobject(b.issue) {
                Set it = b.issue.%GetIterator()
                While it.%GetNext(.k, .iss) {
                    If '$isobject(iss) { Continue }
                    Set sev = $select(iss.%IsDefined("severity"):iss.severity, 1:"")
                    If (sev = "error") || (sev = "fatal") { Set hasError = 1 }
                    Set io = {}
                    Set io.severity = sev
                    Set io.code = $select(iss.%IsDefined("code"):iss.code, 1:"")
                    Set io.diagnostics = $select(iss.%IsDefined("diagnostics"):$extract(iss.diagnostics, 1, 400), 1:"")
                    If iss.%IsDefined("expression") && $isobject(iss.expression) {
                        Try { Set io.location = iss.expression.%Get(0) } Catch  {}
                    }
                    Do out.issues.%Push(io)
                }
            }
            Set out.valid = 'hasError
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ValidateFHIRResource", out)
    Quit out
}

/// Execute an arbitrary FHIR interaction or operation against a local
/// endpoint — the escape hatch for anything the specific tools do not
/// cover ($everything, $expand, $lastn, history, batch/transaction
/// bundles, conditional ops, etc.). CALL THIS for advanced or
/// less-common FHIR requests. Side effects depend on the method/path
/// (GET is read-only; POST/PUT/DELETE mutate).
///
/// url:       endpoint cspUrl.
/// method:    HTTP verb — GET / POST / PUT / DELETE.
/// path:      request path relative to the endpoint, no leading slash
///            (e.g., "Patient/123/$everything", "metadata", "" for a
///            system batch).
/// query:     query string without leading "?" (optional).
/// body:      request body as a FHIR JSON object or string (optional;
///            used for POST/PUT and operations with a Parameters input).
/// namespace: optional target namespace.
///
/// Returns: { ok, url, method, path, httpStatus, body?(object),
/// location?, etag?, error? }.
ClassMethod ExecuteFHIRRequest(url As %String, method As %String, path As %String, query As %String = "", body = "", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ExecuteFHIRRequest")
    Set out = {}
    Set out.tool = "execute_fhir_request"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.method = $zconvert($get(method), "U")
    Set out.path = $get(path)
    If ($get(url) = "") || ($get(method) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url`, `method` (GET/POST/PUT/DELETE), and `path`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("ExecuteFHIRRequest", out)
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
            Set bodyObj = ""
            If $get(body) '= "" { Set bodyObj = ..%ParseResource(body) }
            Set r = ..%Interaction(url, out.method, $get(path), $get(query), bodyObj)
            Set out.httpStatus = $select(r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
            Set out.ok = ''r.ok
            If r.%IsDefined("location") { Set out.location = r.location }
            If r.%IsDefined("etag") { Set out.etag = r.etag }
            If $isobject(r.body) { Set out.body = r.body }
            If 'r.ok && r.%IsDefined("error") { Set out.error = r.error }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ExecuteFHIRRequest", out)
    Quit out
}

/// List the FHIR metadata package sources available to install on this
/// instance (FHIR core versions plus implementation guides such as
/// US Core). CALL THIS before AddFHIRPackages to see valid package ids.
/// Read-only.
///
/// namespace: optional target namespace.
///
/// Returns: { ok, namespace, packages:[id], total }.
ClassMethod ListAvailableFHIRPackages(namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListAvailableFHIRPackages")
    Set out = {}
    Set out.tool = "list_available_fhir_packages"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.packages = []
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRServer.Installer") {
            Set out.ok = 0
            Set out.error = "Namespace " _ targetNs _ " is not FHIR-enabled."
        } Else {
            ; Preferred source: the FHIR metadata repository lists loaded
            ; packages as name@version ids (HS.FHIRMeta.Storage.Package is
            ; a %ListOfObjects, each item has an .id like
            ; "hl7.fhir.us.core@5.0.1").
            Set got = 0
            Try {
                Set pk = ##class(HS.FHIRMeta.Storage.Package).GetAllPackages()
                If $isobject(pk) {
                    For pi=1:1:pk.Count() {
                        Set o = pk.GetAt(pi)
                        If $isobject(o) { Do out.packages.%Push(o.id) Set got = 1 }
                    }
                }
            } Catch  {}
            ; Fallback: installable package source directories.
            If 'got {
                Set src = ""
                Try { Set src = ##class(HS.FHIRServer.Installer).GetAllPackageSources() } Catch  {}
                If $listvalid(src) { For pi=1:1:$listlength(src) { Do out.packages.%Push($list(src, pi)) } }
            }
            Set out.total = out.packages.%Size()
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListAvailableFHIRPackages", out)
    Quit out
}

/// Add one or more FHIR metadata packages (implementation guides /
/// profiles) to an existing endpoint's instance — e.g. add US Core to a
/// core-only server. MUTATING (add_ prefix). Verify ids first with
/// ListAvailableFHIRPackages.
///
/// url:       endpoint cspUrl.
/// packages:  package ids as a CSV string (e.g.,
///            "hl7.fhir.us.core@5.0.1") or a JSON array of ids.
/// namespace: optional target namespace.
///
/// Returns: { ok, url, requestedPackages, metadataPackages?(after), error? }.
ClassMethod AddFHIRPackages(url As %String, packages, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("AddFHIRPackages")
    Set out = {}
    Set out.tool = "add_fhir_packages"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` and `packages`."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("AddFHIRPackages", out)
        Quit out
    }
    Set plist = ..%ToList(packages)
    If plist = "" {
        Set out.ok = 0
        Set out.error = "Pass `packages` as a CSV string or JSON array of package ids."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("AddFHIRPackages", out)
        Quit out
    }
    Set out.requestedPackages = $listtostring(plist, ",")
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 0
            Set out.error = "No endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } Else {
            Set iid = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceIdForEndpoint(url)
            ; AddPackagesToInstance is VOID — call with Do, not Set (Set raises
            ; <COMMAND> "Function must return a value"). It throws on failure,
            ; which the outer Catch handles.
            Do ##class(HS.FHIRServer.Installer).AddPackagesToInstance(iid, plist)
            Try {
                Set cfg = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceConfigData(iid)
                If $isobject(cfg) { Set out.metadataPackages = cfg.FHIRMetadataSet }
            } Catch  {}
            Set out.ok = 1
            Set out.message = "Packages added to endpoint " _ url _ "."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("AddFHIRPackages", out)
    Quit out
}

/// Update the runtime configuration of an existing FHIR endpoint.
/// MUTATING (update_ prefix). Reads the current config, applies the
/// supplied settings, and saves. Only recognized keys are applied.
///
/// url:       endpoint cspUrl.
/// settings:  JSON object of config keys to change. Recognized keys:
///            debugMode (0/1/2), defaultSearchPageSize, maxSearchPageSize,
///            maxSearchResults, maxConditionalDeleteResults,
///            fhirSessionTimeout, defaultPreferHandling
///            ("lenient" | "strict"), resourceValidation
///            ("always" | "if header" | "skip"), searchFiltering (0/1),
///            requiredResource. debugMode is a bit-flag: 1=include
///            traceback in error OperationOutcome, 2=new service instance
///            per request (so 3=both). FHIR version and the interactions
///            strategy are read-only after install and cannot be set here.
/// namespace: optional target namespace.
///
/// Returns: { ok, url, applied:[{key, value}], ignored:[key], error? }.
ClassMethod UpdateFHIREndpointConfig(url As %String, settings As %DynamicObject, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("UpdateFHIREndpointConfig")
    Set out = {}
    Set out.tool = "update_fhir_endpoint_config"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.applied = []
    Set out.ignored = []
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` and a `settings` object."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("UpdateFHIREndpointConfig", out)
        Quit out
    }
    If '$isobject(settings) {
        Set out.ok = 0
        Set out.error = "Pass `settings` as a JSON object of config keys to change."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("UpdateFHIREndpointConfig", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 0
            Set out.error = "No endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } Else {
            Set iid = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceIdForEndpoint(url)
            Set cfg = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceConfigData(iid)
            ; Map known JSON keys -> ConfigData property names.
            Set map("debugmode") = "DebugMode"
            Set map("defaultsearchpagesize") = "DefaultSearchPageSize"
            Set map("maxsearchpagesize") = "MaxSearchPageSize"
            Set map("maxsearchresults") = "MaxSearchResults"
            Set map("maxconditionaldeleteresults") = "MaxConditionalDeleteResults"
            Set map("fhirsessiontimeout") = "FHIRSessionTimeout"
            Set map("defaultpreferhandling") = "DefaultPreferHandling"
            Set map("resourcevalidation") = "ResourceValidation"
            Set map("searchfiltering") = "SearchFiltering"
            Set map("requiredresource") = "RequiredResource"
            Set it = settings.%GetIterator()
            While it.%GetNext(.k, .v) {
                Set prop = $get(map($zconvert(k, "L")))
                If prop = "" {
                    Do out.ignored.%Push(k)
                } Else {
                    Set $property(cfg, prop) = v
                    Set a = {}
                    Set a.key = prop
                    Set a.value = v
                    Do out.applied.%Push(a)
                }
            }
            If out.applied.%Size() = 0 {
                Set out.ok = 0
                Set out.error = "No recognized config keys in `settings`. See the tool description for valid keys."
            } Else {
                ; SetInstanceConfigData is VOID — call with Do, not Set (Set
                ; raises <COMMAND>). It throws on failure (outer Catch handles).
                Do ##class(HS.FHIRServer.ServiceAdmin).SetInstanceConfigData(iid, cfg)
                Set out.ok = 1
                Set out.message = "Updated " _ out.applied.%Size() _ " config setting(s) on " _ url _ "."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("UpdateFHIREndpointConfig", out)
    Quit out
}

/// Enable or disable a FHIR endpoint without deleting it. MUTATING
/// (set_ prefix). A disabled endpoint rejects requests but keeps its
/// data and configuration.
///
/// url:       endpoint cspUrl.
/// enabled:   1 to enable, 0 to disable.
/// namespace: optional target namespace.
///
/// Returns: { ok, url, enabled, error? }.
ClassMethod SetFHIREndpointEnabled(url As %String, enabled As %Boolean, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("SetFHIREndpointEnabled")
    Set out = {}
    Set out.tool = "set_fhir_endpoint_enabled"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    If ($get(url) = "") || ($get(enabled) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url` and `enabled` (1 or 0)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("SetFHIREndpointEnabled", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 0
            Set out.error = "No endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } Else {
            ; SetEndpointEnabled is VOID — call with Do, not Set (Set raises
            ; <COMMAND>). It throws on failure (outer Catch handles).
            Do ##class(HS.FHIRServer.ServiceAdmin).SetEndpointEnabled(url, ''(+enabled))
            Set out.enabled = ''(+enabled)
            Set out.ok = 1
            Set out.message = "Endpoint " _ url _ " " _ $select(+enabled:"enabled", 1:"disabled") _ "."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("SetFHIREndpointEnabled", out)
    Quit out
}

/// Provision a NEW FHIR R4 endpoint in a namespace. MUTATING (create_
/// prefix). GUARD: refuses if an endpoint already exists at the URL —
/// it never reinstalls or duplicates a live server. Prefer managing the
/// existing foundation-namespace endpoint; only call this when the user
/// explicitly wants a new endpoint. Enables the namespace for FHIR if
/// needed, then installs the instance.
///
/// url:         the new endpoint cspUrl (e.g., "/csp/healthshare/myns/fhir/r4").
/// packages:    metadata packages CSV; default "hl7.fhir.r4.core@4.0.1".
/// strategy:    storage strategy; default "advanced-json".
/// description: optional display description.
/// namespace:   optional target namespace.
///
/// Returns: { ok, created, url, namespace, storage, packages, error? }.
ClassMethod CreateFHIREndpoint(url As %String, packages As %String = "hl7.fhir.r4.core@4.0.1", strategy As %String = "advanced-json", description As %String = "", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("CreateFHIREndpoint")
    Set out = {}
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    ; Map the friendly alias to the real storage class. The class name is
    ; never exposed to the model (in the schema or the result) because the
    ; model parrots whatever it sees — that is the internals leak we fix.
    Set strategyClass = ..%ResolveStrategy(strategy)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.storage = $select((strategyClass["JsonAdvSQL"):"Advanced JSON",1:"standard JSON")
    Set out.packages = packages
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (the new endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateFHIREndpoint", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRServer.Installer") {
            Set out.ok = 0
            Set out.error = "Namespace " _ targetNs _ " is not HealthShare/FHIR-capable; cannot install a FHIR endpoint here."
        } ElseIf ##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 0
            Set out.created = 0
            Set out.error = "An endpoint already exists at '" _ url _ "'. Refusing to reinstall. Inspect it with GetFHIREndpoint or manage it with the other tools."
        } Else {
            ; Ensure the namespace is FHIR-enabled (idempotent).
            Try { Do ##class(HS.FHIRServer.Installer).InstallNamespace(targetNs) } Catch  {}
            Set sc = $$$OK
            ; HS.FHIRServer.Installer.InstallInstance -> AddInstanceToRepo ->
            ; HS.FHIRMeta.Storage.Package.ResolvePackageList expects a %List
            ; ($listbuild). A bare string is treated as ONE package id, so a
            ; comma-separated list of multiple packages must be split here.
            Set pkgList = ""
            For pi=1:1:$length(packages, ",") {
                Set onePkg = $zstrip($piece(packages, ",", pi), "<>W")
                If onePkg '= "" { Set pkgList = pkgList _ $listbuild(onePkg) }
            }
            ; InstallInstance is a VOID method (no return value) — call with
            ; Do, not Set (Set triggers <COMMAND> "Function must return a
            ; value"). It throws on failure, which the outer Catch handles.
            Do ##class(HS.FHIRServer.Installer).InstallInstance(url, strategyClass, pkgList, "", description)
            Set out.created = ''##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url)
            If 'out.created {
                Set out.ok = 0
                Set out.error = "InstallInstance completed but the endpoint was not created."
            } Else {
                Set out.ok = 1
                Set out.message = "FHIR endpoint created at " _ url _ " in namespace " _ targetNs _ "."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateFHIREndpoint", out)
    Quit out
}

/// Map a friendly storage-strategy alias to the real InteractionsStrategy
/// class. Back-compat: a value that already looks like a class (contains a
/// dot) passes through unchanged; anything else maps to Advanced JSON, the
/// strategy currently offered. Internal — never exposed as a tool, so the
/// class name stays out of the model's view.
ClassMethod %ResolveStrategy(strategy As %String = "advanced-json") As %String [ Internal ]
{
    Set s = $zstrip($get(strategy), "<>W")
    If s [ "." Quit s
    Quit "HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy"
}

/// Remove a FHIR endpoint. MUTATING (delete_ prefix). By default this
/// decommissions the endpoint (stops serving it) while PRESERVING the
/// stored resource data. Pass deleteData=1 to also drop the repository
/// data — destructive and irreversible.
///
/// url:        endpoint cspUrl.
/// deleteData: 0 = decommission only (default, keeps data); 1 = also
///             delete all stored FHIR data.
/// namespace:  optional target namespace.
///
/// Returns: { ok, deleted, dataDeleted, url, error? }.
ClassMethod DeleteFHIREndpoint(url As %String, deleteData As %Boolean = 0, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("DeleteFHIREndpoint")
    Set out = {}
    Set out.tool = "delete_fhir_endpoint"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteFHIREndpoint", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 1
            Set out.deleted = 0
            Set out.error = "No endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } Else {
            Set iid = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceIdForEndpoint(url)
            ; UninstallInstance / DecommissionInstance are VOID methods — call
            ; with Do, not Set (Set raises <COMMAND> "Function must return a
            ; value" after the work has already run). They throw on real
            ; failure, which the outer Catch handles.
            If +$get(deleteData) {
                Do ##class(HS.FHIRServer.Installer).UninstallInstance(url, 1)
                Set out.dataDeleted = 1
            } Else {
                Do ##class(HS.FHIRServer.ServiceAdmin).DecommissionInstance(iid)
                Set out.dataDeleted = 0
            }
            Set stillExists = 0
            Try { Set stillExists = ##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) } Catch  {}
            If stillExists {
                Set out.ok = 0
                Set out.deleted = 0
                Set out.error = "Endpoint still present after the delete call."
            } Else {
                Set out.ok = 1
                Set out.deleted = 1
                Set out.message = "Endpoint " _ url _ " " _ $select(+$get(deleteData):"uninstalled (data deleted)", 1:"decommissioned (data preserved)") _ "."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteFHIREndpoint", out)
    Quit out
}

/// Bulk-load FHIR resources into an endpoint's repository from a directory
/// on the IRIS server filesystem (.json, .ndjson, or .xml files) using
/// HS.FHIRServer.Tools.DataLoader (in-process, no HTTP). CALL THIS to seed
/// or import a data set into the FHIR server. MUTATING (load_ prefix).
///
/// url:       endpoint cspUrl.
/// directory: server-side directory containing FHIR resource files.
/// namespace: optional target namespace.
///
/// Returns: { ok, url, directory, result?, message?, error? }.
ClassMethod LoadFHIRData(url As %String, directory As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("LoadFHIRData")
    Set out = {}
    Set out.tool = "load_fhir_data"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.directory = $get(directory)
    If ($get(url) = "") || ($get(directory) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl) and `directory` (server-side path with .json/.ndjson/.xml files)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("LoadFHIRData", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 0
            Set out.error = "No endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } ElseIf '##class(%Library.File).DirectoryExists(directory) {
            Set out.ok = 0
            Set out.error = "Directory not found on the IRIS server: " _ directory
        } Else {
            ; SubmitResourceFiles(dir, serviceType, serviceName, displayProgress)
            ; serviceType "FHIRServer" loads directly into the local repo.
            Set res = ##class(HS.FHIRServer.Tools.DataLoader).SubmitResourceFiles(directory, "FHIRServer", url, 0)
            Set scErr = ..%SCErr(res)
            If scErr '= "" {
                Set out.ok = 0
                Set out.error = scErr
            } Else {
                If $isvalidnum(res) { Set out.result = res }
                Set out.ok = 1
                Set out.message = "Submitted FHIR resource files from " _ directory _ " to endpoint " _ url _ "."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("LoadFHIRData", out)
    Quit out
}

/// Wipe ALL stored FHIR resources from an endpoint's repository while
/// keeping the endpoint, its configuration, and metadata packages intact.
/// Uses HS.FHIRServer.Installer.Reset. MUTATING and DESTRUCTIVE (reset_
/// prefix) — there is no undo. Use to return a dev/test server to empty.
///
/// url:       endpoint cspUrl.
/// namespace: optional target namespace.
///
/// Returns: { ok, url, message?, error? }.
ClassMethod ResetFHIRServerData(url As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ResetFHIRServerData")
    Set out = {}
    Set out.tool = "reset_fhir_server_data"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("ResetFHIRServerData", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 0
            Set out.error = "No endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } Else {
            Set iid = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceIdForEndpoint(url)
            ; Reset is a VOID method — call with Do, not Set (Set raises
            ; <COMMAND> "Function must return a value" after the reset runs).
            ; It throws on failure, which the outer Catch handles.
            Do ##class(HS.FHIRServer.Installer).Reset(iid, url)
            Set out.ok = 1
            Set out.message = "All FHIR resource data cleared from endpoint " _ url _ " (endpoint and config preserved)."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ResetFHIRServerData", out)
    Quit out
}

/// Load a directory of FHIR files into an endpoint in the CORRECT ORDER,
/// asynchronously. CALL THIS to ingest a folder of FHIR bundles/resources
/// (e.g. Synthea output) into a FHIR server. It orders the load so
/// infrastructure bundles (hospitalInformation / practitionerInformation,
/// or files referencing Organization/Location/Practitioner) load FIRST,
/// so per-patient bundles' conditional references resolve — without this
/// ordering, Synthea patient bundles fail with ConditionalRefNotResolved.
/// MUTATING (load_ prefix).
///
/// The load runs in a BACKGROUND job (a large folder would exceed a chat
/// turn), so this returns immediately with a jobId. Poll progress with
/// GetFHIRLoadStatus. Pass dryRun=1 to preview the load order WITHOUT
/// loading anything.
///
/// NOTE: `directory` must be a path the IRIS SERVER can read. A file on
/// the user's desktop is NOT reachable by IRIS — it must first be copied
/// onto the server or exposed via a mounted volume.
///
/// url:       endpoint cspUrl.
/// directory: server-side directory of .json/.ndjson FHIR files.
/// infraFirst: 1 (default) = load infrastructure bundles first.
/// dryRun:    1 = return the planned order only, do not load.
/// namespace: optional target namespace.
///
/// Returns: { ok, url, directory, totalFiles, order:[firstFiles],
/// jobId?, dryRun?, message }.
ClassMethod LoadFHIRDirectory(url As %String, directory As %String, infraFirst As %Boolean = 1, dryRun As %Boolean = 0, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("LoadFHIRDirectory")
    Set out = {}
    Set out.tool = "load_fhir_directory"
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set out.directory = $get(directory)
    Set out.order = []
    If ($get(url) = "") || ($get(directory) = "") {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl) and `directory` (server-side path of FHIR files)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("LoadFHIRDirectory", out)
        Quit out
    }
    ; No $namespace switch here — we only read the filesystem (namespace-
    ; independent) and write the ^AgInt.FHIRLoad progress global in the app
    ; namespace. The background job switches into the target namespace per
    ; file (see %LoadOneFile), and GetFHIRLoadStatus reads the global here.
    Try {
        If '##class(%Library.File).DirectoryExists(directory) {
            Set out.ok = 0
            Set out.error = "Directory not found on the IRIS server: " _ directory _ ". The files must be on a path IRIS can read (copy them onto the server or mount a volume)."
        } Else {
            Kill keys
            Set total = 0
            Set q = ##class(%ResultSet).%New("%File:FileSet")
            Do q.Execute(directory, "*.json;*.ndjson")
            While q.Next() {
                Set fp = q.Get("Name")
                If fp = "" { Continue }
                Set lname = $zconvert($piece(fp, "/", *), "L")
                Set rank = 2
                If infraFirst {
                    If lname [ "hospitalinformation" { Set rank = 0 }
                    ElseIf lname [ "practitionerinformation" { Set rank = 1 }
                    ElseIf (lname [ "organization") || (lname [ "location") || (lname [ "practitioner") { Set rank = 1 }
                }
                Set total = total + 1
                ; Sort key: rank, then name, then a counter for stability.
                Set keys(rank, lname, total) = fp
            }
            Set out.totalFiles = total
            If total = 0 {
                Set out.ok = 1
                Set out.message = "No .json/.ndjson files found in " _ directory _ "."
            } ElseIf +$get(dryRun) {
                Set n = 0
                Set r1 = $order(keys(""))
                While r1 '= "" {
                    Set n2 = $order(keys(r1, ""))
                    While n2 '= "" {
                        Set c = $order(keys(r1, n2, ""))
                        While c '= "" {
                            Set n = n + 1
                            If n <= 25 { Do out.order.%Push($piece(keys(r1, n2, c), "/", *)) }
                            Set c = $order(keys(r1, n2, c))
                        }
                        Set n2 = $order(keys(r1, n2))
                    }
                    Set r1 = $order(keys(r1))
                }
                Set out.dryRun = 1
                Set out.ok = 1
                Set out.message = total _ " file(s) would load in this order (infrastructure bundles first). Showing first " _ $select(total > 25:25, 1:total) _ "."
            } Else {
                Set jobId = $zstrip($system.Util.CreateGUID(), "<>W")
                Set out.jobId = jobId
                Kill ^AgInt.FHIRLoad(jobId)
                Set ^AgInt.FHIRLoad(jobId, "total") = total
                Set ^AgInt.FHIRLoad(jobId, "done") = 0
                Set ^AgInt.FHIRLoad(jobId, "failed") = 0
                Set ^AgInt.FHIRLoad(jobId, "status") = "queued"
                Set ^AgInt.FHIRLoad(jobId, "url") = url
                Set ^AgInt.FHIRLoad(jobId, "ns") = targetNs
                Set ^AgInt.FHIRLoad(jobId, "queued") = $zdatetime($horolog, 3, 1)
                Set seq = 0
                Set r1 = $order(keys(""))
                While r1 '= "" {
                    Set n2 = $order(keys(r1, ""))
                    While n2 '= "" {
                        Set c = $order(keys(r1, n2, ""))
                        While c '= "" {
                            Set seq = seq + 1
                            Set ^AgInt.FHIRLoad(jobId, "file", seq) = keys(r1, n2, c)
                            If seq <= 25 { Do out.order.%Push($piece(keys(r1, n2, c), "/", *)) }
                            Set c = $order(keys(r1, n2, c))
                        }
                        Set n2 = $order(keys(r1, n2))
                    }
                    Set r1 = $order(keys(r1))
                }
                ; Launch the background loader.
                Job ##class(AgenticInterop.Tool.FHIRServer).%RunLoadJob(jobId, url, targetNs)
                Set out.ok = 1
                Set out.message = "Loading " _ total _ " file(s) into " _ url _ " in the background (infrastructure bundles first). The chat shows a live progress bar that tracks this to completion — tell the user the load has started and how many files, then stop. Do NOT poll in a loop."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("LoadFHIRDirectory", out)
    Quit out
}

/// Check the progress of a background FHIR directory load started by
/// LoadFHIRDirectory. The chat already shows a live progress bar, so do NOT
/// poll this in a loop — call it only if the user explicitly asks for a
/// one-time status update in text. Read-only.
///
/// jobId:     the id returned by LoadFHIRDirectory.
/// namespace: optional (unused for the read; kept for signature symmetry).
///
/// Returns: { ok, jobId, found, status, total, filesDone, filesFailed,
/// current?, done, errors:[...], jobError? }.
ClassMethod GetFHIRLoadStatus(jobId As %String, namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetFHIRLoadStatus")
    Set out = {}
    Set out.tool = "get_fhir_load_status"
    Set out.jobId = $get(jobId)
    Set out.errors = []
    If $get(jobId) = "" {
        Set out.ok = 0
        Set out.error = "Pass `jobId` (from LoadFHIRDirectory)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIRLoadStatus", out)
        Quit out
    }
    Try {
        If '$data(^AgInt.FHIRLoad(jobId)) {
            Set out.ok = 1
            Set out.found = 0
            Set out.error = "No load job with id " _ jobId _ "."
        } Else {
            Set out.found = 1
            Set out.status = $get(^AgInt.FHIRLoad(jobId, "status"))
            Set out.total = +$get(^AgInt.FHIRLoad(jobId, "total"))
            Set out.filesDone = +$get(^AgInt.FHIRLoad(jobId, "done"))
            Set out.filesFailed = +$get(^AgInt.FHIRLoad(jobId, "failed"))
            Set cur = $get(^AgInt.FHIRLoad(jobId, "current"))
            If cur '= "" { Set out.current = cur }
            Set out.done = ''((out.status = "completed") || (out.status = "error"))
            Set en = +$get(^AgInt.FHIRLoad(jobId, "errN"))
            For j=1:1:en { If $data(^AgInt.FHIRLoad(jobId, "err", j)) { Do out.errors.%Push(^AgInt.FHIRLoad(jobId, "err", j)) } }
            If $get(^AgInt.FHIRLoad(jobId, "jobError")) '= "" { Set out.jobError = ^AgInt.FHIRLoad(jobId, "jobError") }
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIRLoadStatus", out)
    Quit out
}

/// Ingestion performance metrics for a LoadFHIRDirectory job: how long it
/// took, throughput (resources/sec), and the bottlenecks (slowest files).
/// Read-only. Computed from the load job's recorded per-file timing.
///
/// jobId:     the LoadFHIRDirectory jobId. If omitted, the most recent job.
/// namespace: optional (the metrics global is dispatch-namespace scoped).
///
/// Returns: { ok, found, jobId, status, startedAt, finishedAt, durationSec,
/// totalFiles, filesDone, filesFailed, totalResources, resourcesPerSecond,
/// filesPerSecond, avgFileSec, totalMB, mbPerSecond,
/// bottlenecks:[{file, seconds, resources, mb, ok}], message }.
ClassMethod GetFHIRLoadMetrics(jobId As %String = "", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetFHIRLoadMetrics")
    Set out = {}
    Set out.tool = "get_fhir_load_metrics"
    Try {
        Set jid = $get(jobId)
        ; Default to the most recent job that has per-file metrics tracking
        ; (startH > 0); fall back to the most recent job overall.
        If jid = "" {
            Set best = "", bestH = 0, anyK = "", k = ""
            For  { Set k = $order(^AgInt.FHIRLoad(k)) Quit:k=""  Set anyK = k Set sh = +$get(^AgInt.FHIRLoad(k, "startH")) If sh > bestH { Set best = k, bestH = sh } }
            Set jid = $select(best '= "":best, 1:anyK)
        }
        Set out.jobId = jid
        If (jid = "") || ('$data(^AgInt.FHIRLoad(jid))) {
            Set out.ok = 1
            Set out.found = 0
            Set out.message = "No load job metrics found" _ $select($get(jobId)'="":" for id " _ jobId, 1:"") _ "."
        } Else {
            Set out.found = 1
            Set out.status = $get(^AgInt.FHIRLoad(jid, "status"))
            Set out.startedAt = $get(^AgInt.FHIRLoad(jid, "started"))
            Set out.finishedAt = $get(^AgInt.FHIRLoad(jid, "finished"))
            Set startH = +$get(^AgInt.FHIRLoad(jid, "startH"))
            ; Jobs created before per-file metrics tracking have no startH —
            ; report basic counts and say so, rather than bogus throughput.
            If startH = 0 {
                Set out.metricsTracked = 0
                Set out.totalFiles = +$get(^AgInt.FHIRLoad(jid, "total"))
                Set out.filesDone = +$get(^AgInt.FHIRLoad(jid, "done"))
                Set out.filesFailed = +$get(^AgInt.FHIRLoad(jid, "failed"))
                Set out.bottlenecks = []
                Set out.message = "This load job predates per-file metrics tracking. Run a new LoadFHIRDirectory to capture duration, throughput (resources/sec), and bottlenecks."
                Set out.ok = 1
                Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIRLoadMetrics", out)
                Return out
            }
            Set out.metricsTracked = 1
            Set finishH = +$get(^AgInt.FHIRLoad(jid, "finishedH"))
            If finishH = 0 { Set finishH = $zhorolog }
            Set dur = finishH - startH
            If dur < 0 { Set dur = dur + 86400 }
            Set out.durationSec = $normalize(dur, 2)
            Set out.totalFiles = +$get(^AgInt.FHIRLoad(jid, "total"))
            Set out.filesDone = +$get(^AgInt.FHIRLoad(jid, "done"))
            Set out.filesFailed = +$get(^AgInt.FHIRLoad(jid, "failed"))
            Set totalRes = +$get(^AgInt.FHIRLoad(jid, "resources"))
            Set out.totalResources = totalRes
            Set out.resourcesPerSecond = $select(dur > 0:$normalize(totalRes / dur, 1), 1:0)
            Set out.filesPerSecond = $select(dur > 0:$normalize(out.filesDone / dur, 2), 1:0)
            ; Per-file timing -> averages + bottlenecks (top 10 slowest).
            Set totalBytes = 0, sumSec = 0, nFiles = 0
            Kill srt
            Set seq = $order(^AgInt.FHIRLoad(jid, "metric", ""))
            While seq '= "" {
                Set m = ^AgInt.FHIRLoad(jid, "metric", seq)
                Set sumSec = sumSec + (+$listget(m, 2)), totalBytes = totalBytes + (+$listget(m, 5)), nFiles = nFiles + 1
                Set srt(+$listget(m, 2), seq) = m
                Set seq = $order(^AgInt.FHIRLoad(jid, "metric", seq))
            }
            Set out.avgFileSec = $select(nFiles > 0:$normalize(sumSec / nFiles, 2), 1:0)
            Set out.totalMB = $normalize(totalBytes / 1048576, 1)
            Set out.mbPerSecond = $select(dur > 0:$normalize((totalBytes / 1048576) / dur, 2), 1:0)
            Set out.bottlenecks = []
            Set cnt = 0, d = $order(srt(""), -1)
            While (d '= "") && (cnt < 10) {
                Set s2 = $order(srt(d, ""), -1)
                While (s2 '= "") && (cnt < 10) {
                    Set m = srt(d, s2), b = {}
                    Set b.file = $listget(m, 1)
                    Set b.seconds = $normalize(+$listget(m, 2), 2)
                    Set b.resources = +$listget(m, 3)
                    Set b.ok = ''$listget(m, 4)
                    Set b.mb = $normalize((+$listget(m, 5)) / 1048576, 2)
                    Do out.bottlenecks.%Push(b)
                    Set cnt = cnt + 1
                    Set s2 = $order(srt(d, s2), -1)
                }
                Set d = $order(srt(d), -1)
            }
            Set out.message = "Ingested " _ totalRes _ " resources from " _ out.filesDone _ " file(s) in " _ out.durationSec _ "s (" _ out.resourcesPerSecond _ " resources/sec, " _ out.mbPerSecond _ " MB/sec). The `bottlenecks` list is the slowest files."
            Set out.ok = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIRLoadMetrics", out)
    Quit out
}

/// FHIR Server storage + performance audit. For an endpoint: configuration
/// (CORE GetInstanceConfigData), resource counts by type (CORE FHIR
/// `_summary=count` search), and database storage sizes for the namespace
/// (CORE SYS.Database). Read-only. The per-type counts cover a common
/// clinical set (or the supplied resourceTypes) via CORE FHIR search.
///
/// url:           endpoint cspUrl (optional — omit for storage-only audit).
/// resourceTypes: optional CSV of resource types to count (default common set).
/// namespace:     optional target namespace.
///
/// Returns: { ok, namespace, endpoint?{url,enabled,fhirVersion,...},
/// counts:[{resourceType,count}], totalResources,
/// storage:{databases:[{name,directory,sizeMB}], totalMB}, message }.
ClassMethod GetFHIRServerStats(url As %String = "", resourceTypes As %String = "", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetFHIRServerStats")
    Set out = {}
    Set out.tool = "get_fhir_server_stats"
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
        } Else {
            Set out.counts = []
            Set out.totalResources = 0
            ; --- Endpoint config + per-type resource counts (CORE) ---
            If ($get(url) '= "") && ##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
                Set ep = {}
                Set ep.url = url
                Try { Set ep.enabled = ''##class(HS.FHIRServer.ServiceAdmin).IsEndpointEnabled(url) } Catch  {}
                Try {
                    Set iid = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceIdForEndpoint(url)
                    Set cfg = ##class(HS.FHIRServer.ServiceAdmin).GetInstanceConfigData(iid)
                    If $isobject(cfg) {
                        Set ep.instanceId = iid
                        Set ep.fhirVersion = cfg.FHIRVersion
                        Set ep.metadataPackages = cfg.FHIRMetadataSet
                        Set ep.resourceValidation = cfg.ResourceValidation
                    }
                } Catch  {}
                Set out.endpoint = ep
                Set types = $listbuild("Patient", "Encounter", "Observation", "Condition", "Procedure", "MedicationRequest", "DiagnosticReport", "Immunization", "AllergyIntolerance", "CarePlan", "Claim", "ExplanationOfBenefit", "DocumentReference", "Organization", "Practitioner", "Location")
                If $get(resourceTypes) '= "" {
                    Set types = ""
                    For ti=1:1:$length(resourceTypes, ",") { Set t = $zstrip($piece(resourceTypes, ",", ti), "<>W") If t '= "" { Set types = types _ $listbuild(t) } }
                }
                For ti=1:1:$listlength(types) {
                    Set t = $list(types, ti)
                    Set rr = ..%Interaction(url, "GET", t, "_summary=count")
                    If $isobject(rr), rr.ok, $isobject(rr.body), rr.body.%IsDefined("total") {
                        Set n = +rr.body.total
                        Set c = {}
                        Set c.resourceType = t
                        Set c.count = n
                        Do out.counts.%Push(c)
                        Set out.totalResources = out.totalResources + n
                    }
                }
            }
            ; --- FHIR SERVER storage = the repository databases (CORE SYS.Database) ---
            ; The FHIR server's data lives in DEDICATED repo databases created per
            ; endpoint, named <NS>X####R (resources) and <NS>X####V (versions).
            ; We measure THOSE — NOT the namespace's own default database (named
            ; exactly <NS>), which holds namespace code + the FHIR metadata
            ; packages, not FHIR server data. With no endpoint there are no repo
            ; databases, so server storage is 0.
            Set st = {}
            Set st.databases = []
            Set st.totalMB = 0
            Set st.note = "FHIR server storage = the per-endpoint repository databases (<NS>X####R resources + ...V versions). Excludes the namespace default database (code + metadata packages)."
            Set $namespace = "%SYS"
            Set nsU = $zconvert(targetNs, "U")
            Set rs = ##class(%ResultSet).%New("Config.Databases:List")
            Do rs.Execute()
            While rs.Next() {
                Set dbName = rs.GetData(1), dbDir = rs.GetData(2)
                Set dbU = $zconvert(dbName, "U")
                ; Only FHIR repository databases: <NS>X<digits>R | <NS>X<digits>V.
                ; Explicitly exclude the namespace default DB (name = <NS>).
                If (dbU '= nsU) && $match(dbU, "^" _ nsU _ "X[0-9]+[RV]$") {
                    Set sz = ""
                    Try { Set dbo = ##class(SYS.Database).%OpenId(dbDir) If $isobject(dbo) { Set sz = dbo.Size } } Catch  {}
                    Set d = {}
                    Set d.name = dbName
                    Set d.directory = dbDir
                    Set d.sizeMB = +sz
                    Set d.role = $select($extract(dbU, *) = "V":"versions", 1:"resources")
                    Do st.databases.%Push(d)
                    Set st.totalMB = st.totalMB + (+sz)
                }
            }
            Set out.storage = st
            Set out.ok = 1
            Set out.message = "FHIR audit for " _ targetNs _ ": " _ out.totalResources _ " resources (counted types), " _ st.totalMB _ " MB across " _ st.databases.%Size() _ " database(s)."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIRServerStats", out)
    Quit out
}

/// List recent FHIR directory-load runs from the durable history
/// (AgenticInterop.Data.FHIRLoadRun) — duration, throughput, and totals per
/// run for trend review. Read-only. (This reads our own history table, not a
/// FHIR CORE API.)
///
/// namespace: optional — filter to loads that targeted this FHIR namespace.
/// limit:     max rows (default 20).
///
/// Returns: { ok, total, runs:[{namespace, endpoint, jobId, startedAt,
/// finishedAt, durationSec, totalFiles, filesDone, filesFailed,
/// totalResources, resourcesPerSec, totalMB, status}] }.
ClassMethod ListFHIRLoadRuns(namespace As %String = "", limit As %Integer = 20) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListFHIRLoadRuns")
    Set out = {}
    Set out.tool = "list_fhir_load_runs"
    Set out.runs = []
    Try {
        If '##class(%Dictionary.CompiledClass).%ExistsId("AgenticInterop.Data.FHIRLoadRun") {
            Set out.ok = 1
            Set out.total = 0
            Set out.message = "No load-run history yet."
            Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListFHIRLoadRuns", out)
            Return out
        }
        Set lim = +$get(limit) If lim <= 0 { Set lim = 20 }
        Set cols = "Namespace,Endpoint,JobId,StartedAt,FinishedAt,DurationSec,TotalFiles,FilesDone,FilesFailed,TotalResources,ResourcesPerSec,TotalMB,Status"
        Set ns = $get(namespace)
        If ns '= "" {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP ? " _ cols _ " FROM AgenticInterop_Data.FHIRLoadRun WHERE Namespace = ? ORDER BY CreatedAt DESC", lim, ns)
        } Else {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP ? " _ cols _ " FROM AgenticInterop_Data.FHIRLoadRun ORDER BY CreatedAt DESC", lim)
        }
        Set cnt = 0
        While rs.%Next() {
            Set row = {}
            Set row.namespace = rs.%Get("Namespace")
            Set row.endpoint = rs.%Get("Endpoint")
            Set row.jobId = rs.%Get("JobId")
            Set row.startedAt = rs.%Get("StartedAt")
            Set row.finishedAt = rs.%Get("FinishedAt")
            Set row.durationSec = rs.%Get("DurationSec")
            Set row.totalFiles = rs.%Get("TotalFiles")
            Set row.filesDone = rs.%Get("FilesDone")
            Set row.filesFailed = rs.%Get("FilesFailed")
            Set row.totalResources = rs.%Get("TotalResources")
            Set row.resourcesPerSec = rs.%Get("ResourcesPerSec")
            Set row.totalMB = rs.%Get("TotalMB")
            Set row.status = rs.%Get("Status")
            Do out.runs.%Push(row)
            Set cnt = cnt + 1
        }
        Set out.total = cnt
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListFHIRLoadRuns", out)
    Quit out
}

/// Measure FHIR query performance AT REST: times representative CORE FHIR
/// searches (a `_summary=count` and a results page) against an endpoint and
/// reports elapsed milliseconds. Read-only. Answers "are searches fast?"
/// independent of ingestion. Uses the CORE FHIR dispatch (no SQL).
///
/// url:          endpoint cspUrl.
/// resourceType: type to probe (default Patient).
/// namespace:    optional target namespace.
///
/// Returns: { ok, url, resourceType, probes:[{name, query, ms, httpStatus,
/// total?}], message }.
ClassMethod GetFHIRQueryPerformance(url As %String, resourceType As %String = "Patient", namespace As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetFHIRQueryPerformance")
    Set out = {}
    Set out.tool = "get_fhir_query_performance"
    Set dispNs = $namespace
    Set targetNs = ..%ResolveNs(namespace)
    Set out.namespace = targetNs
    Set out.url = $get(url)
    Set rt = $select($get(resourceType) '= "":resourceType, 1:"Patient")
    Set out.resourceType = rt
    Set out.probes = []
    If $get(url) = "" {
        Set out.ok = 0
        Set out.error = "Pass `url` (endpoint cspUrl)."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIRQueryPerformance", out)
        Quit out
    }
    New $namespace
    Try {
        Set nsOk = 1
        Try { Set $namespace = targetNs } Catch  { Set nsOk = 0 }
        If 'nsOk {
            Set out.ok = 0
            Set out.error = "Cannot access namespace: " _ targetNs
        } ElseIf '##class(HS.FHIRServer.ServiceAdmin).EndpointExists(url) {
            Set out.ok = 0
            Set out.error = "No FHIR endpoint at '" _ url _ "' in namespace " _ targetNs _ "."
        } Else {
            Do ..%ProbeQuery(url, rt, "_summary=count", "count", out.probes)
            Do ..%ProbeQuery(url, rt, "_count=20", "page (20 results)", out.probes)
            Set out.ok = 1
            Set out.message = "Timed " _ out.probes.%Size() _ " CORE FHIR search(es) on " _ rt _ " (elapsed ms per probe)."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Set $namespace = dispNs
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetFHIRQueryPerformance", out)
    Quit out
}

/// Time one CORE FHIR search and append a probe result. Internal helper for
/// GetFHIRQueryPerformance.
ClassMethod %ProbeQuery(url As %String, rt As %String, query As %String, name As %String, probes As %DynamicArray) [ Internal ]
{
    Set p = {}
    Set p.name = name
    Set p.query = rt _ "?" _ query
    Set t0 = $zhorolog
    Set r = ..%Interaction(url, "GET", rt, query)
    Set ms = ($zhorolog - t0) * 1000
    If ms < 0 { Set ms = ms + 86400000 }
    Set p.ms = $normalize(ms, 1)
    Set p.httpStatus = $select($isobject(r) && r.%IsDefined("httpStatus"):r.httpStatus, 1:"")
    If $isobject(r), $isobject(r.body), r.body.%IsDefined("total") { Set p.total = r.body.total }
    Do probes.%Push(p)
    Quit
}

/// Background runner for LoadFHIRDirectory: loads each queued file in order,
/// updating the ^AgInt.FHIRLoad(jobId) progress global. JOB'd from
/// LoadFHIRDirectory (runs in the app namespace; switches per file). Internal.
ClassMethod %RunLoadJob(pJobId As %String, pUrl As %String, pNs As %String) [ Internal ]
{
    Try {
        Set ^AgInt.FHIRLoad(pJobId, "status") = "running"
        Set ^AgInt.FHIRLoad(pJobId, "started") = $zdatetime($horolog, 3, 1)
        ; High-precision start markers for throughput/bottleneck metrics.
        Set ^AgInt.FHIRLoad(pJobId, "startH") = $zhorolog
        Set totalRes = 0, totalBytes = 0
        Set seq = $order(^AgInt.FHIRLoad(pJobId, "file", ""))
        While seq '= "" {
            Set fp = ^AgInt.FHIRLoad(pJobId, "file", seq)
            Set ^AgInt.FHIRLoad(pJobId, "current") = $piece(fp, "/", *)
            Set fStart = $zhorolog
            Set r = ..%LoadOneFile(pUrl, fp, pNs)
            Set fDur = $zhorolog - fStart
            If fDur < 0 { Set fDur = fDur + 86400 }
            Set rcount = $select($isobject(r) && r.%IsDefined("resourceCount"):+r.resourceCount, 1:0)
            Set ok = ($isobject(r) && r.ok)
            ; Per-file metrics: filename, seconds, resourceCount, ok, bytes.
            Set bytes = "" Try { Set bytes = ##class(%Library.File).GetFileSize(fp) } Catch  {}
            Set totalBytes = totalBytes + (+bytes)
            Set ^AgInt.FHIRLoad(pJobId, "metric", seq) = $listbuild($piece(fp, "/", *), fDur, rcount, +ok, bytes)
            If ok {
                Set ^AgInt.FHIRLoad(pJobId, "done") = +$get(^AgInt.FHIRLoad(pJobId, "done")) + 1
                Set totalRes = totalRes + rcount
                Set ^AgInt.FHIRLoad(pJobId, "resources") = totalRes
            } Else {
                Set ^AgInt.FHIRLoad(pJobId, "failed") = +$get(^AgInt.FHIRLoad(pJobId, "failed")) + 1
                Set ne = +$get(^AgInt.FHIRLoad(pJobId, "errN")) + 1
                Set ^AgInt.FHIRLoad(pJobId, "errN") = ne
                If ne <= 25 {
                    Set etxt = $select($isobject(r) && r.%IsDefined("error"):r.error, 1:"unknown")
                    Set ^AgInt.FHIRLoad(pJobId, "err", ne) = $piece(fp, "/", *) _ ": " _ etxt
                }
            }
            Set seq = $order(^AgInt.FHIRLoad(pJobId, "file", seq))
        }
        Set ^AgInt.FHIRLoad(pJobId, "status") = "completed"
        Set ^AgInt.FHIRLoad(pJobId, "finished") = $zdatetime($horolog, 3, 1)
        Set ^AgInt.FHIRLoad(pJobId, "finishedH") = $zhorolog
        Do ..%RecordLoadRun(pJobId, pUrl, pNs, totalRes, totalBytes, "completed")
    } Catch ex {
        Set ^AgInt.FHIRLoad(pJobId, "status") = "error"
        Set ^AgInt.FHIRLoad(pJobId, "jobError") = $extract(ex.DisplayString(), 1, 300)
        Set ^AgInt.FHIRLoad(pJobId, "finishedH") = $zhorolog
        Do ..%RecordLoadRun(pJobId, pUrl, pNs, $get(totalRes), $get(totalBytes), "error")
    }
    Quit
}

/// Persist a durable history row for a finished load run into
/// AgenticInterop.Data.FHIRLoadRun. Best-effort: a metrics-history failure
/// must never affect the load itself. Internal helper for %RunLoadJob.
ClassMethod %RecordLoadRun(pJobId As %String, pUrl As %String, pNs As %String, pTotalRes As %Integer, pTotalBytes As %Integer, pStatus As %String) [ Internal ]
{
    Try {
        If '##class(%Dictionary.CompiledClass).%ExistsId("AgenticInterop.Data.FHIRLoadRun") Quit
        Set startH = +$get(^AgInt.FHIRLoad(pJobId, "startH"))
        Set finishH = +$get(^AgInt.FHIRLoad(pJobId, "finishedH"))
        If finishH = 0 { Set finishH = $zhorolog }
        Set dur = finishH - startH
        If dur < 0 { Set dur = dur + 86400 }
        Set rps = $select(dur > 0:$normalize(pTotalRes / dur, 2), 1:0)
        Set mb = $normalize((+pTotalBytes) / 1048576, 2)
        Do ##class(AgenticInterop.Data.FHIRLoadRun).Record(pNs, pUrl, pJobId, $get(^AgInt.FHIRLoad(pJobId, "started")), $get(^AgInt.FHIRLoad(pJobId, "finished")), $normalize(dur, 2), +$get(^AgInt.FHIRLoad(pJobId, "total")), +$get(^AgInt.FHIRLoad(pJobId, "done")), +$get(^AgInt.FHIRLoad(pJobId, "failed")), pTotalRes, rps, mb, pStatus)
    } Catch  {}
    Quit
}

/// Load one FHIR file (Bundle or single resource) into an endpoint via an
/// in-process transaction/create. Stream-parses the file so multi-MB
/// bundles do not hit the long-string limit. Switches into the target
/// namespace internally (restored on return). Internal.
ClassMethod %LoadOneFile(pUrl As %String, pFilePath As %String, pNs As %String) As %DynamicObject [ Internal ]
{
    Set r = {}
    New $namespace
    Set nsOk = 1
    Try { Set $namespace = pNs } Catch  { Set nsOk = 0 }
    If 'nsOk {
        Set r.ok = 0
        Set r.error = "cannot access namespace " _ pNs
        Quit r
    }
    Try {
        Set fs = ##class(%Stream.FileCharacter).%New()
        Set sc = fs.LinkToFile(pFilePath)
        If 'sc {
            Set r.ok = 0
            Set r.error = "cannot open file"
        } Else {
            Set obj = ##class(%DynamicAbstractObject).%FromJSON(fs)
            If '$isobject(obj) {
                Set r.ok = 0
                Set r.error = "JSON parse failed"
            } Else {
                Set svc = ##class(HS.FHIRServer.Service).EnsureInstance(pUrl)
                Set req = ##class(HS.FHIRServer.API.Data.Request).%New()
                Set req.RequestMethod = "POST"
                Set req.Json = obj
                Set rt = $select(obj.%IsDefined("resourceType"):obj.resourceType, 1:"")
                ; Resource count for throughput metrics: a Bundle ingests one
                ; resource per entry; a single resource counts as 1.
                Set r.resourceCount = $select((rt = "Bundle") && obj.%IsDefined("entry") && $isobject(obj.entry):obj.entry.%Size(), 1:1)
                ; Bundle -> POST to base (transaction); single resource -> POST to its type.
                Set req.RequestPath = $select(rt = "Bundle":"", 1:rt)
                Do svc.DispatchRequest(req, .resp)
                Set r.httpStatus = +resp.Status
                Set r.ok = ((+resp.Status >= 200) && (+resp.Status < 300))
                If 'r.ok {
                    Set r.error = "HTTP " _ resp.Status
                    If $isobject(resp.Json), resp.Json.%IsDefined("issue"), $isobject(resp.Json.issue) {
                        Set it = resp.Json.issue.%GetIterator()
                        If it.%GetNext(.k, .iss), $isobject(iss), iss.%IsDefined("diagnostics") {
                            Set r.error = $extract(iss.diagnostics, 1, 200)
                        }
                    }
                }
            }
        }
    } Catch ex {
        Set r.ok = 0
        Set r.error = $extract(ex.DisplayString(), 1, 200)
    }
    Quit r
}

}
