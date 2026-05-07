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
    Set match = ""
    // First try the editor-managed ToolManifest XData (user-authored).
    Set def = ..LoadDefinition(pToolSet)
    If $isobject(def) {
        Set iter = def.tools.%GetIterator()
        While iter.%GetNext(.k, .t) {
            If $isobject(t), t.name = pName {
                Set match = t
                Quit
            }
        }
    }
    // Fall back to the framework Definition XML for shipped tools.
    // Surfaces them as read-only entries with the right name + a
    // synthetic description so the editor renders the form (and its
    // Phase 6 Dry Run panel works).
    If '$isobject(match) {
        Set xml = $classmethod(util, "XDataBody", pToolSet, "Definition")
        If xml '= "" {
            // Pass pToolSet so %ParseDefinitionTools can pull the
            // real Description (the LLM-visible /// block) and
            // Implementation (the method body source) from
            // %Dictionary.CompiledMethod.
            Set arr = ##class(AgenticInterop.Editor.ToolSetService).%ParseDefinitionTools(xml, pToolSet)
            If $isobject(arr) {
                Set iter = arr.%GetIterator()
                While iter.%GetNext(.k, .t) {
                    If $isobject(t), t.name = pName {
                        Set match = t
                        Quit
                    }
                }
            }
        }
    }
    If '$isobject(match) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Tool not found in ToolSet", pName)
    }
    // Surface a curated sample input so the dry-run panel pre-fills
    // the textarea — one-click test for shipped tools.
    Try {
        Set sample = ..SampleInput(pName)
        If $isobject(sample) { Set match.sampleInput = sample }
    } Catch  {}
    Quit $classmethod(util, "WriteJSON", pResponse, match)
}

