/// REST service for the Chatbot configuration layer (chatbot -> agent
/// binding). Backs the admin "Chatbots" tab and the chat surface's
/// agent-resolution lookup. CRUD over AgenticInterop.Data.Chatbot.
///
/// Mirrors the other Editor.* services: methods take the %CSP.Response
/// (and, for writes, the request body stream) and emit JSON via
/// AgenticInterop.Editor.Util.
Class AgenticInterop.Editor.ChatbotService Extends %RegisteredObject
{

/// GET /chatbots — list all configured chatbots.
ClassMethod List(pResponse As %CSP.Response) As %Status
{
    Set arr = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM AgenticInterop_Data.Chatbot ORDER BY ChatbotKey")
    While rs.%Next() {
        Set o = ##class(AgenticInterop.Data.Chatbot).%OpenId(rs.%Get("ID"))
        If $isobject(o) { Do arr.%Push(##class(AgenticInterop.Data.Chatbot).ToJSON(o)) }
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, {"chatbots": (arr)})
}

/// GET /chatbots/:key — one chatbot (used by the chat surface to resolve
/// its agent + title).
ClassMethod Get(pResponse As %CSP.Response, pKey As %String) As %Status
{
    Set o = ##class(AgenticInterop.Data.Chatbot).GetByKey(pKey)
    If '$isobject(o) {
        Quit ##class(AgenticInterop.Editor.Util).WriteError(pResponse, "404 Not Found", "Chatbot not found: " _ pKey)
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, ##class(AgenticInterop.Data.Chatbot).ToJSON(o))
}

/// POST /chatbots (key in body) or PUT /chatbots/:key — upsert.
/// Validates the slug and that AgentClass is a real %AI.Agent subclass.
ClassMethod Save(pResponse As %CSP.Response, pKey As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    Set key = pKey
    If key = "" { Set key = $classmethod(util, "DObj", req, "key", "") }
    If key = "" {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Missing chatbot key")
    }
    If '..validKey(key) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Key must be lowercase letters/digits/dashes, starting with a letter")
    }
    Set agentClass = $classmethod(util, "DObj", req, "agentClass", "")
    If agentClass = "" {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Missing agentClass")
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(agentClass) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Agent class not found: " _ agentClass)
    }
    If '##class(AgenticInterop.Editor.Util).ExtendsClass(agentClass, "%AI.Agent") {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Class is not an %AI.Agent subclass: " _ agentClass)
    }
    Set o = ##class(AgenticInterop.Data.Chatbot).GetByKey(key)
    If '$isobject(o) {
        Set o = ##class(AgenticInterop.Data.Chatbot).%New()
        Set o.ChatbotKey = key
    }
    Set o.Name = $classmethod(util, "DObj", req, "name", o.Name)
    Set o.AgentClass = agentClass
    Set o.HostApp = $classmethod(util, "DObj", req, "hostApp", o.HostApp)
    Set o.Subtitle = $classmethod(util, "DObj", req, "subtitle", o.Subtitle)
    Set en = $classmethod(util, "DObj", req, "enabled", 1)
    Set o.Enabled = $select((en = 0) || (en = "false"):0, 1:1)
    Set o.UpdatedAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
    Set sc = o.%Save()
    If 'sc {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", $system.Status.GetErrorText(sc))
    }
    Quit $classmethod(util, "WriteJSON", pResponse, ##class(AgenticInterop.Data.Chatbot).ToJSON(o))
}

/// DELETE /chatbots/:key — remove a non-core chatbot.
ClassMethod Delete(pResponse As %CSP.Response, pKey As %String) As %Status
{
    Set o = ##class(AgenticInterop.Data.Chatbot).GetByKey(pKey)
    If '$isobject(o) {
        Quit ##class(AgenticInterop.Editor.Util).WriteError(pResponse, "404 Not Found", "Chatbot not found: " _ pKey)
    }
    If o.Core {
        Quit ##class(AgenticInterop.Editor.Util).WriteError(pResponse, "400 Bad Request", "Cannot delete a built-in chatbot. Disable it instead.")
    }
    Set id = o.%Id()
    Set sc = ##class(AgenticInterop.Data.Chatbot).%DeleteId(id)
    If 'sc {
        Quit ##class(AgenticInterop.Editor.Util).WriteError(pResponse, "500 Internal Server Error", $system.Status.GetErrorText(sc))
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, {"ok": 1, "deleted": (pKey)})
}

/// Slug validation: 1 lowercase letter, then any of lowercase / digit /
/// dash. Pattern match avoids the numeric char-range comparison gotcha.
ClassMethod validKey(pKey As %String) As %Boolean [ CodeMode = expression ]
{
pKey?1L.(1L,1N,1"-")
}

}
