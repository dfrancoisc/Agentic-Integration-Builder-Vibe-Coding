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
        Set cls = rs.%Get("Name")
        Set effective = ##class(AgenticInterop.Editor.Overlay).GetEffectiveAgent(cls)
        Set row = {
            "class": (cls),
            "description": (effective.description),
            "abstract": (rs.%Get("Abstract")),
            "name":        (effective.name),
            "customized":  (effective.customized)
        }
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
        // Use the overlay-aware view so the list reflects what the
        // chat runtime actually sees. The shipped .cls Description
        // and Abstract still come from the dictionary row above —
        // they're not user-overridable.
        Set effective = ##class(AgenticInterop.Editor.Overlay).GetEffectiveMCP(cls)
        Set row = {
            "class": (cls),
            "description": (effective.description),
            "abstract": (rs.%Get("Abstract")),
            "name":        (effective.name),
            "shortDescription": (effective.shortDescription),
            "toolsetsCsv": (effective.toolsetsCsv),
            "toolsets":    (effective.toolsets),
            "customized":  (effective.customized)
        }
        Do arr.%Push(row)
    }
    Quit ##class(AgenticInterop.Editor.Util).WriteJSON(pResponse, {"mcps": (arr)})
}

/// GET /api/agentic/registry/toolsets
/// Lists Tool classes (%AI.Tool subclasses) registered in the agent.
/// The ToolSet wrapper layer was removed during the token optimization
/// (duplicate registrations). Manager.Build now registers Tool classes
/// directly via agent.UseToolSet(). This endpoint lists those Tool
/// classes so the admin UI shows the actual tool surface the LLM sees.
ClassMethod ListToolSets(pResponse As %CSP.Response, pRequest As %CSP.Request) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Name, Description FROM %Dictionary.CompiledClass " _
        "WHERE (Super [ '%AI.Tool' OR PrimarySuper [ '~%AI.Tool~') " _
        "AND Name [ 'AgenticInterop.Tool.' " _
        "AND Name <> '%AI.Tool' AND Abstract <> 1 " _
        "ORDER BY Name")
    Set arr = []
    While rs.%Next() {
        Set cls = rs.%Get("Name")
        Set desc = rs.%Get("Description")
        Set row = {
            "class": (cls),
            "description": ($extract(desc, 1, 300)),
            "name": ($piece(cls, ".", $length(cls, ".")))
        }
        ; Count public ClassMethods that are actual tools — the %AI
        ; framework auto-discovers these by name. Skip %-prefixed
        ; system methods inherited from %AI.Tool / %RegisteredObject.
        Set toolCount = 0
        Try {
            Set mrs = ##class(%SQL.Statement).%ExecDirect(,
                "SELECT Name FROM %Dictionary.CompiledMethod " _
                "WHERE parent = ? AND ClassMethod = 1 " _
                "AND Name NOT LIKE '\%%' ESCAPE '\'", cls)
            While mrs.%Next() { Set toolCount = toolCount + 1 }
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
