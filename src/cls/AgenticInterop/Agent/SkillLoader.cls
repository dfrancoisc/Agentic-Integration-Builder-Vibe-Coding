/// Wires AgenticInterop.Skill.* classes onto an %AI.Agent's ToolManager so
/// the LLM sees them as sub-agent tools.
///
/// Per the user's "always use the %AI Framework" restriction, skills are
/// registered the documented way: instantiate the Skill subclass, set
/// ParentAgent, call agent.ToolManager.AddTool(skill).
///
/// Called from AgenticInterop.Agent.Manager.Build() at request time. Not
/// called automatically by IRIS — this is plumbing.
Class AgenticInterop.Agent.SkillLoader Extends %RegisteredObject
{

/// Default v1 skills — the twelve specialist skill classes shipped with the
/// IPM module. Override in a subclass or pass a different list to
/// LoadSkills() to customize per Data.Agent row.
Parameter DEFAULTSKILLS = "AgenticInterop.Skill.Productions,AgenticInterop.Skill.DTL,AgenticInterop.Skill.BPL,AgenticInterop.Skill.RoutingRules,AgenticInterop.Skill.HL7v2,AgenticInterop.Skill.FHIRR4,AgenticInterop.Skill.SDA,AgenticInterop.Skill.RestInProductions,AgenticInterop.Skill.ESBPattern,AgenticInterop.Skill.X12,AgenticInterop.Skill.CDA,AgenticInterop.Skill.Adapters";

/// Instantiate each named Skill class, set ParentAgent, register on the
/// agent's ToolManager. Returns %Status.
///
/// pAgent      The %AI.Agent instance (typically AgenticInterop.Agent.HealthInterop).
/// pSkillCSV   Comma-separated list of fully-qualified Skill class names.
///             Pass "" to use ..#DEFAULTSKILLS.
ClassMethod LoadSkills(pAgent As %AI.Agent, pSkillCSV As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        If pSkillCSV = "" Set pSkillCSV = ..#DEFAULTSKILLS

        For i=1:1:$length(pSkillCSV, ",") {
            Set tClassName = $piece(pSkillCSV, ",", i)
            Set tClassName = $zstrip(tClassName, "<>W")
            Continue:tClassName=""

            // Verify the class exists and is a %AI.Agent.Skill subclass.
            If '##class(%Dictionary.CompiledClass).%ExistsId(tClassName) {
                Set tSC = $$$ERROR($$$GeneralError, "Skill class not found: " _ tClassName)
                Quit
            }

            Set tSkill = $classmethod(tClassName, "%New")
            If '$isobject(tSkill) {
                Set tSC = $$$ERROR($$$GeneralError, "Failed to instantiate skill: " _ tClassName)
                Quit
            }

            Set tSkill.ParentAgent = pAgent
            Set tSC = pAgent.ToolManager.AddTool(tSkill)
            Quit:$$$ISERR(tSC)
        }
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Convenience: list the default skill class names.
ClassMethod ListDefaultSkills() As %DynamicArray
{
    Set tArr = []
    For i=1:1:$length(..#DEFAULTSKILLS, ",") {
        Do tArr.%Push($zstrip($piece(..#DEFAULTSKILLS, ",", i), "<>W"))
    }
    Quit tArr
}

}
