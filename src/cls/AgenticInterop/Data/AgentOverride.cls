/// User customization layer over a shipped Agent class. Same shape
/// and rationale as AgenticInterop.Data.MCPOverride. Fields with
/// runtime impact:
///
///   Instructions   — XData INSTRUCTIONS body (system prompt). Manager.Build
///                    sets agent.SystemPrompt from this when present.
///   Temperature    — Parameter TEMPERATURE. Manager.Build sets
///                    agent.Temperature.
///   MaxIterations  — Parameter MAXITERATIONS. ChatService reads this
///                    when calling agent.Run().
///   McpsCsv        — Parameter MCPS. Manager.Build registers each MCP.
///   SkillsCsv      — Parameter SKILLS. SkillLoader honors this list.
///
/// Cosmetic-only fields (Name, Description) round-trip through the
/// editor for UI consistency.
Class AgenticInterop.Data.AgentOverride Extends (%Persistent, %JSON.Adaptor)
{

Property ClassName As %String(MAXLEN = 200) [ Required ];

Property Name As %String(MAXLEN = 200);

Property Description As %String(MAXLEN = 4000);

Property Instructions As %String(MAXLEN = 32000);

Property Temperature As %String(MAXLEN = 16);

Property MaxIterations As %String(MAXLEN = 16);

Property McpsCsv As %String(MAXLEN = 4000);

Property SkillsCsv As %String(MAXLEN = 4000);

Property Provider As %String(MAXLEN = 200);

/// "mcp" = Agent -> MCP -> ToolSet -> Tool chain.
/// "bypass" = Agent -> Tool (direct, no MCP indirection).
/// Empty = fall through to the class Parameter TOOLBINDING.
Property ToolBinding As %String(MAXLEN = 16);

Property UpdatedBy As %String(MAXLEN = 128);

Property UpdatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Index ClassNameIdx On ClassName [ Unique ];

Storage Default
{
<Data name="AgentOverrideDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>ClassName</Value></Value>
<Value name="3"><Value>Name</Value></Value>
<Value name="4"><Value>Description</Value></Value>
<Value name="5"><Value>Instructions</Value></Value>
<Value name="6"><Value>Temperature</Value></Value>
<Value name="7"><Value>MaxIterations</Value></Value>
<Value name="8"><Value>McpsCsv</Value></Value>
<Value name="9"><Value>SkillsCsv</Value></Value>
<Value name="10"><Value>Provider</Value></Value>
<Value name="11"><Value>UpdatedBy</Value></Value>
<Value name="12"><Value>UpdatedAt</Value></Value>
<Value name="13"><Value>ToolBinding</Value></Value>
</Data>
<DataLocation>^AgInt.AgentOverrideD</DataLocation>
<DefaultData>AgentOverrideDefaultData</DefaultData>
<IdLocation>^AgInt.AgentOverrideD</IdLocation>
<IndexLocation>^AgInt.AgentOverrideI</IndexLocation>
<StreamLocation>^AgInt.AgentOverrideS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
