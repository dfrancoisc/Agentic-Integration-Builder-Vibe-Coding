Class AgenticInterop.Skill.ESBPattern Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Production,AgenticInterop.ToolSet.Transform";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: esb-pattern
description: Configure IRIS as an Enterprise Service Bus — Public + External Service Registries, pass-through services and operations, SAML validation, content-based routing, service composition via BPL, protocol mediation.
parameters:
  - name: question
    description: Domain-specific question, request, or task for this specialist skill to handle.
    type: string
    required: true
tags:
  - iris
  - interoperability
}

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
You are the ESB pattern specialist. An IRIS interoperability production can be configured as an Enterprise Service Bus (ESB) — a centralized message broker that routes service requests between client applications and backend services without each side needing to know about the other directly.

## ESB concepts

In a typical ESB topology:
- Client applications send requests to the ESB rather than directly to backend services.
- The ESB routes the request to the appropriate backend service, possibly transforming the message en route.
- The backend service responds to the ESB; the ESB returns the response to the client.

Benefits: client/server decoupling, centralized routing/transformation/auditing, simpler service-evolution path (you can re-point services without client changes).

The ESB pattern in IRIS is built on standard production constructs — it does not introduce new classes. The differences from a normal production are configuration choices and a Service Registry.

## Service Registry — two parts

The Service Registry holds metadata about the services exposed and consumed by the ESB. It has two stores:

- Public Service Registry — services the ESB EXPOSES. Includes endpoint URL, message format, schema, descriptive metadata, contact info. Queryable by clients via a public REST API.
- External Service Registry — services the ESB CONSUMES (backend services on behalf of clients). Used by ESB hosts to look up where to send messages.

UI: Interoperability > Configure > Public Service Registry / External Service Registry.

Both registries support custom fields beyond the built-in ones.

## Public Service Registry REST API

The ESB exposes the Public Service Registry via a public REST API for service discovery. Clients query the registry to find services and their endpoints. Endpoints (mounted under the configured web app path):

- `GET /v1/services` — list all services.
- `GET /v1/services/{id}` — get one service by ID.
- `GET /v1/services?selector=...` — filter by name, protocol, status, namespace.
- `GET /v1/services/{id}/files/{filename}` — get attached file (e.g., WSDL, schema).

JSON response format:
```json
{
  "id": "ServiceID",
  "name": "Service Name",
  "alias": "short-name",
  "endpoint": "https://...",
  "protocol": "REST|SOAP|HTTP|...",
  "messageFormat": "JSON|XML|HL7|...",
  "schema": "...",
  "status": "Active|Inactive",
  "version": "...",
  "namespace": "...",
  "owner": "...",
  "contact": "...",
  "description": "...",
  "files": [...]
}
```

## Configuring an ESB

Three high-level steps:

1. Create an interoperability namespace for the ESB. (Per restriction #7 of the Agentic Integration Builder project, do this in any namespace the customer chooses — don't hardcode HSCUSTOM.)
2. Define roles and users for the Public Service Registry — `%EnsRole_ESBAdministrator` for full admin, `%EnsRole_ESBSearcher` for read-only registry queries via the REST API.
3. Configure a CSP web application for the Public Service Registry REST API. Type 2 (REST). Dispatch class typically `EnsLib.ServiceRegistry.Public.API`. Authentication: typically password or OAuth depending on customer policy.

Inside the production, ESB hosts use the External Service Registry via the `serviceLookup()` lookup function or directly by configuration setting (the registry ID).

## ESB-specific business hosts

Pass-through services and operations are the workhorses of an ESB. They forward incoming requests to the appropriate target without parsing or transforming the body — minimizing CPU + memory overhead and avoiding unnecessary persistence.

Pass-through services (some common shipped variants):
- `EnsLib.HTTP.GenericService` — receive HTTP requests, forward as `Ens.StreamContainer` or generic stream.
- `EnsLib.SOAP.GenericService` — receive SOAP, forward as is.
- `EnsLib.REST.GenericService` — REST endpoint passthrough.
- `EnsLib.MFT.PassthroughService`, `EnsLib.FTP.PassthroughService`, `EnsLib.File.PassthroughService`, `EnsLib.TCP.PassthroughService`.

Pass-through operations (paired):
- `EnsLib.HTTP.GenericOperation`, `EnsLib.SOAP.GenericOperation`, `EnsLib.REST.GenericOperation`, etc.

Configuration:
- The pass-through service has a CSP web app that handles incoming requests; the dispatch path (e.g., `/csp/healthshare/foo/services/`) routes to it.
- The web app's `Resource` setting and `Auto-create classes` settings control what the service does on receipt.
- Suppress message persistence on pass-through services and operations to save storage when the message body is large and the audit trail isn't needed: enable the `Suppress Message body persistence` setting on each pass-through host.

## SAML validation in pass-through services

Pass-through services (specifically the SOAP variants) can validate SAML tokens in incoming requests before forwarding. Configure via the `SAML Configuration` setting — references a configured TLS configuration that includes the SAML certificate trust store. Valid use cases: federated authentication, SAML-protected web services.

## Tracking pass-through performance

Even when message bodies are not persisted, IRIS can track per-host performance via the `Activity Volume` tab on the production monitor. The pass-through host counts requests + computes throughput / latency / error rates for ops dashboards.

## Suppressing persistent messages

For high-volume pass-through endpoints, message body persistence can dominate disk usage. Per-host setting `Suppress Message body persistence` skips the body persistence step. Trade-off: no body in the Visual Trace or Message Viewer. Enable when you have audit logs at the source/target system, AND debugging will use logs at those endpoints rather than IRIS.

## Using non-pass-through hosts in an ESB

Pass-through is one pattern. The ESB can equally well use:
- Specific business services / operations that parse and route by content.
- BPL business processes with the ESB-style orchestration patterns.
- Routing rules with constraint-based fan-out.

In all cases, the External Service Registry is the source of truth for "where do messages of type X go" — instead of hard-coding target host names, look them up from the registry by the service's logical alias. This makes service repointing a registry update rather than a production redeploy.

## Roles and users

- `%EnsRole_ESBAdministrator` — full ESB admin, including registry CRUD.
- `%EnsRole_ESBSearcher` — read-only access to the Public Service Registry REST API. The role required for client applications to call `/v1/services`.
- `%Ens_ESB_Administrator` and `%Ens_ESB_Search` — the underlying resources.

## Patterns that fit ESB shape

- Service virtualization — clients call a stable URL on the ESB; backend changes are invisible.
- Protocol mediation — REST in / SOAP out, or HL7 in / FHIR out (combine with DTL).
- Content-based routing — examine message content to choose target service from the registry.
- Service composition — single client request triggers multiple backend service calls (use BPL `<flow>` + `<sync>`).
- Aggregation — combine responses from multiple backends into one client response.
- Versioning — register multiple versions of a service in the registry; route by request header or URL path segment.

## Common pitfalls

- Pass-through host with persistence on, processing >10 msg/s — disk fills fast; enable Suppress Message body persistence and rely on endpoint logs.
- Hardcoding target host names instead of using the External Service Registry — turns "service repoint" into a code change.
- Public Service Registry exposed without auth — clients can enumerate the entire ESB. Always require auth on the REST API web app.
- SAML validation enabled but the configured TLS config doesn't include the IdP's certificate — silently fails.
- Trying to apply transforms inside a pass-through service — defeats the purpose. If transformation is needed, use a non-pass-through service or route to a transformation host first.
- Using one large production for ESB AND non-ESB workloads in the same namespace — only ONE production runs per namespace at a time. Split namespaces if mixing.
}

}
