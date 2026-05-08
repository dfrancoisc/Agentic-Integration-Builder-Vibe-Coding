/// Phase 2 chat service — non-streaming, with multi-turn memory via
/// client-side history replay AND iteration-monitor protection against
/// the framework's known tool-result hang. Resolves the default
/// AgenticInterop.Data.Connection via AgenticInterop.Connections.GetProvider,
/// builds the Health Interop agent, replays the prior turns into a
/// fresh %AI.Agent.Session, runs the agent loop with a wall-clock +
/// token-budget Monitor, returns the response.
///
/// Why agent.Run instead of agent.Chat: Chat is a single-turn call that
/// can't iterate tool calls. Run is the iterative loop the framework
/// provides — it lets the model invoke registered tools, gets the
/// result back, and continues until the model produces a final
/// response without tool calls. The Monitor (see
/// AgenticInterop.Agent.Monitor) caps wall-clock at 60s and tokens at
/// 50k so the documented Bedrock tool-result hang (project_agent_toolset_hang
/// memory) can never silently exceed the CSP gateway timeout — it
/// surfaces a fast actionable error instead.
///
/// Why client-side history (and not server-side session OREF caching):
/// %AI.Agent.Session keeps its real conversation state in a Rust-side
/// process-local cache. Persisting the session row to disk doesn't
/// preserve that state — reopening yields a "Session not found" from
/// the Rust LLM library — so cross-process / cross-request resume is
/// not possible at the OREF level. Storing the OREF in a process-
/// private global also loses the live reference (the OREF gets
/// stringified on assignment). Replaying the transcript on every turn
/// is the same pattern OpenAI / Anthropic / Bedrock SDKs use directly,
/// and it Just Works across worker pools, process restarts, and
/// browser reloads.
///
/// Body shape:
///   POST /api/agentic/chat
///   { "message": "<user message>",
///     "history": [{"role":"user"|"assistant","content":"..."}, ...],
///     "agentClass": "<optional override>",
///     "connection": "<optional connection name override>" }
///
/// Response shape (success):
///   { "ok": 1, "response": "<assistant text>", "latencyMs": 1234,
///     "agentClass": "AgenticInterop.Agent.HealthInterop",
///     "connection": "bedrock-default", "model": "...",
///     "namespace": "<ns>", "turnsReplayed": <int> }
///
/// Response shape (failure):
///   { "ok": 0, "error": "<verbatim message>",
///     "stage": "connection|build|session|chat" }
///
/// Phase 3 will replace this with an SSE endpoint that streams tokens
/// + tool-call lifecycle events. The shape above stays compatible —
/// the frontend can swap from POST → SSE without touching the rest of
/// the chat flow.
Class AgenticInterop.Editor.ChatService Extends %RegisteredObject
{

ClassMethod Chat(pResponse As %CSP.Response, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    Set message = $classmethod(util, "DObj", req, "message")
    If message = "" {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Missing 'message'")
    }
    Set agentClass = $classmethod(util, "DObj", req, "agentClass", "AgenticInterop.Agent.HealthInterop")
    Set connectionName = $classmethod(util, "DObj", req, "connection")
    Set history = $S(req.%IsDefined("history"):req.history, 1:[])
    // Approved tokens carried out-of-band — the user clicked Approve
    // on a prior tool_confirm card, so the next request includes the
    // matching token(s) in its body. Manager.Build reads
    // %agenticApprovedTokens and seeds the ConfirmationGate with them
    // so the matching tool call passes the gate this turn.
    Set approvedCsv = ""
    If req.%IsDefined("approvedTokens"), $isobject(req.approvedTokens) {
        Set iter = req.approvedTokens.%GetIterator()
        While iter.%GetNext(.k, .tok) {
            If tok = "" { Continue }
            Set approvedCsv = approvedCsv _ $S(approvedCsv="":"", 1:",") _ tok
        }
    }
    Set %agenticApprovedTokens = approvedCsv

    Set out = {}
    Set start = $zhorolog
    Set stage = "connection"
    Set buildFailed = 0
    Try {
        Set provider = ##class(AgenticInterop.Connections).GetProvider(connectionName)
        // Resolve effective connection name + model. The agent class
        // doesn't know about Connection rows; it gets a Provider object
        // and we have to wire the model id explicitly (the framework's
        // declarative agent classes have no MODEL parameter — the
        // reference repo does this same explicit assignment in
        // Catalog.Agents.GetRunner).
        Set effectiveName = $S(connectionName="":..ResolvedDefaultName(),1:connectionName)
        Set connObj = ##class(AgenticInterop.Connections).Get(effectiveName)
        Set stage = "build"
        Set tSC = ##class(AgenticInterop.Agent.Manager).Build(provider, .agent, agentClass)
        If 'tSC {
            Set out.ok = 0
            Set out.error = $system.Status.GetErrorText(tSC)
            Set out.stage = stage
            Set buildFailed = 1
        } Else {
            // Agent.Model is what %AI.Agent passes to the provider for
            // every Chat / StreamChat / Run call. Without this, the
            // framework picks a default that Bedrock rejects.
            If $isobject(connObj) && (connObj.model '= "") {
                Set agent.Model = connObj.model
            }
            Set stage = "session"
            Set sessionConfig = {}
            Do sessionConfig.%Set("max_tokens", 8192, "number")
            Set session = agent.CreateSession(sessionConfig)
            Set turnsReplayed = ..ReplayHistory(session, history)
            Set stage = "chat"
            // agent.Run iterates the tool-call loop until the model
            // returns a final response (no more tool calls) OR the
            // monitor's OnIterationStart/OnIterationComplete throws.
            // The monitor caps wall-clock + tokens so the known
            // framework toolset-hang can never silently exceed the
            // CSP gateway timeout.
            Set monitor = ##class(AgenticInterop.Agent.Monitor).%New(180, 100000)
            Set maxIter = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMaxIterations(agentClass)
            If maxIter = "" { Set maxIter = 10 }
            Set response = agent.Run(session, message, maxIter, monitor)
            // Belt-and-suspenders: the framework's OnIterationComplete
            // callback may only fire on the FINAL response (no tool
            // calls there). Walk the session to capture any tool
            // dispatch the callback missed.
            Do monitor.CaptureFromSession(session)
            Set out.ok = 1
            Set out.turnsReplayed = turnsReplayed
            Set out.iterations = monitor.IterationCount
            Set out.totalTokens = monitor.TotalTokens
            If monitor.LastToolName '= "" { Set out.lastTool = monitor.LastToolName }
            If monitor.ToolCallTrace '= "" { Set out.toolTrace = monitor.ToolCallTrace }
            Set out.model = agent.Model
            Set out.response = ..ExtractText(response)
            Set out.latencyMs = $fnumber(($zhorolog - start) * 1000, "", 0)
            Set out.agentClass = agentClass
            Set out.connection = $S(connectionName="":..ResolvedDefaultName(),1:connectionName)
            Set out.namespace = $namespace
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 1000)
        Set out.stage = stage
    }
    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

/// %AI.Agent.Chat returns either a %DynamicObject ({content, ...}), a
/// %AI.LLM.Response object with .Content / .Text, or a string. Probe
/// the common shapes, tolerate any access error, and fall back to
/// $extract($zobjref(...)) so a non-empty result always lands.
ClassMethod ExtractText(pResponse) As %String
{
    If '$isobject(pResponse) Quit $extract(pResponse, 1, 32000)
    Set txt = ""
    Try { Set txt = pResponse.Content } Catch  {}
    If txt = "" { Try { Set txt = pResponse.content } Catch  {} }
    If txt = "" { Try { Set txt = pResponse.Text } Catch  {} }
    If txt = "" { Try { Set txt = pResponse.text } Catch  {} }
    If txt = "" { Try { Set txt = pResponse.Message } Catch  {} }
    If txt = "" { Try { Set txt = pResponse.message } Catch  {} }
    If txt = "" {
        Try { Set txt = pResponse.%ToJSON() } Catch  {}
    }
    Quit $extract(txt, 1, 32000)
}

/// What did GetProvider("") resolve to? Used purely for the response
/// envelope so the UI can surface "answered via bedrock-default" etc.
ClassMethod ResolvedDefaultName() As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 Name FROM AgenticInterop_Data.LLMConnection WHERE IsDefault = 1 AND Enabled = 1")
    If rs.%Next() Quit rs.%GetData(1)
    Quit ""
}

