/// Authorization policy that intercepts every tool call before the
/// framework hands it to the implementation. Tools whose definition
/// declares `"requires_confirmation": true` (or whose name starts with
/// a mutating verb prefix like start_, stop_, delete_, remove_,
/// purge_, drop_) are BLOCKED with a structured error. The error
/// message is what the LLM sees in its tool-result frame; it includes
/// a JSON envelope the chat surface uses to render the inline
/// Approve / Reject card.
///
/// Phase 4 (this iteration): the gate denies mutating tools with a
/// clear "user confirmation required" error. The agent then includes
/// the pending action in its assistant text so the user can decide.
/// On the user's "approve X" follow-up, the chat surface includes a
/// confirmation token in its history; this same policy then permits
/// the tool to fire.
///
/// Phase 4 follow-up: replace the deny-and-resurface flow with an
/// SSE-suspend pattern (policy emits tool_confirm event, blocks on a
/// $LOCK keyed by the token, frontend posts /chat/confirm, lock
/// releases, policy returns OK/Deny) so the user clicks Approve
/// without retyping the request.
Class AgenticInterop.Policy.ConfirmationGate Extends %AI.Policy.Authorization
{

/// Tool-name prefixes that we treat as mutating regardless of the
/// definition's requires_confirmation flag. Catches the case where a
/// tool author forgets to mark a destructive op.
Parameter MUTATINGPREFIXES = "start_,stop_,delete_,remove_,purge_,drop_,reset_,clear_,truncate_,kill_,unmount_,deploy_,uninstall_";

/// Comma-separated list of approval tokens the user has already
/// granted in this conversation turn. Set by the chat service
/// before invoking the agent; tools matching one of these tokens
/// pass through. Format: "<toolName>:<argsHash>" — the gate hashes
/// the call's args + name and looks for a match.
Property ApprovedTokens As %String(MAXLEN = 8000);

Method %CanExecute(tool As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
    Set toolName = ""
    Try { Set toolName = call.name } Catch  {}
    If toolName = "" { Quit $$$OK }

    // Pull the tool definition's metadata. The tool string is JSON;
    // some builds pass the full definition.
    Set requiresConfirm = 0
    Try {
        Set toolObj = ##class(%DynamicAbstractObject).%FromJSON(tool)
        If $isobject(toolObj) {
            Set requiresConfirm = ''toolObj.%Get("requires_confirmation", 0)
        }
    } Catch  {}

    // Belt-and-suspenders: any tool whose name starts with one of the
    // mutating prefixes is gated even if the definition forgot to
    // mark requires_confirmation.
    If 'requiresConfirm {
        Set prefixes = ..#MUTATINGPREFIXES
        For i=1:1:$LENGTH(prefixes, ",") {
            Set p = $ZSTRIP($PIECE(prefixes, ",", i), "<>W")
            If p = "" { Continue }
            If $extract(toolName, 1, $length(p)) = p {
                Set requiresConfirm = 1
                Quit
            }
        }
    }
    If 'requiresConfirm { Quit $$$OK }

    // The user may have pre-approved this exact call.
    Set token = ..%TokenFor(toolName, call)
    If ..ApprovedTokens '= "", (","_..ApprovedTokens_",") [ (","_token_",") {
        Quit $$$OK
    }

    // Refuse — the LLM sees this status text as the tool result. It
    // includes a JSON envelope the chat UI parses to render the
    // Approve / Reject card. Keep the prefix human-readable so even
    // if the parser misses it, the user sees what's pending.
    Set argsJson = "{}"
    Try {
        Set ar = call.arguments
        If $isobject(ar) { Set argsJson = ar.%ToJSON() }
    } Catch  {}
    Set envelope = {
        "type": "confirmation_required",
        "tool": (toolName),
        "arguments": ($zconvert(argsJson, "I", "JSON")),
        "token": (token),
        "message": ("Tool '" _ toolName _ "' performs a state-changing action. The user must approve before it runs.")
    }
    // Emit a tool_confirm SSE event so the chat surface can render an
    // inline Approve / Reject card alongside the model's response. The
    // event flows over the same SSE response that's currently streaming
    // tokens. If we're on the non-streaming /chat path (no open SSE
    // stream), the SSEEvent write fails harmlessly — the LLM still
    // receives the deny error and explains it textually.
    Try {
        Set ev = {}
        Set ev.token = token
        Set ev.tool = toolName
        Set ev.arguments = ($zconvert(argsJson, "I", "JSON"))
        Set ev.message = envelope.message
        Do ##class(AgenticInterop.Editor.ChatService).SSEEvent("tool_confirm", ev)
    } Catch  {}
    Set body = "Tool execution blocked — user confirmation required. " _ envelope.%ToJSON()
    Quit $$$ERROR($$$GeneralError, body)
}

/// Stable hash of name + arguments so the same call gets the same
/// token across turns. Cheap content hash via $zcrc — collisions are
/// fine in practice (the user is approving a specific call, not a
/// category of calls).
ClassMethod %TokenFor(pName As %String, pCall As %DynamicObject) As %String
{
    Set argsJson = ""
    Try { Set argsJson = pCall.arguments.%ToJSON() } Catch  {}
    Set raw = pName _ "|" _ argsJson
    Quit pName _ ":" _ $ZHEX($zcrc(raw, 7))
}

}
