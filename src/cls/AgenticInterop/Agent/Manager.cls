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
        Do ..Trace("Instantiating agent class: " _ pAgentClass)
        Set pAgent = $classmethod(pAgentClass, "%New", pProvider)
        Set tSC = pAgent.%Init()
        If 'tSC { Quit }
        Do ..Trace("Agent initialized — auto-discovered all %AI.Tool subclasses")

        // 1b. Strip framework waste tools from the LLM catalog.
        Set filter = ##class(AgenticInterop.Policy.ToolFilter).%New()
        Do pAgent.ToolManager.SetDiscoveryPolicy(filter)
        Do ..Trace("Tool filter applied — stripped framework built-in tools (FileSystem, SQL, Shell)")

        // 1c. Apply Agent overlay overrides.
        Set effSysPrompt = ##class(AgenticInterop.Editor.Overlay).GetEffectiveSystemPrompt(pAgentClass)
        If effSysPrompt '= "" { Set pAgent.SystemPrompt = effSysPrompt }
        Set effTemp = ##class(AgenticInterop.Editor.Overlay).GetEffectiveTemperature(pAgentClass)
        If effTemp '= "" {
            Try { Set pAgent.Temperature = +effTemp } Catch  {}
        }
        Set effMaxIter = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMaxIterations(pAgentClass)
        If effMaxIter '= "" {
            Try { Set pAgent.MaxIterations = +effMaxIter } Catch  {}
        }

        // 2. Register tools via MCP chain or bypass.
        Set bindingMode = ##class(AgenticInterop.Editor.Overlay).GetEffectiveToolBinding(pAgentClass)
        If bindingMode = "" { Set bindingMode = "mcp" }

        If bindingMode = "mcp" {
            Set mcps = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMCPS(pAgentClass)
            Do ..Trace("Registering MCP servers: " _ mcps)
            For i=1:1:$LENGTH(mcps, ",") {
                Set mcpClass = $ZSTRIP($PIECE(mcps, ",", i), "<>W")
                If mcpClass = "" { Continue }
                ; ── Observer: each MCP server ──
                Set mcpEv = {}
                Set mcpEv.msg = "Registering MCP: " _ mcpClass
                Set mcpEv.mcp = mcpClass
                ; Get the ToolSets this MCP exposes
                Try {
                    Set mcpToolsets = $parameter(mcpClass, "TOOLSETS")
                    Set mcpEv.toolsets = mcpToolsets
                } Catch {}
                Do ..LiveFeedEvent("mcp", mcpEv)
                Set tSC = $classmethod(mcpClass, "RegisterToAgent", pAgent)
                If 'tSC { Quit }
            }
        } Else {
            Do ..Trace("Bypass mode — registering tools directly (no MCP)")
            Set tools = "AgenticInterop.Tool.Production,AgenticInterop.Tool.Transform,AgenticInterop.Tool.Testing,AgenticInterop.Tool.Catalog,AgenticInterop.Tool.Monitoring,AgenticInterop.Tool.FHIRServer"
            For i=1:1:$LENGTH(tools, ",") {
                Set cls = $PIECE(tools, ",", i)
                Do ..Trace("Registering ToolSet: " _ cls)
                Set tSC = pAgent.UseToolSet(cls)
                If 'tSC { Quit }
            }
        }
        If 'tSC { Quit }

        // 3. Register Skills.
        Set skillsCSV = ##class(AgenticInterop.Editor.Overlay).GetEffectiveSKILLS(pAgentClass)
        Do ..Trace("Loading skills...")
        Set skillCount = 0
        For si=1:1:$length(skillsCSV, ",") {
            Set sName = $zstrip($piece(skillsCSV, ",", si), "<>W")
            If sName = "" Continue
            Set skillCount = skillCount + 1
            ; short name: last piece of class name
            Set shortName = $piece(sName, ".", $length(sName, "."))
            Set skillEv = {}
            Set skillEv.msg = "Loading skill: " _ shortName
            Set skillEv.class = sName
            Do ..LiveFeedEvent("skill", skillEv)
        }
        Set tSC = ##class(AgenticInterop.Agent.SkillLoader).LoadSkills(pAgent, skillsCSV)
        If 'tSC { Quit }
        Do ..Trace(skillCount _ " skills loaded into agent system prompt")

        // 4. Confirmation gate.
        Set policy = ##class(AgenticInterop.Policy.ConfirmationGate).%New()
        Set policy.ApprovedTokens = $get(%agenticApprovedTokens, "")
        Do pAgent.ToolManager.SetAuthPolicy(policy)
        Do ..Trace("Confirmation gate attached")

        // 5. Catalog search (RAG knowledge bases).
        Do ##class(AgenticInterop.Catalog.Attach).ToAgent(pAgent)
        Do ..Trace("RAG catalogs attached (search_ens, search_hs)")

        Do ..Trace("Agent build complete")
    } Catch ex {
        Set tSC = ex.AsStatus()
        Set pAgent = $$$NULLOREF
    }
    Quit tSC
}

/// Write a trace event to the LiveFeed global (observer terminal).
/// Safe to call from any context — silently no-ops if no session is active.
ClassMethod Trace(pMsg As %String) [ Internal ]
{
    Do ..LiveFeedEvent("trace", {"msg":(pMsg)})
}

/// Write a typed event to the LiveFeed global. Shared helper for
/// Manager.Build and other non-ChatService code paths.
ClassMethod LiveFeedEvent(pType As %String, pData As %DynamicObject) [ Internal ]
{
    Set sid = $get(%agenticChatSessionId)
    If sid = "" Quit
    Set entry = {}
    Set entry.type = pType
    Set entry.data = pData
    Set entry.ts = $zdatetime($horolog, 3, 1)
    Set entry.elapsed = $fnumber($zhorolog - $get(%agenticChatStart, $zhorolog), "", 1)
    Set seq = $increment(^AgInt.LiveFeed(sid))
    Set ^AgInt.LiveFeed(sid, seq) = entry.%ToJSON()
    Set ^AgInt.LiveFeed("active", sid) = $horolog
}

/// Emit a tool_start event to the Observer live feed. Called at the
/// top of every %AI.Tool method so the Observer terminal shows the
/// tool name the moment the Rust bridge dispatches it — DURING
/// agent.Chat(), not after. Safe to call anywhere; silently no-ops
/// if no observer session is active.
ClassMethod ToolStart(pName As %String) [ Internal ]
{
    Try {
        Set sid = $get(%agenticChatSessionId)
        If sid = "" Quit
        Set ev = {}
        Set ev.name = pName
        Set ev.tool = pName
        Set ev.msg = pName
        Do ..LiveFeedEvent("tool_start", ev)
    } Catch {}
}

/// Emit a tool_result event to the Observer live feed. Called at the
/// end of every %AI.Tool method with the result object so the
/// Observer shows whether the tool succeeded or failed — DURING
/// agent.Chat(), not after.
ClassMethod ToolDone(pName As %String, pResult As %DynamicObject = "") [ Internal ]
{
    Try {
        Set sid = $get(%agenticChatSessionId)
        If sid = "" Quit
        Set ev = {}
        Set ev.name = pName
        Set ev.tool = pName
        Set ev.msg = pName
        If $isobject(pResult) {
            If pResult.%IsDefined("ok") Set ev.ok = pResult.ok
            If pResult.%IsDefined("error") Set ev.error = $extract(pResult.error, 1, 200)
        }
        Do ..LiveFeedEvent("tool_result", ev)
    } Catch {}
}

}
