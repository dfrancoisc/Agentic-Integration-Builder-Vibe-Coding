/// Map the AgenticInterop package from HSCUSTOM into the other namespaces
/// the chatbot may operate against (FHIR, USER, PAYER). Without this mapping,
/// any monitoring/CRUD tool that switches `$namespace` to the user's selected
/// namespace and then calls back into `AgenticInterop.Agent.Manager.ToolDone`
/// throws `<CLASS DOES NOT EXIST>` because the AgenticInterop.* classes only
/// live in the HSCUSTOM code database. With the mapping, the runtime resolves
/// AgenticInterop.* against the HSCUSTOM database even when the process is
/// executing in another namespace's context.
///
/// HSCUSTOM remains the only namespace where AgenticInterop code is *deployed*.
/// This class only adds *visibility* mappings — no code copy, no other-namespace
/// install steps.
///
/// Called at Activate phase by module.xml. Idempotent: a duplicate Create returns
/// "already exists" and we treat that as success.
Class AgenticInterop.Install.PackageMapping Extends %RegisteredObject
{

/// Namespaces the chatbot may target. Each gets a package mapping. We skip
/// namespaces that do not exist on the box; this is normal in dev (PAYER may
/// not be provisioned, etc.).
Parameter TARGETNAMESPACES = "FHIR,USER,PAYER";

/// Database that holds the AgenticInterop code. By convention HSCUSTOM is the
/// only deployment target (see project memory: hscustom_foundational).
Parameter CODEDATABASE = "HSCUSTOM";

/// Package to map.
Parameter PACKAGE = "AgenticInterop";

ClassMethod Apply() As %Status
{
    Set originalNs = $namespace
    Set status = $$$OK
    Try {
        Set $namespace = "%SYS"
        Set targets = ..#TARGETNAMESPACES
        Set db = ..#CODEDATABASE
        Set pkg = ..#PACKAGE
        For i = 1:1:$length(targets, ",") {
            Set ns = $piece(targets, ",", i)
            If ns = "" { Continue }
            ; Skip namespaces that don't exist on this box (typical: dev has FHIR but not PAYER)
            If '##class(Config.Namespaces).Exists(ns) {
                Write "PackageMapping: skipping "_ns_" (namespace not present)",!
                Continue
            }
            Kill props
            Set props("Database") = db
            Set sc = ##class(Config.MapPackages).Create(ns, pkg, .props)
            If $$$ISERR(sc) {
                ; "Package map ... already exists" is a no-op success.
                ; IRIS reports this as error #422 in 2026.x — match by
                ; the literal substring so we are version-tolerant.
                Set errText = $system.Status.GetErrorText(sc)
                If errText [ "already exists" {
                    Write "PackageMapping: "_ns_" -> "_pkg_" already mapped",!
                } Else {
                    Write "PackageMapping: FAILED for "_ns_": "_errText,!
                    Set status = sc
                }
            } Else {
                Write "PackageMapping: added "_ns_" -> "_pkg_" -> "_db,!
            }
        }
    } Catch ex {
        Set status = ex.AsStatus()
    }
    Set $namespace = originalNs
    Quit status
}

ClassMethod Revert() As %Status
{
    Set originalNs = $namespace
    Set status = $$$OK
    Try {
        Set $namespace = "%SYS"
        Set targets = ..#TARGETNAMESPACES
        Set pkg = ..#PACKAGE
        For i = 1:1:$length(targets, ",") {
            Set ns = $piece(targets, ",", i)
            If ns = "" { Continue }
            If '##class(Config.Namespaces).Exists(ns) { Continue }
            Set sc = ##class(Config.MapPackages).Delete(ns, pkg)
            If $$$ISERR(sc) {
                ; Tolerate "does not exist" so uninstall is idempotent.
                Set errText = $system.Status.GetErrorText(sc)
                If errText [ "does not exist" {
                    Write "PackageMapping: "_ns_" -> "_pkg_" was not mapped (already removed)",!
                } Else {
                    Write "PackageMapping: revert FAILED for "_ns_": "_errText,!
                }
            } Else {
                Write "PackageMapping: removed "_ns_" -> "_pkg,!
            }
        }
    } Catch ex {
        Set status = ex.AsStatus()
    }
    Set $namespace = originalNs
    Quit status
}

}