/// Curated sample argument shapes — what to drop into the dry-run
/// panel for each shipped tool. Keyed by tool name (the Name attribute
/// in the Definition XData, NOT the method name). Returns a
/// %DynamicObject; the admin renders it as JSON in the textarea so
/// the user can click Run immediately or edit first.
///
/// Add an entry here when you ship a new tool. Unknown tools → empty
/// object — the user fills the input manually.
ClassMethod SampleInput(pToolName As %String) As %DynamicObject
{
    Set t = $get(pToolName)
    // ===== Catalog =====
    If t = "DescribeClass" Quit {"className":"EnsLib.HL7.Message"}
    If t = "GetUserNamespace" Quit {}
    If t = "ListUserAccessibleNamespaces" Quit {}
    If t = "ExplainStatus" Quit {"status":"0 100 ,Ens.Util.Log,SourceClass,SourceMethod"}
    If t = "LookupErrorCode" Quit {"code":5001}
    If t = "LookupGlossaryTerm" Quit {"term":"abstract class"}
    If t = "SearchApiIndex" Quit {"query":"HL7 messages","k":3}
    // ===== Production =====
    If t = "ListProductions" Quit {}
    If t = "GetProduction" Quit {"name":"Demo.Production"}
    If t = "StartProduction" Quit {"production":"Demo.Production"}
    If t = "StopProduction" Quit {"timeout":30,"force":false}
    If t = "CreateProduction" Quit {"name":"MyApp.Productions.Test","description":"A test production created via dry-run"}
    If t = "DeleteProduction" Quit {"name":"MyApp.Productions.Test"}
    If t = "AddBusinessHost" Quit {"production":"MyApp.Productions.Test","hostName":"InboundHL7","hostClass":"EnsLib.HL7.Service.TCPService","settings":{"Adapter":{"Port":"5000"}}}
    If t = "RemoveBusinessHost" Quit {"production":"MyApp.Productions.Test","hostName":"InboundHL7"}
    If t = "UpdateBusinessHostSettings" Quit {"production":"MyApp.Productions.Test","hostName":"InboundHL7","settings":{"Adapter":{"Port":"5500"}}}
    // ===== Testing =====
    If t = "ValidateHL7Structure" Quit {"message":("MSH|^~\&|EpicADT|HOSP|RPMS|LAB|20260101100000||ADT^A01|MSG00001|P|2.5"_$char(13)_"EVN|A01|20260101100000"_$char(13)_"PID|1||100001||DOE^JOHN||19800101|M"_$char(13)_"PV1|1|I"_$char(13))}
    If t = "ValidateHL7Semantics" Quit {"message":("MSH|^~\&|EpicADT|HOSP|RPMS|LAB|20260101100000||ADT^A01|MSG00001|P|2.5"_$char(13)_"EVN|A01|20260101100000"_$char(13)_"PID|1||100001||DOE^JOHN||19800101|M"_$char(13)_"PV1|1|I"_$char(13)),"docType":"2.5:ADT_A01"}
    If t = "ValidateFHIRResource" Quit {"resource":{"resourceType":"Patient","id":"abc","name":[{"family":"Doe","given":["John"]}]}}
    If t = "CompareMessages" Quit {"messageA":("MSH|^~\&|A|H1|B|H2|20260101||ADT^A01|001|P|2.5"_$char(13)_"PID|1||100||DOE^JOHN||19800101|M"_$char(13)),"messageB":("MSH|^~\&|A|H1|B|H2|20260101||ADT^A01|001|P|2.5"_$char(13)_"PID|1||100||SMITH^JOHN||19800101|M"_$char(13))}
    If t = "SendHL7" Quit {"message":("MSH|^~\&|EpicADT|HOSP|RPMS|LAB|20260101100000||ADT^A01|MSG00001|P|2.5"_$char(13)_"PID|1||100001||DOE^JOHN||19800101|M"_$char(13)),"targetHost":"HL7Service"}
    If t = "SendFHIR" Quit {"resource":{"resourceType":"Patient","name":[{"family":"Doe","given":["John"]}]},"endpoint":"https://fhir.example.com/r4/Patient","authBearer":""}
    // ===== Transform =====
    If t = "ListDTLs" Quit {}
    If t = "ListLookupTables" Quit {}
    If t = "ListBusinessRules" Quit {}
    If t = "CompileDTL" Quit {"name":"Demo.Transform.MyDTL"}
    If t = "CreateDTL" Quit {"name":"Demo.Transform.MyDTL","sourceClass":"Ens.Request","targetClass":"Ens.Response"}
    If t = "UpdateDTL" {
        Set dtlSample = "<transform sourceClass=""Ens.Request"" targetClass=""Ens.Response"" create=""new"" language=""objectscript""><assign property=""target.Type"" value=""$$$copied$$$"" action=""set""/></transform>"
        Set dtlSample = $replace(dtlSample, "$$$copied$$$", """copied""")
        Quit {"name":"Demo.Transform.MyDTL","dtlXml":(dtlSample)}
    }
    If t = "DryRunDTL" Quit {"name":"Demo.Transform.MyDTL","sourceText":("MSH|^~\&|A|H1|B|H2|20260101||ADT^A01|001|P|2.5"_$char(13)_"PID|1||100||DOE^JOHN||19800101|M"_$char(13))}
    If t = "CreateBPL" Quit {"name":"Demo.Process.MyBPL","requestClass":"Ens.Request","responseClass":"Ens.Response"}
    If t = "ValidateBPL" Quit {"name":"Demo.Process.MyBPL"}
    Quit {}
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

/// POST /api/agentic/editor/tool/:toolset/:name/dryrun
/// Body: { "input": { ...tool args... } }
///
/// Phase 6 dry-run panel — execute the tool with the provided input
/// and return whatever it produces, so a tool author can verify the
/// implementation works before wiring it to a chat. Goes through
/// %AI.ToolMgr.RegisterToolSet + ExecuteTool, which is the same
/// dispatch the framework uses when the LLM picks a tool — so dry-run
/// behavior matches production behavior.
///
/// Read-only verification: the gate is NOT applied here (the operator
/// has explicit intent — they pasted the input and clicked Run).
/// Mutating tools that the gate would block at chat time still mutate
/// when invoked via dry-run; the UI surfaces a "this is a mutating
/// tool" warning before the operator clicks.
ClassMethod DryRun(pResponse As %CSP.Response, pToolSet As %String, pName As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pToolSet) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "ToolSet does not exist", pToolSet)
    }
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    Set inputArgs = ""
    If $isobject(req), req.%IsDefined("input"), $isobject(req.input) {
        Set inputArgs = req.input
    } Else {
        Set inputArgs = {}
    }
    Set out = {}
    Set start = $zhorolog
    Set out.tool = pName
    Set out.toolset = pToolSet
    Try {
        // Use a per-request ToolMgr name — `agentic-dryrun-<class>-<job>-<ts>`
        // — so we re-register fresh every time. Caching by `agentic-dryrun-<class>`
        // would let a stale registration persist across class recompiles
        // (the framework caches the FormalSpec at register time; if the
        // method's signature changes, the cached spec is wrong until the
        // process restarts). Re-registering each call is cheap.
        Set tag = "agentic-dryrun-" _ pToolSet _ "-" _ $job _ "-" _ $zhorolog
        Set tm = ##class(%AI.ToolMgr).GetOrCreate(tag, .isNew)
        Do tm.RegisterToolSet(pToolSet)
        Set raw = tm.ExecuteTool(pName, inputArgs)
        Set out.ok = 1
        // ExecuteTool returns a wrapper object {value, timing} on
        // some builds, or the raw return value on others. Surface
        // both shapes — caller renders whichever is non-empty.
        If $isobject(raw) {
            Try { Set out.output = raw.value } Catch  { Set out.output = raw }
            Try { Set out.timing = raw.timing } Catch  {}
        } Else {
            Set out.output = raw
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 1000)
    }
    Set out.elapsedMs = $fnumber(($zhorolog - start) * 1000, "", 0)
    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

}
