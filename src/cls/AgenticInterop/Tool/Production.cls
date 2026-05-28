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
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListProductions")
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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListProductions", out)
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
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetProduction")
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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetProduction", out)
    Quit out
}

/// Start the named production. MUTATING — gated by the confirmation
/// policy via the start_ prefix.
///
/// PRECONDITIONS — do NOT call this until ALL of these are done:
/// 1. All DTL classes created and compiled (CreateDTL)
/// 2. All routing rule classes created and compiled (CreateRoutingRule)
/// 3. The production exists (CreateProduction)
/// 4. All business hosts added (AddBusinessHost)
/// 5. All host settings configured (UpdateBusinessHostSettings for EVERY host)
///    - Services: TargetConfigNames, MessageSchemaCategory, adapter ports/paths
///    - Routing engines: BusinessRuleName, Validation=""
///    - Operations: adapter settings (FilePath, IPAddress, Port, etc.)
///    - All file-based hosts: directories must exist on disk
///
/// Starting before settings are configured causes silent failures:
/// services send nowhere, routers crash, file hosts error with #5005.
///
/// production: fully-qualified production class name.
ClassMethod StartProduction(production As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("StartProduction")
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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("StartProduction", out)
    Quit out
}

/// Stop the active production in the active namespace. MUTATING —
/// gated by the confirmation policy via the stop_ prefix.
///
/// timeout: graceful-stop timeout in seconds (default 30).
/// force:   if 1, hard-stop after the grace period instead of waiting.
ClassMethod StopProduction(timeout As %Integer = 30, force As %Boolean = 0) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("StopProduction")
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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("StopProduction", out)
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
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("CreateProduction")
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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateProduction", out)
    Quit out
}

/// Delete a production class — class definition removed from the
/// namespace. MUTATING — gated by the delete_ prefix. The active
/// production cannot be deleted; stop it first.
///
/// name: fully-qualified production class name.
ClassMethod DeleteProduction(name As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("DeleteProduction")
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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteProduction", out)
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
///
/// NOTE: When adding an EnsLib.HL7.MsgRouter.RoutingEngine host,
/// ALWAYS follow up with UpdateBusinessHostSettings to set
/// Validation="" (Host target). Without this, the routing engine
/// validates segment ordering against the schema and rejects
/// real-world messages that have segments in non-standard order
/// (e.g., GT1 after IN1) with "ErrMapSegUnrecog".
/// Returns 1 if `pName` is a RUNTIME-only property on the host class
/// `pHostClass` and therefore must NOT be written as an Ens production-item
/// Setting. The canonical case: OAuthClientName and SessionId on
/// HS.FHIRServer.Interop.HTTPOperation (and any HS.FHIRServer.API.RestClient
/// subclass). These are inherited PROPERTIES that the framework populates on
/// the outbound HS.FHIRServer.Interop.Request at request time; they are
/// absent from the host class's SETTINGS parameter, so writing them as a
/// Host setting makes Ens log "ErrProductionSettingInvalid" on every
/// production start. AddBusinessHost / UpdateBusinessHostSettings skip such
/// settings and report them under `skippedSettings`. Only applies to
/// target="Host" settings.
ClassMethod RuntimeOnlyHostSetting(pHostClass As %String, pTarget As %String, pName As %String) As %Boolean [ Internal ]
{
    If pTarget '= "Host" { Return 0 }
    If (pName '= "OAuthClientName") && (pName '= "SessionId") { Return 0 }
    If pHostClass [ "FHIRServer.Interop.HTTPOperation" { Return 1 }
    Try {
        If ##class(%Dictionary.CompiledClass).%ExistsId(pHostClass),
           $classmethod(pHostClass, "%Extends", "HS.FHIRServer.API.RestClient") { Return 1 }
    } Catch  {}
    Return 0
}

ClassMethod AddBusinessHost(production As %String, hostName As %String, hostClass As %String, settings As %DynamicObject = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("AddBusinessHost")
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
            Set skipped = []
            If $isobject(settings) {
                Set tIter = settings.%GetIterator()
                While tIter.%GetNext(.target, .nameMap) {
                    If '$isobject(nameMap) { Continue }
                    Set nIter = nameMap.%GetIterator()
                    While nIter.%GetNext(.sname, .svalue) {
                        ; Skip runtime-only properties (e.g. OAuthClientName on
                        ; FHIR HTTP operations) that are not valid Ens settings.
                        If ..RuntimeOnlyHostSetting(hostClass, target, sname) {
                            Set skipEntry = {}
                            Set skipEntry.target = target
                            Set skipEntry.name = sname
                            Set skipEntry.reason = "runtime-only property of "_hostClass_", not a production-item Setting — populate it on the outbound request at runtime instead"
                            Do skipped.%Push(skipEntry)
                            Continue
                        }
                        Set s = ##class(Ens.Config.Setting).%New()
                        Set s.Target = target
                        Set s.Name   = sname
                        Set s.Value  = $select($isobject(svalue):svalue.%ToJSON(), 1:svalue)
                        Do item.Settings.Insert(s)
                    }
                }
            }
            If skipped.%Size() > 0 { Set out.skippedSettings = skipped }
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
            ; If production is running, tell the runtime about the new host
            Set isRunning = 0
            Try {
                Set st = ##class(Ens.Director).GetProductionStatus(.pname, .pstate)
                If pname = production, pstate = 1 { Set isRunning = 1 }
            } Catch {}
            If isRunning {
                Set sc2 = ##class(Ens.Director).UpdateProduction()
                If '$$$ISOK(sc2) {
                    Set out.warning = "Host added but runtime update failed: " _ $system.Status.GetErrorText(sc2) _ ". Restart the production to pick up changes."
                }
            }
            Set out.ok = 1
            Set out.added = 1
            Set out.message = "Added host '" _ hostName _ "' (class " _ hostClass _ ") to production '" _ production _ "'."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("AddBusinessHost", out)
    Quit out
}

/// Remove a business host from a production. MUTATING — gated by
/// the remove_ prefix.
///
/// production: fully-qualified production class name.
/// hostName:   the logical host name to remove.
ClassMethod RemoveBusinessHost(production As %String, hostName As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("RemoveBusinessHost")
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
        ; If production is running, tell the runtime about the removed host
        Set isRunning = 0
        Try {
            Set st = ##class(Ens.Director).GetProductionStatus(.pname, .pstate)
            If pname = production, pstate = 1 { Set isRunning = 1 }
        } Catch {}
        If isRunning {
            Set sc2 = ##class(Ens.Director).UpdateProduction()
            If '$$$ISOK(sc2) {
                Set out.warning = "Host removed but runtime update failed: " _ $system.Status.GetErrorText(sc2)
            }
        }
        Set out.ok = 1
        Set out.removed = 1
        Set out.message = "Removed host '" _ hostName _ "' from production '" _ production _ "'."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("RemoveBusinessHost", out)
    Quit out
}

