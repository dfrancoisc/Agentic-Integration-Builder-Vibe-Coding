/// %AI.Tool source for production monitoring and diagnostics:
/// event log queries, message header searches, queue depths,
/// and error analysis. Queries run read-only SQL against
/// Ens.MessageHeader and Ens.Util.Log in the active namespace.
///
/// Each public ClassMethod is auto-discovered by the %AI framework
/// as a tool. Compose into a ToolSet via <Include Class="..."/>.
Class AgenticInterop.Tool.Monitoring Extends %AI.Tool
{

/// Resolve the namespace this tool call should run against. Internal.
ClassMethod TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// Query the Ens.Util.Log (Event Log) for recent errors, warnings, or
/// info entries. CALL THIS when the user asks about errors, warnings,
/// event log, "what went wrong", "why is my message failing", or any
/// production troubleshooting question.
///
/// type: log level filter -- "error", "warning", "info", "trace",
///       "assert", or "all" (default "error").
/// hours: how many hours back to search (default 2, max 168).
/// configName: optional business host name filter (exact match).
/// maxRows: max rows to return (default 50, max 200).
///
/// Returns: { ok, namespace, type, hours, rows:[{id, timeLogged,
/// type, configName, text, sessionId, job}], total, truncated }.
/// Read-only.
ClassMethod QueryEventLog(type As %String = "error", hours As %Integer = 2, configName As %String = "", maxRows As %Integer = 50) As %DynamicObject
{
    Set out = {}
    Set targetNs = ..TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Return out
    }
    Try {
        If hours < 1 { Set hours = 1 }
        If hours > 168 { Set hours = 168 }
        If maxRows < 1 { Set maxRows = 1 }
        If maxRows > 200 { Set maxRows = 200 }
        Set out.type = type
        Set out.hours = hours
        ; Build WHERE clause
        Set where = "WHERE TimeLogged >= DATEADD('hour', ?, CURRENT_TIMESTAMP)"
        Set args(1) = -hours
        Set argCount = 1
        If type '= "all", type '= "" {
            Set typeMap("error") = 1
            Set typeMap("warning") = 2
            Set typeMap("info") = 3
            Set typeMap("trace") = 4
            Set typeMap("assert") = 5
            Set typeCode = $get(typeMap($zconvert(type,"L")), "")
            If typeCode '= "" {
                Set where = where _ " AND Type = ?"
                Set argCount = argCount + 1
                Set args(argCount) = typeCode
            }
        }
        If configName '= "" {
            Set where = where _ " AND (ConfigName = ? OR SourceConfigName = ?)"
            Set argCount = argCount + 1
            Set args(argCount) = configName
            Set argCount = argCount + 1
            Set args(argCount) = configName
        }
        Set sql = "SELECT TOP ? ID, TimeLogged, Type, ConfigName, "
        Set sql = sql _ "SourceConfigName, Text, SessionId, Job "
        Set sql = sql _ "FROM Ens_Util.Log "
        Set sql = sql _ where
        Set sql = sql _ " ORDER BY TimeLogged DESC"
        ; Prepend maxRows as first positional arg, shift others
        Set finalArgs(1) = maxRows
        For ai=1:1:argCount { Set finalArgs(ai+1) = args(ai) }
        Set argCount = argCount + 1
        ; Execute with variable args
        If argCount = 2 {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, finalArgs(1), finalArgs(2))
        } ElseIf argCount = 3 {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, finalArgs(1), finalArgs(2), finalArgs(3))
        } ElseIf argCount = 4 {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, finalArgs(1), finalArgs(2), finalArgs(3), finalArgs(4))
        } ElseIf argCount = 5 {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, finalArgs(1), finalArgs(2), finalArgs(3), finalArgs(4), finalArgs(5))
        } Else {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, finalArgs(1))
        }
        Set rows = []
        Set count = 0
        While rs.%Next() {
            Set entry = {}
            Set entry.id = rs.%Get("ID")
            Set entry.timeLogged = rs.%Get("TimeLogged")
            Set typeVal = rs.%Get("Type")
            Set typeLabels = $listbuild("error","warning","info","trace","assert")
            Set entry.type = $select(typeVal>0&&(typeVal<6):$listget(typeLabels,typeVal), 1:"unknown")
            Set entry.configName = rs.%Get("ConfigName")
            Set entry.sourceConfigName = rs.%Get("SourceConfigName")
            Set rawText = rs.%Get("Text")
            ; Truncate long error texts to keep response manageable
            Set entry.text = $select($length(rawText)>500:$extract(rawText,1,497)_"...", 1:rawText)
            Set entry.sessionId = rs.%Get("SessionId")
            Set entry.job = rs.%Get("Job")
            Do rows.%Push(entry)
            Set count = count + 1
        }
        Set out.rows = rows
        Set out.total = count
        Set out.truncated = (count >= maxRows)
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = ex.DisplayString()
    }
    Return out
}

