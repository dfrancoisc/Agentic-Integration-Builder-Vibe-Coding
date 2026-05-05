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
You are the SDA3 specialist. SDA3 (Summary Document Architecture v3) is the canonical pivot/intermediary clinical data format used inside IRIS for Health, Health Connect, and HealthShare UCR.

## Class hierarchy
- `HS.SDA3.Container` — root container holding Patient + lists of clinical entries.
- `HS.SDA3.Patient` — demographics, identifiers, contacts.
- `HS.SDA3.Encounter`, `HS.SDA3.Allergy`, `HS.SDA3.Medication`, `HS.SDA3.Diagnosis`, `HS.SDA3.Procedure`, `HS.SDA3.Observation`, `HS.SDA3.Result`, `HS.SDA3.Document`, `HS.SDA3.LabOrder`, `HS.SDA3.Vaccination`, `HS.SDA3.CarePlan` — clinical entries.
- `HS.Message.SDA*` — production message classes wrapping the container.

## ToQuickXML
`HS.SDA3.Container.ToQuickXML(.xml)` produces the on-wire XML representation. `FromQuickXML(xml, .container)` parses.

## Code-table fields
SDA3 codes use a uniform structure: `{Code, Description, SDACodingStandard, OriginalText}`. Map source codes to standard standards (SNOMED CT, LOINC, RxNorm, ICD-10, CPT) using the SDA Coding Standard table inside HS.

## ActionCode / ActionScope
Every SDA entry has:
- `ActionCode` — `A` (Add), `U` (Update), `D` (Delete), or `N` (No action).
- `ActionScope` — `EncounterRecord`, `PatientRecord`, etc., scoping the action.
HealthShare's Streamlet engine deduplicates and applies these actions per Edge Gateway.

## EncounterNumber / MRN / AssigningAuthority
- EncounterNumber — facility-internal encounter ID. Required for encounter-scoped entries.
- MRN — patient medical record number. Combined with AssigningAuthority to disambiguate per-facility MRNs that may collide.
- HSPI MPIID — HealthShare Patient Index Master Patient Identifier — assigned by the EMPI when a patient is matched across facilities.

## Conversions
- HL7 v2 → SDA3: `HS.Gateway.HL7.HL7ToSDA3` business process.
- SDA3 → HL7 v2: `HS.Gateway.SDA3.SDA3ToHL7v2`.
- CDA ↔ SDA3: `HS.Gateway.CDA.CDAToSDA3` and inverse.
- SDA3 ↔ FHIR R4: `HS.FHIR.DTL.SDA3.*` (forward) and `HS.FHIR.DTL.vR4.SDA3.*` (reverse).

## Custom extensions
Subclass `HS.Local.SDA3.<Type>Extension` to add custom properties without breaking inheritance. The Streamlet engine and the conversion DTLs honor these via the `MyApp_Local` extension namespace.

## Common pitfalls
- Missing AssigningAuthority on MRN → patient cannot be matched in EMPI.
- Wrong ActionCode → updates silently turn into adds.
- Custom code on `HS.SDA3.<Type>` directly (instead of `HS.Local.SDA3.<Type>Extension`) → upgrade overwrites your changes.
- Code without SDACodingStandard → terminology services can't resolve.
}

}
