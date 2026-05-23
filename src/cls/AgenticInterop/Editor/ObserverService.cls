/// Observer SSE service — tails ^AgInt.LiveFeed(sessionId, seq) in
/// real time, delivering every event the chat session writes to the
/// LiveFeed global. Used by the Observer HTML page to show a "behind
/// the scenes" view of the agent's computation during VP demos.
///
/// Two endpoints:
///   GET /observer/sessions — JSON list of active and recent sessions
///   GET /observer/stream?session=<id> — SSE stream tailing the feed
///
/// The stream endpoint long-polls the global: it reads all events from
/// the last-seen sequence, sends them as SSE frames, then hangs 0.5s
/// and checks again. It terminates when a session_end event arrives
/// or 10 minutes of inactivity pass (whichever comes first).
///
/// Security: inherits the Dispatch.cls OnPreDispatch auth gate. The
/// observer page requires login just like the chat page.
Class AgenticInterop.Editor.ObserverService Extends %RegisteredObject
{

/// Return JSON array of active and recent (last 30 min) sessions.
/// Each entry: { id, user, namespace, startTs, active, eventCount }
ClassMethod Sessions(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set arr = []
    ; Walk ^AgInt.LiveFeed("active", sessionId)
    Set sid = ""
    For {
        Set sid = $order(^AgInt.LiveFeed("active", sid))
        If sid = "" Quit
        Set entry = ..SessionInfo(sid, 1)
        If $isobject(entry) Do arr.%Push(entry)
    }
    ; Also scan recent sessions that ended (no "active" node) but
    ; still have data in ^AgInt.LiveFeed(sessionId). Walk top-level
    ; subscripts, skip "active". Limit to sessions with events in
    ; the last 30 minutes based on $horolog comparison.
    Set cutoff = $piece($horolog, ",", 2) - 1800
    If cutoff < 0 Set cutoff = cutoff + 86400
    Set sid = ""
    For {
        Set sid = $order(^AgInt.LiveFeed(sid))
        If sid = "" Quit
        If sid = "active" Continue
        ; Skip if already in active list
        If $data(^AgInt.LiveFeed("active", sid)) Continue
        ; Check last event timestamp — read last seq
        Set lastSeq = +$get(^AgInt.LiveFeed(sid))
        If lastSeq < 1 Continue
        Set entry = ..SessionInfo(sid, 0)
        If $isobject(entry) Do arr.%Push(entry)
    }
    Set pResponse.ContentType = "application/json"
    Do arr.%ToJSON()
    Quit $$$OK
}

/// Build a session info object from the global data.
ClassMethod SessionInfo(pId As %String, pActive As %Boolean) As %DynamicObject [ Internal ]
{
    Set lastSeq = +$get(^AgInt.LiveFeed(pId))
    If lastSeq < 1 Quit ""
    Set info = {}
    Set info.id = pId
    Set info.active = pActive
    Set info.eventCount = lastSeq
    ; Parse first event for user/namespace/start time
    Set firstRaw = $get(^AgInt.LiveFeed(pId, 1))
    If firstRaw '= "" {
        Try {
            Set first = ##class(%DynamicAbstractObject).%FromJSON(firstRaw)
            If $isobject(first) {
                Try { Set info.user = first.data.user } Catch {}
                Try { Set info.namespace = first.data.namespace } Catch {}
                Try { Set info.startTs = first.ts } Catch {}
            }
        } Catch {}
    }
    ; Parse last event for elapsed time
    Set lastRaw = $get(^AgInt.LiveFeed(pId, lastSeq))
    If lastRaw '= "" {
        Try {
            Set last = ##class(%DynamicAbstractObject).%FromJSON(lastRaw)
            If $isobject(last) {
                Try { Set info.lastTs = last.ts } Catch {}
                Try { Set info.elapsed = last.elapsed } Catch {}
            }
        } Catch {}
    }
    Quit info
}

