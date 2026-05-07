/// Build / refresh the two Phase 5 catalogs:
///
///   - search_ens — Ens.Host descendants + EnsLib adapters from a
///     target interop namespace (default USER). The LLM uses this to
///     answer "which Business Service / Process / Operation fits this
///     pattern?" and "which adapter speaks this protocol?".
///
///   - search_hs — HealthShare transformation classes (HS.FHIR.DTL.*,
///     HS.Gateway.*, HS.Util.HC.HL7.*). The LLM uses this to answer
///     "is there a stock DTL for X to Y?".
///
/// Both catalogs use the bundled FastEmbed embedder (384-dim,
/// AllMiniLML6V2, in-process — no API key) so a fresh install can
/// build them with no external dependency. The persistent rows live
/// in HSCUSTOM (where this class is compiled); the dictionary read
/// switches to the target namespace via `New $namespace`.
///
/// Per the Phase 5 PLAN, the XLS seed is optional — %Dictionary is
/// the source of truth at build time. We use %Dictionary directly so
/// the catalog matches what's actually compiled on this instance,
/// not a static spreadsheet snapshot.
Class AgenticInterop.Catalog.Builder Extends %RegisteredObject
{

Parameter ENSKBNAME = "search_ens";

Parameter HSKBNAME = "search_hs";

Parameter ENSTABLE = "AgenticInterop_Catalog.EnsCatalog";

Parameter HSTABLE = "AgenticInterop_Catalog.HsCatalog";

/// Default location of the InterSystems-curated class catalog XLS.
/// Shipped under seeds/ in the repo and copied to /opt/agentic_interop/
/// seeds/ at install time. The XLS-source ingester (RebuildAllFromXLS)
/// reads this by default.
Parameter XLSPATH = "/opt/agentic_interop/seeds/catalog.xlsx";

/// Rebuild both catalogs from scratch. Returns a result object with
/// per-catalog row counts and timing. Long-running (~30s on a fresh
/// HSCUSTOM container with default IRIS for Health content).
ClassMethod RebuildAll(pSourceNamespace As %String = "USER", pCap As %Integer = 5000) As %DynamicObject
{
    Set out = {}
    Set start = $zhorolog
    Set out.startedAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
    Set out.sourceNamespace = pSourceNamespace
    Try {
        Set out.ens = ..RebuildEns(pSourceNamespace, pCap)
        Set out.hs = ..RebuildHs(pSourceNamespace, pCap)
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 800)
    }
    Set out.elapsedMs = $fnumber(($zhorolog - start) * 1000, "", 0)
    Quit out
}

