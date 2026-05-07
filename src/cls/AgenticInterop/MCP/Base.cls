/// Base class for AgenticInterop MCPs.
///
/// MCPs are real %AI.MCP.Service subclasses (revised design — see
/// docs/PLAN.md, "MCP class strategy"). They are the named bundle of
/// ToolSets that the agent registers as one unit. Wire transport is
/// opt-in: in-process consumers call RegisterToAgent which delegates to
/// %AI.MCP.Service.LoadToolSetsToManager and never touches the
/// CSP/WebSocket side.
///
/// Each concrete MCP supplies:
///   Parameter NAME         — short id, e.g. "production"
///   Parameter DESCRIPTION  — one or two sentences for the admin UI
///   Parameter TOOLSETS     — CSV of %AI.ToolSet class names
///
/// The UI roundtrips these via %Dictionary.ParameterDefinition. Adding,
/// removing, or reordering a ToolSet is a single-row edit in the UI plus
/// a class recompile.
Class AgenticInterop.MCP.Base Extends %AI.MCP.Service [ Abstract ]
{

Parameter NAME = "";

Parameter DESCRIPTION = "";

Parameter TOOLSETS = "";

/// Register this MCP's ToolSets onto the agent's ToolManager. Called by
/// AgenticInterop.Agent.Manager.Build for each MCP listed in the Agent's
/// Parameter MCPS.
///
/// Reads TOOLSETS through AgenticInterop.Editor.Overlay so user
/// customizations (saved into AgenticInterop.Data.MCPOverride) win
/// over the .cls Parameter default. `..#TOOLSETS` (compile-time
/// macro) ignores overrides — DON'T use it here.
ClassMethod RegisterToAgent(pAgent As %AI.Agent) As %Status
{
    Set tSC = $$$OK
    Set toolsets = ##class(AgenticInterop.Editor.Overlay).GetEffectiveTOOLSETS($CLASSNAME())
    If toolsets = "" { Quit tSC }
    For i=1:1:$LENGTH(toolsets, ",") {
        Set cls = $ZSTRIP($PIECE(toolsets, ",", i), "<>W")
        If cls = "" { Continue }
        Set sub = pAgent.UseToolSet(cls)
        If 'sub { Set tSC = $system.Status.AppendStatus(tSC, sub) }
    }
    Quit tSC
}

/// Returns this MCP's ToolSet class names as a %DynamicArray for UI
/// listing. Driven by the TOOLSETS parameter; updated on recompile.
ClassMethod ListToolSets() As %DynamicArray
{
    Set arr = []
    Set toolsets = ..#TOOLSETS
    If toolsets = "" { Quit arr }
    For i=1:1:$LENGTH(toolsets, ",") {
        Set cls = $ZSTRIP($PIECE(toolsets, ",", i), "<>W")
        If cls '= "" { Do arr.%Push(cls) }
    }
    Quit arr
}

/// Convenience accessor — returns the configured display name (or the
/// short class name if NAME parameter is empty).
ClassMethod GetName() As %String
{
    Set name = ..#NAME
    If name '= "" { Quit name }
    Set cls = $CLASSNAME()
    Quit $PIECE(cls, ".", $LENGTH(cls, "."))
}

/// Convenience accessor — returns the configured description.
ClassMethod GetDescription() As %String [ CodeMode = expression ]
{
..#DESCRIPTION
}

}
