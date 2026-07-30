/// One row per chat prompt: how many tokens that single interaction spent
/// and which tools it called. Written at the end of every chat turn from
/// AgenticInterop.Editor.ChatService (both the non-streaming /chat and the
/// streaming /chat/stream paths), best-effort so a logging failure can
/// never break a chat turn.
///
/// The numbers come from AgenticInterop.Agent.Monitor, which accumulates
/// usage across the tool-call iteration loop. Each iteration is a separate
/// billed LLM call that re-sends the growing context, so TotalTokens is the
/// true billed cost of the prompt, not a double-count. On this project the
/// InputTokens half is usually much larger than OutputTokens, because the
/// agent's whole tool + skill catalog is re-sent as context every round —
/// which is exactly the lever behind the Bedrock throughput ceiling.
///
/// Stored in the install namespace (HSCUSTOM), which is where the REST app
/// executes regardless of the caller's namespace. Namespace here is the
/// caller's WORKING namespace, taken from the X-IRIS-Namespace header, so
/// the log can be filtered by it without depending on which namespace the
/// row's global physically lives in. This is the same split that keeps the
/// Spec Questionnaire worklist from appearing empty.
Class AgenticInterop.Data.TokenUsage Extends (%Persistent, %JSON.Adaptor)
{

Property Created As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

/// IRIS user who sent the prompt.
Property Username As %String(MAXLEN = 128);

/// The caller's working namespace (from X-IRIS-Namespace), NOT $namespace.
Property Namespace As %String(MAXLEN = 128);

/// Chat session / observer id, so a whole conversation's turns group.
Property SessionId As %String(MAXLEN = 128);

Property Job As %Integer;

/// Agent that answered, e.g. AgenticInterop.Agent.HealthInterop.
Property AgentClass As %String(MAXLEN = 200);

/// Resolved LLM connection name, e.g. bedrock-default. CONNECTION is a
/// reserved SQL word, so the column projects as ConnName — always refer to
/// it by that name in queries.
Property Connection As %String(MAXLEN = 200) [ SqlFieldName = ConnName ];

/// Model id the provider was called with.
Property Model As %String(MAXLEN = 200);

/// First part of the user's prompt, for recognising the row. Truncated —
/// PromptLength keeps the true size. Not the full text: the log is an
/// accounting record, not a transcript.
Property PromptSnippet As %String(MAXLEN = 2000);

/// True character length of the prompt before truncation.
Property PromptLength As %Integer [ InitialExpression = 0 ];

/// How many LLM rounds the turn took (1 = no tools; more = tool loop).
Property Iterations As %Integer [ InitialExpression = 0 ];

/// Prompt (input) tokens summed across iterations — the tool-catalog cost.
Property InputTokens As %Integer [ InitialExpression = 0 ];

/// Completion (output) tokens summed across iterations.
Property OutputTokens As %Integer [ InitialExpression = 0 ];

/// Total billed tokens for this prompt.
Property TotalTokens As %Integer [ InitialExpression = 0 ];

/// Comma-separated tool names in fire order, exactly as the Monitor saw
/// them. Empty when the turn called no tools.
Property ToolTrace As %String(MAXLEN = 4000);

/// Count of tool calls in ToolTrace, denormalised for cheap sorting.
Property ToolCount As %Integer [ InitialExpression = 0 ];

Property LatencyMs As %Integer [ InitialExpression = 0 ];

/// 1 if the turn produced a response, 0 if it errored.
Property Ok As %Boolean [ InitialExpression = 1 ];

Property ErrorText As %String(MAXLEN = 2000);

/// Which endpoint served the turn: stream | chat.
Property Channel As %String(MAXLEN = 16);

Index Created On Created;

Index UserCreated On (Username, Created);

Index NamespaceCreated On (Namespace, Created);

Index Session On SessionId;

/// Persist one prompt's usage. Every argument is optional and defaulted so
/// a partial call still records something useful; the caller wraps this in
/// its own Try so logging never propagates an error into a chat turn.
ClassMethod Record(pProps As %DynamicObject) As %String
{
    Set id = ""
    Try {
        Set util = "AgenticInterop.Editor.Util"
        Set o = ..%New()
        Set o.Username     = $classmethod(util, "DObj", pProps, "username", $username)
        Set o.Namespace    = $classmethod(util, "DObj", pProps, "namespace", $namespace)
        Set o.SessionId    = $classmethod(util, "DObj", pProps, "sessionId")
        Set o.Job          = $job
        Set o.AgentClass   = $classmethod(util, "DObj", pProps, "agentClass")
        Set o.Connection   = $classmethod(util, "DObj", pProps, "connection")
        Set o.Model        = $classmethod(util, "DObj", pProps, "model")
        Set prompt         = $classmethod(util, "DObj", pProps, "prompt")
        Set o.PromptLength = $length(prompt)
        Set o.PromptSnippet = $extract(prompt, 1, 2000)
        Set o.Iterations   = +$classmethod(util, "DObj", pProps, "iterations", 0)
        Set o.InputTokens  = +$classmethod(util, "DObj", pProps, "inputTokens", 0)
        Set o.OutputTokens = +$classmethod(util, "DObj", pProps, "outputTokens", 0)
        Set o.TotalTokens  = +$classmethod(util, "DObj", pProps, "totalTokens", 0)
        Set trace          = $classmethod(util, "DObj", pProps, "toolTrace")
        Set o.ToolTrace    = $extract(trace, 1, 4000)
        Set o.ToolCount    = $select(trace="":0, 1:$length(trace, ","))
        Set o.LatencyMs    = +$classmethod(util, "DObj", pProps, "latencyMs", 0)
        Set o.Ok           = +$classmethod(util, "DObj", pProps, "ok", 1)
        Set o.ErrorText    = $extract($classmethod(util, "DObj", pProps, "error"), 1, 2000)
        Set o.Channel      = $classmethod(util, "DObj", pProps, "channel")
        Set sc = o.%Save()
        If $$$ISOK(sc) { Set id = o.%Id() }
    } Catch ex {
        ; swallow — a token-log failure must never surface in the chat turn
    }
    Quit id
}

/// Summary row for the log table — every field the list view shows,
/// deliberately excluding nothing large (there are no streams here).
ClassMethod Summary(pObj As AgenticInterop.Data.TokenUsage) As %DynamicObject
{
    Quit {
        "id":           (pObj.%Id()),
        "created":      (pObj.Created),
        "username":     (pObj.Username),
        "namespace":    (pObj.Namespace),
        "sessionId":    (pObj.SessionId),
        "agentClass":   (pObj.AgentClass),
        "connection":   (pObj.Connection),
        "model":        (pObj.Model),
        "promptSnippet":(pObj.PromptSnippet),
        "promptLength": (pObj.PromptLength),
        "iterations":   (pObj.Iterations),
        "inputTokens":  (pObj.InputTokens),
        "outputTokens": (pObj.OutputTokens),
        "totalTokens":  (pObj.TotalTokens),
        "toolTrace":    (pObj.ToolTrace),
        "toolCount":    (pObj.ToolCount),
        "latencyMs":    (pObj.LatencyMs),
        "ok":           (pObj.Ok),
        "channel":      (pObj.Channel)
    }
}

Storage Default
{
<Data name="TokenUsageDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>Created</Value></Value>
<Value name="3"><Value>Username</Value></Value>
<Value name="4"><Value>Namespace</Value></Value>
<Value name="5"><Value>SessionId</Value></Value>
<Value name="6"><Value>Job</Value></Value>
<Value name="7"><Value>AgentClass</Value></Value>
<Value name="8"><Value>Connection</Value></Value>
<Value name="9"><Value>Model</Value></Value>
<Value name="10"><Value>PromptSnippet</Value></Value>
<Value name="11"><Value>PromptLength</Value></Value>
<Value name="12"><Value>Iterations</Value></Value>
<Value name="13"><Value>InputTokens</Value></Value>
<Value name="14"><Value>OutputTokens</Value></Value>
<Value name="15"><Value>TotalTokens</Value></Value>
<Value name="16"><Value>ToolTrace</Value></Value>
<Value name="17"><Value>ToolCount</Value></Value>
<Value name="18"><Value>LatencyMs</Value></Value>
<Value name="19"><Value>Ok</Value></Value>
<Value name="20"><Value>ErrorText</Value></Value>
<Value name="21"><Value>Channel</Value></Value>
</Data>
<DataLocation>^AgenticInterop.Data.TokenUsageD</DataLocation>
<DefaultData>TokenUsageDefaultData</DefaultData>
<IdLocation>^AgenticInterop.Data.TokenUsageD</IdLocation>
<IndexLocation>^AgenticInterop.Data.TokenUsageI</IndexLocation>
<StreamLocation>^AgenticInterop.Data.TokenUsageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
