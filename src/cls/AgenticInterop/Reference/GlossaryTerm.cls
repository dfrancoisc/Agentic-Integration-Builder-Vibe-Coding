/// Glossary term loaded from InterSystems_Glossary_of_Terms.pdf.
/// Owned by AgenticInterop.Reference.Loader; rebuilt from the JSON
/// seed file when ReloadAll() runs. Looked up by lookup_glossary_term.
Class AgenticInterop.Reference.GlossaryTerm Extends (%Persistent, %JSON.Adaptor)
{

/// Term as it appears in the source document (preserves case +
/// spacing, e.g. "ad hoc query", "$ZF function", "MAC routine").
Property Term As %String(MAXLEN = 200);

/// Normalized lookup key — lowercase, alphanumerics + $ only, first
/// token only ("ADT^A01" → "adt"). Built by the loader from `Term`.
Property TermKey As %String(MAXLEN = 200);

/// Category from the source document (e.g. "System", "ObjectScript",
/// "InterSystems SQL", "Objects", "Java").
Property Category As %String(MAXLEN = 80);

/// Definition text. Whitespace-normalized.
Property Definition As %String(MAXLEN = 4000);

Index TermKeyIdx On TermKey [ Unique ];

Index TermIdx On Term;

Storage Default
{
<Data name="GlossaryTermDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>Term</Value></Value>
<Value name="3"><Value>TermKey</Value></Value>
<Value name="4"><Value>Category</Value></Value>
<Value name="5"><Value>Definition</Value></Value>
</Data>
<DataLocation>^AgInt.RefGlossD</DataLocation>
<DefaultData>GlossaryTermDefaultData</DefaultData>
<IdLocation>^AgInt.RefGlossD</IdLocation>
<IndexLocation>^AgInt.RefGlossI</IndexLocation>
<StreamLocation>^AgInt.RefGlossS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
