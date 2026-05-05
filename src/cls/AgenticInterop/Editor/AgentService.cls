/// CRUD for Agent classes (subclasses of %AI.Agent under AgenticInterop.*).
/// Reads via SQL on %Dictionary.Compiled*, writes via %Dictionary.*Definition.
/// All UI field bindings (per docs/PLAN.md "Admin UI — per-entity field
/// specs" / Agent) round-trip through this service.
Class AgenticInterop.Editor.AgentService Extends %RegisteredObject
{

/// GET /api/agentic/editor/agent/:class
ClassMethod Get(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Agent class does not exist", pClass)
    }
    If '$classmethod(util, "ExtendsClass", pClass, "%AI.Agent") {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Class is not an %AI.Agent subclass", pClass)
    }
    Set body = {
        "class":         (pClass),
        "description":   ($classmethod(util, "ClassDescription", pClass)),
        "name":          ($classmethod(util, "ParamDefault", pClass, "NAME")),
        "temperature":   ($classmethod(util, "ParamDefault", pClass, "TEMPERATURE")),
        "maxIterations": ($classmethod(util, "ParamDefault", pClass, "MAXITERATIONS")),
        "provider":      ($classmethod(util, "ParamDefault", pClass, "PROVIDER")),
        "instructions":  ($classmethod(util, "XDataBody", pClass, "INSTRUCTIONS")),
        "mcpsCsv":       ($classmethod(util, "ParamDefault", pClass, "MCPS")),
        "skillsCsv":     ($classmethod(util, "ParamDefault", pClass, "SKILLS"))
    }
    Set body.mcps   = $classmethod(util, "CsvToArray", body.mcpsCsv)
    Set body.skills = $classmethod(util, "CsvToArray", body.skillsCsv)
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// PUT /api/agentic/editor/agent/:class
/// Body: { name, description, temperature, maxIterations, provider,
///         instructions, mcps:[], skills:[] }
ClassMethod Save(pResponse As %CSP.Response, pClass As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Agent class does not exist", pClass)
    }
    Set tSC = ..ApplyEdits(pClass, req)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Save failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, pClass)
}

/// POST /api/agentic/editor/agent
/// Body: { class, super (optional, defaults to %AI.Agent), ... }
/// User-authored agents must live under AgenticInterop.User.Agent.*.
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
    If '$classmethod(util, "IsUserAuthored", cls, "Agent") {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "User-authored agents must live under AgenticInterop.User.Agent.*", cls)
    }
    If ##class(%Dictionary.CompiledClass).%ExistsId(cls) {
        Quit $classmethod(util, "WriteError", pResponse, "409 Conflict", "Agent class already exists", cls)
    }
    Set super = $classmethod(util, "DObj", req, "super", "%AI.Agent")
    Set cdef = ##class(%Dictionary.ClassDefinition).%New(cls)
    Set cdef.Super = super
    Set descVal = $classmethod(util, "DObj", req, "description")
    If descVal '= "" { Set cdef.Description = descVal }
    Set tSC = cdef.%Save()
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Class create failed", $system.Status.GetErrorText(tSC))
    }
    // Apply remaining fields (params, instructions XData)
    Set tSC = ..ApplyEdits(cls, req)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Apply-edits failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, cls)
}

/// DELETE /api/agentic/editor/agent/:class
ClassMethod Delete(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '$classmethod(util, "IsUserAuthored", pClass, "Agent") {
        Quit $classmethod(util, "WriteError", pResponse, "403 Forbidden", "Only user-authored agents can be deleted", pClass)
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Agent class does not exist", pClass)
    }
    Set tSC = $system.OBJ.Delete(pClass, "d")
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Delete failed", $system.Status.GetErrorText(tSC))
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"ok": 1, "deleted": (pClass)})
}

/// Internal: apply UI fields to the class definition + recompile.
/// Called by Save (existing class) and Create (after %New + %Save).
ClassMethod ApplyEdits(pClass As %String, pReq As %DynamicObject) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set tSC = $$$OK

    // Class Description
    If pReq.%IsDefined("description") {
        Set cdef = ##class(%Dictionary.ClassDefinition).%OpenId(pClass)
        If $isobject(cdef) {
            Set cdef.Description = pReq.description
            Set tSC = cdef.%Save()
            If 'tSC { Quit tSC }
        }
    }

    // Parameters (only set if the field is in the request)
    Set fields = $listbuild("NAME","name", "TEMPERATURE","temperature", "MAXITERATIONS","maxIterations", "PROVIDER","provider")
    For i=1:2:$listlength(fields) {
        Set pname = $listget(fields, i)
        Set jkey  = $listget(fields, i+1)
        If pReq.%IsDefined(jkey) {
            Set tSC = $classmethod(util, "SetParameter", pClass, pname, $S(pReq.%Get(jkey)="":"", 1:pReq.%Get(jkey)))
            If 'tSC { Quit }
        }
    }
    If 'tSC { Quit tSC }

    // MCPS / SKILLS — accept either a CSV string or an array.
    If pReq.%IsDefined("mcps") {
        Set csv = $S($isobject(pReq.mcps):$classmethod(util,"ArrayToCsv",pReq.mcps), 1:pReq.mcps)
        Set tSC = $classmethod(util, "SetParameter", pClass, "MCPS", csv)
        If 'tSC { Quit tSC }
    } ElseIf pReq.%IsDefined("mcpsCsv") {
        Set tSC = $classmethod(util, "SetParameter", pClass, "MCPS", pReq.mcpsCsv)
        If 'tSC { Quit tSC }
    }
    If pReq.%IsDefined("skills") {
        Set csv = $S($isobject(pReq.skills):$classmethod(util,"ArrayToCsv",pReq.skills), 1:pReq.skills)
        Set tSC = $classmethod(util, "SetParameter", pClass, "SKILLS", csv)
        If 'tSC { Quit tSC }
    } ElseIf pReq.%IsDefined("skillsCsv") {
        Set tSC = $classmethod(util, "SetParameter", pClass, "SKILLS", pReq.skillsCsv)
        If 'tSC { Quit tSC }
    }

    // Instructions XData (markdown system prompt)
    If pReq.%IsDefined("instructions") {
        Set tSC = $classmethod(util, "SetXData", pClass, "INSTRUCTIONS", pReq.instructions, "text/markdown")
        If 'tSC { Quit tSC }
    }

    Quit $classmethod(util, "Recompile", pClass)
}

}
