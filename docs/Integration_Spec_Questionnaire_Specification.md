# InterSystems Integration Spec Questionnaire — Specification

> **Component of:** Agentic Integration Builder (AIB)
> **Built on:** InterSystems AI Hub (`%AI`) framework
> **Platform:** IRIS for Health / Health Connect 2026.2+ · MVP target Health Connect Cloud
> **Status:** Implemented and running · v0.1 · July 2026
> **Related:** [`Product_Requirements_Integration_Agentic_Builder.md`](Product_Requirements_Integration_Agentic_Builder.md) (parent PRD) ·
> [`Integration_Spec_Questionnaire_Design.md`](Integration_Spec_Questionnaire_Design.md) (design rationale)

---

## 1. Business need

### 1.1 The problem

Customers struggle to **specify** interfaces more than they struggle to build them.

The Agentic Integration Builder made building fast — an engineer describes an interface and the agent constructs it. That moved the bottleneck upstream. The agent can only build what it has been told, and what it is told is routinely incomplete in exactly the places that matter.

Statements of Work, business requirements documents and field-mapping spreadsheets are written for humans. They describe intent — *"send admissions to the lab system"* — and omit the decisions Health Connect actually requires: which acknowledgment mode, where acknowledgments are written when the inbound is file-based, what happens to a message that fails to transform, whether ordering matters, which schema category the inbound service carries.

### 1.2 Cost of the status quo

An incomplete specification produces one of two outcomes, both expensive:

| Outcome | Cost |
|---|---|
| **Clarification loop** | The agent asks; the engineer answers; repeat. Every round trip is latency, tokens, and an opportunity for the conversation to drift. On a provider under token-per-minute pressure, it is also a throttling risk. |
| **Silent wrong assumption** | Worse. The build succeeds, the demo passes, and the defect surfaces in production. |

The third outcome — the specification is complete — is rare, and today depends entirely on the individual engineer's platform experience.

The silent-assumption class is the one that justifies this work. Three real examples, all of which produce a *working-looking* interface:

- **Acknowledgments that land nowhere.** Application ACKs configured on a file-based inbound service, which has no return channel. The production logs a warning; nothing else happens.
- **A routing rule that never matches.** `MessageSchemaCategory` unset on the inbound service, so messages carry no document type and no rule constraint ever fires.
- **A transformation that emits one segment.** An HL7-to-HL7 target created with no segment terminator writes only the MSH.

None of these fail loudly. All of them are the direct consequence of a decision nobody was asked to make.

### 1.3 The insight this product is built on

**We do not have to invent the definition of a complete specification. The agent already contains it.**

`AgenticInterop.Agent.HealthInterop` carries a mandatory "check for gaps" step that enumerates, in the agent's own instructions, every decision it must never silently default:

> ACK target and mode for file/FTP services · dead-letter and bad-message destination and handler · retry interval and failure timeout (healthcare default `FailureTimeout=-1`) · pool size when FIFO matters · `MessageSchemaCategory` on the inbound service · archive path for file pickups · the segment terminator on HL7-to-HL7 DTL targets

Plus a hard never-assume list: **transport**, **HL7 version**, **`MessageSchemaCategory`**.

That list *is* the specification schema. The questionnaire is that list externalised into a user interface — asked **up front**, in a form, instead of discovered mid-conversation through back-and-forth.

This also gives the work an unusually strong provenance argument: it is not an InterSystems-invented novelty. The InterSystems documentation already prescribes the same shape — the "production spreadsheet" intake template in *Best Practices for Creating Productions* §2.3 (Feed · Application · Name · Type · Connection · Sends · Receives · ACKs), the naming conventions in §2.5, and the machine-consumable interface-route grammar of the HL7 Production Generator. **This is documented best practice made executable.**

### 1.4 Business outcomes

| Outcome | How it is achieved | Observable measure |
|---|---|---|
| Fewer clarification round trips | Gap-check items are pre-answered in a `Confirmed defaults` block | Turns from request to plan |
| Fewer production defects from unstated assumptions | Every gap item is either answered or explicitly raised as an open question | Defects traced to unspecified configuration |
| A non-developer can produce a complete specification | Guided form, grounded options, recommended healthcare defaults | Specifications completed without platform expertise |
| Specifications become reusable, auditable artifacts | Machine-readable output, versioned, carried in conversation history | Specification reuse across environments |
| Faster time to a working interface | Three entry paths; description to populated form in ~20 seconds | Time to first working interface |

