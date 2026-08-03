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
    Set cols = "ID, Created, Username, Namespace, SessionId, AgentClass, ConnName, Model, PromptSnippet, PromptLength, Iterations, InputTokens, OutputTokens, TotalTokens, Rounds, Estimated, FinalRoundTokens, ToolTrace, ToolCount, LatencyMs, Ok, Channel"
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
        Set row.rounds        = rs.%Get("Rounds")
        Set row.estimated     = rs.%Get("Estimated")
        Set row.finalRoundTokens = rs.%Get("FinalRoundTokens")
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

/// USD price per 1,000,000 tokens for a model, as {in, out, cacheRead, cacheWrite}.
/// Matched by substring so a full Bedrock model id (global.anthropic.claude-
/// sonnet-4-...) resolves without an exact-id table. These are public
/// list rates and can drift — treat the resulting cost as an estimate, and
/// update here if the contract price differs.
ClassMethod Pricing(pModel As %String) As %DynamicObject [ Internal ]
{
    Set m = $zconvert(pModel, "L")
    If m [ "opus"     { Quit {"in": 15.0, "out": 75.0, "cacheRead": 1.50, "cacheWrite": 18.75} }
    If m [ "haiku"    { Quit {"in": 0.80, "out": 4.0, "cacheRead": 0.08, "cacheWrite": 1.0} }
    ; sonnet (and the safe default — the v1 runtime model)
    Quit {"in": 3.0, "out": 15.0, "cacheRead": 0.30, "cacheWrite": 3.75}
}

/// GET /api/agentic/tokens/sessions[?ns=all][&mine=1][&limit=n]
///
/// The per-session summary the Tokens tab renders as cards, one per
/// conversation (grouped on ConversationId). Each card carries the headline
/// figures — cost, API time, active span, model mix, cache-hit — plus a
/// per-model breakdown of input / output / cache-read / cache-write, the
/// same shape as the Claude Code session panel.
///
/// Cost is derived from Pricing() and the (mostly reconstructed) token
/// counts, so it is an estimate; the response says so via estimated=1 on
/// any session that contains a reconstructed turn.
ClassMethod Sessions(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set limit = 50, mine = 0, nsScope = ""
    Try {
        Set qLimit = $get(%request.Data("limit", 1)) If qLimit '= "" { Set limit = +qLimit }
        Set mine    = ($get(%request.Data("mine", 1)) = 1)
        Set nsScope = $get(%request.Data("ns", 1))
    } Catch  {}
    If limit > 500 { Set limit = 500 }
    If limit < 1 { Set limit = 1 }

    Set callerNs = ##class(AgenticInterop.Editor.SpecResponseService).RequestNamespace()
    Set where = " WHERE 1=1"
    If nsScope '= "all" { Set where = where _ " AND Namespace = '" _ $tr(callerNs, "'", "") _ "'" }
    If mine             { Set where = where _ " AND Username = '" _ $tr($username, "'", "") _ "'" }

    ; One pass grouped by conversation AND model gives both the card totals
    ; (sum the model rows) and the per-model breakdown, in a single query.
    Set sql = "SELECT ConversationId, Model, "
        _ "COUNT(*) AS Prompts, SUM(Rounds) AS Rounds, SUM(ToolCount) AS Tools, "
        _ "SUM(InputTokens) AS InTok, SUM(OutputTokens) AS OutTok, "
        _ "SUM(CacheReadTokens) AS CrTok, SUM(CacheWriteTokens) AS CwTok, "
        _ "SUM(LatencyMs) AS ApiMs, SUM(Estimated) AS EstCount, "
        _ "MIN(Created) AS FirstAt, MAX(Created) AS LastAt, "
        _ "MAX(Username) AS Username, MAX(Namespace) AS Namespace "
        _ "FROM AgenticInterop_Data.TokenUsage" _ where
        _ " GROUP BY ConversationId, Model ORDER BY MAX(Created) DESC"

    ; Assemble sessions in first-seen order (already newest-first from SQL),
    ; each accumulating its model breakdown rows.
    Set sessById = {}, order = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    While rs.%Next() {
        Set cid = rs.%Get("ConversationId")
        If cid = "" { Set cid = "(none)" }
        If 'sessById.%IsDefined(cid) {
            Set s = {"conversationId": (cid), "prompts": 0, "rounds": 0, "tools": 0,
                     "inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheWriteTokens": 0,
                     "apiMs": 0, "estCount": 0, "costUsd": 0, "firstAt": "", "lastAt": "",
                     "username": "", "namespace": "", "models": []}
            Do sessById.%Set(cid, s)
            Do order.%Push(cid)
        }
        Set s = sessById.%Get(cid)
        Set model = rs.%Get("Model")
        Set inTok = +rs.%Get("InTok"), outTok = +rs.%Get("OutTok")
        Set crTok = +rs.%Get("CrTok"), cwTok = +rs.%Get("CwTok")
        Set p = ..Pricing(model)
        ; ObjectScript has NO operator precedence — every product must be
        ; parenthesised or `a*b+c*d` becomes ((a*b)+c)*d.
        Set cost = ((inTok * p.in) + (outTok * p.out) + (crTok * p.cacheRead) + (cwTok * p.cacheWrite)) / 1000000

        Set mb = {"model": (model), "inputTokens": (inTok), "outputTokens": (outTok),
                  "cacheReadTokens": (crTok), "cacheWriteTokens": (cwTok),
                  "prompts": (+rs.%Get("Prompts")), "costUsd": ($normalize(cost, 4))}
        Do s.models.%Push(mb)

        Set s.prompts = s.prompts + (+rs.%Get("Prompts"))
        Set s.rounds = s.rounds + (+rs.%Get("Rounds"))
        Set s.tools = s.tools + (+rs.%Get("Tools"))
        Set s.inputTokens = s.inputTokens + inTok
        Set s.outputTokens = s.outputTokens + outTok
        Set s.cacheReadTokens = s.cacheReadTokens + crTok
        Set s.cacheWriteTokens = s.cacheWriteTokens + cwTok
        Set s.apiMs = s.apiMs + (+rs.%Get("ApiMs"))
        Set s.estCount = s.estCount + (+rs.%Get("EstCount"))
        Set s.costUsd = $normalize(s.costUsd + cost, 4)
        Set s.username = rs.%Get("Username")
        Set s.namespace = rs.%Get("Namespace")
        ; timestamps: keep the earliest first / latest last across model rows
        Set fa = rs.%Get("FirstAt"), la = rs.%Get("LastAt")
        If (s.firstAt = "") || (fa ] "" && (fa < s.firstAt)) { Set s.firstAt = fa }
        If la > s.lastAt { Set s.lastAt = la }
    }

    ; Finalise each session: title from the first prompt, active span, and a
    ; primary model / cache-hit rate for the card header.
    Set sessions = [], n = 0
    Set it = order.%GetIterator()
    While it.%GetNext(.k, .cid) {
        Quit:n>=limit
        Set s = sessById.%Get(cid)
        ; Active span (seconds) between first and last turn.
        Set s.activeSecs = ..SpanSeconds(s.firstAt, s.lastAt)
        Set s.apiSecs = $normalize(s.apiMs / 1000, 0)
        ; Cache-hit rate = cache-read / (cache-read + uncached input).
        Set denom = s.cacheReadTokens + s.inputTokens
        Set s.cacheHitPct = $select(denom > 0: $normalize((s.cacheReadTokens / denom) * 100, 1), 1: 0)
        Set s.estimated = (s.estCount > 0)
        ; Title: first user prompt in this conversation.
        Set s.title = ..FirstPrompt(cid)
        Do sessions.%Push(s)
        Set n = n + 1
    }

    Quit $classmethod(util, "WriteJSON", pResponse,
        {"sessions": (sessions), "count": (n), "namespace": (callerNs)})
}

/// Whole seconds between two %TimeStamp strings (0 on any parse trouble).
ClassMethod SpanSeconds(pFirst As %String, pLast As %String) As %Integer [ Internal ]
{
    Set secs = 0
    Try {
        If (pFirst = "") || (pLast = "") Quit
        Set h1 = $zdatetimeh(pFirst, 3, 1), h2 = $zdatetimeh(pLast, 3, 1)
        Set d1 = $piece(h1, ",", 1), t1 = $piece(h1, ",", 2)
        Set d2 = $piece(h2, ",", 1), t2 = $piece(h2, ",", 2)
        Set secs = ((d2 - d1) * 86400) + (t2 - t1)
        If secs < 0 { Set secs = 0 }
    } Catch  {}
    Quit secs
}

/// The first user prompt in a conversation, for the card title.
ClassMethod FirstPrompt(pConvId As %String) As %String [ Internal ]
{
    Set title = ""
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT TOP 1 PromptSnippet FROM AgenticInterop_Data.TokenUsage WHERE ConversationId = ? ORDER BY ID ASC",
            pConvId)
        If rs.%Next() { Set title = $extract(rs.%Get("PromptSnippet"), 1, 100) }
    } Catch  {}
    Quit title
}

}
