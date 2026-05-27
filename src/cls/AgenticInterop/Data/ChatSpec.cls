/// Per-conversation Project Specification synthesized from chat attachments.
///
/// Each iteration the agent presents a spec for the user to approve. If the
/// user asks for changes, the agent revises and we Record() a new draft;
/// the prior draft moves to status='superseded'. On approval, Accept()
/// flips the latest draft to status='accepted' so the build phase has
/// an unambiguous reference.
Class AgenticInterop.Data.ChatSpec Extends (%Persistent, %JSON.Adaptor)
{

Property SessionId As %String(MAXLEN = 64);

Property Version As %Integer;

/// draft | accepted | superseded
Property Status As %String(MAXLEN = 16) [ InitialExpression = "draft" ];

Property Body As %Stream.GlobalCharacter;

/// Comma-separated list of attachment filenames that produced this spec.
Property AttachmentNames As %String(MAXLEN = 2000);

Property CreatedAt As %TimeStamp [ InitialExpression = {$zdatetime($horolog, 3, 1)} ];

Property AcceptedAt As %TimeStamp;

Index SessionVersion On (SessionId, Version) [ Unique ];

/// Insert a new draft. Any prior 'draft' for this session is flipped to
/// 'superseded' so there is always at most one active draft per session.
ClassMethod Record(pSessionId As %String, pBody As %String, pAttachmentNames As %String = "") As AgenticInterop.Data.ChatSpec
{
    ; Supersede any existing draft
    &sql(UPDATE AgenticInterop_Data.ChatSpec SET Status = 'superseded'
         WHERE SessionId = :pSessionId AND Status = 'draft')
    ; Compute next version
    Set nextVersion = 1
    &sql(SELECT MAX(Version) INTO :maxV FROM AgenticInterop_Data.ChatSpec WHERE SessionId = :pSessionId)
    If $get(maxV) '= "" { Set nextVersion = +maxV + 1 }
    Set obj = ..%New()
    Set obj.SessionId = pSessionId
    Set obj.Version = nextVersion
    Set obj.Status = "draft"
    Set obj.AttachmentNames = pAttachmentNames
    Do obj.Body.Write(pBody)
    Do obj.%Save()
    Quit obj
}

/// Flip the latest draft for this session to 'accepted'. Returns the
/// accepted spec or "" if no draft existed.
ClassMethod Accept(pSessionId As %String) As AgenticInterop.Data.ChatSpec
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TOP 1 ID FROM AgenticInterop_Data.ChatSpec WHERE SessionId = ? AND Status = 'draft' ORDER BY Version DESC",
        pSessionId)
    If 'rs.%Next() { Quit "" }
    Set obj = ..%OpenId(rs.%Get("ID"))
    If '$isobject(obj) { Quit "" }
    Set obj.Status = "accepted"
    Set obj.AcceptedAt = $zdatetime($horolog, 3, 1)
    Do obj.%Save()
    Quit obj
}

/// Return the latest non-superseded spec for a session, or "".
ClassMethod GetCurrent(pSessionId As %String) As AgenticInterop.Data.ChatSpec
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TOP 1 ID FROM AgenticInterop_Data.ChatSpec WHERE SessionId = ? AND Status IN ('draft','accepted') ORDER BY Version DESC",
        pSessionId)
    If 'rs.%Next() { Quit "" }
    Quit ..%OpenId(rs.%Get("ID"))
}

}
