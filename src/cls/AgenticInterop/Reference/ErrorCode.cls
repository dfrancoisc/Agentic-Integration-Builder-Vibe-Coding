/// Error code loaded from InterSystems_Error_Reference.pdf.
/// Owned by AgenticInterop.Reference.Loader; rebuilt from the JSON
/// seed file when ReloadAll() runs. Looked up by lookup_error_code.
Class AgenticInterop.Reference.ErrorCode Extends (%Persistent, %JSON.Adaptor)
{

/// Numeric error code (e.g., 5001). Unique within the table.
Property Code As %Integer;

/// Message template — what $system.Status.GetErrorText would render
/// (verbatim from the reference PDF). May contain %1, %2 placeholders.
Property Message As %String(MAXLEN = 2000);

/// Section heading from the source document (e.g. "General Error
/// Codes", "TSQL Error Codes", "FTP Error Codes").
Property Category As %String(MAXLEN = 200);

Index CodeIdx On Code [ Unique ];

Storage Default
{
<Data name="ErrorCodeDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>Code</Value></Value>
<Value name="3"><Value>Message</Value></Value>
<Value name="4"><Value>Category</Value></Value>
</Data>
<DataLocation>^AgInt.RefErrD</DataLocation>
<DefaultData>ErrorCodeDefaultData</DefaultData>
<IdLocation>^AgInt.RefErrD</IdLocation>
<IndexLocation>^AgInt.RefErrI</IndexLocation>
<StreamLocation>^AgInt.RefErrS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
