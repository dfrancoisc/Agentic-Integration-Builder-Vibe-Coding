/// REST handlers for namespace cleanup operations:
///
///   POST   /api/agentic/cleanup/productions
///          Stop and clean any suspended/stuck production in the
///          user's active namespace so new productions can start.
///
///   GET    /api/agentic/cleanup/artifacts
///          List custom (user-created) Productions, DTLs, and
///          Routing Rules in the user's active namespace. Core classes
///          shipped with IRIS for Health (mapped from HSLIB/ENSLIB)
///          are excluded.
///
///   DELETE /api/agentic/cleanup/artifacts
///          Delete all custom artifacts listed by the GET endpoint.
///          Stops any running production first.
///
/// All three respect the X-IRIS-Namespace header (or the ?namespace=
/// query parameter sent by inject.js). Without it they fall back to
/// the dispatch namespace (HSCUSTOM).
///
/// Response JSON is written inline (not via Util.WriteJSON) because
/// after switching $namespace the AgenticInterop classes are not
/// visible in the target namespace.
Class AgenticInterop.Editor.CleanupService Extends %RegisteredObject
{

/// Resolve the namespace this request targets. Reads the
/// X-IRIS-Namespace header first (set by the chat iframe),
/// then falls back to the ?namespace query param (set by
/// inject.js cleanup buttons), then to $namespace.
ClassMethod %TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch {}
    If ns = "" {
        Try { Set ns = $get(%request.Data("namespace", 1)) } Catch {}
    }
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// Write a %DynamicObject as JSON response. Inlined here so it
/// works after a $namespace switch (Util class not visible in
/// the target namespace).
ClassMethod %WriteResponse(pResponse As %CSP.Response, pObj As %DynamicObject, pStatus As %String = "200 OK") [ Internal ]
{
    Set pResponse.Status = pStatus
    Set pResponse.ContentType = "application/json"
    Do pObj.%ToJSON()
}

/// Stop any running/suspended production and clear stale state
/// so the namespace is ready for a fresh production.
ClassMethod CleanProductions(pResponse As %CSP.Response) As %Status
{
    Set targetNs = ..%TargetNs()
    Set out = {}
    Set out.namespace = targetNs
    Set out.actions = []
    Set nsOk = 1
    New $namespace
    Try { Set $namespace = targetNs } Catch {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Set nsOk = 0
    }
    If nsOk {
        Try {
            ; Check current production state
            Set sc = ##class(Ens.Director).GetProductionStatus(.prodName, .prodState)
            Set out.previousProduction = $get(prodName, "")
            Set out.previousState = +$get(prodState, 0)

            ; State: 1=Running, 2=Stopped, 3=Suspended/Troubled, 4=NetworkStopped
            If out.previousState = 1 {
                ; Running — stop it first
                Set sc = ##class(Ens.Director).StopProduction(, 1)
                Set action = {}
                Set action.action = "StopProduction"
                Set action.production = prodName
                Set action.ok = +$$$ISOK(sc)
                Do out.actions.%Push(action)
            }

            If out.previousState '= 0 {
                ; Clean the production state (handles suspended, troubled, stale)
                Do ##class(Ens.Director).CleanProduction(out.previousProduction)
                Set action = {}
                Set action.action = "CleanProduction"
                Set action.production = out.previousProduction
                Set action.ok = 1
                Do out.actions.%Push(action)
            }

            ; Also clean with empty name to fully reset the Director
            Do ##class(Ens.Director).CleanProduction("")
            Set action = {}
            Set action.action = "ResetDirector"
            Set action.ok = 1
            Do out.actions.%Push(action)

            ; Verify final state
            Do ##class(Ens.Director).GetProductionStatus(.finalName, .finalState)
            Set out.finalProduction = $get(finalName, "")
            Set out.finalState = +$get(finalState, 0)
            Set out.ok = 1
            Set out.message = "Production state cleared in " _ targetNs _ ". Namespace is ready for a new production."
        } Catch ex {
            Set out.ok = 0
            Set out.error = $extract(ex.DisplayString(), 1, 400)
        }
    }
    If nsOk {
        Do ..%WriteResponse(pResponse, out)
    } Else {
        Do ..%WriteResponse(pResponse, out, "400 Bad Request")
    }
    Quit $$$OK
}

/// List custom (user-created) artifacts in the user's active namespace.
/// A class is "custom" when its .cls source is NOT mapped from a
/// system database (HSLIB, ENSLIB, etc.).
///
/// Returns productions, DTLs, BPLs, and routing rules.
ClassMethod ListArtifacts(pResponse As %CSP.Response) As %Status
{
    Set targetNs = ..%TargetNs()
    Set out = {}
    Set out.namespace = targetNs
    Set nsOk = 1
    New $namespace
    Try { Set $namespace = targetNs } Catch {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Set nsOk = 0
    }
    If nsOk {
        Try {
            ; --- Productions (extend Ens.Production) ---
            Set out.productions = ..FindCustomClasses(
                "Ens.Production",
                "production")

            ; --- DTLs (extend Ens.DataTransformDTL) ---
            Set out.dtls = ..FindCustomClasses(
                "Ens.DataTransformDTL",
                "dtl")

            ; --- BPLs (extend Ens.BusinessProcessBPL) ---
            Set out.bpls = ..FindCustomClasses(
                "Ens.BusinessProcessBPL",
                "bpl")

            ; --- Routing Rules (extend Ens.Rule.Definition) ---
            Set out.routingRules = ..FindCustomClasses(
                "Ens.Rule.Definition",
                "routingRule")

            ; Summary counts
            Set out.totalProductions = out.productions.%Size()
            Set out.totalDTLs = out.dtls.%Size()
            Set out.totalBPLs = out.bpls.%Size()
            Set out.totalRoutingRules = out.routingRules.%Size()
            Set out.totalArtifacts = out.totalProductions + out.totalDTLs + out.totalBPLs + out.totalRoutingRules
            Set out.ok = 1
        } Catch ex {
            Set out.ok = 0
            Set out.error = $extract(ex.DisplayString(), 1, 400)
        }
    }
    If nsOk {
        Do ..%WriteResponse(pResponse, out)
    } Else {
        Do ..%WriteResponse(pResponse, out, "400 Bad Request")
    }
    Quit $$$OK
}

