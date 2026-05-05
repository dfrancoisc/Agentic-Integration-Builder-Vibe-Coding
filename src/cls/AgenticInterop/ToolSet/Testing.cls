/// Stub. The full Testing toolset (send_hl7, send_fhir, send_sda, send_dicom,
/// send_mft_file, validate_hl7_structure, validate_hl7_semantics,
/// validate_fhir_resource, compare_messages, test_rest_endpoint,
/// get_test_message_samples, get_iris_fhir_capability_statement) lands in
/// Phase 4. See docs/TOOLS.md "ToolSet.Testing".
Class AgenticInterop.ToolSet.Testing Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Testing" Description="Send and validate HL7 v2, FHIR R4, SDA3, DICOM, MFT messages, plus generic REST testing — sandbox-isolated by default (stub — populated in Phase 4).">
</ToolSet>
}

}
