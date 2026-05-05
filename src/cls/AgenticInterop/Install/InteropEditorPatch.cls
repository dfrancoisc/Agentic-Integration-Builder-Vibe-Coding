/// Patches the IRIS for Health shipped Interop Editor at
/// /usr/irissys/ui/interop/interop-editor/index.html so it loads
/// /agentic/inject.js — which injects the AI Configuration + AI Chatbot
/// buttons at the top of the page.
///
/// Idempotent. Backs up the original to <index.html>.agentic-original
/// the first time it runs. Called by the IPM module's post-install
/// invoke and the corresponding uninstall hook removes the script tag.
///
/// Per restriction #4 (IPM-compliant from day one): zpm load on a
/// clean IRIS for Health instance must produce a working install with
/// no manual file surgery. This class is what makes that true for the
/// Interop-editor banner.
Class AgenticInterop.Install.InteropEditorPatch Extends %RegisteredObject
{

Parameter EDITORHTML = "/usr/irissys/ui/interop/interop-editor/index.html";

Parameter SCRIPTTAG = "<script src=""/agentic/inject.js"" defer></script>";

Parameter MARKER = "agentic/inject.js";

ClassMethod Apply() As %Status
{
    Set tSC = $$$OK
    Try {
        Set path = ..#EDITORHTML
        If '##class(%File).Exists(path) {
            Quit $$$ERROR($$$GeneralError, "Interop editor index.html not found at " _ path _ ". Is this an IRIS for Health install?")
        }

        // Read full body
        Set fs = ##class(%Stream.FileCharacter).%New()
        Set tSC = fs.LinkToFile(path)
        If 'tSC { Quit }
        Set body = ""
        Do fs.Rewind()
        While 'fs.AtEnd { Set body = body _ fs.Read(32768) }

        // Idempotent
        If body [ ..#MARKER {
            Write !,"  InteropEditorPatch: already applied",!
            Quit
        }

        // Backup once
        Set backup = path _ ".agentic-original"
        If '##class(%File).Exists(backup) {
            Set tSC = ##class(%File).CopyFile(path, backup)
            If 'tSC { Quit }
            Write !,"  InteropEditorPatch: backup at ",backup,!
        }

        // Add the cache-busting query so a customer's browser picks up
        // the freshly-installed inject.js on first reload after upgrade.
        Set v = $piece($zhorolog, ".") _ $piece($zhorolog, ".", 2)
        Set tagWithVersion = $replace(..#SCRIPTTAG, "/agentic/inject.js""", "/agentic/inject.js?v="_v_"""")

        // Inject right before </body>
        Set newBody = $replace(body, "</body>", tagWithVersion _ "</body>")
        If newBody = body {
            Quit $$$ERROR($$$GeneralError, "</body> not found in " _ path _ "; manual review required")
        }

        // Write back
        Set out = ##class(%Stream.FileCharacter).%New()
        Set tSC = out.LinkToFile(path)
        If 'tSC { Quit }
        Do out.Clear()
        Do out.Write(newBody)
        Set tSC = out.%Save()
        If 'tSC { Quit }

        Write !,"  InteropEditorPatch: applied to ",path,!
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

ClassMethod Revert() As %Status
{
    Set tSC = $$$OK
    Try {
        Set path = ..#EDITORHTML
        Set backup = path _ ".agentic-original"
        If ##class(%File).Exists(backup) {
            Set tSC = ##class(%File).CopyFile(backup, path, 1)
            If 'tSC { Quit }
            Write !,"  InteropEditorPatch: restored from backup",!
            Quit
        }

        // No backup — strip our script tag in place
        Set fs = ##class(%Stream.FileCharacter).%New()
        Set tSC = fs.LinkToFile(path)
        If 'tSC { Quit }
        Set body = ""
        Do fs.Rewind()
        While 'fs.AtEnd { Set body = body _ fs.Read(32768) }

        If body '[ ..#MARKER {
            Write !,"  InteropEditorPatch: nothing to revert",!
            Quit
        }

        // Strip any <script ...agentic/inject.js...></script>
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

        Write !,"  InteropEditorPatch: stripped script tag",!
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
