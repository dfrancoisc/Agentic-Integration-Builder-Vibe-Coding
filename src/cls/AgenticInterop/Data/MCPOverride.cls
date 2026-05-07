/// User customization layer over a shipped MCP class. One row per
/// customized class, keyed by ClassName.
///
/// Why this exists: shipped MCP classes (AgenticInterop.MCP.*) are
/// re-imported by every `zpm load` of the upstream module, which wipes
/// any direct .cls edits. Save handlers for shipped MCPs write into
/// this table instead of the dictionary, so the customization survives
/// upgrade. Read handlers + the chat runtime layer this row on top of
/// the .cls defaults to produce the effective view.
///
/// Empty / null fields mean "fall through to the .cls value" — only
/// non-empty overrides win, so an operator who changes only TOOLSETS
/// keeps the shipped Name and Description automatically.
///
/// User-authored MCPs (AgenticInterop.User.MCP.*) keep writing to
/// .cls directly — they're operator-owned classes that zpm doesn't
/// touch. The override table is shipped-only.
Class AgenticInterop.Data.MCPOverride Extends (%Persistent, %JSON.Adaptor)
{

Property ClassName As %String(MAXLEN = 200) [ Required ];

Property Name As %String(MAXLEN = 200);

Property ShortDescription As %String(MAXLEN = 2000);

Property Description As %String(MAXLEN = 4000);

/// CSV of toolset class names. Mirrors Parameter TOOLSETS on the
/// shipped MCP class. Empty string is meaningful here — distinct
/// from "field not overridden" — so the column is allowed to be
/// "" but the override semantics treat $data() = 0 as "fall
/// through" via the Has<Field>Override pattern below.
Property ToolsetsCsv As %String(MAXLEN = 2000);

Property UpdatedBy As %String(MAXLEN = 128);

Property UpdatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Index ClassNameIdx On ClassName [ Unique ];

Storage Default
{
<Data name="MCPOverrideDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>ClassName</Value></Value>
<Value name="3"><Value>Name</Value></Value>
<Value name="4"><Value>ShortDescription</Value></Value>
<Value name="5"><Value>Description</Value></Value>
<Value name="6"><Value>ToolsetsCsv</Value></Value>
<Value name="7"><Value>UpdatedBy</Value></Value>
<Value name="8"><Value>UpdatedAt</Value></Value>
</Data>
<DataLocation>^AgInt.MCPOverrideD</DataLocation>
<DefaultData>MCPOverrideDefaultData</DefaultData>
<IdLocation>^AgInt.MCPOverrideD</IdLocation>
<IndexLocation>^AgInt.MCPOverrideI</IndexLocation>
<StreamLocation>^AgInt.MCPOverrideS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
