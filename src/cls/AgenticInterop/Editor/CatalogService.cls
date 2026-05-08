/// REST shell for the Phase 5 catalog admin actions.
///
///   GET    /api/agentic/catalog/status             — row counts + kind breakdown per catalog
///   POST   /api/agentic/catalog/rebuild            — rebuild catalogs from the source namespace
///   GET    /api/agentic/catalog/browse             — paginated list of catalog entries
///   POST   /api/agentic/catalog/search             — test a vector search query
///
/// Browse and Search let admin users verify that the catalog contains
/// the right classes and that queries return expected results.
Class AgenticInterop.Editor.CatalogService Extends %RegisteredObject
{

ClassMethod Status(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set body = ##class(AgenticInterop.Catalog.Builder).Status()
    ; Enrich with kind breakdown for each catalog
    Set body.ens = ..%EnrichStats(body.ens)
    Set body.hs  = ..%EnrichStats(body.hs)
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// Return paginated catalog entries.
/// Query params: catalog (ens|hs), page (1-based), pageSize (default 50),
///               filter (substring match on text), kind (exact match on metadata.kind)
ClassMethod Browse(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set catalog = $get(%request.Data("catalog",1), "ens")
    Set page = +$get(%request.Data("page",1), 1)
    If page < 1 { Set page = 1 }
    Set pageSize = +$get(%request.Data("pageSize",1), 50)
    If pageSize < 1 { Set pageSize = 50 }
    If pageSize > 200 { Set pageSize = 200 }
    Set filter = $get(%request.Data("filter",1), "")
    Set kind = $get(%request.Data("kind",1), "")
    Set table = $select(catalog="hs":"AgenticInterop_Catalog.HsCatalog", 1:"AgenticInterop_Catalog.EnsCatalog")
    Set out = {}
    Set out.catalog = catalog
    Set out.page = page
    Set out.pageSize = pageSize
    Set out.entries = []
    Try {
        ; Build WHERE clause — avoid JSON_VALUE (not on all IRIS builds).
        ; Text filter uses LIKE on the text column; kind filter uses LIKE
        ; on the metadata column (metadata is a JSON string containing "kind":"value").
        Set where = ""
        Set params = 0
        If filter '= "" {
            Set where = where _ $select(where="":"WHERE ", 1:" AND ") _ "text LIKE ?"
            Set params = params + 1
            Set paramVal(params) = "%" _ filter _ "%"
        }
        If kind '= "" {
            ; Match "kind":"<value>" inside the JSON string
            Set where = where _ $select(where="":"WHERE ", 1:" AND ") _ "metadata LIKE ?"
            Set params = params + 1
            Set paramVal(params) = "%""kind"":""" _ kind _ """%"
        }
        ; Count total
        Set countSql = "SELECT COUNT(*) AS n FROM " _ table _ " " _ where
        If params = 0 {
            Set rsC = ##class(%SQL.Statement).%ExecDirect(, countSql)
        } ElseIf params = 1 {
            Set rsC = ##class(%SQL.Statement).%ExecDirect(, countSql, paramVal(1))
        } Else {
            Set rsC = ##class(%SQL.Statement).%ExecDirect(, countSql, paramVal(1), paramVal(2))
        }
        Set total = 0
        If rsC.%Next() { Set total = rsC.%GetData(1) }
        Set out.total = total
        Set out.totalPages = $select(total=0:1, pageSize>0: ((total - 1) \ pageSize) + 1, 1: 1)
        ; Fetch matching rows and paginate in ObjectScript.
        ; Catalogs are small (<300 rows) so this is safe and avoids
        ; IRIS SQL pagination quirks (%VID, OFFSET not universally supported).
        Set offset = (page - 1) * pageSize
        Set dataSql = "SELECT id, text, metadata, source FROM " _ table _ " " _ where _ " ORDER BY text"
        If params = 0 {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, dataSql)
        } ElseIf params = 1 {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, dataSql, paramVal(1))
        } Else {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, dataSql, paramVal(1), paramVal(2))
        }
        Set rowIdx = 0
        While rs.%Next() {
            Set rowIdx = rowIdx + 1
            ; Skip rows before the offset
            If rowIdx <= offset { Continue }
            ; Stop after pageSize rows
            If (rowIdx - offset) > pageSize { Quit }
            Set entry = {}
            Set entry.id = rs.%GetData(1)
            Set entry.text = rs.%GetData(2)
            ; Parse metadata JSON
            Set metaStr = rs.%GetData(3)
            Try {
                Set entry.metadata = ##class(%DynamicAbstractObject).%FromJSON(metaStr)
            } Catch  {
                Set entry.metadataRaw = metaStr
            }
            Set entry.source = rs.%GetData(4)
            Do out.entries.%Push(entry)
        }
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

/// Test a vector search query against a catalog. Returns the top-K
/// results with similarity scores — the same results the agent sees
/// at chat time.
///
/// Body: { catalog: "ens"|"hs", query: "...", k: 8 }
ClassMethod Search(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", %request.Content)
    Set catalog = "ens"
    Set query = ""
    Set topK = 8
    If $isobject(req) {
        Set catalog = $classmethod(util, "DObj", req, "catalog", "ens")
        Set query = $classmethod(util, "DObj", req, "query", "")
        Set topKStr = $classmethod(util, "DObj", req, "k", "8")
        If topKStr '= "" { Set topK = +topKStr }
    }
    If topK < 1 { Set topK = 8 }
    If topK > 20 { Set topK = 20 }
    Set out = {}
    Set out.catalog = catalog
    Set out.query = query
    Set out.k = topK
    Set out.results = []
    If query = "" {
        Set out.ok = 0
        Set out.error = "Pass a non-empty query string."
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }
    Try {
        Set kbName = $select(catalog="hs":"search_hs", 1:"search_ens")
        Set table = $select(catalog="hs":"AgenticInterop_Catalog.HsCatalog", 1:"AgenticInterop_Catalog.EnsCatalog")
        Set kbDesc = $select(catalog="hs":"Vector search across HS.* classes.", 1:"Vector search across Ens.* classes.")
        ; Build the KB and register it with a ToolMgr so we can call
        ; ExecuteTool — %AI.RAG.KnowledgeBase has no direct Query()
        ; method; the only supported query path is via the tool layer.
        Set emb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
        Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
        Set vs.TableName = table
        Set vs.Dimensions = emb.Dimensions
        Set vs.ModelName = emb.ModelName
        Set sc = vs.Build()
        If $$$ISERR(sc) { Throw ##class(%Exception.StatusException).CreateFromStatus(sc) }
        Set kb = ##class(%AI.RAG.KnowledgeBase).%New(kbName, kbDesc)
        Set kb.TopK = topK
        Set sc = kb.Build(emb, vs)
        If $$$ISERR(sc) { Throw ##class(%Exception.StatusException).CreateFromStatus(sc) }
        Set toolMgr = ##class(%AI.ToolMgr).%New()
        Set sc = kb.AddToManager(toolMgr)
        If $$$ISERR(sc) { Throw ##class(%Exception.StatusException).CreateFromStatus(sc) }
        ; Execute the vector search via the tool layer
        Set args = {}
        Set args.query = query
        Set toolResult = toolMgr.ExecuteTool(kbName, args)
        ; toolResult is { timing, value: [ {id, text, score, metadata}, ... ] }
        Set resultsArr = toolResult.%Get("value")
        If '$isobject(resultsArr) { Set resultsArr = [] }
        Set out.timing = toolResult.%Get("timing")
        For i=0:1:resultsArr.%Size()-1 {
            Set chunk = resultsArr.%Get(i)
            Set r = {}
            Set r.rank = i + 1
            Set r.text = chunk.%Get("text")
            Set r.score = chunk.%Get("score")
            Set r.id = chunk.%Get("id")
            ; metadata is already a parsed DynamicObject from the tool result
            Set meta = chunk.%Get("metadata")
            If $isobject(meta) {
                Set r.metadata = meta
            }
            Do out.results.%Push(r)
        }
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 600)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

ClassMethod Rebuild(pResponse As %CSP.Response, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    Set sourceNs = "USER"
    Set scope = "both"
    Set source = "dictionary"
    Set cap = 5000
    Set xlsPath = ""
    If $isobject(req) {
        Set sourceNs = $classmethod(util, "DObj", req, "sourceNamespace", "USER")
        Set scope = $classmethod(util, "DObj", req, "scope", "both")
        Set source = $classmethod(util, "DObj", req, "source", "dictionary")
        Set xlsPath = $classmethod(util, "DObj", req, "xlsPath", "")
        Set capStr = $classmethod(util, "DObj", req, "cap", "5000")
        If capStr '= "" { Set cap = +capStr }
    }
    If source = "xls" {
        Set body = ##class(AgenticInterop.Catalog.Builder).RebuildAllFromXLS(xlsPath)
        Quit $classmethod(util, "WriteJSON", pResponse, body)
    }
    If scope = "ens" {
        Set body = {}
        Set body.ens = ##class(AgenticInterop.Catalog.Builder).RebuildEns(sourceNs, cap)
        Set body.ok = 1
    } ElseIf scope = "hs" {
        Set body = {}
        Set body.hs = ##class(AgenticInterop.Catalog.Builder).RebuildHs(sourceNs, cap)
        Set body.ok = 1
    } Else {
        Set body = ##class(AgenticInterop.Catalog.Builder).RebuildAll(sourceNs, cap)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// Enrich a catalog stats object with kind breakdown. Adds
/// { kinds: [ {kind, count}, ... ] } to the stats.
/// Parses metadata JSON in ObjectScript since JSON_VALUE is not
/// available on all IRIS builds.
ClassMethod %EnrichStats(pStats As %DynamicObject) As %DynamicObject [ Internal ]
{
    If '$isobject(pStats) Quit pStats
    If 'pStats.exists Quit pStats
    Set table = pStats.table
    If table = "" Quit pStats
    Set pStats.kinds = []
    Try {
        ; Walk all rows, parse metadata JSON, count kinds
        Set kindCounts = ""  ; local array: kindCounts(kindName) = count
        Set sql = "SELECT metadata FROM " _ table _ " WHERE metadata IS NOT NULL"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        While rs.%Next() {
            Set metaStr = rs.%GetData(1)
            Set kindVal = ""
            Try {
                Set meta = ##class(%DynamicAbstractObject).%FromJSON(metaStr)
                Set kindVal = meta.%Get("kind")
            } Catch  {}
            If kindVal = "" { Set kindVal = "(unknown)" }
            If $data(kindCounts(kindVal)) { Set kindCounts(kindVal) = kindCounts(kindVal) + 1 }
            Else { Set kindCounts(kindVal) = 1 }
        }
        ; Convert to array sorted by count desc
        Set kindArr = []
        Set kn = ""
        For  {
            Set kn = $order(kindCounts(kn))
            If kn = "" Quit
            Set k = {}
            Set k.kind = kn
            Set k.count = kindCounts(kn)
            Do kindArr.%Push(k)
        }
        ; Sort descending by count (simple bubble sort, small array)
        For i=0:1:kindArr.%Size()-2 {
            For j=i+1:1:kindArr.%Size()-1 {
                If kindArr.%Get(j).count > kindArr.%Get(i).count {
                    Set tmp = kindArr.%Get(i)
                    Do kindArr.%Set(i, kindArr.%Get(j))
                    Do kindArr.%Set(j, tmp)
                }
            }
        }
        Set pStats.kinds = kindArr
    } Catch  {}
    Quit pStats
}

}
