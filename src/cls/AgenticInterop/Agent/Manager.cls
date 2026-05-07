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

        // 1a. Apply Agent overlay overrides for runtime fields the
        //     framework consumes via OREF properties (system prompt,
        //     temperature). MCPS / SKILLS use Overlay accessors below.
        //     If no override row exists, the helpers fall through to
        //     the compiled class defaults.
        Set effSysPrompt = ##class(AgenticInterop.Editor.Overlay).GetEffectiveSystemPrompt(pAgentClass)
        If effSysPrompt '= "" { Set pAgent.SystemPrompt = effSysPrompt }
        Set effTemp = ##class(AgenticInterop.Editor.Overlay).GetEffectiveTemperature(pAgentClass)
        If effTemp '= "" {
            Try { Set pAgent.Temperature = +effTemp } Catch  {}
        }
        // MaxIterations: the %AI.Agent base class has a PROPERTY
        // MaxIterations (InitialExpression=10) that StreamChat uses
        // internally. The class PARAMETER MAXITERATIONS is separate
        // and not wired to the property. We must explicitly push the
        // effective value onto the OREF so StreamChat respects it.
        Set effMaxIter = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMaxIterations(pAgentClass)
        If effMaxIter '= "" {
            Try { Set pAgent.MaxIterations = +effMaxIter } Catch  {}
        }

        // 2. Register each MCP listed in Parameter MCPS (overlay-aware).
        Set mcps = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMCPS(pAgentClass)
        If mcps '= "" {
            For i=1:1:$LENGTH(mcps, ",") {
                Set cls = $ZSTRIP($PIECE(mcps, ",", i), "<>W")
                If cls = "" { Continue }
                Set tSC = $classmethod(cls, "RegisterToAgent", pAgent)
                If 'tSC { Quit }
            }
            If 'tSC { Quit }
        }

        // 3. Register Skills (overlay-aware).
        Set tSC = ##class(AgenticInterop.Agent.SkillLoader).LoadSkills(pAgent, ##class(AgenticInterop.Editor.Overlay).GetEffectiveSKILLS(pAgentClass))
        If 'tSC { Quit }

        // 4. Phase 4 confirmation gate. Every tool call funnels through
        //    %CanExecute on this policy; mutating tools (start_*,
        //    delete_*, etc., or definitions with requires_confirmation:
        //    true) are denied with a structured error the chat surface
        //    can render as an Approve / Reject prompt. Pre-approved
        //    tokens (set by ChatService when the user has already
        //    approved a specific call this turn) bypass the gate.
        //
        //    IMPORTANT: use SetAuthPolicy() — the explicit method —
        //    NOT direct property assignment. The auto-generated
        //    AuthPolicySet only stores the OREF on the ObjectScript
        //    side; SetAuthPolicy also registers the policy with the
        //    Rust-side ToolMgr via %token, which is what actually
        //    causes %CanExecute to fire on each call. The reference
        //    repo's comment ("framework bypasses it") was about a
        //    different orchestrator pattern, not this method.
        Set policy = ##class(AgenticInterop.Policy.ConfirmationGate).%New()
        Set policy.ApprovedTokens = $get(%agenticApprovedTokens, "")
        Do pAgent.ToolManager.SetAuthPolicy(policy)

        // 5. Phase 5 catalog search. Attaches search_ens / search_hs
        //    KnowledgeBase tools when their underlying tables are
        //    populated. If the user hasn't built the catalogs yet, no
        //    tool fires and chat continues without that input.
        Do ##class(AgenticInterop.Catalog.Attach).ToAgent(pAgent)
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
