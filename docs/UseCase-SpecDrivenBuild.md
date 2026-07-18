# Use Case: Specification-Driven Build (Builder / Developer Experience)

> Version 1.0 | May 2026 | InterSystems AI Hub
> Platform: InterSystems IRIS for Health 2026.2+, %AI Framework build 162.0
> Related: `docs/AttachmentWorkflow.md` (technical implementation),
> `docs/01_Requirements_User_Stories.md` (Personas, Section 5 Core Use Cases)

---

## 1. Summary

The Builder / Developer (Interface Engineer persona) drops a Statement of Work,
Business Requirements Document, integration brief, or field-mapping spreadsheet
into the chat composer. The agent reads the attachment, synthesizes a
structured Project Specification, presents it to the user for review, and only
on the user's explicit approval enters the existing plan → authorize → act loop
to build the integration. Throughout the flow the user always sees what the
agent understood before any artifact is created.

This use case extends Section 5 of `01_Requirements_User_Stories.md` (Core Use
Cases). It is complementary to "Build Productions" (5.1) and "Create
Transformations" (5.3) — the new flow lets the WORK BEGIN from a document
rather than a typed prompt, removing the "retype the SoW into chat" step.

---

## 2. Persona

| Attribute | Detail |
|---|---|
| Primary actor | End User: Interface Engineer (`01_Requirements_User_Stories.md` §2.3) |
| Secondary actor | End User: Operator (review-only; can request a spec but cannot approve the build) |
| Where they sit | Chatbot at `/agentic/chat/index.html`, mounted via the Interop Editor inject (`/ui/interop/interop-editor/...`) |
| Their input | One or more files: PDF (SoW, BRD, design doc), `.xlsx` (field mappings, message inventories), `.txt` / `.md` (notes, READMEs) |
| Their output | A configured, working integration in the target namespace (productions, business hosts, DTL transforms, routing rules, lookup tables, SQL tables) |

The Interface Engineer is the same persona who already builds Productions and
Transformations through the chat. The change is the ENTRY POINT: instead of
typing requirements into the composer, they hand the source document to the
agent.

---

## 3. Trigger

The user wants to begin a piece of integration work and the requirements
already live in a document. They open the chat, drag the document onto the
composer (or click the paperclip), optionally add a short message, and press
Send. The agent does the rest.

---

## 4. Workflow

The end-to-end flow has six distinct phases. Phases 1–3 are the new
attachment-driven entry; phases 4–6 are the existing build loop the Interface
Engineer already knows.

### Phase 1 — Drop and stage

| Step | Who | What |
|---|---|---|
| 1.1 | User | Drops file(s) into the composer or clicks the paperclip. A chip per file shows the filename and size, with a remove (×) button. |
| 1.2 | User | (Optional) Types a short prompt — "build this", "create the spec", "summarize and propose a plan". A turn with attachments and no prompt is allowed. |
| 1.3 | User | Presses Send. |
| 1.4 | Backend | `ChatService.ChatStream` (multipart-aware) stages each file under `<mgr>/Temp/agentic-attach/<sessionId>/` owned by `irisowner`, validates the extension whitelist (pdf / xlsx / txt / md), and calls `Editor.AttachmentExtractor`. |
| 1.5 | Backend | Extractor pulls plain text: PyMuPDF for PDF (per-page, with `--- page N ---` markers), openpyxl for xlsx (per-sheet, pipe-delimited rows), passthrough for txt/md. Text is capped at 150 000 chars per file with an annotated truncation marker. |
| 1.6 | Backend | The extracted text is appended to the user's message as one `<attachment name="X" type="pdf" pages="N">…</attachment>` block per file before the message reaches the LLM. The agent sees the attachments in iteration 1. |

### Phase 2 — Synthesize the specification

