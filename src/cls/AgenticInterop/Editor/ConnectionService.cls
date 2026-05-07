/// Thin REST wrapper around AgenticInterop.Connections. The facade is
/// where the logic lives — this class just translates HTTP shapes to
/// facade calls and back. Mirrors the AgentService / MCPService /
/// ToolSetService / ProviderService pattern for consistency.
///
/// Endpoints (mounted in REST.Dispatch):
///   GET    /api/agentic/connections              — list all
///   GET    /api/agentic/connections/:name        — one
///   POST   /api/agentic/connections              — create
///   PUT    /api/agentic/connections/:name        — update
///   DELETE /api/agentic/connections/:name        — delete row + secret
///   POST   /api/agentic/connections/:name/secret — body: { value }
///   POST   /api/agentic/connections/:name/test   — run live ChatComplete
Class AgenticInterop.Editor.ConnectionService Extends %RegisteredObject
{

ClassMethod List(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set arr = ##class(AgenticInterop.Connections).List()
    Quit $classmethod(util, "WriteJSON", pResponse, {"connections": (arr)})
}

ClassMethod Get(pResponse As %CSP.Response, pName As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set obj = ##class(AgenticInterop.Connections).Get(pName)
    If obj = "" {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Connection not found", pName)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, obj)
}

ClassMethod Create(pResponse As %CSP.Response, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    Set name = $classmethod(util, "DObj", req, "name")
    If name = "" {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Missing 'name'")
    }
    Set sc = ##class(AgenticInterop.Connections).Create(name, req)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", $system.Status.GetErrorText(sc))
    }
    Quit ..Get(pResponse, name)
}

ClassMethod Save(pResponse As %CSP.Response, pName As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    Set sc = ##class(AgenticInterop.Connections).Update(pName, req)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", $system.Status.GetErrorText(sc))
    }
    Quit ..Get(pResponse, pName)
}

ClassMethod Delete(pResponse As %CSP.Response, pName As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set sc = ##class(AgenticInterop.Connections).Delete(pName)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", $system.Status.GetErrorText(sc))
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"ok": 1, "deleted": (pName)})
}

ClassMethod SaveSecret(pResponse As %CSP.Response, pName As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    Set value = $classmethod(util, "DObj", req, "value")
    If value = "" {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Missing 'value'")
    }
    Set sc = ##class(AgenticInterop.Connections).SetSecret(pName, value)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", $system.Status.GetErrorText(sc))
    }
    Quit ..Get(pResponse, pName)
}

ClassMethod Test(pResponse As %CSP.Response, pName As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set result = ##class(AgenticInterop.Connections).Test(pName)
    Quit $classmethod(util, "WriteJSON", pResponse, result)
}

}
