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
        Set effective = ##class(AgenticInterop.Editor.Overlay).GetEffectiveToolSet(cls)
        Set row = {
            "class": (cls),
            "description": (effective.description),
            "name":        (effective.name),
            "customized":  (effective.customized)
        }
        ; Count tools from XData Definition (XML, not JSON).
        ; Self-closing <Include Class="X"/> means all tools from that provider;
        ; <Filter Tool="Y"/> counts as one tool; <Tool Name="Z"/> counts as one.
        Set toolCount = 0
        Try {
            Set defXml = ##class(AgenticInterop.Editor.Util).XDataBody(cls, "Definition")
            If defXml '= "" {
                Set lines = $length(defXml, $char(10))
                Set inFiltered = 0
                For li=1:1:lines {
                    Set ln = $piece(defXml, $char(10), li)
                    If ln [ "<Include " {
                        If ln [ "/>" {
                            ; Self-closing — all tools from that provider class
                            Set incCls = ##class(AgenticInterop.Editor.ToolSetService).%XmlAttr(ln, "Class")
                            If incCls '= "" {
                                Set toolCount = toolCount + ##class(AgenticInterop.Editor.ToolSetService).%CountProviderTools(incCls)
                            }
                        } Else {
                            Set inFiltered = 1
                        }
                    }
                    ElseIf inFiltered, ln [ "</Include>" { Set inFiltered = 0 }
                    ElseIf inFiltered, ln [ "<Filter " { Set toolCount = toolCount + 1 }
                    ElseIf ln [ "<Tool " { Set toolCount = toolCount + 1 }
                }
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
