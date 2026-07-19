/// A saved run of the InterSystems Integration Spec Questionnaire.
///
/// Stores BOTH halves of a run: the structured answers the user gave, and
/// the specification text generated from them. Keeping both matters --
/// the prompt alone is not reloadable into the form, and the answers alone
/// do not record what was actually sent to the agent (the user may have
/// edited the text in the preview before sending).
///
/// Not the same thing as AgenticInterop.Data.ChatSpec, which holds the
/// per-conversation specification the agent synthesises from chat
/// attachments. This one is keyed to a questionnaire run, not a chat
/// session, and survives independently of any conversation.
Class AgenticInterop.Data.SpecResponse Extends (%Persistent, %JSON.Adaptor)
{

/// Interface name from the questionnaire, for display in the saved list.
Property InterfaceName As %String(MAXLEN = 200);

/// Short name (3-6 chars) that seeds the generated artifact names.
Property ShortName As %String(MAXLEN = 32);

/// The namespace the specification targets.
Property Namespace As %String(MAXLEN = 64);

/// IRIS user who ran the questionnaire.
Property Username As %String(MAXLEN = 128);

/// Full answer set as JSON: { answers: {...}, repeats: {...} }.
/// A stream because the mapping and destination tables have no fixed size.
Property AnswersJson As %Stream.GlobalCharacter;

/// The generated specification exactly as it stood when saved --
/// including any edits the user made in the preview.
Property PromptText As %Stream.GlobalCharacter;

/// both | prompt | json -- which output format was rendered.
Property OutputFormat As %String(MAXLEN = 16) [ InitialExpression = "both" ];

/// Questionnaire template key and version this run was captured against,
/// so a reload can tell whether the form has changed underneath it.
Property TemplateKey As %String(MAXLEN = 64) [ InitialExpression = "default" ];

Property TemplateVersion As %String(MAXLEN = 16);

/// trial   -- generated via Output Trial, not sent
/// sent    -- handed to the agent via Send it to AIB
Property Status As %String(MAXLEN = 16) [ InitialExpression = "trial" ];

/// How many required answers were complete when saved, e.g. "15/15".
Property Completeness As %String(MAXLEN = 16);

/// Starred by the user so it floats to the top of the worklist.
Property Favorite As %Boolean [ InitialExpression = 0 ];

Property CreatedAt As %TimeStamp [ InitialExpression = {$zdatetime($horolog, 3, 1)} ];

Index ByCreated On CreatedAt;

Index ByFavorite On Favorite;

Index ByUser On Username;

Index ByNamespace On Namespace;

/// Persist one questionnaire run. Returns the new row's id, or "" on failure.
/// pProps is the request body: interfaceName, shortName, namespace,
/// answers (object), prompt (string), outputFormat, status, completeness,
/// templateKey, templateVersion.
ClassMethod Record(pProps As %DynamicObject, pUser As %String = "", Output pSC As %Status) As %String
{
    Set pSC = $$$OK
    Set id = ""
    Try {
        Set o = ..%New()
        Set util = "AgenticInterop.Editor.Util"
        Set o.InterfaceName   = $classmethod(util, "DObj", pProps, "interfaceName")
        Set o.ShortName       = $classmethod(util, "DObj", pProps, "shortName")
        Set o.Namespace       = $classmethod(util, "DObj", pProps, "namespace", $namespace)
        Set o.Username        = $select(pUser'="":pUser, 1:$username)
        Set o.OutputFormat    = $classmethod(util, "DObj", pProps, "outputFormat", "both")
        Set o.Status          = $classmethod(util, "DObj", pProps, "status", "trial")
        Set o.Completeness    = $classmethod(util, "DObj", pProps, "completeness")
        Set o.TemplateKey     = $classmethod(util, "DObj", pProps, "templateKey", "default")
        Set o.TemplateVersion = $classmethod(util, "DObj", pProps, "templateVersion")

        ; answers arrives as an object; store the serialized form
        If pProps.%IsDefined("answers"), $isobject(pProps.answers) {
            Do o.AnswersJson.Write(pProps.answers.%ToJSON())
        }
        Set prompt = $classmethod(util, "DObj", pProps, "prompt")
        If prompt '= "" { Do o.PromptText.Write(prompt) }

        Set pSC = o.%Save()
        If $$$ISERR(pSC) { Quit }
        Set id = o.%Id()
    } Catch ex {
        Set pSC = ex.AsStatus()
    }
    Quit id
}

/// Star or unstar a run. Returns the resulting state, or "" if not found.
ClassMethod SetFavorite(pId As %String, pOn As %Boolean, Output pSC As %Status) As %String
{
    Set pSC = $$$OK
    Set o = ..%OpenId(pId)
    If '$isobject(o) { Quit "" }
    Set o.Favorite = ''pOn
    Set pSC = o.%Save()
    Quit o.Favorite
}

/// Summary row for the list view -- deliberately excludes the two streams
/// so listing a hundred saved runs does not read a hundred blobs.
ClassMethod Summary(pObj As AgenticInterop.Data.SpecResponse) As %DynamicObject
{
    Quit {
        "id":            (pObj.%Id()),
        "interfaceName": (pObj.InterfaceName),
        "shortName":     (pObj.ShortName),
        "namespace":     (pObj.Namespace),
        "username":      (pObj.Username),
        "outputFormat":  (pObj.OutputFormat),
        "status":        (pObj.Status),
        "favorite":      (pObj.Favorite),
        "completeness":  (pObj.Completeness),
        "templateKey":   (pObj.TemplateKey),
        "createdAt":     (pObj.CreatedAt)
    }
}

/// Full row including both streams, for reloading a saved run.
ClassMethod ToJSON(pObj As AgenticInterop.Data.SpecResponse) As %DynamicObject
{
    Set out = ..Summary(pObj)
    Set answers = ""
    Do pObj.AnswersJson.Rewind()
    While 'pObj.AnswersJson.AtEnd { Set answers = answers _ pObj.AnswersJson.Read(8192) }
    Set prompt = ""
    Do pObj.PromptText.Rewind()
    While 'pObj.PromptText.AtEnd { Set prompt = prompt _ pObj.PromptText.Read(8192) }
    ; answers is stored as JSON text; hand it back as an object when it
    ; parses, so the caller does not have to double-decode
    If answers '= "" {
        Try { Set out.answers = ##class(%DynamicAbstractObject).%FromJSON(answers) }
        Catch { Set out.answersRaw = answers }
    }
    Set out.prompt = prompt
    Quit out
}

Storage Default
{
<Data name="SpecResponseDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>InterfaceName</Value>
</Value>
<Value name="3">
<Value>ShortName</Value>
</Value>
<Value name="4">
<Value>Namespace</Value>
</Value>
<Value name="5">
<Value>Username</Value>
</Value>
<Value name="6">
<Value>AnswersJson</Value>
</Value>
<Value name="7">
<Value>PromptText</Value>
</Value>
<Value name="8">
<Value>OutputFormat</Value>
</Value>
<Value name="9">
<Value>TemplateKey</Value>
</Value>
<Value name="10">
<Value>TemplateVersion</Value>
</Value>
<Value name="11">
<Value>Status</Value>
</Value>
<Value name="12">
<Value>Completeness</Value>
</Value>
<Value name="13">
<Value>CreatedAt</Value>
</Value>
<Value name="14">
<Value>Favorite</Value>
</Value>
</Data>
<DataLocation>^AgInt.SpecRespD</DataLocation>
<DefaultData>SpecResponseDefaultData</DefaultData>
<IdLocation>^AgInt.SpecRespD</IdLocation>
<IndexLocation>^AgInt.SpecRespI</IndexLocation>
<StreamLocation>^AgInt.SpecRespS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
