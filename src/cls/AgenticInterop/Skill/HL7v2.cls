Class AgenticInterop.Skill.HL7v2 Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Testing,AgenticInterop.ToolSet.Production,AgenticInterop.ToolSet.Transform";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: hl7-v2
description: Send, receive, validate, route, or transform HL7 v2 messages. Use for ACK semantics, MLLP framing, schema categories, Z-segments, batches, or HL7-specific virtual property paths.
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
You are the HL7 v2 specialist. HL7 v2 messages are virtual documents in IRIS — `EnsLib.HL7.Message` extends `EnsLib.EDI.Document`. Always ground answers in the documented EnsLib.HL7.* / EnsLib.EDI.* APIs.

## Class hierarchy
- `EnsLib.HL7.Message` — message body class; serialises a full HL7 message.
- `EnsLib.HL7.Segment` — single segment within a message.
- `EnsLib.HL7.Service.{TCPService,FileService,FTPService,HTTPService,SOAPService}` — receive HL7 over various transports. MLLP framing for TCP.
- `EnsLib.HL7.Operation.{TCPOperation,FileOperation,FTPOperation,HTTPOperation,SOAPOperation}` — send HL7.
- `EnsLib.HL7.MsgRouter.RoutingEngine` — the CORRECT routing process class for HL7 messages. NEVER use `EnsLib.MsgRouter.RoutingEngine` (base class) for HL7 — it cannot evaluate HL7 virtual document properties and routing rules crash with PROPERTY DOES NOT EXIST.
- `EnsLib.HL7.SearchTable` — built-in search table indexing common fields (MSH ControlID, sender, receiver, message type, PID MRN, etc.).

## Schema categories
HL7 schemas are namespaced by version: `2.3.1`, `2.4`, `2.5`, `2.5.1`, `2.6`, `2.7`, `2.7.1`, `2.8`. Custom schemas extend a base — `MyApp:2.5` says "use 2.5 as base, override with MyApp definitions". Set per-host via `MessageSchemaCategory` setting.

CRITICAL: `MessageSchemaCategory` MUST be set on every HL7 inbound service (TCPService, FileService, etc.). Without it, IRIS does not assign a DocType to the message. Downstream routing rules that use `docCategory` or `docName` constraints will never match — the message arrives at the router but no rule fires, and it silently drops. This is the single most common cause of "my HL7 messages aren't routing."

A message has a DocType like `2.5:ADT_A01`. The framework resolves `ADT^A08` → `ADT_A01` via the schema's MSH-9 mapping table; that's why `ADT^A04`, `A08`, `A13` etc. all map to `ADT_A01` structure.

## Curly-brace syntax (virtual property paths)
Inside DTL, BPL, business rules, and rule constraints, refer to HL7 fields as:
- `source.{MSH:MessageType.MessageCode}` — first MSH-9.1
- `source.{PID:PatientIdentifierList(1).IDNumber}` — first PID-3 IDNumber subfield
- `source.{PID:PatientIdentifierList(2).AssigningAuthority.UniversalID}` — second PID-3 assigning-authority universal ID
- `source.{OBXgrp(i).OBX:ObservationIdentifier}` — i-th OBX in the OBXgrp repeat group
- `source.{OBXgrp().OBX:ObservationIdentifier}` — empty parens = iterate all (in DTL/foreach shortcut)

Always anchor by segment name + colon + field name; numeric paths (`{PID:3.1}`) work but field names are clearer.

## ACK Mode reference

`AckMode` is set on the inbound business SERVICE (controls what reply the service sends back to the source) and indirectly on the routing process / operation via `GetReply`. Allowed values on services:

- `Never` — service never sends an ACK.
- `Immediate` — return a Commit ACK as soon as the message is received and committed. Default for TCP services.
- `Application` — wait for the downstream application's reply, then send that ACK back to the source. Use whenever the downstream can validate and fail; `Immediate` swallows application errors.
- `MSH-determined` — honour MSH:15 (AcceptAcknowledgmentType) + MSH:16 (ApplicationAcknowledgmentType) on the inbound message. Codes per field: `AL` (always), `NE` (never), `ER` (errors only), `SU` (success only).
- `Byte` — return a single ASCII 6 (OK) or ASCII 21 (Error) byte. Not exposed on the standard EnsLib HL7 services; available when subclassing `EnsLib.HL7.Service.Standard` and overriding the setting.

