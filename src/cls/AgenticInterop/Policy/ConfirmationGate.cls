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
/// PascalCase prefixes match the auto-discovered method names from
/// %AI.Tool subclasses (e.g. StartProduction, DeleteProduction).
/// Also includes snake_case variants for any manually-registered tools.
Parameter MUTATINGPREFIXES = "Start,Stop,Delete,Remove,Create,Add,Update,Send,Compile,Purge,Drop,Reset,Clear,Build,Configure,Set,Release,Enable,Disable,start_,stop_,delete_,remove_,create_,add_,update_,send_,compile_,purge_,drop_,reset_,clear_,build_,configure_,set_,release_,enable_,disable_";

/// Comma-separated list of approval tokens the user has already
/// granted in this conversation turn. Set by the chat service
/// before invoking the agent; tools matching one of these tokens
/// pass through. Format: "<toolName>:<argsHash>" — the gate hashes
/// the call's args + name and looks for a match.
Property ApprovedTokens As %String(MAXLEN = 8000);

Method %CanExecute(tool As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
    ; Per-tool gate disabled. The agent now presents its complete plan
    ; in plain text and waits for the user's conversational approval
    ; before calling any mutating tools. This eliminates the broken
    ; per-tool Approve/Reject card flow (re-fire caused 401 auth errors,
    ; multiple cards per turn confused end users, raw JSON was not
    ; user-friendly). The gate class and its infrastructure are kept
    ; intact for future reintroduction if a selective gate (e.g.
    ; Delete/Stop only) is ever needed.
    Quit $$$OK
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
