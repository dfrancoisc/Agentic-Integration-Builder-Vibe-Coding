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
/// When SSEEnabled=1 (set by ChatStream for the streaming endpoint),
/// the monitor emits real-time SSE events during Run(): keepalive
/// comments on every iteration to prevent gateway timeout, tool_start
/// events when the model requests tools, and tool_result events when
/// tools complete. This replaces the broken StreamChat approach that
/// hung during tool execution with no bytes flowing to the client.
///
/// Usage:
///   Set monitor = ##class(AgenticInterop.Agent.Monitor).%New(180, 100000)
///   Set monitor.SSEEnabled = 1   ; for streaming endpoint
///   Set response = agent.Run(session, message, agent.MaxIterations, monitor)
///   Write monitor.IterationCount, ! ; how many turns ran
///   Write monitor.TotalTokens, ! ; cumulative tokens
Class AgenticInterop.Agent.Monitor Extends %RegisteredObject
{

Property StartTime As %Float;

/// Hard wall-clock ceiling in seconds. Default 60 — short enough that
/// a runaway loop fails inside the 90s client-side ceiling the
/// no-timeouts-in-chat memory imposes. ChatStream sets 180 for builds.
Property DeadlineSecs As %Integer [ InitialExpression = 60 ];

/// Total token budget across all iterations. Default 50,000 — generous
/// for planning, tight enough to catch a model flooding tool calls.
Property TokenBudget As %Integer [ InitialExpression = 50000 ];

Property TotalTokens As %Integer [ InitialExpression = 0 ];

/// Input (prompt) tokens summed across iterations. On this project this
/// number is dominated by the agent's tool + skill catalog, which is
/// re-sent as context on every LLM round — so it is the actionable half
/// for the Bedrock throughput problem: trim bound tools, cut this number.
Property InputTokens As %Integer [ InitialExpression = 0 ];

/// Output (completion) tokens summed across iterations.
Property OutputTokens As %Integer [ InitialExpression = 0 ];

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

/// When true, emit SSE keepalive comments and tool lifecycle events
/// during the Run() loop. Set by ChatStream; left false by the non-
/// streaming /chat endpoint.
Property SSEEnabled As %Boolean [ InitialExpression = 0 ];

/// Session message index up to which we have already emitted tool_result
/// events. Advances on each OnIterationStart so we only emit new results.
Property LastScanIdx As %Integer [ InitialExpression = 0 ];

/// Map of tool_call_id -> tool name, built from tool_start emissions so
/// tool_result events can include the tool name (role=tool messages only
/// carry tool_call_id, not name).
Property ToolIdMap As %DynamicObject;

Method %OnNew(deadlineSecs As %Integer = 60, tokenBudget As %Integer = 50000) As %Status
{
    Set ..StartTime = $zhorolog
    Set ..DeadlineSecs = deadlineSecs
    Set ..TokenBudget = tokenBudget
    Set ..ToolIdMap = {}
    Quit $$$OK
}

/// Called by %AI.Agent.Run BEFORE each LLM invocation. Throw to abort.
/// When SSE is enabled, also emits tool_result events for tools that
/// completed since the last iteration, plus a keepalive comment.
Method OnIterationStart(iteration As %Integer, maxIter As %Integer, session As %AI.Agent.Session)
{
    Set ..IterationCount = iteration
    Set elapsed = $zhorolog - ..StartTime
    If elapsed > ..DeadlineSecs {
        Set msg = "Agent deadline exceeded: " _ $fnumber(elapsed, "", 1) _ "s > " _ ..DeadlineSecs _ "s. Tool-result framework hang? Try a narrower question or split it into steps."
        $$$ThrowStatus($$$ERROR($$$GeneralError, msg))
    }
    If ..SSEEnabled {
        Do ..EmitNewToolResults(session)
        Do ..SSEKeepalive(iteration)
    }
}

/// Called AFTER each LLM round. Throw to abort. Tracks token usage
/// across providers (Bedrock returns input_tokens + output_tokens;
/// Anthropic-direct uses total_tokens; we tolerate either shape).
/// When SSE is enabled, also emits tool_start events for tools the
/// model just requested.
Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
{
    Try {
        Set u = response.Usage
        If $isobject(u) {
            ; Capture the input/output split first; providers vary in
            ; shape (Bedrock: input_tokens/output_tokens; Anthropic-direct
            ; also exposes total_tokens). Each iteration is a distinct
            ; billed API call that re-sends the growing context, so summing
            ; across iterations is the true billed cost, not a double-count.
            ; Verified shape on this instance (Bedrock via the %AI bridge):
            ; {"prompt_tokens","completion_tokens","total_tokens",
            ;  "cache_creation_tokens","cache_read_tokens"} — OpenAI-style
            ; names, NOT input_tokens/output_tokens. Read those first and
            ; fall back to the Anthropic-style names for other providers.
            Set inTok = 0, outTok = 0
            Try { Set inTok = +u."prompt_tokens" } Catch  {}
            If 'inTok { Try { Set inTok = +u."input_tokens" } Catch  {} }
            Try { Set outTok = +u."completion_tokens" } Catch  {}
            If 'outTok { Try { Set outTok = +u."output_tokens" } Catch  {} }
            Set ..InputTokens = ..InputTokens + inTok
            Set ..OutputTokens = ..OutputTokens + outTok
            Set t = 0
            Try { Set t = +u."total_tokens" } Catch  {}
            If 't { Set t = inTok + outTok }
            Set ..TotalTokens = ..TotalTokens + t
        }
    } Catch  {}
    If ..TotalTokens > ..TokenBudget {
        Set msg = "Agent token budget exceeded: " _ ..TotalTokens _ " > " _ ..TokenBudget _ " tokens."
        $$$ThrowStatus($$$ERROR($$$GeneralError, msg))
    }
    ; Capture every tool name the framework saw on this iteration AND
    ; emit tool_start SSE events when streaming.
    Try {
        If response.HasToolCalls() {
            Set callIter = response.ToolCalls.%GetIterator()
            While callIter.%GetNext(.callKey, .call) {
                Set toolName = ""
                Try { Set toolName = call.name } Catch  {}
                If toolName '= "" {
                    Set ..LastToolName = toolName
                    Set ..ToolCallTrace = ..ToolCallTrace _ $S(..ToolCallTrace="":"", 1:",") _ toolName
                    ; Map tool_call_id -> name for result matching
                    Set toolId = ""
                    Try { Set toolId = call.id } Catch  {}
                    If toolId '= "" {
                        Do ..ToolIdMap.%Set(toolId, toolName)
                    }
                    ; Emit tool_start SSE event
                    If ..SSEEnabled {
                        Set startEv = {}
                        Set startEv.name = toolName
                        Try {
                            Set args = call.arguments
                            If $isobject(args) {
                                Set startEv.args = args
                            } ElseIf args '= "" {
                                Set startEv.args = ##class(%DynamicAbstractObject).%FromJSON(args)
                            }
                        } Catch  {}
                        Do ##class(AgenticInterop.Editor.ChatService).SSEEvent("tool_start", startEv)
                    }
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

/// Chars-per-token used to size messages the transcript exposes but the
/// provider bills as tokens. ~4 chars/token is the standard rule of thumb
/// for English + JSON; the exact final-round anchor (below) corrects most
/// of the residual error, so the precise value matters little.
Parameter CHARSPERTOKEN = 4;

/// Reconstruct the TRUE cumulative token cost of a turn from the session
/// transcript, because the framework only ever exposes the FINAL round's
/// usage (verified: agent.Run and agent.Chat both report one round's
/// Usage even after an N-tool loop). Without this, a 6-tool build reports
/// ~1/5 of what it actually billed.
///
/// Model. A turn is R model rounds, one per assistant message. Each round
/// re-sends: (a) the tool/skill schemas, a fixed overhead S that is NOT in
/// the transcript, plus (b) every message accumulated so far, which IS in
/// the transcript. So a round's input tokens ~= S + rho * (chars of the
/// messages before it), rho = 1/CHARSPERTOKEN.
///
/// Anchor. The final round's real prompt_tokens (T) is known exactly, and
/// its message-prefix is the whole transcript (M chars). One equation,
/// T = S + rho*M, pins S = T - rho*M — so S falls out as a measured number
/// (it lands near the ~29k catalog cost on this project, which cross-checks
/// against the ~36k no-tool floor). Cumulative input is then the sum of
/// S + rho*prefix over every round; the fixed S, re-paid each round, is the
/// dominant term and the whole reason the real cost dwarfs the final round.
///
/// Returns {rounds, estInput, estOutput, estTotal, estimated, schemaOverhead}.
/// estimated=0 (and est*=final values) when there is only one round, when
/// the anchor is missing, or when the transcript cannot be read — in those
/// cases the caller should trust the exact final-round figures instead.
ClassMethod ReconstructUsage(session As %AI.Agent.Session, finalPromptTok As %Integer, finalCompletionTok As %Integer) As %DynamicObject
{
    Set out = {"rounds": 1, "estInput": (+finalPromptTok), "estOutput": (+finalCompletionTok),
               "estTotal": (+finalPromptTok + +finalCompletionTok), "estimated": 0, "schemaOverhead": 0}
    Try {
        If '$isobject(session) Quit
        Set count = session.MessageCount()
        If count < 1 Quit
        Set rho = 1 / ..#CHARSPERTOKEN

        ; Walk once: record each message's char size and cumulative prefix,
        ; and collect the prefix-char total that precedes each assistant
        ; message (that prefix is what the model was sent to produce it).
        Set prefixChars = 0, rounds = 0, sumPrefix = 0, lastPrefix = 0
        Set asstChars = 0    ; chars of assistant messages other than the last
        Set lastAsstChars = 0
        For i = 0:1:count-1 {
            Set m = session.GetMessage(i)
            If '$isobject(m) { Continue }
            Set role = "" Try { Set role = m.role } Catch  {}
            Set sz = 0 Try { Set sz = $length(m.%ToJSON()) } Catch  {}
            If role = "assistant" {
                Set rounds = rounds + 1
                Set sumPrefix = sumPrefix + prefixChars   ; input prefix for THIS round
                Set lastPrefix = prefixChars
                Set asstChars = asstChars + lastAsstChars ; roll previous assistant into "non-last"
                Set lastAsstChars = sz
            }
            Set prefixChars = prefixChars + sz
        }

        ; Nothing to reconstruct: single round, or no usable anchor.
        If (rounds <= 1) || (+finalPromptTok <= 0) || (lastPrefix <= 0) Quit

        ; S = fixed non-transcript overhead (tool schemas). Floor at 0; if the
        ; message prefix alone would already exceed T, drop the fixed term and
        ; scale rho so the anchor still holds exactly (rho = T / lastPrefix).
        Set S = +finalPromptTok - (rho * lastPrefix)
        If S < 0 { Set S = 0, rho = (+finalPromptTok) / lastPrefix }

        ; Cumulative input = sum over rounds of (S + rho*prefix_r).
        Set estInput = (rounds * S) + (rho * sumPrefix)
        ; Output: last round exact, earlier assistant messages (tool-call
        ; requests, usually small) estimated from their size.
        Set estOutput = (+finalCompletionTok) + (rho * asstChars)

        Set out.rounds = rounds
        Set out.estInput = $normalize(estInput, 0)
        Set out.estOutput = $normalize(estOutput, 0)
        Set out.estTotal = $normalize(estInput + estOutput, 0)
        Set out.schemaOverhead = $normalize(S, 0)
        Set out.estimated = 1
    } Catch  {}
    Quit out
}

/// Scan session messages from LastScanIdx onward. For assistant messages,
/// extract tool_call_id → name mappings and emit tool_start events. For
/// tool messages, emit tool_result events with resolved names.
///
/// Chat() dispatches most tools internally (its own iteration loop inside
/// the Rust bridge), so OnIterationComplete only sees the FINAL response
/// per Chat() call. This session scan catches ALL tool dispatches by
/// reading the full transcript the framework leaves behind.
Method EmitNewToolResults(session As %AI.Agent.Session)
{
    If '$isobject(session) Quit
    Try {
        Set count = session.MessageCount()
        ; First pass: scan assistant messages for tool_call name mappings
        ; and emit tool_start events. Chat() may have dispatched many
        ; tools internally — the assistant messages carry the names.
        For i=..LastScanIdx:1:count-1 {
            Set m = session.GetMessage(i)
            If '$isobject(m) Continue
            Set role = ""
            Try { Set role = m.role } Catch {}
            If role = "assistant" {
                Set tcs = ""
                Try { Set tcs = m."tool_calls" } Catch {}
                If '$isobject(tcs) Continue
                Set tcIter = tcs.%GetIterator()
                While tcIter.%GetNext(.k, .call) {
                    If '$isobject(call) Continue
                    Set toolId = ""
                    Try { Set toolId = call.id } Catch {}
                    Set toolName = ""
                    Try { Set toolName = call.name } Catch {}
                    If toolId '= "", toolName '= "" {
                        Do ..ToolIdMap.%Set(toolId, toolName)
                    }
                    ; Emit tool_start for tools we haven't started yet
                    If toolName '= "" {
                        Set startEv = {}
                        Set startEv.name = toolName
                        Try {
                            Set args = call.arguments
                            If $isobject(args) {
                                Set startEv.args = args
                            } ElseIf args '= "" {
                                Set startEv.args = ##class(%DynamicAbstractObject).%FromJSON(args)
                            }
                        } Catch {}
                        Do ##class(AgenticInterop.Editor.ChatService).SSEEvent("tool_start", startEv)
                    }
                }
            }
        }
        ; Second pass: scan tool messages for results
        For i=..LastScanIdx:1:count-1 {
            Set m = session.GetMessage(i)
            If '$isobject(m) Continue
            Set role = ""
            Try { Set role = m.role } Catch {}
            If role = "tool" {
                Set callId = ""
                Try { Set callId = m."tool_call_id" } Catch {}
                Set name = ""
                If callId '= "" {
                    Try { Set name = ..ToolIdMap.%Get(callId) } Catch {}
                }
                If name = "" Set name = "(tool)"
                Set content = ""
                Try { Set content = m.content } Catch {}
                Set resultEv = {}
                Set resultEv.name = name
                Set resultEv.result = content
                Try {
                    If content '= "", $extract(content) = "{" {
                        Set resultEv.result = ##class(%DynamicAbstractObject).%FromJSON(content)
                    }
                } Catch {}
                Do ##class(AgenticInterop.Editor.ChatService).SSEEvent("tool_result", resultEv)
            }
        }
        Set ..LastScanIdx = count
    } Catch {}
}

/// Emit remaining tool_result events from the session after Run()
/// returns. The last OnIterationComplete may have emitted tool_start
/// events whose results were not yet scanned. This final sweep
/// catches them.
Method EmitFinalToolResults(session As %AI.Agent.Session)
{
    If ..SSEEnabled Do ..EmitNewToolResults(session)
}

/// Write an SSE keepalive comment to the open response. Prevents the
/// Apache/CSP gateway from killing the connection during long tool
/// execution gaps when no tokens are being generated.
Method SSEKeepalive(iteration As %Integer)
{
    Try {
        Set elapsed = $fnumber($zhorolog - ..StartTime, "", 1)
        Write ":keepalive iteration=", iteration, " elapsed=", elapsed, "s", $char(10)
        Write $char(10)
        Write *-3
    } Catch {}
}

}
