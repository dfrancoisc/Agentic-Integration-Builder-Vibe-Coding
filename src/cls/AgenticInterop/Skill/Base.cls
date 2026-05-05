/// Workaround base class for AgenticInterop skills.
///
/// IRIS for Health 2026.2 AI 162.0 has a bug in %AI.Agent.Skill.%OnNew:
/// it calls $ZF(-6, $$$IrisLLMLibrary, $$$LLMBUILDSKILLFROMJSON, skillObject)
/// where skillObject = ..%ToJSON() returns a %DynamicObject. The ObjectScript
/// $ZF marshaler then sends the OREF id (a small integer string) to Rust
/// instead of the JSON serialization, and the Rust LLM bridge fails with
/// "Failed to parse skill JSON: trailing characters at line 1 column N".
///
/// %AI.Provider works around this by calling .%ToJSON() twice — first to
/// build the DynamicObject, then to serialize it to a JSON string —
/// before passing to $ZF (see %AI.Provider lines 649, 717-718).
///
/// We replicate the parent %OnNew with that fix. Macro values are inlined
/// because the %AI include file isn't visible from HSCUSTOM:
///   $$$IrisLLMLibrary        = 1042
///   $$$LLMBUILDSKILLFROMJSON =   66
Class AgenticInterop.Skill.Base Extends %AI.Agent.Skill
{

Method %OnNew(externalData As %DynamicObject = "") As %Status
{
    If $ISOBJECT(externalData) {
        Set ..IsExternal   = 1
        Set ..ExternalData = externalData
    }

    Set skillJson = ..%ToJSON().%ToJSON()
    Set ..%token  = $ZF(-6, 1042, 66, skillJson)

    Return $$$OK
}

}
