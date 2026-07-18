# Agentic Interoperability Builder — Product Requirements

> **Product:** Agentic Interoperability Builder (AIB). An AI agent that builds healthcare interfaces by chat.
> **Built on:** the InterSystems AI Hub (`%AI`) framework.
> **Platform (MVP):** Health Connect Cloud. The product runs on IRIS for Health / Health Connect 2026.2+.
> **Status:** Draft for review. **Date:** July 2026.
> **Canonical.** This document supersedes `docs/PRD.md` (originally published as "Health Interop AI Copilot") and the standalone
> `PRD_Agentic_Integration_Builder` draft. The **FHIR Assistant is a separate product** — see
> `docs/Product_Requirements_FHIR_Assistant.md`. It is out of scope here.

---

## 1. Overview

### 1.1 What it is

The Agentic Interoperability Builder helps an integration engineer build healthcare interfaces in Health Connect Cloud by describing them in plain language — or by handing over a specification document. The agent researches the platform, proposes a plan, and, on the engineer's approval, builds the productions, transformations, routing rules and lookup tables using real IRIS APIs.

It is a **development-time tool, not a production runtime component.** It accelerates the *authoring* of interfaces; it does not sit in the live message path. Once an interface is built, tested and promoted, the agent has no role in its execution. Nothing it produces depends on the agent being present at runtime — the artifacts are standard IRIS classes.

### 1.2 An AI Agent Hub built on the AI Hub foundation

AIB is **an AI Agent Hub implemented on top of our foundation, the InterSystems AI Hub.** It is not a bespoke application that reimplements agent plumbing. Every moving part is a standard `%AI` primitive:

| AI Hub primitive | Role in AIB |
|---|---|
| `%AI.Agent` | The orchestrator that receives the engineer's message and drives the build |
| `%AI.MCP.Service` | Named capability domains grouping tools |
| `%AI.ToolSet` / `%AI.Tool` | The IRIS-native tools the agent calls |
| `%AI.Agent.Skill` | Declarative domain-knowledge sub-agents |
| `%AI.RAG.KnowledgeBase` | Vector search over the class catalogs |
| `%AI.Agent.Policy` | Authorization, audit and confirmation policies |

AIB does not modify or replace the framework. Where framework defects were found, they were worked around at the application layer (§13), leaving framework classes untouched.

### 1.3 The value is the Healthcare AI Harness

AI Hub gives us the agent engine. **The differentiated value of AIB is the Healthcare AI Harness layered on top** — the encoded knowledge of *how to do healthcare integration correctly on this platform*:

- **How to deal with healthcare data** — HL7 v2, FHIR R4, SDA3, CDA/C-CDA, X12/HIPAA, and the rule that IRIS never converts directly between wire formats (SDA3 is the intermediary hub).
- **Policies** — the guardrails that stop an LLM doing dangerous or wrong things: approval on every mutation, permission delegation to the signed-in user, read-only Foundation namespaces, tool filtering.
- **Skills** — curated, platform-specific knowledge (production anatomy, DTL `foreach`/subtransforms, routing-rule grammar, ACK semantics, the SDA pipeline) that a model does not have from training data.
- **Tools** — schema-aware operations that build real artifacts correctly (schema-aware HL7 test messages, `Validation=""` on HL7 routers, correct Host vs Adapter settings placement).
- **Catalogs** — instance-specific descriptions of the components actually present in *this* customer's environment, so every choice is grounded rather than hallucinated.

The harness is what turns a generic LLM into a senior integration engineer. **That is the product.**

### 1.4 Goal: accelerate build time, not execution time

The goal is to **compress the time and expertise needed to stand up a working healthcare interface.** Work that today means navigating dozens of screens and hand-writing ObjectScript becomes a guided conversation ending in a tested, source-controlled interface.

**No agentic workflow is expected at execution time.** The agent reasons, plans and acts only while an engineer is building. There is no autonomous agent processing live messages and no agent-in-the-loop at runtime. The reasoning loop is a **build-time** loop; runtime message processing is ordinary IRIS interoperability.

### 1.5 Purpose-built agent vs generic developer experience — complementary

There are two ways to put an LLM to work against the platform. They are complementary, and AIB is deliberately the first:

**A. Purpose-built agent (this product).** A curated agent that **inherits the security, governance, context and graphical tooling of Health Connect Cloud out of the box.** Because it runs *inside* the platform as a `%AI` agent, it automatically gets the signed-in user's identity and permissions, Foundation-namespace protection, the secured credential store, the audit trail, the CI/CD hooks, and deep links back into the platform's own editors. The engineer never leaves the governed environment.

**B. Generic LLM experience via external MCP.** A customer points their own general-purpose agent at the platform by **exposing capabilities as MCP servers, or importing external MCP servers.** Flexible and general; trades the built-in guardrails and portal integration for openness.

These are **not antagonistic.** Customers will want both. **The generic LLM / external-MCP experience ships with AI Hub itself**, not with this product. AIB is the flagship purpose-built agent that ships *on* AI Hub.

