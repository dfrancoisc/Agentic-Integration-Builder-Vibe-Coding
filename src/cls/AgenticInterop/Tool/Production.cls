/// Production ToolSet — production lifecycle, business host CRUD,
/// inspection, and class-level deletion. All operations scope to the
/// chat's active namespace via the X-IRIS-Namespace header captured
/// at dispatch.
///
/// Mutating operations (start_, stop_, delete_, add_, remove_,
/// update_, create_) flow through AgenticInterop.Policy.
/// ConfirmationGate so the user always approves the action via the
/// inline chat card before it touches IRIS state.
/// %AI.Tool source for the Production toolset. Each public ClassMethod
/// is auto-discovered by the framework as a tool — the method name
/// is the tool name the LLM sees. Composed into AgenticInterop.ToolSet.
/// Production via <Include Class="AgenticInterop.Tool.Production"/> (Pattern 5
/// of the ai-hub-tools skill).
Class AgenticInterop.Tool.Production Extends %AI.Tool
{


/// Resolve the namespace this tool call should run against (the
/// X-IRIS-Namespace the chat surface attached, or the dispatch
/// namespace if absent). Internal helper.
ClassMethod %TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// List the interoperability productions in the active namespace.
/// CALL THIS for "what productions exist", "show me running
/// productions", "is X production running", or any inventory query.
/// Read-only.
///
/// Returns: { ok, namespace, productions:[{name, isActive, status?}], total }.
ClassMethod ListProductions() As %DynamicObject
{
    Set out = {}
    Set out.productions = []
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set activeName = ""
        Try { Set activeName = ##class(Ens.Director).GetActiveProductionName() } Catch  {}
        Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT Name FROM Ens_Config.Production ORDER BY Name")
        Set count = 0
        While rs.%Next() {
            Set name = rs.%Get("Name")
            Set p = {}
            Set p.name = name
            Set p.isActive = ''(name = activeName)
            If p.isActive {
                Set status = ""
                Try { Set status = ##class(Ens.Director).GetProductionStatus(name) } Catch  {}
                If status '= "" { Set p.status = status }
            }
            Do out.productions.%Push(p)
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

/// Inspect a production: returns the class description, actor pool
/// size, and the full list of business hosts (services / processes /
/// operations) with their settings. CALL THIS when the user asks
/// "show me production X", "what hosts are in production X",
/// "what does production X do". Read-only.
///
/// name: fully-qualified production class name.
///
/// Returns: { ok, namespace, name, exists, isActive, description?,
/// items:[{name, className, poolSize, enabled, comment, settings:[{target, name, value}]}], total }.
ClassMethod GetProduction(name As %String) As %DynamicObject
{
    Set out = {}
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(Ens.Config.Production).%ExistsId(name) {
            Set out.ok = 1
            Set out.exists = 0
            Set out.error = "Production not found: " _ name
            Quit
        }
        Set out.exists = 1
        Set prod = ##class(Ens.Config.Production).%OpenId(name)
        Set out.description = $extract(prod.Description, 1, 600)
        Set out.actorPoolSize = prod.ActorPoolSize
        Set activeName = ""
        Try { Set activeName = ##class(Ens.Director).GetActiveProductionName() } Catch  {}
        Set out.isActive = ''(name = activeName)
        Set out.items = []
        Set count = 0
        For i=1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            Set itemObj = {}
            Set itemObj.name = item.Name
            Set itemObj.className = item.ClassName
            Set itemObj.poolSize = item.PoolSize
            Set itemObj.enabled = ''(item.Enabled)
            Set itemObj.comment = $extract(item.Comment, 1, 240)
            Set itemObj.settings = []
            For j=1:1:item.Settings.Count() {
                Set s = item.Settings.GetAt(j)
                Set sObj = {}
                Set sObj.target = s.Target
                Set sObj.name   = s.Name
                Set sObj.value  = $extract(s.Value, 1, 600)
                Do itemObj.settings.%Push(sObj)
            }
            Do out.items.%Push(itemObj)
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

/// Start the named production. MUTATING — gated by the confirmation
/// policy via the start_ prefix.
///
/// production: fully-qualified production class name.
ClassMethod StartProduction(production As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "start_production"
    Set out.production = production
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        ; Pre-flight: check that all host classes in the production
        ; exist. If any are missing (e.g. HS.FHIR.* classes that live
        ; in HSLIB but aren't mapped to this namespace), report them
        ; upfront instead of letting Ens.Director fail mid-start.
        If ##class(Ens.Config.Production).%ExistsId(production) {
            Set prod = ##class(Ens.Config.Production).%OpenId(production)
            Set missing = ""
            For i=1:1:prod.Items.Count() {
                Set item = prod.Items.GetAt(i)
                Set cls = item.ClassName
                If cls '= "", '##class(%Dictionary.CompiledClass).%ExistsId(cls) {
                    Set missing = missing _ $select(missing="":"",1:", ") _ cls
                }
            }
            If missing '= "" {
                Set out.ok = 0
                Set out.error = "Cannot start — these host classes are not available in namespace " _ targetNs _ ": " _ missing _ ". They may live in HSLIB/ENSLIB. Remove them via remove_business_host or verify the class names with describe_class."
                Quit
            }
        }
        Set tSC = ##class(Ens.Director).StartProduction(production)
        If 'tSC {
            Set out.ok = 0
            Set out.error = $system.Status.GetErrorText(tSC)
        } Else {
            Set out.ok = 1
            Set out.message = "Production '" _ production _ "' started."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Stop the active production in the active namespace. MUTATING —
/// gated by the confirmation policy via the stop_ prefix.
///
/// timeout: graceful-stop timeout in seconds (default 30).
/// force:   if 1, hard-stop after the grace period instead of waiting.
ClassMethod StopProduction(timeout As %Integer = 30, force As %Boolean = 0) As %DynamicObject
{
    Set out = {}
    Set out.tool = "stop_production"
    ; Guard against the framework passing "" when the LLM omits a parameter
    If $get(timeout)="" Set timeout = 30
    If $get(force)="" Set force = 0
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set activeName = ""
        Try { Set activeName = ##class(Ens.Director).GetActiveProductionName() } Catch  {}
        Set out.production = activeName
        If activeName = "" {
            Set out.ok = 1
            Set out.stopped = 0
            Set out.message = "No production is currently active."
            Quit
        }
        Set tSC = ##class(Ens.Director).StopProduction(+timeout, +force)
        If 'tSC {
            Set out.ok = 0
            Set out.stopped = 0
            Set out.error = $system.Status.GetErrorText(tSC)
        } Else {
            Set out.ok = 1
            Set out.stopped = 1
            Set out.message = "Production '" _ activeName _ "' stopped (timeout=" _ timeout _ ", force=" _ +force _ ")."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Create an empty production class skeleton — the user can then
/// add hosts via add_business_host. MUTATING — gated by the
/// create_ prefix.
///
/// name: fully-qualified production class name (e.g.,
/// "MyApp.Productions.Inbound").
/// description: shown in the SMP / Production Configuration page.
ClassMethod CreateProduction(name As %String, description As %String = "") As %DynamicObject
{
    Set out = {}
    Set out.tool = "create_production"
    Set out.production = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" {
        Set out.ok = 0
        Set out.error = "Empty class name — pass the fully-qualified production class as `name`."
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
            Set out.error = "Class already exists: " _ name _ ". Use add_business_host to extend it."
            Quit
        }
        Set cdef = ##class(%Dictionary.ClassDefinition).%New(name)
        Set cdef.Super = "Ens.Production"
        Set cdef.ProcedureBlock = 1
        If description '= "" { Set cdef.Description = description }
        Set xdata = ##class(%Dictionary.XDataDefinition).%New()
        Set xdata.Name = "ProductionDefinition"
        Set xdata.XMLNamespace = "http://www.intersystems.com/Production"
        Do xdata.Data.Write("<Production Name=""" _ name _ """ LogGeneralTraceEvents=""false""><ActorPoolSize>2</ActorPoolSize></Production>")
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
        Set out.message = "Production '" _ name _ "' created. Add hosts with add_business_host."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Delete a production class — class definition removed from the
/// namespace. MUTATING — gated by the delete_ prefix. The active
/// production cannot be deleted; stop it first.
///
/// name: fully-qualified production class name.
ClassMethod DeleteProduction(name As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "delete_production"
    Set out.production = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set activeName = ""
        Try { Set activeName = ##class(Ens.Director).GetActiveProductionName() } Catch  {}
        If activeName = name {
            Set out.ok = 0
            Set out.deleted = 0
            Set out.error = "Cannot delete the active production. Stop it first via stop_production."
            Quit
        }
        If '##class(%Dictionary.ClassDefinition).%ExistsId(name) {
            Set out.ok = 1
            Set out.deleted = 0
            Set out.error = "Class not found: " _ name
            Quit
        }
        Set sc = $SYSTEM.OBJ.Delete(name, "d")
        If 'sc {
            Set out.ok = 0
            Set out.deleted = 0
            Set out.error = $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.deleted = 1
        Set out.message = "Production '" _ name _ "' deleted."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Add a business host (Service / Process / Operation) to a
/// production. MUTATING — gated by the add_ prefix.
///
/// production: fully-qualified production class name.
/// hostName:   logical host name unique within the production.
/// hostClass:  fully-qualified host class (e.g.,
///             "EnsLib.HL7.Service.TCPService").
/// settings:   { target: name: value } pairs, e.g.,
///             { "Adapter": { "Port": "5000" } } — optional.
ClassMethod AddBusinessHost(production As %String, hostName As %String, hostClass As %String, settings As %DynamicObject = "") As %DynamicObject
{
    Set out = {}
    Set out.tool = "add_business_host"
    Set out.production = production
    Set out.hostName = hostName
    Set out.hostClass = hostClass
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(Ens.Config.Production).%ExistsId(production) {
            Set out.ok = 0
            Set out.error = "Production not found: " _ production
            Quit
        }
        ; BUG 4 fix: validate that the host class actually exists
        ; before adding it to the production. HS.*/Ens.*/EnsLib.*
        ; classes live in HSLIB/ENSLIB mapped databases — check
        ; there if not found in the user namespace. Without this,
        ; the production compiles but StartProduction fails at
        ; runtime with CLASS DOES NOT EXIST.
        Set classFound = ##class(%Dictionary.CompiledClass).%ExistsId(hostClass)
        If 'classFound {
            Set prefix2 = $extract(hostClass, 1, 3)
            Set prefix4 = $extract(hostClass, 1, 4)
            If (prefix2 = "HS.") || (prefix4 = "Ens.") || (prefix4 = "Ensl") {
                For fbNs = "HSLIB", "HSCUSTOM", "%SYS" {
                    Try {
                        New $namespace
                        Set $namespace = fbNs
                        If ##class(%Dictionary.CompiledClass).%ExistsId(hostClass) Set classFound = 1
                    } Catch  {}
                    If classFound Quit
                }
            }
        }
        If 'classFound {
            Set out.ok = 0
            Set out.error = "Host class not found: " _ hostClass _ ". Verify the exact class name with describe_class or search_ens before adding a host."
            Quit
        }
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        For i=1:1:prod.Items.Count() {
            Set existing = prod.Items.GetAt(i)
            If existing.Name = hostName {
                Set out.ok = 0
                Set out.error = "Host '" _ hostName _ "' already exists in production. Use update_business_host_settings to modify it."
                Quit
            }
        }
        If 'out.%IsDefined("ok") {
            Set item = ##class(Ens.Config.Item).%New()
            Set item.Name = hostName
            Set item.ClassName = hostClass
            Set item.Enabled = 1
            Set item.PoolSize = 1
            If $isobject(settings) {
                Set tIter = settings.%GetIterator()
                While tIter.%GetNext(.target, .nameMap) {
                    If '$isobject(nameMap) { Continue }
                    Set nIter = nameMap.%GetIterator()
                    While nIter.%GetNext(.sname, .svalue) {
                        Set s = ##class(Ens.Config.Setting).%New()
                        Set s.Target = target
                        Set s.Name   = sname
                        Set s.Value  = $select($isobject(svalue):svalue.%ToJSON(), 1:svalue)
                        Do item.Settings.Insert(s)
                    }
                }
            }
            Do prod.Items.Insert(item)
            Set sc = prod.SaveToClass()
            If 'sc {
                Set out.ok = 0
                Set out.error = $system.Status.GetErrorText(sc)
                Quit
            }
            Set sc = $SYSTEM.OBJ.Compile(production, "ck-d")
            If 'sc {
                Set out.ok = 0
                Set out.error = "Saved but compile failed: " _ $system.Status.GetErrorText(sc)
                Quit
            }
            Set out.ok = 1
            Set out.added = 1
            Set out.message = "Added host '" _ hostName _ "' (class " _ hostClass _ ") to production '" _ production _ "'."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Remove a business host from a production. MUTATING — gated by
/// the remove_ prefix.
///
/// production: fully-qualified production class name.
/// hostName:   the logical host name to remove.
ClassMethod RemoveBusinessHost(production As %String, hostName As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "remove_business_host"
    Set out.production = production
    Set out.hostName = hostName
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(Ens.Config.Production).%ExistsId(production) {
            Set out.ok = 0
            Set out.error = "Production not found: " _ production
            Quit
        }
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        Set foundIdx = 0
        For i=1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            If item.Name = hostName { Set foundIdx = i Quit }
        }
        If foundIdx = 0 {
            Set out.ok = 1
            Set out.removed = 0
            Set out.error = "Host '" _ hostName _ "' not found in production."
            Quit
        }
        Do prod.Items.RemoveAt(foundIdx)
        Set sc = prod.SaveToClass()
        If 'sc {
            Set out.ok = 0
            Set out.removed = 0
            Set out.error = $system.Status.GetErrorText(sc)
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(production, "ck-d")
        If 'sc {
            Set out.ok = 0
            Set out.removed = 0
            Set out.error = "Saved but compile failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.removed = 1
        Set out.message = "Removed host '" _ hostName _ "' from production '" _ production _ "'."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Update settings on an existing business host — overwrites
/// settings whose (target, name) match, inserts new ones, leaves
/// others untouched. MUTATING — gated by the update_ prefix.
///
/// production: fully-qualified production class name.
/// hostName:   the host whose settings to update.
/// settings:   { target: { name: value } } map of settings to write.
ClassMethod UpdateBusinessHostSettings(production As %String, hostName As %String, settings As %DynamicObject) As %DynamicObject
{
    Set out = {}
    Set out.tool = "update_business_host_settings"
    Set out.production = production
    Set out.hostName = hostName
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '$isobject(settings) {
            Set out.ok = 0
            Set out.error = "Pass a settings object: { target: { name: value } }."
            Quit
        }
        If '##class(Ens.Config.Production).%ExistsId(production) {
            Set out.ok = 0
            Set out.error = "Production not found: " _ production
            Quit
        }
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        Set item = ""
        For i=1:1:prod.Items.Count() {
            Set candidate = prod.Items.GetAt(i)
            If candidate.Name = hostName { Set item = candidate Quit }
        }
        If '$isobject(item) {
            Set out.ok = 0
            Set out.error = "Host '" _ hostName _ "' not found in production."
            Quit
        }
        Set updates = []
        Set tIter = settings.%GetIterator()
        While tIter.%GetNext(.target, .nameMap) {
            If '$isobject(nameMap) { Continue }
            Set nIter = nameMap.%GetIterator()
            While nIter.%GetNext(.sname, .svalue) {
                Set raw = $select($isobject(svalue):svalue.%ToJSON(), 1:svalue)
                Set foundIdx = 0
                For j=1:1:item.Settings.Count() {
                    Set s = item.Settings.GetAt(j)
                    If s.Target = target, s.Name = sname { Set foundIdx = j Quit }
                }
                If foundIdx > 0 {
                    Set existingSetting = item.Settings.GetAt(foundIdx)
                    Set existingSetting.Value = raw
                } Else {
                    Set s = ##class(Ens.Config.Setting).%New()
                    Set s.Target = target
                    Set s.Name = sname
                    Set s.Value = raw
                    Do item.Settings.Insert(s)
                }
                Set u = {}
                Set u.target = target
                Set u.name   = sname
                Set u.value  = $extract(raw, 1, 200)
                Do updates.%Push(u)
            }
        }
        Set sc = prod.SaveToClass()
        If 'sc {
            Set out.ok = 0
            Set out.error = $system.Status.GetErrorText(sc)
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(production, "ck-d")
        If 'sc {
            Set out.ok = 0
            Set out.error = "Saved but compile failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.updated = updates
        Set out.message = "Updated " _ updates.%Size() _ " setting(s) on host '" _ hostName _ "'."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

}