### 1.5 Non-goals

- Not a mapping tool. Complex field-level mapping belongs in the dedicated visual tool (see §6.7).
- Not a build tool. The questionnaire **creates nothing** on the instance; it is read-only.
- Not a replacement for document upload. It complements it (§4.4).

---

## 2. Personas

| Persona | Role in this component |
|---|---|
| **Integration Engineer** (primary, non-developer) | Completes the questionnaire, verifies extracted answers, reviews and sends the specification |
| **AI Admin** (InterSystems-internal, MVP) | Maintains the catalogs the questionnaire draws its options from; will own questionnaire templates when configurability ships |
| **Operator** | May produce a specification for review; cannot approve a build |

---

## 3. Primary use case

### UC-1 — Specify an Epic-to-Quest interface

**Actor:** Integration Engineer · **Goal:** produce a complete, verified specification for an interface that the agent can build without asking clarifying questions.

**Precondition:** the engineer is signed into the Interop Editor with an LLM connection configured and the catalogs indexed.

**Trigger:** Epic will send HL7 v2.5 ADT admissions over MLLP; Quest must receive transformed ORU over MLLP; specific field rules apply.

#### Main flow

| # | Actor | Step |
|---|---|---|
| 1 | Engineer | Opens **Integration Spec** from the Interop Editor toolbar. The questionnaire opens with all sections collapsed — a one-screen index of the work, each section showing a required-answers chip. |
| 2 | Engineer | Types the requirement into **Start from a description** in plain language, including the transformation rules. |
| 3 | System | Sends the description plus the questionnaire schema to the extractor agent. |
| 4 | System | Populates the form from the response, marks every filled field **verify**, and lists anything it could not determine. |
| 5 | Engineer | Reviews the marked fields, corrects the interface name, and answers the outstanding items using the **Still needed** list. |
| 6 | Engineer | Opens **Source** and selects the exact inbound business service from the catalog, reading the class description in place. |
| 7 | Engineer | Opens **Transformation** and browses available transformations to confirm none already does the job. |
| 8 | Engineer | Clicks **Output Trial**, reviews the generated specification, and switches output format if required. |
| 9 | Engineer | Clicks **Send it to AIB**. The chat opens in the same namespace with the specification as the first turn. |
| 10 | Agent | Responds with a specification card, then a build plan — **without a clarification round**, because the gap items were pre-answered. |

**Postcondition:** an approved specification exists in conversation history and is the authoritative source for the build.

#### Alternate flows

- **A1 — Form first.** The engineer skips the description and completes the form directly. Steps 3–5 do not occur.
- **A2 — Document first.** The engineer attaches a Statement of Work in the chat; the agent synthesises a specification. The questionnaire is used afterwards to fill the gaps the document left.
- **A3 — Complex mapping.** At step 7 the engineer instead uses **GO TO DATA ATLAS** and builds the transformation visually, returning to reference it.
- **A4 — Unknown answer.** The engineer selects *Not sure*. The item is emitted as an open question rather than defaulted.

#### Acceptance criteria

1. A description containing transport, port, message type, two field rules, a destination and a dead-letter path populates the corresponding fields without manual entry.
2. Every populated field is visually marked for verification before it can be sent.
3. Anything the description did not state is listed, not invented.
4. The generated specification contains a `Confirmed defaults` block covering every applicable gap-check item.
5. Selecting a class from the catalog causes that class to appear in the specification.
6. The agent proceeds from specification to plan without asking about a gap item that was answered.

---

## 4. Functional requirements

### 4.1 Questionnaire structure

