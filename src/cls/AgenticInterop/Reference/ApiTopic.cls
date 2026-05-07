/// API topic loaded from Detailed_API_Index.pdf — one record per
/// "<Topic> (Tools/APIs)" entry in the source. Looked up by
/// search_api_index. Body is whitespace-normalized + length-capped
/// at parse time so a single full-text scan stays fast.
Class AgenticInterop.Reference.ApiTopic Extends (%Persistent, %JSON.Adaptor)
{

/// URL-safe identifier derived from the title.
Property Slug As %String(MAXLEN = 200);

/// Topic title (e.g., "Productions (Tools/APIs)" → "Productions").
Property Title As %String(MAXLEN = 200);

/// One-line summary the source prints below the title.
Property Summary As %String(MAXLEN = 600);

/// Full body text, whitespace-normalized.
Property Body As %String(MAXLEN = 8000);

/// Availability statement from the source ("All namespaces", "%SYS
/// namespace", "All interoperability-enabled namespaces", etc.).
Property Namespaces As %String(MAXLEN = 400);

Index SlugIdx On Slug [ Unique ];

Index TitleIdx On Title;

Storage Default
{
<Data name="ApiTopicDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>Slug</Value></Value>
<Value name="3"><Value>Title</Value></Value>
<Value name="4"><Value>Summary</Value></Value>
<Value name="5"><Value>Body</Value></Value>
<Value name="6"><Value>Namespaces</Value></Value>
</Data>
<DataLocation>^AgInt.RefApiD</DataLocation>
<DefaultData>ApiTopicDefaultData</DefaultData>
<IdLocation>^AgInt.RefApiD</IdLocation>
<IndexLocation>^AgInt.RefApiI</IndexLocation>
<StreamLocation>^AgInt.RefApiS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
