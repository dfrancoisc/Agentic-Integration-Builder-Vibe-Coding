/// Loader for the IRIS reference data tables. Reads the JSON files
/// produced by src/seed/parse_reference_pdfs.py and bulk-populates the
/// three Reference.* persistent classes (GlossaryTerm, ErrorCode,
/// ApiTopic).
///
/// Drop the JSON files into /opt/agentic-seed/reference/ inside the
/// container (the deploy step copies them there) and call:
///   do ##class(AgenticInterop.Reference.Loader).ReloadAll()
///
/// The lookup tools (lookup_glossary_term, lookup_error_code,
/// search_api_index) query the resulting tables directly.
Class AgenticInterop.Reference.Loader Extends %RegisteredObject
{

Parameter SEEDDIR = "/tmp/agentic-seed/reference/";

/// Reload all three reference tables from their JSON seed files. Each
/// reload is wrapped in a transaction; on error the table is left in
/// its prior state. Returns a per-table summary.
ClassMethod ReloadAll(pSeedDir As %String = "") As %DynamicObject
{
    Set out = {}
    Set out.tables = []
    Set dir = $select(pSeedDir'="":pSeedDir, 1:..#SEEDDIR)
    If $extract(dir, *) '= "/" { Set dir = dir _ "/" }
    Set out.seedDir = dir
    Set total = 0
    Set tables = $listbuild(
        $listbuild("glossary",  "GlossaryTerm",  dir _ "glossary.json"),
        $listbuild("errors",    "ErrorCode",     dir _ "error_codes.json"),
        $listbuild("apiTopics", "ApiTopic",      dir _ "api_topics.json"))
    For i=1:1:$listlength(tables) {
        Set spec = $list(tables, i)
        Set name = $list(spec, 1)
        Set cls  = "AgenticInterop.Reference." _ $list(spec, 2)
        Set path = $list(spec, 3)
        Set summary = ..%LoadOne(name, cls, path)
        Do out.tables.%Push(summary)
        If summary.loaded { Set total = total + summary.loaded }
    }
    Set out.totalLoaded = total
    Set out.ok = 1
    Quit out
}

/// Reload a single reference table from its JSON file. Internal —
/// ReloadAll calls this for each kind.
ClassMethod %LoadOne(pName As %String, pClass As %String, pPath As %String) As %DynamicObject [ Internal ]
{
    Set summary = {}
    Set summary.name = pName
    Set summary.class = pClass
    Set summary.path = pPath
    Try {
        // Read file via stream (works regardless of file size).
        If '##class(%File).Exists(pPath) {
            Set summary.ok = 0
            Set summary.error = "Seed file not found: " _ pPath
            Quit
        }
        Set stream = ##class(%Stream.FileCharacter).%New()
        Set stream.Filename = pPath
        Set stream.TranslateTable = "UTF8"
        Set raw = ""
        While 'stream.AtEnd { Set raw = raw _ stream.Read(65536) }
        Set arr = ##class(%DynamicAbstractObject).%FromJSON(raw)
        If '$isobject(arr) {
            Set summary.ok = 0
            Set summary.error = "Seed file did not parse as JSON: " _ pPath
            Quit
        }
        // Wipe existing rows so a re-run is idempotent.
        Set sc = $classmethod(pClass, "%KillExtent")
        If $$$ISERR(sc) {
            Set summary.ok = 0
            Set summary.error = "%KillExtent failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set count = 0
        Set iter = arr.%GetIterator()
        TSTART
        While iter.%GetNext(.idx, .row) {
            Set obj = $classmethod(pClass, "%New")
            Do ..%PopulateRow(pClass, obj, row)
            Set sc = obj.%Save()
            If $$$ISERR(sc) {
                TROLLBACK
                Set summary.ok = 0
                Set summary.error = "Save failed at row " _ idx _ ": " _ $system.Status.GetErrorText(sc)
                Quit
            }
            Set count = count + 1
        }
        If 'summary.%IsDefined("ok") {
            TCOMMIT
            Set summary.ok = 1
            Set summary.loaded = count
        }
    } Catch ex {
        Try { TROLLBACK } Catch  {}
        Set summary.ok = 0
        Set summary.error = $extract(ex.DisplayString(), 1, 600)
    }
    Quit summary
}

/// Populate a fresh persistent object from a JSON row. Knows the three
/// table shapes by class name. Internal helper.
ClassMethod %PopulateRow(pClass As %String, pObj As %RegisteredObject, pRow As %DynamicObject) [ Internal ]
{
    If pClass = "AgenticInterop.Reference.GlossaryTerm" {
        Set pObj.Term       = $select(pRow.%IsDefined("term"):pRow.term, 1:"")
        Set pObj.TermKey    = $select(pRow.%IsDefined("termKey"):pRow.termKey, 1:"")
        Set pObj.Category   = $select(pRow.%IsDefined("category"):pRow.category, 1:"")
        Set pObj.Definition = $select(pRow.%IsDefined("definition"):pRow.definition, 1:"")
    } ElseIf pClass = "AgenticInterop.Reference.ErrorCode" {
        Set pObj.Code     = $select(pRow.%IsDefined("code"):+pRow.code, 1:0)
        Set pObj.Message  = $select(pRow.%IsDefined("message"):pRow.message, 1:"")
        Set pObj.Category = $select(pRow.%IsDefined("category"):pRow.category, 1:"")
    } ElseIf pClass = "AgenticInterop.Reference.ApiTopic" {
        Set pObj.Slug       = $select(pRow.%IsDefined("slug"):pRow.slug, 1:"")
        Set pObj.Title      = $select(pRow.%IsDefined("title"):pRow.title, 1:"")
        Set pObj.Summary    = $select(pRow.%IsDefined("summary"):pRow.summary, 1:"")
        Set pObj.Body       = $select(pRow.%IsDefined("body"):pRow.body, 1:"")
        Set pObj.Namespaces = $select(pRow.%IsDefined("namespaces"):pRow.namespaces, 1:"")
    }
    Quit
}

/// Counts in each table — admin diagnostic. Returns
/// { glossary, errors, apiTopics, ok }.
ClassMethod Status() As %DynamicObject
{
    Set out = {}
    Set out.glossary  = ..%CountTable("AgenticInterop.Reference.GlossaryTerm")
    Set out.errors    = ..%CountTable("AgenticInterop.Reference.ErrorCode")
    Set out.apiTopics = ..%CountTable("AgenticInterop.Reference.ApiTopic")
    Set out.ok = 1
    Quit out
}

ClassMethod %CountTable(pClass As %String) As %Integer [ Internal ]
{
    Set count = 0
    Try {
        Set sql = "SELECT COUNT(*) AS C FROM " _ $translate(pClass, ".", "_")
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        If rs.%Next() { Set count = +rs.%Get("C") }
    } Catch  { Set count = 0 }
    Quit count
}

}
