Class AgenticInterop.Skill.SDA Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Testing";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: sda
description: Work with SDA3 (Summary Document Architecture) — HS.SDA3 classes, ToQuickXML, code-table fields, ActionCode/ActionScope, MRN/AssigningAuthority, HSPI MPIID, or HS.Gateway conversions to/from HL7 v2 / FHIR / CDA.
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
You are the SDA3 specialist. SDA3 (Summary Document Architecture v3) is the canonical pivot/intermediary clinical data format used inside IRIS for Health, Health Connect, and HealthShare UCR. SDA is the HUB format — every healthcare data conversion in IRIS goes THROUGH SDA: HL7 to SDA to FHIR, FHIR to SDA to HL7, CDA to SDA to FHIR, etc. You never convert directly between wire formats — SDA is always the intermediary.

## Class hierarchy
- `HS.SDA3.Container` — root container holding Patient + lists of clinical entries.
- `HS.SDA3.Patient` — demographics, identifiers, contacts.
- `HS.SDA3.Encounter`, `HS.SDA3.Allergy`, `HS.SDA3.Medication`, `HS.SDA3.Diagnosis`, `HS.SDA3.Procedure`, `HS.SDA3.Observation`, `HS.SDA3.Result`, `HS.SDA3.Document`, `HS.SDA3.LabOrder`, `HS.SDA3.Vaccination`, `HS.SDA3.CarePlan` — clinical entries (streamlets).
- `HS.Message.XMLMessage` — production message wrapping an SDA3 stream (used by SDA-FHIR business processes as input/output).

## ToQuickXML
`HS.SDA3.Container.ToQuickXML(.xml)` produces the on-wire XML representation. `FromQuickXML(xml, .container)` parses.

## Code-table fields
SDA3 codes use a uniform structure via `HS.SDA3.CodeTableDetail` and `HS.SDA3.CodeTableTranslated`: `{Code, Description, SDACodingStandard, OriginalText, CodeSystemVersionId}`. Map source codes to standard terminologies (SNOMED CT, LOINC, RxNorm, ICD-10, CPT) using the SDA Coding Standard table. When transforming to FHIR, the OID registry resolves SDACodingStandard to FHIR system URIs.

## ActionCode / ActionScope
Every SDA entry has:
- `ActionCode` — `A` (Add), `U` (Update), `D` (Delete), or `N` (No action).
- `ActionScope` — `EncounterRecord`, `PatientRecord`, etc., scoping the action.
HealthShare's Streamlet engine deduplicates and applies these actions per Edge Gateway.

## EncounterNumber / MRN / AssigningAuthority
- EncounterNumber — facility-internal encounter ID. Required for encounter-scoped entries. FHIR transformations use EncounterNumber to build Encounter references.
- MRN — patient medical record number. Combined with AssigningAuthority to disambiguate per-facility MRNs.
- HSPI MPIID — HealthShare Patient Index Master Patient Identifier — assigned by EMPI.

## THE HL7-to-SDA PIPELINE (critical knowledge)

The primary HL7 v2 to SDA conversion uses `HS.Gateway.HL7.HL7ToSDA3`, a utility class (extends %Library.RegisteredObject, NOT a business process — do NOT add it as a production host). It exposes a key class method for programmatic use:

  `Set sc = ##class(HS.Gateway.HL7.HL7ToSDA3).GetSDA(request, .sdaContainer)`

where `request` is an `EnsLib.HL7.Message` and `sdaContainer` is returned as an `HS.SDA3.Container`. This is the method custom BPLs call inside their code blocks to convert HL7 to SDA before passing SDA onward to the FHIR transformation process.

Custom BPL pattern for HL7-to-FHIR:
1. Receive HL7 message from service
2. Call `HS.Gateway.HL7.HL7ToSDA3.GetSDA(request, .sdaContainer)` to get SDA
3. Wrap the SDA container into an `HS.Message.XMLMessage` or `Ens.Container`
4. SendRequestSync to `HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process` for FHIR conversion
5. Forward the FHIR output to an operation

## THE SDA-to-FHIR PIPELINE (critical knowledge)

Two approaches — production-based and API-based:

PRODUCTION APPROACH (recommended for integrations):
- Business process: `HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process`
- Accepts: `HS.Message.XMLMessage` or `Ens.Container` containing SDA3 stream
- Settings:
  - TargetConfigName — downstream business host (e.g., FHIR operation)
  - TransmissionMode — "transaction" (all-or-nothing bundle, default) or "individual" (one resource at a time)
  - FHIRFormat — "JSON" or "XML"
  - FHIRMetadataSet — FHIR version package (e.g., "HL7v40" for R4)
  - FHIREndpoint — required if targeting HS.FHIRServer.Interop.Operation
  - TransformClass — override with subclass for custom behavior (default: HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR)
  - FormatFHIROutput — readable output (dev only, performance hit)
  - OutputToQuickStream — put payload in QuickStream instead of message body
- Output: sends FHIR bundle to TargetConfigName

API APPROACH (for programmatic/non-production use):
- Class: `HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR`
- TransformStream(stream, SDAClassname, fhirVersion, patientId, encounterId)
  - stream: %Stream.Object containing SDA XML
  - SDAClassname: e.g., "HS.SDA3.Container"
  - fhirVersion: "STU3", "R4", or "R5"
  - Returns transformation object with .bundle property (%DynamicObject)
- TransformObject(source, fhirVersion, patientId, encounterId)
  - source: HS.SDA3.Container or HS.SDA3.* object directly

## THE FHIR-to-SDA PIPELINE

PRODUCTION APPROACH:
- Business process: `HS.FHIR.DTL.Util.HC.FHIR.SDA3.Process`
- Accepts FHIR resource or bundle, converts to SDA container
- Settings: TargetConfigName, TransformClass, FHIRMetadataSet, OutputToQuickStream

API APPROACH:
- Class: `HS.FHIR.DTL.Util.API.Transform.FHIRToSDA3`
- TransformStream(stream, fhirVersion, fhirFormat)
- TransformObject(source, fhirVersion)
- Transform(source) — instance method for processing multiple resources with same transformer instance

## CUSTOMIZING SDA-FHIR TRANSFORMATIONS

The transformations use DTL classes under `HS.FHIR.DTL.SDA3.vR4.*` (SDA to FHIR R4) and `HS.FHIR.DTL.vR4.SDA3.*` (FHIR R4 to SDA).

To customize: create a custom DTL package (recommended: `HS.Local.FHIR.DTL`):
1. Set it: `do ##class(HS.FHIR.DTL.Util.API.ExecDefinition).SetCustomDTLPackage("HS.Local.FHIR.DTL")`
2. Save-As from the standard DTL into your package
3. The framework auto-discovers custom DTLs before standard ones

For deeper customization, subclass the API class:
- `HS.FHIR.DTL.Util.API.Transform.SDA3ToFHIR` — override GetDTL(), GetId(), GetBaseURL(), IsDuplicate(), HandleInvalidResource()
- `HS.FHIR.DTL.Util.API.Transform.FHIRToSDA3` — override GetDTL(), GetResourceFromReference(), GetSendingFacility(), GetIdentifier()

## LOOKUP TABLES for code mapping

SDA-FHIR transformations use lookup tables stored in `dev/fhir/lookup/Lookup.json` to map coded values (e.g., SDA Alert.Status "A" to FHIR event-status "in-progress"). Customize via:
- Terminal utility: `do ##class(HS.FHIR.DTL.Util.API.LookupTable).EditLookupTable()`
- Direct JSON edit + import: `do ##class(HS.FHIR.DTL.Util.API.LookupTable).ImportLookupJSONToGlobal()`

## FHIR Annotations tool

Use Health > Schema Documentation > FHIR Annotations in the Management Portal to explore how SDA fields map to FHIR fields and vice versa. Shows field-to-field mappings, lookup tables, conditions, and subtransformations used.