/// Update settings on an existing business host — overwrites
/// settings whose (target, name) match, inserts new ones, leaves
/// others untouched. MUTATING — gated by the update_ prefix.
///
/// If the production is running, changes are applied immediately
/// via Ens.Director.UpdateProduction().
///
/// production: fully-qualified production class name.
/// hostName:   the host whose settings to update.
/// settings:   { "Host": { "name": "value" }, "Adapter": { "name": "value" } }.
///     The top-level keys are the setting target: "Host", "Adapter", or "Item".
///     Nested keys are setting names, values are setting values.
///     Example: { "Host": { "TargetConfigNames": "MyRouter", "MessageSchemaCategory": "2.5" },
///                "Adapter": { "FilePath": "/tmp/in/", "FileSpec": "*.hl7" } }
ClassMethod UpdateBusinessHostSettings(production As %String, hostName As %String, settings As %DynamicObject) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("UpdateBusinessHostSettings")
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
            Set out.error = "Pass a settings object: { ""Host"": { ""name"": ""value"" }, ""Adapter"": { ""name"": ""value"" } }."
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
        Set settingsBefore = item.Settings.Count()
        Set updates = []
        Set skipped = []
        Set tIter = settings.%GetIterator()
        While tIter.%GetNext(.target, .nameMap) {
            If '$isobject(nameMap) { Continue }
            Set nIter = nameMap.%GetIterator()
            While nIter.%GetNext(.sname, .svalue) {
                ; Skip runtime-only properties (e.g. OAuthClientName on FHIR
                ; HTTP operations) — they are not valid Ens settings and make
                ; the production log ErrProductionSettingInvalid on start.
                If ..RuntimeOnlyHostSetting(item.ClassName, target, sname) {
                    Set skipEntry = {}
                    Set skipEntry.target = target
                    Set skipEntry.name = sname
                    Set skipEntry.reason = "runtime-only property of "_item.ClassName_", not a production-item Setting — populate it on the outbound request at runtime instead"
                    Do skipped.%Push(skipEntry)
                    Continue
                }
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
        ; Persist to the production class XData
        Set sc = prod.SaveToClass()
        If 'sc {
            Set out.ok = 0
            Set out.error = "SaveToClass failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set sc = $SYSTEM.OBJ.Compile(production, "ck-d")
        If 'sc {
            Set out.ok = 0
            Set out.error = "Saved but compile failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        ; If production is running, apply changes to the live runtime
        Set isRunning = 0
        Try {
            Set st = ##class(Ens.Director).GetProductionStatus(.pname, .pstate)
            If pname = production, pstate = 1 { Set isRunning = 1 }
        } Catch {}
        If isRunning {
            Set sc = ##class(Ens.Director).UpdateProduction()
            If 'sc {
                Set out.ok = 1
                Set out.updated = updates
                Set out.warning = "Saved but UpdateProduction failed: " _ $system.Status.GetErrorText(sc) _ ". Restart the production to apply."
            }
        }
        ; Report count from the in-memory object (already saved)
        Set settingsAfter = item.Settings.Count()
        Set out.ok = 1
        Set out.updated = updates
        If skipped.%Size() > 0 { Set out.skippedSettings = skipped }
        Set out.settingsBefore = settingsBefore
        Set out.settingsAfter = settingsAfter
        Set out.message = "Updated " _ updates.%Size() _ " setting(s) on host '" _ hostName _ "'. Settings count: " _ settingsBefore _ " -> " _ settingsAfter _ "."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("UpdateBusinessHostSettings", out)
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
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("PostBuildValidation")
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
        Kill reachedMap
        While rs4.%Next() {
            Set tgt = rs4.%Get("TargetConfigName")
            Do c6.hostsReached.%Push(tgt)
            Set reachedMap($zconvert(tgt, "U")) = 1
        }
        ; Compare reached hosts to production hosts (case-insensitive)
        ; Dead-letter / fallback hosts are optional — their purpose is to
        ; catch failures, so they may legitimately receive zero messages
        ; during a clean test run. Mark them as info, not failures.
        Set unreached = ""
        Set unreachedOptional = ""
        For i=1:1:hostCount {
            Set item = prod.Items.GetAt(i)
            Set hName = item.Name
            ; Services don't appear as TargetConfigName — skip them
            Set hClass = item.ClassName
            Set isService = (hClass [ "Service") || (hClass [ "service")
            If 'isService, '$data(reachedMap($zconvert(hName, "U"))) {
                ; Check if this is a dead-letter/fallback host (optional in clean runs)
                Set hNameUp = $zconvert(hName, "U")
                Set isFallback = (hNameUp [ "DEADLETTER") || (hNameUp [ "DEAD-LETTER") || (hNameUp [ "DEAD_LETTER") || (hNameUp [ "DLQ") || (hNameUp [ "FALLBACK") || (hNameUp [ "ERROR")
                If isFallback {
                    Set unreachedOptional = unreachedOptional _ $select(unreachedOptional="":"", 1:", ") _ hName
                } Else {
                    Set unreached = unreached _ $select(unreached="":"", 1:", ") _ hName
                }
            }
        }
        If unreached = "" {
            Set c6.pass = 1
            If unreachedOptional '= "" {
                Set c6.detail = "Messages reached all required hosts. Optional (dead-letter/fallback) hosts with no traffic: " _ unreachedOptional _ " (expected in clean test runs)."
            } Else {
                Set c6.detail = "Messages reached all non-service hosts."
            }
        } ElseIf totalMsgs = 0 {
            Set c6.pass = 0
            Set c6.detail = "No messages — cannot verify pipeline coverage."
            Set allPass = 0
        } Else {
            Set c6.pass = 0
            Set c6.detail = "These hosts received no messages: " _ unreached
            If unreachedOptional '= "" {
                Set c6.detail = c6.detail _ ". Optional (dead-letter/fallback) hosts also empty: " _ unreachedOptional
            }
            Set allPass = 0
        }
        Do out.checks.%Push(c6)

        ; --- Check 7: Critical settings populated ---
        Set c7 = {}
        Set c7.check = "settings_configured"
        Set missingSettings = ""
        ; Re-open production to get fresh item data after any changes
        Set prod7 = ##class(Ens.Config.Production).%OpenId(production)
        If $isobject(prod7) {
            For i=1:1:prod7.Items.Count() {
                Set item = prod7.Items.GetAt(i)
                Set hName = item.Name
                Set hClass = item.ClassName
                ; Build a lookup of setting name -> value for this item
                Kill sMap
                For si=1:1:item.Settings.Count() {
                    Set s = item.Settings.GetAt(si)
                    Set sMap(s.Target, s.Name) = s.Value
                }
                ; Check services: need TargetConfigNames
                If (hClass [ "Service") || (hClass [ "service") {
                    If $get(sMap("Host","TargetConfigNames")) = "" {
                        Set missingSettings = missingSettings _ $select(missingSettings="":"", 1:"; ") _ hName _ ": missing Host.TargetConfigNames"
                    }
                    ; HL7 services need MessageSchemaCategory
                    If hClass [ "HL7" {
                        If $get(sMap("Host","MessageSchemaCategory")) = "" {
                            Set missingSettings = missingSettings _ $select(missingSettings="":"", 1:"; ") _ hName _ ": missing Host.MessageSchemaCategory (HL7 messages will have no DocType)"
                        }
                    }
                }
                ; Check routing engines: need BusinessRuleName
                If hClass [ "RoutingEngine" {
                    If $get(sMap("Host","BusinessRuleName")) = "" {
                        Set missingSettings = missingSettings _ $select(missingSettings="":"", 1:"; ") _ hName _ ": missing Host.BusinessRuleName (every message will crash)"
                    }
                }
                ; Check file-based operations/services: need FilePath
                If (hClass [ "File") && (hClass '[ "RoutingEngine") {
                    If $get(sMap("Adapter","FilePath")) = "" {
                        Set missingSettings = missingSettings _ $select(missingSettings="":"", 1:"; ") _ hName _ ": missing Adapter.FilePath"
                    } Else {
                        ; Verify directory exists
                        Set dir = $get(sMap("Adapter","FilePath"))
                        If '##class(%File).DirectoryExists(dir) {
                            Set missingSettings = missingSettings _ $select(missingSettings="":"", 1:"; ") _ hName _ ": directory does not exist: " _ dir
                        }
                    }
                }
            }
        }
        If missingSettings = "" {
            Set c7.pass = 1
            Set c7.detail = "All critical settings are configured."
        } Else {
            Set c7.pass = 0
            Set c7.detail = missingSettings
            Set allPass = 0
        }
        Do out.checks.%Push(c7)

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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("PostBuildValidation", out)
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
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListBusinessRules")
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
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListBusinessRules", out)
    Quit out
}

/// Create or update a routing rule class (Ens.Rule.Definition) with
/// the supplied RuleDefinition XML. Idempotent: if the class already
/// exists, its XData is replaced and recompiled.
///
/// Routing rules drive EnsLib.MsgRouter.RoutingEngine hosts — the
/// engine's BusinessRuleName setting points to the rule class, and
/// the rule's <send transform="..." target="..."/> actions decide
/// where each message goes and how it gets transformed.
///
/// IMPORTANT - Transform placement: In IRIS, the transform is applied
/// during the <send> action, NOT before rules evaluate. The rule
/// conditions evaluate the INCOMING message. To transform ADT->ORU
/// before sending to an operation, put the transform on the <send>:
///   <send transform="My.Transform" target="My.Operation"/>
///
/// IMPORTANT - HL7 VDoc path syntax: Use CURLY BRACES for HL7 virtual
/// document property access in conditions: HL7.{MSH:9.1} — NOT
/// HL7.(MSH:9.1). Parentheses silently fail to resolve and the
/// condition always evaluates false.
///
/// IMPORTANT - Boolean AND: Use &amp;&amp; (double ampersand) for AND,
/// not the word AND. In XML attributes, escape as &amp;amp;&amp;amp;
///
/// MUTATING — gated by the create_ prefix.
///
/// name:    fully-qualified class name (e.g., "USER.Rule.ADTRouting").
/// ruleXml: full <ruleDefinition>...</ruleDefinition> XML body.
///          See the routing-rules skill for the exact XML grammar.
///          Example — route ADT^A01 to an operation with transformation:
///          <ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine">
///            <ruleSet name="">
///              <rule name="RouteADT">
///                <constraint name="msgClass" value="EnsLib.HL7.Message"/>
///                <when condition="HL7.{MSH:9.1}=&quot;ADT&quot;&amp;&amp;HL7.{MSH:9.2}=&quot;A01&quot;">
///                  <send transform="My.DTL" target="My.Operation"/>
///                  <return/>
///                </when>
///              </rule>
///              <rule name="DeadLetter">
///                <constraint name="msgClass" value="EnsLib.HL7.Message"/>
///                <when condition="1">
///                  <send transform="" target="My.DeadLetter"/>
///                  <return/>
///                </when>
///              </rule>
///            </ruleSet>
///          </ruleDefinition>
ClassMethod CreateRoutingRule(name As %String, ruleXml As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("CreateRoutingRule")
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
        ; ---- Validate constraint names in the ruleXml ----
        ; Only source, msgClass, docCategory, docName are valid for VDocRuleAssist.
        ; Any other name causes <PROPERTY DOES NOT EXIST>RuntimeConstraintCheck
        ; at runtime. Catch this early rather than letting the production crash.
        Set validNames = $listbuild("source","msgClass","docCategory","docName")
        Set warnings = ""
        Set searchPos = 1
        For {
            Set found = $find(ruleXml, "constraint name=""", searchPos)
            Quit:found=0
            Set endQuote = $find(ruleXml, """", found)
            If endQuote > 0 {
                Set cName = $extract(ruleXml, found, endQuote - 2)
                If '$listfind(validNames, cName) {
                    Set warnings = warnings _ $select(warnings'="": ", ", 1:"") _ cName
                }
            }
            Set searchPos = $select(endQuote>0: endQuote, 1: found + 1)
        }
        If warnings '= "" {
            Set out.ok = 0
            Set out.created = 0
            Set out.error = "Invalid constraint name(s): " _ warnings _ ". Valid names for VDocRuleAssist are: source, msgClass, docCategory, docName. Using invalid names causes <PROPERTY DOES NOT EXIST> crash at runtime."
            Quit
        }
        ; ---- Check context attribute for HL7 rules ----
        ; If ruleXml contains msgClass EnsLib.HL7.Message but context is
        ; EnsLib.MsgRouter.RoutingEngine (base), warn that it should be
        ; EnsLib.HL7.MsgRouter.RoutingEngine for HL7 routing.
        If (ruleXml [ "EnsLib.HL7.Message") && (ruleXml [ "context=""EnsLib.MsgRouter.RoutingEngine""") && '(ruleXml [ "context=""EnsLib.HL7.MsgRouter.RoutingEngine""") {
            Set out.ok = 0
            Set out.created = 0
            Set out.error = "HL7 routing rules MUST use context=""EnsLib.HL7.MsgRouter.RoutingEngine"" (not the base EnsLib.MsgRouter.RoutingEngine). The base engine cannot evaluate HL7 virtual document properties."
            Quit
        }
        ; ---- Validate HL7 VDoc expression syntax ----
        ; HL7 virtual document paths in conditions MUST use curly braces:
        ; HL7.{MSH:9.1} not HL7.(MSH:9.1). Parentheses silently fail to
        ; resolve and the condition always evaluates false.
        If ruleXml [ "HL7.(" {
            Set out.ok = 0
            Set out.created = 0
            Set out.error = "HL7 virtual document paths must use curly braces, not parentheses. Use HL7.{MSH:9.1} instead of HL7.(MSH:9.1). Parentheses silently fail to resolve."
            Quit
        }
        ; ---- Auto-correct: docName constraint must match DTL SOURCE, not TARGET ----
        ; Common error: routing rule has docName="ORU_R01" but the referenced
        ; DTL converts ADT_A01 -> ORU_R01. Rules evaluate the INCOMING message.
        ; Instead of rejecting (which causes the agent to enter a costly error-fix
        ; loop), auto-correct the constraint and condition expressions to match
        ; the incoming type. This handles the "transform before routing" pattern
        ; that users describe but IRIS implements as transform-on-send.
        Set correctionNote = ""
        ; Collect docName constraint values
        Set docNameVals = ""
        Set sp4 = 1
        For {
            Set f4 = $find(ruleXml, "constraint name=""docName"" value=""", sp4)
            Quit:f4=0
            Set eq4 = $find(ruleXml, """", f4)
            If eq4 > 0 {
                Set dnVal = $extract(ruleXml, f4, eq4 - 2)
                If dnVal '= "" { Set docNameVals = docNameVals _ $select(docNameVals'="":"|",1:"") _ dnVal }
            }
            Set sp4 = $select(eq4>0:eq4, 1:f4+1)
        }
        ; Collect transform class names from <send> elements
        Set xformClasses = ""
        Set sp5 = 1
        For {
            Set f5 = $find(ruleXml, "transform=""", sp5)
            Quit:f5=0
            Set eq5 = $find(ruleXml, """", f5)
            If eq5 > 0 {
                Set xfVal = $extract(ruleXml, f5, eq5 - 2)
                If xfVal '= "" { Set xformClasses = xformClasses _ $select(xformClasses'="":"|",1:"") _ xfVal }
            }
            Set sp5 = $select(eq5>0:eq5, 1:f5+1)
        }
        ; Cross-validate and auto-correct if docName matches DTL TARGET type
        If docNameVals '= "" && (xformClasses '= "") {
            For xi=1:1:$length(xformClasses, "|") {
                Set dtlCls = $piece(xformClasses, "|", xi)
                If dtlCls = "" Continue
                Try {
                    If ##class(%Dictionary.CompiledXData).%ExistsId(dtlCls_"||DTLBody") {
                        Set xdObj = ##class(%Dictionary.CompiledXData).%OpenId(dtlCls_"||DTLBody")
                        Set xdText = xdObj.Data.Read(8000)
                        Set srcStruct = ""
                        Set tgtStruct = ""
                        Set pSrc = $find(xdText, "sourceDocType=""")
                        If pSrc > 0 { Set pSrc2 = $find(xdText, """", pSrc) If pSrc2 > 0 { Set srcStruct = $piece($extract(xdText, pSrc, pSrc2-2), ":", 2) } }
                        Set pTgt = $find(xdText, "targetDocType=""")
                        If pTgt > 0 { Set pTgt2 = $find(xdText, """", pTgt) If pTgt2 > 0 { Set tgtStruct = $piece($extract(xdText, pTgt, pTgt2-2), ":", 2) } }
                        If tgtStruct '= "" && (tgtStruct '= srcStruct) {
                            For di=1:1:$length(docNameVals, "|") {
                                Set dn = $piece(docNameVals, "|", di)
                                If dn = tgtStruct {
                                    ; Auto-correct docName constraint: target -> source
                                    Set ruleXml = $replace(ruleXml, "constraint name=""docName"" value=""" _ tgtStruct _ """", "constraint name=""docName"" value=""" _ srcStruct _ """")
                                    ; Auto-correct condition expressions: fix message code and trigger event
                                    ; e.g. &quot;ORU&quot; -> &quot;ADT&quot; and &quot;R01&quot; -> &quot;A01&quot;
                                    Set tgtCode = $piece(tgtStruct, "_", 1)
                                    Set tgtEvent = $piece(tgtStruct, "_", 2)
                                    Set srcCode = $piece(srcStruct, "_", 1)
                                    Set srcEvent = $piece(srcStruct, "_", 2)
                                    If tgtCode '= srcCode {
                                        Set ruleXml = $replace(ruleXml, "&quot;" _ tgtCode _ "&quot;", "&quot;" _ srcCode _ "&quot;")
                                    }
                                    If tgtEvent '= srcEvent {
                                        Set ruleXml = $replace(ruleXml, "&quot;" _ tgtEvent _ "&quot;", "&quot;" _ srcEvent _ "&quot;")
                                    }
                                    Set correctionNote = "Auto-corrected: docName changed from " _ tgtStruct _ " to " _ srcStruct _ ". Routing rules evaluate the INCOMING message. DTL '" _ dtlCls _ "' converts " _ srcStruct _ " -> " _ tgtStruct _ " during the <send> action."
                                }
                            }
                        }
                    }
                } Catch  {}
            }
        }
        ; ---- Create or update the class ----
        Set isUpdate = ##class(%Dictionary.ClassDefinition).%ExistsId(name)
        If isUpdate {
            ; Upsert: open existing class and replace its XData
            Set cdef = ##class(%Dictionary.ClassDefinition).%OpenId(name)
            ; Find and remove existing RuleDefinition XData
            Set removeIdx = 0
            For i=1:1:cdef.XDatas.Count() {
                If cdef.XDatas.GetAt(i).Name = "RuleDefinition" { Set removeIdx = i Quit }
            }
            If removeIdx > 0 { Do cdef.XDatas.RemoveAt(removeIdx) }
        } Else {
            Set cdef = ##class(%Dictionary.ClassDefinition).%New(name)
            Set cdef.Super = "Ens.Rule.Definition"
            Set cdef.ProcedureBlock = 1
            ; RuleAssistClass tells the editor which helper to use for this
            ; rule type.  VDocRoutingEngine rules need the VDoc assist.
            Set param = ##class(%Dictionary.ParameterDefinition).%New()
            Set param.Name = "RuleAssistClass"
            Set param.Default = "EnsLib.MsgRouter.VDocRuleAssist"
            Do cdef.Parameters.Insert(param)
        }
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
        Set out.created = $select(isUpdate: 0, 1: 1)
        If isUpdate {
            Set out.message = "Routing rule '" _ name _ "' updated. XData replaced and recompiled."
        } Else {
            Set out.message = "Routing rule '" _ name _ "' created. Point a routing engine's BusinessRuleName to this class."
        }
        If correctionNote '= "" {
            Set out.corrected = 1
            Set out.correctionNote = correctionNote
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("CreateRoutingRule", out)
    Quit out
}

/// Read the RuleDefinition XData of a routing/business rule class.
/// CALL THIS before UpdateRoutingRule whenever the user wants to
/// inspect or modify an existing rule. Returns the rule XML plus the
/// rule's context attribute (which determines whether the rule
/// works on HL7 virtual documents vs plain messages). Read-only.
///
/// name: fully-qualified rule class name.
///
/// Returns: { ok, namespace, name, exists, ruleXml?, context?,
/// alias? }.
ClassMethod GetRoutingRule(name As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetRoutingRule")
    Set out = {}
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" {
        Set out.ok = 0
        Set out.error = "Pass `name` (the rule class)."
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
            Set out.exists = 0
            Set out.error = "Class not found: " _ name
            Quit
        }
        Set out.exists = 1
        Set xd = ##class(%Dictionary.XDataDefinition).%OpenId(name _ "||RuleDefinition")
        If '$isobject(xd) {
            Set out.ok = 1
            Set out.error = "Class exists but has no RuleDefinition XData block."
            Quit
        }
        Set body = ""
        Do xd.Data.Rewind()
        While 'xd.Data.AtEnd { Set body = body _ xd.Data.Read(8000) }
        Set out.ruleXml = body
        ; Pull context + alias attributes for quick reference
        For attr = "context","alias" {
            Set p = $find(body, attr _ "=")
            If p > 0 {
                Set tail = $extract(body, p, $length(body))
                Set q = $extract(tail, 1, 1)
                If (q = "'") || (q = """") {
                    Set rest = $extract(tail, 2, $length(tail))
                    Set val = $piece(rest, q, 1)
                    Do out.%Set(attr, val)
                }
            }
        }
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetRoutingRule", out)
    Quit out
}

/// Delete a routing/business rule class — class definition removed
/// from the namespace. MUTATING — gated by the delete_ prefix.
/// Refuses to delete if any business host in the active namespace
/// references the rule via its BusinessRuleName setting — change or
/// remove the host first.
///
/// name: fully-qualified rule class name.
ClassMethod DeleteRoutingRule(name As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("DeleteRoutingRule")
    Set out = {}
    Set out.tool = "delete_routing_rule"
    Set out.name = name
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(name) = "" {
        Set out.ok = 0
        Set out.error = "Pass `name` (the rule class)."
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
            Set out.deleted = 0
            Set out.error = "Class not found: " _ name
            Quit
        }
        ; Refuse if any host setting (any production) sets BusinessRuleName to this rule
        Set referrers = []
        Set sql = "SELECT DISTINCT Production, Name FROM Ens_Config.Item_Settings WHERE Name = 'BusinessRuleName' AND Value = ?"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, name)
        While rs.%Next() {
            Set r = {}
            Set r.production = rs.%Get("Production")
            Set r.hostName = rs.%Get("Name")
            Do referrers.%Push(r)
        }
        If referrers.%Size() > 0 {
            Set out.ok = 0
            Set out.deleted = 0
            Set out.error = "Rule still referenced by host BusinessRuleName settings — change them first."
            Set out.referencedBy = referrers
            Quit
        }
        Set sc = $SYSTEM.OBJ.Delete(name, "-d")
        If 'sc {
            Set out.ok = 0
            Set out.deleted = 0
            Set out.error = "Delete failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.deleted = 1
        Set out.message = "Routing rule '" _ name _ "' deleted from " _ targetNs _ "."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteRoutingRule", out)
    Quit out
}

/// Create a directory (and any missing parent directories) on the
/// IRIS server filesystem. Idempotent: succeeds if directory already
/// exists. Call this for EVERY FilePath configured on file-based
/// business hosts (EnsLib.HL7.Service.FileService,
/// EnsLib.HL7.Operation.FileOperation, etc.) BEFORE starting the
/// production. Without the directories, file-based hosts error on
/// startup. Also create archive/processed subdirectories when the
/// service uses ArchivePath.
ClassMethod EnsureDirectory(path As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("EnsureDirectory")
    Set out = {}
    Set out.tool = "ensure_directory"
    Set out.path = path
    If $get(path) = "" {
        Set out.ok = 0
        Set out.error = "path is required."
        Quit out
    }
    Try {
        If ##class(%Library.File).DirectoryExists(path) {
            Set out.ok = 1
            Set out.existed = 1
            Set out.message = "Directory already exists: " _ path
        } Else {
            Set created = ##class(%Library.File).CreateDirectoryChain(path)
            If created {
                Set out.ok = 1
                Set out.existed = 0
                Set out.message = "Created directory: " _ path
            } Else {
                Set out.ok = 0
                Set out.error = "Failed to create directory: " _ path _ ". Check filesystem permissions."
            }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnsureDirectory", out)
    Quit out
}

/// Internal helper — calls AddBusinessHost if the host doesn't exist
/// in the production, otherwise UpdateBusinessHostSettings. Returns
/// the underlying tool's response unchanged, plus an `action` field
/// of "added" or "updated". Centralises the host-exists check used
/// by every Configure* helper.
ClassMethod %AddOrUpdate(production As %String, hostName As %String, hostClass As %String, settings As %DynamicObject) As %DynamicObject [ Internal ]
{
    Set inv = ..GetProduction(production)
    If 'inv.ok {
        Set r = {}
        Set r.ok = 0
        Set r.error = $select(inv.%IsDefined("error"):inv.error, 1:"GetProduction failed")
        Quit r
    }
    If $select(inv.%IsDefined("exists"):'inv.exists, 1:0) {
        Set r = {}
        Set r.ok = 0
        Set r.error = "Production not found: " _ production
        Quit r
    }
    Set hostExists = 0
    If inv.%IsDefined("items") {
        For i = 0:1:(inv.items.%Size()-1) {
            If inv.items.%Get(i).name = hostName { Set hostExists = 1 Quit }
        }
    }
    If 'hostExists {
        Set r = ..AddBusinessHost(production, hostName, hostClass, settings)
        If r.ok { Set r.action = "added" }
        Quit r
    }
    Set r = ..UpdateBusinessHostSettings(production, hostName, settings)
    If r.ok { Set r.action = "updated" }
    Quit r
}

/// Add (or update) an EnsLib.HL7.Service.TCPService host in a
/// production with HL7-correct defaults baked in. The docs document
/// the trap of leaving MessageSchemaCategory blank (downstream rules
/// silently fail to match) and the FIFO importance of PoolSize=1.
/// This tool sets both correctly. MUTATING — gated by the configure_
/// prefix.
///
/// production:        fully-qualified production class name.
/// hostName:          logical host name (e.g. "HL7.Inbound.MLLP").
/// port:              TCP port the service listens on.
/// targetConfigNames: comma-separated downstream host names (typically
///                    the routing engine or a BPL). REQUIRED.
/// schemaCategory:    HL7 schema category. Default "2.5". Pass
///                    "2.5.1" if any downstream expects SDA conversion
///                    (HL7ToSDA3 only accepts 2.5.1). REQUIRED.
/// framing:           Default "MLLP". See HL7 framing reference for
///                    alternatives (Flexible, AsciiLF, etc.).
/// ackMode:           Default "Immediate". For consumers that can
///                    fail the message use "Application".
/// batchHandling:     Default "Single-Session Batch". If your feed
///                    isn't batched leave the default.
/// poolSize:          Default 1 — required for FIFO ordering of
///                    patient updates. Increase only if order
///                    doesn't matter.
/// jobPerConnection:  Default 1 (per HL7 TCP adapter convention).
/// stayConnected:     Default -1 (stay connected indefinitely).
ClassMethod ConfigureHL7TCPService(production As %String, hostName As %String, port As %String, targetConfigNames As %String, schemaCategory As %String = "2.5", framing As %String = "MLLP", ackMode As %String = "Immediate", batchHandling As %String = "Single-Session Batch", poolSize As %Integer = 1, jobPerConnection As %Boolean = 1, stayConnected As %Integer = -1) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ConfigureHL7TCPService")
    Set out = {}
    Set out.tool = "configure_hl7_tcp_service"
    Set out.production = production
    Set out.hostName = hostName
    Set out.namespace = ..%TargetNs()
    If ($get(production) = "") || ($get(hostName) = "") || ($get(port) = "") || ($get(targetConfigNames) = "") {
        Set out.ok = 0
        Set out.error = "Pass production, hostName, port, targetConfigNames (all required). MessageSchemaCategory is set from schemaCategory and must not be empty — without it, downstream routing rules silently fail to match."
        Quit out
    }
    Try {
        Set settings = {}
        Set hostSet = {}
        Set hostSet.TargetConfigNames = targetConfigNames
        Set hostSet.MessageSchemaCategory = schemaCategory
        Set hostSet.AckMode = ackMode
        Set hostSet.BatchHandling = batchHandling
        Set hostSet.PoolSize = poolSize
        Do settings.%Set("Host", hostSet)
        Set adSet = {}
        Set adSet.Port = port
        Set adSet.Framing = framing
        Set adSet.JobPerConnection = jobPerConnection
        Set adSet.StayConnected = stayConnected
        Do settings.%Set("Adapter", adSet)
        Set r = ..%AddOrUpdate(production, hostName, "EnsLib.HL7.Service.TCPService", settings)
        Set out.ok = r.ok
        If r.%IsDefined("action") { Set out.action = r.action }
        If r.%IsDefined("error") { Set out.error = r.error }
        Set out.settingsApplied = settings
        If out.ok { Set out.message = $select(r.action="added":"Added", 1:"Updated") _ " HL7 TCP service '" _ hostName _ "' on port " _ port _ " in '" _ production _ "'." }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ConfigureHL7TCPService", out)
    Quit out
}

/// Add (or update) an EnsLib.HL7.Operation.TCPOperation host in a
/// production with HL7-correct defaults. MUTATING — gated by the
/// configure_ prefix.
///
/// production:       fully-qualified production class name.
/// hostName:         logical host name (e.g. "HL7.Outbound.MLLP").
/// ipAddress:        target host IP / DNS name. REQUIRED.
/// port:             target TCP port. REQUIRED.
/// framing:          Default "MLLP".
/// getReply:         Default 1 (wait for reply per HL7 convention).
/// replyCodeActions: Default ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C"
///                   per the docs. Adjust :?R for targets that
///                   legitimately reject duplicates.
/// separators:       Default "|^~\\&" (escape backslash in JSON).
/// stayConnected:    Default -1 (stay connected indefinitely).
ClassMethod ConfigureHL7TCPOperation(production As %String, hostName As %String, ipAddress As %String, port As %String, framing As %String = "MLLP", getReply As %Boolean = 1, replyCodeActions As %String = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C", separators As %String = "|^~\&", stayConnected As %Integer = -1) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ConfigureHL7TCPOperation")
    Set out = {}
    Set out.tool = "configure_hl7_tcp_operation"
    Set out.production = production
    Set out.hostName = hostName
    Set out.namespace = ..%TargetNs()
    If ($get(production) = "") || ($get(hostName) = "") || ($get(ipAddress) = "") || ($get(port) = "") {
        Set out.ok = 0
        Set out.error = "Pass production, hostName, ipAddress, port (all required)."
        Quit out
    }
    Try {
        Set settings = {}
        Set hostSet = {}
        Set hostSet.ReplyCodeActions = replyCodeActions
        Set hostSet.Separators = separators
        Do settings.%Set("Host", hostSet)
        Set adSet = {}
        Set adSet.IPAddress = ipAddress
        Set adSet.Port = port
        Set adSet.Framing = framing
        Set adSet.GetReply = getReply
        Set adSet.StayConnected = stayConnected
        Do settings.%Set("Adapter", adSet)
        Set r = ..%AddOrUpdate(production, hostName, "EnsLib.HL7.Operation.TCPOperation", settings)
        Set out.ok = r.ok
        If r.%IsDefined("action") { Set out.action = r.action }
        If r.%IsDefined("error") { Set out.error = r.error }
        Set out.settingsApplied = settings
        If out.ok { Set out.message = $select(r.action="added":"Added", 1:"Updated") _ " HL7 TCP operation '" _ hostName _ "' -> " _ ipAddress _ ":" _ port _ "." }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ConfigureHL7TCPOperation", out)
    Quit out
}

/// Add (or update) an EnsLib.HL7.MsgRouter.RoutingEngine host in a
/// production with `Validation=""` baked in. The docs explicitly warn
/// that the default Validation rejects real-world HL7 traffic
/// (segments arrive in non-standard orders). Use this tool instead of
/// AddBusinessHost + a separate UpdateBusinessHostSettings call — you
/// will forget Validation otherwise and the production will silently
/// drop messages with ErrMapSegUnrecog. MUTATING — gated by the
/// configure_ prefix.
///
/// production:        fully-qualified production class name.
/// hostName:          logical host name (e.g. "HL7.Router").
/// businessRuleName:  fully-qualified rule class name. REQUIRED.
/// validation:        Default "" (recommended). Pass an explicit flag
///                    string (e.g. "dm-z") only if you need
///                    validation and accept the risk.
/// alertOnBadMessage: Default 1.
/// badMessageHandler: Optional — name of a downstream host that
///                    receives validation failures.
ClassMethod ConfigureHL7Router(production As %String, hostName As %String, businessRuleName As %String, validation As %String = "", alertOnBadMessage As %Boolean = 1, badMessageHandler As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ConfigureHL7Router")
    Set out = {}
    Set out.tool = "configure_hl7_router"
    Set out.production = production
    Set out.hostName = hostName
    Set out.namespace = ..%TargetNs()
    If ($get(production) = "") || ($get(hostName) = "") || ($get(businessRuleName) = "") {
        Set out.ok = 0
        Set out.error = "Pass production, hostName, businessRuleName (all required)."
        Quit out
    }
    Try {
        Set settings = {}
        Set hostSet = {}
        Set hostSet.BusinessRuleName = businessRuleName
        Set hostSet.Validation = validation
        Set hostSet.AlertOnBadMessage = alertOnBadMessage
        If $get(badMessageHandler) '= "" { Set hostSet.BadMessageHandler = badMessageHandler }
        Do settings.%Set("Host", hostSet)
        Set r = ..%AddOrUpdate(production, hostName, "EnsLib.HL7.MsgRouter.RoutingEngine", settings)
        Set out.ok = r.ok
        If r.%IsDefined("action") { Set out.action = r.action }
        If r.%IsDefined("error") { Set out.error = r.error }
        Set out.settingsApplied = settings
        If out.ok {
            Set out.message = $select(r.action="added":"Added", 1:"Updated") _ " HL7 router '" _ hostName _ "' with rule '" _ businessRuleName _ "' and Validation='" _ validation _ "'."
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ConfigureHL7Router", out)
    Quit out
}

/// Enable enhanced trace operations for an HS.* business host. The
/// HealthShare hosts (HS.FHIR.*, HS.Gateway.*, HS.SDA3.*, etc.) emit
/// internal $$$HSTRACE events that are invisible by default. To
/// surface them in the Visual Trace this tool (1) adds the
/// HS.Util.Trace.Operations business operation to the production if
/// not already present, and (2) sets the TraceOperations setting on
/// the named HS.* host to the requested level.
///
/// CRITICAL: Turn this off in production environments — FULL tracing
/// has a significant performance cost.
///
/// production:  fully-qualified production class name.
/// hostName:    the HS.* host to instrument.
/// level:       "ERRORSONLY" / "MINIMAL" / "FULL" (default) /
///              empty (disable).
ClassMethod EnableHL7TraceOperations(production As %String, hostName As %String, level As %String = "FULL") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("EnableHL7TraceOperations")
    Set out = {}
    Set out.tool = "enable_hl7_trace_operations"
    Set out.production = production
    Set out.hostName = hostName
    Set out.level = level
    Set out.namespace = ..%TargetNs()
    If ($get(production) = "") || ($get(hostName) = "") {
        Set out.ok = 0
        Set out.error = "Pass production and hostName."
        Quit out
    }
    Try {
        ; Step 1: ensure HS.Util.Trace.Operations is in the production
        Set inv = ..GetProduction(production)
        If 'inv.ok {
            Set out.ok = 0
            Set out.error = $select(inv.%IsDefined("error"):inv.error, 1:"GetProduction failed")
            Quit
        }
        If 'inv.exists {
            Set out.ok = 0
            Set out.error = "Production not found: " _ production
            Quit
        }
        Set traceHostName = "HS.Util.Trace.Operations"
        Set traceExists = 0
        Set targetHostExists = 0
        For i = 0:1:(inv.items.%Size()-1) {
            Set it = inv.items.%Get(i)
            If it.className = "HS.Util.Trace.Operations" { Set traceExists = 1 Set traceHostName = it.name }
            If it.name = hostName { Set targetHostExists = 1 }
        }
        If 'targetHostExists {
            Set out.ok = 0
            Set out.error = "Host '" _ hostName _ "' not found in production. Add it first."
            Quit
        }
        Set out.traceHostName = traceHostName
        If 'traceExists {
            Set addResult = ..AddBusinessHost(production, traceHostName, "HS.Util.Trace.Operations", "")
            If 'addResult.ok {
                Set out.ok = 0
                Set out.error = "Could not add HS.Util.Trace.Operations: " _ $select(addResult.%IsDefined("error"):addResult.error, 1:"unknown")
                Quit
            }
            Set out.traceHostAdded = 1
        } Else {
            Set out.traceHostAdded = 0
        }
        ; Step 2: set TraceOperations on the target host
        Set settings = {}
        Set hostSet = {}
        Set hostSet.TraceOperations = level
        Do settings.%Set("Host", hostSet)
        Set updResult = ..UpdateBusinessHostSettings(production, hostName, settings)
        If 'updResult.ok {
            Set out.ok = 0
            Set out.error = "Could not set TraceOperations on '" _ hostName _ "': " _ $select(updResult.%IsDefined("error"):updResult.error, 1:"unknown")
            Quit
        }
        Set out.ok = 1
        Set out.message = "Trace operations '" _ level _ "' enabled on '" _ hostName _ "'."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("EnableHL7TraceOperations", out)
    Quit out
}

/// List System Default Settings (Ens.Config.DefaultSettings rows).
/// These are environment-specific values that override production
/// definitions at runtime — the recommended mechanism for promoting
/// productions between dev/test/live without editing the class.
/// Wildcards `*` apply to ProductionName, ItemName, HostClassName.
/// Read-only.
///
/// productionFilter: optional substring filter on ProductionName.
/// itemFilter:       optional substring filter on ItemName.
/// settingFilter:    optional substring filter on SettingName.
///
/// Returns: { ok, namespace, defaults:[{production, item, hostClass,
/// setting, value, deployable, description?}], total }.
ClassMethod ListSystemDefaultSettings(productionFilter As %String = "", itemFilter As %String = "", settingFilter As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListSystemDefaultSettings")
    Set out = {}
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    Set out.defaults = []
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set sql = "SELECT ProductionName, ItemName, HostClassName, SettingName, SettingValue, Deployable, Description FROM Ens_Config.DefaultSettings ORDER BY ProductionName, ItemName, HostClassName, SettingName"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        Set count = 0
        Set prodLow = $zconvert($get(productionFilter), "L")
        Set itemLow = $zconvert($get(itemFilter), "L")
        Set settLow = $zconvert($get(settingFilter), "L")
        While rs.%Next() {
            Set prod = rs.%Get("ProductionName")
            Set item = rs.%Get("ItemName")
            Set sett = rs.%Get("SettingName")
            If prodLow '= "" { If '($zconvert(prod, "L") [ prodLow) { Continue } }
            If itemLow '= "" { If '($zconvert(item, "L") [ itemLow) { Continue } }
            If settLow '= "" { If '($zconvert(sett, "L") [ settLow) { Continue } }
            Set d = {}
            Set d.production = prod
            Set d.item = item
            Set d.hostClass = rs.%Get("HostClassName")
            Set d.setting = sett
            Set d.value = rs.%Get("SettingValue")
            Set d.deployable = rs.%Get("Deployable")
            Set desc = rs.%Get("Description")
            If desc '= "" { Set d.description = $extract(desc, 1, 240) }
            Do out.defaults.%Push(d)
            Set count = count + 1
        }
        Set out.total = count
        Set out.ok = 1
        If count = 0 { Set out.hint = "No System Default Settings rows in this namespace. Use SetSystemDefaultSetting to add the first one. Wildcards: ProductionName='*' applies to every production; ItemName='*' applies to every host; HostClassName='*' applies regardless of host class." }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListSystemDefaultSettings", out)
    Quit out
}

/// Read a single System Default Setting row using the same lookup
/// chain that runtime settings resolution uses — 8 wildcard
/// combinations from most-specific to fully-wildcarded. Use this to
/// answer "what value would this host get for setting X at startup
/// if the production class itself doesn't specify it." Read-only.
///
/// productionName: exact production name (no wildcard here — pass the
///                 actual production you want resolution for).
/// itemName:       exact host name in the production.
/// hostClassName:  exact host class name.
/// settingName:    setting name (without the Host: or Adapter: prefix).
/// targetType:     "Host" (default) or "Adapter". Determines whether
///                 the lookup checks rows saved with the "Host:" or
///                 "Adapter:" SettingName prefix first.
///
/// Returns: { ok, namespace, found, value?, productionName,
/// itemName, hostClassName, targetType, settingName }.
ClassMethod GetSystemDefaultSetting(productionName As %String, itemName As %String, hostClassName As %String, settingName As %String, targetType As %String = "Host") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetSystemDefaultSetting")
    Set out = {}
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    Set out.productionName = productionName
    Set out.itemName = itemName
    Set out.hostClassName = hostClassName
    Set out.settingName = settingName
    Set out.targetType = targetType
    If ($get(productionName) = "") || ($get(itemName) = "") || ($get(hostClassName) = "") || ($get(settingName) = "") {
        Set out.ok = 0
        Set out.error = "Pass productionName, itemName, hostClassName, settingName (all required). Use ListSystemDefaultSettings to discover available rows."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set val = ""
        Set found = ##class(Ens.Config.DefaultSettings).%GetSetting(productionName, itemName, hostClassName, $get(targetType, "Host"), settingName, .val)
        Set out.ok = 1
        Set out.found = found
        If found { Set out.value = val }
        If 'found { Set out.hint = "No System Default Setting matches this (production, item, hostClass, setting) tuple — neither exact nor wildcarded. Falls back to InitialExpression or the production-class value." }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetSystemDefaultSetting", out)
    Quit out
}

/// Create or update a System Default Setting row. The 4-part key
/// (ProductionName, ItemName, HostClassName, SettingName) makes this
/// idempotent — calling it twice with different values updates in
/// place. Use `*` for any of the first three keys to match all
/// productions / items / host classes. SettingName can be prefixed
/// with "Host:" or "Adapter:" if you need to disambiguate target
/// type. MUTATING — gated by the set_ prefix.
///
/// productionName: exact production name, or "*" for any production.
/// itemName:       exact host name, or "*" for any host.
/// hostClassName:  exact class name, or "*" for any class.
/// settingName:    setting name. Prefix with "Host:" or "Adapter:"
///                 to scope; bare names match either target.
/// settingValue:   the value to store. Must be a string; non-string
///                 values must be pre-formatted.
/// deployable:     1 (default) means the row is included in
///                 deployment packages; 0 keeps it environment-local.
/// description:    optional human description.
ClassMethod SetSystemDefaultSetting(productionName As %String, itemName As %String, hostClassName As %String, settingName As %String, settingValue As %String, deployable As %Boolean = 1, description As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("SetSystemDefaultSetting")
    Set out = {}
    Set out.tool = "set_system_default_setting"
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    Set out.productionName = productionName
    Set out.itemName = itemName
    Set out.hostClassName = hostClassName
    Set out.settingName = settingName
    If ($get(productionName) = "") || ($get(itemName) = "") || ($get(hostClassName) = "") || ($get(settingName) = "") {
        Set out.ok = 0
        Set out.error = "Pass productionName, itemName, hostClassName, settingName (use `*` for wildcards on the first three)."
        Quit out
    }
    If '$data(settingValue) {
        Set out.ok = 0
        Set out.error = "Pass `settingValue`. To remove a row, use DeleteSystemDefaultSetting instead."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        ; Composite ID = ProductionName||ItemName||HostClassName||SettingName
        Set id = productionName _ "||" _ itemName _ "||" _ hostClassName _ "||" _ settingName
        Set existed = 0
        Set ds = ##class(Ens.Config.DefaultSettings).%OpenId(id)
        If $isobject(ds) {
            Set existed = 1
        } Else {
            Set ds = ##class(Ens.Config.DefaultSettings).%New()
            Set ds.ProductionName = productionName
            Set ds.ItemName = itemName
            Set ds.HostClassName = hostClassName
            Set ds.SettingName = settingName
        }
        Set ds.SettingValue = settingValue
        Set ds.Deployable = deployable
        If $get(description) '= "" { Set ds.Description = description }
        Set sc = ds.%Save()
        If 'sc {
            Set out.ok = 0
            Set out.error = "%Save failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.action = $select(existed:"updated", 1:"created")
        Set out.message = $select(existed:"Updated", 1:"Created") _ " default setting " _ productionName _ "/" _ itemName _ "/" _ hostClassName _ ":" _ settingName _ " = '" _ settingValue _ "'."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("SetSystemDefaultSetting", out)
    Quit out
}

/// Delete a single System Default Setting row by exact (production,
/// item, hostClass, setting) key. Refuses if no matching row exists.
/// MUTATING — gated by the delete_ prefix.
///
/// productionName: exact production name as stored.
/// itemName:       exact item name as stored.
/// hostClassName:  exact host class as stored.
/// settingName:    exact setting name as stored.
ClassMethod DeleteSystemDefaultSetting(productionName As %String, itemName As %String, hostClassName As %String, settingName As %String) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("DeleteSystemDefaultSetting")
    Set out = {}
    Set out.tool = "delete_system_default_setting"
    Set out.productionName = productionName
    Set out.itemName = itemName
    Set out.hostClassName = hostClassName
    Set out.settingName = settingName
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If ($get(productionName) = "") || ($get(itemName) = "") || ($get(hostClassName) = "") || ($get(settingName) = "") {
        Set out.ok = 0
        Set out.error = "Pass productionName, itemName, hostClassName, settingName."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set id = productionName _ "||" _ itemName _ "||" _ hostClassName _ "||" _ settingName
        If '##class(Ens.Config.DefaultSettings).%ExistsId(id) {
            Set out.ok = 1
            Set out.deleted = 0
            Set out.error = "No matching row found for (" _ productionName _ ", " _ itemName _ ", " _ hostClassName _ ", " _ settingName _ ")."
            Quit
        }
        Set sc = ##class(Ens.Config.DefaultSettings).%DeleteId(id)
        If 'sc {
            Set out.ok = 0
            Set out.deleted = 0
            Set out.error = "%DeleteId failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.deleted = 1
        Set out.message = "Deleted default setting " _ productionName _ "/" _ itemName _ "/" _ hostClassName _ ":" _ settingName _ "."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("DeleteSystemDefaultSetting", out)
    Quit out
}

/// Resolve the effective value of a setting at production runtime,
/// using the documented 3-source chain: (1) the production class
/// definition, (2) Ens.Config.DefaultSettings (System Default
/// Settings), (3) the property's InitialExpression on the host class.
/// Returns the value plus a `source` field so the agent can explain
/// "why the value is X" to the user. Read-only.
///
/// For PRODUCTION-LEVEL settings (the production class's own
/// settings like ShutdownTimeout, AlertNotificationManager), pass
/// hostName="" — the tool reads the production's VirtualSettings
/// collection.
///
/// For HOST-LEVEL settings (settings on a specific business host
/// inside the production), pass hostName and the tool reads the
/// item's effective settings.
///
/// production:  fully-qualified production class name.
/// hostName:    host name within the production, or "" for
///              production-level settings.
/// settingName: setting name (no Host:/Adapter: prefix).
/// targetType:  "Host" (default) or "Adapter" — only consulted when
///              hostName is non-empty.
///
/// Returns: { ok, namespace, production, hostName, settingName,
/// found, value?, source? }.
ClassMethod GetEffectiveSetting(production As %String, hostName As %String = "", settingName As %String, targetType As %String = "Host") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("GetEffectiveSetting")
    Set out = {}
    Set out.production = production
    Set out.hostName = hostName
    Set out.settingName = settingName
    Set out.targetType = targetType
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If ($get(production) = "") || ($get(settingName) = "") {
        Set out.ok = 0
        Set out.error = "Pass production and settingName."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If $get(hostName) = "" {
            ; Production-level setting
            Set status = $$$OK
            Set val = ##class(Ens.Director).GetProductionSettingValue(production, settingName, .status)
            If 'status {
                Set out.ok = 1
                Set out.found = 0
                Set out.error = "Production-level setting '" _ settingName _ "' not found for '" _ production _ "': " _ $system.Status.GetErrorText(status)
                Quit
            }
            Set out.ok = 1
            Set out.found = 1
            Set out.value = val
            Set out.source = "Production"
            Quit
        }
        ; Host-level setting — walk the item's settings collection first
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        If '$isobject(prod) {
            Set out.ok = 0
            Set out.error = "Production class not found: " _ production
            Quit
        }
        Set item = ""
        For i = 1:1:prod.Items.Count() {
            Set it = prod.Items.GetAt(i)
            If it.Name = hostName { Set item = it Quit }
        }
        If '$isobject(item) {
            Set out.ok = 0
            Set out.error = "Host '" _ hostName _ "' not found in production '" _ production _ "'."
            Quit
        }
        ; Production-class value: walk the item's Settings collection
        For j = 1:1:item.Settings.Count() {
            Set st = item.Settings.GetAt(j)
            If (st.Name = settingName) && ((st.Target = targetType) || (targetType = "")) {
                Set out.ok = 1
                Set out.found = 1
                Set out.value = st.Value
                Set out.source = "Production"
                Quit
            }
        }
        If out.%IsDefined("found") { Quit }
        ; System Default Setting
        Set val = ""
        Set found = ##class(Ens.Config.DefaultSettings).%GetSetting(production, hostName, item.ClassName, targetType, settingName, .val)
        If found {
            Set out.ok = 1
            Set out.found = 1
            Set out.value = val
            Set out.source = "SystemDefault"
            Quit
        }
        ; InitialExpression fallback — read the property's InitialExpression
        Set initExpr = ""
        Set propId = item.ClassName _ "||" _ settingName
        Set pd = ##class(%Dictionary.PropertyDefinition).%OpenId(propId)
        If $isobject(pd) {
            Set initExpr = pd.InitialExpression
        } Else {
            ; Maybe it's on the adapter
            Set hostClass = item.ClassName
            Set adapterClass = ""
            Try { Set adapterClass = $parameter(hostClass, "ADAPTER") } Catch  {}
            If adapterClass '= "" {
                Set pd2 = ##class(%Dictionary.PropertyDefinition).%OpenId(adapterClass _ "||" _ settingName)
                If $isobject(pd2) { Set initExpr = pd2.InitialExpression }
            }
        }
        If initExpr '= "" {
            Set out.ok = 1
            Set out.found = 1
            Set out.value = initExpr
            Set out.source = "InitialExpression"
            Set out.note = "Value is the property's InitialExpression — the runtime evaluates this ObjectScript expression at startup."
            Quit
        }
        Set out.ok = 1
        Set out.found = 0
        Set out.source = "NotSet"
        Set out.note = "No value found anywhere in the resolution chain. Runtime will use the property's empty default."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("GetEffectiveSetting", out)
    Quit out
}

