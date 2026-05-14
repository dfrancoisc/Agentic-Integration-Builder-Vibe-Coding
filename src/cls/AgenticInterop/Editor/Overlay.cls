/// Overlay facade — read/write user customizations on top of shipped
/// classes. Currently covers MCPs; Agent and ToolSet overlays slot
/// into the same shape when they land.
///
/// Read flow:
///   GetEffectiveMCP(class) → returns a %DynamicObject whose fields
///   come from the override row when present, otherwise from the
///   compiled class metadata. Used by MCPService.Get and the chat
///   runtime (Manager.Build, MCP.Base.RegisterToAgent).
///
/// Write flow:
///   SaveMCPOverride(class, props, user) → upserts a row in
///   AgenticInterop.Data.MCPOverride. Only non-empty fields in props
///   are persisted; an empty string is treated as "remove the
///   override for this field" so the operator can revert one column
///   without nuking the whole row.
///
/// Reset flow:
///   ResetMCP(class) → deletes the override row. The class then
///   serves whatever the shipping module compiled.
Class AgenticInterop.Editor.Overlay Extends %RegisteredObject
{

/// Read the effective MCP shape — class metadata layered with the
/// override row if one exists. Always returns a %DynamicObject; the
/// extra `customized: true|false` field tells the UI whether to
/// render the "CUSTOMIZED" badge.
ClassMethod GetEffectiveMCP(pClass As %String) As %DynamicObject
{
    Set util = "AgenticInterop.Editor.Util"
    Set out = {}
    Set out.class = pClass
    Set out.name = $classmethod(util, "ParamDefault", pClass, "NAME")
    Set out.shortDescription = $classmethod(util, "ParamDefault", pClass, "DESCRIPTION")
    Set out.description = $classmethod(util, "ClassDescription", pClass)
    Set toolsetsCsv = $classmethod(util, "ParamDefault", pClass, "TOOLSETS")
    Set out.toolsetsCsv = toolsetsCsv
    Set out.toolsets = $classmethod(util, "CsvToArray", toolsetsCsv)
    Set out.customized = 0

    // If a User.MCP.* class is ever passed in, we still permit
    // overlaying — but in practice user-authored MCPs save to .cls
    // directly so the override row is empty. Lookup is harmless.
    Set ovr = ..%OpenOverride(pClass)
    If $isobject(ovr) {
        If ovr.Name '= ""             { Set out.name = ovr.Name }
        If ovr.ShortDescription '= "" { Set out.shortDescription = ovr.ShortDescription }
        If ovr.Description '= ""      { Set out.description = ovr.Description }
        If ovr.ToolsetsCsv '= ""      {
            Set out.toolsetsCsv = ovr.ToolsetsCsv
            Set out.toolsets = $classmethod(util, "CsvToArray", ovr.ToolsetsCsv)
        }
        Set out.customized = 1
        Set out.updatedBy = ovr.UpdatedBy
        Set out.updatedAt = ovr.UpdatedAt
    }
    Quit out
}

/// Upsert an override row. Each field in props that's defined and
/// non-null is written; fields that are missing or null leave the
/// row's existing value alone (i.e., partial updates work). To
/// clear an individual override field, send the field as the
/// literal empty string — the row will be saved with that field
/// blank and the read path will fall through to .cls.
ClassMethod SaveMCPOverride(pClass As %String, pProps As %DynamicObject, pUser As %String = "") As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set ovr = ..%OpenOverride(pClass)
    If '$isobject(ovr) {
        Set ovr = ##class(AgenticInterop.Data.MCPOverride).%New()
        Set ovr.ClassName = pClass
    }
    If pProps.%IsDefined("name")             { Set ovr.Name = pProps.name }
    If pProps.%IsDefined("shortDescription") { Set ovr.ShortDescription = pProps.shortDescription }
    If pProps.%IsDefined("description")      { Set ovr.Description = pProps.description }
    If pProps.%IsDefined("toolsetsCsv")      { Set ovr.ToolsetsCsv = pProps.toolsetsCsv }
    If pProps.%IsDefined("toolsets") {
        Set csv = $S($isobject(pProps.toolsets):$classmethod(util, "ArrayToCsv", pProps.toolsets), 1:pProps.toolsets)
        Set ovr.ToolsetsCsv = csv
    }
    Set ovr.UpdatedBy = pUser
    Set ovr.UpdatedAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
    Quit ovr.%Save()
}

