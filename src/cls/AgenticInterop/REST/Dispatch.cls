/// REST dispatcher for /api/agentic. Routes /health, /namespace, and the
/// /editor/* family to the matching Editor service classes.
///
/// UseSession=0 (class param) + UseCookies=0 + CSRFToken=0 + SessionScope=0
/// (CSP application). Every request authenticates via the Authorization
/// header — no session cookies, no CSRF tokens. Previous UseCookies=2
/// caused 401 on the second chat turn: the CSP gateway created a session
/// on the first SSE POST, then the browser sent the stale session cookie
/// on the second POST, and CSRF validation failed before OnPreDispatch ran.
///
/// Cross-cutting headers:
///   X-IRIS-Namespace — optional. If present and non-empty, Dispatch
///                      switches to that namespace for the request.
///                      Required restriction-7 path (namespace-agnostic).
Class AgenticInterop.REST.Dispatch Extends %CSP.REST
{

Parameter UseSession = 0;

Parameter HandleCorsRequest = 1;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
    <Route Url="/health"             Method="GET"  Call="Health" />
    <Route Url="/namespace"          Method="GET"  Call="Namespace" />
    <Route Url="/namespaces"         Method="GET"  Call="Namespaces" />
    <Route Url="/whoami"             Method="GET"  Call="WhoAmI" />
    <Route Url="/debug"              Method="GET"  Call="Debug" />
    <Route Url="/fhir/audit"         Method="GET"  Call="FHIRAudit" />
    <Route Url="/fhir/upload"        Method="GET"    Call="FHIRUploadList" />
    <Route Url="/fhir/upload"        Method="POST"   Call="FHIRUpload" />
    <Route Url="/fhir/upload"        Method="DELETE" Call="FHIRUploadClear" />
    <Route Url="/fhir/load/status"   Method="GET"    Call="FHIRLoadStatus" />
    <Route Url="/fhir/load/history"  Method="DELETE" Call="FHIRLoadHistoryClear" />

    <!-- Registries (for UI dropdowns) -->
    <!-- Class source viewer (read-only UDL for the inline panel) -->
    <Route Url="/source/:class"      Method="GET"  Call="GetSource" />

    <Route Url="/registry/agents"    Method="GET"  Call="ListAgents" />
    <Route Url="/registry/mcps"      Method="GET"  Call="ListMCPs" />
    <Route Url="/registry/toolsets"  Method="GET"  Call="ListToolSets" />
    <Route Url="/registry/skills"    Method="GET"  Call="ListSkills" />

    <!-- Agent CRUD -->
    <Route Url="/editor/agent/:class"           Method="GET"    Call="GetAgent" />
    <Route Url="/editor/agent/:class"           Method="PUT"    Call="SaveAgent" />
    <Route Url="/editor/agent"                  Method="POST"   Call="CreateAgent" />
    <Route Url="/editor/agent/:class"           Method="DELETE" Call="DeleteAgent" />
    <Route Url="/editor/agent/:class/reset"     Method="POST"   Call="ResetAgent" />

    <!-- MCP CRUD -->
    <Route Url="/editor/mcp/:class"             Method="GET"    Call="GetMCP" />
    <Route Url="/editor/mcp/:class"             Method="PUT"    Call="SaveMCP" />
    <Route Url="/editor/mcp"                    Method="POST"   Call="CreateMCP" />
    <Route Url="/editor/mcp/:class"             Method="DELETE" Call="DeleteMCP" />
    <Route Url="/editor/mcp/:class/reset"       Method="POST"   Call="ResetMCP" />

    <!-- ToolSet CRUD -->
    <Route Url="/editor/toolset/:class"         Method="GET"    Call="GetToolSet" />
    <Route Url="/editor/toolset/:class"         Method="PUT"    Call="SaveToolSet" />
    <Route Url="/editor/toolset"                Method="POST"   Call="CreateToolSet" />
    <Route Url="/editor/toolset/:class"         Method="DELETE" Call="DeleteToolSet" />
    <Route Url="/editor/toolset/:class/reset"   Method="POST"   Call="ResetToolSet" />

    <!-- Tool providers — list all %AI.Tool subclasses for the ToolSet editor -->
    <Route Url="/editor/tool-providers"         Method="GET"    Call="ListToolProviders" />

    <!-- Tool CRUD (one tool entry inside a ToolSet's XData Definition) -->
    <Route Url="/editor/tool/:toolset/:name"    Method="GET"    Call="GetTool" />
    <Route Url="/editor/tool/:toolset/:name"    Method="PUT"    Call="SaveTool" />
    <Route Url="/editor/tool/:toolset"          Method="POST"   Call="CreateTool" />
    <Route Url="/editor/tool/:toolset/:name"    Method="DELETE" Call="DeleteTool" />
    <Route Url="/editor/tool/:toolset/:name/dryrun" Method="POST" Call="DryRunTool" />

    <!-- Connection CRUD + secret + test (LLM provider config). Modeled
         on Catalog.Connections from new-interoperability-health: name-
         keyed, %Wallet.KeyValue secrets, %AI.Provider.Create + ChatComplete
         for the live test. -->
    <Route Url="/connections"                   Method="GET"    Call="ListConnections" />
    <Route Url="/connections"                   Method="POST"   Call="CreateConnection" />
    <Route Url="/connections/:name"             Method="GET"    Call="GetConnection" />
    <Route Url="/connections/:name"             Method="PUT"    Call="SaveConnection" />
    <Route Url="/connections/:name"             Method="DELETE" Call="DeleteConnection" />
    <Route Url="/connections/:name/secret"      Method="POST"   Call="SaveConnectionSecret" />
    <Route Url="/connections/:name/test"        Method="POST"   Call="TestConnection" />

    <!-- Chatbot config layer: bind a chatbot surface to an %AI.Agent.
         The chat surface resolves its agent from the chatbot Key at
         request time, so changing the agent is a one-row config edit. -->
    <Route Url="/chatbots"                      Method="GET"    Call="ListChatbots" />
    <Route Url="/chatbots"                      Method="POST"   Call="CreateChatbot" />
    <Route Url="/chatbots/:key"                 Method="GET"    Call="GetChatbot" />
    <Route Url="/chatbots/:key"                 Method="PUT"    Call="SaveChatbot" />
    <Route Url="/chatbots/:key"                 Method="DELETE" Call="DeleteChatbot" />

    <!-- Saved Integration Spec Questionnaire runs. Each row holds both the
         structured answers and the generated specification text, so a run
         can be reloaded into the form or re-sent to the agent. -->
    <Route Url="/spec/responses"                Method="GET"    Call="ListSpecResponses" />
    <Route Url="/spec/responses"                Method="POST"   Call="SaveSpecResponse" />
    <Route Url="/spec/responses/:id"            Method="GET"    Call="GetSpecResponse" />
    <Route Url="/spec/responses/:id"            Method="DELETE" Call="DeleteSpecResponse" />
    <Route Url="/spec/responses/:id/favorite"   Method="POST"   Call="FavoriteSpecResponse" />

    <!-- Phase 2 chat — non-streaming single turn against the default
         (or named) Connection. Kept for callers that don't want SSE. -->
    <Route Url="/chat"                          Method="POST"   Call="Chat" />
    <!-- Phase 3 chat — Server-Sent Events stream. Token-by-token text
         + tool-call lifecycle events as the model produces them. -->
    <Route Url="/chat/stream"                   Method="POST"   Call="ChatStream" />

    <!-- Phase 5 catalog admin: search_ens / search_hs vector index
         status + rebuild. The rebuild call is synchronous and can
         run ~30s on a stock IRIS for Health install. -->
    <Route Url="/catalog/status"                Method="GET"    Call="CatalogStatus" />
    <Route Url="/catalog/rebuild"               Method="POST"   Call="CatalogRebuild" />
    <Route Url="/catalog/browse"                Method="GET"    Call="CatalogBrowse" />
    <Route Url="/catalog/search"                Method="POST"   Call="CatalogSearch" />

    <!-- Phase 7 audit trail viewer: list recent audit rows with
         filters, plus distinct kinds for dropdowns. -->
    <Route Url="/audit/log"                     Method="GET"    Call="AuditList" />
    <Route Url="/audit/kinds"                   Method="GET"    Call="AuditKinds" />

    <!-- Tokens log: per-prompt token + tool spend, one row per chat turn. -->
    <Route Url="/tokens"                        Method="GET"    Call="TokenUsageList" />

    <!-- Transformation Catalog: read-only inventory of shipped HS.*
         transformation classes organized by pipeline direction. -->
    <Route Url="/transforms/inventory"          Method="GET"    Call="TransformInventory" />
    <Route Url="/transforms/dtl-fields"         Method="GET"    Call="DTLFields" />
    <Route Url="/transforms/hl7-fields"         Method="GET"    Call="HL7Fields" />
    <Route Url="/transforms/field-trace/rebuild" Method="POST"  Call="FieldTraceRebuild" />
    <Route Url="/transforms/field-trace/status"  Method="GET"   Call="FieldTraceStatus" />
    <Route Url="/transforms/field-trace"         Method="GET"   Call="FieldTraceQuery" />

    <!-- Cleanup: stop stuck productions and delete test artifacts. -->
    <Route Url="/cleanup/productions"           Method="POST"   Call="CleanupProductions" />
    <Route Url="/cleanup/artifacts"             Method="GET"    Call="ListCustomArtifacts" />
    <Route Url="/cleanup/artifacts"             Method="DELETE" Call="DeleteCustomArtifacts" />

    <!-- Observer: behind-the-scenes live feed for VP demos. The
         observer page tails ^AgInt.LiveFeed in real time, showing
         every tool call, RAG search, and approval gate as the agent
         works. Separate SSE stream from the chat endpoint. -->
    <Route Url="/observer/sessions"             Method="GET"    Call="ObserverSessions" />
    <Route Url="/observer/stream"               Method="POST"   Call="ObserverStream" />
    <Route Url="/observer/purge"                Method="POST"   Call="ObserverPurge" />
</Routes>
}

/// Auth + namespace + audit gate. Per restriction #3 every request must
/// belong to an authenticated user; per the audit requirement every call
/// is logged to AgenticInterop.Data.AuditLog with username, namespace,
/// session id, and timing.
ClassMethod OnPreDispatch(pUrl As %String, pMethod As %String, ByRef pContinue As %Boolean) As %Status
{
    Set pContinue = 1
    Set %agenticReqStart = $zhorolog
    Set %agenticPath = pUrl
    Set %agenticMethod = pMethod
    Set %agenticReqSize = +$get(%request.CgiEnvs("CONTENT_LENGTH"))

    // /debug bypasses auth so we can inspect what the browser actually
    // sends (cookies, headers, $username) without 401-blocking.
    If pUrl = "/debug" { Quit $$$OK }

    // Reject anonymous. CSP web app is UnauthenticatedEnabled=0 so this
    // should already be blocked at the gateway, but defense in depth —
    // never trust the gateway alone. ($username is a special variable;
    // do not wrap it in $get.)
    Set user = $username
    If (user = "") || (user = "UnknownUser") {
        Set %response.Status = "401 Unauthorized"
        Do %response.SetHeader("WWW-Authenticate", "Basic realm=""agentic_interop""")
        Do ..%WriteJSON({"error": "Authentication required"})
        Set pContinue = 0
        Do ..AuditEnd(401, "anonymous request rejected")
    }

    If pContinue {
        // Phase 3 access gate. The X-IRIS-Namespace header names the
        // namespace the chat (and its tools) should logically operate
        // on. We DO NOT switch $namespace permanently here — the
        // dispatch class is only compiled in the install namespace
        // (HSCUSTOM by default), so a permanent switch breaks every
        // request afterward. Instead we probe access in a New'd
        // stack frame and surface 400 (namespace doesn't exist) /
        // 403 (user has no access) before the route runs. Per-tool
        // namespace switching is the layer that actually changes
        // execution context inside chat.
        Set targetNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE"))
        If targetNs '= "", targetNs '= $namespace {
            Set exists = ..NamespaceExists(targetNs)
            If 'exists {
                Set %response.Status = "400 Bad Request"
                Do ..%WriteJSON({"error": "Namespace does not exist", "namespace": (targetNs)})
                Set pContinue = 0
                Do ..AuditEnd(400, "missing namespace " _ targetNs)
            } ElseIf '..NamespaceAccessible(targetNs) {
                Set %response.Status = "403 Forbidden"
                Do %response.SetHeader("Content-Type", "application/json")
                Do ..%WriteJSON({"error": "User does not have access to this namespace", "namespace": (targetNs), "user": (user)})
                Set pContinue = 0
                Do ..AuditEnd(403, "no access to namespace " _ targetNs _ " for user " _ user)
            }
        }
    }

    Quit $$$OK
}

