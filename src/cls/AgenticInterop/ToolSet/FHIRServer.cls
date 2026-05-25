/// %AI.ToolSet wrapper for the FHIR Server tool family. Composes the
/// AgenticInterop.Tool.FHIRServer %AI.Tool subclass via <Include> so the
/// framework auto-discovers every public ClassMethod as a tool.
///
/// Covers the full lifecycle of the IRIS for Health FHIR R4 server:
/// discover FHIR-enabled foundation namespaces, list/describe endpoints,
/// read the CapabilityStatement, search/read/create/update/delete and
/// $validate resources, manage metadata packages and runtime config,
/// enable/disable endpoints, and (guarded) provision or remove endpoints.
/// Mutating tools (Create/Update/Delete/Add/Set*) flow through the
/// confirmation gate.
Class AgenticInterop.ToolSet.FHIRServer Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.FHIRServer ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="FHIRServer">
    <Description>Build and manage the IRIS for Health FHIR R4 server. Discover FHIR-enabled foundation namespaces and existing endpoints; inspect endpoint config and CapabilityStatement; search/read/create/update/delete and $validate FHIR resources against the repository; manage metadata packages (US Core etc.) and runtime config; enable/disable endpoints; and provision/remove endpoints (provisioning refuses to touch an endpoint that already exists). Read-only discovery/inspection/search; mutating data-write, config, package, and provisioning operations gated by the confirmation policy.</Description>
    <Include Class="AgenticInterop.Tool.FHIRServer"/>
</ToolSet>
}

}
