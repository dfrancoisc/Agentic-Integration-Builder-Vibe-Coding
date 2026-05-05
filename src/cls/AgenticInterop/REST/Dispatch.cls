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

    <!-- Registries (for UI dropdowns) -->
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

/// Switch namespace based on X-IRIS-Namespace header before any route
/// runs. Returning $$$ERROR with a non-empty message blocks the request.
ClassMethod OnPreDispatch(pUrl As %String, pMethod As %String, ByRef pContinue As %Boolean) As %Status
{
    Set pContinue = 1
    Set targetNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE"))
    If targetNs '= "", targetNs '= $namespace {
        // Validate the user has access. For now (no auth), accept any
        // namespace that exists. Phase 1 wires real auth.
        Set tSC = $$$OK
        Try {
            Set $namespace = targetNs
        } Catch ex {
            Set %response.Status = "400 Bad Request"
            Do ..%WriteJSON({"error": "Invalid namespace", "namespace": (targetNs)})
            Set pContinue = 0
        }
    }
    Quit $$$OK
}

ClassMethod %WriteJSON(pObj As %DynamicObject) As %Status
{
    Set %response.ContentType = "application/json"
    Do pObj.%ToJSON()
    Quit $$$OK
}

ClassMethod Health() As %Status
{
    Do ..%WriteJSON({
        "ok": 1,
        "namespace": ($namespace),
        "agentClass": "AgenticInterop.Agent.HealthInterop"
    })
    Quit $$$OK
}

ClassMethod Namespace() As %Status
{
    Do ..%WriteJSON({"namespace": ($namespace)})
    Quit $$$OK
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
