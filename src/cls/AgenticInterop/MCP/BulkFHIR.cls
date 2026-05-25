/// MCP: Bulk FHIR Coordinator. Tools to create, configure, start, edit, and
/// monitor Bulk FHIR (BFC) exports — fetch FHIR resources from a source FHIR
/// endpoint and write them to ndjson files or ingest them into a target FHIR
/// server. Backed by HS.BulkFHIR.Installer / Configuration / ExportManager.
///
/// BFC is a separate component from the FHIR repository: $export lives here,
/// not in the FHIR Server. To load a directory of FHIR files INTO a server,
/// use the FHIR Server MCP's LoadFHIRData tool (DataLoader), not BFC.
Class AgenticInterop.MCP.BulkFHIR Extends AgenticInterop.MCP.Base
{

Parameter NAME = "bulkfhir";

Parameter DESCRIPTION = "Bulk FHIR Coordinator (BFC): create/configure/edit/start/monitor bulk FHIR exports. Fetches from a source FHIR endpoint and writes to ndjson or ingests into a target FHIR server. Needs the %HS_BFC_Administrator role.";

Parameter TOOLSETS = "AgenticInterop.ToolSet.BulkFHIR";

}
