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
/// Works for both %AI.ToolSet subclasses and %AI.Tool subclasses.
/// NOTE: %AI.ToolSet extends %AI.Tool in the framework class hierarchy,
/// so we MUST check for %AI.ToolSet FIRST (more specific) before falling
/// back to the %AI.Tool branch. Checking %AI.Tool first would incorrectly
/// route ToolSet classes to GetToolClass, which lists ClassMethods on the
/// ToolSet itself (empty) instead of parsing its Definition XData.
ClassMethod Get(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "Class does not exist", pClass)
    }
    ; %AI.ToolSet subclass — parse Definition XData for included tools.
    ; Must check BEFORE %AI.Tool because %AI.ToolSet extends %AI.Tool.
    If $classmethod(util, "ExtendsClass", pClass, "%AI.ToolSet") {
        ; Fall through to the ToolSet handler below
    }
    ; %AI.Tool subclass (but NOT a ToolSet) — list public ClassMethods as tools
    ElseIf $classmethod(util, "ExtendsClass", pClass, "%AI.Tool") {
        Quit ..GetToolClass(pResponse, pClass)
    }
    Else {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Class is not a %AI.Tool or %AI.ToolSet subclass", pClass)
    }
    // Overlay-aware read — surfaces user customizations on top of
    // shipped class metadata.
    Set effective = ##class(AgenticInterop.Editor.Overlay).GetEffectiveToolSet(pClass)
    Set body = effective
    Set body.userAuthored = ..IsUserAuthored(pClass)
    Set rawManifest = body.toolManifest
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
    // If ToolManifest yielded nothing, fall back to parsing tool
    // names out of Definition XML — `<Tool Name="..." Method="..."/>`.
    // Shipped toolsets have only the XML; Phase 4 generators will
    // eventually keep the JSON manifest in sync.
    If $isobject(tools), tools.%Size() = 0, body.definitionRaw '= "" {
        Set tools = ..%ParseDefinitionTools(body.definitionRaw, pClass)
        Set body.toolSource = "definition-xml"
    } Else {
        Set body.toolSource = "tool-manifest"
    }
    Set body.tools = tools
    Set body.toolCount = $select($isobject(tools):tools.%Size(), 1:0)
    ; Extract the included %AI.Tool provider class from the Definition XData
    Set defRaw = body.definitionRaw
    If defRaw '= "" {
        Set body.includedClass = ..%ExtractIncludedClass(defRaw)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// Handle GET for %AI.Tool subclasses — introspect public ClassMethods
/// as tool entries. Each method becomes a tool the LLM can call.
ClassMethod GetToolClass(pResponse As %CSP.Response, pClass As %String) As %Status [ Internal ]
{
    Set util = "AgenticInterop.Editor.Util"
    Set body = {}
    Set body.class = pClass
    Set body.name = $piece(pClass, ".", $length(pClass, "."))
    Set body.userAuthored = 0
    Set body.toolSource = "class-methods"
    ; Read class description
    Set cdef = ##class(%Dictionary.CompiledClass).%OpenId(pClass)
    If $isobject(cdef) {
        Set body.description = $extract(cdef.Description, 1, 500)
    }
    ; List public ClassMethods (skip %-prefixed system methods)
    Set tools = []
    Set mrs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, Description, FormalSpec FROM %Dictionary.CompiledMethod " _
        "WHERE parent = ? AND ClassMethod = 1 " _
        "AND Name NOT LIKE '\%%' ESCAPE '\'", pClass)
    While mrs.%Next() {
        Set t = {}
        Set t.name = mrs.%Get("Name")
        Set t.description = $extract(mrs.%Get("Description"), 1, 300)
        Set t.formalSpec = mrs.%Get("FormalSpec")
        Do tools.%Push(t)
    }
    Set body.tools = tools
    Set body.toolCount = tools.%Size()
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