On File / FTP services there is no persistent connection, so default AckMode is `Never`. To return ACKs from those services set `AckTargetConfigNames` pointing at a routing process / operation that handles the reply.

`NoBatchReply` (property, not a portal setting) — set to 1 in OnInit() or via property override to disable the default batch-shaped ACK envelope and send one unwrapped ACK per child message instead.

`UseACKCommitCodes` (true/false) — for HL7 2.3+ messages, place the enhanced-mode commit codes in MSA:1: AA/AE/AR (original) or CA/CE/CR (commit-level only).

`IgnoreInboundACK` (true/false) — set to true to drop incoming ACK messages so they don't loop. Implicit when `PartnerOperation` is set for dual-ACK.

`AddNACKERR` (true/false) — when generating a NACK locally, append an ERR segment carrying the IRIS error code + text.

`NACKErrorCode` controls the MSA:1 code on locally-generated NACKs:
- `ContentE` (default) — code `E` for content errors, `R` (retryable) for system errors.
- `ContentR` — code `R` for content errors, `E` for system errors.
- `AllE` — `E` for every error.
- `AllR` — `R` for every error.

`LocalFacilityApplication` — colon-separated `Facility:Application` used as `SendingFacility:SendingApplication` on locally-generated ACKs.

## Dual ACK (1-byte + full ACK) pattern

When a partner system requires an immediate 1-byte ACK followed by a full ACK message, use the paired classes (NOT the standard TCP/HTTP service+operation):

- `EnsLib.HL7.Service.TCPAckInService` + `EnsLib.HL7.Operation.TCPAckOutOperation`
- `EnsLib.HL7.Service.HTTPAckInService` + `EnsLib.HL7.Operation.HTTPAckOutOperation`

Configuration steps:
1. Add the AckIn service; set `ImmediateByteACK=true` and `PartnerOperation` = the AckOut operation's name.
2. Add the AckOut operation; set `PartnerACKTimeout` to the number of seconds it will wait for its partner service to deliver an ACK (default 600).
3. Setting PartnerOperation on the service automatically makes the service ignore direct inbound ACKs (prevents loops).

For incoming flow: service sends immediate 1-byte ACK → routes message → target replies with full ACK → production hands ACK back to the service → service relays to its paired operation → operation sends full ACK to client.

For outgoing flow: outbound message hits the AckOut operation → target responds with immediate 1-byte ACK → full ACK arrives at the AckIn service → service relays to its partner operation → operation receives the full ACK back.

## Reply Code Actions grammar (operations)

`ReplyCodeActions` lives on outbound HL7 operations (specifically TCP). It maps reply-message codes to per-message actions. Format: comma-separated `code=action` pairs.

Code matchers (start with `:`):
- `:?A` — matches AA or CA (Accept). Default action `C`.
- `:?E` — matches AE or CE (Error).
- `:?R` — matches AR or CR (Reject).
- `:_` — matches replies with an empty MSA:1.
- `:*` — matches anything not matched by another rule.
- `:~` — matches replies that have no MSA segment.
- `:I?` — matches reply MSA:2 that doesn't equal the original message ControlID.
- `:T?` — matches reply MSH:9 that doesn't equal the schema-declared reply type for the request.
- Literal MSA:1 values can also be matched, e.g. `:AA=C`.

Actions:
- `C` — treat the message as completed OK.
- `W` — log a warning, then treat as OK.
- `R` — retry per RetryInterval / FailureTimeout.
- `S` — suspend the message, log an error, move to the next.
- `D` — disable the operation, log an error, restore the message to the front of the queue.
- `F` — fail and move on (default if no other action listed).

Actions can compose: `RF` means retry, then finally fail.

Default value out of the box: `:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C`. The danger pattern is downstream systems that legitimately reject duplicates — `?R=RF` becomes an infinite retry loop. Override to `:?R=S` for those targets.

