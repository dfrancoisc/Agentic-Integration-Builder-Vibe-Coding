/// %AI.ToolSet wrapper for the Testing tool family. Composes the
/// AgenticInterop.Tool.Testing %AI.Tool subclass via <Include> so the
/// framework's auto-discovery picks up every public ClassMethod as a
/// tool. Send* tools route through the confirmation gate.
Class AgenticInterop.ToolSet.Testing Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.Testing ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Testing">
    <Description>Validate HL7 v2 / FHIR R4 messages, send into a Business Service, POST to a FHIR endpoint, and diff message pairs. Read-only validators fire freely; Send* tools route through the confirmation gate.</Description>
    <Include Class="AgenticInterop.Tool.Testing"/>
</ToolSet>
}

}