/// True iff a namespace by that name is configured on this instance.
/// Uses the system %SYS.Namespace API; runs in %SYS to avoid leaking
/// the caller's current namespace context. Used only by the access
/// gate in OnPreDispatch — not exposed via REST.
ClassMethod NamespaceExists(pName As %String) As %Boolean
{
    If pName = "" Quit 0
    Set ok = 0
    New $namespace
    Set $namespace = "%SYS"
    Try { Set ok = ##class(%SYS.Namespace).Exists(pName) } Catch  { Set ok = 0 }
    Quit ok
}

/// True iff the AUTHENTICATED user has permission to use pName as
/// their active namespace.
///
/// Why this can't be a "Set $namespace = pName" probe: the
/// /api/agentic CSP application elevates to %ISCMgtPortal at request
/// dispatch (see module.xml), so $namespace assignments succeed for
/// any namespace %ISCMgtPortal can reach — bypassing the calling
/// user's actual privileges. We instead inspect the user's BASE
/// roles (Security.Users.Roles) and walk each role's %DB_<db>:Read
/// resources, checking if any of them grants the namespace's
/// default global database. Equivalent to "would this user be able
/// to switch to this namespace from the Management Portal as
/// themselves." %All in the user's roles is treated as a master
/// key.
ClassMethod NamespaceAccessible(pName As %String) As %Boolean
{
    If pName = "" Quit 0
    Set ok = 0
    New $namespace
    Set $namespace = "%SYS"
    Try {
        // 1. Walk Config.Namespaces -> Globals (default DB name) ->
        //    Config.Databases -> Directory (file path) ->
        //    SYS.Database -> ResourceName. Resource isn't a column on
        //    Config.Databases — it lives on the SYS.Database wrapper.
        Set sc = ##class(Config.Namespaces).Get(pName, .nsProps)
        If $$$ISERR(sc) { Quit }
        Set defaultDB = $get(nsProps("Globals"))
        If defaultDB = "" { Quit }
        Set sc = ##class(Config.Databases).Get(defaultDB, .dbProps)
        If $$$ISERR(sc) { Quit }
        Set directory = $get(dbProps("Directory"))
        If directory = "" { Quit }
        Set db = ##class(SYS.Database).%OpenId(directory)
        If '$isobject(db) { Quit }
        Set requiredResource = db.ResourceName
        If requiredResource = "" {
            // No resource gates this database — open access.
            Set ok = 1
            Quit
        }

        // 2. _SYSTEM and any user with %All are free-passers. Read
        //    BASE roles directly from Security.Users so the CSP app's
        //    %ISCMgtPortal elevation doesn't mask user privileges.
        Set userRoles = ""
        Set ru = ##class(%SQL.Statement).%ExecDirect(,"SELECT Roles FROM Security.Users WHERE Name = ?", $username)
        If ru.%Next() { Set userRoles = ru.%Get("Roles") }
        If userRoles [ "%All" { Set ok = 1 Quit }

        // 3. For each role, check if it grants <requiredResource>:Read.
        //    Security.Roles.Resources format: "Res1:perm1,Res2:perm2".
        For i=1:1:$LENGTH(userRoles, ",") {
            Set role = $ZSTRIP($PIECE(userRoles, ",", i), "<>W")
            If role = "" { Continue }
            Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT Resources FROM Security.Roles WHERE Name = ?", role)
            If 'rs.%Next() { Continue }
            Set resList = rs.%Get("Resources")
            For j=1:1:$LENGTH(resList, ",") {
                Set entry = $ZSTRIP($PIECE(resList, ",", j), "<>W")
                If entry = "" { Continue }
                Set resName = $PIECE(entry, ":", 1)
                Set resPerm = $PIECE(entry, ":", 2)
                If (resName = requiredResource) && (resPerm [ "R") {
                    Set ok = 1
                    Quit
                }
            }
            If ok { Quit }
        }
    } Catch  {
        Set ok = 0
    }
    Quit ok
}

/// Debug endpoint — anonymous-allowed. Dumps what the gateway gave us.
ClassMethod Debug() As %Status
{
    Set info = {}
    Set info.username = $username
    Set info.namespace = $namespace
    Try { Set info.sessionId = %session.SessionId } Catch { Set info.sessionId = "<n/a>" }
    Set info.cookieRaw = $get(%request.CgiEnvs("HTTP_COOKIE"))
    Set info.authorization = $get(%request.CgiEnvs("HTTP_AUTHORIZATION"))
    Set info.userAgent = $get(%request.CgiEnvs("HTTP_USER_AGENT"))
    Set info.referer = $get(%request.CgiEnvs("HTTP_REFERER"))
    Set info.origin = $get(%request.CgiEnvs("HTTP_ORIGIN"))
    Set info.requestUrl = $get(%request.CgiEnvs("REQUEST_URI"))
    Set info.remoteAddr = $get(%request.CgiEnvs("REMOTE_ADDR"))
    Set info.cookies = []
    Set raw = info.cookieRaw
    If raw '= "" {
        For i=1:1:$LENGTH(raw, ";") {
            Set kv = $ZSTRIP($PIECE(raw, ";", i), "<>W")
            If kv '= "" { Do info.cookies.%Push(kv) }
        }
    }
    Do ..%WriteJSON(info)
    Quit $$$OK
}

/// Called from the route handlers (or implicitly when OnPreDispatch
/// rejects) to write the audit row. Safe to call multiple times — only
/// the first call is recorded.
ClassMethod AuditEnd(pStatus As %Integer = 0, pError As %String = "")
{
    If $get(%agenticAudited, 0) { Quit }
    Set %agenticAudited = 1
    Set duration = 0
    If $get(%agenticReqStart) '= "" {
        Set duration = $fnumber(($zhorolog - %agenticReqStart) * 1000, "", 0)
    }
    Set path = $get(%agenticPath, "")
    Set method = $get(%agenticMethod, "")
    Set kind = ##class(AgenticInterop.Data.AuditLog).ClassifyPath(path)
    Set sessionId = ""
    Try { Set sessionId = %session.SessionId } Catch {}
    Set reqSize = +$get(%agenticReqSize)
    Try {
        Do ##class(AgenticInterop.Data.AuditLog).Record(kind, $username, $namespace, sessionId, method, path, pStatus, reqSize, 0, duration, pError)
    } Catch {}
}

/// Common JSON response writer. Audit-logs the request as it returns.
/// Note: %response.Status is multi-dimensional — read it with explicit
/// fallback through a Try, never $get.
ClassMethod %WriteJSON(pObj As %DynamicObject) As %Status
{
    Set %response.ContentType = "application/json"
    Do pObj.%ToJSON()
    Set status = 200
    Try { Set s = %response.Status If s '= "" { Set status = +s } } Catch {}
    Do ..AuditEnd(status)
    Quit $$$OK
}

ClassMethod Health() As %Status
{
    Do ..%WriteJSON({
        "ok": 1,
        "namespace": ($namespace),
        "username": ($username),
        "agentClass": "AgenticInterop.Agent.HealthInterop"
    })
    Quit $$$OK
}

ClassMethod Namespace() As %Status
{
    Do ..%WriteJSON({"namespace": ($namespace)})
    Quit $$$OK
}

/// GET /namespaces — the namespaces the authenticated user can actually
/// access, for the chat header's namespace picker. Each is gated by the
/// same NamespaceAccessible check used by OnPreDispatch, so the picker
/// only offers namespaces the user is allowed to operate in (respecting
/// namespace boundaries). System namespaces are excluded.
ClassMethod Namespaces() As %Status
{
    Set out = {}
    Set out.current = $namespace
    Set out.namespaces = []
    ; If the requesting chatbot's agent uses the FHIR Server MCP, restrict
    ; the picker to namespaces that actually have a FHIR Server installed
    ; (FHIR-enabled foundation namespaces). Other chatbots see all the
    ; namespaces the user can access.
    Set fhirOnly = 0
    Set ck = ""
    Try { Set ck = %request.Get("chatbot", "") } Catch  {}
    If ck '= "" {
        Set cb = ##class(AgenticInterop.Data.Chatbot).GetByKey(ck)
        If $isobject(cb), cb.AgentClass '= "" {
            Set mcps = ""
            Try { Set mcps = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMCPS(cb.AgentClass) } Catch  {}
            If mcps [ "AgenticInterop.MCP.FHIRServer" { Set fhirOnly = 1 }
        }
    }
    Set out.fhirOnly = ''fhirOnly
    Do ..collectNamespaces(out.namespaces, fhirOnly)
    Do ..%WriteJSON(out)
    Quit $$$OK
}

/// Fill pArr with the non-system namespaces the user can access. When
/// pFhirOnly, only namespaces with a FHIR Server installed are included.
/// Runs in a New'd %SYS frame so the dispatch namespace is restored on
/// return (before the caller writes JSON / audits in the install namespace).
ClassMethod collectNamespaces(pArr As %DynamicArray, pFhirOnly As %Boolean = 0) [ Internal ]
{
    New $namespace
    Set $namespace = "%SYS"
    Set sysNs = ",%SYS,%ALL,IRISSYS,IRISTEMP,IRISLIB,IRISLOCALDATA,HSLIB,HSSYS,HSSYSLOCALTEMP,DOCBOOK,ENSLIB,"
    Set list = ""
    Do List^%SYS.NAMESPACE(.list)
    Set ns = $order(list(""))
    While ns '= "" {
        If sysNs '[ ("," _ $zconvert(ns, "U") _ ",") {
            If ..NamespaceAccessible(ns) {
                If 'pFhirOnly {
                    Do pArr.%Push(ns)
                } ElseIf ..IsFhirNamespace(ns) {
                    Do pArr.%Push(ns)
                }
            }
        }
        Set ns = $order(list(ns))
    }
}

