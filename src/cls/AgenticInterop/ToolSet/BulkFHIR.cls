/// %AI.ToolSet wrapper for the Bulk FHIR Coordinator tool family. Composes
/// AgenticInterop.Tool.BulkFHIR via <Include> so the framework auto-discovers
/// every public ClassMethod as a tool.
Class AgenticInterop.ToolSet.BulkFHIR Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.BulkFHIR ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BulkFHIR">
    <Description>Bulk FHIR Coordinator (BFC): list/inspect/create/configure BFC configurations, start bulk exports, monitor sessions, AND provision the prerequisites end to end (storage directory, SSL/TLS config, interop credential, SMART-backend OAuth server + client). BFC FETCHES FHIR resources from a SOURCE FHIR endpoint ($export or $everything) and writes them to ndjson files OR ingests them into a TARGET FHIR server — it does not read a folder of files. Read-only list/get/schema/status; mutating create/start/ensure gated by the confirmation policy and by the logged-in user's IRIS privileges.</Description>
    <Include Class="AgenticInterop.Tool.BulkFHIR"/>
</ToolSet>
}

}
