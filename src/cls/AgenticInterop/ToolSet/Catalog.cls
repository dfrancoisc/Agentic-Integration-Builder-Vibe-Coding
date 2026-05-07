/// %AI.ToolSet wrapper for the Catalog tool family. Composes the
/// AgenticInterop.Tool.Catalog %AI.Tool subclass via <Include> so the
/// framework's auto-discovery picks up every public ClassMethod as a
/// tool. The two RAG tools (SearchEns / SearchHs) are registered
/// separately at runtime by AgenticInterop.Catalog.Attach.
Class AgenticInterop.ToolSet.Catalog Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.Catalog ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Catalog">
    <Description>Cross-cutting introspection: %Dictionary metadata, IRIS namespace context, %Status decoding, error-code lookup, glossary, and API-index search. Read-only.</Description>
    <Include Class="AgenticInterop.Tool.Catalog"/>
</ToolSet>
}

}