/// True iff the namespace is a FHIR FOUNDATION namespace — i.e. it is
/// FHIR-enabled (HS.FHIRServer available) AND has REGISTERED FHIR metadata
/// packages (HS.FHIRMeta.Storage.Package). Registered packages are the
/// DURABLE foundation signal: it survives endpoint churn (endpoints are
/// created/deleted, but a foundation namespace stays a foundation namespace),
/// and it correctly excludes app namespaces like HSCUSTOM that merely have
/// the package FILES on disk but none registered. An existing endpoint also
/// counts (fallback). This is the filter for the FHIR chatbot's namespace
/// picker. See Tool.FHIRServer.DiscoverFHIRNamespaces for endpoint listing.
ClassMethod IsFhirNamespace(pName As %String) As %Boolean [ Internal ]
{
    Set ok = 0
    Try {
        New $namespace
        Set $namespace = pName
        If ##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRServer.ServiceAdmin") {
            ; Primary (durable): registered FHIR metadata packages, via the
            ; CORE method HS.FHIRMeta.Storage.Package.GetAllPackages() (NOT raw
            ; SQL on the storage table). A foundation namespace has >=1
            ; registered package; an app namespace like HSCUSTOM has the package
            ; files on disk but none registered.
            Try {
                If ##class(%Dictionary.CompiledClass).%ExistsId("HS.FHIRMeta.Storage.Package") {
                    Set pkgs = ##class(HS.FHIRMeta.Storage.Package).GetAllPackages()
                    If $isobject(pkgs), (pkgs.Count() > 0) { Set ok = 1 }
                }
            } Catch  {}
            ; Fallback: an installed endpoint also marks a FHIR namespace (CORE).
            If 'ok {
                Set el = ##class(HS.FHIRServer.ServiceAdmin).GetEndpointList()
                If $listvalid(el), $listlength(el) > 0 { Set ok = 1 }
            }
        }
    } Catch  { Set ok = 0 }
    Quit ok
}