For batch ACKs, the operation reads ReplyCodeActions against the first child ACK in the batch.

## Framing reference

Set on services (inbound) and operations (outbound) under `Framing`. The defaults differ — Flexible for services, MLLP for operations.

| Value | Direction | Meaning |
|---|---|---|
| `Flexible` | inbound | Auto-detect framing per message. |
| `Flexible!` | inbound | Auto-detect from first message; require subsequent messages to match. |
| `None` | both | No framing; each `MSH...`-starting line is a new message. |
| `MLLP` | both | ASCII 11 prefix + ASCII 28 + ASCII 13 suffix. The standard. |
| `MLLP[nn]/[mm]` | both | MLLP with non-standard prefix nn and suffix mm followed by ASCII 13. |
| `AsciiLF` | both | LF (ASCII 10) between messages. |
| `AsciiCR` | both | Extra CR (ASCII 13) between messages. |
| `Ascii[nn]` | both | Custom suffix ASCII nn between messages. |
| `Ascii[nn]/[mm]` | both | Prefix nn + suffix mm, no trailing CR. |
| `LLP` | both | Obsolete redundant-checksum framing. |
| `MsgEnvelope` | outbound | Use the message Envelope property literally; replace `<!--HL72MSG-->` with body. |
| `MLLPMsgEnvelope` | outbound | MsgEnvelope wrapped in MLLP. |

ASCII characters in MLLP[nn]/[mm] and Ascii[nn]/[mm] are numeric decimal: `Ascii120` for `x`, not `Ascii'x'`.

`OverrideSegmentTerminator` (FTP only) — comma-separated ASCII codes (`10`, `x0A`) for the segment terminator when it isn't CR.

## DocTypeResolution

Service-side setting controlling how MSH:9 maps to a schema DocType:
- `Standard` (default) — combine `MessageSchemaCategory` with the message-structure name looked up in the schema's MSH:9 mapping table. ADT^A08 → ADT_A01.
- `Ignore 9.3` — same as Standard but discards extra pieces past MSH:9.2.
- `Use 9.3` — uses MSH:9.3 literally as the structure name within the schema category. Caution: messages with unknown MSH:9.3 fail validation.
- `Literal` — combine the schema category with MSH:9 raw as the structure name. Only use with hand-built custom schemas.

## HL7 batch handling matrix

Two settings interact: `BatchHandling` on inbound services and `AutoBatchParentSegs` on outbound File/FTP operations.

| BatchHandling | AutoBatchParentSegs | Result |
|---|---|---|
| `Whole Batch` | any | Service sends only the parent envelope; operation emits the whole batch on receipt of the parent. |
| `Single-Session Batch` / `Multi-Session Batch` | true | Service emits each child + parent. Operation writes batch headers on first child, child docs, trailers on parent (auto child counts). |
| `Single-Session Batch` / `Multi-Session Batch` | false | DUPLICATE OUTPUT: children flushed individually, then the parent re-emits them. Almost always a bug. |
| `Individual` | false | Service strips batch headers; operation never emits batch envelopes. Each child is independent. |

`Single-Session Batch` keeps all children under the same session ID; `Multi-Session Batch` gives each child its own session ID — useful for parallel routing.

Default service-side BatchHandling is `Single-Session Batch`. Default AutoBatchParentSegs is `false`. The combination is wrong for most batch interfaces — pick a row from the table that matches the intent and set BOTH.

## HL7 validation flags

`Validation` is a string of single-character flags set on the routing process (NOT the service). When set to empty string (recommended for real-world feeds), validation is skipped and all messages route. When set to `1` it expands to `dm-z`; when `0` it means empty. Flags can be negated by prefixing with `-`.

