/// Shared helpers for the Editor.* REST services. Centralized so that
/// JSON-response shape, error formatting, and the CSV/list utilities used
/// by Agent/MCP/ToolSet/Tool stay consistent.
Class AgenticInterop.Editor.Util Extends %RegisteredObject
{

/// Write a %DynamicObject as the JSON body of pResponse and set 200.
/// Used by every Get/Save/Create handler that returns JSON.
ClassMethod WriteJSON(pResponse As %CSP.Response, pObj As %DynamicObject, pStatus As %String = "200 OK")
{
    Set pResponse.Status = pStatus
    Set pResponse.ContentType = "application/json"
    Do pObj.%ToJSON()
    Quit $$$OK
}

/// Write a {error, ...} body and set the matching HTTP status.
ClassMethod WriteError(pResponse As %CSP.Response, pStatus As %String, pMessage As %String, pDetail As %String = "")
{
    Set body = {"error": (pMessage)}
    If pDetail '= "" { Set body.detail = pDetail }
    Quit ..WriteJSON(pResponse, body, pStatus)
}

/// Read a request body stream and parse as JSON. Returns "" on error.
ClassMethod ParseBody(pStream) As %DynamicObject
{
    Set result = ""
    Try {
        If $isobject(pStream), pStream.%IsA("%Stream.Object") {
            Do pStream.Rewind()
            Set txt = ""
            While 'pStream.AtEnd { Set txt = txt _ pStream.Read(8192) }
        } Else {
            Set txt = pStream
        }
        If txt '= "" {
            Set result = ##class(%DynamicAbstractObject).%FromJSON(txt)
        }
    } Catch {
        Set result = ""
    }
    Quit result
}

/// CSV → %DynamicArray, trimming whitespace and dropping empties.
ClassMethod CsvToArray(pCsv As %String) As %DynamicArray
{
    Set arr = []
    If pCsv = "" { Quit arr }
    For i=1:1:$LENGTH(pCsv, ",") {
        Set v = $ZSTRIP($PIECE(pCsv, ",", i), "<>W")
        If v '= "" { Do arr.%Push(v) }
    }
    Quit arr
}

/// %DynamicArray → CSV. Inverse of CsvToArray.
ClassMethod ArrayToCsv(pArr As %DynamicArray) As %String
{
    Set csv = ""
    If '$isobject(pArr) { Quit csv }
    Set iter = pArr.%GetIterator()
    While iter.%GetNext(.k, .v) {
        Set v = $ZSTRIP(v, "<>W")
        If v = "" { Continue }
        Set csv = csv _ $S(csv="":"", 1:",") _ v
    }
    Quit csv
}

/// Read a Parameter's compiled Default via SQL (avoids the OREF cache
/// staleness issue with %Dictionary.CompiledParameter.%OpenId after a save
/// in the same process — see docs/PLAN.md "Data model — class as data").
///
/// SQL gotcha: the column name on disk is `Default` which collides with
/// the SQL reserved word, so IRIS maps it to `_Default` for queries.
/// Likewise `parent` is the parent-class column.
ClassMethod ParamDefault(pClass As %String, pName As %String) As %String
{
    Set sql = "SELECT _Default AS DefaultValue FROM %Dictionary.CompiledParameter WHERE parent = ? AND Name = ?"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pClass, pName)
    If rs.%Next() { Quit rs.%Get("DefaultValue") }
    Quit ""
}

/// Read a class's compiled Description via SQL.
ClassMethod ClassDescription(pClass As %String) As %String
{
    Set sql = "SELECT Description FROM %Dictionary.CompiledClass WHERE Name = ?"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pClass)
    If rs.%Next() { Quit rs.%Get("Description") }
    Quit ""
}

/// Read an XData block's body as a single string.
ClassMethod XDataBody(pClass As %String, pXData As %String) As %String
{
    Set body = ""
    Set xd = ##class(%Dictionary.CompiledXData).%OpenId(pClass _ "||" _ pXData)
    If '$isobject(xd) { Quit body }
    Do xd.Data.Rewind()
    While 'xd.Data.AtEnd { Set body = body _ xd.Data.Read(8192) }
    Quit body
}

