/// REST shell for the Phase 7 audit log viewer.
///
///   GET /api/agentic/audit/log
///       ?limit=100&user=&kind=&status=&errorsOnly=true&since=
///
/// Reads from AgenticInterop.Data.AuditLog (every REST call to
/// /api/agentic/* gets a row via Dispatch.OnPreDispatch +
/// AuditEnd). Returns the most recent matching rows.
Class AgenticInterop.Editor.AuditService Extends %RegisteredObject
{

ClassMethod List(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set limit = 100
    Set user = ""
    Set kind = ""
    Set status = ""
    Set errorsOnly = 0
    Set since = ""
    Try {
        Set qLimit = $get(%request.Data("limit", 1)) If qLimit '= "" { Set limit = +qLimit }
        Set user = $get(%request.Data("user", 1))
        Set kind = $get(%request.Data("kind", 1))
        Set status = $get(%request.Data("status", 1))
        Set errorsOnly = ($get(%request.Data("errorsOnly", 1)) = "true")
        Set since = $get(%request.Data("since", 1))
    } Catch  {}
    If limit > 1000 { Set limit = 1000 }
    If limit < 1 { Set limit = 1 }
    // TOP doesn't accept bound parameters in IRIS SQL — limit is
    // integer-bounded above so interpolation is safe. Filter
    // strings come from admin-only query params; we $zstrip-scrub
    // single quotes defensively before interpolating to avoid SQL
    // injection paths even though the route is auth-gated.
    Set safeUser   = $tr(user, "'", "")
    Set safeKind   = $tr(kind, "'", "")
    Set safeStatus = +status
    Set safeSince  = $tr(since, "'", "")
    Set sql = "SELECT TOP " _ +limit _ " ID, Created, Username, Namespace, SessionId, Job, Method, Path, StatusCode, RequestSize, ResponseSize, DurationMs, ErrorText, Kind FROM AgenticInterop_Data.AuditLog WHERE 1=1"
    If safeUser '= ""   { Set sql = sql _ " AND Username = '" _ safeUser _ "'" }
    If safeKind '= ""   { Set sql = sql _ " AND Kind = '" _ safeKind _ "'" }
    If status '= ""     { Set sql = sql _ " AND StatusCode = " _ safeStatus }
    If errorsOnly       { Set sql = sql _ " AND StatusCode >= 400" }
    If safeSince '= ""  { Set sql = sql _ " AND Created >= '" _ safeSince _ "'" }
    Set sql = sql _ " ORDER BY ID DESC"

    Set rows = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    While rs.%Next() {
        Set row = {}
        Set row.id           = rs.%Get("ID")
        Set row.created      = rs.%Get("Created")
        Set row.username     = rs.%Get("Username")
        Set row.namespace    = rs.%Get("Namespace")
        Set row.sessionId    = rs.%Get("SessionId")
        Set row.job          = rs.%Get("Job")
        Set row.method       = rs.%Get("Method")
        Set row.path         = rs.%Get("Path")
        Set row.statusCode   = rs.%Get("StatusCode")
        Set row.requestSize  = rs.%Get("RequestSize")
        Set row.responseSize = rs.%Get("ResponseSize")
        Set row.durationMs   = rs.%Get("DurationMs")
        Set row.errorText    = rs.%Get("ErrorText")
        Set row.kind         = rs.%Get("Kind")
        Do rows.%Push(row)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"rows": (rows), "limit": (limit)})
}

/// GET /api/agentic/audit/kinds — distinct Kind values for filter dropdown.
ClassMethod Kinds(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set arr = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT DISTINCT Kind FROM AgenticInterop_Data.AuditLog WHERE Kind <> '' ORDER BY Kind")
    While rs.%Next() { Do arr.%Push(rs.%Get("Kind")) }
    Quit $classmethod(util, "WriteJSON", pResponse, {"kinds": (arr)})
}

}