/// Resolve a filename time-stamp specification to the literal string
/// IRIS would produce right now, by wrapping Ens.Util.File.CreateTimestamp.
/// Use this whenever the user configures File Name / Archive Path /
/// Working Path on a File or FTP business host and isn't sure how a
/// spec like "%#F_%Q_%+(a0)%$f" will resolve. Read-only.
///
/// spec:       the time-stamp specification (e.g. "%f_%Q",
///             "%Y%m%d-%H%M%S.txt"). Default "%f_%Q" matches the
///             IRIS adapter default.
/// sourceName: simulated source filename for the %f / %F substitutions
///             (default "input.dat"). For TCP services the source is
///             the IP+port concat — pass that here to preview TCP
///             filenames.
///
/// Returns: { ok, namespace, spec, sourceName, resolved }. The
/// resolved field is what Ens.Util.File.CreateTimestamp returned.
ClassMethod PreviewTimestampSpec(spec As %String = "%f_%Q", sourceName As %String = "input.dat") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("PreviewTimestampSpec")
    Set out = {}
    Set out.spec = spec
    Set out.sourceName = sourceName
    Set out.namespace = ..%TargetNs()
    Try {
        Set resolved = ##class(Ens.Util.File).CreateTimestamp(sourceName, spec)
        Set out.ok = 1
        Set out.resolved = resolved
        Set out.note = "Resolved using Ens.Util.File.CreateTimestamp — the same method the File/FTP adapters call at runtime. Format codes are documented in 'Time Stamp Specifications for Filenames'."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("PreviewTimestampSpec", out)
    Quit out
}

