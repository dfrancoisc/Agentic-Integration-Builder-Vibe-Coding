/// Transform ToolSet — initial cut (Phase 4). DTL (Data Transformation
/// Language) inventory and compile actions. Lets the agent answer
/// "what DTLs already exist for X?" and re-compile a DTL after a user
/// edit so the next interop run picks up the change.
///
/// Roadmap (not yet built): create_dtl, update_dtl, dry_run_dtl,
/// list_lookup_tables, crud_lookup_table, list_bpls, create_bpl,
/// validate_bpl, list_business_rules, evaluate_rule. See
/// docs/TOOLS.md "ToolSet.Transform".
/// %AI.Tool source for the Transform toolset. Each public ClassMethod
/// is auto-discovered by the framework as a tool — the method name
/// is the tool name the LLM sees. Composed into AgenticInterop.ToolSet.
/// Transform via <Include Class="AgenticInterop.Tool.Transform"/> (Pattern 5
/// of the ai-hub-tools skill).
Class AgenticInterop.Tool.Transform Extends %AI.Tool
{


/// Resolve the active namespace for this tool call. Internal helper.
ClassMethod %TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// List Data Transformation Language (DTL) classes defined in the
/// chat's active namespace. Returns the class name + super class for
/// each DTL — enough for the agent to answer "what DTLs do we have"
/// or "is there already a DTL that maps X to Y" (combined with a
/// describe_class follow-up). CALL THIS whenever the user wants an
/// inventory of transformations.
///
/// Returns: { ok, namespace, dtls:[{name, super, description?}],
/// total }. Read-only.
ClassMethod ListDTLs() As %DynamicObject
{
    Set out = {}
    Set targetNs = ""
    Try { Set targetNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If targetNs = "" { Set targetNs = $namespace }
    Set out.namespace = targetNs
    Set out.dtls = []
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        // DTL classes extend Ens.DataTransformDTL. Walking
        // %Dictionary.CompiledClass with that filter is exact.
        Set sql = "SELECT Name, Super, Description FROM %Dictionary.CompiledClass "
        Set sql = sql _ "WHERE Super = 'Ens.DataTransformDTL' OR Super [ 'Ens.DataTransformDTL,' "
        Set sql = sql _ "OR Super [ ',Ens.DataTransformDTL' ORDER BY Name"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        Set count = 0
        While rs.%Next() {
            Set d = {}
            Set d.name = rs.%Get("Name")
            Set d.super = rs.%Get("Super")
            Set desc = rs.%Get("Description")
            If desc '= "" { Set d.description = $extract(desc, 1, 240) }
            Do out.dtls.%Push(d)
            Set count = count + 1
        }
        Set out.total = count
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Compile a Data Transformation Language (DTL) class so the next
/// interop run uses the latest source. Class-level action — the
/// confirmation gate intercepts calls whose name starts with
/// `compile_` so the user explicitly approves before IRIS recompiles
/// the class.
///
/// name: fully-qualified DTL class name (e.g.,
/// "Demo.Transform.ADT_to_SDA"). Pass the class, not the file path.
///
/// Returns: { ok, namespace, name, compiled, errors? }.
ClassMethod CompileDTL(name As %String) As %DynamicObject
{
    Set out = {}
    Set out.name = name
    Set targetNs = ""
    Try { Set targetNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If targetNs = "" { Set targetNs = $namespace }
    Set out.namespace = targetNs
    If $get(name) = "" {
        Set out.ok = 0
        Set out.compiled = 0
        Set out.error = "Empty class name — pass the fully-qualified DTL class as `name`."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(%Dictionary.ClassDefinition).%ExistsId(name) {
            Set out.ok = 0
            Set out.compiled = 0
            Set out.error = "Class not found in namespace " _ targetNs _ ": " _ name
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(name, "ck-d")
        If $$$ISERR(sc) {
            Set out.ok = 1
            Set out.compiled = 0
            Set out.errors = $extract($system.Status.GetErrorText(sc), 1, 1000)
            Quit
        }
        Set out.ok = 1
        Set out.compiled = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Create a Data Transformation Language (DTL) class and compile it.
/// MUTATING — gated by the create_ prefix.
///
/// IMPORTANT: For HL7-to-HL7 DTLs (sourceClass and targetClass are both
/// EnsLib.HL7.Message), you MUST call BuildDTLXml FIRST to generate the
/// dtlXml. DO NOT hand-write the XML — the virtual document paths are
/// complex nested group paths that differ per message structure and are
/// impossible to guess correctly. BuildDTLXml resolves them from the
/// schema automatically. Pass its returned dtlXml here.
///
/// name:        fully-qualified DTL class name (e.g.,
///              "Demo.Transform.ADT_to_SDA").
/// sourceClass: fully-qualified source class (e.g.,
///              "EnsLib.HL7.Message").
/// targetClass: fully-qualified target class.
/// sourceDocType: optional HL7 DocType for the source side
///              (e.g., "2.5:ADT_A01").
/// targetDocType: optional HL7 DocType for the target side.
/// dtlXml:      COMPLETE transform XML body. For HL7 DTLs, this MUST
///              come from BuildDTLXml. Pass the full
///              "<transform ...>...</transform>" XML with ALL field
///              mappings. Build ALL mappings in ONE call — do NOT call
///              update_dtl multiple times for individual fields.
ClassMethod CreateDTL(name As %String, sourceClass As %String, targetClass As %String, sourceDocType As %String = "", targetDocType As %String = "", dtlXml As %String = "") As %DynamicObject
{
    Set out = {}
    Set out.tool = "create_dtl"
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" || ($get(sourceClass) = "") || ($get(targetClass) = "") {
        Set out.ok = 0
        Set out.error = "Pass `name`, `sourceClass`, and `targetClass`."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If ##class(%Dictionary.ClassDefinition).%ExistsId(name) {
            Set out.ok = 1
            Set out.created = 0
            Set out.error = "Class already exists: " _ name _ ". Use update_dtl to replace its content."
            Quit
        }
        Set cdef = ##class(%Dictionary.ClassDefinition).%New(name)
        Set cdef.Super = "Ens.DataTransformDTL"
        Set cdef.ProcedureBlock = 1
        Set cdef.DependsOn = sourceClass _ "," _ targetClass
        Set xdata = ##class(%Dictionary.XDataDefinition).%New()
        Set xdata.Name = "DTL"
        Set xdata.XMLNamespace = "http://www.intersystems.com/dtl"
        If dtlXml '= "" {
            ; Full DTL body provided — validate HL7 paths before writing
            If (sourceClass [ "HL7") || (targetClass [ "HL7") {
                Set valResult = ..%ValidateHL7Paths(dtlXml, sourceDocType, targetDocType)
                If 'valResult.ok {
                    Set out.ok = 0
                    Set out.created = 0
                    Set out.error = valResult.error
                    Quit
                }
            }
            Do xdata.Data.Write(dtlXml)
        } Else {
            ; No body — build a minimal skeleton
            Set transformOpen = "<transform sourceClass=""" _ sourceClass _ """ targetClass=""" _ targetClass _ """"
            If sourceDocType '= "" { Set transformOpen = transformOpen _ " sourceDocType=""" _ sourceDocType _ """" }
            If targetDocType '= "" { Set transformOpen = transformOpen _ " targetDocType=""" _ targetDocType _ """" }
            Set transformOpen = transformOpen _ " create=""new"" language=""objectscript"">"
            Do xdata.Data.Write(transformOpen)
            Do xdata.Data.Write("<assign property='target' value='source' action='set' />")
            Do xdata.Data.Write("</transform>")
        }
        Do cdef.XDatas.Insert(xdata)
        Set sc = cdef.%Save()
        If 'sc {
            Set out.ok = 0
            Set out.created = 0
            Set out.error = "%Save failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(name, "ck-d")
        If 'sc {
            Set out.ok = 0
            Set out.created = 0
            Set out.compileError = $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.created = 1
        If dtlXml '= "" {
            Set out.message = "DTL '" _ name _ "' created with full mappings and compiled."
        } Else {
            Set out.message = "DTL '" _ name _ "' created with empty mapping. Use update_dtl to add field mappings."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Replace the body of a DTL class's <transform> XData and recompile.
/// MUTATING — gated by the update_ prefix.
///
/// IMPORTANT: For HL7-to-HL7 DTLs, DO NOT hand-write the dtlXml.
/// Call BuildDTLXml first to generate correct XML with validated
/// virtual document paths. Hand-written paths will be rejected by
/// the path validator if they do not match the HL7 schema.
///
/// name:    fully-qualified DTL class name.
/// dtlXml:  full XML body of XData DTL — typically starts with
///          "<transform sourceClass=...>" and ends with "</transform>".
ClassMethod UpdateDTL(name As %String, dtlXml As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "update_dtl"
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" || ($get(dtlXml) = "") {
        Set out.ok = 0
        Set out.error = "Pass `name` and `dtlXml`."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(%Dictionary.ClassDefinition).%ExistsId(name) {
            Set out.ok = 1
            Set out.updated = 0
            Set out.error = "Class not found: " _ name
            Quit
        }
        Set cdef = ##class(%Dictionary.ClassDefinition).%OpenId(name)
        Set xdata = ""
        For i=1:1:cdef.XDatas.Count() {
            Set candidate = cdef.XDatas.GetAt(i)
            If candidate.Name = "DTL" { Set xdata = candidate Quit }
        }
        If '$isobject(xdata) {
            Set xdata = ##class(%Dictionary.XDataDefinition).%New()
            Set xdata.Name = "DTL"
            Set xdata.XMLNamespace = "http://www.intersystems.com/dtl"
            Do cdef.XDatas.Insert(xdata)
        }
        ; Validate HL7 paths if the DTL involves HL7 messages
        Set srcDocType = ""
        Set tgtDocType = ""
        If dtlXml [ "sourceDocType" {
            ; Extract docTypes from the XML attributes
            Set srcDocType = ..%ExtractAttr(dtlXml, "sourceDocType")
            Set tgtDocType = ..%ExtractAttr(dtlXml, "targetDocType")
        }
        If dtlXml [ "EnsLib.HL7.Message" {
            Set valResult = ..%ValidateHL7Paths(dtlXml, srcDocType, tgtDocType)
            If 'valResult.ok {
                Set out.ok = 0
                Set out.updated = 0
                Set out.error = valResult.error
                Quit
            }
        }
        Do xdata.Data.Clear()
        Do xdata.Data.Write(dtlXml)
        Set sc = cdef.%Save()
        If 'sc {
            Set out.ok = 0
            Set out.updated = 0
            Set out.error = "%Save failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(name, "ck-d")
        If 'sc {
            Set out.ok = 0
            Set out.updated = 0
            Set out.compileError = $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.updated = 1
        Set out.message = "DTL '" _ name _ "' updated and recompiled."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Run a DTL transformation in-process and return the result. CALL
/// THIS to test "does my DTL produce X for Y" without standing up a
/// full production. Read-only with respect to IRIS state, but the
/// underlying DTL may have side effects (e.g., writing to a lookup
/// table) — those still happen.
///
/// Source-input forms supported:
///   - JSON object → sourceJson: passes the dynamic object directly
///     to the transform; works when the DTL's source class accepts
///     a dynamic shape (rare — most need a typed instance).
///   - HL7 v2 string → sourceText: parsed via EnsLib.HL7.Message.
///     The DTL must declare sourceClass="EnsLib.HL7.Message".
///   - SDA / FHIR JSON → not yet supported as a typed source. Use
///     describe_class on the DTL to see what it expects, then post
///     manually for now.
///
/// name:       fully-qualified DTL class.
/// sourceText: raw input text (HL7 message or similar). Optional.
/// sourceJson: %DynamicObject input. Optional.
///
/// Returns: { ok, output? (string), outputJson? (object), error? }.
ClassMethod DryRunDTL(name As %String, sourceText As %String = "", sourceJson As %DynamicObject = "") As %DynamicObject
{
    Set out = {}
    Set out.tool = "dry_run_dtl"
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" {
        Set out.ok = 0
        Set out.error = "Pass `name` (the DTL class)."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(%Dictionary.CompiledClass).%ExistsId(name) {
            Set out.ok = 0
            Set out.error = "DTL class not compiled or not found: " _ name
            Quit
        }
        // Get the source class via the DTL's GetSourceType ClassMethod
        // (every DTL gets one auto-generated). Falls back to inspecting
        // the XData if the method isn't present yet.
        Set sourceClass = ""
        Try { Set sourceClass = $classmethod(name, "GetSourceType") } Catch  {}
        If sourceClass = "" {
            Set out.ok = 0
            Set out.error = "Cannot determine source type for DTL " _ name _ "; recompile it first."
            Quit
        }
        Set source = ""
        // HL7 message path
        If sourceClass = "EnsLib.HL7.Message", $get(sourceText) '= "" {
            Set scH = $$$OK
            Set source = ##class(EnsLib.HL7.Message).ImportFromString(sourceText, .scH)
            If $$$ISERR(scH) {
                Set out.ok = 0
                Set out.error = "Source HL7 parse failed: " _ $system.Status.GetErrorText(scH)
                Quit
            }
        } ElseIf $isobject(sourceJson) {
            // JSON path — only useful if source class is a %JSON.Adaptor /
            // %DynamicObject-friendly class.
            Try {
                Set source = $classmethod(sourceClass, "%New")
                If ##class(%Dictionary.CompiledMethod).%ExistsId(sourceClass _ "||%JSONImport") {
                    Do source.%JSONImport(sourceJson)
                }
            } Catch  {
                Set out.ok = 0
                Set out.error = "Cannot construct source class " _ sourceClass _ " from JSON. Pass sourceText for HL7 sources."
                Quit
            }
        } Else {
            Set out.ok = 0
            Set out.error = "Provide sourceText (for HL7) or sourceJson (for JSON-friendly source classes). The DTL expects: " _ sourceClass
            Quit
        }
        // Run the transform. DTL.Transform is the standard entry point.
        Set target = ""
        Set sc = $classmethod(name, "Transform", source, .target)
        If $$$ISERR(sc) {
            Set out.ok = 0
            Set out.error = "Transform failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        ; Render result
        If $isobject(target) {
            Set targetCls = $classname(target)
            Set out.targetClass = targetCls
            ; HL7 message — render to string via OutputToString
            If target.%IsA("EnsLib.HL7.Message") {
                Try {
                    Set scOut = $$$OK
                    Set out.output = target.OutputToString("|^~\&", .scOut)
                } Catch {}
            }
            ; JSON adaptor — export (only for non-HL7 targets)
            ElseIf target.%IsA("%JSON.Adaptor") {
                Try {
                    Set jstream = ##class(%Stream.TmpCharacter).%New()
                    Do target.%JSONExportToStream(jstream)
                    Do jstream.Rewind()
                    Set jbody = ""
                    While 'jstream.AtEnd { Set jbody = jbody _ jstream.Read(8192) }
                    Set out.outputJson = ##class(%DynamicAbstractObject).%FromJSON(jbody)
                } Catch {}
            }
            ; Fallback — try OutputToString for any other virtual doc
            ElseIf ##class(%Dictionary.CompiledMethod).%ExistsId(targetCls _ "||OutputToString") {
                Try {
                    Set scOut = $$$OK
                    Set out.output = target.OutputToString(, .scOut)
                } Catch {}
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// List the lookup tables defined in the active namespace. Lookup
/// tables are key/value pairs DTLs and routing rules consult via
/// ..Lookup() — the agent should know what tables exist before
/// suggesting a Lookup() reference. CALL THIS for "what lookup
/// tables do we have", "is there a table for X". Read-only.
///
/// Returns: { ok, namespace, tables:[{name, entries}], total }.
ClassMethod ListLookupTables() As %DynamicObject
{
    Set out = {}
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    Set out.tables = []
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        // Ens_Util.LookupTable holds the rows; group by TableName.
        Set sql = "SELECT TableName, COUNT(*) AS Entries FROM Ens_Util.LookupTable GROUP BY TableName ORDER BY TableName"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        Set count = 0
        While rs.%Next() {
            Set t = {}
            Set t.name = rs.%Get("TableName")
            Set t.entries = rs.%Get("Entries")
            Do out.tables.%Push(t)
            Set count = count + 1
        }
        Set out.total = count
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Create a Business Process Language (BPL) class skeleton. The
/// generated class extends Ens.BusinessProcessBPL and contains an
/// empty <process> XData with an empty <sequence>. The user (or a
/// follow-up tool) fills in the activities. MUTATING — gated by
/// the create_ prefix.
///
/// name:           fully-qualified BPL class name.
/// requestClass:   request message class (default "Ens.Request").
/// responseClass:  response message class (default "Ens.Response").
ClassMethod CreateBPL(name As %String, requestClass As %String = "Ens.Request", responseClass As %String = "Ens.Response") As %DynamicObject
{
    Set out = {}
    Set out.tool = "create_bpl"
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" {
        Set out.ok = 0
        Set out.error = "Pass `name` (the BPL class)."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If ##class(%Dictionary.ClassDefinition).%ExistsId(name) {
            Set out.ok = 1
            Set out.created = 0
            Set out.error = "Class already exists: " _ name
            Quit
        }
        Set cdef = ##class(%Dictionary.ClassDefinition).%New(name)
        Set cdef.Super = "Ens.BusinessProcessBPL"
        Set cdef.ProcedureBlock = 1
        Set xdata = ##class(%Dictionary.XDataDefinition).%New()
        Set xdata.Name = "BPL"
        Set xdata.XMLNamespace = "http://www.intersystems.com/bpl"
        // Minimal valid BPL — an empty sequence inside the process.
        // The user's editor (or a follow-up update tool) adds activities.
        Do xdata.Data.Write("<process language='objectscript' request='" _ requestClass _ "' response='" _ responseClass _ "' height='2000' width='2000'>")
        Do xdata.Data.Write("<sequence xend='200' yend='350'/>")
        Do xdata.Data.Write("</process>")
        Do cdef.XDatas.Insert(xdata)
        Set sc = cdef.%Save()
        If 'sc {
            Set out.ok = 0
            Set out.created = 0
            Set out.error = "%Save failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(name, "ck-d")
        If 'sc {
            Set out.ok = 0
            Set out.created = 0
            Set out.compileError = $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.created = 1
        Set out.message = "BPL '" _ name _ "' created (empty sequence). Use the BPL editor or update_bpl (roadmap) to add activities."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Compile a BPL class to verify its <process> XML is well-formed
/// and references resolve. MUTATING (recompile is a class action) —
/// gated by the validate_ prefix. Same mechanism as compile_dtl,
/// just scoped to BPL classes.
///
/// name: fully-qualified BPL class name.
ClassMethod ValidateBPL(name As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "validate_bpl"
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" {
        Set out.ok = 0
        Set out.valid = 0
        Set out.error = "Pass `name`."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(%Dictionary.ClassDefinition).%ExistsId(name) {
            Set out.ok = 1
            Set out.valid = 0
            Set out.error = "Class not found: " _ name
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(name, "ck-d")
        If 'sc {
            Set out.ok = 1
            Set out.valid = 0
            Set out.errors = $extract($system.Status.GetErrorText(sc), 1, 1500)
            Quit
        }
        Set out.ok = 1
        Set out.valid = 1
        Set out.message = "BPL '" _ name _ "' compiled cleanly."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Discover existing SDA-to-FHIR and FHIR-to-SDA DTL classes in the
/// active namespace. These are the BUILT-IN transformation DTLs that
/// ship with IRIS for Health — the agent MUST check these before
/// creating custom DTLs. CALL THIS FIRST whenever the user asks to
/// build HL7-to-FHIR, SDA-to-FHIR, or FHIR-to-SDA pipelines.
///
/// direction: "sda2fhir" (default), "fhir2sda", or "both".
/// fhirVersion: "vR4" (default), "vSTU3", or "all".
/// filter: optional substring filter on DTL class name (e.g., "Patient",
///         "Encounter", "Observation").
///
/// Returns: { ok, namespace, direction, dtls:[{name, sourceClass,
/// targetClass, description?}], total }. Read-only.
ClassMethod ListSDAFHIRDTLs(direction As %String = "sda2fhir", fhirVersion As %String = "vR4", filter As %String = "") As %DynamicObject
{
    Set out = {}
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    Set out.direction = direction
    Set out.dtls = []
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        ; Build the WHERE clause based on direction + version
        Set patterns = ""
        Set dir = $zconvert($get(direction, "sda2fhir"), "L")
        Set ver = $get(fhirVersion, "vR4")
        If ver = "all" { Set ver = "" }
        If (dir = "sda2fhir") || (dir = "both") {
            ; SDA3 to FHIR: HS.FHIR.DTL.SDA3.vR4.*
            Set pkg = "HS.FHIR.DTL.SDA3." _ ver
            If ver = "" { Set pkg = "HS.FHIR.DTL.SDA3." }
            Set patterns = patterns _ $select(patterns'="": " OR ", 1:"") _ "Name LIKE '" _ pkg _ "%'"
            ; Also check HS.Local custom DTLs
            Set localPkg = "HS.Local.FHIR.DTL.SDA3." _ ver
            If ver = "" { Set localPkg = "HS.Local.FHIR.DTL.SDA3." }
            Set patterns = patterns _ " OR Name LIKE '" _ localPkg _ "%'"
        }
        If (dir = "fhir2sda") || (dir = "both") {
            ; FHIR to SDA3: HS.FHIR.DTL.vR4.SDA3.*
            Set pkg = "HS.FHIR.DTL." _ ver _ ".SDA3."
            If ver = "" { Set pkg = "HS.FHIR.DTL.v" }
            Set patterns = patterns _ $select(patterns'="": " OR ", 1:"") _ "Name LIKE '" _ pkg _ "%'"
            ; Also check HS.Local
            Set localPkg = "HS.Local.FHIR.DTL." _ ver _ ".SDA3."
            If ver = "" { Set localPkg = "HS.Local.FHIR.DTL.v" }
            Set patterns = patterns _ " OR Name LIKE '" _ localPkg _ "%'"
        }
        If patterns = "" {
            Set out.ok = 0
            Set out.error = "Invalid direction. Use 'sda2fhir', 'fhir2sda', or 'both'."
            Quit
        }
        Set sql = "SELECT Name, Super, Description FROM %Dictionary.CompiledClass "
        Set sql = sql _ "WHERE (" _ patterns _ ") "
        Set sql = sql _ "AND (Super [ 'Ens.DataTransformDTL' OR Super [ 'HS.FHIR.DTL') "
        If $get(filter) '= "" {
            Set sql = sql _ "AND Name LIKE '%" _ $zstrip(filter, "<>W") _ "%' "
        }
        Set sql = sql _ "ORDER BY Name"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        Set count = 0
        While rs.%Next() {
            Set d = {}
            Set d.name = rs.%Get("Name")
            Set desc = rs.%Get("Description")
            If desc '= "" { Set d.description = $extract(desc, 1, 300) }
            Do out.dtls.%Push(d)
            Set count = count + 1
        }
        Set out.total = count
        Set out.ok = 1
        If count = 0 {
            Set out.message = "No SDA-FHIR DTLs found. This namespace may not have the HS.FHIR.DTL package installed. Check if this is a Foundation/FHIR-enabled namespace."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Recommend the correct transformation pipeline for converting
/// between healthcare data formats (HL7 v2, SDA3, FHIR R4, CDA).
/// Returns the specific IRIS classes needed at each stage.
/// CALL THIS when the user asks "how do I convert X to Y" or
/// "build me an X-to-Y pipeline". Read-only.
///
/// sourceFormat: "hl7v2", "sda3", "fhir", "cda".
/// targetFormat: "hl7v2", "sda3", "fhir", "cda".
///
/// Returns: { ok, pipeline:[{step, class, role, notes}], summary,
/// productionHosts:[{class, role, keySettings}] }.
ClassMethod DescribeTransformationPipeline(sourceFormat As %String, targetFormat As %String) As %DynamicObject
{
    Set out = {}
    Set out.sourceFormat = $get(sourceFormat)
    Set out.targetFormat = $get(targetFormat)
    Set out.pipeline = []
    Set out.productionHosts = []
    If $get(sourceFormat) = "" || ($get(targetFormat) = "") {
        Set out.ok = 0
        Set out.error = "Pass `sourceFormat` and `targetFormat`. Valid values: hl7v2, sda3, fhir, cda."
        Quit out
    }
    Set src = $zconvert(sourceFormat, "L")
    Set tgt = $zconvert(targetFormat, "L")
    Try {
        ; HL7 v2 -> FHIR (the most common pipeline)
        If (src = "hl7v2") && (tgt = "fhir") {
            Set step1 = {}
            Set step1.step = 1
            Set step1.class = "HS.Gateway.HL7.HL7ToSDA3"
            Set step1.role = "HL7 v2 to SDA3 conversion"
            Set step1.notes = "UTILITY CLASS (%RegisteredObject, NOT a business process — do NOT add as a production host). Call ##class(HS.Gateway.HL7.HL7ToSDA3).GetSDA(request, .sdaContainer) inside a custom BPL <code> block. Input: EnsLib.HL7.Message. Output: HS.SDA3.Container. The custom BPL wraps the SDA container into an HS.Message.XMLMessage and routes it to the SDA-to-FHIR process."
            Do out.pipeline.%Push(step1)
            Set step2 = {}
            Set step2.step = 2
            Set step2.class = "HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process"
            Set step2.role = "SDA3 to FHIR R4 transformation"
            Set step2.notes = "Business process. Input: HS.Message.XMLMessage or Ens.Container with SDA stream. Output: FHIR bundle sent to TargetConfigName. Key settings: TransmissionMode, FHIRFormat, FHIRMetadataSet, FHIREndpoint."
            Do out.pipeline.%Push(step2)
            Set out.summary = "HL7 v2 to FHIR R4 uses a two-stage pipeline: HL7 to SDA3 (via HS.Gateway.HL7.HL7ToSDA3.GetSDA) then SDA3 to FHIR (via HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process). A custom BPL connects the two stages. The system ships with built-in SDA-to-FHIR DTLs under HS.FHIR.DTL.SDA3.vR4.* — search with ListSDAFHIRDTLs before writing custom DTLs."
            ; Production hosts
            Set h1 = {} Set h1.class = "EnsLib.HL7.Service.TCPService" Set h1.role = "HL7 MLLP inbound"
            Set h1.keySettings = "Host: TargetConfigNames, MessageSchemaCategory. Adapter: Port, JobPerConnection."
            Do out.productionHosts.%Push(h1)
            Set h2 = {} Set h2.class = "Custom BPL (Ens.BusinessProcessBPL)" Set h2.role = "HL7-to-SDA conversion + routing to FHIR process"
            Set h2.keySettings = "Custom code calls HS.Gateway.HL7.HL7ToSDA3.GetSDA(), wraps result into HS.Message.XMLMessage, sends to SDA-to-FHIR process."
            Do out.productionHosts.%Push(h2)
            Set h3 = {} Set h3.class = "HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process" Set h3.role = "SDA3 to FHIR R4 transformation"
            Set h3.keySettings = "TargetConfigName, FHIRMetadataSet, FHIREndpoint, TransmissionMode."
            Do out.productionHosts.%Push(h3)
            Set h4 = {} Set h4.class = "HS.FHIRServer.Interop.Operation or HS.FHIRServer.Interop.HTTPOperation" Set h4.role = "FHIR outbound"
            Set h4.keySettings = "Internal: FHIREndpoint on upstream process. External: HTTPServer, URL, SSLConfig."
            Do out.productionHosts.%Push(h4)
        }
        ; FHIR -> HL7 v2
        ElseIf (src = "fhir") && (tgt = "hl7v2") {
            Set step1 = {}
            Set step1.step = 1
            Set step1.class = "HS.FHIR.DTL.Util.HC.FHIR.SDA3.Process"
            Set step1.role = "FHIR R4 to SDA3 conversion"
            Set step1.notes = "Business process. Input: FHIR resource or bundle. Output: HS.Message.XMLMessage with SDA3 stream."
            Do out.pipeline.%Push(step1)
            Set step2 = {}
            Set step2.step = 2
            Set step2.class = "HS.Gateway.SDA3.SDA3ToHL7.* (per-message-type DTLs)"
            Set step2.role = "SDA3 to HL7 v2 conversion"
            Set step2.notes = "Per-message-type DTL classes: HS.Gateway.SDA3.SDA3ToHL7.ADTA0N (ADT), .ORUR01 (ORU), .VXUV04 (VXU). Use in a custom BPL code block or Ens.DataTransform host. Sub-transforms exist for individual segments (PID, PV1, OBR, OBX, etc.)."
            Do out.pipeline.%Push(step2)
            Set out.summary = "FHIR to HL7 v2 uses two stages: FHIR to SDA3 (via HS.FHIR.DTL.Util.HC.FHIR.SDA3.Process) then SDA3 to HL7 v2 (via per-message-type DTLs under HS.Gateway.SDA3.SDA3ToHL7.* — pick the DTL matching your target HL7 message type, e.g., ADTA0N for ADT, ORUR01 for ORU)."
        }
        ; SDA3 -> FHIR
        ElseIf (src = "sda3") && (tgt = "fhir") {
            Set step1 = {}
            Set step1.step = 1
            Set step1.class = "HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process"
            Set step1.role = "SDA3 to FHIR R4 transformation"
            Set step1.notes = "Business process. Input: HS.Message.XMLMessage with SDA stream. Output: FHIR bundle. Or use API: HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR.TransformStream() for programmatic use."
            Do out.pipeline.%Push(step1)
            Set out.summary = "SDA3 to FHIR is a single-step conversion via HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process (production) or HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR (API)."
        }
        ; FHIR -> SDA3
        ElseIf (src = "fhir") && (tgt = "sda3") {
            Set step1 = {}
            Set step1.step = 1
            Set step1.class = "HS.FHIR.DTL.Util.HC.FHIR.SDA3.Process"
            Set step1.role = "FHIR R4 to SDA3 conversion"
            Set step1.notes = "Business process. Or use API: HS.FHIR.DTL.Util.API.Transform.FHIRToSDA3.TransformObject() for programmatic use."
            Do out.pipeline.%Push(step1)
            Set out.summary = "FHIR to SDA3 is a single-step conversion via HS.FHIR.DTL.Util.HC.FHIR.SDA3.Process (production) or HS.FHIR.DTL.Util.API.Transform.FHIRToSDA3 (API)."
        }
        ; HL7 v2 -> SDA3
        ElseIf (src = "hl7v2") && (tgt = "sda3") {
            Set step1 = {}
            Set step1.step = 1
            Set step1.class = "HS.Gateway.HL7.HL7ToSDA3"
            Set step1.role = "HL7 v2 to SDA3 conversion"
            Set step1.notes = "UTILITY CLASS (%RegisteredObject, NOT a business process — do NOT add as a production host). Call programmatically inside a custom BPL code block: Set sc = ##class(HS.Gateway.HL7.HL7ToSDA3).GetSDA(request, .sdaContainer). Input: EnsLib.HL7.Message. Output: HS.SDA3.Container (returned by reference)."
            Do out.pipeline.%Push(step1)
            Set out.summary = "HL7 v2 to SDA3: call ##class(HS.Gateway.HL7.HL7ToSDA3).GetSDA(request, .sdaContainer) inside a custom BPL code block. This is a utility class, NOT a business process — cannot be added as a production host."
        }
        ; SDA3 -> HL7 v2
        ElseIf (src = "sda3") && (tgt = "hl7v2") {
            Set step1 = {}
            Set step1.step = 1
            Set step1.class = "HS.Gateway.SDA3.SDA3ToHL7.* (per-message-type DTLs)"
            Set step1.role = "SDA3 to HL7 v2 conversion"
            Set step1.notes = "Per-message-type DTL classes — there is NO single SDA3-to-HL7v2 converter. Available DTLs: HS.Gateway.SDA3.SDA3ToHL7.ADTA0N (ADT A01/A02/A04/etc.), .ADTA0NA03 (ADT A03), .ORUR01 (ORU R01), .VXUV04 (VXU V04). Sub-transforms exist for individual segments under HS.Gateway.SDA3.SDA3ToHL7.SubTransform.* (PatientToPID, EncounterToPV1, LabResultToOBX, etc.). Use the appropriate DTL in a custom BPL or Ens.DataTransform host."
            Do out.pipeline.%Push(step1)
            Set out.summary = "SDA3 to HL7 v2: use per-message-type DTLs under HS.Gateway.SDA3.SDA3ToHL7.* — e.g., .ADTA0N for ADT, .ORUR01 for ORU, .VXUV04 for VXU. There is NO single SDA3-to-HL7v2 converter class."
        }
        ; CDA -> FHIR (via SDA)
        ElseIf (src = "cda") && (tgt = "fhir") {
            Set step1 = {} Set step1.step = 1 Set step1.class = "HS.Doc.Mapping.CDAToSDAMapper" Set step1.role = "CDA to SDA3"
            Set step1.notes = "Utility mapper class — parses CDA document into SDA3 container. Call programmatically or wrap in a custom BPL."
            Do out.pipeline.%Push(step1)
            Set step2 = {} Set step2.step = 2 Set step2.class = "HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process" Set step2.role = "SDA3 to FHIR R4"
            Set step2.notes = "Standard SDA-to-FHIR business process."
            Do out.pipeline.%Push(step2)
            Set out.summary = "CDA to FHIR goes through SDA: CDA to SDA3 (HS.Doc.Mapping.CDAToSDAMapper) then SDA3 to FHIR (HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process)."
        }
        ; Same format
        ElseIf src = tgt {
            Set out.summary = "Source and target are the same format. No transformation needed."
        }
        Else {
            Set out.summary = "No standard pipeline for " _ sourceFormat _ " to " _ targetFormat _ ". SDA3 is the hub — convert source to SDA3 first, then SDA3 to target. Search the HS.* catalog for relevant classes."
        }
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Check whether a custom DTL package is configured in the active
/// namespace and return its name. CALL THIS when the user wants to
/// customize SDA-FHIR transformations to know if a custom package
/// already exists. Read-only.
///
/// Returns: { ok, namespace, customPackage, configured }.
ClassMethod GetCustomDTLPackage() As %DynamicObject
{
    Set out = {}
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set pkg = ""
        Try { Set pkg = ##class(HS.FHIR.DTL.Util.API.ExecDefinition).GetCustomDTLPackage() } Catch  {}
        Set out.customPackage = pkg
        Set out.configured = (pkg '= "")
        Set out.ok = 1
        If pkg = "" {
            Set out.message = "No custom DTL package configured. To set one: do ##class(HS.FHIR.DTL.Util.API.ExecDefinition).SetCustomDTLPackage(""HS.Local.FHIR.DTL"")"
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Generate complete, compilable DTL XML from a list of field mapping
/// instructions. This tool resolves the correct virtual-document paths
/// internally using the HL7 schema — the agent does NOT need to know
/// or guess the nested group paths (PIDgrpgrp, ORCgrp, OBXgrp, etc.).
///
/// CALL THIS instead of manually assembling DTL XML. The agent describes
/// WHAT to map; this tool handles HOW (correct paths, correct XML syntax).
///
/// After this tool returns the XML, pass it to CreateDTL as the dtlXml
/// parameter. Do NOT call UpdateDTL multiple times for individual fields.
///
/// sourceDocType:  e.g. "2.5:ADT_A01"
/// targetDocType:  e.g. "2.5:ORU_R01"
/// mappingsJson:   JSON array of mapping objects. Each mapping is one of:
///   { "action": "copy-segment", "sourceSegment": "MSH", "targetSegment": "MSH" }
///     Copy all fields from a source segment to the same-type target segment.
///   { "action": "set", "targetPath": "MSH:MessageType.MessageCode", "value": "\"ORU\"" }
///     Set a literal value. value is an ObjectScript expression (quote strings).
///   { "action": "copy-field", "sourcePath": "PID:PatientIdentifierList(1)", "targetPath": "OBR:FillerOrderNumber" }
///     Copy one field from source to target.
///   { "action": "copy-all-components", "sourcePath": "PV1:AttendingDoctor", "targetPath": "OBR:OrderingProvider" }
///     Copy a complex field with all its sub-components.
///   { "action": "concat", "targetPath": "OBX:ObservationValue", "parts": ["PID:PatientName.FamilyName.Surname", "PID:PatientName.GivenName", "PID:PatientName.SecondandFurtherGivenNamesor"], "separator": " " }
///     Concatenate multiple source fields into one target field.
///   { "action": "code", "objectscript": " set target.{...} = ..." }
///     Raw ObjectScript code block. Use sparingly.
/// createMode:     "new" (default) or "copy". Use "copy" when source and
///                 target are the same message type and you only change a few fields.
///
/// Returns: { ok, dtlXml, segmentPathsUsed, warnings? }
ClassMethod BuildDTLXml(sourceDocType As %String, targetDocType As %String, mappingsJson As %String, createMode As %String = "new") As %DynamicObject
{
    Set out = {}
    Set out.tool = "build_dtl_xml"
    If $get(sourceDocType) = "" || ($get(targetDocType) = "") || ($get(mappingsJson) = "") {
        Set out.ok = 0
        Set out.error = "Pass sourceDocType, targetDocType, and mappingsJson."
        Return out
    }
    Try {
        ; Parse the doc types: "2.5:ADT_A01" -> category "2.5", structure "ADT_A01"
        Set srcCat = $piece(sourceDocType, ":", 1)
        Set srcMS  = $piece(sourceDocType, ":", 2)
        Set tgtCat = $piece(targetDocType, ":", 1)
        Set tgtMS  = $piece(targetDocType, ":", 2)
        ; Build segment-type -> dtlPath maps for source and target
        ; srcMap("PID") = "PID"                (for ADT_A01 — flat)
        ; tgtMap("PID") = "PIDgrpgrp(1).PIDgrp.PID"  (for ORU_R01 — nested)
        Kill srcMap, tgtMap
        Do ..%BuildSegMap(srcCat, srcMS, .srcMap)
        Do ..%BuildSegMap(tgtCat, tgtMS, .tgtMap)
        ; Parse the mappings JSON
        Set mappings = ""
        If $isobject(mappingsJson) {
            Set mappings = mappingsJson
        } Else {
            Set mappings = ##class(%DynamicAbstractObject).%FromJSON(mappingsJson)
        }
        If '$isobject(mappings) || ('mappings.%IsA("%DynamicArray")) {
            Set out.ok = 0
            Set out.error = "mappingsJson must be a JSON array."
            Return out
        }
        ; Build the XML
        Set xml = "<transform sourceClass=""EnsLib.HL7.Message"" targetClass=""EnsLib.HL7.Message"""
        Set xml = xml _ " sourceDocType=""" _ sourceDocType _ """ targetDocType=""" _ targetDocType _ """"
        Set xml = xml _ " create=""" _ $get(createMode, "new") _ """ language=""objectscript"">"
        Set warnings = []
        Set pathsUsed = []
        ; Process each mapping
        Set iter = mappings.%GetIterator()
        While iter.%GetNext(.idx, .m) {
            Set action = m.action
            If action = "copy-segment" {
                ; Copy entire segment: source.{srcPath:} -> target.{tgtPath:}
                Set srcSeg = m.sourceSegment
                Set tgtSeg = m.targetSegment
                Set srcPath = ..%ResolveSegPath(srcSeg, .srcMap)
                Set tgtPath = ..%ResolveSegPath(tgtSeg, .tgtMap)
                If srcPath = "" { Do warnings.%Push("Source segment not found: " _ srcSeg) Continue }
                If tgtPath = "" { Do warnings.%Push("Target segment not found: " _ tgtSeg) Continue }
                Set xml = xml _ "<assign property='target.{" _ tgtPath _ "}' value='source.{" _ srcPath _ "}' action='set'/>"
                Do pathsUsed.%Push("source.{" _ srcPath _ "} -> target.{" _ tgtPath _ "}")
            }
            ElseIf action = "set" {
                ; Set literal value on target
                Set tgtField = m.targetPath
                Set val = m.value
                ; Resolve the segment from the field path (e.g., "MSH:MessageType" -> segment "MSH")
                ; Handles repetition indices: "OBX(1):SetIDOBX" -> seg "OBX(1)" -> bare "OBX"
                Set tgtSeg = $piece(tgtField, ":", 1)
                Set tgtSegPath = ..%ResolveSegPath(tgtSeg, .tgtMap)
                If tgtSegPath = "" { Do warnings.%Push("Target segment not found for: " _ tgtField) Continue }
                Set fieldPart = $piece(tgtField, ":", 2, 99)
                Set fullTgt = tgtSegPath _ ":" _ fieldPart
                Set xml = xml _ "<assign property='target.{" _ fullTgt _ "}' value='" _ $replace(val, "'", "&apos;") _ "' action='set'/>"
                Do pathsUsed.%Push("target.{" _ fullTgt _ "} = " _ val)
            }
            ElseIf (action = "copy-field") || (action = "copy-all-components") {
                ; Copy a field from source to target
                Set srcField = m.sourcePath
                Set tgtField = m.targetPath
                Set srcSeg = $piece(srcField, ":", 1)
                Set tgtSeg = $piece(tgtField, ":", 1)
                Set srcSegPath = ..%ResolveSegPath(srcSeg, .srcMap)
                Set tgtSegPath = ..%ResolveSegPath(tgtSeg, .tgtMap)
                If srcSegPath = "" { Do warnings.%Push("Source segment not found for: " _ srcField) Continue }
                If tgtSegPath = "" { Do warnings.%Push("Target segment not found for: " _ tgtField) Continue }
                Set srcFieldPart = $piece(srcField, ":", 2, 99)
                Set tgtFieldPart = $piece(tgtField, ":", 2, 99)
                Set fullSrc = srcSegPath _ ":" _ srcFieldPart
                Set fullTgt = tgtSegPath _ ":" _ tgtFieldPart
                Set xml = xml _ "<assign property='target.{" _ fullTgt _ "}' value='source.{" _ fullSrc _ "}' action='set'/>"
                Do pathsUsed.%Push("source.{" _ fullSrc _ "} -> target.{" _ fullTgt _ "}")
            }
            ElseIf action = "concat" {
                ; Concatenate multiple source fields with a separator
                Set tgtField = m.targetPath
                Set parts = m.parts
                Set sep = m.separator
                If sep = "" { Set sep = " " }
                Set tgtSeg = $piece(tgtField, ":", 1)
                Set tgtSegPath = ..%ResolveSegPath(tgtSeg, .tgtMap)
                If tgtSegPath = "" { Do warnings.%Push("Target segment not found for: " _ tgtField) Continue }
                Set tgtFieldPart = $piece(tgtField, ":", 2, 99)
                Set fullTgt = tgtSegPath _ ":" _ tgtFieldPart
                ; Build concatenation expression
                Set expr = ""
                Set pIter = parts.%GetIterator()
                While pIter.%GetNext(.pi, .part) {
                    Set pSeg = $piece(part, ":", 1)
                    Set pSegPath = ..%ResolveSegPath(pSeg, .srcMap)
                    If pSegPath = "" { Do warnings.%Push("Source segment not found for concat part: " _ part) Continue }
                    Set pFieldPart = $piece(part, ":", 2, 99)
                    Set fullPart = pSegPath _ ":" _ pFieldPart
                    If expr '= "" { Set expr = expr _ "_""" _ sep _ """_" }
                    Set expr = expr _ "source.{" _ fullPart _ "}"
                }
                Set xml = xml _ "<assign property='target.{" _ fullTgt _ "}' value='" _ $replace(expr, "'", "&apos;") _ "' action='set'/>"
                Do pathsUsed.%Push("concat -> target.{" _ fullTgt _ "}")
            }
            ElseIf action = "code" {
                ; Raw ObjectScript code block
                Set code = m.objectscript
                Set xml = xml _ "<code><![CDATA[" _ code _ "]]></code>"
                Do pathsUsed.%Push("code block")
            }
            Else {
                Do warnings.%Push("Unknown action: " _ action)
            }
        }
        Set xml = xml _ "</transform>"
        Set out.ok = 1
        Set out.dtlXml = xml
        Set out.segmentPathsUsed = pathsUsed
        If warnings.%Size() > 0 {
            Set out.warnings = warnings
        }
        Set out.hint = "Pass the dtlXml value to CreateDTL as the dtlXml parameter. The XML has the correct virtual document paths for " _ sourceDocType _ " -> " _ targetDocType _ "."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 600)
    }
    Return out
}

/// Internal helper: build a segment-type -> dtlPath lookup array
/// from the HL7 schema map. Called by BuildDTLXml.
ClassMethod %BuildSegMap(category As %String, messageStructure As %String, ByRef segMap) [ Internal ]
{
    Kill segMap
    Set key = ""
    For {
        Set key = $order(^EnsHL7.Schema(category, "MS", messageStructure, "map", key))
        Quit:key=""
        If key = "leftoversegs" Continue
        Set mapVal = $get(^EnsHL7.Schema(category, "MS", messageStructure, "map", key))
        Set segType = $piece($piece(mapVal, "|", 2), ":", 2)
        ; Replace () with (1) for DTL paths
        Set dtlPath = $replace(key, "()", "(1)")
        ; Only store the FIRST occurrence of each segment type
        ; (the agent can specify (2), (3) explicitly if needed)
        If '$data(segMap(segType)) {
            Set segMap(segType) = dtlPath
        }
    }
}

/// Internal helper: resolve a segment name (possibly with a repetition
/// index like "OBX(1)") against a segMap built by %BuildSegMap.
///
/// HL7 VDoc path rules:
///   - Repetition indices go on the GROUP, not the segment.
///   - "OBX(1)" means "the first OBXgrp's OBX segment" — the (1) is
///     on OBXgrp, not on OBX itself.
///   - segMap already stores the default path with (1) on all groups:
///     segMap("OBX") = "PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX"
///
/// When the agent writes OBX(N) with N > 1, we adjust the parent group
/// index (OBXgrp(1) -> OBXgrp(N)). For OBX(1) or bare OBX, we return
/// the segMap path as-is (which already has (1) on the group).
ClassMethod %ResolveSegPath(segName As %String, ByRef segMap) As %String [ Internal ]
{
    ; Direct lookup first (no repetition index)
    If $data(segMap(segName)) Return segMap(segName)
    ; Strip repetition index: "OBX(1)" -> bare="OBX", repIdx=1
    Set bare = $piece(segName, "(", 1)
    If bare = "" Return ""
    If '$data(segMap(bare)) Return ""
    Set fullPath = segMap(bare)
    ; Extract the agent's repetition index (if any)
    Set repIdx = 0
    If segName [ "(" {
        Set repStr = $piece($piece(segName, "(", 2), ")")
        If $isvalidnum(repStr) Set repIdx = +repStr
    }
    ; If agent specified a non-default repetition (2+), adjust the
    ; parent group's index. E.g., "OBX(2)" -> change OBXgrp(1) to
    ; OBXgrp(2) in the full path. The parent group is the piece
    ; immediately before the segment name in the dotted path.
    If repIdx > 1 {
        Set numParts = $length(fullPath, ".")
        If numParts >= 2 {
            ; Find the parent group part (one before the last segment)
            Set parentIdx = numParts - 1
            Set parentPart = $piece(fullPath, ".", parentIdx)
            Set parentBare = $piece(parentPart, "(", 1)
            ; Replace the parent group index
            Set newParent = parentBare _ "(" _ repIdx _ ")"
            Set $piece(fullPath, ".", parentIdx) = newParent
        }
    }
    Return fullPath
}

/// Internal helper: extract an XML attribute value from a string.
/// Returns "" if not found.
ClassMethod %ExtractAttr(xml As %String, attr As %String) As %String [ Internal ]
{
    Set pos = $find(xml, attr _ "=""")
    If pos = 0 Return ""
    Set endPos = $find(xml, """", pos)
    If endPos = 0 Return ""
    Return $extract(xml, pos, endPos - 2)
}

/// Internal helper: validate that all HL7 virtual document paths in a
/// DTL XML are correct for the given source/target doc types. This
/// catches the common agent error of using flat paths like "OBR:field"
/// when the target structure requires nested paths like
/// "PIDgrpgrp(1).ORCgrp(1).OBR:field".
///
/// Returns: { ok:1 } on success, { ok:0, error:"..." } on failure.
ClassMethod %ValidateHL7Paths(dtlXml As %String, sourceDocType As %String, targetDocType As %String) As %DynamicObject [ Internal ]
{
    Set result = {}
    ; If we cannot determine the doc types, skip validation
    ; (better to let it compile and fail naturally)
    If sourceDocType = "" { Set sourceDocType = ..%ExtractAttr(dtlXml, "sourceDocType") }
    If targetDocType = "" { Set targetDocType = ..%ExtractAttr(dtlXml, "targetDocType") }
    If (sourceDocType = "") || (targetDocType = "") {
        Set result.ok = 1
        Return result
    }
    ; Build valid segment paths for source and target
    Set srcCat = $piece(sourceDocType, ":", 1)
    Set srcMS  = $piece(sourceDocType, ":", 2)
    Set tgtCat = $piece(targetDocType, ":", 1)
    Set tgtMS  = $piece(targetDocType, ":", 2)
    ; Verify the message structures exist
    If $get(^EnsHL7.Schema(srcCat, "MS", srcMS)) = "" {
        Set result.ok = 1
        Return result
    }
    If $get(^EnsHL7.Schema(tgtCat, "MS", tgtMS)) = "" {
        Set result.ok = 1
        Return result
    }
    ; Build segment -> validPath maps
    Kill srcMap, tgtMap
    Do ..%BuildSegMap(srcCat, srcMS, .srcMap)
    Do ..%BuildSegMap(tgtCat, tgtMS, .tgtMap)
    ; Build full valid path sets (segment-level, like "MSH", "PIDgrpgrp(1).PIDgrp.PID")
    Kill srcValid, tgtValid
    Set seg = "" For { Set seg = $order(srcMap(seg)) Quit:seg=""  Set srcValid(srcMap(seg)) = 1 }
    Set seg = "" For { Set seg = $order(tgtMap(seg)) Quit:seg=""  Set tgtValid(tgtMap(seg)) = 1 }
    ; Only add bare segment names for TOP-LEVEL segments (where seg = fullPath)
    ; Nested segments like OBR in ORU_R01 must NOT be accepted bare
    Set seg = "" For { Set seg = $order(srcMap(seg)) Quit:seg=""  If srcMap(seg) = seg Set srcValid(seg) = 1 }
    Set seg = "" For { Set seg = $order(tgtMap(seg)) Quit:seg=""  If tgtMap(seg) = seg Set tgtValid(seg) = 1 }
    ; Scan the XML for assign elements and extract property paths
    ; Pattern: property='target.{PATH:field}' or value='source.{PATH:field}'
    Set badPaths = []
    Set corrections = []
    ; Check target paths (property='target.{...}')
    Set searchStr = "target.{"
    Set pos = 0
    For {
        Set pos = $find(dtlXml, searchStr, pos)
        Quit:pos=0
        Set endBrace = $find(dtlXml, "}", pos)
        If endBrace = 0 Continue
        Set fullPath = $extract(dtlXml, pos, endBrace - 2)
        ; Extract segment part (before the colon)
        Set segPath = $piece(fullPath, ":", 1)
        If segPath = "" Continue
        ; Skip whole-message assignments (target = source, target.{MSH} = source.{MSH})
        ; Check if segPath is a valid target path
        If '$data(tgtValid(segPath)) {
            ; This path is NOT valid for the target structure
            ; Find what the correct path should be
            Set segType = segPath
            ; If segPath has dots (like "PIDgrpgrp(1).PIDgrp.PID"), extract last part
            If segPath [ "." { Set segType = $piece(segPath, ".", *) }
            ; Remove index suffix like "(1)"
            Set segType = $piece(segType, "(", 1)
            Set correctPath = $get(tgtMap(segType))
            If correctPath '= "" {
                Set fix = {}
                Set fix.wrong = "target.{" _ fullPath _ "}"
                Set fix.correct = "target.{" _ correctPath _ ":" _ $piece(fullPath, ":", 2, 99) _ "}"
                Set fix.segment = segType
                Do corrections.%Push(fix)
            }
            Do badPaths.%Push("target.{" _ fullPath _ "}")
        }
    }
    ; Check source paths (source.{...})
    Set searchStr = "source.{"
    Set pos = 0
    For {
        Set pos = $find(dtlXml, searchStr, pos)
        Quit:pos=0
        Set endBrace = $find(dtlXml, "}", pos)
        If endBrace = 0 Continue
        Set fullPath = $extract(dtlXml, pos, endBrace - 2)
        Set segPath = $piece(fullPath, ":", 1)
        If segPath = "" Continue
        If '$data(srcValid(segPath)) {
            Set segType = segPath
            If segPath [ "." { Set segType = $piece(segPath, ".", *) }
            Set segType = $piece(segType, "(", 1)
            Set correctPath = $get(srcMap(segType))
            If correctPath '= "" {
                Set fix = {}
                Set fix.wrong = "source.{" _ fullPath _ "}"
                Set fix.correct = "source.{" _ correctPath _ ":" _ $piece(fullPath, ":", 2, 99) _ "}"
                Set fix.segment = segType
                Do corrections.%Push(fix)
            }
            Do badPaths.%Push("source.{" _ fullPath _ "}")
        }
    }
    If badPaths.%Size() = 0 {
        Set result.ok = 1
        Return result
    }
    ; Build detailed error message
    Set errMsg = "INVALID HL7 PATHS — the DTL XML contains " _ badPaths.%Size() _ " incorrect virtual document path(s). "
    Set errMsg = errMsg _ "You MUST call BuildDTLXml to generate correct paths. DO NOT hand-write assign elements for HL7 DTLs. "
    Set errMsg = errMsg _ "Wrong paths found: "
    Set iter = badPaths.%GetIterator()
    While iter.%GetNext(.i, .p) {
        Set errMsg = errMsg _ p
        If i < (badPaths.%Size() - 1) Set errMsg = errMsg _ ", "
    }
    If corrections.%Size() > 0 {
        Set errMsg = errMsg _ ". Corrections: "
        Set citer = corrections.%GetIterator()
        While citer.%GetNext(.i, .c) {
            Set errMsg = errMsg _ c.wrong _ " should be " _ c.correct
            If i < (corrections.%Size() - 1) Set errMsg = errMsg _ "; "
        }
    }
    Set errMsg = errMsg _ ". Call BuildDTLXml(""" _ sourceDocType _ """, """ _ targetDocType _ """, mappingsJson) to generate valid XML."
    Set result.ok = 0
    Set result.error = errMsg
    Return result
}

/// Return the EXACT virtual-document segment paths for an HL7 message
/// structure. CALL THIS BEFORE writing or updating any DTL that uses
/// EnsLib.HL7.Message as source or target. The paths returned are the
/// ONLY valid paths for SetValueAt / GetValueAt on that DocType — using
/// any other path silently fails and produces empty segments.
///
/// Different message types have DIFFERENT group nesting. For example:
///   ADT_A01: PID is flat  →  source.{PID:PatientName}
///   ORU_R01: PID is nested → target.{PIDgrpgrp(1).PIDgrp.PID:PatientName}
/// You MUST look up both source and target schemas before writing <assign>
/// elements. Do NOT guess the paths.
///
/// category:         HL7 version category, e.g. "2.5", "2.3.1".
/// messageStructure: message structure name, e.g. "ADT_A01", "ORU_R01",
///                   "ORM_O01", "SIU_S12".
///
/// Returns: { ok, category, messageStructure, segments:[{path, segment,
/// segmentType}], segmentCount, hint }.
ClassMethod GetHL7SchemaMap(category As %String, messageStructure As %String) As %DynamicObject
{
    Set out = {}
    Set out.category = $get(category)
    Set out.messageStructure = $get(messageStructure)
    Set out.segments = []
    If $get(category) = "" {
        Set out.ok = 0
        Set out.error = "Pass `category` (e.g. '2.5') and `messageStructure` (e.g. 'ORU_R01')."
        Return out
    }
    If $get(messageStructure) = "" {
        Set out.ok = 0
        Set out.error = "Pass `messageStructure` (e.g. 'ADT_A01', 'ORU_R01')."
        Return out
    }
    Try {
        ; Verify the message structure exists in the schema
        Set rawDef = $get(^EnsHL7.Schema(category, "MS", messageStructure))
        If rawDef = "" {
            Set out.ok = 0
            Set out.error = "Message structure '" _ messageStructure _ "' not found in '" _ category _ "'."
            Set out.available = []
            Set ms = "", count = 0
            For {
                Set ms = $order(^EnsHL7.Schema(category, "MS", ms))
                Quit:ms=""
                Do out.available.%Push(ms)
                Set count = count + 1
                Quit:count>30
            }
            Quit
        }
        ; Walk the map sub-node — each entry is a segment path.
        ; DEDUP: only emit the full field list the FIRST time a
        ; segment type is seen. Later occurrences just get dtlPath
        ; + a "fieldsRef" pointer. This cuts ORU_R01 from 122K chars
        ; to ~15K by eliminating the 30-40 fields × N occurrences
        ; explosion that was blowing the token budget.
        Set segCount = 0
        Set key = ""
        For {
            Set key = $order(^EnsHL7.Schema(category, "MS", messageStructure, "map", key))
            Quit:key=""
            If key = "leftoversegs" Continue
            Set mapVal = $get(^EnsHL7.Schema(category, "MS", messageStructure, "map", key))
            Set segType = $piece($piece(mapVal, "|", 2), ":", 2)
            Set entry = {}
            Set entry.path = key
            Set entry.segmentType = segType
            Set dtlPath = $replace(key, "()", "(1)")
            Set entry.dtlPath = dtlPath
            ; First occurrence: emit field names (no fullPath — agent
            ; derives it as dtlPath:fieldName). Later: just a reference.
            If '$data(seenSeg(segType)) {
                Set seenSeg(segType) = dtlPath
                Set entry.fields = []
                Set fld = "", fldCount = 0
                For {
                    Set fld = $order(^EnsHL7.Schema(category, "SS", segType, "map", fld))
                    Quit:fld=""
                    Set fldCount = fldCount + 1
                    Do entry.fields.%Push(fld)
                    Quit:fldCount>40
                }
            } Else {
                Set entry.fieldsRef = "Same fields as " _ segType _ " at " _ seenSeg(segType)
            }
            Do out.segments.%Push(entry)
            Set segCount = segCount + 1
        }
        Set out.segmentCount = segCount
        Set out.ok = 1
        Set out.hint = "Use dtlPath:fieldName in DTL <assign> elements. For repeating groups, increment the index: (1), (2). For repeating fields, append (1) to the field name: dtlPath:PatientIdentifierList(1). Segments with fieldsRef share the same fields as the referenced path."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Return out
}

/// Return detailed field metadata for a single HL7 segment type in a
/// given schema category. Each field includes its position number,
/// property name, data type, required/optional status, maximum length,
/// and sub-components. Use this to understand segment structure before
/// building DTLs or test messages.
///
/// CALL THIS when the agent needs to know which fields exist in a
/// segment, their exact positions, and their data types. This is
/// complementary to GetHL7SchemaMap (which returns message-level
/// segment paths) — this tool goes one level deeper into a single
/// segment.
///
/// category:      schema version, e.g. "2.5", "2.5.1", "2.3.1".
/// segmentType:   segment name, e.g. "PV1", "PID", "OBR", "OBX".
///
/// Returns: { ok, category, segmentType, fields: [ { position,
///   name, dataType, required, maxLength, description, subComponents? } ] }.
/// Read-only.
ClassMethod GetHL7SegmentFields(category As %String, segmentType As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "get_hl7_segment_fields"
    Set out.category = $get(category)
    Set out.segmentType = $get(segmentType)
    If $get(category) = "" || ($get(segmentType) = "") {
        Set out.ok = 0
        Set out.error = "Pass `category` (e.g. '2.5') and `segmentType` (e.g. 'PV1')."
        Return out
    }
    Try {
        ; Check segment exists in schema
        Set segDef = $get(^EnsHL7.Schema(category, "SS", segmentType))
        If segDef = "" {
            Set out.ok = 0
            Set out.error = "Segment '" _ segmentType _ "' not found in schema '" _ category _ "'."
            ; List available segments
            Set out.available = []
            Set seg = ""
            Set count = 0
            For {
                Set seg = $order(^EnsHL7.Schema(category, "SS", seg))
                Quit:seg=""
                Do out.available.%Push(seg)
                Set count = count + 1
                Quit:count>50
            }
            Return out
        }
        ; --- Segment definition is a $list of $lists ---
        ; segDef = $lb($lb("cat:DT","",maxLen,"opt"), ...) with one
        ; entry per field, 1-indexed. Field N's data type is:
        ;   $piece($lg($lg(segDef, N), 1), ":", 2)
        ; This is 100% reliable (no text-scanning heuristics).
        ;
        ; --- Walk the map sub-node for top-level fields ---
        ; Keys are dotted field paths ("attendingdoctor",
        ; "attendingdoctor.familyname.surname"). Values encode the
        ; actual HL7 position: "7()" = field 7 repeating,
        ; "17().2.1" = field 17 sub-component 2.1. We only emit
        ; TOP-LEVEL fields (no dot in name).
        Set out.fields = []
        Set fieldKey = ""
        Set tmpArr = []
        For {
            Set fieldKey = $order(^EnsHL7.Schema(category, "SS", segmentType, "map", fieldKey))
            Quit:fieldKey=""
            ; Skip sub-components (dotted names like "admittingdoctor.familyname")
            Continue:fieldKey["."
            Set mapVal = $get(^EnsHL7.Schema(category, "SS", segmentType, "map", fieldKey))
            ; Extract actual HL7 position: "7()" -> 7, "41" -> 41
            Set posStr = $translate(mapVal, "()", "")
            Set realPos = +posStr
            ; Detect repeating from "()" suffix
            Set isRepeating = (mapVal [ "()")
            ; Look up data type from the $list-of-$lists structure
            Set fldDef = $listget(segDef, realPos, "")
            If $listvalid(fldDef) {
                Set dtName = $piece($listget(fldDef, 1, ""), ":", 2)
            } Else {
                Set dtName = ""
            }
            ; Build field entry
            Set entry = {}
            Set entry.position = realPos
            Set entry.name = fieldKey
            Set entry.dataType = dtName
            Set entry.repeating = isRepeating
            ; Walk data type definition for sub-component names
            If dtName '= "" {
                Set subKey = ""
                Set subs = []
                For {
                    Set subKey = $order(^EnsHL7.Schema(category, "DT", dtName, "names", subKey))
                    Quit:subKey=""
                    Continue:subKey["."
                    Do subs.%Push(subKey)
                }
                If subs.%Size() > 0 {
                    Set entry.subComponents = subs
                }
            }
            Do tmpArr.%Push(entry)
        }
        ; Sort by actual HL7 position (insertion sort — segments have <60 fields)
        Set sorted = []
        For i=0:1:tmpArr.%Size()-1 {
            Set entry = tmpArr.%Get(i)
            Set inserted = 0
            For j=0:1:sorted.%Size()-1 {
                If entry.position < sorted.%Get(j).position {
                    ; Insert before j — rebuild array
                    Set newArr = []
                    For k=0:1:sorted.%Size()-1 {
                        If k = j Do newArr.%Push(entry) Set inserted = 1
                        Do newArr.%Push(sorted.%Get(k))
                    }
                    Set sorted = newArr
                    Quit
                }
            }
            If 'inserted Do sorted.%Push(entry)
        }
        Set out.fields = sorted
        Set out.fieldCount = sorted.%Size()
        Set out.ok = 1
        Set out.hint = "Fields sorted by HL7 position. Use name in BuildHL7TestMessage fields: " _ segmentType _ ":FieldName. For sub-components: " _ segmentType _ ":FieldName.SubComponent. Repeating fields use (1) syntax: " _ segmentType _ ":FieldName(1).SubComponent."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Return out
}

}
