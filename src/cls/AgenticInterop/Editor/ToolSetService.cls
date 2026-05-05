/// CRUD for ToolSet classes (subclasses of %AI.ToolSet under
/// AgenticInterop.*). Tool entries inside the XData Definition are
/// managed by AgenticInterop.Editor.ToolService, not here — this service
/// covers ToolSet-level fields (name, description) and lists the tools.
Class AgenticInterop.Editor.ToolSetService Extends %RegisteredObject
{

ClassMethod IsUserAuthored(pClass As %String) As %Boolean [ CodeMode = expression ]
{
##class(AgenticInterop.Editor.Util).IsUserAuthored(pClass, "ToolSet")
}

/// GET /api/agentic/editor/toolset/:class
ClassMethod Get(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "ToolSet class does not exist", pClass)
    }
    If '$classmethod(util, "ExtendsClass", pClass, "%AI.ToolSet") {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Class is not a %AI.ToolSet subclass", pClass)
    }
    Set body = {
        "class":         (pClass),
        "userAuthored":  (..IsUserAuthored(pClass)),
        "description":   ($classmethod(util, "ClassDescription", pClass)),
        "name":          ($classmethod(util, "ParamDefault", pClass, "NAME"))
    }
    // Definition XData = XML (framework-managed). Returned as raw text
    // for power users; not parsed here.
    Set body.definitionRaw = $classmethod(util, "XDataBody", pClass, "Definition")
    // ToolManifest XData = JSON (editor-managed). This is where the UI's
    // tool list lives.
    Set rawManifest = $classmethod(util, "XDataBody", pClass, "ToolManifest")
    Set tools = []
    If rawManifest '= "" {
        Try {
            Set obj = ##class(%DynamicAbstractObject).%FromJSON(rawManifest)
            If $isobject(obj), $isobject(obj.tools) {
                Set tools = obj.tools
            }
        } Catch ex {
            Set body.manifestParseError = ex.DisplayString()
        }
    }
    Set body.tools = tools
    Set body.toolCount = $S($isobject(tools):tools.%Size(), 1:0)
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// PUT /api/agentic/editor/toolset/:class
/// Body: { name, description, definitionRaw }
/// Tools are typically edited via the Tool service, but this endpoint
/// accepts a full definitionRaw replacement for power users.
ClassMethod Save(pResponse As %CSP.Response, pClass As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '..IsUserAuthored(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored ToolSets can be edited", pClass)
    }
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "ToolSet class does not exist", pClass)
    }
    Set tSC = ..ApplyEdits(pClass, req)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Save failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, pClass)
}

/// POST /api/agentic/editor/toolset
/// Body: { class, name, description }
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
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "User-authored ToolSets must live under AgenticInterop.User.ToolSet.*", cls)
    }
    If ##class(%Dictionary.CompiledClass).%ExistsId(cls) {
        Quit $classmethod(util, "WriteError", pResponse, "409 Conflict", "ToolSet class already exists", cls)
    }
    Set cdef = ##class(%Dictionary.ClassDefinition).%New(cls)
    Set cdef.Super = "%AI.ToolSet"
    Set descVal = $classmethod(util, "DObj", req, "description")
    If descVal '= "" { Set cdef.Description = descVal }
    Set tSC = cdef.%Save()
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Class create failed", $system.Status.GetErrorText(tSC))
    }
    // Seed framework-required Definition XData (XML) — empty ToolSet
    // element. The framework's compile-time generator parses this; if
    // we leave invalid content here the class won't compile.
    Set shortName = $piece(cls, ".", $length(cls, "."))
    Set descAttr = $S(descVal'="":descVal, 1:shortName_" toolset")
    Set xmlBody = "<ToolSet Name="""_shortName_""" Description="""_$replace(descAttr,"""","&quot;")_"""></ToolSet>"
    Set tSC = $classmethod(util, "SetXData", cls, "Definition", xmlBody, "application/xml")
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Definition XData seed failed", $system.Status.GetErrorText(tSC))
    }
    // Seed editor-only ToolManifest XData (JSON). The framework ignores
    // this XData; the editor uses it to store tool entries the UI manages.
    // Phase 4 translates ToolManifest into the framework-readable
    // Definition (XML) plus generated class methods / Rust refs.
    Set tSC = $classmethod(util, "SetXData", cls, "ToolManifest", "{""tools"": []}", "application/json")
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "ToolManifest seed failed", $system.Status.GetErrorText(tSC))
    }
    Set tSC = ..ApplyEdits(cls, req)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Apply-edits failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, cls)
}

/// DELETE /api/agentic/editor/toolset/:class
ClassMethod Delete(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '..IsUserAuthored(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored ToolSets can be deleted", pClass)
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "ToolSet class does not exist", pClass)
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
    If pReq.%IsDefined("definitionRaw") {
        Set tSC = $classmethod(util, "SetXData", pClass, "Definition", pReq.definitionRaw, "application/json")
        If 'tSC { Quit tSC }
    }
    Quit $classmethod(util, "Recompile", pClass)
}

}