/// List the active production message queues in the namespace.
/// Walks the `Ens.Queue:Enumerate` query, returning name, count, and
/// creation timestamp for each queue. The queue name is usually the
/// business host name (`Ens.Actor` for the shared actor pool). Use
/// for runtime diagnostics: backlog detection, idle-host detection,
/// validating that messages reach the expected host. Read-only.
///
/// includeIdle: 1 (default) returns every queue. 0 skips queues
///              with Count=0.
///
/// Returns: { ok, namespace, queues:[{name, count, created}], total,
/// totalMessages }.
ClassMethod ListProductionQueues(includeIdle As %Boolean = 1) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListProductionQueues")
    Set out = {}
    Set out.namespace = ..%TargetNs()
    Set out.queues = []
    Try {
        Set rs = ##class(%ResultSet).%New("Ens.Queue:Enumerate")
        Set sc = rs.Execute()
        If 'sc {
            Set out.ok = 0
            Set out.error = "Enumerate failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set count = 0, totalMsgs = 0
        While rs.Next() {
            Set qName = rs.GetData(1)
            Set qCount = +rs.GetData(2)
            Set qCreated = rs.GetData(3)
            If 'includeIdle, qCount = 0 { Continue }
            Set q = {}
            Set q.name = qName
            Set q.count = qCount
            Set q.created = qCreated
            Do out.queues.%Push(q)
            Set count = count + 1
            Set totalMsgs = totalMsgs + qCount
        }
        Set out.total = count
        Set out.totalMessages = totalMsgs
        Set out.ok = 1
        If count = 0 { Set out.hint = "No queues found. If you expect queues, the production may not have started, or this namespace has no production." }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListProductionQueues", out)
    Quit out
}