/// Get the top N most frequent errors from Ens.Util.Log grouped by
/// business host and error text. CALL THIS when the user asks
/// "top errors", "most common failures", "error summary", or
/// "group errors by host".
///
/// hours: how many hours back to search (default 2, max 168).
/// topN: number of top error groups to return (default 10, max 50).
///
/// Returns: { ok, namespace, hours, groups:[{configName,
/// text, count, firstSeen, lastSeen}], totalErrors }.
/// Read-only.
ClassMethod TopErrors(hours As %Integer = 2, topN As %Integer = 10) As %DynamicObject
{
    Set out = {}
    Set targetNs = ..TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Return out
    }
    Try {
        If hours < 1 { Set hours = 1 }
        If hours > 168 { Set hours = 168 }
        If topN < 1 { Set topN = 1 }
        If topN > 50 { Set topN = 50 }
        Set out.hours = hours
        Set sql = "SELECT TOP ? ConfigName, Text, COUNT(*) AS ErrorCount, "
        Set sql = sql _ "MIN(TimeLogged) AS FirstSeen, MAX(TimeLogged) AS LastSeen "
        Set sql = sql _ "FROM Ens_Util.Log "
        Set sql = sql _ "WHERE TimeLogged >= DATEADD('hour', ?, CURRENT_TIMESTAMP) "
        Set sql = sql _ "AND Type = 1 "
        Set sql = sql _ "GROUP BY ConfigName, Text "
        Set sql = sql _ "ORDER BY ErrorCount DESC"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, topN, -hours)
        Set groups = []
        Set totalErrors = 0
        While rs.%Next() {
            Set entry = {}
            Set entry.configName = rs.%Get("ConfigName")
            Set rawText = rs.%Get("Text")
            Set entry.text = $select($length(rawText)>300:$extract(rawText,1,297)_"...", 1:rawText)
            Set entry.count = +rs.%Get("ErrorCount")
            Set entry.firstSeen = rs.%Get("FirstSeen")
            Set entry.lastSeen = rs.%Get("LastSeen")
            Set totalErrors = totalErrors + entry.count
            Do groups.%Push(entry)
        }
        Set out.groups = groups
        Set out.totalErrors = totalErrors
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = ex.DisplayString()
    }
    Return out
}

/// Query Ens.MessageHeader for messages in a specific status.
/// CALL THIS when the user asks about "stuck messages",
/// "suspended messages", "errored messages", "message status",
/// "what messages failed", or message-level troubleshooting.
///
/// status: message status filter -- "Error", "Suspended",
///         "Deferred", "Queued", or "all" (default "Error").
/// hours: how many hours back to search (default 2, max 168).
/// maxRows: max rows to return (default 50, max 200).
///
/// Returns: { ok, namespace, status, hours, rows:[{id,
/// timeCreated, status, sourceConfigName, targetConfigName,
/// sourceBusinessType, targetBusinessType, messageBodyClassName,
/// isError, errorStatus, sessionId, priority}], total,
/// truncated }. Read-only.
ClassMethod QueryMessageStatus(status As %String = "Error", hours As %Integer = 2, maxRows As %Integer = 50) As %DynamicObject
{
    Set out = {}
    Set targetNs = ..TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Return out
    }
    Try {
        If hours < 1 { Set hours = 1 }
        If hours > 168 { Set hours = 168 }
        If maxRows < 1 { Set maxRows = 1 }
        If maxRows > 200 { Set maxRows = 200 }
        Set out.status = status
        Set out.hours = hours
        Set sql = "SELECT TOP ? ID, TimeCreated, Status, "
        Set sql = sql _ "SourceConfigName, TargetConfigName, "
        Set sql = sql _ "SourceBusinessType, TargetBusinessType, "
        Set sql = sql _ "MessageBodyClassName, IsError, "
        Set sql = sql _ "ErrorStatus, SessionId, Priority "
        Set sql = sql _ "FROM Ens.MessageHeader "
        Set sql = sql _ "WHERE TimeCreated >= DATEADD('hour', ?, CURRENT_TIMESTAMP)"
        Set argCount = 2
        Set args(1) = maxRows
        Set args(2) = -hours
        If status '= "all", status '= "" {
            Set sql = sql _ " AND Status = ?"
            Set argCount = argCount + 1
            Set args(argCount) = status
        }
        Set sql = sql _ " ORDER BY TimeCreated DESC"
        If argCount = 2 {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, args(1), args(2))
        } Else {
            Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, args(1), args(2), args(3))
        }
        Set rows = []
        Set count = 0
        While rs.%Next() {
            Set entry = {}
            Set entry.id = rs.%Get("ID")
            Set entry.timeCreated = rs.%Get("TimeCreated")
            Set entry.status = rs.%Get("Status")
            Set entry.sourceConfigName = rs.%Get("SourceConfigName")
            Set entry.targetConfigName = rs.%Get("TargetConfigName")
            Set entry.sourceBusinessType = rs.%Get("SourceBusinessType")
            Set entry.targetBusinessType = rs.%Get("TargetBusinessType")
            Set entry.messageBodyClassName = rs.%Get("MessageBodyClassName")
            Set entry.isError = +rs.%Get("IsError")
            Set errSt = rs.%Get("ErrorStatus")
            If errSt '= "", errSt '= 1 {
                Set entry.errorStatus = $select($length(errSt)>300:$extract(errSt,1,297)_"...", 1:errSt)
            }
            Set entry.sessionId = rs.%Get("SessionId")
            Set entry.priority = rs.%Get("Priority")
            Do rows.%Push(entry)
            Set count = count + 1
        }
        Set out.rows = rows
        Set out.total = count
        Set out.truncated = (count >= maxRows)
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = ex.DisplayString()
    }
    Return out
}