/// GET /fhir/audit — FHIR Server performance + storage audit for the
/// namespace named by the X-IRIS-Namespace header (or the dispatch namespace).
/// Combines the CORE-based metrics tools (Tool.FHIRServer.GetFHIRServerStats +
/// GetFHIRLoadMetrics) with the discovered endpoint, for the left-menu Audit
/// panel injected into the FHIR Management page.
ClassMethod FHIRAudit() As %Status
{
    Set out = {}
    Set reqNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE"))
    ; The FHIR Server lives in a FHIR FOUNDATION namespace (e.g. FHIR), never
    ; the dispatch/app namespace (HSCUSTOM). Resolve the audit target to a FHIR
    ; namespace regardless of what the picker/dispatch passes:
    ;   1. honor the requested namespace only if it is itself a FHIR namespace;
    ;   2. else prefer a namespace that actually has a FHIR endpoint;
    ;   3. else any FHIR foundation namespace (registered metadata packages);
    ;   4. last resort, the requested/dispatch namespace.
    Set ns = ""
    If (reqNs '= ""), ..IsFhirNamespace(reqNs) { Set ns = reqNs }
    If ns = "" {
        Try {
            Set disc = ##class(AgenticInterop.Tool.FHIRServer).DiscoverFHIRNamespaces()
            If $isobject(disc), $isobject(disc.namespaces), (disc.namespaces.%Size() > 0) { Set ns = disc.namespaces.%Get(0).namespace }
        } Catch  {}
    }
    If ns = "" {
        Set cand = []
        Do ..collectNamespaces(cand, 1)
        If cand.%Size() > 0 { Set ns = cand.%Get(0) }
    }
    If ns = "" { Set ns = $select(reqNs '= "":reqNs, 1:$namespace) }
    Set out.namespace = ns
    Set out.requestedNamespace = reqNs
    Set out.endpoints = []
    Set url = ""
    Try {
        Set eps = ##class(AgenticInterop.Tool.FHIRServer).ListFHIREndpoints(ns)
        If $isobject(eps), $isobject(eps.endpoints) {
            Set it = eps.endpoints.%GetIterator()
            While it.%GetNext(.k, .e) {
                Do out.endpoints.%Push(e)
                If (url = "") && $isobject(e) && e.%IsDefined("url") { Set url = e.url }
            }
        }
    } Catch  {}
    Set out.endpointUrl = url
    Try { Set out.stats = ##class(AgenticInterop.Tool.FHIRServer).GetFHIRServerStats(url, "", ns) } Catch ex { Set out.statsError = $extract(ex.DisplayString(), 1, 300) }
    Try { Set out.loadMetrics = ##class(AgenticInterop.Tool.FHIRServer).GetFHIRLoadMetrics("", ns) } Catch ex { Set out.loadError = $extract(ex.DisplayString(), 1, 300) }
    Set out.ok = 1
    Do ..%WriteJSON(out)
    Quit $$$OK
}

/// GET /fhir/load/status?jobId=... — live progress for a background FHIR
/// directory load (started by LoadFHIRDirectory). The chat surface polls this
/// to animate a progress bar. Reads the ^AgInt.FHIRLoad progress global
/// directly (it lives in the dispatch namespace where the loader writes it),
/// so frequent polling does not spam the Observer/tool log.
/// Returns: { ok, found, jobId, status, total, filesDone, filesFailed, done,
/// percent, current?, error? }. status: queued|running|completed|error.
ClassMethod FHIRLoadStatus() As %Status
{
    Set out = {}
    Set jobId = $get(%request.Data("jobId", 1))
    Set out.jobId = jobId
    If jobId = "" {
        Set out.ok = 0, out.found = 0, out.error = "Pass jobId."
        Do ..%WriteJSON(out)
        Quit $$$OK
    }
    If '$data(^AgInt.FHIRLoad(jobId)) {
        Set out.ok = 1, out.found = 0, out.status = "unknown", out.percent = 0
        Do ..%WriteJSON(out)
        Quit $$$OK
    }
    Set out.ok = 1, out.found = 1
    Set out.status = $get(^AgInt.FHIRLoad(jobId, "status"))
    Set out.total = +$get(^AgInt.FHIRLoad(jobId, "total"))
    Set out.filesDone = +$get(^AgInt.FHIRLoad(jobId, "done"))
    Set out.filesFailed = +$get(^AgInt.FHIRLoad(jobId, "failed"))
    Set out.current = $get(^AgInt.FHIRLoad(jobId, "current"))
    Set done = out.filesDone + out.filesFailed
    Set out.done = done
    Set out.percent = $select(out.total > 0:$normalize((done / out.total) * 100, 0), 1:0)
    If $get(^AgInt.FHIRLoad(jobId, "jobError")) '= "" { Set out.error = ^AgInt.FHIRLoad(jobId, "jobError") }
    Do ..%WriteJSON(out)
    Quit $$$OK
}

/// DELETE /fhir/load/history — clear all FHIR load metrics so the Audit panel
/// starts fresh: kills the in-memory progress global (^AgInt.FHIRLoad, which
/// feeds "last load" ingestion metrics) and empties the durable run-history
/// table (Data.FHIRLoadRun). Does NOT touch any loaded FHIR resources — only
/// the metrics/history about past loads.
ClassMethod FHIRLoadHistoryClear() As %Status
{
    Set out = {}
    Try {
        Kill ^AgInt.FHIRLoad
        Set sc = ##class(AgenticInterop.Data.FHIRLoadRun).%KillExtent()
        Set out.ok = 1
        Set out.message = "FHIR load metrics and history cleared."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 300)
    }
    Do ..%WriteJSON(out)
    Quit $$$OK
}

/// Server-readable staging folder for uploaded FHIR files. Lives under the
/// instance manager directory (mgr/Temp), owned by the IRIS process, so the
/// FHIR server's DataLoader (LoadFHIRDirectory) can read it. NOT the FHIR
/// repository — just a folder on the server filesystem.
ClassMethod FHIRUploadDir() As %String
{
    Quit ##class(%Library.File).NormalizeDirectory("Temp/agentic-fhir-upload", ##class(%Library.File).ManagerDirectory())
}

/// POST /fhir/upload — receive uploaded FHIR JSON files (multipart/form-data)
/// and write them to the server staging folder. Does NOT POST them into the
/// FHIR repository; loading the folder into a FHIR server is a separate step
/// (the FHIR Assistant's LoadFHIRDirectory). Returns the folder path + files.
ClassMethod FHIRUpload() As %Status
{
    Set out = {}
    Set dir = ..FHIRUploadDir()
    Set out.directory = dir
    Set out.files = []
    Set out.failed = []
    Set count = 0
    Try {
        Do ##class(%Library.File).CreateDirectoryChain(dir)
        Set name = ""
        For  {
            Set name = %request.NextMimeData(name)
            Quit:name=""
            Set n = %request.CountMimeData(name)
            For i=1:1:n {
                Set stream = %request.GetMimeData(name, "", i)
                If '$isobject(stream) { Continue }
                Set fn = stream.FileName
                If fn = "" { Set fn = name }
                ; basename + sanitize for the filesystem
                Set fn = $piece(fn, "/", *) Set fn = $piece(fn, "\", *)
                Set fn = $translate(fn, "<>:""|?*", "_______")
                If fn = "" { Set fn = "upload_" _ (count + 1) _ ".json" }
                Set ok = 0
                Try {
                    Set file = ##class(%Stream.FileBinary).%New()
                    Set file.Filename = dir _ fn
                    Do stream.Rewind()
                    Do file.CopyFrom(stream)
                    Set ok = file.%Save()
                } Catch  { Set ok = 0 }
                If ok {
                    Set f = {}
                    Set f.name = fn
                    Set f.bytes = file.Size
                    Do out.files.%Push(f)
                    Set count = count + 1
                } Else {
                    Do out.failed.%Push(fn)
                }
            }
        }
        Set out.uploaded = count
        Set out.ok = 1
        Set out.message = count _ " file(s) staged in " _ dir _ ". To load them, ask the FHIR Assistant to load this directory into the FHIR server (it uses LoadFHIRDirectory; infrastructure bundles load first)."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ..%WriteJSON(out)
    Quit $$$OK
}

/// GET /fhir/upload — list the staged FHIR files in the server folder.
ClassMethod FHIRUploadList() As %Status
{
    Set out = {}
    Set dir = ..FHIRUploadDir()
    Set out.directory = dir
    Set out.files = []
    Set total = 0, bytes = 0
    Try {
        If ##class(%Library.File).DirectoryExists(dir) {
            Set rs = ##class(%ResultSet).%New("%File:FileSet")
            Do rs.Execute(dir, "*.json", "Name", 1)
            While rs.Next() {
                Set f = {}
                Set f.name = rs.Get("ItemName")
                Set f.bytes = +rs.Get("Size")
                Do out.files.%Push(f)
                Set total = total + 1, bytes = bytes + (+rs.Get("Size"))
            }
        }
        Set out.total = total
        Set out.totalMB = $normalize(bytes / 1048576, 2)
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ..%WriteJSON(out)
    Quit $$$OK
}

/// DELETE /fhir/upload — clear the staged FHIR files from the server folder.
ClassMethod FHIRUploadClear() As %Status
{
    Set out = {}
    Set dir = ..FHIRUploadDir()
    Set out.directory = dir
    Set deleted = 0
    Try {
        If ##class(%Library.File).DirectoryExists(dir) {
            Set rs = ##class(%ResultSet).%New("%File:FileSet")
            Do rs.Execute(dir, "*.json", "Name", 1)
            Set list = ""
            While rs.Next() { Set list = list _ $listbuild(rs.Get("Name")) }
            For li=1:1:$listlength(list) { If ##class(%Library.File).Delete($list(list, li)) { Set deleted = deleted + 1 } }
        }
        Set out.deleted = deleted
        Set out.ok = 1
        Set out.message = "Cleared " _ deleted _ " file(s) from " _ dir _ "."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ..%WriteJSON(out)
    Quit $$$OK
}

ClassMethod WhoAmI() As %Status
{
    // Used by inject.js to verify the IRIS session before showing any UI.
    // Returns 200 only when the session is real and a username is bound.
    Set sessionId = ""
    Try { Set sessionId = %session.SessionId } Catch {}
    Do ..%WriteJSON({
        "ok": 1,
        "username": ($username),
        "namespace": ($namespace),
        "sessionId": (sessionId)
    })
    Quit $$$OK
}

ClassMethod GetSource(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.SourceService).Get(%response, pClass)
}

ClassMethod ListAgents() As %Status
{
    Quit ##class(AgenticInterop.Editor.RegistryService).ListAgents(%response, %request)
}

ClassMethod ListMCPs() As %Status
{
    Quit ##class(AgenticInterop.Editor.RegistryService).ListMCPs(%response, %request)
}

ClassMethod ListToolSets() As %Status
{
    Quit ##class(AgenticInterop.Editor.RegistryService).ListToolSets(%response, %request)
}

ClassMethod ListSkills() As %Status
{
    Quit ##class(AgenticInterop.Editor.RegistryService).ListSkills(%response, %request)
}

ClassMethod GetAgent(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.AgentService).Get(%response, pClass)
}

ClassMethod SaveAgent(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.AgentService).Save(%response, pClass, %request.Content)
}

ClassMethod CreateAgent() As %Status
{
    Quit ##class(AgenticInterop.Editor.AgentService).Create(%response, %request.Content)
}

ClassMethod DeleteAgent(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.AgentService).Delete(%response, pClass)
}

ClassMethod GetMCP(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.MCPService).Get(%response, pClass)
}

ClassMethod SaveMCP(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.MCPService).Save(%response, pClass, %request.Content)
}