| ID | Requirement |
|---|---|
| **FR-1** | The questionnaire is defined by a schema (sections → questions), not by hard-coded markup, so fields can be added, removed or relabelled without changing rendering logic. |
| **FR-2** | Questions are tiered **Essential / Recommended / Advanced**, and revealed conditionally — a question is shown only when its predicate holds (no MLLP port unless the transport is TCP; no ACK-target question unless the inbound is file-based and application ACKs were requested). |
| **FR-3** | Every question traces to a tool input parameter or a documented agent gap item. No question exists without that provenance. |
| **FR-4** | *Not sure* is a first-class answer that routes the item to **Open questions** in the output. The system must never substitute a default for an unknown. |
| **FR-5** | Fields carrying a healthcare default (`FailureTimeout=-1`, `Validation=""`, pool size 1 under FIFO) are pre-filled and labelled as recommended and overridable. |
| **FR-6** | Sections open collapsed. Each header carries a required-answers chip that reflects only currently visible questions. |
| **FR-7** | Outstanding required answers are listed, grouped by section, and each entry navigates to its field. |

### 4.2 Describe-it-first

| ID | Requirement |
|---|---|
| **FR-8** | The user can describe the interface in prose and have the form populated from it. |
| **FR-9** | Extraction receives the current questionnaire schema, so customer-modified fields are honoured without a backend change. |
| **FR-10** | Populated fields are visually marked pending verification. The user always confirms before sending. |
| **FR-11** | Only known field identifiers are accepted, and option-backed fields accept only listed values. Unrecognised fields or values are discarded, never applied. |
| **FR-12** | Values are routed by what the schema says a field is, not by which bucket the model returned them in. |
| **FR-13** | Anything the description did not state is surfaced as a note, not inferred. |
| **FR-14** | Worked examples can be loaded with one action, cycling through distinct interface shapes. |

### 4.3 Catalog-backed selection

| ID | Requirement |
|---|---|
| **FR-15** | The user can select the **inbound business service** and **inbound adapter** from the instance's indexed catalog. |
| **FR-16** | The user can select the **outbound business operation** and **adapter** per destination. |
| **FR-17** | The user can browse **available transformations** with their descriptions and select one to reuse. |
| **FR-18** | The catalog picker is searchable across class name and description, and filtered to the relevant class kind. |
| **FR-19** | Each entry displays the curated description the agent itself searches; the selected class's description remains visible in the form. |
| **FR-20** | All catalog selections are optional. Unset, the agent searches and proposes as before; set, the choice is stated in the output and the agent uses it. |
| **FR-21** | Browsing the catalog is read-only and changes nothing on the instance. |

### 4.4 Output and hand-off

| ID | Requirement |
|---|---|
| **FR-22** | **Output Trial** renders an editable preview of the generated specification before anything is sent. |
| **FR-23** | Output is available as **prose**, **JSON**, or **both**. Both is the default: JSON is the authoritative machine payload, prose is the human-readable rendering and drives the approval card. |
| **FR-24** | The prose output conforms to the specification contract the agent already understands, so it renders as the existing approval card and enters the existing plan → approve → build loop. No new agent path. |
| **FR-25** | The output includes a **Confirmed defaults** block pre-answering the applicable gap-check items, so the agent proceeds to plan without a clarification round. |
| **FR-26** | The JSON payload is keyed to tool parameter names. An absent key means *not specified* and instructs the agent to ask rather than assume. |
| **FR-27** | **Send it to AIB** delivers the specification to the chatbot scoped to the same namespace, as the first turn of a conversation. |
| **FR-28** | Artifact names are generated from the documented InterSystems naming conventions and shown before sending. |
| **FR-29** | **GO TO DATA ATLAS** hands off to the visual transformation tool. *Currently a placeholder; target configurable per deployment.* |

### 4.5 Persistence