/// PUT /api/agentic/editor/toolset/:class
/// Body: { name, description, definitionRaw }
///
/// Save routing:
///   - User-authored classes (AgenticInterop.User.ToolSet.*) write
///     to .cls dictionary as before.
///   - Shipped classes write to AgenticInterop.Data.ToolSetOverride.
///     Caveat: definitionRaw / toolManifest customizations
///     round-trip through the editor but do NOT change runtime tool
///     dispatch — the framework parses Definition XData at compile
///     time. UI shows the override; runtime sees the shipped class.
///     Name + description ARE used at request time via GetEffectiveToolSet.
ClassMethod Save(pResponse As %CSP.Response, pClass As %String, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    If '$isobject(req) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "Invalid JSON body")
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "ToolSet class does not exist", pClass)
    }
    ; Tool selection changes MUST write to the actual class (not just
    ; the overlay) because the framework reads XData Definition at
    ; compile time. Overlay-only writes round-trip through the editor
    ; but do NOT affect runtime tool dispatch.
    If req.%IsDefined("includedClass") || req.%IsDefined("selectedTools") {
        ; Write directly to class source + recompile
        Set tSC = ..ApplyEdits(pClass, req)
    } ElseIf ..IsUserAuthored(pClass) {
        Set tSC = ..ApplyEdits(pClass, req)
    } Else {
        Set tSC = ##class(AgenticInterop.Editor.Overlay).SaveToolSetOverride(pClass, req, $username)
    }
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Save failed", $system.Status.GetErrorText(tSC))
    }
    Quit ..Get(pResponse, pClass)
}

/// POST /api/agentic/editor/toolset/:class/reset — drops the override.
ClassMethod Reset(pResponse As %CSP.Response, pClass As %String) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    If '##class(%Dictionary.CompiledClass).%ExistsId(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "404 Not Found", "ToolSet class does not exist", pClass)
    }
    If ..IsUserAuthored(pClass) {
        Quit $classmethod(util, "WriteError", pResponse, "400 Bad Request", "User-authored ToolSets do not use overrides — edits already write to .cls.", pClass)
    }
    Set tSC = ##class(AgenticInterop.Editor.Overlay).ResetToolSet(pClass)
    If 'tSC {
        Quit $classmethod(util, "WriteError", pResponse, "500 Internal Server Error", "Reset failed", $system.Status.GetErrorText(tSC))
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