ClassMethod CreateMCP() As %Status
{
    Quit ##class(AgenticInterop.Editor.MCPService).Create(%response, %request.Content)
}

ClassMethod DeleteMCP(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.MCPService).Delete(%response, pClass)
}

ClassMethod ResetMCP(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.MCPService).Reset(%response, pClass)
}

ClassMethod ResetAgent(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.AgentService).Reset(%response, pClass)
}

ClassMethod ResetToolSet(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolSetService).Reset(%response, pClass)
}

ClassMethod ListToolProviders() As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolSetService).ListProviders(%response)
}

ClassMethod GetToolSet(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolSetService).Get(%response, pClass)
}

ClassMethod SaveToolSet(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolSetService).Save(%response, pClass, %request.Content)
}

ClassMethod CreateToolSet() As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolSetService).Create(%response, %request.Content)
}

ClassMethod DeleteToolSet(pClass As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolSetService).Delete(%response, pClass)
}

ClassMethod GetTool(pToolSet As %String, pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolService).Get(%response, pToolSet, pName)
}

ClassMethod SaveTool(pToolSet As %String, pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolService).Save(%response, pToolSet, pName, %request.Content)
}

ClassMethod CreateTool(pToolSet As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolService).Create(%response, pToolSet, %request.Content)
}

