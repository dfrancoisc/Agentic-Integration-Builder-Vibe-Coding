/// Patches the shipped IRIS for Health FHIR Server Management Angular app
/// (web app /csp/fhir-management, physical path
/// /usr/irissys/csp/hslib/ui/isc-fhir/index.html) so it loads
/// /agentic/inject.js in FLOATING mode bound to the "fhir-management"
/// chatbot. inject.js then renders a bottom-right launcher that opens the
/// FHIR Specialist agent in a slide-in chat panel.
///
/// Same mechanism as AgenticInterop.Install.InteropEditorPatch: idempotent,
/// backs up the original to <index.html>.agentic-original on first run, and
/// the IPM UnConfigure hook reverts it. If the FHIR Management UI isn't
/// installed on this instance, Apply logs and skips (not an error).
///
/// Per restriction #3 (no UI before login): inject.js hides the launcher
/// while the login screen is showing (floating-mode login detection).
Class AgenticInterop.Install.FHIRManagementPatch Extends %RegisteredObject
{

Parameter PAGEHTML = "/usr/irissys/csp/hslib/ui/isc-fhir/index.html";

Parameter SCRIPTSRC = "/agentic/inject.js?chatbot=fhir-management&mode=header&title=FHIR%20Assistant";

Parameter MARKER = "agentic/inject.js";

ClassMethod Apply() As %Status
{
    Set tSC = $$$OK
    Try {
        Set path = ..#PAGEHTML
        If '##class(%File).Exists(path) {
            Write !,"  FHIRManagementPatch: page not found at ",path," — skipped (FHIR Management UI not installed).",!
            Quit
        }

        Set fs = ##class(%Stream.FileCharacter).%New()
        Set tSC = fs.LinkToFile(path)
        If 'tSC { Quit }
        Set body = ""
        Do fs.Rewind()
        While 'fs.AtEnd { Set body = body _ fs.Read(32768) }

        ; Idempotent
        If body [ ..#MARKER {
            Write !,"  FHIRManagementPatch: already applied",!
            Quit
        }

        ; Backup once
        Set backup = path _ ".agentic-original"
        If '##class(%File).Exists(backup) {
            Set tSC = ##class(%File).CopyFile(path, backup)
            If 'tSC { Quit }
            Write !,"  FHIRManagementPatch: backup at ",backup,!
        }

        ; Cache-busting version so the customer's browser picks up the
        ; freshly-installed inject.js on first reload after upgrade.
        Set v = $piece($zhorolog, ".") _ $piece($zhorolog, ".", 2)
        Set tag = "<script src=""" _ ..#SCRIPTSRC _ "&v=" _ v _ """ defer></script>"

        ; Inject right before </body>
        Set newBody = $replace(body, "</body>", tag _ "</body>")
        If newBody = body {
            Set tSC = $$$ERROR($$$GeneralError, "</body> not found in " _ path _ "; manual review required")
            Quit
        }

        Set out = ##class(%Stream.FileCharacter).%New()
        Set tSC = out.LinkToFile(path)
        If 'tSC { Quit }
        Do out.Clear()
        Do out.Write(newBody)
        Set tSC = out.%Save()
        If 'tSC { Quit }

        Write !,"  FHIRManagementPatch: applied to ",path,!
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

ClassMethod Revert() As %Status
{
    Set tSC = $$$OK
    Try {
        Set path = ..#PAGEHTML
        Set backup = path _ ".agentic-original"
        If ##class(%File).Exists(backup) {
            Set tSC = ##class(%File).CopyFile(backup, path, 1)
            If 'tSC { Quit }
            Write !,"  FHIRManagementPatch: restored from backup",!
            Quit
        }

        If '##class(%File).Exists(path) { Quit }
        Set fs = ##class(%Stream.FileCharacter).%New()
        Set tSC = fs.LinkToFile(path)
        If 'tSC { Quit }
        Set body = ""
        Do fs.Rewind()
        While 'fs.AtEnd { Set body = body _ fs.Read(32768) }

        If body '[ ..#MARKER {
            Write !,"  FHIRManagementPatch: nothing to revert",!
            Quit
        }

        Set start = $find(body, "<script src=""/agentic/inject.js")
        If start = 0 { Quit }
        Set start = start - $length("<script src=""/agentic/inject.js")
        Set end = $find(body, "</script>", start)
        If end = 0 { Quit }
        Set newBody = $extract(body, 1, start - 1) _ $extract(body, end + 1, *)

        Set out = ##class(%Stream.FileCharacter).%New()
        Set tSC = out.LinkToFile(path)
        If 'tSC { Quit }
        Do out.Clear()
        Do out.Write(newBody)
        Set tSC = out.%Save()
        If 'tSC { Quit }

        Write !,"  FHIRManagementPatch: stripped script tag",!
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