/// True iff a class extends pBase (directly or transitively).
ClassMethod ExtendsClass(pClass As %String, pBase As %String) As %Boolean
{
    If pClass = "" { Quit 0 }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) { Quit 0 }
    Set sql = "SELECT 1 FROM %Dictionary.CompiledClass WHERE Name = ? AND PrimarySuper [ ?"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pClass, "~"_pBase_"~")
    If rs.%Next() { Quit 1 }
    Quit 0
}

/// Set or replace a Parameter's Default value on a class. Creates the
/// Parameter definition if it doesn't exist. Caller must recompile after.
///
/// Uses the parent-relationship pattern: open the ClassDefinition,
/// search its Parameters collection, mutate-or-insert, save the parent.
/// Direct `pdef.parent = pClass` assignment is rejected by the IRIS
/// dictionary metaclass.
ClassMethod SetParameter(pClass As %String, pName As %String, pValue As %String, pDescription As %String = "") As %Status
{
    Set cdef = ##class(%Dictionary.ClassDefinition).%OpenId(pClass)
    If '$isobject(cdef) { Quit $$$ERROR($$$GeneralError, "ClassDefinition not found: " _ pClass) }

    Set existing = ""
    For i=1:1:cdef.Parameters.Count() {
        Set p = cdef.Parameters.GetAt(i)
        If $isobject(p), p.Name = pName { Set existing = p Quit }
    }
    If $isobject(existing) {
        Set existing.Default = pValue
        If pDescription '= "" { Set existing.Description = pDescription }
    } Else {
        Set pdef = ##class(%Dictionary.ParameterDefinition).%New()
        Set pdef.Name = pName
        Set pdef.Default = pValue
        If pDescription '= "" { Set pdef.Description = pDescription }
        Do cdef.Parameters.Insert(pdef)
    }
    Quit cdef.%Save()
}

/// Replace the body of an XData block. Creates the XData if missing.
/// Same parent-collection pattern as SetParameter.
ClassMethod SetXData(pClass As %String, pName As %String, pBody As %String, pMimeType As %String = "application/json") As %Status
{
    Set cdef = ##class(%Dictionary.ClassDefinition).%OpenId(pClass)
    If '$isobject(cdef) { Quit $$$ERROR($$$GeneralError, "ClassDefinition not found: " _ pClass) }

    Set existing = ""
    For i=1:1:cdef.XDatas.Count() {
        Set x = cdef.XDatas.GetAt(i)
        If $isobject(x), x.Name = pName { Set existing = x Quit }
    }
    If $isobject(existing) {
        Set existing.MimeType = pMimeType
        Do existing.Data.Clear()
        Do existing.Data.Write(pBody)
    } Else {
        Set xdef = ##class(%Dictionary.XDataDefinition).%New()
        Set xdef.Name = pName
        Set xdef.MimeType = pMimeType
        Do xdef.Data.Write(pBody)
        Do cdef.XDatas.Insert(xdef)
    }
    Quit cdef.%Save()
}

/// Recompile a class with quiet flags. Returns %Status.
ClassMethod Recompile(pClass As %String) As %Status
{
    Quit $system.OBJ.Compile(pClass, "ck-d")
}

/// True iff pClass starts with pPrefix. Avoids $extract length math
/// (the editor service IsUserAuthored guards used to be buggy because
/// of off-by-N $extract counts).
ClassMethod StartsWith(pClass As %String, pPrefix As %String) As %Boolean [ CodeMode = expression ]
{
$extract(pClass, 1, $length(pPrefix)) = pPrefix
}

/// True iff pClass lives under AgenticInterop.User.<entity>.* —
/// shorthand for the per-entity guards used by AgentService/MCPService/
/// ToolSetService.
ClassMethod IsUserAuthored(pClass As %String, pEntity As %String) As %Boolean [ CodeMode = expression ]
{
..StartsWith(pClass, "AgenticInterop.User."_pEntity_".")
}

/// Read a field on a %DynamicObject without the $get gotcha:
/// `$get(obj.field)` throws <INVALID CLASS> on this IRIS build, so
/// this helper does the safe %IsDefined dance.
ClassMethod DObj(pObj As %DynamicObject, pField As %String, pDefault As %String = "") As %String
{
    If '$isobject(pObj) { Quit pDefault }
    If 'pObj.%IsDefined(pField) { Quit pDefault }
    Quit pObj.%Get(pField)
}

}
