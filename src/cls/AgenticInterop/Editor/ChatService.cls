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
    ; Resolve the agent: an explicit agentClass wins; otherwise the
    ; chatbot key maps to an agent via the Chatbot config layer; else
    ; fall back to the generalist default.
    Set agentClass = $classmethod(util, "DObj", req, "agentClass", "")
    Set chatbotKey = $classmethod(util, "DObj", req, "chatbot", "")
    If (agentClass = ""), (chatbotKey '= "") {
        Set cb = ##class(AgenticInterop.Data.Chatbot).GetByKey(chatbotKey)
        If $isobject(cb), cb.Enabled, cb.AgentClass '= "" { Set agentClass = cb.AgentClass }
    }
    If agentClass = "" { Set agentClass = "AgenticInterop.Agent.HealthInterop" }
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

    ; LiveFeed session tracking for the Observer — same setup as
    ; ChatStream but without SSE output. ToolStart/ToolDone (Manager.cls)
    ; write to ^AgInt.LiveFeed during agent.Run() using this session id.
    Set clientObs = $classmethod(util, "DObj", req, "observerId")
    If clientObs '= "" {
        Set %agenticChatSessionId = clientObs
    } Else {
        Set %agenticChatSessionId = $zstrip($system.Util.CreateGUID(), "<>W")
    }
    Set %agenticChatStart = $zhorolog
    Set ^AgInt.LiveFeed("active", %agenticChatSessionId) = $horolog

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
            Set monitor = ##class(AgenticInterop.Agent.Monitor).%New(300, 100000)
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
    ; Clean up LiveFeed session so Observer shows completion
    If $get(%agenticChatSessionId) '= "" {
        Kill ^AgInt.LiveFeed("active", %agenticChatSessionId)
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
    ; pBodyStream is forwarded from the dispatcher (REST.Dispatch.ChatStream
    ; passes %request.Content here). For multipart turns it is empty because
    ; the framework parses parts into %request.MIMEData; we use that path
    ; below. For JSON turns it is the request body stream which we hand to
    ; Util.ParseBody. Earlier we tried removing this parameter to "let
    ; multipart be parsed" — but %CSP.REST's parsing decision is driven by
    ; the ROUTE handler's signature (REST.Dispatch.ChatStream takes no body
    ; param, so the framework already parses multipart). This method is
    ; called from there with two args; dropping one breaks that call with a
    ; hard ObjectScript error -> HTTP 500 with nothing logged.
    Set util = "AgenticInterop.Editor.Util"
    ; Read the content type DEFENSIVELY — $get(%request.ContentType)
    ; throws (the same OREF-property quirk that hits %DynamicObject), and
    ; that throw at the top of the method killed every chat turn with a
    ; 500 that never even reached the SSE headers. Wrapping the property
    ; access in Try/Catch is the safe pattern here.
    Set chatCT = ""
    Try { Set chatCT = %request.ContentType } Catch  {}
    ; Diagnostic breadcrumb global. Read after a failed run with:
    ;   set k="" for { set k=$order(^AgInt.ChatTrace(k)) quit:k=""  write !,k,": ",^AgInt.ChatTrace(k) }
    Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_": ChatStream entry user="_$username_" ct="_chatCT
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
    ; Close the TCP connection after the SSE stream finishes. Without
    ; this, the browser reuses the keep-alive socket and the CSP gateway's
    ; connection-level auth state becomes stale — the NEXT request on the
    ; same socket gets 401 even though it sends a valid Authorization
    ; header. This was the "session expired" bug on the second chat turn.
    Do pResponse.SetHeader("Connection", "close")

    // Process-private flag SSEEvent() checks before writing. Without
    // this, /chat (non-streaming) callers that reach the gate's
    // tool_confirm emit corrupt their JSON response with SSE frames.
    Set %agenticChatSSE = 1

    ; Parse body first so we can read the client-supplied observerId.
    ; Two transports are accepted:
    ;   application/json       -> existing pBodyStream path, no attachments.
    ;   multipart/form-data    -> 'body' part carries the JSON, 'files'
    ;                             parts carry the attachments (handled
    ;                             after sessionId is established).
    Set isMultipart = (chatCT [ "multipart/form-data")
    Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_": before body-parse multipart="_isMultipart
    ; Dump every multipart part name and count so we can see what the
    ; framework actually parsed. If this list is empty for a multipart
    ; request, %CSP.REST is not parsing the body into MIMEData.
    If isMultipart {
        Set mpartName = ""
        For  {
            Set mpartName = %request.NextMimeData(mpartName)
            Quit:mpartName=""
            Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_":   mpart name='"_mpartName_"' count="_%request.CountMimeData(mpartName)
        }
        Set hasContent = $isobject(%request.Content) Try { Set hasContent = hasContent_" contentSize="_%request.Content.Size } Catch  {}
        Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_":   %request.Content isobj+size: "_hasContent
        Try { Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_":   pBodyStream type: "_$select($isobject(pBodyStream):pBodyStream.%ClassName(1)_" size="_pBodyStream.Size,1:"not-object value="_$e(pBodyStream,1,80)) } Catch {}
    }
    Set req = ""
    Try {
        If isMultipart {
            Set bodyData = %request.GetMimeData("body", "", 1)
            If $isobject(bodyData) || (bodyData '= "") {
                Set req = ##class(%DynamicAbstractObject).%FromJSON(bodyData)
            }
        } Else {
            Set req = $classmethod(util, "ParseBody", pBodyStream)
        }
    } Catch parseEx {
        Do ..SSEEvent("error", {"error":("Body parse failed ("_$select(isMultipart:"multipart",1:"json")_"): "_$extract(parseEx.DisplayString(),1,300)),"stage":"parse"})
        Return $$$OK
    }
    Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_": after body-parse reqIsObj="_$isobject(req)
    If '$isobject(req) {
        Do ..SSEEvent("error", {"error":("Invalid body — multipart="_isMultipart_", req-isobj=0, contentType="_chatCT),"stage":"parse"})
        Quit $$$OK
    }
    Set message = $classmethod(util, "DObj", req, "message")
    If message = "" {
        Do ..SSEEvent("error", {"error":"Missing 'message'","stage":"parse"})
        Quit $$$OK
    }

    ; LiveFeed session tracking. If the client provides an observerId
    ; (generated before the request so the Observer tab can connect to
    ; the stream before any events exist), use it. Otherwise generate
    ; a server-side GUID. The id is process-scoped; clears at request end.
    Set clientObs = $classmethod(util, "DObj", req, "observerId")
    If clientObs '= "" {
        Set %agenticChatSessionId = clientObs
    } Else {
        Set %agenticChatSessionId = $zstrip($system.Util.CreateGUID(), "<>W")
    }
    Set %agenticChatStart = $zhorolog
    Set ^AgInt.LiveFeed("active", %agenticChatSessionId) = $horolog
    ; Write a session_start event so the observer knows who/what
    Set startInfo = {}
    Set startInfo.sessionId = %agenticChatSessionId
    Set startInfo.user = $username
    Set startInfo.namespace = $namespace
    Do ..WriteLiveFeed("session_start", startInfo)

    ; -------- Attachment ingestion (multipart only) --------
    ; Stage each uploaded file under <mgr>/Temp/agentic-attach/<sessionId>/,
    ; extract its text via AttachmentExtractor (PyMuPDF/openpyxl/passthrough),
    ; and append the extracted text to the user's message as one
    ;   <attachment name="X" type="pdf" pages="N">...</attachment>
    ; block per file. The agent sees these in iteration 1 and synthesizes
    ; a Project Specification (per its INSTRUCTIONS) before any action.
    ; Per-attachment text is capped at 150 000 chars to keep the LLM
    ; context bounded; truncation is annotated inline.
    Set attachmentNames = ""
    Set attachStep = "(none)"
    Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_": before-attach-block isMultipart="_isMultipart
    If isMultipart {
     Try {
        Set attachStep = "begin"
        Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_": attach-try-entered"
        Set fileCount = +%request.CountMimeData("files")
        Set ^AgInt.ChatTrace($i(^AgInt.ChatTrace))=$zdt($h,3,1)_": attach-files-count="_fileCount
        Do ..WriteLiveFeed("trace", {"msg":("Attachment ingest: contentType="_chatCT_" files="_fileCount)})
        Set attachStep = "stageDir"
        Set stageDir = ##class(%File).NormalizeDirectory("Temp/agentic-attach/" _ %agenticChatSessionId, ##class(%File).ManagerDirectory())
        Do ##class(%File).CreateDirectoryChain(stageDir)
        Set blocks = ""
        For i=1:1:fileCount {
            Set attachStep = "iter"_i
            Set fstream = %request.GetMimeData("files", "", i)
            If '$isobject(fstream) { Continue }
            Set fname = fstream.FileName
            If fname = "" { Continue }
            Set safeName = $piece(fname, "/", *)
            Set safeName = $piece(safeName, "\", *)
            Set safeName = $translate(safeName, "<>:""|?*", "______")
            If '##class(AgenticInterop.Editor.AttachmentExtractor).IsSupported(safeName) {
                Do ..WriteLiveFeed("trace", {"msg":("Skipping unsupported attachment: " _ safeName)})
                Continue
            }
            Set targetPath = stageDir _ safeName
            Try {
                Set f = ##class(%Stream.FileBinary).%New()
                Set f.Filename = targetPath
                Do fstream.Rewind()
                Do f.CopyFrom(fstream)
                Set sc = f.%Save()
                If 'sc { Continue }
                Set ext = ##class(AgenticInterop.Editor.AttachmentExtractor).Extract(targetPath, safeName)
                If 'ext.ok {
                    Do ..WriteLiveFeed("trace", {"msg":("Attachment extract failed: " _ safeName _ " — " _ $select(ext.%IsDefined("error"):ext.error, 1:"unknown"))})
                    Continue
                }
                Set extractedText = ext.text
                If $length(extractedText) > 150000 {
                    Set origLen = $length(extractedText)
                    Set extractedText = $extract(extractedText, 1, 150000) _ $char(10) _ "[... truncated; original " _ origLen _ " chars]"
                }
                Set extra = ""
                If ext.%IsDefined("pages"), ext.pages '= "" { Set extra = extra _ " pages=""" _ ext.pages _ """" }
                If ext.%IsDefined("sheets"), ext.sheets '= "" { Set extra = extra _ " sheets=""" _ ext.sheets _ """" }
                Set block = "<attachment name=""" _ safeName _ """ type=""" _ ext.type _ """" _ extra _ ">" _ $char(10) _ extractedText _ $char(10) _ "</attachment>"
                Set blocks = blocks _ $char(10,10) _ block
                Set attachmentNames = attachmentNames _ $select(attachmentNames="":"",1:",") _ safeName
            } Catch  {}
        }
        If blocks '= "" {
            Set message = message _ blocks
            Do ..WriteLiveFeed("trace", {"msg":("Attachments staged: " _ attachmentNames)})
        }
     } Catch attachEx {
        ; Any uncaught exception in the attachment block becomes a visible
        ; SSE error event so the user sees what failed instead of an HTTP 500.
        Do ..SSEEvent("error", {"error":("Attachment processing failed at "_attachStep_": "_$extract(attachEx.DisplayString(),1,400)),"stage":"attachments"})
        Return $$$OK
     }
    }

    ; Resolve the agent: an explicit agentClass wins; otherwise the
    ; chatbot key maps to an agent via the Chatbot config layer; else
    ; fall back to the generalist default.
    Set agentClass = $classmethod(util, "DObj", req, "agentClass", "")
    Set chatbotKey = $classmethod(util, "DObj", req, "chatbot", "")
    If (agentClass = ""), (chatbotKey '= "") {
        Set cb = ##class(AgenticInterop.Data.Chatbot).GetByKey(chatbotKey)
        If $isobject(cb), cb.Enabled, cb.AgentClass '= "" { Set agentClass = cb.AgentClass }
    }
    If agentClass = "" { Set agentClass = "AgenticInterop.Agent.HealthInterop" }
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
        ; ── Observer: resolving LLM connection ──
        Do ..WriteLiveFeed("trace", {"msg":"Resolving LLM connection..."})
        Set provider = ##class(AgenticInterop.Connections).GetProvider(connectionName)
        Set effectiveName = $S(connectionName="":..ResolvedDefaultName(),1:connectionName)
        Set connObj = ##class(AgenticInterop.Connections).Get(effectiveName)
        Set connModel = ""
        If $isobject(connObj) && (connObj.model '= "") Set connModel = connObj.model
        Set connEv = {}
        Set connEv.msg = "LLM Provider resolved"
        Set connEv.connection = effectiveName
        Set connEv.model = connModel
        Set connEv.provider = $S($isobject(connObj):connObj.provider, 1:"unknown")
        Do ..WriteLiveFeed("provider", connEv)

        ; ── Observer: building agent ──
        Set stage = "build"
        Do ..WriteLiveFeed("trace", {"msg":("Building agent: "_agentClass)})
        Set tSC = ##class(AgenticInterop.Agent.Manager).Build(provider, .agent, agentClass)
        If 'tSC {
            Do ..SSEEvent("error", {"error":($system.Status.GetErrorText(tSC)),"stage":(stage)})
            Quit
        }
        If connModel '= "" {
            Set agent.Model = connModel
        }

        ; ── Observer: creating session ──
        Set stage = "session"
        Do ..WriteLiveFeed("trace", {"msg":"Creating LLM session (max_tokens=8192)..."})
        Set sessionConfig = {}
        Do sessionConfig.%Set("max_tokens", 8192, "number")
        Set session = agent.CreateSession(sessionConfig)
        Set turnsReplayed = ..ReplayHistory(session, history)
        Set readyEv = {}
        Set readyEv.msg = "Session ready"
        Set readyEv.turnsReplayed = turnsReplayed
        Do ..WriteLiveFeed("trace", readyEv)
        Do ..SSEEvent("status", {"phase":"ready","turnsReplayed":(turnsReplayed)})
        Set stage = "run"
        Set maxIter = +agent.MaxIterations
        If maxIter < 1 { Set maxIter = 25 }
        Set monitor = ##class(AgenticInterop.Agent.Monitor).%New(300, 100000)
        Set monitor.SSEEnabled = 1
        Do ..WriteLiveFeed("trace", {"msg":("Starting run loop (max "_maxIter_" iterations, deadline 300s, budget 100k tokens)")})
        Set response = ""
        Set iteration = 0
        Set fabricationRetried = 0
        While iteration < maxIter {
            Set iteration = iteration + 1
            Do monitor.OnIterationStart(iteration, maxIter, session)
            Set input = $select(iteration=1:message, 1:"Continue working. If you still need to act, call the next tool. If everything the user asked for is done, reply to the user in plain language with ONLY the outcome — one or two short sentences naming what now exists and where. Do NOT show tool output, JSON, or internal class names; do NOT add suggestions, caveats, comparisons, or any topic the user did not ask about.")
            ; ── Observer: calling LLM ──
            Set iterEv = {}
            Set iterEv.msg = "Calling Bedrock..."
            Set iterEv.iteration = iteration
            Set iterEv.maxIterations = maxIter
            Set iterEv.model = agent.Model
            Do ..WriteLiveFeed("llm_call", iterEv)
            Set chatStart = $zhorolog
            Set response = ..ChatWithRetry(agent, session, input, monitor)
            Set chatMs = $fnumber(($zhorolog - chatStart) * 1000, "", 0)
            ; ── Observer: LLM response received ──
            Set respEv = {}
            Set respEv.msg = "Bedrock response received"
            Set respEv.latencyMs = chatMs
            Set respEv.iteration = iteration
            Try {
                Set u = response.Usage
                If $isobject(u) {
                    Set respEv.inputTokens = +u."input_tokens"
                    Set respEv.outputTokens = +u."output_tokens"
                }
            } Catch {}
            Try { Set respEv.hasToolCalls = response.HasToolCalls() } Catch { Set respEv.hasToolCalls = 0 }
            Do ..WriteLiveFeed("llm_response", respEv)
            Do monitor.OnIterationComplete(iteration, response, session)
            If '$isobject(response) Quit
            Try { Set hasCalls = response.HasToolCalls() } Catch { Set hasCalls = 0 }
            If 'hasCalls {
                If iteration = 1, 'fabricationRetried {
                    Set checkText = ..ExtractText(response)
                    If ..LooksLikeFabrication(checkText, monitor.ToolCallTrace) {
                        Do ..WriteLiveFeed("trace", {"msg":"FABRICATION GUARD: model claimed results without calling tools, forcing retry"})
                        Set fabricationRetried = 1
                        Set iteration = iteration + 1
                        Do monitor.OnIterationStart(iteration, maxIter, session)
                        Do ..WriteLiveFeed("llm_call", {"msg":"Calling Bedrock (fabrication retry)...","iteration":(iteration)})
                        Set response = ..ChatWithRetry(agent, session, "STOP. You just wrote text claiming you built something, but you did NOT call any tools. Text is not action. You MUST call CreateProduction, AddBusinessHost, and the other tools to actually build the production. Do it now — call the tools.", monitor)
                        Do monitor.OnIterationComplete(iteration, response, session)
                        If '$isobject(response) Quit
                        Try { Set hasCalls = response.HasToolCalls() } Catch { Set hasCalls = 0 }
                        If 'hasCalls Quit
                        Continue
                    }
                }
                Do ..WriteLiveFeed("trace", {"msg":("No more tool calls after iteration "_iteration_" — model is done")})
                Quit
            }
            If iteration > 1 {
                Set cooldownSecs = $select(iteration > 5: 5, 1: 3)
                Do ..WriteLiveFeed("trace", {"msg":("Rate-limit cooldown "_cooldownSecs_"s before next iteration...")})
                If monitor.SSEEnabled {
                    Do ..SSEEvent("status", {"message":"Working... (pacing to stay within provider rate limits)"})
                }
                Hang cooldownSecs
            }
        }
        ; Emit any remaining tool_result events for the final iteration
        Do monitor.EmitFinalToolResults(session)
        Do monitor.CaptureFromSession(session)
        // Extract final text from the response
        Set finalText = ..ExtractText(response)
        // Safety net: if tools ran but the model returned no text, emit
        // a fallback so the user never sees an empty response.
        If finalText = "", monitor.ToolCallTrace '= "" {
            Set finalText = "I executed " _ $length(monitor.ToolCallTrace, ",") _ " tool calls but did not produce a summary. Please ask me to review what was built (e.g. ""review the production"") so I can report the results."
        }
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
    ; Mark session as finished in the LiveFeed so the Observer shows
    ; the completed state and stops polling.
    If $get(%agenticChatSessionId) '= "" {
        Do ..WriteLiveFeed("session_end", {})
        Kill ^AgInt.LiveFeed("active", %agenticChatSessionId)
    }
    Quit $$$OK
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

/// Wrap agent.Chat() with retry-on-rate-limit. Bedrock (and other
/// providers) return a ProviderError with "Too many tokens" or
/// "ThrottlingException" when the TPM/RPM quota is exceeded. Without
/// this wrapper, the whole turn crashes. With it, we wait 30-90s
/// (exponential backoff) and retry up to 3 more times (4 attempts
/// total). The run loop also pauses 3-5s between iterations to
/// spread token load below the TPM ceiling. Emits an SSE
/// status event during the wait so the user sees "Rate limited,
/// waiting..." in the UI instead of silence.
///
/// The monitor is passed for SSE emission only — OnIterationStart/
/// OnIterationComplete are NOT called here (the caller handles those).
ClassMethod ChatWithRetry(agent As %AI.Agent, session As %AI.Agent.Session, input As %String, monitor As AgenticInterop.Agent.Monitor) As %AI.LLM.Response
{
    ; NOTE: Quit inside a Try exits the Try block, NOT the While loop
    ; (ObjectScript gotcha). Use a success flag to control the loop.
    Set maxRetries = 3
    Set attempt = 0
    Set response = ""
    Set success = 0
    While (attempt <= maxRetries) && ('success) {
        Try {
            Set response = agent.Chat(session, input)
            Set success = 1
        } Catch ex {
            Set errText = ex.DisplayString()
            Set isRateLimit = 0
            Set lower = $zconvert(errText, "L")
            If lower [ "too many tokens" Set isRateLimit = 1
            If lower [ "throttling" Set isRateLimit = 1
            If lower [ "rate limit" Set isRateLimit = 1
            If lower [ "rate_limit" Set isRateLimit = 1
            If lower [ "429" Set isRateLimit = 1
            If lower [ "too many requests" Set isRateLimit = 1
            If lower [ "overloaded" Set isRateLimit = 1
            If 'isRateLimit {
                ; Not a rate limit — rethrow immediately
                Throw ex
            }
            If attempt >= maxRetries {
                ; Exhausted retries — rethrow so the outer catch handles it
                Throw ex
            }
            ; Wait and retry. Emit SSE status so the UI knows we're waiting.
            Set waitSecs = $select(attempt=0:30, attempt=1:60, 1:90)
            If monitor.SSEEnabled {
                Set statusEv = {}
                Set statusEv.message = "Rate limited by provider. Waiting " _ waitSecs _ " seconds before retrying (attempt " _ (attempt + 2) _ " of " _ (maxRetries + 1) _ ")..."
                Do ..SSEEvent("status", statusEv)
            }
            Hang waitSecs
            Set attempt = attempt + 1
        }
    }
    Quit response
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
    ; Mirror every SSE event to ^AgInt.LiveFeed so the Observer page
    ; can tail the session in real time from a separate browser tab.
    ; Skip tool_start / tool_result — these are now emitted in real-time
    ; by ToolStart/ToolDone (Manager.cls) DURING agent.Chat() execution.
    ; Mirroring them here would create duplicates in the Observer since
    ; the Monitor fires AFTER Chat() returns.
    If (pType = "tool_start") || (pType = "tool_result") Quit
    Do ..WriteLiveFeed(pType, pData)
}

/// Write one event to the LiveFeed global so the Observer page can
/// tail it in real time. Each event is stored as a JSON string under
/// ^AgInt.LiveFeed(sessionId, seq). The session id comes from the
/// process-private %agenticChatSessionId set by ChatStream at the
/// start of the request. Active sessions are tracked in
/// ^AgInt.LiveFeed("active", sessionId) = $horolog.
ClassMethod WriteLiveFeed(pType As %String, pData As %DynamicObject)
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
    ; Update active-session marker with latest activity time
    Set ^AgInt.LiveFeed("active", sid) = $horolog
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
