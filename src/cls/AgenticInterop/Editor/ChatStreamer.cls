/// Per-token callback for %AI.Agent.StreamChat(). Each chunk arrives
/// via OnChunk() and is emitted as an SSE `token` event so the chat
/// client can render text in real time as the LLM streams it.
///
/// Also accumulates the full content into a buffer property — when
/// StreamChat returns, `response.Content` can be empty for long
/// responses (the framework only delivered tokens via callback). The
/// chat service reads this buffer for the response envelope's "final
/// text" archival. Pattern ported from Catalog.SSEStreamer in
/// dfrancoisc/new-interoperability-health.
Class AgenticInterop.Editor.ChatStreamer Extends %RegisteredObject
{

/// Full streamed content, accumulated chunk by chunk.
Property Buffer As %String(MAXLEN = "") [ InitialExpression = "" ];

Method OnChunk(chunk As %String)
{
    If chunk = "" Quit
    Set ..Buffer = ..Buffer _ chunk
    Set obj = {}
    Set obj.text = chunk
    Do ##class(AgenticInterop.Editor.ChatService).SSEEvent("token", obj)
}

}