/// SSE stream that tails ^AgInt.LiveFeed(sessionId). Polls every 500ms
/// for new events, sends them as SSE frames. Terminates on session_end
/// event or 600s inactivity timeout.
///
/// Query param: session=<id> — required.
/// If session=latest, picks the most recently active session.
ClassMethod Stream(pResponse As %CSP.Response) As %Status
{
    Set pResponse.ContentType = "text/event-stream"
    Set pResponse.CharSet = "utf-8"
    Do pResponse.SetHeader("Cache-Control", "no-cache, no-transform")
    Do pResponse.SetHeader("X-Accel-Buffering", "no")
    Do pResponse.SetHeader("Connection", "close")

    Set sid = $get(%request.Data("session", 1))
    ; "latest" mode: find most recently active session
    If sid = "latest" {
        Set sid = ..FindLatestSession()
    }
    If sid = "" {
        Write "event: error", $char(10)
        Write "data: {""error"":""Missing session parameter""}", $char(10), $char(10)
        Quit $$$OK
    }

    ; Send initial snapshot: replay all existing events. Flush after
    ; every event — the Apache CSP gateway buffers aggressively on GET
    ; SSE streams, so one big batch+flush at the end never reaches the
    ; browser. Per-event flush mirrors what ChatService does.
    Set cursor = 0
    Set ended = 0
    Set lastSeq = +$get(^AgInt.LiveFeed(sid))
    For seq=1:1:lastSeq {
        Set raw = $get(^AgInt.LiveFeed(sid, seq))
        If raw = "" Continue
        Write "event: feed", $char(10)
        Write "data: ", raw, $char(10)
        Write ":", ..Padding(), $char(10)
        Write $char(10)
        Write *-3
        Set cursor = seq
        ; Detect session_end during replay so we exit cleanly for
        ; completed sessions instead of hanging in the poll loop.
        Try {
            Set ev = ##class(%DynamicAbstractObject).%FromJSON(raw)
            If $isobject(ev), ev.type = "session_end" Set ended = 1
        } Catch {}
    }

    ; If session already ended during replay, exit immediately.
    If ended Quit $$$OK

    ; Long-poll for new events. Check every 500ms. Exit on
    ; session_end or 600s (10 min) inactivity timeout.
    Set idleStart = $zhorolog
    Set maxIdle = 600
    Set lastKeepalive = $zhorolog
    While 'ended {
        ; Check for new events since cursor
        Set newSeq = +$get(^AgInt.LiveFeed(sid))
        If newSeq > cursor {
            Set idleStart = $zhorolog
            For seq=(cursor+1):1:newSeq {
                Set raw = $get(^AgInt.LiveFeed(sid, seq))
                If raw = "" Continue
                Write "event: feed", $char(10)
                Write "data: ", raw, $char(10)
                Write ":", ..Padding(), $char(10)
                Write $char(10)
                Write *-3
                ; Check if this is session_end
                Try {
                    Set ev = ##class(%DynamicAbstractObject).%FromJSON(raw)
                    If $isobject(ev), ev.type = "session_end" Set ended = 1
                } Catch {}
            }
            Set cursor = newSeq
        } Else {
            ; No new events — send keepalive comment every 10s to
            ; prevent Apache from killing the idle connection.
            If ($zhorolog - lastKeepalive) > 10 {
                Write ":keepalive ", $zdatetime($horolog, 3, 1), $char(10)
                Write $char(10)
                Write *-3
                Set lastKeepalive = $zhorolog
            }
            ; Check idle timeout
            If ($zhorolog - idleStart) > maxIdle {
                Set ended = 1
                Write "event: feed", $char(10)
                Write "data: {""type"":""timeout"",""data"":{},""ts"":"""_$zdatetime($horolog,3,1)_""",""elapsed"":""0""}", $char(10)
                Write $char(10)
                Write *-3
            }
        }
        If 'ended Hang 0.5
    }
    Quit $$$OK
}

/// Find the most recently active session (for session=latest mode).
/// Prefers active sessions; if none, finds the session with the most
/// recent first event timestamp by checking all non-active sessions.
ClassMethod FindLatestSession() As %String [ Internal ]
{
    Set best = ""
    Set bestH = ""
    Set sid = ""
    For {
        Set sid = $order(^AgInt.LiveFeed("active", sid))
        If sid = "" Quit
        Set h = $get(^AgInt.LiveFeed("active", sid))
        If bestH = "" || (h ] bestH) {
            Set best = sid
            Set bestH = h
        }
    }
    ; If no active sessions, find the one with the latest start time
    ; by reading the first event of each session. GUIDs don't sort
    ; chronologically so $order(...,-1) doesn't give the most recent.
    If best = "" {
        Set bestTs = ""
        Set sid = ""
        For {
            Set sid = $order(^AgInt.LiveFeed(sid))
            If sid = "" Quit
            If sid = "active" Continue
            ; Read first event to get timestamp
            Set raw = $get(^AgInt.LiveFeed(sid, 1))
            If raw = "" Continue
            Set ts = ""
            Try {
                Set ev = ##class(%DynamicAbstractObject).%FromJSON(raw)
                If $isobject(ev) Set ts = ev.ts
            } Catch {}
            If ts '= "", (bestTs = "" || (ts ] bestTs)) {
                Set best = sid
                Set bestTs = ts
            }
        }
    }
    Quit best
}

/// Purge old LiveFeed data. Called periodically or manually. Removes
/// sessions older than pMaxAgeMins minutes.
ClassMethod Purge(pMaxAgeMins As %Integer = 60) As %Integer
{
    Set count = 0
    Set cutoff = $piece($horolog, ",", 2) - (pMaxAgeMins * 60)
    If cutoff < 0 Set cutoff = cutoff + 86400
    Set sid = ""
    For {
        Set sid = $order(^AgInt.LiveFeed(sid))
        If sid = "" Quit
        If sid = "active" Continue
        ; Skip active sessions
        If $data(^AgInt.LiveFeed("active", sid)) Continue
        ; Kill old sessions
        Kill ^AgInt.LiveFeed(sid)
        Set count = count + 1
    }
    Quit count
}

/// Purge ALL LiveFeed data (active + finished). Called by the
/// observer UI "Clear" button so the next poll starts fresh.
ClassMethod PurgeAll(pResponse As %CSP.Response) As %Status
{
    Set count = 0
    Set sid = ""
    For {
        Set sid = $order(^AgInt.LiveFeed(sid))
        If sid = "" Quit
        If sid = "active" {
            Kill ^AgInt.LiveFeed("active")
            Continue
        }
        Kill ^AgInt.LiveFeed(sid)
        Set count = count + 1
    }
    Set pResponse.ContentType = "application/json"
    Set out = {}
    Set out.ok = 1
    Set out.purged = count
    Do out.%ToJSON()
    Quit $$$OK
}

/// 1KB padding — same pattern as ChatService.SSEPadding. Reuses the
/// same process-private cache.
ClassMethod Padding() As %String [ Internal ]
{
    If $get(^||AgenticInterop.SSEPad1k) '= "" Quit ^||AgenticInterop.SSEPad1k
    Set s = ""
    For i=1:1:1024 Set s = s _ "x"
    Set ^||AgenticInterop.SSEPad1k = s
    Quit s
}

}
