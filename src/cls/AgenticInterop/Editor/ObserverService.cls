/// Observer service — tails ^AgInt.LiveFeed(sessionId, seq) in real time,
/// delivering every event the chat session writes to the LiveFeed global.
/// Used by the Observer HTML page to show a "behind the scenes" view of
/// the agent's computation during VP demos.
///
/// Three endpoints:
///   GET  /observer/sessions — JSON list of active and recent sessions
///   POST /observer/stream   — JSON batch of events since a cursor
///   POST /observer/purge    — Clear all LiveFeed data
///
/// The stream endpoint uses fast JSON polling (POST every 500ms from the
/// browser with an incrementing cursor) instead of SSE long-poll because
/// the Apache CSP gateway buffers SSE responses on non-chat endpoints and
/// they never reach the browser. The 500ms poll rate gives near-real-time
/// visibility into tool execution during agent.Chat().
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

/// Return events since a cursor position for a given session. The
/// observer page polls this every 500ms with an incrementing cursor to
/// get near-real-time visibility into tool execution during agent.Chat().
///
/// POST body: { "session": "<id>", "cursor": <int> }
/// session — required. Use "latest" to auto-pick the most recent.
/// cursor  — optional (default 0). Events after this seq are returned.
///
/// Response: { session, cursor, events: [...], ended: 0|1 }
ClassMethod Stream(pResponse As %CSP.Response) As %Status
{
    ; Read session id from POST body or query param (backwards compat)
    Set sid = ""
    Set body = ""
    Try {
        Set body = ##class(%DynamicAbstractObject).%FromJSON(%request.Content)
        If $isobject(body) Set sid = body.session
    } Catch {}
    If sid = "" Set sid = $get(%request.Data("session", 1))
    ; "latest" mode: find most recently active session
    If sid = "latest" {
        Set sid = ..FindLatestSession()
    }
    If sid = "" {
        Set pResponse.ContentType = "application/json"
        Set pResponse.Status = "400 Bad Request"
        Set err = {}
        Set err.error = "Missing session parameter"
        Do err.%ToJSON()
        Quit $$$OK
    }
    Set cursor = +$get(%request.Data("cursor", 1))
    Try {
        If $isobject(body), body.%IsDefined("cursor") Set cursor = +body.cursor
    } Catch {}
    Set pResponse.ContentType = "application/json"
    Set arr = []
    Set lastSeq = +$get(^AgInt.LiveFeed(sid))
    Set ended = 0
    For seq=(cursor+1):1:lastSeq {
        Set raw = $get(^AgInt.LiveFeed(sid, seq))
        If raw = "" Continue
        Try {
            Set ev = ##class(%DynamicAbstractObject).%FromJSON(raw)
            Do arr.%Push(ev)
            If ev.type = "session_end" Set ended = 1
        } Catch {}
    }
    Set out = {}
    Set out.session = sid
    Set out.cursor = lastSeq
    Set out.events = arr
    Set out.ended = ended
    Do out.%ToJSON()
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