| ID | Requirement |
|---|---|
| **FR-30** | Every specification the questionnaire generates is persisted automatically, with the answer set that produced it. The user never has to remember to save. |
| **FR-31** | Both halves are stored. The prompt alone cannot repopulate the form; the answers alone do not record what was actually sent, because the preview is editable. |
| **FR-32** | A questionnaire is saved by an explicit **Save**, and again when it is sent to the agent from either the preview or the footer. Both record it under the questionnaire's interface name. |
| **FR-33** | One row per questionnaire per user per namespace. Re-saving or re-sending the same named questionnaire updates that row in place; only a new name creates a new entry. |
| **FR-34** | Saved runs are listable, filterable, and scoped to the caller's namespace and user by default. |
| **FR-35** | A saved run can be reloaded into the form, restoring both answers and repeating groups. |
| **FR-36** | A saved run can be deleted. |
| **FR-37** | A failed save never blocks review or sending. Persistence is a side effect, not a gate. |
| **FR-38** | The worklist is a **screen of its own**, reached from a tab in the header carrying a count, not a dialog buried in a toolbar. |
| **FR-42** | Each row shows the questionnaire name as a link that reopens it, who created it, and when it was last saved. |
| **FR-43** | Each row can copy its generated prompt to the clipboard, re-send it to the agent, or be deleted, without opening the questionnaire. |
| **FR-44** | Saving requires an interface name. An unnamed row is useless in a worklist, so Save refuses and takes the user to the field. |
| **FR-45** | Searchable by interface name, short name, user and namespace, so an engineer can find an earlier specification without scrolling. |
| **FR-39** | Search runs server-side, so a long history is never shipped to the browser to be filtered. |
| **FR-40** | A run can be **starred**. Starred runs sort above everything else regardless of age, and can be filtered to on their own. |
| **FR-41** | Starring is optimistic — the star reflects the click immediately and rolls back only if the server refuses. |

---

## 5. Technical requirements

### 5.1 Architecture

```
Interop Editor (Angular, authenticated)
  │  toolbar: Integration Spec
  ▼
/agentic/spec/                     ← questionnaire (static, no framework)
  │   ├─ schema-driven renderer
  │   ├─ catalog picker
  │   └─ spec generator (prose + JSON)
  │
  ├── POST /api/agentic/chat ──────► AgenticInterop.Agent.SpecExtractor
  │        (agentClass override)      1 iteration · no tools · no skills
  │
  ├── GET  /api/agentic/catalog/browse ─► Ens (164) · HS (58) vector catalogs
  │
  └── hand-off ─► /agentic/chat/ ──► AgenticInterop.Agent.HealthInterop
                                       plan → approve → build → validate
```

| ID | Requirement |
|---|---|
| **TR-1** | The questionnaire is a static page served by the existing `/agentic` CSP application. No framework, no build step, matching the established UI family. |
| **TR-2** | It introduces **no new REST endpoints**. It consumes `POST /chat` and `GET /catalog/browse`, both of which already exist. |
| **TR-3** | It ships inside the existing IPM module. The CSP application already deploys the directory recursively, so no manifest change is required. |

### 5.2 Extraction agent

| ID | Requirement |
|---|---|
| **TR-4** | Extraction runs on a dedicated agent class, not the generalist. It is a text-to-JSON transform, so binding the full tool catalogue would add prompt overhead, invite unwanted tool calls, and worsen provider throttling. |
| **TR-5** | The agent is constrained to **one iteration**, **temperature 0**, **no MCP servers**, **no skills**, **no tools**. |
| **TR-6** | Having no tool results, extraction is unaffected by the provider tool-result round-trip defect that affects the generalist agent. |
| **TR-7** | The agent carries no field list. The schema arrives in the request. |
| **TR-8** | Output must be a single JSON object; the client tolerates a fenced response and extracts the object by brace matching. |

> **Implementation note.** Two framework behaviours are counter-intuitive and are documented in the class: tool binding must remain `mcp` (in `bypass` mode the manager ignores the MCP list and registers all six tool classes, roughly 140 tools, which the provider rejects for duplicate tool names); and the skills parameter must be a single space rather than empty, because the loader treats empty as *unspecified* and falls back to loading all thirteen skills.

### 5.3 Catalog access

| ID | Requirement |
|---|---|
| **TR-9** | Catalog entries are read from the instance's own indexed catalogs — currently 164 Ens/EnsLib business hosts and adapters and 58 HS transformation classes — via the existing browse endpoint. |
| **TR-10** | Entries are filtered client-side by class kind: business services, inbound adapters, business operations, outbound adapters. |
| **TR-11** | Catalog results are cached per session; the picker opens instantly after first load. |
| **TR-12** | Catalog access is read-only. |

### 5.4 Persistence

