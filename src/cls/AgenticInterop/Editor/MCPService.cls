/// CRUD for MCP classes (subclasses of AgenticInterop.MCP.Base).
/// User-authored MCPs live under AgenticInterop.User.MCP.*; shipped MCPs
/// under AgenticInterop.MCP.* can be EDITED (Save) — the user can re-bind
/// toolsets, rename, edit descriptions — but NOT deleted (Delete still
/// requires User.MCP.*). Note: edits to shipped classes write to the
/// .cls dictionary directly and will be overwritten by a subsequent
/// `zpm load` of the shipped module. If preservation across upgrades is
/// required, copy the class under AgenticInterop.User.MCP.* first.
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
    // Overlay-aware read: GetEffectiveMCP layers any user override
    // on top of the shipped .cls metadata, so the UI sees what the
    // chat runtime will see at request time.
    Set body = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMCP(pClass)
    Set body.userAuthored = ..IsUserAuthored(pClass)
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// PUT /api/agentic/editor/mcp/:class
/// Body: { name, shortDescription, description, toolsets:[] }
///
/// Save routing:
///   - User-authored classes (AgenticInterop.User.MCP.*) write to
///     the .cls dictionary as before — those classes are operator-
///     owned and zpm doesn't touch them.
///   - Shipped classes (AgenticInterop.MCP.*) write to the
///     AgenticInterop.Data.MCPOverride table. The overlay layer
///     surfaces the edit transparently to the UI and the chat
///     runtime, and a subsequent `zpm load` of the upstream module
///     leaves the override row untouched, so customizations
///     survive upgrade.
ClassMethod Save(pResponse As %CSP.Response, pClass As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "MCP class does not exist", pClass)
    }
    If ..IsUserAuthored(pClass) {
        Set tSC = ..ApplyEdits(pClass, req)
    } Else {
        Set tSC = ##class(AgenticInterop.Editor.Overlay).SaveMCPOverride(pClass, req, $username)
    }
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Save failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, pClass)
}

/// POST /api/agentic/editor/mcp/:class/reset — drops the override
/// row for a shipped MCP, restoring it to the shipping defaults.
/// 404s on user-authored classes (those don't have overrides).
ClassMethod Reset(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "MCP class does not exist", pClass)
    }
    If ..IsUserAuthored(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "User-authored MCPs do not use overrides — edits already write to .cls.", pClass)
    }
    Set tSC = ##class(AgenticInterop.Editor.Overlay).ResetMCP(pClass)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Reset failed", $system.Status.GetErrorText(tSC))
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