ClassMethod DeleteTool(pToolSet As %String, pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolService).Delete(%response, pToolSet, pName)
}

ClassMethod DryRunTool(pToolSet As %String, pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ToolService).DryRun(%response, pToolSet, pName, %request.Content)
}

ClassMethod ListConnections() As %Status
{
    Quit ##class(AgenticInterop.Editor.ConnectionService).List(%response)
}

ClassMethod GetConnection(pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ConnectionService).Get(%response, pName)
}

ClassMethod CreateConnection() As %Status
{
    Quit ##class(AgenticInterop.Editor.ConnectionService).Create(%response, %request.Content)
}

ClassMethod SaveConnection(pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ConnectionService).Save(%response, pName, %request.Content)
}

ClassMethod DeleteConnection(pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ConnectionService).Delete(%response, pName)
}

ClassMethod SaveConnectionSecret(pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ConnectionService).SaveSecret(%response, pName, %request.Content)
}

ClassMethod TestConnection(pName As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ConnectionService).Test(%response, pName)
}

ClassMethod ListChatbots() As %Status
{
    Quit ##class(AgenticInterop.Editor.ChatbotService).List(%response)
}

ClassMethod GetChatbot(pKey As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ChatbotService).Get(%response, pKey)
}

ClassMethod CreateChatbot() As %Status
{
    Quit ##class(AgenticInterop.Editor.ChatbotService).Save(%response, "", %request.Content)
}

