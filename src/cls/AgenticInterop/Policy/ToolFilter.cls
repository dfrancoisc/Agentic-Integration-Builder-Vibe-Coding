/// Discovery policy that strips framework waste tools AND deduplicates
/// the catalog so the LLM sees each tool exactly once.
///
/// %AI.Agent.%Init() auto-discovers every non-abstract %AI.Tool subclass
/// in the namespace, adding them to FindTools. Manager.Build then calls
/// UseToolSet on each Tool class to make individual methods executable.
/// Both paths add entries to the catalog, so without filtering the LLM
/// would see every tool twice.
///
/// This policy:
///   1. Removes framework auto-discovered waste (%AI.Tools.FileSystem,
///      SQL, ShellTools, %AI.Agent.Skill) — ~2,100 tokens saved.
///   2. Removes AgenticInterop.Skill.Base (abstract base class that
///      slips through auto-discovery).
///   3. Deduplicates by class name — keeps the FIRST entry for each
///      class (the one with isToolSet=0 and tool method definitions).
///
/// Wired in by AgenticInterop.Agent.Manager.Build after %Init().
Class AgenticInterop.Policy.ToolFilter Extends %AI.Policy.Discovery
{

/// Filter the tool catalog before each LLM request. Removes excluded
/// classes and deduplicates by class name.
Method %Resolve(catalog As %DynamicArray) As %Status
{
    ; Classes to strip entirely from the LLM-visible catalog.
    Set exclude("%AI.Tools.FileSystem") = 1
    Set exclude("%AI.Tools.SQL") = 1
    Set exclude("%AI.Tools.ShellTools") = 1
    Set exclude("%AI.Agent.Skill") = 1
    Set exclude("AgenticInterop.Skill.Base") = 1

    ; Collect entries to keep: first occurrence per class wins.
    Set kept = []
    Set iter = catalog.%GetIterator()
    While iter.%GetNext(.key, .tool) {
        Set cls = tool.class
        ; Skip excluded classes
        If $data(exclude(cls)) Continue
        ; Skip duplicates (second registration of same class)
        If $data(seen(cls)) Continue
        Set seen(cls) = 1
        Do kept.%Push(tool)
    }

    ; Replace catalog contents with the filtered list
    While catalog.%Size() > 0 { Do catalog.%Pop() }
    Set iter = kept.%GetIterator()
    While iter.%GetNext(.key, .tool) {
        Do catalog.%Push(tool)
    }

    Quit $$$OK
}

/// Not used — this policy only removes/deduplicates, never adds tools.
/// Return $$$NULLOREF so the framework falls through to normal dispatch.
Method %Execute(toolName As %String, args As %DynamicObject) As %DynamicObject
{
    Quit $$$NULLOREF
}

}