### 1.6 MVP shape — three parts, in this order

| # | Part | Audience | Priority |
|---|---|---|---|
| 1 | **The Agent** — tools, skills, catalogs, policies, LLM connection | — | MVP. Most important. Build first. |
| 2 | **The Chat Experience** — where the engineer works with the agent | Customer facing | MVP. Build second. |
| 3 | **The AI Setting Experience** — where the agent is assembled | Internal to InterSystems | MVP. Build third. Not shown to customers in MVP. |

More agents come later. They are not in the MVP.

### 1.7 Driving use case — Epic to Quest

> Epic sends HL7 v2 ADT over a TCP port, and FHIR over a web endpoint. Quest must receive HL7 over a TCP port, and FHIR at a secured FHIR server URL. A business process transforms Epic's data into the format Quest requires.

This single use case drives which tools and skills we must build. If AIB cannot do Epic to Quest end to end, the MVP is not done.

### 1.8 Two hard requirements that apply everywhere

- **Inherit the security context.** The agent runs inside the calling namespace as the signed-in user, and respects both before its own capabilities. A namespace that does not allow FHIR blocks FHIR even if the agent can do FHIR. A user who cannot set up OAuth blocks OAuth even if the tool exists. **Capability never overrides permission.**
- **Integrate with the pipeline.** Every artifact the agent builds enters the CI/CD and change-control pipeline Health Connect Cloud already uses. **The agent never writes around it.**

### 1.9 Out of scope (MVP)

- **Creating or administering a FHIR server** — that is the FHIR Assistant, a separate product. AIB *connects to* FHIR servers; it does not provision them.
- Autonomous or runtime agentic workflows.
- Additional agents beyond AIB.
- Multi-tenant SaaS deployment; external or public-facing chatbot.
- Replacing the platform's graphical tools — AIB **complements and deep-links into** them.

---

## 2. Personas

The MVP has **two active roles**. Two further roles are recognised by the design but are not MVP-facing.

### 2.1 Integration Engineer — the primary persona (non-developer)

| Attribute | Detail |
|---|---|
| Who they are | A healthcare integration specialist. Deep expertise in HL7, FHIR and clinical data flows. **Limited or no InterSystems platform knowledge, and does not write code.** |
| What they want | To stand up and modify working interfaces without learning the class library, the DTL editor's quirks, or the settings model. |
| Where they work | The **chat**, plus the platform's graphical tools. Never source code. |
| What they produce | New and modified productions, DTLs, BPLs, routing rules and lookup tables. |

They think in terms of *"route ADT admissions to Quest and strip the dashes from the SSN"*, not *"instantiate `EnsLib.HL7.Service.TCPService` and set `MessageSchemaCategory`."* The harness translates the former into the latter, safely and transparently.

### 2.2 AI Admin — assembles the agent (InterSystems-internal for MVP)

| Attribute | Detail |
|---|---|
| Role | Connects the LLM, builds and refreshes the catalogs, authors skills, selects the agent's tools and skills, tunes its instructions, reviews the audit trail. |
| Who holds it | **For MVP this is an InterSystems person, not the customer.** The AI Setting Experience is not exposed to customers in the MVP. |
| Interface | The AI Setting Experience (§11). No code required. |

### 2.3 Recognised but not MVP-facing

- **Operator** — run-time monitoring and triage, read-mostly, no structural change. Covered by UC-2/UC-3 and enforced by role-scoped tool binding, but not a separately configured MVP persona.
- **Developer** — authors tool and skill classes in an IDE and ships them via IPM. Supplies the building blocks the AI Admin assembles.

---

## 3. Use Cases

### 3.1 UC-1 — Build end-to-end interfaces for any healthcare message type (Integration Engineer)

Stand up a complete, tested interface from a plain-English request or an uploaded specification, across HL7 v2 (ADT, ORU, ORM, SIU, MDM, DFT, VXU…), FHIR R4, SDA3, CDA/C-CDA and X12/HIPAA.

1. **Describe or attach.** Type the requirement, upload a specification, or complete the Integration Spec Questionnaire (§5.2).
2. **Prompt refinement.** The agent identifies what was *not* said — HL7 version, transport and port, field mappings, error handling, ACK targets — and either asks, or proposes a recommended default for confirmation.
3. **Research.** Catalog search for the right business hosts and transformation classes; exact HL7 schema paths; relevant skills. All read-only.
4. **Plan and approval gate.** Every component, its class and why, key settings, data flow, every field mapping, the test message. Then it stops.
5. **Build.** In strict dependency order, with every setting configured and every directory created.
6. **Test and validate.** Schema-aware test message through the pipeline, then post-build validation. Failures are fixed and re-validated.
7. **Report with links.** Every artifact named, with **deep links into the matching graphical editor** (§5.4), plus the actual test message, output and per-field verification.
8. **Catalog update.** New artifacts are indexed so the next engineer can discover and reuse them.

### 3.2 UC-2 — Troubleshoot interfaces (Operator work; escalation to Integration Engineer)