/// Rebuild the search_ens catalog. Walks Ens.Host + Ens.InboundAdapter
/// + Ens.OutboundAdapter descendants from pSourceNamespace's
/// %Dictionary. Replaces the catalog table contents.
ClassMethod RebuildEns(pSourceNamespace As %String = "USER", pCap As %Integer = 5000) As %DynamicObject
{
    Set out = {}
    Set start = $zhorolog
    Set out.kb = ..#ENSKBNAME
    Set rows = ..ReadEnsRows(pSourceNamespace, pCap)
    Set out.scanned = rows.%Size()
    Set kb = ..%EnsureKB(..#ENSKBNAME, ..#ENSTABLE, "Vector search across Ens.Host, EnsLib.* business hosts, and Ens.InboundAdapter / Ens.OutboundAdapter classes available in the target namespace. Call this before recommending any IRIS interoperability class — returns the closest matches with class name, kind (Service/Process/Operation/Adapter), and the descriptive comment used to embed the row.")
    Set added = ..%Repopulate(kb, ..#ENSTABLE, rows)
    Set out.indexed = added
    Set out.elapsedMs = $fnumber(($zhorolog - start) * 1000, "", 0)
    Quit out
}

/// Rebuild the search_hs catalog. Walks HealthShare transformation
/// classes (HS.FHIR.DTL.*, HS.Gateway.*, HS.Util.HC.HL7.*).
ClassMethod RebuildHs(pSourceNamespace As %String = "USER", pCap As %Integer = 5000) As %DynamicObject
{
    Set out = {}
    Set start = $zhorolog
    Set out.kb = ..#HSKBNAME
    Set rows = ..ReadHsRows(pSourceNamespace, pCap)
    Set out.scanned = rows.%Size()
    Set kb = ..%EnsureKB(..#HSKBNAME, ..#HSTABLE, "Vector search across HealthShare HS.* transformation and gateway classes — DTLs, FHIR↔SDA3 mappers, HL7 v2 helpers. Call this before recommending an HS class for converting between HL7, FHIR, SDA3, or CDA.")
    Set added = ..%Repopulate(kb, ..#HSTABLE, rows)
    Set out.indexed = added
    Set out.elapsedMs = $fnumber(($zhorolog - start) * 1000, "", 0)
    Quit out
}

/// Rebuild both catalogs from the curated XLS shipped under
/// seeds/ (InterSystems_IRIS_Health_Complete_Class_Catalog.xlsx).
/// The XLS has 12 sheets covering Business Services, Processes,
/// Operations, Adapters, DTLs, BPL, Messages, REST/SOAP APIs, etc.,
/// each row carrying curated Purpose / When to Use / Key Settings
/// fields. We compose those fields into a single semantic text per
/// class and route by the Namespace column: HSLIB rows land in the
/// HS catalog, ENSLIB (and blank) in the ENS catalog. This produces
/// a much higher-signal embedding than %Dictionary.Description
/// alone, especially for "When to Use" queries the LLM cares about.
///
/// Returns: { ok, ens:{scanned,indexed,elapsedMs}, hs:{...},
/// elapsedMs, source: "xls", path }.
ClassMethod RebuildAllFromXLS(pPath As %String = "") As %DynamicObject
{
    Set out = {}
    Set start = $zhorolog
    Set out.startedAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
    Set out.source = "xls"
    Set path = $S(pPath="":..#XLSPATH, 1:pPath)
    Set out.path = path
    Try {
        Set raw = ..%ReadXLSRows(path)
        Set rowsByCatalog = ##class(%DynamicAbstractObject).%FromJSON(raw)
        Set ensRows = rowsByCatalog.%Get("ens")
        Set hsRows  = rowsByCatalog.%Get("hs")
        Set ensKb = ..%EnsureKB(..#ENSKBNAME, ..#ENSTABLE, "Vector search across InterSystems IRIS for Health business services, processes, operations, and adapters. Curated entries from the shipped Class Catalog (Purpose / When to Use / Key Settings per class). Call before recommending any IRIS interoperability class.")
        Set ensAdded = ..%Repopulate(ensKb, ..#ENSTABLE, ensRows)
        Set ensReport = {}
        Set ensReport.scanned = ensRows.%Size()
        Set ensReport.indexed = ensAdded
        Set out.ens = ensReport
        Set hsKb = ..%EnsureKB(..#HSKBNAME, ..#HSTABLE, "Vector search across HealthShare HS.* transformation, gateway, and clinical-data classes. Curated entries from the shipped Class Catalog. Call before recommending an HS class for HL7↔FHIR↔SDA3↔CDA conversions or HealthShare gateway routing.")
        Set hsAdded = ..%Repopulate(hsKb, ..#HSTABLE, hsRows)
        Set hsReport = {}
        Set hsReport.scanned = hsRows.%Size()
        Set hsReport.indexed = hsAdded
        Set out.hs = hsReport
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 800)
    }
    Set out.elapsedMs = $fnumber(($zhorolog - start) * 1000, "", 0)
    Quit out
}

/// Embedded Python: parse the XLS via openpyxl, walk every data
/// sheet, build rich semantic text per row, route by Namespace
/// column. Returns a %DynamicObject {"ens": [...], "hs": [...]}
/// where each entry is [text, metadata{className, kind, source,
/// package, sheet}].
ClassMethod %ReadXLSRows(path As %String) As %String [ Internal, Language = python ]
{
    # IRIS UDL parser is naive about braces inside Embedded Python
    # methods, so this body avoids dict literals and f-strings. We
    # use dict() and string concatenation. Caller deserializes the
    # returned JSON string.
    import openpyxl, json, os
    if not os.path.exists(path):
        raise RuntimeError("XLS not found at " + path + ". Ship seeds/catalog.xlsx and re-mount.")
    wb = openpyxl.load_workbook(path, data_only=True)
    ens = list()
    hs = list()
    HEADER_ROW = 3
    DATA_START = 4
    for sheet_name in wb.sheetnames:
        if sheet_name == 'Overview':
            continue
        ws = wb[sheet_name]
        col_idx = dict()
        for j, cell in enumerate(ws[HEADER_ROW]):
            v = cell.value
            if v:
                col_idx[str(v).strip()] = j
        def col(row, name):
            i = col_idx.get(name)
            if i is None or i >= len(row):
                return ''
            v = row[i]
            return str(v).strip() if v else ''
        for row in ws.iter_rows(min_row=DATA_START, values_only=True):
            class_name = col(row, 'Class Name')
            if not class_name:
                continue
            ns = col(row, 'Namespace')
            package = col(row, 'Package')
            ctype = col(row, 'Type')
            abstract = col(row, 'Abstract')
            purpose = col(row, 'Purpose')
            when_to_use = col(row, 'When to Use')
            key_settings = col(row, 'Key Settings')
            text_parts = list()
            text_parts.append(class_name + ' — ' + (ctype or 'class') + ' (' + sheet_name + ').')
            if purpose:
                text_parts.append('Purpose: ' + purpose)
            if when_to_use:
                text_parts.append('When to use: ' + when_to_use)
            if key_settings:
                text_parts.append('Key settings: ' + key_settings)
            text = ' '.join(text_parts)
            meta = dict()
            meta['className'] = class_name
            meta['kind'] = ctype or sheet_name
            meta['sheet'] = sheet_name
            meta['package'] = package
            meta['namespace'] = ns
            meta['abstract'] = abstract
            meta['source'] = class_name
            target = hs if ns.upper() == 'HSLIB' or class_name.startswith('HS.') else ens
            target.append([text, meta])
    out = dict()
    out['ens'] = ens
    out['hs'] = hs
    return json.dumps(out)
}

/// Snapshot per-catalog stats without rebuilding. Used by the admin
/// status endpoint.
ClassMethod Status() As %DynamicObject
{
    Set out = {}
    Set out.ens = ..%TableStats(..#ENSTABLE)
    Set out.hs  = ..%TableStats(..#HSTABLE)
    Quit out
}

/// Open or create the named KB. Reuses if a matching VectorStore
/// already exists; rebuilds the underlying table if the dimensions /
/// model don't match (catches an embedder change). Idempotent.
ClassMethod %EnsureKB(pName As %String, pTable As %String, pDescription As %String) As %AI.RAG.KnowledgeBase [ Internal ]
{
    Set emb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
    Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
    Set vs.TableName = pTable
    Set vs.Dimensions = emb.Dimensions
    Set vs.ModelName = emb.ModelName
    $$$ThrowOnError(vs.Build())
    Set kb = ##class(%AI.RAG.KnowledgeBase).%New(pName, pDescription)
    Set kb.TopK = 8
    $$$ThrowOnError(kb.Build(emb, vs))
    Quit kb
}

/// Walk the source namespace's compiled Ens host + adapter classes
/// and return [ [text, metadata{className, kind, source}], ... ].
/// Cap protects against pathological dictionaries.
ClassMethod ReadEnsRows(pSourceNamespace As %String, pCap As %Integer) As %DynamicArray [ Internal ]
{
    Set rows = []
    New $namespace
    Set $namespace = pSourceNamespace
    Set sql = "SELECT TOP ? Name, Description, PrimarySuper FROM %Dictionary.CompiledClass "
        _ "WHERE (PrimarySuper [ '~Ens.BusinessService~' OR PrimarySuper [ '~Ens.BusinessProcess~' "
        _ "  OR PrimarySuper [ '~Ens.BusinessOperation~' OR PrimarySuper [ '~Ens.InboundAdapter~' "
        _ "  OR PrimarySuper [ '~Ens.OutboundAdapter~') "
        _ "  AND Deprecated = 0 AND Abstract = 0 "
        _ "  AND (Name LIKE 'EnsLib.%' OR Name LIKE 'Ens.%') "
        _ "ORDER BY Name"
    Set rs = ##class(%SQL.Statement).%ExecDirect(,sql, pCap)
    While rs.%Next() {
        Set name = rs.%Get("Name")
        Set descr = rs.%Get("Description")
        Set ps = rs.%Get("PrimarySuper")
        Set kind = ..%KindFromSuper(ps)
        Set text = ..%FormatEntry(name, kind, descr)
        Set meta = {}
        Set meta.className = name
        Set meta.kind = kind
        Set meta.source = name
        Do rows.%Push([(text), (meta)])
    }
    Quit rows
}

ClassMethod ReadHsRows(pSourceNamespace As %String, pCap As %Integer) As %DynamicArray [ Internal ]
{
    Set rows = []
    New $namespace
    Set $namespace = pSourceNamespace
    Set sql = "SELECT TOP ? Name, Description FROM %Dictionary.CompiledClass "
        _ "WHERE (Name LIKE 'HS.FHIR.DTL.%' OR Name LIKE 'HS.Gateway.%' "
        _ "  OR Name LIKE 'HS.Util.HC.HL7.%' OR Name LIKE 'HS.SDA3.%' "
        _ "  OR Name LIKE 'HS.HC.HL7.%') "
        _ "  AND Deprecated = 0 AND Abstract = 0 "
        _ "  AND Description IS NOT NULL AND Description <> '' "
        _ "ORDER BY Name"
    Set rs = ##class(%SQL.Statement).%ExecDirect(,sql, pCap)
    While rs.%Next() {
        Set name = rs.%Get("Name")
        Set descr = rs.%Get("Description")
        Set kind = ..%HsKind(name)
        Set text = ..%FormatEntry(name, kind, descr)
        Set meta = {}
        Set meta.className = name
        Set meta.kind = kind
        Set meta.source = name
        Do rows.%Push([(text), (meta)])
    }
    Quit rows
}

/// Drop existing rows from the underlying table and re-add. Returns
/// the count of documents added. The %AI.RAG framework supports
/// chunk replacement via source key, but we want a clean slate per
/// rebuild (renamed classes, deleted classes).
ClassMethod %Repopulate(pKB As %AI.RAG.KnowledgeBase, pTable As %String, pRows As %DynamicArray) As %Integer [ Internal ]
{
    Try { Do $system.SQL.Execute("DELETE FROM " _ pTable) } Catch  {}
    Set added = pKB.AddDocuments(pRows)
    Quit added
}

ClassMethod %TableStats(pTable As %String) As %DynamicObject [ Internal ]
{
    Set out = {}
    Set out.table = pTable
    Set out.rows = 0
    Set out.exists = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM " _ pTable)
        If rs.%Next() {
            Set out.rows = rs.%Get("n")
            Set out.exists = 1
        }
    } Catch  {}
    Quit out
}

/// Curated semantic text — keeps doc text close to natural-language
/// content per the embedding-signal-vs-boilerplate memory note.
ClassMethod %FormatEntry(pName As %String, pKind As %String, pDescription As %String) As %String [ Internal ]
{
    Set descr = $zstrip(pDescription, "<>WC")
    If descr = "" { Set descr = "(no description)" }
    Quit pName _ " — " _ pKind _ ". " _ descr
}

ClassMethod %KindFromSuper(pSuper As %String) As %String [ Internal ]
{
    If pSuper [ "~Ens.BusinessService~" Quit "BusinessService"
    If pSuper [ "~Ens.BusinessProcess~" Quit "BusinessProcess"
    If pSuper [ "~Ens.BusinessOperation~" Quit "BusinessOperation"
    If pSuper [ "~Ens.InboundAdapter~" Quit "InboundAdapter"
    If pSuper [ "~Ens.OutboundAdapter~" Quit "OutboundAdapter"
    Quit "EnsHost"
}

ClassMethod %HsKind(pName As %String) As %String [ Internal ]
{
    If $extract(pName, 1, 12) = "HS.FHIR.DTL." Quit "FHIR-DTL"
    If $extract(pName, 1, 11) = "HS.Gateway." Quit "Gateway"
    If $extract(pName, 1, 16) = "HS.Util.HC.HL7." Quit "HL7-Util"
    If $extract(pName, 1, 8)  = "HS.SDA3." Quit "SDA3"
    If $extract(pName, 1, 10) = "HS.HC.HL7." Quit "HL7"
    Quit "HS"
}

}
