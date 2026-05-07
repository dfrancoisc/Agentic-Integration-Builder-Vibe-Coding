/// Iteration-level monitor for %AI.Agent.Run() calls. Enforces a hard
/// wall-clock deadline and a token budget so a runaway tool-use loop
/// cannot burn the whole CSP gateway timeout silently — converts the
/// known framework toolset-hang (see project_agent_toolset_hang memory)
/// into a fast, actionable error instead of a multi-minute freeze.
///
/// The framework invokes OnIterationStart() before each LLM round and
/// OnIterationComplete() after — throwing from either method aborts
/// the loop cleanly. We track iteration count + cumulative token usage
/// so the chat envelope can surface "completed in 4 iterations" or
/// "stopped at 60s deadline / 50k tokens" in the response.
///
/// Pattern ported from Catalog.AgentMonitor in
/// dfrancoisc/new-interoperability-health.
///
/// Usage:
///   Set monitor = ##class(AgenticInterop.Agent.Monitor).%New(60, 50000)
///   Set response = agent.Run(session, message, agent.MaxIterations, monitor)
///   Write monitor.IterationCount, ! ; how many turns ran
///   Write monitor.TotalTokens, ! ; cumulative tokens
Class AgenticInterop.Agent.Monitor Extends %RegisteredObject
{

Property StartTime As %Float;

/// Hard wall-clock ceiling in seconds. Default 60 — short enough that
/// a runaway loop fails inside the 90s client-side ceiling the
/// no-timeouts-in-chat memory imposes.
Property DeadlineSecs As %Integer [ InitialExpression = 60 ];

/// Total token budget across all iterations. Default 50,000 — generous
/// for planning, tight enough to catch a model flooding tool calls.
Property TokenBudget As %Integer [ InitialExpression = 50000 ];

Property TotalTokens As %Integer [ InitialExpression = 0 ];

Property IterationCount As %Integer [ InitialExpression = 0 ];

/// Last tool call seen — informational. The chat envelope can surface
/// "the agent invoked X tool" in its trailing meta line.
Property LastToolName As %String(MAXLEN = 200);

/// Every tool-call name captured across the iteration loop, in fire
/// order. Populated from OnIterationComplete (intermediate responses
/// where HasToolCalls=true) AND from a parallel scan of session.GetMessage
/// at the end so we see calls the framework dispatched even if our
/// callback didn't get a HasToolCalls=true response object.
Property ToolCallTrace As %String(MAXLEN = 4000);

Method %OnNew(deadlineSecs As %Integer = 60, tokenBudget As %Integer = 50000) As %Status
{
    Set ..StartTime = $zhorolog
    Set ..DeadlineSecs = deadlineSecs
    Set ..TokenBudget = tokenBudget
    Quit $$$OK
}

/// Called by %AI.Agent.Run BEFORE each LLM invocation. Throw to abort.
Method OnIterationStart(iteration As %Integer, maxIter As %Integer, session As %AI.Agent.Session)
{
    Set ..IterationCount = iteration
    Set elapsed = $zhorolog - ..StartTime
    If elapsed > ..DeadlineSecs {
        Set msg = "Agent deadline exceeded: " _ $fnumber(elapsed, "", 1) _ "s > " _ ..DeadlineSecs _ "s. Tool-result framework hang? Try a narrower question or split it into steps."
        $$$ThrowStatus($$$ERROR($$$GeneralError, msg))
    }
}

/// Called AFTER each LLM round. Throw to abort. Tracks token usage
/// across providers (Bedrock returns input_tokens + output_tokens;
/// Anthropic-direct uses total_tokens; we tolerate either shape).
Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
{
    Try {
        Set u = response.Usage
        If $isobject(u) {
            Set t = 0
            Try { Set t = +u."total_tokens" } Catch  {}
            If 't { Try { Set t = (+u."input_tokens") + (+u."output_tokens") } Catch  {} }
            Set ..TotalTokens = ..TotalTokens + t
        }
    } Catch  {}
    If ..TotalTokens > ..TokenBudget {
        Set msg = "Agent token budget exceeded: " _ ..TotalTokens _ " > " _ ..TokenBudget _ " tokens."
        $$$ThrowStatus($$$ERROR($$$GeneralError, msg))
    }
    // Capture every tool name the framework saw on this iteration.
    // For Bedrock the intermediate response (the one that triggered
    // a tool dispatch) is what carries the tool_use frames; the final
    // response after tool results have been replayed has no calls.
    Try {
        If response.HasToolCalls() {
            Set callIter = response.ToolCalls.%GetIterator()
            While callIter.%GetNext(.callKey, .call) {
                Set toolName = ""
                Try { Set toolName = call.name } Catch  {}
                If toolName '= "" {
                    Set ..LastToolName = toolName
                    Set ..ToolCallTrace = ..ToolCallTrace _ $S(..ToolCallTrace="":"", 1:",") _ toolName
                }
            }
        }
    } Catch  {}
}

/// Walk the session transcript after the loop ends and capture every
/// tool dispatch from the message stream. Belt-and-suspenders to the
/// OnIterationComplete capture: some framework versions deliver only
/// the FINAL response to the callback, so HasToolCalls() returns 0
/// even when tools fired earlier in the same Run(). The transcript
/// is the source of truth — every dispatched tool leaves a
/// `role=tool` message behind.
Method CaptureFromSession(session As %AI.Agent.Session)
{
    If '$isobject(session) Quit
    Try {
        Set count = session.MessageCount()
        For i=0:1:count-1 {
            Set m = session.GetMessage(i)
            If '$isobject(m) { Continue }
            Set role = ""
            Try { Set role = m.role } Catch  {}
            If role '= "assistant" { Continue }
            // The assistant message that triggered tool dispatch
            // carries `tool_calls: [{id, name, arguments}, ...]`.
            // The framework's tool-result message that follows
            // (role=tool) only has tool_call_id — no name — so we
            // capture from the assistant frame.
            Set tcs = ""
            Try { Set tcs = m."tool_calls" } Catch  {}
            If '$isobject(tcs) { Continue }
            Set iter = tcs.%GetIterator()
            While iter.%GetNext(.k, .call) {
                If '$isobject(call) { Continue }
                Set name = ""
                Try { Set name = call.name } Catch  {}
                If name = "" { Continue }
                If ..ToolCallTrace '[ name {
                    Set ..LastToolName = name
                    Set ..ToolCallTrace = ..ToolCallTrace _ $S(..ToolCallTrace="":"", 1:",") _ name
                }
            }
        }
    } Catch  {}
}

}