Read-only investigation: error triage grouped by business host, health assessment (queue depth, throughput, bottlenecks), and operational tuning (pool size, throttle, retry) through the approval gate. Structural fixes escalate to an Integration Engineer.

### 3.3 UC-3 — Get insights on how to improve an interface

Recommendations grounded in the catalogs and skills, each citing the specific setting, its current value, the recommended value and the expected impact — for example `StayConnected=0` reopening the socket per message on a high-volume feed. Includes DTL review (hardcoded values that should be lookup tables, missing null checks, mishandled repeating fields) and modernization (adopt the HL7→SDA→FHIR pipeline instead of point-to-point transforms).

### 3.4 UC-4 — Specification-driven build

The work begins from a **document** or a **structured questionnaire** rather than a typed prompt (§5.2). The agent synthesises a specification, presents it for approval, and only then enters the plan → approve → build loop — so the build traces back to an explicitly approved reading of the source.

---

## 4. How the Agent Behaves

### 4.1 The persona

The agent embodies a senior system integrator and healthcare interoperability architect. Core philosophy: **research first, build second**; **optimize for out-of-the-box** (prefer built-in hosts, DTLs and routing patterns over custom code); **plan thoroughly and ask smart questions** about what the user has *not* said; **be detailed and transparent** — and **never claim success without a tool result confirming it.**

### 4.2 The safe loop

```
(INGEST) → RESEARCH → GAP CHECK → PROPOSE → [APPROVAL GATE] → BUILD → TEST → REPORT → CATALOG UPDATE
```

| Step | What the agent does |
|---|---|
| Ingest | Only when a document or questionnaire arrives: synthesise a specification, present it, and **stop** until approved. No tool calls. |
| Research | Confirm namespace; search the catalogs; pull exact schema maps; consult skills. Read-only, batched. |
| Gap check | **Ask or recommend, never silently default.** Missing detail with no safe default → ask. A required sub-decision the user omitted → recommend in the plan, with rationale, flagged for confirmation. |
| Propose | Components with chosen classes and why, data flow, **every** field mapping, test-message spec, recommended defaults. |
| Approval gate | Stop and wait. **The agent builds nothing without approval.** |
| Build | Silent, in dependency order. Settings before start; directories before start; production running before test. |
| Test | Schema-aware test message, then post-build validation. Failures fixed and re-run once. |
| Report | Validation verdict first, every artifact named and linked, actual message and output, per-field verification, next steps. |

