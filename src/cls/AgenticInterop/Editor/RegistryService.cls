/// Read-only listings used by the admin UI to populate dropdowns and
/// summary tables. All queries hit %Dictionary.Compiled* via SQL so
/// results stay fresh after a save.
Class AgenticInterop.Editor.RegistryService Extends %RegisteredObject
{

/// GET /api/agentic/registry/agents
/// Lists every class that extends %AI.Agent, including the shipped
/// HealthInterop and any user-authored AgenticInterop.User.Agent.* clones.
ClassMethod ListAgents(pResponse As %CSP.Response, pRequest As %CSP.Request) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, Description, Abstract FROM %Dictionary.CompiledClass " _
        "WHERE PrimarySuper [ '~%AI.Agent~' AND Name [ 'AgenticInterop.' " _
        "ORDER BY Name")
    Set arr = []
    While rs.%Next() {
        Set row = {
            "class": (rs.%Get("Name")),
            "description": (rs.%Get("Description")),
            "abstract": (rs.%Get("Abstract"))
        }
        Set row.name = ##class(AgenticInterop.Editor.Util).ParamDefault(rs.%Get("Name"), "NAME")
        Do arr.%Push(row)
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, {"agents": (arr)})
}

/// GET /api/agentic/registry/mcps
/// Every class extending AgenticInterop.MCP.Base.
ClassMethod ListMCPs(pResponse As %CSP.Response, pRequest As %CSP.Request) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, Description, Abstract FROM %Dictionary.CompiledClass " _
        "WHERE PrimarySuper [ '~AgenticInterop.MCP.Base~' AND Name <> 'AgenticInterop.MCP.Base' " _
        "ORDER BY Name")
    Set arr = []
    While rs.%Next() {
        Set cls = rs.%Get("Name")
        Set row = {
            "class": (cls),
            "description": (rs.%Get("Description")),
            "abstract": (rs.%Get("Abstract")),
            "name":        (##class(AgenticInterop.Editor.Util).ParamDefault(cls, "NAME")),
            "shortDescription": (##class(AgenticInterop.Editor.Util).ParamDefault(cls, "DESCRIPTION")),
            "toolsetsCsv": (##class(AgenticInterop.Editor.Util).ParamDefault(cls, "TOOLSETS"))
        }
        Set row.toolsets = ##class(AgenticInterop.Editor.Util).CsvToArray(row.toolsetsCsv)
        Do arr.%Push(row)
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, {"mcps": (arr)})
}

/// GET /api/agentic/registry/toolsets
/// Every class extending %AI.ToolSet (excluding the base itself).
ClassMethod ListToolSets(pResponse As %CSP.Response, pRequest As %CSP.Request) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, Description FROM %Dictionary.CompiledClass " _
        "WHERE PrimarySuper [ '~%AI.ToolSet~' AND Name <> '%AI.ToolSet' AND Name [ 'AgenticInterop.' " _
        "ORDER BY Name")
    Set arr = []
    While rs.%Next() {
        Set cls = rs.%Get("Name")
        Set row = {
            "class": (cls),
            "description": (rs.%Get("Description")),
            "name": (##class(AgenticInterop.Editor.Util).ParamDefault(cls, "NAME"))
        }
        // Count tools in XData Definition (best-effort — empty stub yields 0).
        Set toolCount = 0
        Try {
            Set body = ##class(AgenticInterop.Editor.Util).XDataBody(cls, "Definition")
            If body '= "" {
                Set obj = ##class(%DynamicAbstractObject).%FromJSON(body)
                If $isobject(obj), $isobject(obj.tools) { Set toolCount = obj.tools.%Size() }
            }
        } Catch {}
        Set row.toolCount = toolCount
        Do arr.%Push(row)
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, {"toolsets": (arr)})
}

/// GET /api/agentic/registry/skills
/// Every class extending AgenticInterop.Skill.Base (excluding the base).
ClassMethod ListSkills(pResponse As %CSP.Response, pRequest As %CSP.Request) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, Description FROM %Dictionary.CompiledClass " _
        "WHERE PrimarySuper [ '~AgenticInterop.Skill.Base~' AND Name <> 'AgenticInterop.Skill.Base' " _
        "ORDER BY Name")
    Set arr = []
    While rs.%Next() {
        Set cls = rs.%Get("Name")
        Set row = {
            "class": (cls),
            "description": (rs.%Get("Description")),
            "toolsCsv": (##class(AgenticInterop.Editor.Util).ParamDefault(cls, "TOOLS"))
        }
        Set row.toolsets = ##class(AgenticInterop.Editor.Util).CsvToArray(row.toolsCsv)
        Do arr.%Push(row)
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, {"skills": (arr)})
}

}