/// Look up an existing session by id under ^||AgenticInteropSessions, or
/// build a fresh one if the id is empty / not found / not an OREF. The
/// process-private global means sessions don't survive an IRIS process
/// restart — that's the same trade-off the reference repo makes (see
/// Catalog.Agents.%ResolveSession). For Phase 2 it gives us real
/// conversational memory within a tab without persistence machinery
/// that wouldn't survive an OREF cache anyway.
/// Phase 3 streaming chat. Returns text/event-stream — each LLM token
/// flows down the stream as `event: token` the moment Bedrock emits it,
/// instead of the client waiting silently for the whole response.
///
/// Why agent.StreamChat (not agent.Run): StreamChat goes through the
/// /converse-stream Bedrock endpoint via a different Rust HTTP bridge
/// that does NOT exhibit the documented tool-result hang Run() suffers
/// from. (See project_agent_toolset_hang memory + reference repo
/// Catalog.Agents.Stream.) For tool-using flows, the Phase 4 toolset
/// implementations will land tool-lifecycle SSE events on top of this
/// same stream; the event types are documented inline so the front
/// end can render them as cards now.
///
/// SSE event types emitted (all data: is JSON):
///   event: status     { iteration, elapsed, message? }
///   event: token      { text }
///   event: tool_start { name, args }                 (Phase 4)
///   event: tool_result{ name, result }               (Phase 4)
///   event: tool_error { name, error }                (Phase 4)
///   event: done       { latencyMs, totalLen, model, connection,
///                       namespace, agentClass, turnsReplayed }
///   event: error      { error, stage }
///
/// Body shape mirrors POST /chat — message, history, agentClass, connection.
ClassMethod ChatStream(pResponse As %CSP.Response, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    // SSE response shape. The CSP framework auto-emits the HTTP
    // response header line + Content-Type + our SetHeader() values
    // when the first byte hits the wire — DO NOT call
    // WriteHTTPHeader() here, it writes the header section into the
    // body and the browser sees a "CacheSP:...HTTP/1.1 200 OK..."
    // prefix that breaks the SSE parse.
    Set pResponse.ContentType = "text/event-stream"
    Set pResponse.CharSet = "utf-8"
    Do pResponse.SetHeader("Cache-Control", "no-cache, no-transform")
    Do pResponse.SetHeader("X-Accel-Buffering", "no")

    // Process-private flag SSEEvent() checks before writing. Without
    // this, /chat (non-streaming) callers that reach the gate's
    // tool_confirm emit corrupt their JSON response with SSE frames.
    Set %agenticChatSSE = 1

    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Do ..SSEEvent("error", {"error":"Invalid JSON body","stage":"parse"})
        Quit $$$OK
    }
    Set message = $classmethod(util, "DObj", req, "message")
    If message = "" {
        Do ..SSEEvent("error", {"error":"Missing 'message'","stage":"parse"})
        Quit $$$OK
    }
    Set agentClass = $classmethod(util, "DObj", req, "agentClass", "AgenticInterop.Agent.HealthInterop")
    Set connectionName = $classmethod(util, "DObj", req, "connection")
    Set history = $S(req.%IsDefined("history"):req.history, 1:[])
    // Approved tokens carried out-of-band — the user clicked Approve
    // on a prior tool_confirm card, so the next request includes the
    // matching token(s) in its body. Manager.Build reads
    // %agenticApprovedTokens and seeds the ConfirmationGate with them
    // so the matching tool call passes the gate this turn.
    Set approvedCsv = ""
    If req.%IsDefined("approvedTokens"), $isobject(req.approvedTokens) {
        Set iter = req.approvedTokens.%GetIterator()
        While iter.%GetNext(.k, .tok) {
            If tok = "" { Continue }
            Set approvedCsv = approvedCsv _ $S(approvedCsv="":"", 1:",") _ tok
        }
    }
    Set %agenticApprovedTokens = approvedCsv

    Set start = $zhorolog
    Set stage = "connection"
    Try {
        Set provider = ##class(AgenticInterop.Connections).GetProvider(connectionName)
        Set effectiveName = $S(connectionName="":..ResolvedDefaultName(),1:connectionName)
        Set connObj = ##class(AgenticInterop.Connections).Get(effectiveName)
        Set stage = "build"
        Set tSC = ##class(AgenticInterop.Agent.Manager).Build(provider, .agent, agentClass)
        If 'tSC {
            Do ..SSEEvent("error", {"error":($system.Status.GetErrorText(tSC)),"stage":(stage)})
            Quit
        }
        If $isobject(connObj) && (connObj.model '= "") {
            Set agent.Model = connObj.model
        }
        Set stage = "session"
        Set sessionConfig = {}
        Do sessionConfig.%Set("max_tokens", 8192, "number")
        Set session = agent.CreateSession(sessionConfig)
        Set turnsReplayed = ..ReplayHistory(session, history)
        Do ..SSEEvent("status", {"phase":"ready","turnsReplayed":(turnsReplayed)})
        Set stage = "run"
        // Custom run loop — mirrors %AI.Agent.Run() but passes
        // "Continue." instead of "" on iteration 2+. The framework's
        // Run() uses $SELECT(iteration=1:goal, 1:"") which causes
        // Bedrock to reject the empty text content block. This custom
        // loop is otherwise identical: calls Chat() per iteration,
        // fires Monitor callbacks, checks HasToolCalls() to continue.
        //
        // The Monitor emits SSE keepalive comments on every iteration
        // (prevents CSP gateway timeout during tool execution) plus
        // real-time tool_start/tool_result events so tool cards appear
        // progressively in the UI.
        Set maxIter = +agent.MaxIterations
        If maxIter < 1 { Set maxIter = 25 }
        Set monitor = ##class(AgenticInterop.Agent.Monitor).%New(180, 100000)
        Set monitor.SSEEnabled = 1
        Set response = ""
        Set iteration = 0
        Set fabricationRetried = 0
        While iteration < maxIter {
            Set iteration = iteration + 1
            Do monitor.OnIterationStart(iteration, maxIter, session)
            Set input = $select(iteration=1:message, 1:"Continue executing tool calls. Do not repeat tools you already called.")
            Set response = agent.Chat(session, input)
            Do monitor.OnIterationComplete(iteration, response, session)
            If '$isobject(response) Quit
            Try { Set hasCalls = response.HasToolCalls() } Catch { Set hasCalls = 0 }
            If 'hasCalls {
                ; FABRICATION GUARD: if the model returned text-only on the
                ; FIRST iteration AND the text contains build/create claims
                ; but NO tools were called, this is fabrication. Force the
                ; model to try again with an explicit instruction to use tools.
                ; Only retry once to avoid infinite loops.
                If iteration = 1, 'fabricationRetried {
                    Set checkText = ..ExtractText(response)
                    If ..LooksLikeFabrication(checkText, monitor.ToolCallTrace) {
                        Set fabricationRetried = 1
                        ; Don't break out of loop — continue with a corrective message
                        Set iteration = iteration + 1
                        Do monitor.OnIterationStart(iteration, maxIter, session)
                        Set response = agent.Chat(session, "STOP. You just wrote text claiming you built something, but you did NOT call any tools. Text is not action. You MUST call CreateProduction, AddBusinessHost, and the other tools to actually build the production. Do it now — call the tools.")
                        Do monitor.OnIterationComplete(iteration, response, session)
                        If '$isobject(response) Quit
                        Try { Set hasCalls = response.HasToolCalls() } Catch { Set hasCalls = 0 }
                        If 'hasCalls Quit
                        Continue
                    }
                }
                Quit
            }
        }
        ; Emit any remaining tool_result events for the final iteration
        Do monitor.EmitFinalToolResults(session)
        Do monitor.CaptureFromSession(session)
        // Extract final text from the response
        Set finalText = ..ExtractText(response)
        // Emit the response text as token events so the frontend renders
        // it in the message bubble. Run() returns the full text at once
        // (no real-time token streaming), but the UI accumulates token
        // events the same way — it just arrives as one chunk.
        If finalText '= "" {
            Set tokenEv = {}
            Set tokenEv.text = finalText
            Do ..SSEEvent("token", tokenEv)
        }
        Set done = {}
        Set done.latencyMs = $fnumber(($zhorolog - start) * 1000, "", 0)
        Set done.totalLen = $length(finalText)
        Set done.iterations = monitor.IterationCount
        Set done.totalTokens = monitor.TotalTokens
        Set done.model = agent.Model
        Set done.connection = effectiveName
        Set done.namespace = $namespace
        Set done.agentClass = agentClass
        Set done.turnsReplayed = turnsReplayed
        // Tool trace from the Monitor (populated during Run via callbacks
        // + CaptureFromSession belt-and-suspenders). No need for the
        // post-hoc EmitToolEventsFromSession — the Monitor emits tool
        // lifecycle events in real-time during the Run() loop.
        Set done.toolTrace = monitor.ToolCallTrace
        Do ..SSEEvent("done", done)
    } Catch ex {
        Do ..SSEEvent("error", {"error":($extract(ex.DisplayString(),1,1000)),"stage":(stage)})
    }
    Quit $$$OK
}

