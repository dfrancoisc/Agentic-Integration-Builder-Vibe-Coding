/// MCP: Catalog. Tools that query the FastEmbed-backed
/// %AI.RAG.KnowledgeBase catalogs (catalog.ens, catalog.hs) and the
/// pattern library.
Class AgenticInterop.MCP.Catalog Extends AgenticInterop.MCP.Base
{

Parameter NAME = "catalog";

Parameter DESCRIPTION = "Tools for searching the IRIS for Health class catalogs (catalog.ens, catalog.hs) and the pattern library.";

Parameter TOOLSETS = "AgenticInterop.ToolSet.Catalog";

}
