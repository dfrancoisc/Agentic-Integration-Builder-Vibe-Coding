/// Stub. The Catalog toolset wraps the two FastEmbed-backed
/// %AI.RAG.KnowledgeBase instances (catalog.ens for HL7+Production,
/// catalog.hs for FHIR+Transformation) plus describe_class. Phase 5 wires
/// the real RAG; this stub returns empty results so Phase 2-3 development
/// is not blocked. See docs/PLAN.md "Catalogs" + docs/TOOLS.md
/// "ToolSet.Catalog".
Class AgenticInterop.ToolSet.Catalog Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Catalog" Description="Vector search across the Ens.* and HS.* class catalogs plus %Dictionary metadata (stub — populated in Phase 5).">
</ToolSet>
}

}
