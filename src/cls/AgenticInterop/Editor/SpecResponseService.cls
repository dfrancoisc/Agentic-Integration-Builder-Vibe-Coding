/// REST surface for saved Integration Spec Questionnaire runs.
///
///   GET    /spec/responses            list (summaries; newest first)
///   POST   /spec/responses            save a run
///   GET    /spec/responses/:id        one run, including answers + prompt
///   DELETE /spec/responses/:id        remove a run
///
/// Listing is scoped to the caller's namespace by default, because a
/// specification only means something against the namespace it targets.
/// Pass ?all=1 to see every namespace.
Class AgenticInterop.Editor.SpecResponseService Extends %RegisteredObject
{

/// GET /spec/responses[?all=1][&limit=n][&mine=1]
ClassMethod List(pResponse As %CSP.Response, pRequest As %CSP.Request) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set all   = $get(%request.Data("all", 1))
    Set mine  = $get(%request.Data("mine", 1))
    Set limit = +$get(%request.Data("limit", 1))
    If limit <= 0 { Set limit = 200 }

    Set sql = "SELECT ID FROM AgenticInterop_Data.SpecResponse"
    Set where = "", args = 0
    If all '= 1 {
        Set where = where _ $select(where="":" WHERE ", 1:" AND ") _ "Namespace = ?"
        Set args = args + 1, arg(args) = $namespace
    }
    If mine = 1 {
        Set where = where _ $select(where="":" WHERE ", 1:" AND ") _ "Username = ?"
        Set args = args + 1, arg(args) = $username
    }
    Set sql = sql _ where _ " ORDER BY CreatedAt DESC"

    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare(sql)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", $system.Status.GetErrorText(sc))
    }
    If args = 0      { Set rs = stmt.%Execute() }
    ElseIf args = 1  { Set rs = stmt.%Execute(arg(1)) }
    Else             { Set rs = stmt.%Execute(arg(1), arg(2)) }

    Set arr = [], n = 0
    While rs.%Next(), n < limit {
        Set o = ##class(AgenticInterop.Data.SpecResponse).%OpenId(rs.%Get("ID"))
        Continue:'$isobject(o)
        Do arr.%Push(##class(AgenticInterop.Data.SpecResponse).Summary(o))
        Set n = n + 1
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"responses": (arr), "count": (n), "namespace": ($namespace)})
}

/// POST /spec/responses
ClassMethod Save(pResponse As %CSP.Response, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    ; A run with neither answers nor a prompt is not worth a row.
    Set hasAnswers = req.%IsDefined("answers") && $isobject(req.answers)
    Set hasPrompt  = $classmethod(util, "DObj", req, "prompt") '= ""
    If 'hasAnswers, 'hasPrompt {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Nothing to save: supply answers, prompt, or both")
    }

    Set id = ##class(AgenticInterop.Data.SpecResponse).Record(req, $username, .sc)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", $system.Status.GetErrorText(sc))
    }
    Set o = ##class(AgenticInterop.Data.SpecResponse).%OpenId(id)
    Quit $classmethod(util, "WriteJSON", pResponse,
        {"ok": 1, "id": (id), "saved": (##class(AgenticInterop.Data.SpecResponse).Summary(o))}, "201 Created")
}

/// GET /spec/responses/:id
ClassMethod Get(pResponse As %CSP.Response, pId As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set o = ##class(AgenticInterop.Data.SpecResponse).%OpenId(pId)
    If '$isobject(o) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "No saved specification with id " _ pId)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, ##class(AgenticInterop.Data.SpecResponse).ToJSON(o))
}

/// DELETE /spec/responses/:id
ClassMethod Delete(pResponse As %CSP.Response, pId As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(AgenticInterop.Data.SpecResponse).%ExistsId(pId) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "No saved specification with id " _ pId)
    }
    Set sc = ##class(AgenticInterop.Data.SpecResponse).%DeleteId(pId)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", $system.Status.GetErrorText(sc))
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"ok": 1, "deleted": (pId)})
}

}