| Step | Who | What |
|---|---|---|
| 2.1 | Agent | The Agentic Integration Builder INSTRUCTIONS contain an ATTACHMENT WORKFLOW section. When the turn carries `<attachment>` blocks, the agent's ONLY job for this turn is to synthesize the Project Specification — no tool calls, no research, no build. |
| 2.2 | Agent | Produces the spec in a fixed template wrapped in `[[SPEC]] … [[/SPEC]]` markers: Overview, Exercises (one numbered subsection per integration / transformation / loader, each with Goal / Inputs / Outputs / Transformation rules / Routing rules / Acceptance criteria), Open questions (where the source document is ambiguous), Build tasks (the plain-language list of what will be created on approval). |
| 2.3 | Chat UI | Detects the `[[SPEC]]` markers on stream completion and replaces them with a structured Spec Card inside the assistant bubble: section headings, bulleted rules, an Approve, build it button and an Edit button. |
| 2.4 | Agent | Closes with exactly one line: *"Does this match what you want me to build? Reply `approve, build it` to start the build, or tell me what to change."* |

The agent does not run any action tool in this phase. The user always sees
what the agent understood before any state changes.

### Phase 3 — Review, revise, or approve

| Path | What happens |
|---|---|
| Approve | The user clicks Approve, build it (sends `approve, build it` as the next user turn) or types the same phrase. The agent enters Phase 4. |
| Edit (small change) | The user types the revision in natural language: *"change exercise 2 to also strip leading zeros from PID:3"*, *"the routing rule for ADT should also check MSH:9"*. The agent revises and re-emits a fresh `[[SPEC]]` block (Phase 2 repeats). |
| Edit (rewrite) | The user clicks Edit. The full spec markdown loads into the composer textarea; they revise it inline and press Send. The agent treats the edited text as the new authoritative spec and re-emits it. |
| Operator (view-only) | Operators can drop a document and receive a spec, but the agent refuses to enter Phase 4 — the role-based tool filter denies write tools. The Operator hands the spec to an Interface Engineer for approval. |

Approval is a turn-level event. The accepted spec stays in the conversation
history so subsequent build turns reference it.

### Phase 4 — Research

Identical to the existing "Build Productions" use case (`01_Requirements_User_Stories.md` §5.1, first response pattern):

- `GetUserNamespace` to confirm the target.
- `search_ens` / `search_hs` against the vector catalogs to find the right Business Hosts and transformation classes for what the spec says.
- `GetHL7SchemaMap` and similar lookups for any schema the spec names.
- Reads from the relevant skills (Productions, DTL, BPL, Routing Rules, HL7 v2, FHIR R4, SDA, Adapters, etc.) for domain detail.

All Phase 4 calls are read-only. The user sees them as tool cards in the chat
("3 actions running…").

### Phase 5 — Plan and ask

