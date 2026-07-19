/// REST surface for saved Integration Spec Questionnaire runs.
///
///   GET    /spec/responses                   worklist (summaries only)
///   POST   /spec/responses                   save a run
///   GET    /spec/responses/:id               one run, with answers + prompt
///   POST   /spec/responses/:id/favorite      star / unstar
///   DELETE /spec/responses/:id               remove a run
///
/// Listing is scoped to the caller's namespace and user by default,
/// because a specification only means something against the namespace it
/// targets. Pass ?all=1 for every namespace, ?mine=0 for every user.
/// Search with ?q=, filter to starred with ?fav=1.
///
/// Summaries never read the answer or prompt streams, so a long worklist
/// costs one row read each rather than two blob reads.
Class AgenticInterop.Editor.SpecResponseService Extends %RegisteredObject
{

/// GET /spec/responses[?all=1][&mine=1][&fav=1][&q=text][&limit=n]
///
/// The worklist. Search runs server-side across interface name, short
/// name, user and namespace, so a long history does not have to be
/// shipped to the browser to be filtered. Starred runs always sort
/// first -- that is the point of starring them.
ClassMethod List(pResponse As %CSP.Response, pRequest As %CSP.Request) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set all   = $get(%request.Data("all", 1))
    Set mine  = $get(%request.Data("mine", 1))
    Set fav   = $get(%request.Data("fav", 1))
    Set q     = $zstrip($get(%request.Data("q", 1)), "<>W")
    Set limit = +$get(%request.Data("limit", 1))
    If limit <= 0 { Set limit = 200 }

    Set where = "", args = 0
    If all '= 1 {
        Set where = where _ $select(where="":" WHERE ", 1:" AND ") _ "Namespace = ?"
        Set args = args + 1, arg(args) = $namespace
    }
    If mine = 1 {
        Set where = where _ $select(where="":" WHERE ", 1:" AND ") _ "Username = ?"
        Set args = args + 1, arg(args) = $username
    }
    If fav = 1 {
        Set where = where _ $select(where="":" WHERE ", 1:" AND ") _ "Favorite = 1"
    }
    If q '= "" {
        ; case-insensitive contains across the fields a user would recall
        Set where = where _ $select(where="":" WHERE ", 1:" AND ") _
            "(%SQLUPPER(InterfaceName) [ ? OR %SQLUPPER(ShortName) [ ? " _
            "OR %SQLUPPER(Username) [ ? OR %SQLUPPER(Namespace) [ ?)"
        Set needle = $zconvert(q, "U")
        For i=1:1:4 { Set args = args + 1, arg(args) = needle }
    }

    ; starred first, then newest first
    Set sql = "SELECT ID FROM AgenticInterop_Data.SpecResponse" _ where _
              " ORDER BY Favorite DESC, UpdatedAt DESC"

    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare(sql)
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", $system.Status.GetErrorText(sc))
    }
    If args = 0      { Set rs = stmt.%Execute() }
    ElseIf args = 1  { Set rs = stmt.%Execute(arg(1)) }
    ElseIf args = 2  { Set rs = stmt.%Execute(arg(1), arg(2)) }
    ElseIf args = 4  { Set rs = stmt.%Execute(arg(1), arg(2), arg(3), arg(4)) }
    ElseIf args = 5  { Set rs = stmt.%Execute(arg(1), arg(2), arg(3), arg(4), arg(5)) }
    Else             { Set rs = stmt.%Execute(arg(1), arg(2), arg(3), arg(4), arg(5), arg(6)) }

    Set arr = [], n = 0, favs = 0
    While rs.%Next(), n < limit {
        Set o = ##class(AgenticInterop.Data.SpecResponse).%OpenId(rs.%Get("ID"))
        Continue:'$isobject(o)
        Do arr.%Push(##class(AgenticInterop.Data.SpecResponse).Summary(o))
        Set n = n + 1
        If o.Favorite { Set favs = favs + 1 }
    }
    Quit $classmethod(util, "WriteJSON", pResponse,
        {"responses": (arr), "count": (n), "favorites": (favs),
         "query": (q), "namespace": ($namespace)})
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

/// POST /spec/responses/:id/favorite   body: { "favorite": true|false }
ClassMethod Favorite(pResponse As %CSP.Response, pId As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    Set on = 1
    If $isobject(req), req.%IsDefined("favorite") { Set on = ''req.favorite }

    Set state = ##class(AgenticInterop.Data.SpecResponse).SetFavorite(pId, on, .sc)
    If state = "" {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "No saved specification with id " _ pId)
    }
    If $$$ISERR(sc) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", $system.Status.GetErrorText(sc))
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"ok": 1, "id": (pId), "favorite": (''state)})
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
