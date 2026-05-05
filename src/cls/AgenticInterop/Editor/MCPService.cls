/// CRUD for MCP classes (subclasses of AgenticInterop.MCP.Base).
/// User-authored MCPs live under AgenticInterop.User.MCP.*; shipped MCPs
/// under AgenticInterop.MCP.* are read-only (Get works, Save and Delete
/// reject with 403).
Class AgenticInterop.Editor.MCPService Extends %RegisteredObject
{

ClassMethod IsUserAuthored(pClass As %String) As %Boolean [ CodeMode = expression ]
{
##class(AgenticInterop.Editor.Util).IsUserAuthored(pClass, "MCP")
}

/// GET /api/agentic/editor/mcp/:class
ClassMethod Get(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "MCP class does not exist", pClass)
    }
    If '$classmethod(util, "ExtendsClass", pClass, "AgenticInterop.MCP.Base") {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Class is not an MCP", pClass)
    }
    Set body = {
        "class":             (pClass),
        "userAuthored":      (..IsUserAuthored(pClass)),
        "description":       ($classmethod(util, "ClassDescription", pClass)),
        "name":              ($classmethod(util, "ParamDefault", pClass, "NAME")),
        "shortDescription":  ($classmethod(util, "ParamDefault", pClass, "DESCRIPTION")),
        "toolsetsCsv":       ($classmethod(util, "ParamDefault", pClass, "TOOLSETS"))
    }
    Set body.toolsets = $classmethod(util, "CsvToArray", body.toolsetsCsv)
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// PUT /api/agentic/editor/mcp/:class
/// Body: { name, shortDescription, description, toolsets:[] }
ClassMethod Save(pResponse As %CSP.Response, pClass As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '..IsUserAuthored(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored MCPs can be edited", pClass)
    }
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "MCP class does not exist", pClass)
    }
    Set tSC = ..ApplyEdits(pClass, req)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Save failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, pClass)
}

/// POST /api/agentic/editor/mcp
/// Body: { class, name, shortDescription, description, toolsets:[] }
ClassMethod Create(pResponse As %CSP.Response, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    Set cls = $classmethod(util, "DObj", req, "class")
    If cls = "" {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Missing 'class' in body")
    }
    If '..IsUserAuthored(cls) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "User-authored MCPs must live under AgenticInterop.User.MCP.*", cls)
    }
    If ##class(%Dictionary.CompiledClass).%ExistsId(cls) {
        Quit $classmethod(util, "WriteError", pResponse, "409 Conflict", "MCP class already exists", cls)
    }
    Set cdef = ##class(%Dictionary.ClassDefinition).%New(cls)
    Set cdef.Super = "AgenticInterop.MCP.Base"
    Set descVal = $classmethod(util, "DObj", req, "description")
    If descVal '= "" { Set cdef.Description = descVal }
    Set tSC = cdef.%Save()
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Class create failed", $system.Status.GetErrorText(tSC))
    }
    Set tSC = ..ApplyEdits(cls, req)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Apply-edits failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, cls)
}

/// DELETE /api/agentic/editor/mcp/:class
ClassMethod Delete(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '..IsUserAuthored(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored MCPs can be deleted", pClass)
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "MCP class does not exist", pClass)
    }
    Set tSC = $system.OBJ.Delete(pClass, "d")
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Delete failed", $system.Status.GetErrorText(tSC))
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"ok": 1, "deleted": (pClass)})
}

ClassMethod ApplyEdits(pClass As %String, pReq As %DynamicObject) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set tSC = $$$OK

    If pReq.%IsDefined("description") {
        Set cdef = ##class(%Dictionary.ClassDefinition).%OpenId(pClass)
        If $isobject(cdef) {
            Set cdef.Description = pReq.description
            Set tSC = cdef.%Save()
            If 'tSC { Quit tSC }
        }
    }
    If pReq.%IsDefined("name") {
        Set tSC = $classmethod(util, "SetParameter", pClass, "NAME", pReq.name)
        If 'tSC { Quit tSC }
    }
    If pReq.%IsDefined("shortDescription") {
        Set tSC = $classmethod(util, "SetParameter", pClass, "DESCRIPTION", pReq.shortDescription)
        If 'tSC { Quit tSC }
    }
    If pReq.%IsDefined("toolsets") {
        Set csv = $S($isobject(pReq.toolsets):$classmethod(util,"ArrayToCsv",pReq.toolsets), 1:pReq.toolsets)
        Set tSC = $classmethod(util, "SetParameter", pClass, "TOOLSETS", csv)
        If 'tSC { Quit tSC }
    } ElseIf pReq.%IsDefined("toolsetsCsv") {
        Set tSC = $classmethod(util, "SetParameter", pClass, "TOOLSETS", pReq.toolsetsCsv)
        If 'tSC { Quit tSC }
    }

    Quit $classmethod(util, "Recompile", pClass)
}

}
