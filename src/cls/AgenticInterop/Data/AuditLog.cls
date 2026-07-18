/// Audit trail for every Agentic Integration Builder REST request — editor CRUD, chat,
/// registry reads. Per restriction #3 (no UI/operation without an
/// authenticated user) and the related audit requirement, every call to
/// /api/agentic/* writes a row here from REST.Dispatch.OnPreDispatch /
/// OnPostDispatch.
///
/// Indexed on Username + Created so the future audit page can show
/// "what did this user do" quickly. Stored in the install namespace
/// (whichever namespace the IPM module was loaded into) so multi-tenant
/// installs keep separate audit trails.
Class AgenticInterop.Data.AuditLog Extends (%Persistent, %JSON.Adaptor)
{

Property Created As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Property Username As %String(MAXLEN = 128) [ Required ];

Property Namespace As %String(MAXLEN = 128) [ Required ];

Property SessionId As %String(MAXLEN = 128);

Property Job As %Integer;

Property Method As %String(MAXLEN = 16) [ Required ];

Property Path As %String(MAXLEN = 1024) [ Required ];

Property StatusCode As %Integer;

Property RequestSize As %Integer;

Property ResponseSize As %Integer;

Property DurationMs As %Integer;

Property ErrorText As %String(MAXLEN = 2048);

/// Tag the request kind: registry / editor.agent / editor.mcp /
/// editor.toolset / editor.tool / chat / health / namespace / other.
Property Kind As %String(MAXLEN = 32);

Index UsernameCreated On (Username, Created);

Index PathCreated On (Path, Created);

Index Created On Created;

ClassMethod Record(pKind As %String, pUsername As %String, pNamespace As %String, pSessionId As %String, pMethod As %String, pPath As %String, pStatusCode As %Integer = 0, pRequestSize As %Integer = 0, pResponseSize As %Integer = 0, pDurationMs As %Integer = 0, pErrorText As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        Set row = ..%New()
        Set row.Kind = pKind
        Set row.Username = pUsername
        Set row.Namespace = pNamespace
        Set row.SessionId = pSessionId
        Set row.Job = $job
        Set row.Method = pMethod
        Set row.Path = pPath
        Set row.StatusCode = pStatusCode
        Set row.RequestSize = pRequestSize
        Set row.ResponseSize = pResponseSize
        Set row.DurationMs = pDurationMs
        Set row.ErrorText = pErrorText
        Set tSC = row.%Save()
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Classify the URL into a Kind tag for audit aggregation.
ClassMethod ClassifyPath(pPath As %String) As %String
{
    If pPath = "" { Quit "other" }
    If pPath [ "/health"   { Quit "health" }
    If pPath [ "/namespace" { Quit "namespace" }
    If pPath [ "/whoami"   { Quit "whoami" }
    If pPath [ "/registry/" { Quit "registry" }
    If pPath [ "/editor/agent"   { Quit "editor.agent" }
    If pPath [ "/editor/mcp"     { Quit "editor.mcp" }
    If pPath [ "/editor/toolset" { Quit "editor.toolset" }
    If pPath [ "/editor/tool"    { Quit "editor.tool" }
    If pPath [ "/chat"           { Quit "chat" }
    Quit "other"
}

Storage Default
{
<Data name="AuditLogDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>Created</Value></Value>
<Value name="3"><Value>Username</Value></Value>
<Value name="4"><Value>Namespace</Value></Value>
<Value name="5"><Value>SessionId</Value></Value>
<Value name="6"><Value>Job</Value></Value>
<Value name="7"><Value>Method</Value></Value>
<Value name="8"><Value>Path</Value></Value>
<Value name="9"><Value>StatusCode</Value></Value>
<Value name="10"><Value>RequestSize</Value></Value>
<Value name="11"><Value>ResponseSize</Value></Value>
<Value name="12"><Value>DurationMs</Value></Value>
<Value name="13"><Value>ErrorText</Value></Value>
<Value name="14"><Value>Kind</Value></Value>
</Data>
<DataLocation>^AgenticInterop.Data.AuditLogD</DataLocation>
<DefaultData>AuditLogDefaultData</DefaultData>
<IdLocation>^AgenticInterop.Data.AuditLogD</IdLocation>
<IndexLocation>^AgenticInterop.Data.AuditLogI</IndexLocation>
<StreamLocation>^AgenticInterop.Data.AuditLogS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