/// Drop the override row entirely — restores the class to its
/// shipped defaults. Idempotent: returns OK whether a row existed
/// or not.
ClassMethod ResetMCP(pClass As %String) As %Status
{
    Set ovr = ..%OpenOverride(pClass)
    If '$isobject(ovr) Quit $$$OK
    Quit ##class(AgenticInterop.Data.MCPOverride).%DeleteId(ovr.%Id())
}

/// Runtime helper — return the effective TOOLSETS CSV for a given
/// MCP class. Used by MCP.Base.RegisterToAgent (which can't use
/// the compile-time `..#TOOLSETS` macro, since that misses
/// overrides).
ClassMethod GetEffectiveTOOLSETS(pClass As %String) As %String
{
    Set ovr = ..%OpenOverride(pClass)
    If $isobject(ovr), ovr.ToolsetsCsv '= "" Quit ovr.ToolsetsCsv
    Quit $classmethod("AgenticInterop.Editor.Util", "ParamDefault", pClass, "TOOLSETS")
}

ClassMethod %OpenOverride(pClass As %String) As AgenticInterop.Data.MCPOverride [ Internal ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM AgenticInterop_Data.MCPOverride WHERE ClassName = ?", pClass)
    If 'rs.%Next() Quit ""
    Quit ##class(AgenticInterop.Data.MCPOverride).%OpenId(rs.%Get("ID"))
}

// ----------------------------------------------------------------
// ToolSet overlay — same model as MCP. See class header.
// ----------------------------------------------------------------

ClassMethod GetEffectiveToolSet(pClass As %String) As %DynamicObject
{
    Set util = "AgenticInterop.Editor.Util"
    Set out = {}
    Set out.class = pClass
    Set out.name = $classmethod(util, "ParamDefault", pClass, "NAME")
    Set out.description = $classmethod(util, "ClassDescription", pClass)
    Set out.definitionRaw = $classmethod(util, "XDataBody", pClass, "Definition")
    Set out.toolManifest = $classmethod(util, "XDataBody", pClass, "ToolManifest")
    Set out.customized = 0
    Set ovr = ..%OpenToolSetOverride(pClass)
    If $isobject(ovr) {
        If ovr.Name '= ""          { Set out.name = ovr.Name }
        If ovr.Description '= ""   { Set out.description = ovr.Description }
        If ovr.DefinitionRaw '= "" { Set out.definitionRaw = ovr.DefinitionRaw }
        If ovr.ToolManifest '= ""  { Set out.toolManifest = ovr.ToolManifest }
        Set out.customized = 1
        Set out.updatedBy = ovr.UpdatedBy
        Set out.updatedAt = ovr.UpdatedAt
    }
    Quit out
}

ClassMethod SaveToolSetOverride(pClass As %String, pProps As %DynamicObject, pUser As %String = "") As %Status
{
    Set ovr = ..%OpenToolSetOverride(pClass)
    If '$isobject(ovr) {
        Set ovr = ##class(AgenticInterop.Data.ToolSetOverride).%New()
        Set ovr.ClassName = pClass
    }
    If pProps.%IsDefined("name")          { Set ovr.Name = pProps.name }
    If pProps.%IsDefined("description")   { Set ovr.Description = pProps.description }
    If pProps.%IsDefined("definitionRaw") { Set ovr.DefinitionRaw = pProps.definitionRaw }
    If pProps.%IsDefined("toolManifest")  { Set ovr.ToolManifest = pProps.toolManifest }
    Set ovr.UpdatedBy = pUser
    Set ovr.UpdatedAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
    Quit ovr.%Save()
}

ClassMethod ResetToolSet(pClass As %String) As %Status
{
    Set ovr = ..%OpenToolSetOverride(pClass)
    If '$isobject(ovr) Quit $$$OK
    Quit ##class(AgenticInterop.Data.ToolSetOverride).%DeleteId(ovr.%Id())
}