| ID | Requirement |
|---|---|
| **TR-18** | Runs persist to `AgenticInterop.Data.SpecResponse`. Answers and prompt are streams, because the mapping and destination tables have no fixed size. |
| **TR-19** | Four endpoints under the existing dispatcher: list, save, get, delete. Listing returns summaries only, so a large history does not read every blob. |
| **TR-20** | The record carries namespace, user, template key and version, completeness and output format, so a reload can tell whether the form has changed underneath it. |
| **TR-22** | Search is a parameterised, case-insensitive contains across the indexed identity columns. Ordering is `Favorite DESC, UpdatedAt DESC`, so starring is a first-class sort key rather than a client-side reshuffle. |
| **TR-24** | Upsert is keyed on `(InterfaceName, Username, Namespace)`, indexed. Streams are cleared before rewrite, so an update replaces the stored prompt rather than appending to it. |
| **TR-25** | `UpdatedAt` is distinct from `CreatedAt`: the worklist sorts and displays on last-touched, which is the question a user is actually asking. |
| **TR-23** | Rapid typing cannot render a stale result: each search carries a sequence number and a late response whose sequence is superseded is discarded. |
| **TR-21** | Distinct from `Data.ChatSpec`, which holds the per-conversation specification the agent synthesises from chat attachments. A questionnaire run is not tied to a chat session and outlives any conversation. |

### 5.5 Security

| ID | Requirement |
|---|---|
| **TR-13** | The page inherits the host application's IRIS session. It obtains the signed-in user's token from the parent via the established bridge, with the chat's stored credential as fallback. No second login. |
| **TR-14** | Every request carries the active namespace, and the server validates the user's access to it. |
| **TR-15** | The questionnaire performs **no mutating operation**. All state change remains behind the agent's approval gate. |
| **TR-16** | An authorization failure is reported plainly and actionably; it never fails silently. |
| **TR-17** | All requests are captured by the existing audit trail. |

### 5.6 Performance

| Metric | Target | Measured |
|---|---|---|
| Page render | Under 1 second | Immediate; static assets |
| Catalog picker first open | Under 2 seconds | Single request, cached thereafter |
| Description extraction | Under 30 seconds | 16–23 seconds, ~3.0–3.4k tokens, 1 iteration |
| Specification generation | Immediate | Client-side |

> Extraction latency is user-visible. The interface must show progress for its duration and must never appear frozen.

---

## 6. Component inventory

| Component | Responsibility |
|---|---|
| `spec/index.html` · `spec.css` · `spec.js` | Questionnaire, catalog picker, generator, hand-off |
| `AgenticInterop.Agent.SpecExtractor` | Prose → structured answers |
| `inject.js` | Toolbar entry point and overlay in the Interop Editor |
| `chat/chat.js` | Consumes the handed-off specification as the first turn |

---

## 7. Out of scope

- Customer-facing template editing (add/remove/relabel fields through a UI). The schema supports it; the editor is not built.
- Populating options from live production configuration (existing productions, hosts, credentials, SSL configurations). Only the class catalogs are wired.
- Deriving a custom schema from sample messages.
- Emitting the HL7 Production Generator items-file format.
- A real Data Atlas target.

---

## 8. Status

**Implemented and verified:** schema-driven questionnaire with conditional reveal; describe-it-first extraction with verification marking and value validation; catalog-backed selection for inbound, outbound and transformation; prose/JSON/both output with confirmed defaults and open questions; hand-off to the chatbot; worked examples; collapsed-by-default interface with per-section progress and a readiness list.

**Known limitations:** the page requires the host application's session, so opened standalone it reports an authorization error until the chat has been signed into; Data Atlas is a placeholder; extraction takes 16–23 seconds against the current provider.

**Recommended next:** environment prefill (TR — populate namespaces, productions, hosts, credentials and SSL configurations from the live instance), then template configurability.

---

## Appendix — Traceability

| Gap-check item (agent instructions) | Questionnaire field |
|---|---|
| ACK mode | Acknowledgment mode |
| ACK target for file/FTP | Where should ACKs be written (conditional) |
| Dead-letter / bad-message destination | Dead-letter destination (required) |
| Retry interval and failure timeout | Per destination, default `-1` |
| Pool size when FIFO matters | Ordering required → pool size 1 |
| `MessageSchemaCategory` | HL7 schema category (required) |
| Archive path for file pickups | Archive directory (conditional) |
| Segment terminator on HL7-to-HL7 targets | Stamp a segment terminator |
| Never assume transport | Inbound transport (required) |
| Never assume HL7 version | HL7 schema category (required) |