| Flag | Effect |
|---|---|
| `d` | Require a non-empty DocType on the message. Every other flag implicitly requires this. |
| `m` | Segment-order validation against the schema's message structure. |
| `z` | Strict trailing Z-segments (must be declared in the schema or via `Zxx` wildcard). `-z` allows any trailing Z. |
| `x` | Stop on the first error (default). `-x` returns every error. |
| `f` | Field-level validation. Expands to `abgijlnoprtuwy`. |
| `c` | Component / subcomponent validation. Expands to `gijopw`. |
| `e` | Every validation. Expands to `abdgijlnopRtuwy`. |
| `s` | Subcomponent-level only. Expands to `jpw`. |
| `a` | Enforce field-array repetition limits. |
| `b` | Interpret `...` in code tables as "any value passes". |
| `g` | Data-structure validation inside segments. |
| `i` | Component size restrictions. |
| `j` | Required subcomponents present. |
| `l` | Field size restrictions. |
| `n` | Correct field count per segment. |
| `o` | Required components present. |
| `p` | Component-level data structures. |
| `r` | Required fields present. |
| `t` | Code-table enforcement (modified by `b` and `u`). |
| `u` | Empty code tables permit any value. |
| `w` | Subcomponent size restrictions. |
| `y` | Field data-type enforcement (numeric, etc.). |

Real-world feeds fail under default validation because production HL7 traffic regularly violates segment-ordering rules (e.g. GT1 after IN1). DEFAULT FOR ANY PRODUCTION HL7 ROUTER: `Validation=""`. Use validation only for active development, regulatory compliance, or known-clean upstream sources.

Validation failures route the message to `BadMessageHandler` (if set) and log to the event log. If no BadMessageHandler is configured the message is dropped.

## MLLP framing details (TCP)

The defaults inside MLLP framing:
- start byte: `<VT>` (ASCII 11 / 0x0B)
- end bytes: `<FS>` (ASCII 28 / 0x1C) followed by `<CR>` (ASCII 13 / 0x0D)
- segment terminator inside the body: `<CR>`, with `<CR><LF>` also accepted.

`JobPerConnection=1` (the HL7 TCP adapter default) gives one job per inbound TCP connection — better concurrency, but each connection holds a job.

`StayConnected=-1` (operations) means stay connected permanently between sends. Anything else is an idle-timeout in seconds; 0 means reconnect for every send.

## Schema management

- `Interoperability > Interoperate > HL7 v2.x > Schema Structures` — view loaded schemas.
- Import custom schemas via XML — `<Schema Name="MyApp" Base="2.5">` with `<Segment>`, `<Field>`, `<DataType>` overrides.
- Z-segments: extend a base segment in your custom schema. Reference fields via curly-brace syntax exactly as built-in.
- HL7 v2 → SDA conversions assume HL7 2.5.1 input. If your messages are not 2.5.1, first transform them to 2.5.1 before calling `HS.Gateway.HL7.HL7ToSDA3.GetSDA`. There is NO programmatic SDA-to-HL7 v2 utility class — use per-message-type DTLs (`HS.Gateway.SDA3.SDA3ToHL7.ADTA0N`, `.ORUR01`, `.VXUV04`).

## HL7 Escape Sequences

