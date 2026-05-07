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
            Set out.ok = 1
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

/// Create a Data Transformation Language (DTL) class skeleton. The
/// generated class extends Ens.DataTransformDTL and contains an empty
/// <transform> XData with the specified source / target classes — the
/// user (or a follow-up update_dtl call) fills in the field mappings.
/// MUTATING — gated by the create_ prefix.
///
/// name:        fully-qualified DTL class name (e.g.,
///              "Demo.Transform.ADT_to_SDA").
/// sourceClass: fully-qualified source class (e.g.,
///              "EnsLib.HL7.Message").
/// targetClass: fully-qualified target class.
/// sourceDocType: optional HL7 DocType for the source side
///              (e.g., "2.5:ADT_A01").
/// targetDocType: optional HL7 DocType for the target side.
ClassMethod CreateDTL(name As %String, sourceClass As %String, targetClass As %String, sourceDocType As %String = "", targetDocType As %String = "") As %DynamicObject
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
            Set out.error = "Class already exists: " _ name _ ". Use update_dtl to modify it."
            Quit
        }
        Set cdef = ##class(%Dictionary.ClassDefinition).%New(name)
        Set cdef.Super = "Ens.DataTransformDTL"
        Set cdef.ProcedureBlock = 1
        Set cdef.DependsOn = sourceClass _ "," _ targetClass
        Set xdata = ##class(%Dictionary.XDataDefinition).%New()
        Set xdata.Name = "DTL"
        Set xdata.XMLNamespace = "http://www.intersystems.com/dtl"
        Set transformOpen = "<transform sourceClass=""" _ sourceClass _ """ targetClass=""" _ targetClass _ """"
        If sourceDocType '= "" { Set transformOpen = transformOpen _ " sourceDocType=""" _ sourceDocType _ """" }
        If targetDocType '= "" { Set transformOpen = transformOpen _ " targetDocType=""" _ targetDocType _ """" }
        Set transformOpen = transformOpen _ " create=""new"" language=""objectscript"">"
        Do xdata.Data.Write(transformOpen)
        Do xdata.Data.Write("<assign property='target' value='source' action='set' />")
        Do xdata.Data.Write("</transform>")
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
        Set out.message = "DTL '" _ name _ "' created with empty mapping. Use update_dtl to add field mappings."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Replace the body of a DTL class's <transform> XData and recompile.
/// MUTATING — gated by the update_ prefix. The body is the inner XML
/// of the <transform> element (the <assign>, <foreach>, <code>,
/// <subtransform> children); pass the entire <transform> wrapper to
/// also change source/target attributes.
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
                If $method(source, "%JSONImport") '= "" {
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
        // Render result
        If $isobject(target) {
            Set targetCls = $classname(target)
            Set out.targetClass = targetCls
            // HL7 message — render to string
            If $method(target, "OutputToString") '= "" {
                Try {
                    Set scOut = $$$OK
                    Set out.output = target.OutputToString("|^~\&", .scOut)
                } Catch  {}
            }
            // JSON adaptor — export
            If $method(target, "%JSONExport") '= "" {
                Try {
                    Set jstream = ##class(%Stream.TmpCharacter).%New()
                    Do target.%JSONExport(jstream)
                    Do jstream.Rewind()
                    Set jbody = ""
                    While 'jstream.AtEnd { Set jbody = jbody _ jstream.Read(8192) }
                    Set out.outputJson = ##class(%DynamicAbstractObject).%FromJSON(jbody)
                } Catch  {}
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

/// List business / routing rule classes defined in the active
/// namespace. Rule classes extend Ens.Rule.Definition (the rule
/// editor's base class). CALL THIS for "what rules do we have",
/// "is there an existing rule for X". Read-only.
///
/// Returns: { ok, namespace, rules:[{name, super, description?}], total }.
ClassMethod ListBusinessRules() As %DynamicObject
{
    Set out = {}
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    Set out.rules = []
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set sql = "SELECT Name, Super, Description FROM %Dictionary.CompiledClass "
        Set sql = sql _ "WHERE Super = 'Ens.Rule.Definition' OR Super [ 'Ens.Rule.Definition,' "
        Set sql = sql _ "OR Super [ ',Ens.Rule.Definition' ORDER BY Name"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        Set count = 0
        While rs.%Next() {
            Set r = {}
            Set r.name = rs.%Get("Name")
            Set r.super = rs.%Get("Super")
            Set desc = rs.%Get("Description")
            If desc '= "" { Set r.description = $extract(desc, 1, 240) }
            Do out.rules.%Push(r)
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

}