/// Release the FIFO message-group hold associated with a specific
/// message header. Wraps Ens.Queue.FIFOMessageGroup.ReleaseHoldByHeaderId.
/// Use when a single stuck message is blocking a FIFO group from
/// progressing (e.g. a downstream system rejected one message and
/// the rest of the group is queued behind it). MUTATING — gated by
/// the release_ prefix.
///
/// messageHeaderId: the Ens.MessageHeader %Id of the stuck message.
///                  Obtain from the Message Viewer or via a SQL
///                  query against Ens_MessageHeader.
/// signalQueue:     1 (default) signals the queue to resume
///                  processing; 0 clears the hold without notifying
///                  the queue (useful when you're about to release
///                  many holds and signal once at the end).
ClassMethod ReleaseFIFOHold(messageHeaderId As %String, signalQueue As %Boolean = 1) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ReleaseFIFOHold")
    Set out = {}
    Set out.tool = "release_fifo_hold"
    Set out.messageHeaderId = messageHeaderId
    Set out.signalQueue = signalQueue
    Set out.namespace = ..%TargetNs()
    If $get(messageHeaderId) = "" {
        Set out.ok = 0
        Set out.error = "Pass `messageHeaderId` — the Ens.MessageHeader Id."
        Quit out
    }
    Try {
        Set sc = ##class(Ens.Queue.FIFOMessageGroup).ReleaseHoldByHeaderId(messageHeaderId, signalQueue)
        If 'sc {
            Set out.ok = 0
            Set out.error = "ReleaseHoldByHeaderId failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.message = "FIFO hold released for header " _ messageHeaderId _ "."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ReleaseFIFOHold", out)
    Quit out
}