/// Delete all custom artifacts found by ListArtifacts.
/// Stops any running production first.
ClassMethod DeleteArtifacts(pResponse As %CSP.Response) As %Status
{
    Set targetNs = ..%TargetNs()
    Set out = {}
    Set out.namespace = targetNs
    Set out.deleted = []
    Set out.errors = []
    Set nsOk = 1
    New $namespace
    Try { Set $namespace = targetNs } Catch {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Set nsOk = 0
    }
    If nsOk {
        Try {
            ; Stop any running production first
            Do ##class(Ens.Director).GetProductionStatus(.prodName, .prodState)
            If +$get(prodState, 0) = 1 {
                Do ##class(Ens.Director).StopProduction(, 1)
            }
            If +$get(prodState, 0) '= 0 {
                Do ##class(Ens.Director).CleanProduction($get(prodName, ""))
                Do ##class(Ens.Director).CleanProduction("")
            }

            ; Collect all custom artifacts
            Set classes = ##class(%DynamicArray).%New()
            ; Order matters: delete productions last (they reference hosts)
            ; Delete rules and DTLs first, then BPLs, then productions
            Do ..CollectCustomClasses("Ens.Rule.Definition", classes)
            Do ..CollectCustomClasses("Ens.DataTransformDTL", classes)
            Do ..CollectCustomClasses("Ens.BusinessProcessBPL", classes)
            Do ..CollectCustomClasses("Ens.Production", classes)

            ; Delete each one
            Set iter = classes.%GetIterator()
            While iter.%GetNext(.key, .clsName) {
                Set sc = $system.OBJ.Delete(clsName, "-d")
                If $$$ISOK(sc) {
                    Set d = {}
                    Set d.class = clsName
                    Set d.ok = 1
                    Do out.deleted.%Push(d)
                } Else {
                    Set e = {}
                    Set e.class = clsName
                    Set e.error = $system.Status.GetErrorText(sc)
                    Do out.errors.%Push(e)
                }
            }

            Set out.totalDeleted = out.deleted.%Size()
            Set out.totalErrors = out.errors.%Size()
            Set out.ok = 1
            Set out.message = "Deleted " _ out.totalDeleted _ " artifact(s) in " _ targetNs _ "."
        } Catch ex {
            Set out.ok = 0
            Set out.error = $extract(ex.DisplayString(), 1, 400)
        }
    }
    If nsOk {
        Do ..%WriteResponse(pResponse, out)
    } Else {
        Do ..%WriteResponse(pResponse, out, "400 Bad Request")
    }
    Quit $$$OK
}

/// Find custom classes that extend pSuper. A class is custom when
/// its source is NOT mapped (i.e., it lives in the local namespace
/// database, not mapped from HSLIB/ENSLIB/system databases).
/// Also excludes our own AgenticInterop.* package.
/// MUST be called after $namespace is already switched to the target.
ClassMethod FindCustomClasses(pSuper As %String, pKind As %String) As %DynamicArray [ Internal ]
{
    Set arr = []
    Set sql = "SELECT Name, Super, Description FROM %Dictionary.CompiledClass "
        _ "WHERE (Super = ? OR Super [ ? OR Super [ ?) "
        _ "AND Name NOT LIKE 'AgenticInterop.%' "
        _ "AND Name NOT LIKE '%Abstract%' "
        _ "ORDER BY Name"
    Set superPrefix = pSuper _ ","
    Set superSuffix = "," _ pSuper
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pSuper, superPrefix, superSuffix)
    While rs.%Next() {
        Set clsName = rs.%Get("Name")
        ; Skip system/mapped classes — IsMapped returns 1 for
        ; classes from HSLIB, ENSLIB, or any mapped database
        If ##class(%RoutineMgr).IsMapped(clsName _ ".cls") { Continue }
        ; Skip known system prefixes that might not be read-only
        ; in development namespaces
        If $extract(clsName, 1, 4) = "Ens." { Continue }
        If $extract(clsName, 1, 7) = "EnsLib." { Continue }
        If $extract(clsName, 1, 3) = "HS." { Continue }
        If $extract(clsName, 1, 1) = "%" { Continue }
        Set item = {}
        Set item.class = clsName
        Set item.kind = pKind
        Set desc = rs.%Get("Description")
        If desc '= "" { Set item.description = $extract(desc, 1, 200) }
        Do arr.%Push(item)
    }
    Quit arr
}

/// Collect custom class names into a %DynamicArray (names only, for deletion).
ClassMethod CollectCustomClasses(pSuper As %String, pArray As %DynamicArray) [ Internal ]
{
    Set found = ..FindCustomClasses(pSuper, "")
    Set iter = found.%GetIterator()
    While iter.%GetNext(.key, .item) {
        Do pArray.%Push(item.class)
    }
}

}
