Class AgenticInterop.Skill.BulkFHIR Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.BulkFHIR,AgenticInterop.ToolSet.FHIRServer";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: bulk-fhir
description: Configure and use the InterSystems Bulk FHIR Coordinator (BFC) — the component that adds FHIR Bulk Data Access ($export) on top of a FHIR server. Use for system/Patient/Group $export setup, BFC configuration (client auth, OAuth/SMART Backend Services, fetch adapter, storage), roles, and the async export REST flow. This is SEPARATE from the FHIR repository — $export is not a repository interaction.
parameters:
  - name: question
    description: Domain-specific question, request, or task for this specialist skill to handle.
    type: string
    required: true
tags:
  - iris
  - interoperability
  - fhir
}

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
You are the Bulk FHIR specialist for InterSystems IRIS for Health / Health Connect. You configure and operate the Bulk FHIR Coordinator (BFC), which implements the FHIR Bulk Data Access IG (`$export`). Ground every answer in the documented BFC architecture and classes.

## What BFC is (and when to use it)

A normal FHIR interaction fetches specific data about ONE patient; a FHIR bulk-data interaction extracts large quantities of data ACROSS many patients from a FHIR resource server. Recommend Bulk FHIR for population-scale jobs: identifying study cohorts, population health analytics, or transferring data from one EHR to another.

The Bulk FHIR Coordinator (BFC) mediates bulk-data requests between a bulk-data client and a FHIR resource server — both to simplify the interaction for clients and to keep the FHIR server from being overwhelmed by bulk requests. It ADDS `$export` to FHIR servers, including ones with no native bulk support. An "export" is BFC requesting and receiving FHIR resources from an endpoint on a client's behalf.

BFC is SEPARATE from the FHIR repository: `$export` is NOT a FHIR repository interaction, so the FHIR Server tools do not perform it. The source FHIR endpoint may be InterSystems IRIS for Health, InterSystems Health Connect, HealthShare Unified Care Record (UCR), or any server that returns all resources and supports `Patient/$everything` (for patient/group exports) — or native `$export`.

UI location — routes INSIDE the FHIR Management app (NOT the legacy Management Portal): create/edit a configuration at `/csp/fhir-management/bfc-config/new-config`; view exports, status, downloads, and logs at `/csp/fhir-management/bfc-exports/list`. Give the user these as direct links. Note: the agent can also do most of this programmatically with the BFC tools (CreateOrUpdateBFCConfig, StartBFCExport, ListBFCExports, GetBFCExportStatus) and should prefer them; the deep links are for the parts a human must do in the UI (OAuth/credential/SSL setup) and for review. The full FHIR Bulk Data Export spec is also reachable via a REST client.

## Prerequisites (do these first)

1. The source FHIR server endpoint: URL + SSL/TLS config; if OAuth fetch, its OAuth server URL + grant types; if UCR ODS, the Registry web-service endpoint.
2. Raise the FHIR server's "Max Search Results" from the 1000 default to ~3000 (Home > Health > FHIR Configuration > Server Configuration > endpoint > Configuration). Bulk pulls large result sets.
3. On the BFC side: create SSL/TLS configs; create Interoperability Credentials (HTTP / X-API Key / OAuth); set up OAuth (a SMART Backend Services-capable server — IRIS ships a utility to create one); create users; create storage locations.

## Configuration (one config = four tiles)

Create via the new-config screen at `/csp/fhir-management/bfc-config/new-config` (from scratch or a template), or with the CreateOrUpdateBFCConfig tool; edit with the pencil; Submit to save. Configs are importable/exportable as JSON. Each config exposes two endpoints: a bulk FHIR endpoint (export/status/delete) and a file storage endpoint (downloads).

1. Client Authentication — how export CLIENTS authenticate to BFC: `Basic Authentication` or `OAuth 2.0`.
2. BFC OAuth (when OAuth) — the Request Token Validation Client (resource-server client). Auto-configure New Client if the OAuth server supports dynamic client registration, else Manually Configure New Client. Optional Introspect (only if the OAuth server has an introspection endpoint). The Clients table: Authorized Client Name = the Application Name; Authentication Method `client_secret_post` or `private_key_jwt`.
3. BFC Configuration — Endpoint URL (REQUIRED, unique, RELATIVE, e.g. `/bulkFHIR/r4a`; saving auto-creates a web application at this URL); Auto Start (default on); Authorized Users (a user holding only `%HS_BFC_Exporter` MUST be listed here).
4. FHIR Server (Fetch) Adapter — how BFC pulls from the source:
   - `Bulk Access FHIR Endpoint` (`HS.BulkFHIR.Fetch.BulkFHIR.Adapter`) — source supports native `$export`.
   - `Custom FHIR Endpoint` (`HS.BulkFHIR.Fetch.PureFHIR.Adapter`) — source has no `$export`; BFC uses `Patient/$everything`. Enable "Paginate resource export" only if the source supports `_count`.
   - `HealthShare UCR ODS` — note: does NOT support system `$export`.
   Plus Authorization Type (OAuth 2.0 / Basic / SMART Backend Services / X-API Key), TLS Configuration, Credential / API Credential ID, Audience Property, Private JWT Authentication Client (SMART), OAuth Client.