/// Release every FIFO message-group hold on a named queue. Wraps
/// Ens.Queue.FIFOMessageGroup.ReleaseHoldForAll. Use for bulk
/// recovery after a downstream outage when the FIFO discipline is
/// no longer needed for the backlog. MUTATING — gated by the
/// release_ prefix.
///
/// queueName:              the queue (usually a business-host name)
///                         whose held messages should be released.
/// onlyCompletedSessions:  1 (default) — only release messages whose
///                         sessions are Complete. 0 — release every
///                         held header on the queue regardless of
///                         session state (use with care).
ClassMethod ReleaseAllFIFOHolds(queueName As %String, onlyCompletedSessions As %Boolean = 1) As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ReleaseAllFIFOHolds")
    Set out = {}
    Set out.tool = "release_all_fifo_holds"
    Set out.queueName = queueName
    Set out.onlyCompletedSessions = onlyCompletedSessions
    Set out.namespace = ..%TargetNs()
    If $get(queueName) = "" {
        Set out.ok = 0
        Set out.error = "Pass `queueName`. Use ListProductionQueues to see available names."
        Quit out
    }
    Try {
        Set sc = ##class(Ens.Queue.FIFOMessageGroup).ReleaseHoldForAll(queueName, onlyCompletedSessions)
        If 'sc {
            Set out.ok = 0
            Set out.error = "ReleaseHoldForAll failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.message = "All FIFO holds released on queue '" _ queueName _ "' (onlyCompletedSessions=" _ onlyCompletedSessions _ ")."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ReleaseAllFIFOHolds", out)
    Quit out
}

