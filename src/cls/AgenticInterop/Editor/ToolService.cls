/// CRUD for individual Tool entries inside a ToolSet's XData Definition.
/// A "tool" is one element of the JSON array `tools`. The service reads
/// the XData body, mutates the matching entry, writes back, and recompiles.
///
/// Only ToolSets under AgenticInterop.User.ToolSet.* accept Save/Create/
/// Delete. Tools inside shipped ToolSets are read-only by design.
Class AgenticInterop.Editor.ToolService Extends %RegisteredObject
{

ClassMethod IsUserAuthored(pClass As %String) As %Boolean [ CodeMode = expression ]
{
##class(AgenticInterop.Editor.Util).IsUserAuthored(pClass, "ToolSet")
}

/// Read the ToolSet's Definition XData as a %DynamicObject. Returns ""
/// if the ToolSet doesn't exist or the body is unparseable.
ClassMethod LoadDefinition(pToolSet As %String) As %DynamicObject [ Internal ]
{
    Set util = "AgenticInterop.Editor.Util"
    Set raw = $classmethod(util, "XDataBody", pToolSet, "ToolManifest")
    Set result = ""
    If raw = "" { Quit result }
    Try {
        Set obj = ##class(%DynamicAbstractObject).%FromJSON(raw)
        If '$isobject(obj.tools) {
            Set obj.tools = []
        }
        Set result = obj
    } Catch {
        Set result = ""
    }
    Quit result
}

/// Write a Definition object back to the ToolSet's XData. Recompiles.
ClassMethod SaveDefinition(pToolSet As %String, pDef As %DynamicObject) As %Status [ Internal ]
{
    Set util = "AgenticInterop.Editor.Util"
    Set raw = pDef.%ToJSON()
    Set tSC = $classmethod(util, "SetXData", pToolSet, "ToolManifest", raw, "application/json")
    If 'tSC { Quit tSC }
    Quit $classmethod(util, "Recompile", pToolSet)
}

/// GET /api/agentic/editor/tool/:toolset/:name
ClassMethod Get(pResponse As %CSP.Response, pToolSet As %String, pName As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pToolSet) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "ToolSet does not exist", pToolSet)
    }
    Set def = ..LoadDefinition(pToolSet)
    If '$isobject(def) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Definition XData unparseable", pToolSet)
    }
    Set match = ""
    Set iter = def.tools.%GetIterator()
    While iter.%GetNext(.k, .t) {
        If $isobject(t), t.name = pName {
            Set match = t
            Quit
        }
    }
    If '$isobject(match) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Tool not found in ToolSet", pName)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, match)
}

/// PUT /api/agentic/editor/tool/:toolset/:name
/// Body: full tool object — name, description, inputSchema, implementation,
///       timeoutMs, requiresConfirmation. Replaces the existing entry.
ClassMethod Save(pResponse As %CSP.Response, pToolSet As %String, pName As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '..IsUserAuthored(pToolSet) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored ToolSets accept tool edits", pToolSet)
    }
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    Set def = ..LoadDefinition(pToolSet)
    If '$isobject(def) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Definition XData unparseable")
    }
    // Replace the matching tool entry in place.
    Set replaced = 0
    Set iter = def.tools.%GetIterator()
    While iter.%GetNext(.k, .t) {
        If $isobject(t), t.name = pName {
            Do def.tools.%Set(k, req)
            Set replaced = 1
            Quit
        }
    }
    If 'replaced {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Tool not found in ToolSet", pName)
    }
    Set tSC = ..SaveDefinition(pToolSet, def)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Save failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, pToolSet, $S(req.%IsDefined("name"):req.name, 1:pName))
}

/// POST /api/agentic/editor/tool/:toolset
/// Body: full tool object including name (must be unique within ToolSet).
ClassMethod Create(pResponse As %CSP.Response, pToolSet As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '..IsUserAuthored(pToolSet) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored ToolSets accept tool creation", pToolSet)
    }
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    Set name = $classmethod(util, "DObj", req, "name")
    If name = "" {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Missing 'name' on tool body")
    }
    Set def = ..LoadDefinition(pToolSet)
    If '$isobject(def) {
        // Initialize an empty definition if missing
        Set def = {"tools": []}
    }
    Set conflict = 0
    Set iter = def.tools.%GetIterator()
    While iter.%GetNext(.k, .t) {
        If $isobject(t), t.name = name {
            Set conflict = 1
            Quit
        }
    }
    If conflict {
        Quit $classmethod(util, "WriteError", pResponse, "409 Conflict", "Tool with this name already exists", name)
    }
    Do def.tools.%Push(req)
    Set tSC = ..SaveDefinition(pToolSet, def)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Save failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, pToolSet, name)
}

/// DELETE /api/agentic/editor/tool/:toolset/:name
ClassMethod Delete(pResponse As %CSP.Response, pToolSet As %String, pName As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '..IsUserAuthored(pToolSet) {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored ToolSets accept tool deletion", pToolSet)
    }
    Set def = ..LoadDefinition(pToolSet)
    If '$isobject(def) {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Definition XData unparseable")
    }
    Set newTools = []
    Set removed = 0
    Set iter = def.tools.%GetIterator()
    While iter.%GetNext(.k, .t) {
        If $isobject(t), t.name = pName {
            Set removed = 1
            Continue
        }
        Do newTools.%Push(t)
    }
    If 'removed {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Tool not found in ToolSet", pName)
    }
    Set def.tools = newTools
    Set tSC = ..SaveDefinition(pToolSet, def)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Delete failed", $system.Status.GetErrorText(tSC))
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"ok": 1, "deleted": (pName), "toolset": (pToolSet)})
}

}