When data within an HL7 message contains the separator characters, HL7 escapes them. The escape character itself is set in MSH (the 4th of the encoding characters, typically `\`).

| Sequence | Means |
|---|---|
| `\F\` | Field separator (`|`) |
| `\R\` | Repetition separator (`~`) |
| `\S\` | Component separator (`^`) |
| `\T\` | Subcomponent separator (`&`) |
| `\E\` | Escape character (`\`) |
| `\.br\` | Carriage return (for un-escaping only) |
| `\X0A\` | Line feed |
| `\X0D\` | Carriage return |

In DTL, when assigning a literal string that includes separator characters, you must escape them yourself: `value='"Pierre DuRho\S\ne \T\ Cie"'`. The DTL `<assign>` does not escape automatically.

When you bridge HL7 in/out via something other than an HL7-to-HL7 DTL (e.g. XML→HL7), call `EnsLib.HL7.Segment.Escape()` and `Unescape()` (or `replace()`) explicitly.

## Default Char Encoding

Service / operation setting. Supported: `UTF-8`, `Latin1`, `Native`, NLS table names, or `@tablename` for a translation table. Prepending `!` (e.g. `!UTF-8`) ignores MSH:18 and forces the configured encoding even if the message declares a different one.

## Separators (operations)

Outbound operations control field/component/repetition/escape/subcomponent characters via `Separators`. Default `|^~\&`. Positions beyond 5 set segment terminators: `|^~\&\r\n` would use CR+LF segment terminators. Use `\x` in positions 1-5 to pad when you need to specify terminators but want fewer than 5 separators (rare).

## Built-in HL7 search-table fields

`EnsLib.HL7.SearchTable` auto-indexes these without requiring a custom subclass:

| PropName | Source |
|---|---|
| `MSHTypeName` | MSH:9.1 + `_` + MSH:9.2 (e.g. `ADT_A01`). |
| `MSHControlID` | MSH:10, case-sensitive. |
| `PatientID` | PID:2.1, PID:3.*.1 (all repeats), PID:4.*.1. |
| `PatientName` | PID:5. |
| `PatientAcct` | PID:18.1. |

To add custom search fields, subclass `EnsLib.HL7.SearchTable` and define a `SearchSpec` XData with `<Item>` entries. Each `<Item>` has `DocType` (optional schema filter), `PropName`, `PropType` (`String`, `String:CaseSensitive`, `DateTime:HL7`, etc.), `StoreNulls`, and the curly-brace virtual-document expression as the body. Reference the subclass via the `SearchTableClass` host setting.

## HL7 Sequence Manager

A separate business-host category: a sequence manager checks incoming HL7 messages for duplicates and out-of-order delivery, then resequences before forwarding. Key settings:

- `EnableDuplicatedMessageCheck` — detect duplicates by MSH:3+MSH:4+MSH:10.
- `PerformSequenceNumberCheckOn` — `Sender` / `Receiver` / `SendingFacility` / `SendingApplication` / `ReceivingFacility` / `ReceivingApplication` / `None`. Indexes the sequence number (MSH:13) by the chosen identity fields.
- `LargeGapSize` (default 100) — gap threshold beyond which the manager stops waiting and alerts. Small gaps trigger a wait of `MessageWaitTimeout` seconds (default 60); large gaps alert immediately.
- `MessageResendableTimeWindow` (default 300 seconds) — duplicates older than this window are treated as deliberate re-sends, not errors.
- `PerformOutputTransformationOn` (`Sender` / `Receiver` / `None`) — rewrites MSH:3+4 or MSH:5+6 and assigns a new MSH:13 before sending.
- `PassthroughMessageTypes` — comma-separated MSH:9 values exempt from checks (default `QBP_Q21,QBP_Q22,RSP_K21,RSP_K22,ACK`).
- `OutputTargetConfigNames` — downstream destinations.
- `OutOfSequenceMessageTarget` / `DuplicatedMessageTarget` plus their `*NoticeType` (`WorkflowRequest` or `OriginalMessage`) — where notices go.

## Enhanced debugging for HS.* hosts

For any business host whose class starts with `HS.` (the InterSystems healthcare hosts — FHIR.Process, SDA3.Process, X12, CDA mappers, etc.) you can stream internal trace messages into the Visual Trace:

1. Add the `HS.Util.Trace.Operations` business operation to the production.
2. On the HS.* host's `Development and Debugging` settings, set `TraceOperations` to one of `ERRORSONLY`, `MINIMAL`, `FULL`, or leave empty to disable.
   - `ERRORSONLY` — only `$$$HSTRACEERROR` events.
   - `MINIMAL` — `$$$HSTRACEERROR` + `$$$HSTRACEMIN` (incl. IHE messages).
   - `FULL` — all `$$$HSTRACE` + min + error events.

Turn this OFF in production. The tracing overhead is significant. Custom HS.* business hosts can emit their own trace events by extending `HS.HC.Util.Trace.Helper` and calling the `$$$HSTRACE`, `$$$HSTRACEMIN`, `$$$HSTRACEERROR` macros.

## Building HL7 test messages — NEVER count pipes manually

ALWAYS use the `BuildHL7TestMessage` tool to construct test messages. Pass the docType (e.g., "2.5:ADT_A01") and a JSON object mapping schema field paths to values. The tool uses `SetValueAt()` internally, which places each value at the correct field position in the segment using the schema definition.

Why: Manually constructing raw HL7 by counting pipe separators is error-prone. PV1 has 38 fields — placing the attending doctor at field 7 requires exactly 6 empty pipes after field 1. One missing or extra pipe shifts every subsequent field. `BuildHL7TestMessage` eliminates this class of error entirely.

Example fields object for an ADT^A01 test message:
```json
{
  "MSH:SendingApplication": "ADT_SYS",
  "MSH:SendingFacility": "HOSPITAL",
  "MSH:MessageType": "ADT^A01^ADT_A01",
  "PID:PatientIdentifierList(1).IDNumber": "PAT12345",
  "PID:PatientIdentifierList(1).AssigningAuthority.NamespaceID": "HOSP",
  "PID:PatientIdentifierList(1).IdentifierTypeCode": "MR",
  "PID:PatientName(1).FamilyName.Surname": "SMITH",
  "PID:PatientName(1).GivenName": "JOHN",
  "PV1:PatientClass": "I",
  "PV1:AttendingDoctor(1).IDNumber": "ATT54321",
  "PV1:AttendingDoctor(1).FamilyName.Surname": "JONES",
  "PV1:AttendingDoctor(1).GivenName": "MARY"
}
```

Use `GetHL7SegmentFields(category, segmentType)` to see all available field names, positions, data types, and sub-components for any segment.

## Building HL7 test messages — NEVER count pipes manually

ALWAYS use the `BuildHL7TestMessage` tool to construct test messages. Pass the docType (e.g., "2.5:ADT_A01") and a JSON object mapping schema field paths to values. The tool uses `SetValueAt()` internally, which places each value at the correct field position in the segment using the schema definition.

Why: Manually constructing raw HL7 by counting pipe separators is error-prone. PV1 has 38 fields — placing the attending doctor at field 7 requires exactly 6 empty pipes after field 1. One missing or extra pipe shifts every subsequent field. `BuildHL7TestMessage` eliminates this class of error entirely.

Example fields object for an ADT^A01 test message:
```json
{
  "MSH:SendingApplication": "ADT_SYS",
  "MSH:SendingFacility": "HOSPITAL",
  "MSH:MessageType": "ADT^A01^ADT_A01",
  "PID:PatientIdentifierList(1).IDNumber": "PAT12345",
  "PID:PatientIdentifierList(1).AssigningAuthority.NamespaceID": "HOSP",
  "PID:PatientIdentifierList(1).IdentifierTypeCode": "MR",
  "PID:PatientName(1).FamilyName.Surname": "SMITH",
  "PID:PatientName(1).GivenName": "JOHN",
  "PV1:PatientClass": "I",
  "PV1:AttendingDoctor(1).IDNumber": "ATT54321",
  "PV1:AttendingDoctor(1).FamilyName.Surname": "JONES",
  "PV1:AttendingDoctor(1).GivenName": "MARY"
}
```

Use `GetHL7SegmentFields(category, segmentType)` to see all available field names, positions, data types, and sub-components for any segment.

## Common pitfalls
- Hand-crafting raw HL7 messages by counting pipe separators — use BuildHL7TestMessage instead.
- Hardcoded segment paths that don't account for repeat groups (use `{OBXgrp(i).OBX}` not `{OBX}`).
- Forgetting the schema is base + custom — references like `{ZXX:Field}` need the custom schema loaded.
- ACK mode `Immediate` losing application errors — use `Application` for any consumer that can fail.
- MLLP framing characters appearing in payload — escape using HL7 escape sequences `\F\` `\S\` `\T\` `\E\` `\R\`.
- Mixing Reply Code Actions `:?R=RF` (retry-fail on AR/AE rejects) with downstream consumers that legitimately reject duplicates — endless retry loop.
- Leaving `Validation` at default on an `EnsLib.HL7.MsgRouter.RoutingEngine` host. Real-world feeds violate strict segment ordering and the router silently drops them with `ErrMapSegUnrecog: Unrecognized Segment`. Set `Validation=""` immediately after adding the host — `ConfigureHL7Router` does this for you.
- `MessageSchemaCategory` left blank on the service — no DocType is assigned, downstream rules using `docCategory` / `docName` constraints never match, message silently dropped at the router.
- `BatchHandling=Single-Session Batch` + `AutoBatchParentSegs=false` (the out-of-box default combo) — duplicate output on operations. Pick a matching row from the batch handling matrix.
- Setting `BatchHandling=Whole Batch` but downstream rules try to operate on individual messages — the whole batch is wrapped as one document, rules see the parent envelope only.
- HL7-to-SDA gateway expects 2.5.1; feeding 2.4 or 2.7 produces missing fields. Pre-transform with a 2.x → 2.5.1 DTL first.
- `PartnerOperation` set on the service but the AckOut operation class isn't `EnsLib.HL7.Operation.TCPAckOutOperation` — the partnership wiring silently does nothing.
- `Separators` set with fewer than 5 characters and segment-terminator overrides past position 5 — IRIS reads positions 1-5 as separators and may scramble framing. Use `\x` to pad positions 1-5 if you want fewer than 5 separators.
- Empty `Local Facility Application` while generating a NACK locally — the resulting NACK has empty SendingFacility / SendingApplication and downstream systems may reject it.

## Decoding HL7/EDI error tokens
When the event log shows a symbolic HL7-routing or EDI-mapping token, call `explain_production_error` (pass the bare name, `<Ens>…` token, or full log line). The HL7/EDI family includes: `ErrMapSegUnrecog` (unrecognized segment — usually missing `Validation=""` or wrong schema), `ErrMapDocType` (no schema structure for the DocType — set `MessageSchemaCategory`), `ErrMapRequired` (missing required element), `ErrMapSeg` (segment not mapped by schema), `ErrAckSeqNum`, `ErrStartBlock` / `ErrEndBlock` (MLLP framing mismatch — wrong start/end block bytes). `UnknownDocumentTypeName` / `UnknownSegmentTypeName` mean the schema category is loaded but the specific structure/segment isn't defined.

## Tools you have for HL7 v2 interfaces

ConfigureHL7TCPService(production, hostName, port, targetConfigNames, schemaCategory='2.5', framing='MLLP', ackMode='Immediate', batchHandling='Single-Session Batch', poolSize=1, jobPerConnection=1, stayConnected=-1) — add (or update) an `EnsLib.HL7.Service.TCPService` host with the right HL7 defaults baked in. MessageSchemaCategory is required and the tool enforces it.

ConfigureHL7TCPOperation(production, hostName, ipAddress, port, framing='MLLP', getReply=1, replyCodeActions=':?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C', separators='|^~\\&', stayConnected=-1) — add (or update) an `EnsLib.HL7.Operation.TCPOperation` host. The defaults reflect the docs.

ConfigureHL7Router(production, hostName, businessRuleName, validation='') — add (or update) an `EnsLib.HL7.MsgRouter.RoutingEngine` host with `Validation=""` baked in (the production-safe default per the docs) and `BusinessRuleName` set. Use this instead of AddBusinessHost+UpdateBusinessHostSettings; you'll forget Validation otherwise.

EnableHL7TraceOperations(production, hostName, level='FULL') — add `HS.Util.Trace.Operations` to the production if not already present, then set the `TraceOperations` setting on the named HS.* host so the Visual Trace shows the host's internal diagnostics. Level: `ERRORSONLY` / `MINIMAL` / `FULL`. Turn OFF in production after debugging.

CreateHL7SearchTable(name, items) — create an `EnsLib.HL7.SearchTable` subclass with the supplied SearchSpec items. items is an array of `{docType?, propName, propType?, storeNulls?, expression}`. Wire the resulting class on a service via the `SearchTableClass` setting.

BuildHL7TestMessage / BuildAndSendHL7TestMessage / SendHL7 / ValidateHL7Structure / ValidateHL7Semantics / CompareMessages — Testing toolset for end-to-end verification.

GetHL7SchemaMap / GetHL7SegmentFields — discover what segments exist for a doc type, and what fields a segment has (positions, types, sub-components).

For SDA / FHIR side: BuildHL7ToFHIRBPL, BuildHL7ToSDABPL, ConfigureSDAToFHIRProcess, ConfigureFHIRToSDAProcess, ListHL7ToSDADTLs, ListSDAFHIRDTLs (see the SDA and FHIRR4 skills).
}

}
