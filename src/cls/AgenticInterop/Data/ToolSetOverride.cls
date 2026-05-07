/// User customization layer over a shipped ToolSet class. Same shape
/// and rationale as AgenticInterop.Data.MCPOverride — see that class
/// for the full doc-block. ToolSet-specific fields:
///
///   Name           — parameter NAME (display)
///   Description    — class-level (operator-facing)
///   DefinitionRaw  — Framework XData Definition (XML). Edits stored
///                    here are returned by the editor, but the chat
///                    runtime still reads the compiled XData — the
///                    framework parses Definition at compile time.
///                    A real "live" override of tool routing would
///                    require us to mutate the XData and recompile,
///                    which we don't do automatically. For now this
///                    column is round-trip only (UI shows what was
///                    saved, runtime needs an explicit recompile via
///                    `zpm` redeploy of the User class).
///   ToolManifest   — Editor-managed JSON. Same caveat.
Class AgenticInterop.Data.ToolSetOverride Extends (%Persistent, %JSON.Adaptor)
{

Property ClassName As %String(MAXLEN = 200) [ Required ];

Property Name As %String(MAXLEN = 200);

Property Description As %String(MAXLEN = 4000);

Property DefinitionRaw As %String(MAXLEN = 16000);

Property ToolManifest As %String(MAXLEN = 16000);

Property UpdatedBy As %String(MAXLEN = 128);

Property UpdatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Index ClassNameIdx On ClassName [ Unique ];

Storage Default
{
<Data name="ToolSetOverrideDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>ClassName</Value></Value>
<Value name="3"><Value>Name</Value></Value>
<Value name="4"><Value>Description</Value></Value>
<Value name="5"><Value>DefinitionRaw</Value></Value>
<Value name="6"><Value>ToolManifest</Value></Value>
<Value name="7"><Value>UpdatedBy</Value></Value>
<Value name="8"><Value>UpdatedAt</Value></Value>
</Data>
<DataLocation>^AgInt.ToolSetOverrideD</DataLocation>
<DefaultData>ToolSetOverrideDefaultData</DefaultData>
<IdLocation>^AgInt.ToolSetOverrideD</IdLocation>
<IndexLocation>^AgInt.ToolSetOverrideI</IndexLocation>
<StreamLocation>^AgInt.ToolSetOverrideS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