**Gap-check items the agent must never silently default** (these are also the questionnaire's schema, §5.2): ACK mode and ACK target for file/FTP services; dead-letter / bad-message destination; retry interval and failure timeout (healthcare default `FailureTimeout=-1`); pool size when FIFO matters; `MessageSchemaCategory` on the inbound service; archive path for file pickups; segment terminator on HL7-to-HL7 DTL targets. Plus the never-assume list: transport, HL7 version, `MessageSchemaCategory`.

### 4.3 Policies enforced on every action

| Policy | What it means |
|---|---|
| **Approval** | The agent pauses before any change. Nothing is applied without explicit approval. |
| **Acting as the user** | The agent acts within the signed-in user's permissions. It can never do what the user could not do by hand. |
| **Tool and knowledge visibility** | Only the tools and knowledge the AI Admin enabled. An excluded tool cannot be used even if a user asks. |
| **Respect the context** | Inherits the security of the calling namespace and user, before its own capabilities. Capability never overrides permission. |
| **Foundation-namespace lock** | Foundation namespaces are always read-only. The approval gate cannot override this. |
| **Integrate with CI/CD** | Every artifact enters the existing pipeline. The agent never writes around it or skips a required review. |
| **Anti-fabrication** | No claim of success without a tool result. |
| **Turn budget** | A deadline and token budget per turn; on breach, a graceful stop with partial results. |

---

## 5. Chat Experience

### 5.1 Core chat

Streaming responses (visible output within a couple of seconds, never a blank screen); each action rendered as an expandable card showing what it did, with what inputs, and the result; inline Approve/Reject on every mutating call; errors explained in plain language with no technical traces.

### 5.2 Starting from a specification — documents and the questionnaire

Engineers rarely start from a blank prompt. They start from a **specification**. Two supported entry points, both of which end in an approved specification before any build:

**Upload.** Attach the organization's specification documents — **TXT, DOCX, XLSX, MD** and PDF. The agent extracts the text, synthesises a structured specification, and presents it for approval with Approve and Edit. It calls no action tool on that turn.
*Current build state: PDF, XLSX, TXT and MD are supported; **DOCX is an MVP requirement of this document** and is presently a follow-on.*

**The InterSystems Integration Spec Questionnaire.** A schema-driven form that collects everything the platform needs, then emits the specification directly. Its questions *are* the agent's gap-check list (§4.2) externalised — answered up front rather than discovered mid-conversation. Options are grounded in the environment and catalogs so the engineer can only specify things that exist. Two exits: **Output Trial** (review and edit the generated specification) and **Send it to AIB** (hand it straight to the chat for that namespace). Output is prose, JSON, or both — JSON is authoritative and keyed to real tool parameters; the prose renders the approval card. Customers can add, remove and relabel fields, because the form is data.

### 5.3 Memory

Full context within a conversation; the approved specification stays in history and is the authoritative source of what to build; conversations can be left and resumed; catalogs grow with every successful build so the agent remembers what this instance already has.

### 5.4 Links to artifacts, and round-tripping with the graphical tools

**This behaviour defines the product for a non-developer.** The engineer builds with the agent, keeps working in the graphical tools, and returns to the agent when useful. There is no code at any point.

- **One action opens the exact artifact** in the matching editor — data transformations, business process logic, routing rules, production configuration, lookup tables, security configuration, host settings. Not a generic landing page.
- **Every artifact opens, because the agent builds ObjectScript-based artifacts.**
- **Edits made in a graphical tool are respected.** Ask the agent afterwards and it works from the current version, never a stale copy.
- **Runtime inspection** links out to the visual message trace, the event log and message search for the interface just built.

### 5.5 Testing and validating from the chat

The agent generates and sends representative HL7 and FHIR messages, reports whether each reached its destination, validates structure and meaning of the outbound result, and compares input to output — flagging fields the destination expects that are missing or wrong.

### 5.6 Managing conversations

History with search, resume and rename; a clear control to start a new conversation; a clear indicator of whether the agent is available; guided starter prompts on a new conversation, at least one showing a source-to-destination build like Epic to Quest.

### 5.7 Behaviour is configuration

Instructions, temperature, iteration limits and bound skills/tools are configuration, not code — edited in the AI Setting Experience, stored as overrides that survive product updates, with reset-to-default.

### 5.8 Style

No emojis or icons in the data UI; status as a colored dot plus label. Technical identifiers in backticks. No markdown bold in chat responses.

---

## 6. Tools, Skills and Catalogs

### 6.1 Tools to build

Driven by the Epic-to-Quest use case. Every artifact is **ObjectScript-based** so it opens in the graphical tools.

| Tool group | What the agent can do |
|---|---|
| Productions and interfaces | Create, edit, update, set up, start, stop, validate |
| Business hosts | Create, edit, update, set up inbound services and outbound operations |
| HL7 over TCP | Set up inbound and outbound HL7 v2 over a TCP port |
| FHIR connections | Inbound FHIR at a web endpoint; outbound FHIR to a secured external server |
| DTL transformations | Create, edit, update, compile, dry-run |
| BPL business processes | Create, edit, update — and **populate**, never leave an empty skeleton |
| Routing rules | Create, edit, update |
| Lookup and code tables | Create, edit, update |
| OAuth security | Set up OAuth 2.0 for a secured connection |
| File folders | Create the folders an interface reads from or writes to |
| Test messages | Build and send HL7/FHIR test messages, validate, compare input to output |
| Monitoring and trace | Event log, message status, queues, throughput, visual trace |
| Catalog search | Find the right building block or pattern |
| System default settings | Promote environment-specific settings dev → test → live |

Tools must understand these artifacts as a **connected system** — a routing rule references a DTL by class name, a DTL references lookup tables, a BPL calls sub-DTLs and routes to hosts — and enforce those dependencies during a build.

**Not in the MVP:** creating or administering a FHIR server.

### 6.2 Skills to build

**Build skills (best practice):** Productions · Business hosts · DTL · BPL · Routing rules · OAuth · Connections and adapters.

**Healthcare standards:** HL7 v2 (core) · FHIR (core) · SDA (supporting — the clinical model bridging HL7 v2 and FHIR) · CDA (later) · X12 (later).

**Customer knowledge — customers must be able to author their own skills.** This is a first-class requirement. The critical case is the **organization's interface template**: site conventions, naming standards, Z-segment definitions, house DTL patterns, and how to read the customer's own specification documents. A customer-authored skill teaches the agent to interpret those the way the customer's senior engineer would (US-B09). Skills are authored in plain language, with no code.

### 6.3 Catalogs to build

| Catalog | What it holds | Why |
|---|---|---|
| Interface building blocks | Services, operations and adapters available on the platform | Find the right inbound/outbound component |
| Transformation patterns | Known transformation mappings and patterns | Reuse proven mappings instead of guessing |

Built by walking the class dictionary — the source of truth — embedding curated prose, and stored as vector indexes. The AI Admin builds, refreshes, quality-checks and binds them (US-B10). Catalogs **auto-grow**: artifacts created during a successful build are indexed for reuse.

---

## 7. Security

Defense in depth — four independent layers, and a mutation must pass all four:

| Layer | Enforced by | Checks |
|---|---|---|
| 1. Tool availability | AI Admin (tool/skill binding per agent) | Is this tool bound to this agent at all? Prevents prompt injection escalating a session. |
| 2. Namespace validation | Tool implementation | Non-Foundation namespace, and does the user have access to it? |
| 3. Permission delegation | Tool implementation | Does the **signed-in user** hold the required privilege? |
| 4. User approval | Approval policy | Did the user approve this specific change? |

Requirements:

- **Namespaces.** Namespace-agnostic; resolved at request time and displayed in the UI. **Foundation namespaces are always read-only** — a hard constraint the approval gate cannot override. Cross-namespace access is validated against the user's rights.
- **The agent acts as the user, never as itself.** Every tool executes in the signed-in user's security context. Lacking permission returns a structured error naming the missing privilege, explained in plain language and recorded in the audit trail.
- **Artifacts marked as created by the agent.** Agent-created or modified artifacts must carry that provenance — attribution to the signed-in user *and* a marker that the agent produced it — so reviewers and the pipeline can see what the agent touched. *(User attribution exists today via source-control hooks; the explicit marker is a requirement to formalize.)*
- **Authentication.** All endpoints authenticated. **No UI element is visible before login.**
- **Secrets.** Credentials live only in the encrypted secret store — never in tables, globals, source, logs or any API response, not even masked. Connection *test results* are logged for debugging.
- **Audit.** Every request and every tool call recorded: who, when, which environment, what action, inputs, result, duration, errors. Filterable to errors only. Denied attempts are audited too.
- **No bypass on writes.** All class changes go through documented APIs so source-control hooks fire. The agent never writes globals or internal structures directly, and respects source-control locks.

---

## 8. CI/CD Integration

Agent-created artifacts are **not a special case** — they are ordinary class changes and must flow through the same change control as any manual edit: version control, review, validation and staged promotion.

**This must be configurable**: the customer defines how the agent interacts with their CI/CD — provider, repository and branch, commit and attribution behaviour, and what triggers the pipeline.

**For Health Connect Cloud it is defined out of the box.** The platform's source-control hooks intercept class save and compile, export definitions, attribute changes to the signed-in user, and feed the pipeline. Because the agent uses standard APIs, the hooks fire with no agent-specific configuration. Requirements:

- **Artifact capture** on every create and compile.
- **User attribution** to the Integration Engineer, plus the created-by-agent marker (§7).
- **Status reporting** — after a build the agent reports whether source control captured the classes, and warns when it is not configured.
- **Lock respect** — the agent will not modify a class another user has locked.
- **Configurable elsewhere** — on non-HCC deployments the binding is a documented customer configuration.

---

## 9. Distribution and Deployment

> **This section defines a product need and flags an open engineering problem. The distribution mechanism, kit-building procedure, and the security review it entails are NOT in place today and must be specified by Development before MVP.**

### 9.1 The product need: an independently updatable agent

AIB must be **updatable as independently as possible from the Health Connect Cloud upgrade cycle.** The agent, its skills, tools, catalogs, policies and prompts should move on their own release train rather than being frozen to whatever shipped with the customer's current platform version. Three reasons:

- **Adapt to AI scenarios faster.** The AI landscape moves far faster than a healthcare platform release cadence.
- **Deliver new capabilities as AI Hub improves**, without waiting for the next platform upgrade to carry them.
- **Fix issues faster.** A defect fix must not require the customer to take a full platform upgrade.

### 9.2 Independent release train (the default)

A self-contained, versioned kit delivered through a release channel InterSystems controls, so installing or updating AIB is a discrete, low-risk operation:

- **Versioned, semantic releases** with release notes and a dependency floor.
- **In-place update that preserves configuration** — customer overrides (instructions, bound tools and skills, connections, catalogs) survive; shipped defaults refresh. No re-configuration after an update.
- **Idempotent install / upgrade / rollback**, all defined and tested, including catalog and override behaviour on downgrade.
- **Compatibility matrix** — each release declares its supported AI Hub / platform range and refuses to install outside it rather than half-installing.

### 9.3 Coupling policy

**A platform upgrade MAY be tied to a specific AIB version** — but only with a **strong, documented justification**, canonically a hard platform dependency (an AI Hub feature or API that only exists in that version). Any coupling is a deliberate, written decision, never a default.

### 9.4 No ad-hoc distribution — ever

**Ad-hoc deliveries must be avoided at all cost.** No one-off patches, hand-built kits, hotfix archives, or out-of-band class imports. Everything reaches a customer through the defined, versioned channel. Ad-hocs are unauditable, unreproducible, un-rollback-able and incompatible with the security posture below. Urgent fixes ship as expedited *normal* releases.

### 9.5 Security and kit-building implications (Dev to specify)

An independently updatable component that installs executable classes into a governed clinical platform **raises concerns we have no procedure for today**:

- **Kit-building procedure** — a repeatable build → test → package → publish pipeline with artifact provenance. Does not exist yet; prerequisite.
- **Integrity and authenticity** — how kits are signed and verified.
- **Change control and review** — the update path must not become a way to bypass platform governance. Because AIB installs tools the agent can execute, the update channel is itself a sensitive surface.
- **Trust boundary vs the platform** — what AIB may change on update and what it must never touch, agreed explicitly with the platform team.
- **Supply chain** — dependency pinning, scanning and disclosure per release.
- **Auditability of updates** — every install, upgrade and rollback recorded.

### 9.6 Ownership

| Item | Status | Owner |
|---|---|---|
| Kit-building / release pipeline | **Not in place — to be specified** | Development |
| Kit signing, integrity, provenance | **Not in place — to be specified** | Development + Security |
| Compatibility matrix | To define | Development + AI Hub team |
| Independent channel + preserve-config upgrade | To design | Development |
| Security review of an out-of-band updatable component | **Required before MVP go-live** | Development + Security + platform team |
| Coupling-justification process | To define | Product + Development |

---

## 10. LLM Connection

Conceptually **part of the AI Hub experience**, but **delivered as part of AIB's MVP**, because **customers bring their own LLM** and the agent is inert without a configured provider. It cannot wait on the broader AI Hub admin surface.

- **Bring-your-own-LLM.** The AI Admin chooses provider and model in a form. No environment variables, config files or code.
- **Data control.** The organization chooses the provider and therefore where its data is processed.
- **Secure storage.** The credential is masked on entry, stored encrypted, and never shown, returned, exported or logged afterwards.
- **Health status.** A test shows available / unavailable / not yet tested, with the provider's exact error text on failure. **The chat surfaces this status to end users** — if the model is down, engineers are told plainly.
- **Runtime LLM ≠ development LLM.** The chat uses whatever the AI Admin configured; any development-time assistant is a separate connection.

---

## 11. AI Setting Experience and the AI Hub Admin Experience

### 11.1 The AI Setting Experience (Epic 3, MVP)

Where the AI Admin assembles the agent. **Built and operated by InterSystems; not shown to customers in the MVP.** It does not need to be fully featured or customer-grade for MVP; a later release can open it to customers.

Covers: connecting the LLM and storing the credential (US-B01–B03); selecting tools and skills per agent and grouping them into toggleable areas (US-B04, US-B06); tuning instructions with save and revert that survive updates (US-B05); authoring skills from plain-language documents, registering supplied skills, and authoring the organization template skill (US-B07–B09); providing, refreshing, quality-testing and binding catalogs (US-B10); reviewing the audit trail and safely trying a tool before exposing it (US-B11–B12).

### 11.2 Relationship to the shared AI Hub Admin Experience

The broader **AI Hub Admin Experience** — the shared platform surface for managing agents, MCPs, tools, skills, connections, catalogs and policies across *all* AI Hub agents — is **being built by Benjamin de Boe and Hemil.** Two boundaries:

- **Not a release gate.** AIB does **not** require the shared surface to ship. It carries its own AI Setting Experience for MVP, and owns LLM-connection management (§10).
- **Alignment required.** As the shared surface matures, AIB's admin surfaces should **converge onto it rather than diverge** — same primitives, same override model, same audit. The team must stay aligned on data model and UX so the purpose-built builder and the generic AI Hub admin are one coherent platform.

---

## 12. Non-Functional and Non-Technical Requirements

| Requirement | Target |
|---|---|
| Responsiveness | Visible output starts within a couple of seconds; the agent stays responsive throughout a task |
| Reliability | Never fails silently; every error explained in plain language |
| Security — acting as the user | Acts within the signed-in user's permissions; can never exceed what they could do by hand |
| Security — change gate | Every change requires explicit approval before it is applied |
| Security — secrets | Credentials stored encrypted; never shown, exported or logged |
| Security — inherit the context | Cannot exceed what the calling namespace allows or the user is permitted; refuses in plain language |
| Auditability | Every action taken for a user is recorded and reviewable |
| Data control | The organization chooses the AI provider and therefore where its data is processed |
| Usability | A non-developer can use the product; no source code in the engineer's workflow |
| Platform constraints | Uses only what Health Connect Cloud provides. **No command line. No file server access. No local developer tools.** |
| Artifact form | ObjectScript-based artifacts, each opening in a graphical tool. Python-based artifacts are not used where a graphical view is needed |
| Change control and CI/CD | Every artifact enters the existing pipeline, versioned, tracked, attributed to the signed-in user, promoted normally |
| Distribution | Updatable independently of the platform upgrade cycle; no ad-hoc delivery (§9) |

**Non-technical requirements**

- **Positioning.** Consistently framed as a build-time accelerator (not a runtime component), an AI Agent Hub on the AI Hub foundation whose value is the Healthcare AI Harness, and the purpose-built counterpart to the generic external-MCP experience — complementary, not competing. Never implies autonomous runtime agents processing patient data.
- **Trust and expectation-setting.** Human approval on every change, the agent acts as the user, honest failure reporting, no claim of success without verification.
- **Compliance posture.** No PHI is required for the product to function; it operates on class definitions and configuration, and any build-validation test data is synthetic.
- **Documentation and enablement.** Getting started, skill authoring (including the organization template skill), catalog build, LLM provider setup, and an operations runbook.
- **Internal style.** No emojis or icons in the data UI; colored dot plus label for status; InterSystems acronyms expanded on first use.
- **Packaging.** Installs into a clean supported environment with no machine-specific paths; namespace-agnostic.
- **Success criteria.** Adoption by engineers who are *not* platform experts; measurable reduction in time-to-first-working-interface; engineers keep agent-built artifacts; zero security incidents attributable to the agent bypassing user permissions.

---

## 13. Known Constraints and Framework Notes

Application-level workarounds; framework classes remain unmodified.

- **Skill instantiation** — the framework's skill constructor mis-marshals its argument to the LLM bridge; all skills extend an application base class that overrides it.
- **Provider round-trip** — the Bedrock tool-result round-trip hangs below the ObjectScript surface, and is prone to token-per-minute throttling on large multi-host builds. Anthropic-direct is the reliable reference provider. Mitigate throttling by trimming each agent's tool catalog.
- **Turn limits** — a deadline and token budget per turn; complex builds are split into several short, visible-progress turns.
- **Language and REST gotchas** — documented in `docs/BUG.md` and `docs/03_Lessons_Learned.md`. Engineering notes, not product requirements, but they bound estimates.

---

## 14. End-to-End Walkthrough

**AI Admin — one-time setup in the AI Setting Experience (internal).**
1. Connects the chosen AI model, stores the credential securely, tests until available.
2. Provides and refreshes the catalogs; confirms relevance with a test search.
3. Authors the organization-specific template skill and attaches it to the engineers' agent.
4. Assembles the agent: selects tools and skills, tunes instructions, binds catalogs.

**Integration Engineer — the daily work in the chat (customer facing).**
5. Opens the chat. Attaches the Epic-to-Quest specification, or completes the Integration Spec Questionnaire.
6. The agent reads it through the template skill and shows a structured summary. The engineer edits one line and confirms.
7. The engineer says "build it". The agent proposes a plan — the two inbound legs, the business process and transformations, the two outbound legs — and asks for approval.
8. The engineer approves. The agent builds, validating as it goes, keeping full context.
9. The engineer opens the new transformation in the graphical editor, adjusts one mapping, saves, and asks the agent to re-validate. The agent works from the current version.
10. The agent sends a test HL7 message and a test FHIR resource, validates them against Quest's requirements, compares input to output, and links to the visual trace.
11. Everything passes. The engineer starts the interface.

**AI Admin — oversight.**
12. Reviews the audit trail: every action, by this engineer, in this environment.

---

## 15. Definition of Done (MVP)

The MVP is done when all of these are true on Health Connect Cloud.

1. The agent follows the safe loop: research, propose, wait for approval, build, test, report.
2. An Integration Engineer supplies the Epic-to-Quest specification — by upload or questionnaire — and the agent reads it through the organization template skill and shows a correct summary.
3. From the chat, the agent builds the full interface: both inbound legs, the business process and transformations to Quest's format, and both outbound legs including the secured external FHIR. The engineer approves every change.
4. The engineer opens any result in the matching graphical editor with one action and edits it with no code. The agent then works from those edits.
5. The agent sends test HL7 and FHIR messages, validates them, and the engineer confirms flow in the visual trace and the event log.
6. Every artifact is ObjectScript-based and opens in its graphical editor.
7. The agent respects the calling namespace and the signed-in user, never exceeding what they allow even when it has the capability.
8. Every artifact enters the CI/CD and change-control pipeline, attributed to the signed-in user. Nothing is written around the pipeline.
9. The agent is connected to the chosen AI model, the credential is secured, and status shows available.
10. An InterSystems AI Admin can assemble the agent in the AI Setting Experience: connect the LLM, build the catalogs, pick tools and skills, set policies, write the prompt.
11. Every action is recorded in the audit trail.
12. The solution uses only what Health Connect Cloud provides. No CLI. No file server access. No developer tools.

> **Scope reminder.** The Agent and the Chat Experience are customer facing. The AI Setting Experience is built and operated by InterSystems and is not shown to customers in the MVP. More agents come later.

---

## Appendix A — User Stories

### A.1 The Agent

**US-1.01: The agent works in a safe loop.** *As an Integration Engineer, I need the agent to research, propose, wait for my approval, build, test, and then report, because I must see and approve the plan before anything changes, and I need proof at the end.*
- The agent never changes anything before I approve the plan.
- The agent tests what it built and reports the result.
- If a step fails, the agent stops and tells me plainly.

### A.2 Chat Experience (customer facing)

**US-A01: Build an interface by describing it.** *…because I am not a developer, and I should not have to assemble an interface screen by screen.*
- I state the goal in business terms and get back a clear, ordered plan.
- The agent recommends the right inbound and outbound components before it builds anything.
- It shows the plan and waits for approval; after approval it builds and reports in plain language.

**US-A02: Approve or reject every change.** *…because I am accountable for what gets created in my environment.*
- Every change pauses for approval — create, modify, start, stop. Nothing is applied until I approve. If I reject, the agent asks how to proceed.

**US-A03: See what the agent is doing.** *…because I need to trust and follow its work, not watch a spinner.*
- Output appears as produced; each action shows inputs and result, expandable; errors in plain language, no traces.

**US-A04: Remember the conversation.** *…because building an interface is step by step.*
- Full context within a conversation; "now add the outbound side" resolves correctly; I can leave and come back.

**US-A05: Stay responsive, never hang.** *…because a frozen build is worse than a slow one.*
- Long tasks split into short steps with visible progress; on a long step it summarizes and offers to continue or retry.

**US-A06: Upload our interface specification.** *…because retyping a multi-page specification into a chat box is slow and error prone.*
- I attach common document and spreadsheet files, listed and removable.
- The agent produces a structured summary of what it understood, and builds nothing until I confirm. I can edit it and it revises.

**US-A07: Have the agent understand our template.** *…because a generic reading will misread our conventions.*
- With the AI Admin's organization skill attached, the summary reflects our template's real meaning. This is the hand-off between the two roles.

**US-A08: Refine by prompting.** *…because for most changes, talking is faster than hand editing.*
- The agent finds the artifact, proposes the change, applies it after approval, and re-checks.

**US-A09: Open any result in the graphical editors.** *…because for detailed work I prefer the visual tools, and I must never read or edit source code.*
- One action opens the exact artifact in the right editor, for every artifact type. No source code, ever.

**US-A10: Edit in a graphical tool, then keep talking to the agent.** *…because the agent must never use an old copy.*
- After a visual edit the agent reflects current changes and can summarize, validate or keep building on them.

**US-A11: Inspect runtime behavior through the existing tools.** *…because checking real message flow is a visual task.*
- Links to visual trace, event log and message search; can also answer "did my message arrive" and then offer the link.

**US-A12: Send a test message.** *…because I must prove the path works before going live.*
- Generates and sends representative HL7 and FHIR messages, reporting arrival and surfacing errors.

**US-A13: Validate the output against the destination's specification.** *…because the destination rejects anything that does not match.*
- Validates structure and meaning; compares inbound to outbound; flags missing or wrong expected fields.

**US-A14: Keep, search, resume and label conversations.** *…because building an interface spans sessions.*
- History view with search, resume, rename; a clear new-conversation control; an availability indicator.

**US-A15: Start from a guided prompt.** *…because a blank box is intimidating.*
- Example prompts on a new conversation, filling the composer; at least one source-to-destination build like Epic to Quest.

### A.3 AI Setting Experience (InterSystems internal)

**US-B01: Connect to the chosen AI provider.** Provider and model chosen in a form and saved as configuration; the organization controls where its data goes.
**US-B02: Store credentials securely.** Masked on entry, stored encrypted, never shown, returned or logged afterwards.
**US-B03: Test the connection and see its status.** Available / unavailable / not yet tested; provider's exact error on failure; status surfaced to end users in the chat.
**US-B04: Choose which tools and skills the agent has.** Include or exclude each per agent; excluded tools cannot be used even on request; effective for new conversations with no redeployment.
**US-B05: Tune the agent's instructions.** Edit instructions, persona, planning rules and guardrails; save and revert; changes persist across product updates.
**US-B06: Group tools and toggle whole areas.** Enable or disable each tool area with a description.
**US-B07: Author a skill from a document.** Name, description and plain-language content, pasted or uploaded; attachable to any agent; no coding.
**US-B08: Register a supplied skill.** Self-authored and supplied skills in one pool, attached the same way.
**US-B09: Teach the agent our interface template.** Author a plain-language skill describing our template's structure and conventions, attach it, and uploaded templates are then read our way. *The worked example of a skill customers build for themselves.*
**US-B10: Provide and refresh the catalogs.** Size and last update visible; refresh on demand; test search before exposing; bind catalogs to agents.
**US-B11: Review the audit trail.** Who, when, which environment, what action, result; filter to errors only; captures successes and denials.
**US-B12: Verify a tool before exposing it.** Browse each tool with description and inputs; safely try a non-destructive tool with sample input.

### A.4 Change control

**US-SC01: Agent-created artifacts appear in source control**, using standard APIs so hooks fire, attributed to the signed-in user.
**US-SC02: The agent reports source-control status** after a build, and warns when it is not configured.
**US-SC03: The agent respects source-control locks** and will not modify a class locked by another user.

---

## Appendix B — Sources and Supersedes

Consolidated from `docs/01_Requirements_User_Stories.md`, `docs/02_Technical_Build_Specification.md`, `docs/03_Lessons_Learned.md`, `docs/system_integrator_persona.md`, `docs/AttachmentWorkflow.md`, `docs/UseCase-SpecDrivenBuild.md`, `docs/PLAN.md`, the live agent instructions, and the InterSystems product documentation (notably *Best Practices for Creating Productions*, *Configuring Productions*, *Routing HL7 Version 2 Messages in Productions*, and *HL7 Productivity Tools*).

**Supersedes:** `docs/PRD.md` (Agentic Interoperability Builder) and the standalone `PRD_Agentic_Integration_Builder` draft.
**Sibling product:** `docs/Product_Requirements_FHIR_Assistant.md` — out of scope here.