ClassMethod SaveChatbot(pKey As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ChatbotService).Save(%response, pKey, %request.Content)
}

ClassMethod DeleteChatbot(pKey As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.ChatbotService).Delete(%response, pKey)
}

ClassMethod ListSpecResponses() As %Status
{
    Quit ##class(AgenticInterop.Editor.SpecResponseService).List(%response, %request)
}

ClassMethod SaveSpecResponse() As %Status
{
    Quit ##class(AgenticInterop.Editor.SpecResponseService).Save(%response, %request.Content)
}

ClassMethod GetSpecResponse(pId As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.SpecResponseService).Get(%response, pId)
}

ClassMethod FavoriteSpecResponse(pId As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.SpecResponseService).Favorite(%response, pId, %request.Content)
}

ClassMethod DeleteSpecResponse(pId As %String) As %Status
{
    Quit ##class(AgenticInterop.Editor.SpecResponseService).Delete(%response, pId)
}

ClassMethod Chat() As %Status
{
    Quit ##class(AgenticInterop.Editor.ChatService).Chat(%response, %request.Content)
}

ClassMethod ChatStream() As %Status
{
    Quit ##class(AgenticInterop.Editor.ChatService).ChatStream(%response, %request.Content)
}

ClassMethod CatalogStatus() As %Status
{
    Quit ##class(AgenticInterop.Editor.CatalogService).Status(%response)
}

