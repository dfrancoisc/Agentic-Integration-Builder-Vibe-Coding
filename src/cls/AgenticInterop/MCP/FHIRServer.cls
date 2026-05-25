/// MCP: FHIR Server. Everything about building and managing the IRIS for
/// Health FHIR R4 server — discovering the foundation namespace where FHIR
/// is already defined, inspecting and configuring endpoints, managing
/// metadata packages, working with resources in the repository
/// (search/read/CRUD/$validate/CapabilityStatement), and guarded
/// provisioning of new endpoints.
///
/// Design rule: a foundation namespace already HAS the FHIR Server. This
/// MCP manages the existing server first; provisioning is explicit and
/// never reinstalls a live endpoint. See AgenticInterop.Tool.FHIRServer.
Class AgenticInterop.MCP.FHIRServer Extends AgenticInterop.MCP.Base
{

Parameter NAME = "fhir";

Parameter DESCRIPTION = "Tools to build and manage the IRIS for Health FHIR R4 server: discover FHIR-enabled foundation namespaces, inspect/configure endpoints, read the CapabilityStatement, search/read/create/update/delete and $validate FHIR resources, manage metadata packages, and (guarded) provision endpoints.";

Parameter TOOLSETS = "AgenticInterop.ToolSet.FHIRServer";

}
