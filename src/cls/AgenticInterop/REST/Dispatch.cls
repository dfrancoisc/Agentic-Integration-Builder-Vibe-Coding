/// REST dispatcher for /api/agentic. Routes /health, /namespace, and the
/// /editor/* family to the matching Editor service classes. UseSession=0
/// (set on the CSP application) so iframe fetches with credentials don't
/// deadlock against curl-style probes.
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
    <Route Url="/whoami"             Method="GET"  Call="WhoAmI" />
    <Route Url="/debug"              Method="GET"  Call="Debug" />

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

    <!-- MCP CRUD -->
    <Route Url="/editor/mcp/:class"             Method="GET"    Call="GetMCP" />
    <Route Url="/editor/mcp/:class"             Method="PUT"    Call="SaveMCP" />
    <Route Url="/editor/mcp"                    Method="POST"   Call="CreateMCP" />
    <Route Url="/editor/mcp/:class"             Method="DELETE" Call="DeleteMCP" />

    <!-- ToolSet CRUD -->
    <Route Url="/editor/toolset/:class"         Method="GET"    Call="GetToolSet" />
    <Route Url="/editor/toolset/:class"         Method="PUT"    Call="SaveToolSet" />
    <Route Url="/editor/toolset"                Method="POST"   Call="CreateToolSet" />
    <Route Url="/editor/toolset/:class"         Method="DELETE" Call="DeleteToolSet" />

    <!-- Tool CRUD (one tool entry inside a ToolSet's XData Definition) -->
    <Route Url="/editor/tool/:toolset/:name"    Method="GET"    Call="GetTool" />
    <Route Url="/editor/tool/:toolset/:name"    Method="PUT"    Call="SaveTool" />
    <Route Url="/editor/tool/:toolset"          Method="POST"   Call="CreateTool" />
    <Route Url="/editor/tool/:toolset/:name"    Method="DELETE" Call="DeleteTool" />
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
        // Optional namespace switch via X-IRIS-Namespace header.
        Set targetNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE"))
        If targetNs '= "", targetNs '= $namespace {
            Try {
                Set $namespace = targetNs
            } Catch ex {
                Set %response.Status = "400 Bad Request"
                Do ..%WriteJSON({"error": "Invalid namespace", "namespace": (targetNs)})
                Set pContinue = 0
                Do ..AuditEnd(400, "invalid namespace " _ targetNs)
            }
        }
    }

    Quit $$$OK
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

}