/// Validate a Schedule setting string. Parses the documented
/// comma-separated `ACTION:TIMESTAMP` grammar AND calls
/// Ens.Util.Schedule.Evaluate to confirm IRIS accepts the spec at
/// runtime. Returns a per-entry breakdown so the caller can fix the
/// specific entry that's malformed. Read-only.
///
/// schedule:        the Schedule setting value. Empty string is
///                  valid (no schedule = always running).
/// referenceTime:   optional ODBC timestamp to evaluate the schedule
///                  at (default = current time). Used to also report
///                  whether the host would be running RIGHT NOW.
///
/// Returns: { ok, namespace, schedule, valid, entries:[{action,
/// timestamp, valid, error?}], runtimeActive?, parseErrors:[...] }.
ClassMethod ValidateScheduleSpec(schedule As %String, referenceTime As %String = "") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ValidateScheduleSpec")
    Set out = {}
    Set out.schedule = schedule
    Set out.namespace = ..%TargetNs()
    Set out.entries = []
    Set out.parseErrors = []
    If $get(schedule) = "" {
        Set out.ok = 1
        Set out.valid = 1
        Set out.note = "Empty schedule — the host is always running."
        Do ##class(AgenticInterop.Agent.Manager).ToolDone("ValidateScheduleSpec", out)
        Return out
    }
    Try {
        Set valid = 1
        For i = 1:1:$length(schedule, ",") {
            Set piece = $zstrip($piece(schedule, ",", i), "<>W")
            If piece = "" { Continue }
            Set entry = {}
            Set action = $piece(piece, ":", 1)
            Set body = $piece(piece, ":", 2, 99)
            Set entry.action = action
            Set entry.timestamp = body
            Set entry.valid = 1
            If (action '= "START") && (action '= "STOP") {
                Set entry.valid = 0
                Set entry.error = "action must be START or STOP, got '" _ action _ "'"
                Do out.parseErrors.%Push("Entry " _ i _ ": " _ entry.error)
                Set valid = 0
            } ElseIf body = "" {
                Set entry.valid = 0
                Set entry.error = "missing timestamp body after action"
                Do out.parseErrors.%Push("Entry " _ i _ ": " _ entry.error)
                Set valid = 0
            } Else {
                ; Body can be a literal ODBC datetime OR a WEEK-MM-DD weekly pattern OR contain `*` wildcards.
                Set tsOk = 0
                If body [ "WEEK" {
                    Set tsOk = 1
                } ElseIf body [ "*" {
                    Set tsOk = 1
                } Else {
                    Set h = $zdatetimeh(body, 3, , , , , , , , -1)
                    If h '= -1 { Set tsOk = 1 }
                }
                If 'tsOk {
                    Set entry.valid = 0
                    Set entry.error = "timestamp '" _ body _ "' is not parseable as ODBC (YYYY-MM-DDThh:mm:ss), WEEK-MM-DD, or a `*`-wildcard pattern"
                    Do out.parseErrors.%Push("Entry " _ i _ ": " _ entry.error)
                    Set valid = 0
                }
            }
            Do out.entries.%Push(entry)
        }
        Set out.valid = valid
        ; Also run a runtime Evaluate to confirm IRIS accepts it
        Set refTs = $select($get(referenceTime)'="":referenceTime, 1:$zdatetime($horolog, 3))
        Set runtimeActive = ##class(Ens.Util.Schedule).Evaluate(schedule, refTs)
        Set out.runtimeActive = (runtimeActive = 1)
        Set out.referenceTime = refTs
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ValidateScheduleSpec", out)
    Quit out
}

}