/// Summarize message counts by status and business host for the
/// given time window. CALL THIS for "message summary", "how many
/// messages processed", "production throughput", "message volume",
/// or dashboard-style overview queries.
///
/// hours: how many hours back to search (default 2, max 168).
///
/// Returns: { ok, namespace, hours, byStatus:[{status, count}],
/// byHost:[{configName, role, completed, errored, total}],
/// grandTotal }. Read-only.
ClassMethod MessageSummary(hours As %Integer = 2) As %DynamicObject
{
    Set out = {}
    Set targetNs = ..TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Return out
    }
    Try {
        If hours < 1 { Set hours = 1 }
        If hours > 168 { Set hours = 168 }
        Set out.hours = hours
        ; By status
        Set sql = "SELECT Status, COUNT(*) AS Cnt "
        Set sql = sql _ "FROM Ens.MessageHeader "
        Set sql = sql _ "WHERE TimeCreated >= DATEADD('hour', ?, CURRENT_TIMESTAMP) "
        Set sql = sql _ "GROUP BY Status ORDER BY Cnt DESC"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, -hours)
        Set byStatus = []
        Set grand = 0
        While rs.%Next() {
            Set entry = {}
            Set entry.status = rs.%Get("Status")
            Set entry.count = +rs.%Get("Cnt")
            Set grand = grand + entry.count
            Do byStatus.%Push(entry)
        }
        Set out.byStatus = byStatus
        Set out.grandTotal = grand
        ; By target host — completed vs errored
        Set sql2 = "SELECT TargetConfigName, "
        Set sql2 = sql2 _ "SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END) AS Completed, "
        Set sql2 = sql2 _ "SUM(CASE WHEN IsError = 1 THEN 1 ELSE 0 END) AS Errored, "
        Set sql2 = sql2 _ "COUNT(*) AS Total "
        Set sql2 = sql2 _ "FROM Ens.MessageHeader "
        Set sql2 = sql2 _ "WHERE TimeCreated >= DATEADD('hour', ?, CURRENT_TIMESTAMP) "
        Set sql2 = sql2 _ "AND TargetConfigName IS NOT NULL AND TargetConfigName <> '' "
        Set sql2 = sql2 _ "GROUP BY TargetConfigName ORDER BY Total DESC"
        Set rs2 = ##class(%SQL.Statement).%ExecDirect(, sql2, -hours)
        Set byHost = []
        While rs2.%Next() {
            Set entry = {}
            Set entry.configName = rs2.%Get("TargetConfigName")
            Set entry.completed = +rs2.%Get("Completed")
            Set entry.errored = +rs2.%Get("Errored")
            Set entry.total = +rs2.%Get("Total")
            Do byHost.%Push(entry)
        }
        Set out.byHost = byHost
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = ex.DisplayString()
    }
    Return out
}

/// Check queue depths for all active business hosts. CALL THIS
/// when the user asks "are queues backing up", "queue depth",
/// "is anything stuck", or production health checks.
///
/// Returns: { ok, namespace, queues:[{configName, count}],
/// totalQueued }. Read-only.
ClassMethod QueueStatus() As %DynamicObject
{
    Set out = {}
    Set targetNs = ..TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Return out
    }
    Try {
        Set sql = "SELECT TargetConfigName, COUNT(*) AS Cnt "
        Set sql = sql _ "FROM Ens.MessageHeader "
        Set sql = sql _ "WHERE Status = 'Queued' "
        Set sql = sql _ "GROUP BY TargetConfigName ORDER BY Cnt DESC"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        Set queues = []
        Set totalQueued = 0
        While rs.%Next() {
            Set entry = {}
            Set entry.configName = rs.%Get("TargetConfigName")
            Set entry.count = +rs.%Get("Cnt")
            Set totalQueued = totalQueued + entry.count
            Do queues.%Push(entry)
        }
        Set out.queues = queues
        Set out.totalQueued = totalQueued
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = ex.DisplayString()
    }
    Return out
}

}