/// Walk a session and return a CSV of tool names dispatched. Used
/// by ChatStream to surface tool usage in the `done` event.
/// Tool names live on the assistant frames in `tool_calls[].name`,
/// not on the role=tool result frames (those only carry tool_call_id).
ClassMethod SessionToolTrace(pSession As %AI.Agent.Session) As %String
{
    If '$isobject(pSession) Quit ""
    Set trace = ""
    Try {
        Set count = pSession.MessageCount()
        For i=0:1:count-1 {
            Set m = pSession.GetMessage(i)
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
                If trace '[ name {
                    Set trace = trace _ $S(trace="":"", 1:",") _ name
                }
            }
        }
    } Catch  {}
    Quit trace
}

/// Walk a completed session and emit tool_start + tool_result SSE events
/// for every tool the framework dispatched during StreamChat. Called after
/// the stream completes so tool cards render in the frontend even though
/// StreamChat doesn't expose tool lifecycle callbacks.
///
/// Session message structure (for tool-using conversations):
///   [0] system (prompt)
///   [1..N] user/assistant replay
///   [N+1] user (current message)
///   [N+2] assistant with tool_calls: [{id, name, arguments}, ...]
///   [N+3] tool with tool_call_id + content (the result)
///   [N+4] assistant (final text response)
///
/// We skip messages from the replay portion (indices up to the current
/// turn's user message) so tool cards only appear for THIS turn's calls.
ClassMethod EmitToolEventsFromSession(pSession As %AI.Agent.Session)
{
    If '$isobject(pSession) Quit
    Try {
        Set count = pSession.MessageCount()
        ; Find the index of the LAST user message — that's the current turn.
        ; Everything before it is replay.
        Set lastUserIdx = -1
        For i=0:1:count-1 {
            Set m = pSession.GetMessage(i)
            If '$isobject(m) Continue
            Set role = "" Try { Set role = m.role } Catch {}
            If role = "user" Set lastUserIdx = i
        }
        If lastUserIdx < 0 Quit
        ; Walk from lastUserIdx+1 onward — these are the current turn's
        ; assistant + tool messages.
        ; Build a map of tool_call_id → name from assistant frames, then
        ; match tool result frames by id.
        Set toolNames = {}  ; tool_call_id → name
        Set toolArgs = {}   ; tool_call_id → arguments JSON
        For i=lastUserIdx+1:1:count-1 {
            Set m = pSession.GetMessage(i)
            If '$isobject(m) Continue
            Set role = "" Try { Set role = m.role } Catch {}
            If role = "assistant" {
                Set tcs = "" Try { Set tcs = m."tool_calls" } Catch {}
                If '$isobject(tcs) Continue
                Set iter = tcs.%GetIterator()
                While iter.%GetNext(.k, .call) {
                    If '$isobject(call) Continue
                    Set id = "" Try { Set id = call.id } Catch {}
                    Set name = "" Try { Set name = call.name } Catch {}
                    If id = "" Continue
                    Do toolNames.%Set(id, name)
                    ; Capture arguments
                    Set args = "" Try { Set args = call.arguments } Catch {}
                    If $isobject(args) {
                        Do toolArgs.%Set(id, args.%ToJSON())
                    } ElseIf args '= "" {
                        Do toolArgs.%Set(id, args)
                    }
                    ; Emit tool_start immediately
                    Set startEv = {}
                    Set startEv.name = name
                    If $isobject(args) {
                        Set startEv.args = args
                    } ElseIf args '= "" {
                        Try { Set startEv.args = ##class(%DynamicAbstractObject).%FromJSON(args) } Catch {}
                    }
                    Do ..SSEEvent("tool_start", startEv)
                }
            } ElseIf role = "tool" {
                ; Tool result frame — match to name via tool_call_id
                Set callId = "" Try { Set callId = m."tool_call_id" } Catch {}
                Set name = ""
                If callId '= "" {
                    Try { Set name = toolNames.%Get(callId) } Catch {}
                }
                If name = "" Set name = "(tool)"
                Set content = "" Try { Set content = m.content } Catch {}
                ; Emit tool_result
                Set resultEv = {}
                Set resultEv.name = name
                ; Try to parse the result as JSON for the card; fall back to string
                Set resultEv.result = content
                Try {
                    If content '= "", $extract(content) = "{" {
                        Set resultEv.result = ##class(%DynamicAbstractObject).%FromJSON(content)
                    }
                } Catch {}
                Do ..SSEEvent("tool_result", resultEv)
            }
        }
    } Catch {}
}