ClassMethod %OpenToolSetOverride(pClass As %String) As AgenticInterop.Data.ToolSetOverride [ Internal ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM AgenticInterop_Data.ToolSetOverride WHERE ClassName = ?", pClass)
    If 'rs.%Next() Quit ""
    Quit ##class(AgenticInterop.Data.ToolSetOverride).%OpenId(rs.%Get("ID"))
}

// ----------------------------------------------------------------
// Agent overlay — same model. Adds runtime helpers consumed by
// Manager.Build / ChatService for system prompt + temperature +
// max iterations + MCPS + SKILLS.
// ----------------------------------------------------------------

ClassMethod GetEffectiveAgent(pClass As %String) As %DynamicObject
{
    Set util = "AgenticInterop.Editor.Util"
    Set out = {}
    Set out.class = pClass
    Set out.name = $classmethod(util, "ParamDefault", pClass, "NAME")
    Set out.description = $classmethod(util, "ClassDescription", pClass)
    Set out.instructions = $classmethod(util, "XDataBody", pClass, "INSTRUCTIONS")
    Set out.temperature = $classmethod(util, "ParamDefault", pClass, "TEMPERATURE")
    Set out.maxIterations = $classmethod(util, "ParamDefault", pClass, "MAXITERATIONS")
    Set mcpsCsv = $classmethod(util, "ParamDefault", pClass, "MCPS")
    Set skillsCsv = $classmethod(util, "ParamDefault", pClass, "SKILLS")
    Set out.mcpsCsv = mcpsCsv
    Set out.mcps = $classmethod(util, "CsvToArray", mcpsCsv)
    Set out.skillsCsv = skillsCsv
    Set out.skills = $classmethod(util, "CsvToArray", skillsCsv)
    Set out.provider = $classmethod(util, "ParamDefault", pClass, "PROVIDER")
    Set out.toolBinding = $classmethod(util, "ParamDefault", pClass, "TOOLBINDING")
    Set out.customized = 0
    Set ovr = ..%OpenAgentOverride(pClass)
    If $isobject(ovr) {
        If ovr.Name '= ""          { Set out.name = ovr.Name }
        If ovr.Description '= ""   { Set out.description = ovr.Description }
        If ovr.Instructions '= ""  { Set out.instructions = ovr.Instructions }
        If ovr.Temperature '= ""   { Set out.temperature = ovr.Temperature }
        If ovr.MaxIterations '= "" { Set out.maxIterations = ovr.MaxIterations }
        If ovr.McpsCsv '= "" {
            Set out.mcpsCsv = ovr.McpsCsv
            Set out.mcps = $classmethod(util, "CsvToArray", ovr.McpsCsv)
        }
        If ovr.SkillsCsv '= "" {
            Set out.skillsCsv = ovr.SkillsCsv
            Set out.skills = $classmethod(util, "CsvToArray", ovr.SkillsCsv)
        }
        If ovr.Provider '= ""      { Set out.provider = ovr.Provider }
        If ovr.ToolBinding '= ""   { Set out.toolBinding = ovr.ToolBinding }
        Set out.customized = 1
        Set out.updatedBy = ovr.UpdatedBy
        Set out.updatedAt = ovr.UpdatedAt
    }
    Quit out
}

