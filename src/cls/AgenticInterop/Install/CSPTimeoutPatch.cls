/// Bump the CSP gateway Server_Response_Timeout from its default 60s
/// to 300s so agent tool-call loops (which can run 60-180s on complex
/// builds) survive without the gateway dropping the connection.
///
/// Called at Activate phase by module.xml. Idempotent — only writes if
/// the current value is below 300. The CSP.ini change is picked up on
/// the next Apache graceful restart; we trigger one via httpd -k graceful
/// after the write.
Class AgenticInterop.Install.CSPTimeoutPatch Extends %RegisteredObject
{

ClassMethod Apply() As %Status
{
    Set iniPath = "/usr/irissys/csp/bin/CSP.ini"
    If '##class(%File).Exists(iniPath) {
        Write "CSP.ini not found at "_iniPath_"; skipping timeout patch.",!
        Quit $$$OK
    }
    ; Read the file
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set sc = stream.LinkToFile(iniPath)
    If $$$ISERR(sc) Quit sc
    Set content = ""
    While 'stream.AtEnd { Set content = content _ stream.Read(32000) }
    ; Check if already patched
    If content [ "Server_Response_Timeout=300" {
        Write "CSP gateway timeout already set to 300s — no change needed.",!
        Quit $$$OK
    }
    ; Replace timeout values
    Set content = $replace(content, "Server_Response_Timeout=60", "Server_Response_Timeout=300")
    Set content = $replace(content, "Queued_Request_Timeout=60", "Queued_Request_Timeout=300")
    ; Write back
    Set outStream = ##class(%Stream.FileCharacter).%New()
    Set sc = outStream.LinkToFile(iniPath)
    If $$$ISERR(sc) Quit sc
    Do outStream.Write(content)
    Set sc = outStream.%Save()
    If $$$ISERR(sc) Quit sc
    Write "CSP gateway timeouts set to 300s in "_iniPath,!
    ; Graceful restart Apache to pick up the new config
    Set rc = $zf(-1, "/usr/irissys/httpd/bin/httpd -k graceful 2>/dev/null")
    If rc = 0 { Write "Apache graceful restart triggered.",! }
    Else { Write "Could not restart Apache (rc="_rc_"); restart manually.",! }

    ; Bump JWT access token timeout on /api/agentic from the default 60s
    ; to 3600s. The 60s default causes "session expired" on the build
    ; turn: the plan phase takes 30-40s, user reads the plan, and by the
    ; time they type approval the JWT has expired. All silent retry
    ; paths in chat.js re-fetch the same stale token from the parent
    ; frame, so every retry also fails.
    Do ..PatchJWTTimeout()

    Quit $$$OK
}

/// Bump JWTAccessTokenTimeout on EVERY web app in the %ISCMgtPortal
/// group from the default 60s to 3600s. The JWT's exp claim is stamped
/// at issuance by the issuing app's timeout value. Since the Interop
/// Editor can call any of these apps first (and the bridge captures the
/// resulting Bearer), ALL apps in the group must use the longer timeout.
/// Without this, the chatbot's JWT expires mid-conversation and all
/// retry paths fail because the parent frame caches the same stale token.
ClassMethod PatchJWTTimeout() [ Internal ]
{
    New $namespace
    Set $namespace = "%SYS"
    Try {
        Set patched = 0
        Set skipped = 0
        ; Walk every JWT-enabled web app in the Management Portal group
        Set stmt = ##class(%SQL.Statement).%New()
        Set sc = stmt.%Prepare("SELECT Name FROM Security.Applications WHERE JWTAuthEnabled = 1 AND (GroupById = '%ISCMgtPortal' OR Name = '/api/agentic')")
        If $$$ISERR(sc) { Write "JWT patch: SQL prepare failed",! Quit }
        Set rs = stmt.%Execute()
        While rs.%Next() {
            Set appName = rs.Name
            Kill p, props
            Do ##class(Security.Applications).Get(appName, .p)
            If $get(p("JWTAccessTokenTimeout")) < 3600 {
                Set props("JWTAccessTokenTimeout") = 3600
                Set sc = ##class(Security.Applications).Modify(appName, .props)
                If $$$ISOK(sc) {
                    Write "JWT timeout -> 3600s on ", appName, !
                    Set patched = patched + 1
                } Else {
                    Write "FAILED ", appName, ": ", $system.Status.GetErrorText(sc), !
                }
            } Else {
                Set skipped = skipped + 1
            }
        }
        Write "JWT patch complete: ", patched, " updated, ", skipped, " already OK.", !
    } Catch ex {
        Write "JWT timeout patch error: ", ex.DisplayString(), !
    }
}

}
