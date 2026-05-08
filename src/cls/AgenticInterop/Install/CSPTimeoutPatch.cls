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
    Quit $$$OK
}

}