ClassMethod CatalogRebuild() As %Status
{
    Quit ##class(AgenticInterop.Editor.CatalogService).Rebuild(%response, %request.Content)
}

ClassMethod CatalogBrowse() As %Status
{
    Quit ##class(AgenticInterop.Editor.CatalogService).Browse(%response)
}

ClassMethod CatalogSearch() As %Status
{
    Quit ##class(AgenticInterop.Editor.CatalogService).Search(%response)
}

ClassMethod AuditList() As %Status
{
    Quit ##class(AgenticInterop.Editor.AuditService).List(%response)
}

ClassMethod TokenUsageList() As %Status
{
    Quit ##class(AgenticInterop.Editor.TokenUsageService).List(%response)
}

ClassMethod AuditKinds() As %Status
{
    Quit ##class(AgenticInterop.Editor.AuditService).Kinds(%response)
}

ClassMethod TransformInventory() As %Status
{
    Quit ##class(AgenticInterop.Editor.TransformService).Inventory(%response)
}

ClassMethod DTLFields() As %Status
{
    Quit ##class(AgenticInterop.Editor.TransformService).DTLFields(%response)
}

ClassMethod HL7Fields() As %Status
{
    Quit ##class(AgenticInterop.Editor.TransformService).HL7Fields(%response)
}

ClassMethod FieldTraceRebuild() As %Status
{
    Quit ##class(AgenticInterop.Editor.TransformService).RebuildFieldMappings(%response)
}

ClassMethod FieldTraceStatus() As %Status
{
    Quit ##class(AgenticInterop.Editor.TransformService).FieldTraceStatus(%response)
}

ClassMethod FieldTraceQuery() As %Status
{
    Quit ##class(AgenticInterop.Editor.TransformService).QueryFieldTrace(%response)
}

ClassMethod CleanupProductions() As %Status
{
    Quit ##class(AgenticInterop.Editor.CleanupService).CleanProductions(%response)
}

ClassMethod ListCustomArtifacts() As %Status
{
    Quit ##class(AgenticInterop.Editor.CleanupService).ListArtifacts(%response)
}

ClassMethod DeleteCustomArtifacts() As %Status
{
    Quit ##class(AgenticInterop.Editor.CleanupService).DeleteArtifacts(%response)
}

ClassMethod ObserverSessions() As %Status
{
    Quit ##class(AgenticInterop.Editor.ObserverService).Sessions(%response)
}

ClassMethod ObserverStream() As %Status
{
    Quit ##class(AgenticInterop.Editor.ObserverService).Stream(%response)
}

ClassMethod ObserverPurge() As %Status
{
    Quit ##class(AgenticInterop.Editor.ObserverService).PurgeAll(%response)
}

}