ClassMethod SaveAgentOverride(pClass As %String, pProps As %DynamicObject, pUser As %String = "") As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set ovr = ..%OpenAgentOverride(pClass)
    If '$isobject(ovr) {
        Set ovr = ##class(AgenticInterop.Data.AgentOverride).%New()
        Set ovr.ClassName = pClass
    }
    If pProps.%IsDefined("name")          { Set ovr.Name = pProps.name }
    If pProps.%IsDefined("description")   { Set ovr.Description = pProps.description }
    If pProps.%IsDefined("instructions")  { Set ovr.Instructions = pProps.instructions }
    If pProps.%IsDefined("temperature")   { Set ovr.Temperature = pProps.temperature }
    If pProps.%IsDefined("maxIterations") { Set ovr.MaxIterations = pProps.maxIterations }
    If pProps.%IsDefined("mcps") {
        Set ovr.McpsCsv = $S($isobject(pProps.mcps):$classmethod(util, "ArrayToCsv", pProps.mcps), 1:pProps.mcps)
    } ElseIf pProps.%IsDefined("mcpsCsv") {
        Set ovr.McpsCsv = pProps.mcpsCsv
    }
    If pProps.%IsDefined("skills") {
        Set ovr.SkillsCsv = $S($isobject(pProps.skills):$classmethod(util, "ArrayToCsv", pProps.skills), 1:pProps.skills)
    } ElseIf pProps.%IsDefined("skillsCsv") {
        Set ovr.SkillsCsv = pProps.skillsCsv
    }
    If pProps.%IsDefined("provider")      { Set ovr.Provider = pProps.provider }
    If pProps.%IsDefined("toolBinding")   { Set ovr.ToolBinding = pProps.toolBinding }
    Set ovr.UpdatedBy = pUser
    Set ovr.UpdatedAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
    Quit ovr.%Save()
}

ClassMethod ResetAgent(pClass As %String) As %Status
{
    Set ovr = ..%OpenAgentOverride(pClass)
    If '$isobject(ovr) Quit $$$OK
    Quit ##class(AgenticInterop.Data.AgentOverride).%DeleteId(ovr.%Id())
}

/// Runtime helpers — Manager.Build calls these instead of $parameter().
ClassMethod GetEffectiveMCPS(pClass As %String) As %String
{
    Set ovr = ..%OpenAgentOverride(pClass)
    If $isobject(ovr), ovr.McpsCsv '= "" Quit ovr.McpsCsv
    Quit $classmethod("AgenticInterop.Editor.Util", "ParamDefault", pClass, "MCPS")
}

ClassMethod GetEffectiveSKILLS(pClass As %String) As %String
{
    Set ovr = ..%OpenAgentOverride(pClass)
    If $isobject(ovr), ovr.SkillsCsv '= "" Quit ovr.SkillsCsv
    Quit $classmethod("AgenticInterop.Editor.Util", "ParamDefault", pClass, "SKILLS")
}

ClassMethod GetEffectiveSystemPrompt(pClass As %String) As %String
{
    Set ovr = ..%OpenAgentOverride(pClass)
    If $isobject(ovr), ovr.Instructions '= "" Quit ovr.Instructions
    Quit $classmethod("AgenticInterop.Editor.Util", "XDataBody", pClass, "INSTRUCTIONS")
}

ClassMethod GetEffectiveTemperature(pClass As %String) As %String
{
    Set ovr = ..%OpenAgentOverride(pClass)
    If $isobject(ovr), ovr.Temperature '= "" Quit ovr.Temperature
    Quit $classmethod("AgenticInterop.Editor.Util", "ParamDefault", pClass, "TEMPERATURE")
}

ClassMethod GetEffectiveMaxIterations(pClass As %String) As %String
{
    Set ovr = ..%OpenAgentOverride(pClass)
    If $isobject(ovr), ovr.MaxIterations '= "" Quit ovr.MaxIterations
    Quit $classmethod("AgenticInterop.Editor.Util", "ParamDefault", pClass, "MAXITERATIONS")
}

/// Returns the effective tool binding mode for the agent.
/// "mcp" = Agent -> MCP Server -> ToolSet -> Tool (proper chain).
/// "bypass" = Agent -> Tool (direct, no MCP indirection).
ClassMethod GetEffectiveToolBinding(pClass As %String) As %String
{
    Set ovr = ..%OpenAgentOverride(pClass)
    If $isobject(ovr), ovr.ToolBinding '= "" Quit ovr.ToolBinding
    Quit $classmethod("AgenticInterop.Editor.Util", "ParamDefault", pClass, "TOOLBINDING")
}

ClassMethod %OpenAgentOverride(pClass As %String) As AgenticInterop.Data.AgentOverride [ Internal ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM AgenticInterop_Data.AgentOverride WHERE ClassName = ?", pClass)
    If 'rs.%Next() Quit ""
    Quit ##class(AgenticInterop.Data.AgentOverride).%OpenId(rs.%Get("ID"))
}

}
