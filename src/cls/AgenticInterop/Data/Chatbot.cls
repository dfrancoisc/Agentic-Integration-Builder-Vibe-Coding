/// A configured chatbot surface — the new AI Hub layer that binds a chatbot
/// (a UI surface such as the Interop Editor panel or the FHIR Server
/// Management launcher) to the %AI.Agent that answers in it.
///
/// The chat REST layer resolves the agent from the chatbot's Key at request
/// time, so changing which agent a chatbot uses is a configuration edit
/// (one row), never a code change or redeploy. Managed in the admin UI
/// "Chatbots" tab and via /api/agentic/chatbots.
///
/// `Key` is an IRIS SQL reserved word, so the property is `ChatbotKey`
/// (SQL column ChatbotKey); the SQL table is AgenticInterop_Data.Chatbot.
Class AgenticInterop.Data.Chatbot Extends %Persistent
{

/// Stable slug used by the chat surface to identify itself (e.g.
/// "interop", "fhir-management"). Lowercase letters, digits, dashes.
Property ChatbotKey As %String(MAXLEN = 100) [ Required ];

/// Operator-facing title shown in the chat panel header.
Property Name As %String(MAXLEN = 200);

/// Fully-qualified %AI.Agent subclass this chatbot runs (e.g.
/// "AgenticInterop.Agent.FHIRSpecialist").
Property AgentClass As %String(MAXLEN = 200) [ Required ];

/// The host page / web application this chatbot attaches to (e.g.
/// "/csp/fhir-management" or "/ui/interop"). Informational.
Property HostApp As %String(MAXLEN = 200);

/// Short tagline shown under the title.
Property Subtitle As %String(MAXLEN = 500);

/// Whether this chatbot is active. Disabled chatbots fall back to the
/// default agent and the launcher can hide itself.
Property Enabled As %Boolean [ InitialExpression = 1 ];

/// Built-in / shipped row that the user should not delete (may still edit).
Property Core As %Boolean [ InitialExpression = 0 ];

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Property UpdatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Index KeyIdx On ChatbotKey [ Unique ];

/// Open a chatbot by its slug. Returns the object or "" if none.
ClassMethod GetByKey(pKey As %String) As AgenticInterop.Data.Chatbot
{
    If $get(pKey) = "" { Quit "" }
    Quit ..KeyIdxOpen(pKey)
}

/// Serialize one row to the JSON shape the admin UI and chat surface use.
ClassMethod ToJSON(pObj As AgenticInterop.Data.Chatbot) As %DynamicObject
{
    Set j = {}
    If '$isobject(pObj) { Quit j }
    Set j.id = pObj.%Id()
    Set j.key = pObj.ChatbotKey
    Set j.name = pObj.Name
    Set j.agentClass = pObj.AgentClass
    Set j.hostApp = pObj.HostApp
    Set j.subtitle = pObj.Subtitle
    Set j.enabled = ''pObj.Enabled
    Set j.core = ''pObj.Core
    Quit j
}

/// Create the two shipped chatbots if they do not already exist.
/// Idempotent: never overwrites a row the user may have edited. Called
/// from the IPM Activate hook.
ClassMethod EnsureSeed() As %Status
{
    Set tSC = $$$OK
    Try {
        Do ..seedOne("interop", "Agentic Integration Builder", "AgenticInterop.Agent.HealthInterop", "/ui/interop", "Interoperability copilot — productions, DTL, routing rules, HL7 and FHIR.")
        Do ..seedOne("fhir-management", "FHIR Assistant", "AgenticInterop.Agent.FHIRSpecialist", "/csp/fhir-management", "FHIR Server, Bulk FHIR, and FHIR SQL Builder specialist.")
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Insert a single seed row if its key is free. Internal.
ClassMethod seedOne(pKey As %String, pName As %String, pAgent As %String, pHost As %String, pSubtitle As %String) [ Internal ]
{
    If $isobject(..GetByKey(pKey)) { Quit }
    Set o = ..%New()
    Set o.ChatbotKey = pKey
    Set o.Name = pName
    Set o.AgentClass = pAgent
    Set o.HostApp = pHost
    Set o.Subtitle = pSubtitle
    Set o.Enabled = 1
    Set o.Core = 1
    Do o.%Save()
}

Storage Default
{
<Data name="ChatbotDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>ChatbotKey</Value></Value>
<Value name="3"><Value>Name</Value></Value>
<Value name="4"><Value>AgentClass</Value></Value>
<Value name="5"><Value>HostApp</Value></Value>
<Value name="6"><Value>Subtitle</Value></Value>
<Value name="7"><Value>Enabled</Value></Value>
<Value name="8"><Value>Core</Value></Value>
<Value name="9"><Value>CreatedAt</Value></Value>
<Value name="10"><Value>UpdatedAt</Value></Value>
</Data>
<DataLocation>^AgenticInterop.Data.ChatbotD</DataLocation>
<DefaultData>ChatbotDefaultData</DefaultData>
<IdLocation>^AgenticInterop.Data.ChatbotD</IdLocation>
<IndexLocation>^AgenticInterop.Data.ChatbotI</IndexLocation>
<StreamLocation>^AgenticInterop.Data.ChatbotS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
