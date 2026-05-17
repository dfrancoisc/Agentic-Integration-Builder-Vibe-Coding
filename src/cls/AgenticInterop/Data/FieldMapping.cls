/// Pre-computed field-level mapping rows joining HL7/FHIR/CDA/X12 fields
/// through SDA3. Built by TransformService.RebuildFieldMappings() and
/// queried by the Transforms tab UI. Persisted so the UI loads instantly
/// from SQL rather than re-parsing code on every page load.
///
/// Rebuild is triggered manually from the admin UI (or scheduled) because
/// the underlying HS.Gateway.HL7.HL7ToSDA3 and HS.FHIR.DTL.* classes
/// change only with IRIS for Health upgrades.
Class AgenticInterop.Data.FieldMapping Extends (%Persistent, %JSON.Adaptor)
{

/// External format: "HL7 v2", "FHIR R4", "FHIR STU3", "CDA", "X12"
Property SourceFormat As %String(MAXLEN = 32) [ Required ];

/// External format: "HL7 v2", "FHIR R4", "FHIR STU3", "CDA", "X12"
Property TargetFormat As %String(MAXLEN = 32) [ Required ];

/// SDA3 container type (Patient, Allergy, Encounter, etc.)
Property SdaType As %String(MAXLEN = 64) [ Required ];

/// Field from source format: "PID-5 PatientName" or "allergyIntoleranceCategory"
Property SourceField As %String(MAXLEN = 256);

/// SDA3 property name (the pivot): "BirthTime", "Allergy", "Name"
Property SdaField As %String(MAXLEN = 128) [ Required ];

/// Field in target format: "birthDate", "Patient.birthDate"
Property TargetField As %String(MAXLEN = 256);

/// Join status: "complete" (both sides present), "in-only", "out-only"
Property Status As %String(MAXLEN = 16) [ Required ];

/// HL7 segment if source is HL7: "PID", "AL1", "PV1"
Property SourceSegment As %String(MAXLEN = 16);

/// Source class: DTL class name or "HS.Gateway.HL7.HL7ToSDA3"
Property SourceClass As %String(MAXLEN = 256);

/// Target class: DTL class name or segment method
Property TargetClass As %String(MAXLEN = 256);

/// Normalized SDA key used for joining (lowercase base property name)
Property SdaNormalized As %String(MAXLEN = 128);

/// When this row was last rebuilt
Property RebuiltAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

/// Primary query index: filter by format pair + SDA type
Index FormatType On (SourceFormat, TargetFormat, SdaType);

/// Secondary index: SDA type alone (for cross-format queries)
Index SdaTypeIdx On SdaType;

/// Normalized SDA key index (for join lookups during rebuild)
Index SdaNorm On (SourceFormat, TargetFormat, SdaNormalized);

/// Purge all rows. Called at the start of a full rebuild.
ClassMethod PurgeAll() As %Status
{
    Set sql = "DELETE FROM AgenticInterop_Data.FieldMapping"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    If rs.%SQLCODE < 0 {
        Quit $$$ERROR($$$GeneralError, "Purge failed: SQLCODE " _ rs.%SQLCODE)
    }
    Quit $$$OK
}

/// Count total rows currently stored.
ClassMethod CountAll() As %Integer
{
    Set sql = "SELECT COUNT(*) AS cnt FROM AgenticInterop_Data.FieldMapping"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    If rs.%Next() { Quit rs.%Get("cnt") }
    Quit 0
}

/// Query rows for a given format pair and optional SDA type.
/// Returns a %DynamicArray of row objects.
ClassMethod Query(pSrcFmt As %String, pTgtFmt As %String, pSdaType As %String = "") As %DynamicArray
{
    Set arr = []
    Set sql = "SELECT SourceField, SdaField, TargetField, Status, SourceSegment, SourceClass, TargetClass, SdaNormalized, SdaType FROM AgenticInterop_Data.FieldMapping WHERE SourceFormat = ? AND TargetFormat = ?"
    If pSdaType '= "" {
        Set sql = sql _ " AND SdaType = ?"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pSrcFmt, pTgtFmt, pSdaType)
    } Else {
        Set sql = sql _ " ORDER BY SdaType, SdaNormalized"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pSrcFmt, pTgtFmt)
    }
    While rs.%Next() {
        Set row = {}
        Set row.sourceField = rs.%Get("SourceField")
        Set row.sdaField = rs.%Get("SdaField")
        Set row.targetField = rs.%Get("TargetField")
        Set row.status = rs.%Get("Status")
        Set row.sourceSegment = rs.%Get("SourceSegment")
        Set row.sourceClass = rs.%Get("SourceClass")
        Set row.targetClass = rs.%Get("TargetClass")
        Set row.sdaNormalized = rs.%Get("SdaNormalized")
        Set row.sdaType = rs.%Get("SdaType")
        Do arr.%Push(row)
    }
    Quit arr
}

/// List distinct SDA types available for a format pair.
ClassMethod ListSdaTypes(pSrcFmt As %String, pTgtFmt As %String) As %DynamicArray
{
    Set arr = []
    Set sql = "SELECT DISTINCT SdaType FROM AgenticInterop_Data.FieldMapping WHERE SourceFormat = ? AND TargetFormat = ? ORDER BY SdaType"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pSrcFmt, pTgtFmt)
    While rs.%Next() {
        Do arr.%Push(rs.%Get("SdaType"))
    }
    Quit arr
}

Storage Default
{
<Data name="FieldMappingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SourceFormat</Value>
</Value>
<Value name="3">
<Value>TargetFormat</Value>
</Value>
<Value name="4">
<Value>SdaType</Value>
</Value>
<Value name="5">
<Value>SourceField</Value>
</Value>
<Value name="6">
<Value>SdaField</Value>
</Value>
<Value name="7">
<Value>TargetField</Value>
</Value>
<Value name="8">
<Value>Status</Value>
</Value>
<Value name="9">
<Value>SourceSegment</Value>
</Value>
<Value name="10">
<Value>SourceClass</Value>
</Value>
<Value name="11">
<Value>TargetClass</Value>
</Value>
<Value name="12">
<Value>SdaNormalized</Value>
</Value>
<Value name="13">
<Value>RebuiltAt</Value>
</Value>
</Data>
<DataLocation>^AgenticInterop.Data.FieldMappD</DataLocation>
<DefaultData>FieldMappingDefaultData</DefaultData>
<IdLocation>^AgenticInterop.Data.FieldMappD</IdLocation>
<IndexLocation>^AgenticInterop.Data.FieldMappI</IndexLocation>
<StreamLocation>^AgenticInterop.Data.FieldMappS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
