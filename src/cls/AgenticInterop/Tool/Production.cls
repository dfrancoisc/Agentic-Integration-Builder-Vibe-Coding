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

/// Run a post-build validation checklist on a production. Call this
/// AFTER building and testing a production to verify everything works
/// end-to-end. Checks: production exists, production is running, all
/// hosts are enabled, no recent event log errors, messages flowed
/// through the pipeline. Returns a structured pass/fail report with
/// an overall verdict. Read-only.
///
/// production: fully-qualified production class name.
/// minutesBack: how far back to check event log and messages (default 5).
ClassMethod PostBuildValidation(production As %String, minutesBack As %Integer = 5) As %DynamicObject
{
    Set out = {}
    Set out.production = production
    Set out.checks = []
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(minutesBack) = "" Set minutesBack = 5
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set allPass = 1
        Set warnings = 0

        ; --- Check 1: Production exists ---
        Set c1 = {}
        Set c1.check = "production_exists"
        If ##class(Ens.Config.Production).%ExistsId(production) {
            Set c1.pass = 1
            Set c1.detail = "Class exists and is a valid production."
        } Else {
            Set c1.pass = 0
            Set c1.detail = "Production class not found: " _ production
            Set allPass = 0
        }
        Do out.checks.%Push(c1)
        If 'c1.pass { Set out.ok = 0 Set out.allPass = 0 Set out.verdict = "FAIL — production does not exist" Quit }

        ; --- Check 2: Production is running ---
        Set c2 = {}
        Set c2.check = "production_running"
        Set activeName = ""
        Try { Set activeName = ##class(Ens.Director).GetActiveProductionName() } Catch  {}
        If activeName = production {
            Set sc = ##class(Ens.Director).GetProductionStatus(.prodName, .prodStatus)
            If prodStatus = 1 {
                Set c2.pass = 1
                Set c2.detail = "Production is running."
            } Else {
                Set c2.pass = 0
                Set c2.detail = "Production is active but status is " _ prodStatus _ " (expected 1=Running)."
                Set allPass = 0
            }
        } Else {
            Set c2.pass = 0
            Set c2.detail = "Production is NOT running. Active production: " _ $select(activeName="":"(none)", 1:activeName)
            Set allPass = 0
        }
        Do out.checks.%Push(c2)

        ; --- Check 3: All hosts enabled and classes valid ---
        Set c3 = {}
        Set c3.check = "hosts_healthy"
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        Set hostCount = prod.Items.Count()
        Set disabledHosts = ""
        Set missingClasses = ""
        Set hostNames = ""
        For i=1:1:hostCount {
            Set item = prod.Items.GetAt(i)
            Set hostNames = hostNames _ $select(hostNames="":"", 1:",") _ item.Name
            If 'item.Enabled {
                Set disabledHosts = disabledHosts _ $select(disabledHosts="":"", 1:", ") _ item.Name
            }
            If item.ClassName '= "", '##class(%Dictionary.CompiledClass).%ExistsId(item.ClassName) {
                Set missingClasses = missingClasses _ $select(missingClasses="":"", 1:", ") _ item.Name _ "(" _ item.ClassName _ ")"
            }
        }
        If missingClasses '= "" {
            Set c3.pass = 0
            Set c3.detail = "Missing host classes: " _ missingClasses
            Set allPass = 0
        } ElseIf disabledHosts '= "" {
            Set c3.pass = 0
            Set c3.detail = hostCount _ " hosts found. Disabled: " _ disabledHosts
            Set allPass = 0
        } Else {
            Set c3.pass = 1
            Set c3.detail = hostCount _ " hosts, all enabled with valid classes."
        }
        Set c3.hostCount = hostCount
        Do out.checks.%Push(c3)

        ; --- Check 4: Event log errors ---
        Set c4 = {}
        Set c4.check = "no_recent_errors"
        Set cutoff = $system.SQL.DATEADD("mi", -minutesBack, $zdatetime($horolog, 3, 1))
        Set sql = "SELECT COUNT(*) AS cnt FROM Ens_Util.Log WHERE Type = 1 AND TimeLogged >= ?"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, cutoff)
        Set errorCount = 0
        If rs.%Next() { Set errorCount = +rs.%Get("cnt") }
        If errorCount = 0 {
            Set c4.pass = 1
            Set c4.detail = "No errors in event log (last " _ minutesBack _ " minutes)."
        } Else {
            Set c4.pass = 0
            Set c4.errorCount = errorCount
            Set allPass = 0
            ; Grab the first 3 error messages for context
            Set c4.recentErrors = []
            Set sql2 = "SELECT TOP 3 ConfigName, Text FROM Ens_Util.Log WHERE Type = 1 AND TimeLogged >= ? ORDER BY ID DESC"
            Set rs2 = ##class(%SQL.Statement).%ExecDirect(, sql2, cutoff)
            While rs2.%Next() {
                Set e = {}
                Set e.host = rs2.%Get("ConfigName")
                Set e.text = $extract(rs2.%Get("Text"), 1, 300)
                Do c4.recentErrors.%Push(e)
            }
            Set c4.detail = errorCount _ " error(s) in event log (last " _ minutesBack _ " min). See recentErrors."
        }
        Do out.checks.%Push(c4)

        ; --- Check 5: Messages flowed ---
        Set c5 = {}
        Set c5.check = "messages_routed"
        Set sql3 = "SELECT Status, COUNT(*) AS cnt FROM Ens.MessageHeader WHERE TimeCreated >= ? GROUP BY Status"
        Set rs3 = ##class(%SQL.Statement).%ExecDirect(, sql3, cutoff)
        Set totalMsgs = 0
        Set completedMsgs = 0
        Set errorMsgs = 0
        Set c5.byStatus = []
        While rs3.%Next() {
            Set st = rs3.%Get("Status")
            Set cnt = +rs3.%Get("cnt")
            Set totalMsgs = totalMsgs + cnt
            Set statusLabel = $case(st, 1:"Created", 2:"Queued", 3:"Delivered", 4:"Discarded", 5:"Suspended", 6:"Deferred", 7:"Aborted", 8:"Error", 9:"Completed", :"Unknown("_st_")")
            If st = 9 Set completedMsgs = cnt
            If st = 8 Set errorMsgs = cnt
            Set s = {}
            Set s.status = statusLabel
            Set s.count = cnt
            Do c5.byStatus.%Push(s)
        }
        Set c5.totalMessages = totalMsgs
        Set c5.completedMessages = completedMsgs
        Set c5.errorMessages = errorMsgs
        If totalMsgs = 0 {
            Set c5.pass = 0
            Set c5.detail = "No messages found in last " _ minutesBack _ " minutes. Was a test message sent?"
            Set allPass = 0
        } ElseIf errorMsgs > 0 {
            Set c5.pass = 0
            Set c5.detail = totalMsgs _ " messages total, " _ errorMsgs _ " errored, " _ completedMsgs _ " completed."
            Set allPass = 0
        } ElseIf completedMsgs > 0 {
            Set c5.pass = 1
            Set c5.detail = totalMsgs _ " messages total, " _ completedMsgs _ " completed successfully."
        } Else {
            Set c5.pass = 0
            Set c5.detail = totalMsgs _ " messages found but none in Completed status yet."
            Set warnings = warnings + 1
        }
        Do out.checks.%Push(c5)

        ; --- Check 6: Message trace — did messages reach every host? ---
        Set c6 = {}
        Set c6.check = "pipeline_coverage"
        Set c6.hostsReached = []
        Set sql4 = "SELECT DISTINCT TargetConfigName FROM Ens.MessageHeader WHERE TimeCreated >= ? AND TargetConfigName IS NOT NULL"
        Set rs4 = ##class(%SQL.Statement).%ExecDirect(, sql4, cutoff)
        Set reached = ""
        While rs4.%Next() {
            Set tgt = rs4.%Get("TargetConfigName")
            Do c6.hostsReached.%Push(tgt)
            Set reached = reached _ $select(reached="":"", 1:",") _ tgt
        }
        ; Compare reached hosts to production hosts (case-insensitive)
        Set unreached = ""
        Set reachedUpper = $zconvert(reached, "U")
        For i=1:1:hostCount {
            Set item = prod.Items.GetAt(i)
            Set hName = item.Name
            ; Services don't appear as TargetConfigName — skip them
            Set hClass = item.ClassName
            Set isService = (hClass [ "Service") || (hClass [ "service")
            If 'isService, reachedUpper '[ $zconvert(hName, "U") {
                Set unreached = unreached _ $select(unreached="":"", 1:", ") _ hName
            }
        }
        If unreached = "" {
            Set c6.pass = 1
            Set c6.detail = "Messages reached all non-service hosts."
        } ElseIf totalMsgs = 0 {
            Set c6.pass = 0
            Set c6.detail = "No messages — cannot verify pipeline coverage."
            Set allPass = 0
        } Else {
            Set c6.pass = 0
            Set c6.detail = "These hosts received no messages: " _ unreached
            Set allPass = 0
        }
        Do out.checks.%Push(c6)

        ; --- Verdict ---
        Set passed = 0
        Set total = out.checks.%Size()
        Set iter = out.checks.%GetIterator()
        While iter.%GetNext(.k, .v) {
            If v.%Get("pass") = 1 Set passed = passed + 1
        }
        Set out.passed = passed
        Set out.total = total
        Set out.allPass = allPass
        If allPass {
            Set out.verdict = "ALL CHECKS PASSED (" _ passed _ "/" _ total _ ")"
        } Else {
            Set out.verdict = "FAILED — " _ passed _ "/" _ total _ " checks passed. See failed checks above."
        }
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// List business/routing rule classes (Ens.Rule.Definition subclasses)
/// defined in the active namespace. Routing rules drive RoutingEngine
/// hosts — they decide WHERE each message goes and which transform
/// to apply. Part of production wiring, not data transformation.
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

/// Create a routing rule class (Ens.Rule.Definition) with the supplied
/// RuleDefinition XML. Routing rules drive EnsLib.MsgRouter.RoutingEngine
/// hosts — the engine's BusinessRuleName setting points to the rule class,
/// and the rule's <send transform="..." target="..."/> actions decide where
/// each message goes and how it gets transformed.
///
/// MUTATING — gated by the create_ prefix.
///
/// name:    fully-qualified class name (e.g., "USER.Rule.ADTRouting").
/// ruleXml: full <ruleDefinition>...</ruleDefinition> XML body.
///          See the routing-rules skill for the exact XML grammar.
///          Example for a simple send-all rule:
///          <ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine">
///            <ruleSet name="">
///              <rule name="SendAll">
///                <constraint name="msgClass" value="EnsLib.HL7.Message"/>
///                <when condition="1">
///                  <send transform="My.DTL" target="My.Operation"/>
///                  <return/>
///                </when>
///              </rule>
///            </ruleSet>
///          </ruleDefinition>
ClassMethod CreateRoutingRule(name As %String, ruleXml As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "create_routing_rule"
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" || ($get(ruleXml) = "") {
        Set out.ok = 0
        Set out.error = "Pass `name` (class name) and `ruleXml` (the <ruleDefinition> XML body)."
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
        Set cdef.Super = "Ens.Rule.Definition"
        Set cdef.ProcedureBlock = 1
        ; RuleAssistClass tells the editor which helper to use for this
        ; rule type.  VDocRoutingEngine rules need the VDoc assist.
        Set param = ##class(%Dictionary.ParameterDefinition).%New()
        Set param.Name = "RuleAssistClass"
        Set param.Default = "EnsLib.MsgRouter.VDocRuleAssist"
        Do cdef.Parameters.Insert(param)
        Set xdata = ##class(%Dictionary.XDataDefinition).%New()
        Set xdata.Name = "RuleDefinition"
        Set xdata.XMLNamespace = "http://www.intersystems.com/rule"
        Do xdata.Data.Write(ruleXml)
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
        Set out.message = "Routing rule '" _ name _ "' created. Point a routing engine's BusinessRuleName to this class."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

}
