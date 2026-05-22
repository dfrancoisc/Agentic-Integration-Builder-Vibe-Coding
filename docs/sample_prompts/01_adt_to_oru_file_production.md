# Sample Prompt: ADT-to-ORU File-Based Production with Dead-Letter Routing

> **Persona:** Interface Engineer
> **Complexity:** Advanced (5 hosts, 1 DTL, 1 compiled routing rule, 19-point validation)
> **Expected agent calls:** ~25 across Catalog, Production, Transform, Testing, Monitoring MCPs
> **Test data:** Uses ADT^A01 from `/test-messages` skill (Nakamura, MRN-88402)

---

## Prompt

Build me a complete production called `ADT.ToORU.FileProduction` that does the following:

**Inbound**
Pick up HL7 v2.5 ADT^A01 admission messages from the folder `/tmp/hl7-in/`. The Business Service should watch that directory, process each `.hl7` file it finds, and move the original file to an archive subfolder after processing. Use the `2.5` schema category for parsing. Generate an application accept (AA) acknowledgment for every message that parses successfully, and an application reject (AR) for anything that fails schema validation.

Use this message to test:

```
MSH|^~\&|EPIC|MAIN-HOSP|LIS|LAB-SYS|20260522143027||ADT^A01^ADT_A01|MSG-20260522-00471|P|2.5|||AL|NE|USA|ASCII|en^English^ISO639
EVN|A01|20260522142800|20260522143000||ADMIN^Richardson^Nancy^M^^RN|20260522142500
PID|1||MRN-88402^^^MAIN-HOSP^MR~SSN-321654987^^^SSA^SS||Nakamura^Kenji^Takeshi^^^^L~Nakamura^Ken^^^^A||19870314|M|||2200 Coral Way^^Miami^FL^33145^USA^H~PO Box 9012^^Miami^FL^33101^USA^M||^PRN^PH^^1^305^5559012~^PRN^CP^^1^786^5553344|^WPN^PH^^1^305^5558800|en^English^ISO639|M|BUD||SSN-321654987|||N^Non-Hispanic^HL70189||N||||||N
PD1|||MAIN CAMPUS^^12345|ATTEND-4401^Reeves^Samantha^L^Dr.^MD^L
NK1|1|Nakamura^Yuki^M^^^^L|SPO^Spouse^HL70063|2200 Coral Way^^Miami^FL^33145^USA^H|^PRN^PH^^1^305^5559013||EC^Emergency Contact^HL70131
NK1|2|Nakamura^Hiroshi^^^^^L|FTH^Father^HL70063|445 Biscayne Blvd^^Miami^FL^33132^USA^H|^PRN^PH^^1^305^5551234||NK^Next of Kin^HL70131
PV1|1|I|4-EAST^4E-201^A^MAIN-HOSP^^^^4TH FLOOR EAST||||ATTEND-4401^Reeves^Samantha^L^Dr.^MD^L|REFER-7702^Patel^Ravi^K^Dr.^MD^L|CONSULT-3309^Johannsen^Erik^^Dr.^DO^L|MED||||7|ADM-0042^Williams^Tara^R^^NP^L||VN-660234^^^MAIN-HOSP^VN|SELF|||||||||||||||||||ADMIT||ACTIVE|||20260522142800
PV2|||^Chest pain with shortness of breath||||||20260523|1||||||||||||N
AL1|1|DA^Drug Allergy^HL70127|PENICILLIN^Penicillin^NDC|MO^Moderate^HL70128|Hives and rash|20190615
AL1|2|FA^Food Allergy^HL70127|SHELLFISH^Shellfish^LOCAL|SV^Severe^HL70128|Anaphylaxis|20150301
DG1|1|ICD10|R07.9^Chest pain, unspecified^ICD10||20260522142800|A
DG1|2|ICD10|R06.0^Dyspnea^ICD10||20260522142800|A
IN1|1|BCBS-FL-PPO^^BCBS|BCBS-FL-001|Blue Cross Blue Shield of Florida|PO Box 1798^^Jacksonville^FL^32231^USA|^PRN^PH^^1^800^5551234||GRP-MH-40021||||20260101|20261231||COM^Commercial^HL70086|Nakamura^Kenji^T^^^^L|SEL^Self^HL70063|19870314|2200 Coral Way^^Miami^FL^33145^USA^H|||1||||||||||||||ACT-44021
GT1|1||Nakamura^Kenji^Takeshi^^^^L||2200 Coral Way^^Miami^FL^33145^USA^H|^PRN^PH^^1^305^5559012||19870314|M||SEL^Self^HL70063
```

