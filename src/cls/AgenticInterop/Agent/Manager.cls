/// Builds a fully-configured AgenticInterop.Agent.HealthInterop instance
/// at request time: instantiates the agent class, attaches the LLM
/// provider, attaches all four ToolSets directly to the ToolManager so
/// cross-cutting tools resolve, then loads the nine specialist Skills via
/// SkillLoader. Returns the configured agent.
///
/// Phase 1 wires the real Provider lookup (Data.Provider rows + the
/// IRIS Secured Wallet via @{wallet.X.Y} resolution). For now Provider
/// is passed in by the caller so this class can compile and be smoke-
/// tested before Phase 1 lands.
///
/// Per restriction #2, the LLM provider used here is the chatbot's
/// runtime Provider — separate from any dev provider used by Claude Code.
Class AgenticInterop.Agent.Manager Extends %RegisteredObject
{

/// Build a HealthInterop agent ready to run. Returns OREF in pAgent.
ClassMethod Build(pProvider As %AI.Provider, Output pAgent As AgenticInterop.Agent.HealthInterop) As %Status
{
    Set tSC = $$$OK
    Try {
        // 1. Instantiate the declarative agent class.
        Set pAgent = ##class(AgenticInterop.Agent.HealthInterop).%New(pProvider)
        Set tSC = pAgent.%Init()
        Quit:$$$ISERR(tSC)

        // 2. Attach all four ToolSets directly so cross-cutting tools
        // (search_ens, search_hs, get_user_namespace, ...) are resolvable
        // by name inside Skill sub-agents that reference the same toolsets
        // via Parameter TOOLS.
        For tToolSet = "AgenticInterop.ToolSet.Production",
                       "AgenticInterop.ToolSet.Transform",
                       "AgenticInterop.ToolSet.Testing",
                       "AgenticInterop.ToolSet.Catalog" {
            Set tSC = pAgent.UseToolSet(tToolSet)
            Quit:$$$ISERR(tSC)
        }
        Quit:$$$ISERR(tSC)

        // 3. Register the nine specialist Skills as sub-agent tools.
        Set tSC = ##class(AgenticInterop.Agent.SkillLoader).LoadSkills(pAgent)
        Quit:$$$ISERR(tSC)
    } Catch ex {
        Set tSC = ex.AsStatus()
        Set pAgent = $$$NULLOREF
    }
    Quit tSC
}

/// Diagnostic: build the agent and dump its registered tools (skills +
/// any direct toolset entries). Useful to confirm scaffolding works
/// before wiring the REST chat endpoint in Phase 2-3.
ClassMethod Diagnose(pProvider As %AI.Provider, Output pInfo As %DynamicObject) As %Status
{
    Set pInfo = {}
    Set tSC = ..Build(pProvider, .agent)
    If $$$ISERR(tSC) {
        Set pInfo.ok = 0
        Set pInfo.error = $system.Status.GetErrorText(tSC)
        Quit tSC
    }
    Set pInfo.ok = 1
    Set pInfo.agentClass = $classname(agent)
    Set pInfo.namespace = $namespace
    Set pInfo.skills = ##class(AgenticInterop.Agent.SkillLoader).ListDefaultSkills()
    // ToolManager.Discover would list every tool the LLM sees; for the
    // smoke test we just confirm the manager exists.
    If $isobject(agent.ToolManager) {
        Set pInfo.toolManagerToken = agent.ToolManager."%token"
    }
    Quit $$$OK
}

}