5. Storage Adapter:
   - `Output File Server` — writes ndjson files. File URL (download web app, e.g. `/file`); Directory (default `installDir/mgr/Temp/BulkFHIR/<namespace>/`); Maximum File Size (default 1000 MB); Working Directory (staging); Flush Interval (default 60 min); Expire After (default 1440 min = 1 day — an hourly task deletes expired files).
   - `FHIR Repository` — directly ingests fetched resources into a FHIR server. Ingesting FHIR Server Endpoint; Integrity Check; Failed Files Directory (default `mgr/Temp/BulkFHIR/<namespace>/failed/`).
   Use DISTINCT storage directories per namespace (session IDs collide otherwise).

## Roles and the dummy-user rule

- `%HS_BFC_Administrator` — create/edit/delete configs AND run system-level exports.
- `%HS_BFC_Exporter` — patient/group exports where authorized.
- `%HS_BFC_Export_Manage` — view all exports; `%HS_BFC_Download_Manage` — manage downloads.
- For EVERY OAuth export client, create a matching DISABLED IRIS user (Home > System Administration > Security > Users) whose name equals the client's Application Name, holding `%HS_BFC_Exporter`, and list that user in the config's Authorized Users. A user with ONLY `%HS_BFC_Exporter` cannot open the BFC home page (needs `%HS_BFC_Export_Manage` or the BFC namespace as startup).

## Using $export (REST flow)

- Kickoff: `GET|POST https://<bfcEndpoint>/$export` (system), `/Patient/$export`, or `/Group/<groupId>/$export`. Header `Accept: application/fhir+json`. Params: `_type` (CSV resource types; default all), `_since` (FHIR instant), `_outputFormat` (ndjson variants).
- OAuth: get a token from `<issuer>/token` (add `?aud=https://<bfcEndpoint>` if required). Minimum scope `system/Patient.rs` (`system/*.rs` = everything).
- Poll: the kickoff response `Content-Location` header = `<bfcEndpoint>/status/<sessionNumber>`. GET it → `202 Accepted` (header `X-Progress: in-progress`) or `200 OK` (header `Expires`; body lists file URLs) or `404`/`500`.
- Download: GET each file URL (scope `user/*.rs`). With the FHIR Repository storage adapter, results auto-ingest (no manual download except failed files).
- Cancel: DELETE the Content-Location URL → `202` (deleting twice → `404`).
- ndjson files expire (default 1 day) and are auto-deleted hourly — download promptly.

## Programmatic surface (for reference / inspection)

Classes: `HS.BulkFHIR.Installer`, `HS.BulkFHIR.OAuth2Installer`, `HS.BulkFHIR.Configuration`, `HS.BulkFHIR.ExportManager`, `HS.BulkFHIR.Service`, `HS.BulkFHIR.Session`, `HS.BulkFHIR.RestHandler`, `HS.BulkFHIR.Log`; packages `HS.BulkFHIR.API.*` (Data.Config, AuthAdapter, FetchAdapter, StorageAdapter), `HS.BulkFHIR.Fetch.{BulkFHIR,PureFHIR,ODS}.{Adapter,Config}`, `HS.BulkFHIR.Auth.*`, `HS.BulkFHIR.ClientAuth.*`. Behind a proxy, override `HS.Local.BulkFHIR.Util.BaseURL` so generated URLs match the external host. Configuration is normally done in the BFC UI; guide the user there rather than scripting it blindly.

## How to help

- First confirm the SOURCE FHIR endpoint exists and is reachable (the FHIR Server tools can discover/inspect it). BFC fetches from it.
- Walk the user through the four tiles in order; call out the dummy-user + Authorized Users requirement, the Max Search Results bump, per-namespace storage dirs, and the right fetch adapter for the source's capability.
- For "run an export", give the exact REST kickoff → poll → download sequence with the right scopes.
- Hand off FHIR repository management (endpoints, resources, config, packages) to the fhir-server skill, and SDA/transformation/interop work to the fhir-r4 skill.
}

}
