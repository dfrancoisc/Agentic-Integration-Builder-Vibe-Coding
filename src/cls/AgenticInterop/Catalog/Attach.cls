/// Per-request glue: register the existing search_ens / search_hs
/// KnowledgeBase tools onto an agent's ToolManager. Called from
/// AgenticInterop.Agent.Manager.Build right after the MCPs/Skills
/// land, so the LLM sees catalog search alongside the rest of the
/// tool surface.
///
/// If a catalog hasn't been built yet (RebuildCatalogs never ran on
/// this instance), the corresponding KB simply isn't attached — no
/// runtime error, just no tool. The chat surface still works; the
/// LLM just can't search the catalog. The admin "Rebuild" button
/// turns this on.
Class AgenticInterop.Catalog.Attach Extends %RegisteredObject
{

ClassMethod ToAgent(pAgent As %AI.Agent) As %Status
{
    Do ..%TryAttach(pAgent, "AgenticInterop.Catalog.Builder", "ENSKBNAME", "ENSTABLE", "Vector search across Ens.Host / EnsLib.* business hosts and adapters in the active interop namespace. Call before recommending any IRIS class.")
    Do ..%TryAttach(pAgent, "AgenticInterop.Catalog.Builder", "HSKBNAME",  "HSTABLE",  "Vector search across HealthShare HS.* transformation classes (DTLs, FHIR↔SDA3 mappers, HL7 helpers).")
    Quit $$$OK
}

ClassMethod %TryAttach(pAgent As %AI.Agent, pBuilderClass As %String, pNameParam As %String, pTableParam As %String, pDescription As %String) [ Internal ]
{
    Try {
        Set kbName = $parameter(pBuilderClass, pNameParam)
        Set tableName = $parameter(pBuilderClass, pTableParam)
        // Skip silently if the catalog hasn't been built yet — the
        // chat continues to work without it.
        If '..%TableHasRows(tableName) { Quit }
        Set emb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
        Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
        Set vs.TableName = tableName
        Set vs.Dimensions = emb.Dimensions
        Set vs.ModelName = emb.ModelName
        Do vs.Build()
        Set kb = ##class(%AI.RAG.KnowledgeBase).%New(kbName, pDescription)
        Set kb.TopK = 8
        Do kb.Build(emb, vs)
        Do kb.AddToAgent(pAgent)
    } Catch  {
        // Best-effort attach. Don't break the chat over a catalog
        // wiring failure — the LLM will just answer without that
        // tool's input.
    }
}

ClassMethod %TableHasRows(pTable As %String) As %Boolean [ Internal ]
{
    Set has = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM " _ pTable)
        If rs.%Next() { Set has = (+rs.%Get("n") > 0) }
    } Catch  { }
    Quit has
}

}