The agent presents a numbered build plan — productions, business hosts, DTL
transforms, routing rules, lookup tables, SQL tables, alerts — naming each
artifact, its target namespace, and what it produces. For any mutating tool
(CreateProduction, AddBusinessHost, CreateDTL, CreateRoutingRule, etc.) the
agent stops and asks the user to confirm before firing. This is the existing
plan → authorize → act gate (see Agentic Integration Builder INSTRUCTIONS, §"Response
pattern"); the spec-driven flow does NOT bypass it.

### Phase 6 — Build and verify

On approval, the agent fires the build tools in the right order, reports the
result of each (artifact name, namespace, status), and offers to run a smoke
test (BuildHL7TestMessage → SendHL7 → VisualTrace, or the FHIR analogue). The
accepted spec from Phase 2 is the authoritative source of "what to build", so
the final artifact set traces back to the original document.

---

## 5. Worked example: Sanford SoW

Concrete walkthrough using `docs/sample_attachments/Sanford_SoW.pdf` (the
2019 Health Connect Proof of Concept Statement of Work). The PDF is 7 pages
and defines three integration exercises.

### What the user does

1. Opens the chat panel from the Interop Editor.
2. Drags `Sanford_SoW.pdf` onto the composer. A chip appears: *Sanford_SoW.pdf · 1.1 MB · ×*.
3. Types *"create the spec for this integration."*
4. Presses Send.

### What the agent does (Phase 2 output, abridged)

```
[[SPEC]]
# Project Specification: InterSystems Health Connect Proof of Concept - Sanford Health

## Overview
A comprehensive proof of concept demonstrating Health Connect's capabilities through
three distinct exercises: one-to-many HL7 ADT routing with custom transformations,
ORU message manipulation with OBX segment formatting, and database-driven message
enrichment using ORM/SIU message pairs.

## Exercises

### 1. HL7 ADT one-to-many routing
- Goal: Route a single inbound ADT message to multiple downstream systems with custom transformations
- Inputs: ADT messages with custom SH2.5 schema including Z3R segment, inbound via file service
- Outputs: Three file operations (two transformed, one original)
- Transformation rules:
  - Remove dashes from social security number (PID:19)
  - Set MSH:3 (Sending Application) to "EPIC"
  - Substring EVN:2 to first 8 characters (date only)
  - Loop PID:3, find the MRN whose Assigning Authority is "USDMC", copy ONLY that MRN
  - Lookup table for gender code (Male→M, Female→F, Unknown→U)
  - If PV1:19 is defined, copy its contents to PID:18
- Routing rules:
  - Route only ADT^A01 where MSH:4 = "USDMC"; filter everything else
- Acceptance criteria: validate transformation + routing logic, verify output files, confirm via Message Browser and Visual Trace

### 2. HL7 ORU OBX manipulation
- Goal: Format OBX segments in ORU^R01 messages with header/footer insertion and text wrapping
- (… full rules …)

### 3. ORM / SIU enrichment via SQL
- Goal: Persist ORM facts in a SQL table; on SIU, look up by MRN + order number; enrich and forward; delete the row; alert on miss
- (… full rules …)

## Open questions
1. Where does the SH2.5 schema with Z3R live — supplied as an XML, or to be authored from the segment description?
2. Which target file operations are expected — file paths and naming convention?

## Build tasks (post-approval)
1. SH2.5 + Z3R schema (HL7 Schema editor or imported XML)
2. Gender lookup table seeded from the spec values
3. SQL table for ORM facts (MRN, OrderNumber, ServiceIdentifier)
4. DTL transforms: ADT-to-ADT and ORU-to-ORU
5. ORM/SIU business process for the enrichment flow
6. Routing rule sets for ADT and ORU
7. Production with file services, routing engines, file operations, and alert configuration
[[/SPEC]]

Does this match what you want me to build? Reply `approve, build it` to start the build, or tell me what to change.
```

### What the user does next

- If the open questions are wrong, the user answers them in chat. The agent revises and re-emits.
- When the spec matches the user's intent, the user clicks Approve, build it.
- The agent enters Phase 4 (research) and continues to Phase 5 and 6.

---

## 6. UI surface

| Element | Where | Behavior |
|---|---|---|
| Paperclip button | Composer, left of Send | Opens a multi-select file picker (`accept=".pdf,.xlsx,.xlsm,.txt,.md,.markdown"`) |
| File chips | Above the textarea | One chip per queued file: name · size · × to remove |
| Drag-drop zone | Composer shell + messages area | Drop a file anywhere on the chat panel; the composer outlines while a file is over it |
| Per-file caps | Client + server | 10 MB per file (client gate); 150 000 chars of extracted text per file (server gate, annotated on truncation) |
| Type-mismatch toast | Composer | "Unsupported: foo.docx — accept pdf, xlsx, txt, md." |
| Spec Card | Assistant bubble | Replaces the `[[SPEC]] … [[/SPEC]]` markers with a themed card: sections, bullets, Approve / Edit buttons |
| Approve button | Spec Card | Sends `approve, build it` and disables both buttons |
| Edit button | Spec Card | Loads the spec markdown into the composer textarea so the user can revise inline and resend |

---

## 7. Acceptance criteria

1. A user can drop a PDF, xlsx, txt, or md file onto the composer and see a chip; they can remove the chip before sending.
2. On Send, the agent's first response is a Project Specification wrapped in `[[SPEC]] … [[/SPEC]]` markers and rendered as a structured card with Approve and Edit buttons.
3. The agent does NOT call any mutating tool on the same turn it synthesizes a spec.
4. The spec's Exercises section names each integration/transformation found in the source document and includes the transformation rules verbatim where the document is explicit.
5. The user can click Approve, build it and the agent transitions into the existing plan → authorize → act loop using the spec as the source of truth.
6. The user can click Edit, change the spec text in the composer, and resend; the agent re-emits a fresh spec card from the revised text.
7. Operators can drop a document and receive a spec; the role-based tool filter prevents them from approving the build.
8. Unsupported file types are rejected client-side with a toast AND server-side with a `Skipping unsupported attachment` trace; the chat session is not killed.
9. Files larger than 10 MB are rejected client-side with a toast naming the size and limit.
10. The build phase, when it runs, produces artifacts that match the spec's Build tasks list one-for-one and traces back to the original document via the accepted spec in the conversation history.

---

## 8. Why this matters

| Without the use case | With the use case |
|---|---|
| The Interface Engineer reads the SoW, hand-types the requirements into the chat, may paraphrase or omit details, then hopes the agent's interpretation matches the document. | The Interface Engineer drops the SoW. The agent reads the actual text, presents a structured spec, and the user confirms the agent's understanding BEFORE any build runs. |
| Rules buried on page 4 of a PDF can be missed. | The agent extracts the full document text and surfaces every rule it found in the Exercises section. |
| Edits require re-explaining the change in prose. | Edits are made inline against the spec text the agent already produced. |
| Operators cannot meaningfully participate in scoping. | Operators can produce specs for review by Interface Engineers. |
| Builds happen against the agent's INTERPRETATION of typed prose. | Builds happen against an EXPLICITLY APPROVED specification that lives in the conversation history. |

---

## 9. Implementation reference

The technical plan of record for this feature lives in
`docs/AttachmentWorkflow.md`. Highlights of the moving parts:

- `AgenticInterop.Editor.AttachmentExtractor` — Embedded Python extractor (PyMuPDF for PDF, openpyxl for xlsx, passthrough for txt/md). Returns plain text plus per-type metadata (pages / sheets).
- `AgenticInterop.Data.ChatSpec` — Per-conversation Project Specification persistence (compiled, reserved for v2 — v1 keeps the spec in the conversation history).
- `AgenticInterop.Editor.ChatService.ChatStream` — Multipart-aware: reads the JSON `body` part from `%request.Data` and file parts from `%request.MIMEData`, injects `<attachment>` blocks into the iteration-1 user message.
- `AgenticInterop.Agent.HealthInterop` — INSTRUCTIONS XData with the ATTACHMENT WORKFLOW section that gates Phase 2 (no tool calls, `[[SPEC]]` template, approval phrases).
- `src/csp/agentic/chat/chat.js` + `chat.css` — Composer paperclip + chips + drag-drop, FormData multipart send, Spec Card render with Approve / Edit.

---

## 10. Out of scope for v1

- OCR for scanned / image-only PDFs (deferred to v2 — PyMuPDF would need Tesseract or a vision LLM call).
- `.docx` / `.pptx` / audio attachments (deferred to v2).
- Multi-user collaborative editing of a spec (the spec is per-session; v2 may persist via `Data.ChatSpec` so it can be shared).
- Diff view between spec versions (v2 polish).

---

## 11. Related use cases and documents

- `docs/01_Requirements_User_Stories.md` §2.3 (Interface Engineer persona), §5.1 (Build Productions), §5.3 (Create Transformations).
- `docs/AttachmentWorkflow.md` — technical plan of record.
- `docs/FHIRServerMCP.md` — FHIR-side feature inventory (the FHIR Specialist chatbot is currently out of scope for this use case; v1 targets only the Interop Editor chatbot).
- `docs/PRD.md` — overall product framing.
