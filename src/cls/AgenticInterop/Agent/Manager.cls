/// Builds a fully-configured AgenticInterop.Agent.HealthInterop instance
/// at request time: instantiates the agent class, attaches the LLM
/// provider, registers each MCP listed in the Agent's Parameter MCPS,
/// then loads the Skills listed in Parameter SKILLS via SkillLoader.
/// Returns the configured agent.
///
/// All agent → MCP and agent → Skill bindings are CSV parameters on the
/// Agent class itself, edited by the admin UI via the Editor REST API
/// (see docs/PLAN.md, "Admin UI — per-entity field specs"). No CSV is
/// hardcoded in Manager.
///
/// Per restriction #2, the LLM provider used here is the chatbot's
/// runtime Provider — separate from any dev provider used by Claude Code.
Class AgenticInterop.Agent.Manager Extends %RegisteredObject
{

/// Build a HealthInterop agent ready to run. Agent class defaults to
/// AgenticInterop.Agent.HealthInterop; pass another class name to build
/// a different agent (multi-agent support per data model).
ClassMethod Build(pProvider As %AI.Provider, Output pAgent As %AI.Agent, pAgentClass As %String = "AgenticInterop.Agent.HealthInterop") As %Status
{
    Set tSC = $$$OK
    Try {
        // 1. Instantiate the declarative agent class.
        Set pAgent = $classmethod(pAgentClass, "%New", pProvider)
        Set tSC = pAgent.%Init()
        If 'tSC { Quit }

        // 2. Register each MCP listed in Parameter MCPS. Each MCP delegates
        //    to %AI.MCP.Service.LoadToolSetsToManager via its own
        //    RegisterToAgent classmethod (see AgenticInterop.MCP.Base).
        Set mcps = $parameter(pAgentClass, "MCPS")
        If mcps '= "" {
            For i=1:1:$LENGTH(mcps, ",") {
                Set cls = $ZSTRIP($PIECE(mcps, ",", i), "<>W")
                If cls = "" { Continue }
                Set tSC = $classmethod(cls, "RegisterToAgent", pAgent)
                If 'tSC { Quit }
            }
            If 'tSC { Quit }
        }

        // 3. Register Skills as sub-agent tools. SkillLoader honors the
        //    Agent's Parameter SKILLS first; falls back to its own
        //    DEFAULTSKILLS list if the parameter is empty.
        Set tSC = ##class(AgenticInterop.Agent.SkillLoader).LoadSkills(pAgent, $parameter(pAgentClass, "SKILLS"))
        If 'tSC { Quit }
    } Catch ex {
        Set tSC = ex.AsStatus()
        Set pAgent = $$$NULLOREF
    }
    Quit tSC
}

/// Diagnostic: build the agent and dump its registered tools and skill
/// list. Returns a %DynamicObject suitable for the admin UI's Test panel.
ClassMethod Diagnose(pProvider As %AI.Provider, Output pInfo As %DynamicObject, pAgentClass As %String = "AgenticInterop.Agent.HealthInterop") As %Status
{
    Set pInfo = {}
    Set tSC = ..Build(pProvider, .agent, pAgentClass)
    If 'tSC {
        Set pInfo.ok = 0
        Set pInfo.error = $system.Status.GetErrorText(tSC)
        Quit tSC
    }
    Set pInfo.ok = 1
    Set pInfo.agentClass = $classname(agent)
    Set pInfo.namespace = $namespace
    Set pInfo.mcps = []
    Set mcps = $parameter(pAgentClass, "MCPS")
    For i=1:1:$LENGTH(mcps, ",") {
        Set cls = $ZSTRIP($PIECE(mcps, ",", i), "<>W")
        If cls '= "" { Do pInfo.mcps.%Push(cls) }
    }
    Set pInfo.skills = []
    Set skills = $parameter(pAgentClass, "SKILLS")
    For i=1:1:$LENGTH(skills, ",") {
        Set cls = $ZSTRIP($PIECE(skills, ",", i), "<>W")
        If cls '= "" { Do pInfo.skills.%Push(cls) }
    }
    If $isobject(agent.ToolManager) {
        Set pInfo.toolManagerToken = agent.ToolManager."%token"
    }
    Quit $$$OK
}

}
