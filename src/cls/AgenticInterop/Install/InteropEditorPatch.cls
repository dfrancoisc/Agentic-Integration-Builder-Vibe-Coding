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

/// Sub-step: widen /ui/interop's CookiePath to "/" so its session
/// cookie is sent to /api/agentic (which lives at a different path).
/// Without this the inject script's /api/agentic/whoami call returns
/// 401 even for an authenticated Interop-Editor user, the launchers
/// never render, and the customer-facing experience looks broken.
///
/// We do not change AutheEnabled or NameSpace — only the cookie scope.
/// Idempotent.
ClassMethod WidenInteropCookiePath() As %Status
{
    Set tSC = $$$OK
    Try {
        New $namespace
        Set $namespace = "%SYS"
        If '##class(Security.Applications).Exists("/ui/interop") { Quit }
        Do ##class(Security.Applications).Get("/ui/interop", .props)
        If $get(props("CookiePath")) = "/" {
            Write !,"  WidenInteropCookiePath: already /",!
            Quit
        }
        Set props("CookiePath") = "/"
        Set tSC = ##class(Security.Applications).Modify("/ui/interop", .props)
        If 'tSC { Quit }
        Write !,"  WidenInteropCookiePath: /ui/interop CookiePath -> /",!
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Disable the CSP gateway's static-file Expires cache on /agentic
/// so that every page load fetches the current chat.js / chat.css /
/// admin.js from disk. Without this IRIS sets Expires: +1h and the
/// user's browser silently serves a stale JS bundle after deploys,
/// breaking features that were just shipped (slash commands, etc.).
/// Idempotent.
ClassMethod DisableStaticFileCache() As %Status
{
    Set tSC = $$$OK
    Try {
        New $namespace
        Set $namespace = "%SYS"
        If '##class(Security.Applications).Exists("/agentic") { Quit }
        Do ##class(Security.Applications).Get("/agentic", .props)
        Set changed = 0
        If $get(props("ServeFilesTimeout")) '= 0 {
            Set props("ServeFilesTimeout") = 0
            Set changed = 1
            Write !,"  DisableStaticFileCache: ServeFilesTimeout -> 0",!
        }
        ; Fix cookie leak: /agentic serves static files and must NOT set
        ; session cookies. UseCookies=1 with CookiePath=/ caused the
        ; session cookie to leak to /api/agentic requests, and the CSP
        ; gateway rejected follow-up chat messages with 401 when the
        ; leaked session went stale during long SSE streams.
        If $get(props("UseCookies")) '= 2 {
            Set props("UseCookies") = 2
            Set changed = 1
            Write !,"  DisableStaticFileCache: UseCookies -> 2 (no session cookies)",!
        }
        If 'changed {
            Write !,"  DisableStaticFileCache: already configured",!
            Quit
        }
        Set tSC = ##class(Security.Applications).Modify("/agentic", .props)
        If 'tSC { Quit }
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

ClassMethod Apply() As %Status
{
    Set tSC = ..WidenInteropCookiePath()
    If 'tSC { Quit tSC }
    Set tSC = ..DisableStaticFileCache()
    If 'tSC { Quit tSC }
    Set tSC = $$$OK
    Try {
        Set path = ..#EDITORHTML
        If '##class(%File).Exists(path) {
            Set tSC = $$$ERROR($$$GeneralError, "Interop editor index.html not found at " _ path _ ". Is this an IRIS for Health install?")
            Quit
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
            Set tSC = $$$ERROR($$$GeneralError, "</body> not found in " _ path _ "; manual review required")
            Quit
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