This message has values in every field the transformation touches, plus extra segments (NK1, AL1, DG1, IN1, GT1) that should NOT appear in the output ORU — if any of those leak through, the DTL is copying too much.

**Transformation — ADT^A01 to ORU^R01**
Create a DTL called `ADT.ToORU.Transform` that converts each ADT^A01 into an ORU^R01 observation report. The mapping rules are:

- Copy `MSH` from source to target, but change MSH:9 (MessageType) to `ORU^R01` and set MSH:12 (VersionID) to `2.5`
- Map `PID:3` (PatientIdentifierList) into `OBR:3` (FillerOrderNumber) — take the first repetition's ID value
- Map `PV1:7` (AttendingDoctor) into `OBR:16` (OrderingProvider) — carry all components (ID, family name, given name, suffix, prefix, degree)
- Create one `OBX` segment:
  - `OBX:1` (SetID) = `1`
  - `OBX:2` (ValueType) = `ST` (string)
  - `OBX:3` (ObservationIdentifier) = `PATNAME^Patient Name^L`
  - `OBX:5` (ObservationValue) = the full patient name from `PID:5` (concatenate family name, given name, and middle name separated by spaces)
  - `OBX:11` (ObservationResultStatus) = `F` (final)
- Copy `PID` as-is into the ORU's PID (so the patient demographics travel with the report)
- Set `OBR:4` (UniversalServiceIdentifier) to `ADT-OBS^Admission Observation^L`
- Set `OBR:7` (ObservationDateTime) to the value from `EVN:2` (RecordedDateTime) if it exists, otherwise use the current timestamp

Compile the DTL after creating it.

**Routing**
Add a routing engine Business Process called `ADT.ToORU.Router`. Create a compiled business rule called `ADT.ToORU.RoutingRule` with these conditions:

1. **Rule 1 — "Route ORU to outbound"**: If the message type (`MSH:9.1`) equals `ORU` and the message event (`MSH:9.2`) equals `R01`, send to the outbound file operation (see below). This is the normal path after successful transformation.
2. **Rule 2 — "Dead letter"**: This is the default/otherwise rule — any message that does not match Rule 1 (including messages that failed transformation or arrived with an unexpected type) gets sent to the dead-letter file operation.

The routing engine should apply the transformation `ADT.ToORU.Transform` before evaluating routing rules, so the inbound ADT arrives, gets transformed to ORU, and then the rules decide where the ORU goes.

**Outbound**
Create a file-based Business Operation called `ADT.ToORU.FileOut` that writes each ORU^R01 message to the folder `/tmp/hl7-out/`. Use the filename pattern `ORU_%Y%m%d%H%M%S_%MessageID%.hl7` so each file is unique. Overwrite mode off.

**Dead Letter**
Create a second file-based Business Operation called `ADT.ToORU.DeadLetter` that writes failed or unroutable messages to `/tmp/dead-letter/`. Use the filename pattern `DL_%Y%m%d%H%M%S_%MessageID%.hl7`.

**Final Steps**
After everything is created and compiled:

1. Start the production with all five hosts enabled
2. Send the ADT^A01 test message above through the inbound path to verify end-to-end flow
3. Validate that the ORU^R01 appeared in `/tmp/hl7-out/`, that the OBR:3 filler order number matches the original PID:3, and that the OBX:5 contains the patient name
4. Check the Event Log for any errors or warnings
5. Give me a summary of what was built, what was tested, and whether it all passed
