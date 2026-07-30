/// REST shell for the Tokens log — per-prompt token and tool spend.
///
///   GET /api/agentic/tokens
///       ?limit=100&user=&agent=&channel=&mine=1&toolsOnly=true&q=&since=
///
/// Reads from AgenticInterop.Data.TokenUsage, one row per chat prompt,
/// written by AgenticInterop.Editor.ChatService at the end of every turn.
/// Returns the most recent matching rows plus a rollup (row count, prompt
/// count, summed input/output/total tokens, tool-call total) so the UI can
/// show a header line without a second query.
///
/// Scoped by default to the caller's WORKING namespace — a token log only
/// makes sense against the namespace the work happened in — with ?ns=all to
/// see every namespace. The namespace comes from the request header via the
/// shared RequestNamespace helper, because the REST app always executes in
/// the install namespace and $namespace would be the same for every caller.
Class AgenticInterop.Editor.TokenUsageService Extends %RegisteredObject
{

ClassMethod List(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set limit = 100, user = "", agent = "", channel = "", q = "", since = ""
    Set mine = 0, toolsOnly = 0, nsScope = ""
    Try {
        Set qLimit = $get(%request.Data("limit", 1)) If qLimit '= "" { Set limit = +qLimit }
        Set user      = $get(%request.Data("user", 1))
        Set agent     = $get(%request.Data("agent", 1))
        Set channel   = $get(%request.Data("channel", 1))
        Set q         = $zstrip($get(%request.Data("q", 1)), "<>W")
        Set since     = $get(%request.Data("since", 1))
        Set mine      = ($get(%request.Data("mine", 1)) = 1)
        Set toolsOnly = ($get(%request.Data("toolsOnly", 1)) = "true")
        Set nsScope   = $get(%request.Data("ns", 1))
    } Catch  {}
    If limit > 2000 { Set limit = 2000 }
    If limit < 1 { Set limit = 1 }

    ; TOP takes no bound parameter in IRIS SQL; limit is integer-bounded
    ; above so interpolating it is safe. Filter strings are scrubbed of
    ; single quotes before interpolation even though the route is auth-gated.
    Set callerNs = ##class(AgenticInterop.Editor.SpecResponseService).RequestNamespace()
    Set safeUser  = $tr(user, "'", "")
    Set safeAgent = $tr(agent, "'", "")
    Set safeChan  = $tr(channel, "'", "")
    Set safeSince = $tr(since, "'", "")
    Set safeNeedle = $zconvert($tr(q, "'", ""), "U")

    ; ConnName is the SQL projection of the Connection property (CONNECTION
    ; is a reserved word); see AgenticInterop.Data.TokenUsage.
    Set cols = "ID, Created, Username, Namespace, SessionId, AgentClass, ConnName, Model, PromptSnippet, PromptLength, Iterations, InputTokens, OutputTokens, TotalTokens, ToolTrace, ToolCount, LatencyMs, Ok, Channel"
    Set where = " WHERE 1=1"
    If nsScope '= "all"    { Set where = where _ " AND Namespace = '" _ $tr(callerNs, "'", "") _ "'" }
    If mine                { Set where = where _ " AND Username = '" _ $tr($username, "'", "") _ "'" }
    If safeUser '= ""      { Set where = where _ " AND Username = '" _ safeUser _ "'" }
    If safeAgent '= ""     { Set where = where _ " AND AgentClass = '" _ safeAgent _ "'" }
    If safeChan '= ""      { Set where = where _ " AND Channel = '" _ safeChan _ "'" }
    If toolsOnly           { Set where = where _ " AND ToolCount > 0" }
    If safeSince '= ""     { Set where = where _ " AND Created >= '" _ safeSince _ "'" }
    If safeNeedle '= ""    { Set where = where _ " AND (%SQLUPPER(PromptSnippet) [ '" _ safeNeedle _ "' OR %SQLUPPER(ToolTrace) [ '" _ safeNeedle _ "' OR %SQLUPPER(Username) [ '" _ safeNeedle _ "')" }

    Set sql = "SELECT TOP " _ +limit _ " " _ cols _ " FROM AgenticInterop_Data.TokenUsage" _ where _ " ORDER BY ID DESC"

    Set rows = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    While rs.%Next() {
        Set row = {}
        Set row.id            = rs.%Get("ID")
        Set row.created       = rs.%Get("Created")
        Set row.username      = rs.%Get("Username")
        Set row.namespace     = rs.%Get("Namespace")
        Set row.sessionId     = rs.%Get("SessionId")
        Set row.agentClass    = rs.%Get("AgentClass")
        Set row.connection    = rs.%Get("ConnName")
        Set row.model         = rs.%Get("Model")
        Set row.promptSnippet = rs.%Get("PromptSnippet")
        Set row.promptLength  = rs.%Get("PromptLength")
        Set row.iterations    = rs.%Get("Iterations")
        Set row.inputTokens   = rs.%Get("InputTokens")
        Set row.outputTokens  = rs.%Get("OutputTokens")
        Set row.totalTokens   = rs.%Get("TotalTokens")
        Set row.toolTrace     = rs.%Get("ToolTrace")
        Set row.toolCount     = rs.%Get("ToolCount")
        Set row.latencyMs     = rs.%Get("LatencyMs")
        Set row.ok            = rs.%Get("Ok")
        Set row.channel       = rs.%Get("Channel")
        Do rows.%Push(row)
    }

    ; Rollup over the SAME filter (not just the returned page), so the
    ; header totals reflect everything matched, not the top N shown.
    Set agg = {"prompts": 0, "inputTokens": 0, "outputTokens": 0, "totalTokens": 0, "toolCalls": 0}
    Set aggSql = "SELECT COUNT(*) AS Prompts, SUM(InputTokens) AS InTok, SUM(OutputTokens) AS OutTok, SUM(TotalTokens) AS TotTok, SUM(ToolCount) AS Tools FROM AgenticInterop_Data.TokenUsage" _ where
    Set ars = ##class(%SQL.Statement).%ExecDirect(, aggSql)
    If ars.%Next() {
        Set agg.prompts      = +ars.%Get("Prompts")
        Set agg.inputTokens  = +ars.%Get("InTok")
        Set agg.outputTokens = +ars.%Get("OutTok")
        Set agg.totalTokens  = +ars.%Get("TotTok")
        Set agg.toolCalls    = +ars.%Get("Tools")
    }

    Quit $classmethod(util, "WriteJSON", pResponse,
        {"rows": (rows), "limit": (limit), "namespace": (callerNs), "summary": (agg)})
}

}