/// Parse the Definition XData and produce the list of tools the
/// editor should render. Three patterns are supported:
///
///   (a) Pattern 1 — inline tools on the ToolSet itself:
///       `<Tool Name="..." Method="..."/>` — the Method is a
///       ClassMethod on pClass. Used by user-authored toolsets the
///       UI manages.
///
///   (b) Pattern 5 — included %AI.Tool subclass (all tools):
///       `<Include Class="..."/>` — every public ClassMethod on the
///       included class is a tool, auto-discovered by the framework.
///       Used by shipped AgenticInterop.ToolSet.* which wrap
///       AgenticInterop.Tool.* %AI.Tool providers.
///
///   (c) Pattern 5 with Filter — selective inclusion:
///       `<Include Class="..."><Filter Tool="X"/>...</Include>`
///       Only the listed tools are active. Other tools from the
///       provider appear with enabled=0 so the editor can show them
///       as unchecked.
///
/// In all cases each tool entry carries the real method Description
/// (the leading /// block, what the framework feeds the LLM) and the
/// Implementation (method body source) pulled from
/// %Dictionary.CompiledMethod. Each tool entry also carries an
/// `enabled` flag (1 or 0) reflecting the filter state.
///
/// pXml:   the XData Definition body.
/// pClass: the ToolSet class — needed for Pattern 1 (where Methods
///         live on pClass). For Pattern 5 we read from the Include's
///         Class attribute instead.
ClassMethod %ParseDefinitionTools(pXml As %String, pClass As %String = "") As %DynamicArray [ Internal ]
{
    Set arr = []
    Set lines = $LENGTH(pXml, $char(10))
    Set inInclude = 0
    Set includeClass = ""
    Set filterCSV = ""
    For i=1:1:lines {
        Set line = $PIECE(pXml, $char(10), i)
        ; Inside an <Include>...</Include> block — collect Filter elements
        If inInclude {
            If line [ "</Include>" {
                ; End of Include block — append tools with filter applied
                If filterCSV '= "" {
                    Do ..%AppendFilteredTools(arr, includeClass, filterCSV)
                } Else {
                    Do ..%AppendDiscoveredTools(arr, includeClass)
                }
                Set inInclude = 0
                Set includeClass = ""
                Set filterCSV = ""
                Continue
            }
            If line [ "<Filter " {
                Set toolName = ..%XmlAttr(line, "Tool")
                If toolName '= "" {
                    Set filterCSV = filterCSV _ $select(filterCSV'="":",", 1:"") _ toolName
                }
            }
            Continue
        }
        ; Pattern 5 — <Include Class="..."/>  or  <Include Class="...">
        If line [ "<Include " {
            Set incCls = ..%XmlAttr(line, "Class")
            If incCls = "" { Continue }
            If line [ "/>" {
                ; Self-closing — all tools enabled
                Do ..%AppendDiscoveredTools(arr, incCls)
            } Else {
                ; Opening tag — collect Filter children until </Include>
                Set inInclude = 1
                Set includeClass = incCls
                Set filterCSV = ""
            }
            Continue
        }
        ; Pattern 1 — <Tool Name="..." Method="..."/>
        If line [ "<Tool " {
            Set name = ..%XmlAttr(line, "Name")
            Set method = ..%XmlAttr(line, "Method")
            If name = "" { Continue }
            Do ..%AppendInlineTool(arr, pClass, name, method)
            Continue
        }
    }
    Quit arr
}

/// Discovery helper for Pattern 5 — walks every public ClassMethod on
/// pIncludedClass and pushes one tool entry per method. Skips methods
/// flagged `[Internal]`, methods named with leading `%`, and inherited
/// methods from %AI.Tool / %Library.RegisteredObject (which would
/// otherwise leak into the catalog). All tools are marked enabled=1
/// (no filter). Internal helper.
ClassMethod %AppendDiscoveredTools(pArr As %DynamicArray, pIncludedClass As %String) [ Internal ]
{
    Set sql = "SELECT Name, Description, FormalSpec, ReturnType, ClassMethod, Internal "
    Set sql = sql _ "FROM %Dictionary.CompiledMethod "
    Set sql = sql _ "WHERE Parent = ? AND Origin = ? "
    Set sql = sql _ "ORDER BY Name"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pIncludedClass, pIncludedClass)
    While rs.%Next() {
        Set methodName = rs.%Get("Name")
        ; Skip framework / system methods.
        If $extract(methodName, 1, 1) = "%" { Continue }
        If +rs.%Get("Internal") { Continue }
        Set entry = {}
        Set entry.name = methodName
        Set entry.method = methodName
        Set entry.providerClass = pIncludedClass
        Set entry.description = rs.%Get("Description")
        Set entry.formalSpec = rs.%Get("FormalSpec")
        Set entry.returnType = rs.%Get("ReturnType")
        Set entry.classMethod = ''+rs.%Get("ClassMethod")
        Set entry.enabled = 1
        Set entry.implementation = {}
        Set entry.implementation.kind = "objectscript"
        Try {
            Set cm = ##class(%Dictionary.CompiledMethod).%OpenId(pIncludedClass _ "||" _ methodName)
            If $isobject(cm), $isobject(cm.Implementation) {
                Set src = ""
                Do cm.Implementation.Rewind()
                While 'cm.Implementation.AtEnd { Set src = src _ cm.Implementation.Read(8192) }
                Set entry.implementation.body = src
            }
        } Catch  {}
        Do pArr.%Push(entry)
    }
    Quit
}

/// Discovery helper for Pattern 5 with Filter — walks every public
/// ClassMethod on pIncludedClass, marks each tool with enabled=1 if
/// its name appears in the comma-separated pFilterCSV, enabled=0
/// otherwise. This lets the editor show all available tools with
/// checked/unchecked state. Internal helper.
ClassMethod %AppendFilteredTools(pArr As %DynamicArray, pIncludedClass As %String, pFilterCSV As %String) [ Internal ]
{
    ; Build a lookup of enabled tool names from the filter CSV
    For fi=1:1:$length(pFilterCSV, ",") {
        Set enabledLookup($zstrip($piece(pFilterCSV, ",", fi), "<>W")) = 1
    }
    Set sql = "SELECT Name, Description, FormalSpec, ReturnType, ClassMethod, Internal "
    Set sql = sql _ "FROM %Dictionary.CompiledMethod "
    Set sql = sql _ "WHERE Parent = ? AND Origin = ? "
    Set sql = sql _ "ORDER BY Name"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pIncludedClass, pIncludedClass)
    While rs.%Next() {
        Set methodName = rs.%Get("Name")
        If $extract(methodName, 1, 1) = "%" { Continue }
        If +rs.%Get("Internal") { Continue }
        Set entry = {}
        Set entry.name = methodName
        Set entry.method = methodName
        Set entry.providerClass = pIncludedClass
        Set entry.description = rs.%Get("Description")
        Set entry.formalSpec = rs.%Get("FormalSpec")
        Set entry.returnType = rs.%Get("ReturnType")
        Set entry.classMethod = ''+rs.%Get("ClassMethod")
        Set entry.enabled = $select($data(enabledLookup(methodName)):1, 1:0)
        Set entry.implementation = {}
        Set entry.implementation.kind = "objectscript"
        Try {
            Set cm = ##class(%Dictionary.CompiledMethod).%OpenId(pIncludedClass _ "||" _ methodName)
            If $isobject(cm), $isobject(cm.Implementation) {
                Set src = ""
                Do cm.Implementation.Rewind()
                While 'cm.Implementation.AtEnd { Set src = src _ cm.Implementation.Read(8192) }
                Set entry.implementation.body = src
            }
        } Catch  {}
        Do pArr.%Push(entry)
    }
    Quit
}

/// Pattern-1 helper — read description + body for an inline tool's
/// backing ClassMethod. Internal helper.
ClassMethod %AppendInlineTool(pArr As %DynamicArray, pClass As %String, pName As %String, pMethod As %String) [ Internal ]
{
    Set entry = {}
    Set entry.name = pName
    Set entry.method = pMethod
    Set entry.implementation = {}
    Set entry.implementation.kind = "objectscript"
    Set found = 0
    If pClass '= "", pMethod '= "" {
        Try {
            Set cm = ##class(%Dictionary.CompiledMethod).%OpenId(pClass _ "||" _ pMethod)
            If $isobject(cm) {
                Set entry.description = cm.Description
                Set entry.formalSpec = cm.FormalSpec
                Set entry.returnType = cm.ReturnType
                Set entry.classMethod = ''(cm.ClassMethod)
                If $isobject(cm.Implementation) {
                    Set src = ""
                    Do cm.Implementation.Rewind()
                    While 'cm.Implementation.AtEnd { Set src = src _ cm.Implementation.Read(8192) }
                    Set entry.implementation.body = src
                }
                Set found = 1
            }
        } Catch  {}
    }
    If 'found {
        Set entry.description = "(method " _ pMethod _ " not found in %Dictionary; recompile the ToolSet class)"
        Set entry.implementation.body = "ClassMethod " _ pMethod
    }
    Do pArr.%Push(entry)
    Quit
}

/// Extract the %AI.Tool provider class name from the first <Include>
/// element in the XData Definition. Returns "" if no Include found.
ClassMethod %ExtractIncludedClass(pXml As %String) As %String [ Internal ]
{
    Set lines = $length(pXml, $char(10))
    For i=1:1:lines {
        Set line = $piece(pXml, $char(10), i)
        If line [ "<Include " {
            Set cls = ..%XmlAttr(line, "Class")
            If cls '= "" Return cls
        }
    }
    Quit ""
}

/// Build the ToolSet Definition XData XML from tool selection state.
/// When pSelectedCSV is empty or "*", a plain <Include Class="..."/>
/// is emitted (all tools active). Otherwise <Filter Tool="..."/>
/// children restrict the active set while leaving deselected tools
/// visible-but-unchecked in the editor.
///
/// pName:         ToolSet display name (for the Name attribute).
/// pDescription:  ToolSet description (for the <Description> element).
/// pIncludedClass: fully-qualified %AI.Tool provider class.
/// pSelectedCSV:  comma-separated list of selected tool names, or ""/"*" for all.
ClassMethod BuildDefinitionXml(pName As %String, pDescription As %String, pIncludedClass As %String, pSelectedCSV As %String = "") As %String [ Internal ]
{
    Set descEsc = ..%XmlEscape(pDescription)
    Set xml = "<ToolSet Name="""_pName_""">"_$char(10)
    Set xml = xml _ "    <Description>"_descEsc_"</Description>"_$char(10)
    If pSelectedCSV = "" || (pSelectedCSV = "*") {
        ; All tools — simple self-closing Include
        Set xml = xml _ "    <Include Class="""_pIncludedClass_"""/>"_$char(10)
    } Else {
        ; Filtered — Include with Filter children
        Set xml = xml _ "    <Include Class="""_pIncludedClass_""">"_$char(10)
        For pi=1:1:$length(pSelectedCSV, ",") {
            Set toolName = $zstrip($piece(pSelectedCSV, ",", pi), "<>W")
            If toolName '= "" {
                Set xml = xml _ "        <Filter Tool="""_toolName_"""/>"_$char(10)
            }
        }
        Set xml = xml _ "    </Include>"_$char(10)
    }
    Set xml = xml _ "</ToolSet>"
    Quit xml
}

/// Build the ToolSet Definition XData XML from a multi-provider
/// selection. pSelections is a DynamicArray of {name, providerClass}
/// objects. Groups tools by provider class and emits one <Include>
/// per provider (with <Filter> children when only a subset is chosen).
///
/// pName:        ToolSet display name.
/// pDescription: ToolSet description.
/// pSelections:  DynamicArray of {name, providerClass}.
ClassMethod BuildDefinitionXmlMulti(pName As %String, pDescription As %String, pSelections As %DynamicArray) As %String [ Internal ]
{
    Set descEsc = ..%XmlEscape(pDescription)
    Set xml = "<ToolSet Name="""_pName_""">"_$char(10)
    Set xml = xml _ "    <Description>"_descEsc_"</Description>"_$char(10)
    ; Group selected tools by provider class: grouped(provClass, toolName)=""
    Set iter = pSelections.%GetIterator()
    While iter.%GetNext(.key, .val) {
        Set provCls = val.providerClass
        Set toolName = val.name
        If provCls '= "", toolName '= "" {
            Set grouped(provCls, toolName) = ""
        }
    }
    ; For each provider class, count selected vs total then emit Include
    Set provCls = ""
    For {
        Set provCls = $order(grouped(provCls))
        If provCls = "" Quit
        ; Count selected tools for this provider
        Set selCount = 0, tn = ""
        For {
            Set tn = $order(grouped(provCls, tn))
            If tn = "" Quit
            Set selCount = selCount + 1
        }
        ; Count total discoverable tools for this provider
        Set totalCount = ..%CountProviderTools(provCls)
        If selCount = totalCount {
            ; All tools selected — simple self-closing Include
            Set xml = xml _ "    <Include Class="""_provCls_"""/>"_$char(10)
        } Else {
            ; Subset — Include with Filter children
            Set xml = xml _ "    <Include Class="""_provCls_""">"_$char(10)
            Set tn = ""
            For {
                Set tn = $order(grouped(provCls, tn))
                If tn = "" Quit
                Set xml = xml _ "        <Filter Tool="""_tn_"""/>"_$char(10)
            }
            Set xml = xml _ "    </Include>"_$char(10)
        }
    }
    Set xml = xml _ "</ToolSet>"
    Quit xml
}

/// Count public, non-internal ClassMethods on a %AI.Tool provider class.
/// Used by BuildDefinitionXmlMulti to decide Include vs Include+Filter.
ClassMethod %CountProviderTools(pClass As %String) As %Integer [ Internal ]
{
    Set count = 0
    Set sql = "SELECT Name, Internal FROM %Dictionary.CompiledMethod "
    Set sql = sql _ "WHERE Parent = ? AND Origin = ? ORDER BY Name"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pClass, pClass)
    While rs.%Next() {
        Set mName = rs.%Get("Name")
        If $extract(mName, 1, 1) = "%" { Continue }
        If +rs.%Get("Internal") { Continue }
        Set count = count + 1
    }
    Quit count
}

/// GET /api/agentic/editor/tool-providers
/// Returns all %AI.Tool subclasses available in the system with their
/// discoverable public ClassMethods. Used by the ToolSet editor to let
/// the user select a provider when creating or editing a ToolSet.
ClassMethod ListProviders(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set arr = []
    Set sql = "SELECT Name FROM %Dictionary.CompiledClass "
    Set sql = sql _ "WHERE Name %STARTSWITH 'AgenticInterop.Tool.' "
    Set sql = sql _ "OR Name %STARTSWITH 'AgenticInterop.User.Tool.' "
    Set sql = sql _ "ORDER BY Name"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    While rs.%Next() {
        Set cls = rs.%Get("Name")
        ; Only include classes that extend %AI.Tool
        If '$classmethod(util, "ExtendsClass", cls, "%AI.Tool") { Continue }
        Set entry = {}
        Set entry.class = cls
        Set entry.shortName = $piece(cls, ".", $length(cls, "."))
        ; Discover public ClassMethods (same logic as %AppendDiscoveredTools)
        Set methods = []
        Set msql = "SELECT Name, Description, Internal FROM %Dictionary.CompiledMethod "
        Set msql = msql _ "WHERE Parent = ? AND Origin = ? ORDER BY Name"
        Set mrs = ##class(%SQL.Statement).%ExecDirect(, msql, cls, cls)
        While mrs.%Next() {
            Set mName = mrs.%Get("Name")
            If $extract(mName, 1, 1) = "%" { Continue }
            If +mrs.%Get("Internal") { Continue }
            Set m = {}
            Set m.name = mName
            Set m.description = mrs.%Get("Description")
            Do methods.%Push(m)
        }
        Set entry.methods = methods
        Set entry.methodCount = methods.%Size()
        Do arr.%Push(entry)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, {"providers": (arr)})
}

/// Escape a string for safe embedding inside XML element content.
/// Handles &, <, >, " — the minimum set to avoid SAX parse errors
/// when descriptions contain angle brackets (e.g. "<Include>").
ClassMethod %XmlEscape(pText As %String) As %String [ Internal ]
{
    Set out = $replace(pText, "&", "&amp;")
    Set out = $replace(out, "<", "&lt;")
    Set out = $replace(out, ">", "&gt;")
    Set out = $replace(out, """", "&quot;")
    Quit out
}

/// Pluck `Name="value"` out of a fragment. Empty if not present.
ClassMethod %XmlAttr(pLine As %String, pAttr As %String) As %String [ Internal ]
{
    Set marker = pAttr _ "="""
    Set p = $FIND(pLine, marker)
    If p = 0 { Quit "" }
    Set rest = $EXTRACT(pLine, p, *)
    Set q = $FIND(rest, """")
    If q = 0 { Quit "" }
    Quit $EXTRACT(rest, 1, q - 2)
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
            If 'tSC Quit tSC
        }
    }
    If pReq.%IsDefined("name") {
        Set tSC = $classmethod(util, "SetParameter", pClass, "NAME", pReq.name)
        If 'tSC Quit tSC
    }
    ; Tool selection — build Definition XData from selectedTools.
    ; selectedTools can be:
    ;   (a) Array of {name, providerClass} objects — multi-provider (new format)
    ;   (b) Array of plain strings + includedClass — single-provider (legacy)
    ; This takes priority over raw definitionRaw because it represents the
    ; structured tool-selector state from the editor UI.
    If pReq.%IsDefined("selectedTools"), $isobject(pReq.selectedTools) {
        ; Resolve display name for the XData ToolSet Name attribute
        Set tsName = ""
        If pReq.%IsDefined("name"), pReq.name '= "" {
            Set tsName = pReq.name
        } Else {
            Set tsName = $piece(pClass, ".", $length(pClass, "."))
        }
        ; Resolve description for the <Description> element
        Set tsDesc = ""
        If pReq.%IsDefined("toolsetDescription") {
            Set tsDesc = pReq.toolsetDescription
        } ElseIf pReq.%IsDefined("description") {
            Set tsDesc = pReq.description
        }
        ; Detect format: if first element is an object with providerClass, use multi-provider
        Set isMulti = 0
        If pReq.selectedTools.%Size() > 0 {
            Set first = pReq.selectedTools.%Get(0)
            If $isobject(first), first.%IsDefined("providerClass") {
                Set isMulti = 1
            }
        }
        If isMulti {
            Set xml = ..BuildDefinitionXmlMulti(tsName, tsDesc, pReq.selectedTools)
        } Else {
            ; Legacy single-provider format (array of strings)
            Set incCls = ""
            If pReq.%IsDefined("includedClass") { Set incCls = pReq.includedClass }
            Set selCSV = ""
            Set iter = pReq.selectedTools.%GetIterator()
            While iter.%GetNext(.key, .val) {
                Set selCSV = selCSV _ $select(selCSV'="":",", 1:"") _ val
            }
            If incCls '= "" {
                Set xml = ..BuildDefinitionXml(tsName, tsDesc, incCls, selCSV)
            }
        }
        If $data(xml), xml '= "" {
            Set tSC = $classmethod(util, "SetXData", pClass, "Definition", xml, "application/xml")
            If 'tSC Quit tSC
        }
    } ElseIf pReq.%IsDefined("includedClass"), pReq.includedClass '= "" {
        ; Legacy: includedClass without selectedTools — include all from one provider
        Set tsName = $select(pReq.%IsDefined("name")&&(pReq.name'=""):pReq.name, 1:$piece(pClass,".",$length(pClass,".")))
        Set tsDesc = ""
        If pReq.%IsDefined("toolsetDescription") { Set tsDesc = pReq.toolsetDescription }
        ElseIf pReq.%IsDefined("description") { Set tsDesc = pReq.description }
        Set xml = ..BuildDefinitionXml(tsName, tsDesc, pReq.includedClass, "")
        Set tSC = $classmethod(util, "SetXData", pClass, "Definition", xml, "application/xml")
        If 'tSC Quit tSC
    } ElseIf pReq.%IsDefined("definitionRaw") {
        ; Fallback: raw XData editing (advanced mode)
        Set tSC = $classmethod(util, "SetXData", pClass, "Definition", pReq.definitionRaw, "application/xml")
        If 'tSC Quit tSC
    }
    Quit $classmethod(util, "Recompile", pClass)
}

}
