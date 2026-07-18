# Chatbot Attachment Workflow — Plan of Record

## What

The interop-editor chatbot (Agentic Interoperability Builder (AIB) agent) accepts file attachments
(PDF, xlsx, txt, md) alongside the user's prompt, synthesizes the attached
document into a structured Project Specification, presents it to the user
for approval, and only on approval enters the existing plan → authorize →
act loop to build the integrations the spec describes.

## Why

Statements of Work, business requirements documents, and field-mapping
spreadsheets are the real inputs to interoperability work. Forcing users
to retype the spec into the chat is wasteful and lossy. Letting the agent
read the source document directly and then confirm its understanding
before any build action removes guesswork and prevents the "agent built
the wrong thing" failure mode.

## Scope (v1)

Target chatbot: interop-editor (`Data.Chatbot` key `interop` ->
`AgenticInterop.Agent.HealthInterop`). The FHIR Management chatbot is
out of scope for v1.

Supported file types: PDF (PyMuPDF/fitz), .xlsx (openpyxl), .txt, .md.
Image-only / scanned PDFs (OCR) are deferred to v2.

Out of scope for v1: .docx, .doc, .pptx, images, audio. The
content-type gate refuses these with a plain message so the user is told
upfront and the LLM never sees an empty attachment.

## End-to-end flow

1. User drags file(s) into the chat composer (or clicks the paperclip).
   The chat panel shows a chip per file with name + size + remove (X).
2. On Send, the chat POSTs the message + file(s) to
   `POST /api/agentic/chat/stream` as `multipart/form-data`:
   - field `body` = the existing JSON body (message, history, chatbot, ...).
   - field `files` repeated per attachment.
3. `Editor.ChatService.ChatStream` stages each file under
   `<mgr>/Temp/agentic-attach/<sessionId>/<filename>` (irisowner-owned),
   then calls `Editor.AttachmentExtractor` to pull text out of each file.
4. Each extracted block is appended to the user message as:
   ```
   <attachment name="X.pdf" type="application/pdf" pages="7">
   ...extracted text...
   </attachment>
   ```
   The agent sees this in `iteration=1`'s `message`.
5. The HealthInterop agent has a new ATTACHMENT WORKFLOW section in its
   INSTRUCTIONS. When a turn contains one or more `<attachment>` blocks,
   the agent's only job in that turn is to synthesize a Project
   Specification (Overview, Exercises, Rules, Acceptance, Open Questions)
   and present it as a structured spec card, then STOP and wait for the
   user's approval. It is forbidden to call any action tool on this turn.
6. The chat renders the spec response as a structured card with:
   - Section headings, bullet lists.
   - Approve button → sends "approve, build it".
   - Edit button → opens an inline textarea pre-filled with the spec
     text; user edits, presses "Save and re-summarize" → the edited
     spec is sent back to the agent as the next turn.
7. On approval, the spec is persisted in `Data.ChatSpec` (sessionId,
   version=N, status=accepted, body=text). The agent then enters its
   normal plan → authorize → act loop, treating the accepted spec as
   the authoritative source of "what to build".
8. On "edit" iterations, the prior `ChatSpec` row is superseded
   (status=superseded) and a new draft is written.

## What gets built

### Backend
- A. `AgenticInterop.Editor.AttachmentExtractor` — Embedded Python
  helper. One ClassMethod per supported type, plus an `Extract(path)`
  dispatcher that sniffs by extension. PDF: PyMuPDF/fitz. xlsx:
  openpyxl. txt/md: stream read.
- B. `AgenticInterop.Data.ChatSpec` — persistent entity. Properties:
  SessionId, Version, Status (draft|accepted|superseded), Body,
  CreatedAt, AcceptedAt?, AttachmentNames.
- C. `Editor.ChatService.ChatStream` — multipart-aware. Detects
  Content-Type starts with `multipart/form-data`, reads the `body` part
  as the existing JSON, reads each `files` part, stages it, calls
  Extractor, injects `<attachment>` blocks into the user message.
  Falls through to the existing JSON path when no multipart.

### Frontend
- D. `agentic/chat/chat.js` composer changes:
  - Paperclip button next to Send.
  - Drag-drop overlay on the messages area.
  - File chips below the textarea (name, size, X).
  - On Send: if files, build FormData with `body` (current JSON) + `files`;
    set fetch headers to NOT include explicit Content-Type (browser sets
    multipart boundary).
  - Per-file size cap 10MB; type whitelist matches backend.
- E. Spec card rendering — when an assistant SSE `done` arrives and the
  message text begins with the agreed-on marker `[[SPEC]]` and ends with
  `[[/SPEC]]`, parse the inner content as markdown sections and render
  as a structured card with two buttons:
  - Approve → sends `approve, build it`.
  - Edit → expands an inline `<textarea>` with the spec markdown
    pre-populated; "Save and re-summarize" submits the edited text.

### Agent
- F. `AgenticInterop.Agent.HealthInterop` INSTRUCTIONS XData — add an
  ATTACHMENT WORKFLOW section that:
  - On any turn containing `<attachment>` blocks, synthesize a spec and
    output it wrapped in `[[SPEC]] ... [[/SPEC]]` markers. No tool calls.
  - On the next user turn, if the user says "approve" / "build it" /
    similar, proceed to the existing plan → authorize → act loop.
  - On "edit / change X", revise the spec and re-emit between the same
    markers.

## Reading order for execution

1. Doc (this file) — committed.
2. Python extractor + Data.ChatSpec — small, low risk.
3. ChatService multipart path — touches the streaming entry point;
   guarded so JSON-only requests are unchanged.
4. Agent INSTRUCTIONS — add ATTACHMENT WORKFLOW; verify the existing
   plan-authorize text still applies post-approval.
5. Chat UI composer changes — incremental, no regression risk to the
   non-attachment chat flow.
6. Spec card rendering — last, layered on top of the working pipeline.
7. End-to-end test with the Sanford SoW PDF as the input.

## Out of scope for v1 (call out so we don't drift)

- OCR for image-only PDFs.
- Docx/pptx/audio.
- Multi-user spec collaboration (the spec is per-session only).
- Server-side virus scanning (users are authenticated; trust boundary
  is the existing chat auth).