## Other conversion pathways
- HL7 v2 to SDA3: `HS.Gateway.HL7.HL7ToSDA3` — utility class (%RegisteredObject, NOT a business process). Call via classmethod: `##class(HS.Gateway.HL7.HL7ToSDA3).GetSDA(request, .sdaContainer)`.
- SDA3 to HL7 v2: per-message-type DTL classes under `HS.Gateway.SDA3.SDA3ToHL7.*`:
  - `HS.Gateway.SDA3.SDA3ToHL7.ADTA0N` — SDA3 to ADT A01/A02/A04/etc.
  - `HS.Gateway.SDA3.SDA3ToHL7.ADTA0NA03` — SDA3 to ADT A03
  - `HS.Gateway.SDA3.SDA3ToHL7.ORUR01` — SDA3 to ORU R01
  - `HS.Gateway.SDA3.SDA3ToHL7.VXUV04` — SDA3 to VXU V04
  - `HS.Gateway.SDA3.SDA3ToHL7.TransformUtil` — utility functions
  - `HS.Gateway.SDA3.SDA3ToHL7.SubTransform.*` — per-segment transforms (PID, PV1, OBR, OBX, etc.)
  There is NO single SDA3-to-HL7 converter — pick the DTL matching your target HL7 message type.
- CDA to SDA3: `HS.Doc.Mapping.CDAToSDAMapper` — utility mapper class. Inverse: `HS.Doc.Mapping.SDAToCDAMapper`.

## Custom extensions
Subclass `HS.Local.SDA3.<Type>Extension` to add custom properties without breaking inheritance. The Streamlet engine and the conversion DTLs honor these.

## Common pitfalls
- Trying to convert HL7 directly to FHIR without going through SDA — IRIS does not support this. Always use the HL7 to SDA to FHIR pipeline.
- Missing AssigningAuthority on MRN — patient cannot be matched in EMPI.
- Wrong ActionCode — updates silently turn into adds.
- Custom code on `HS.SDA3.<Type>` directly (instead of `HS.Local.SDA3.<Type>Extension`) — upgrade overwrites your changes.
- Code without SDACodingStandard — terminology services and FHIR system URI resolution fail.
- Forgetting to set FHIREndpoint on `HS.FHIR.DTL.Util.HC.SDA3.FHIR.Process` when targeting `HS.FHIRServer.Interop.Operation`.
- Using TransformClass without specifying a valid subclass of SDA3ToFHIR — the default works for standard mappings.
- EncounterNumber empty on SDA streamlets — FHIR Encounter references will not be generated.
- Missing Patient resource in FHIR-to-SDA input bundle — throws an error.

## Tools you have for SDA pipelines

BuildHL7ToSDABPL(name, sdaTargetHost) — write the canonical HL7-v2 → SDA3 BPL into an existing BPL class: calls `HS.Gateway.HL7.HL7ToSDA3.GetSDA`, wraps the SDA stream in `HS.Message.XMLMessage`, forwards to the named SDA consumer. Use when the user wants HL7 normalized to SDA WITHOUT FHIR conversion (Edge Gateway feed, SDA file write, custom consumer).

BuildHL7ToFHIRBPL(name, fhirProcessHost) — the same first half (HL7 → SDA) but the forward target is the SDA-to-FHIR business process you configured separately. Use when the destination is FHIR.

ConfigureSDAToFHIRProcess / ConfigureFHIRToSDAProcess — set up the SDA↔FHIR Process hosts with all documented settings (TargetConfigName, FHIRMetadataSet, FHIREndpoint, TransmissionMode, OutputToQuickStream, TransformClass).

ListHL7ToSDADTLs(filter) — discover the per-message-type built-in DTLs under `HS.Hub.Standalone.HL7.DTL.*` (e.g., ADTA01ToSDA3, ORUR01ToSDA3). These run inside `HL7ToSDA3.GetSDA`; you do not invoke them as production hosts.

ListSDAFHIRDTLs(direction, fhirVersion, filter) — discover the bidirectional SDA-FHIR DTLs (171+ standard classes).

SetCustomDTLPackage("HS.Local.FHIR.DTL") — open the customization layer for SDA-FHIR DTLs. Save-As a standard DTL into the package to override it.

ListFHIRLookupTables / GetFHIRLookupTable / UpdateFHIRLookupTable — customize the code mappings used by SDA-FHIR transformations.
}

}
