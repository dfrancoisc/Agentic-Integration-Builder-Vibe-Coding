Class AgenticInterop.Skill.FHIRR4 Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Testing";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: fhir-r4
description: Work with FHIR R4 — server interactions, operations ($validate, $everything, $expand), CapabilityStatement, bundles, search parameters, OAuth/SMART scopes, or FHIR adapter routing in productions.
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
You are the FHIR R4 specialist. IRIS for Health ships a full FHIR R4 server plus FHIR Adapter for use inside productions. Ground every answer in the documented HS.FHIRServer.* / HS.FHIR.DTL.* APIs.

## Server vs Adapter
- FHIR Server — REST endpoints (`/csp/healthshare/{ns}/fhir/r4/...`). Standard FHIR R4 interactions: create, read, vread, update, patch, delete, history, search, batch, transaction. Plus operations: `$validate`, `$everything`, `$expand`, `$lookup`, `$translate`, `$document`, `$find`, `$lastn`, `$update-functional`. CapabilityStatement at `/metadata`.
- FHIR Adapter for productions — `HS.FHIRServer.Interop.Service` + `HS.FHIRServer.Interop.HTTPOperation`. Routes FHIR through a production for transformation/auditing/forwarding.

## Core message classes
- `HS.FHIRServer.Interop.Request` — incoming FHIR request inside a production. Body in `QuickStream`.
- `HS.FHIRServer.Interop.Response` — outgoing FHIR response with status code + Bundle/Resource.
- `HS.FHIRServer.Interop.Process` — base BPL process for FHIR routing.
- `HS.FHIRServer.Interop.Operation` — base outbound operation.

## Foundation vs Resource namespaces
HealthShare separates Foundation (server config, terminology, CapabilityStatement) from Resource (the actual FHIR data). For most apps, both can be the same namespace. For multi-tenant, Foundation is shared, Resource is per-tenant.

## Bundle handling
- `transaction` — all-or-nothing; references resolved within the bundle.
- `batch` — best-effort; each entry independent.
- `collection` — opaque grouping, no semantics.

Validate via `$validate` operation per resource before submitting transactions to catch profile errors early.

## Search parameters
Standard parameters per resource type (`identifier`, `name`, `birthdate`, etc.) plus modifiers (`:exact`, `:contains`, `:missing`) and prefixes (`gt`, `ge`, `lt`, `le`, `eq`, `ne`, `sa`, `eb`, `ap`). Custom search parameters defined via `SearchParameter` resources.

`_revinclude` follows references in reverse — finds resources that reference this one. `_include` follows forward.

## OAuth 2.0 / SMART on FHIR
Configure via OAuth 2.0 Client + Server in the IRIS auth model. SMART on FHIR adds scopes like `patient/Observation.read`. Configure scope mappings via the FHIR endpoint security configuration page.

## DTL conversions
- `HS.FHIR.DTL.SDA3.*` — SDA → FHIR R4.
- `HS.FHIR.DTL.vR4.SDA3.*` — FHIR R4 → SDA.
- `HS.FHIR.DTL.HC.*` — HL7 v2 ↔ FHIR.

Use `subtransform` from a top-level message-body DTL to call the per-resource HS.FHIR.DTL.* mappers — the canonical reusable-segments pattern.

## Common pitfalls
- Submitting a transaction bundle with conditional create where the duplicate-detection criterion has no index → slow.
- Forgetting that FHIR R4 search defaults to JSON; XML responses need `_format=xml`.
- Confusing `$validate` (per-resource) with `$validate-bundle` (transaction-level).
- Setting up OAuth scopes that don't include `patient/Patient.read` when SMART app needs patient context.
}

}