/// Count tool-result messages (role=tool) in the session. Used by the
/// StreamChat loop to track how many tool calls have fired across passes.
ClassMethod CountToolMessages(pSession As %AI.Agent.Session) As %Integer
{
    Set n = 0
    If '$isobject(pSession) Quit 0
    Try {
        Set count = pSession.MessageCount()
        For i=0:1:count-1 {
            Set m = pSession.GetMessage(i)
            If '$isobject(m) Continue
            Set role = "" Try { Set role = m.role } Catch {}
            If role = "tool" Set n = n + 1
        }
    } Catch {}
    Quit n
}

/// Detect fabrication: the model returned text that CLAIMS to have built
/// or created something, but the tool trace is empty (no tools were called).
/// This catches the most common hallucination pattern: the LLM writes a
/// narrative like "Production created successfully" without actually
/// calling CreateProduction. Returns true if the text looks like fabrication.
ClassMethod LooksLikeFabrication(pText As %String, pToolTrace As %String) As %Boolean
{
    ; If tools were called, it is not fabrication — the model did actual work
    If pToolTrace '= "" Quit 0
    ; If the text is empty or very short, not fabrication (just a question or plan)
    If $length(pText) < 50 Quit 0
    ; Check for build/create/success claim patterns in the response text.
    ; Case-insensitive via $zconvert.
    Set lower = $zconvert(pText, "L")
    ; Strong fabrication signals: claiming to have built/created artifacts
    If lower [ "created successfully" Quit 1
    If lower [ "production created" Quit 1
    If lower [ "what i built" Quit 1
    If lower [ "hosts properly configured" Quit 1
    If lower [ "hosts configured" Quit 1
    If lower [ "built and running" Quit 1
    If lower [ "production is running" Quit 1
    If lower [ "all three hosts" Quit 1
    If lower [ "all hosts" Quit 1
    If lower [ "fully built" Quit 1
    If lower [ "interface is fully built" Quit 1
    If lower [ "pipeline is configured" Quit 1
    ; Moderate signal: claiming build + using past-tense creation verbs
    If (lower [ "i built") || (lower [ "i created") || (lower [ "i configured") {
        If (lower [ "production") || (lower [ "business host") || (lower [ "dtl") || (lower [ "routing rule") {
            Quit 1
        }
    }
    Quit 0
}

/// Write one SSE event to the open response. Each event format is:
///
///     event: <type>\n
///     data: <json>\n
///     :<padding>\n
///     \n
///
/// The trailing `:`-prefixed line is an SSE comment (clients ignore
/// it) used only to push each event past the Apache CSP gateway's
/// chunked-response buffer threshold. Without the padding, small
/// events get held until end-of-response and the stream looks
/// non-streaming. Cost: ~1KB per event.
ClassMethod SSEEvent(pType As %String, pData As %DynamicObject)
{
    // Only emit when the request is actually a streaming chat. Non-
    // streaming /chat callers also reach this method via the gate's
    // tool_confirm path — writing SSE frames there would corrupt the
    // JSON envelope. ChatStream sets the process-private flag below
    // before opening the stream; the flag clears at request end.
    If '$get(%agenticChatSSE, 0) Quit
    Write "event: ", pType, $char(10)
    Write "data: ", pData.%ToJSON(), $char(10)
    Write ":", ..SSEPadding(), $char(10)
    Write $char(10)
    Write *-3
}

ClassMethod SSEPadding() As %String [ Internal ]
{
    If $get(^||AgenticInterop.SSEPad1k) '= "" Quit ^||AgenticInterop.SSEPad1k
    Set s = ""
    For i=1:1:1024 Set s = s _ "x"
    Set ^||AgenticInterop.SSEPad1k = s
    Quit s
}

/// Replay the client-supplied transcript into a fresh session via
/// session.InsertMessage so the LLM sees the prior turns as context.
/// Each entry is { role: "user"|"assistant", content: "..." }. Returns
/// the count of messages successfully inserted (informational).
///
/// We tolerate missing fields and unknown roles silently — the front
/// end is the source of truth for history shape, and a malformed entry
/// shouldn't poison the whole chat.
/// InsertMessage(index, msg) where msg is a %DynamicObject of shape
/// {role, content}. Index is 0-based; we append at the current end of
/// the session's message list (which already contains the system
/// prompt at index 0 after CreateSession).
ClassMethod ReplayHistory(pSession As %AI.Agent.Session, pHistory As %DynamicArray) As %Integer
{
    Set count = 0
    If '$isobject(pHistory) Quit count
    Set iter = pHistory.%GetIterator()
    While iter.%GetNext(.k, .entry) {
        If '$isobject(entry) { Continue }
        Set role = ""
        Try { Set role = entry.role } Catch  {}
        Set content = ""
        Try { Set content = entry.content } Catch  {}
        If (role = "") || (content = "") { Continue }
        If (role '= "user") && (role '= "assistant") { Continue }
        Set msg = {}
        Set msg.role = role
        Set msg.content = content
        Try {
            Do pSession.InsertMessage(pSession.MessageCount(), msg)
            Set count = count + 1
        } Catch  {}
    }
    Quit count
}

}
