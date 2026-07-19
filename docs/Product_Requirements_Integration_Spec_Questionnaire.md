# Integration Specification Questionnaire — Product and Technical Requirements

> **Audience:** the engineer who will build this. Written to be implementable without reference to any existing codebase.
> **Product:** a guided specification capture tool for healthcare integration work.
> **Context:** a component of an AI-assisted integration builder. It runs *before* the build agent, not instead of it.
> **Status:** requirements for build · Version 1.0 · July 2026

---

## 1. Why this matters

### 1.1 The business driver

Interface projects do not usually fail because the platform cannot do the work. They fail, slip, or rework because **nobody wrote down what "done" means** in enough detail before building started.

An integration engineer receives a Statement of Work, a business requirements document, or a field-mapping spreadsheet. These are written for humans. They describe intent — *"send admissions to the lab system"* — and omit the decisions the integration platform actually requires: which acknowledgment mode, where acknowledgments go when the inbound feed is file-based, what happens to a message that fails to transform, whether message ordering matters, which schema version the inbound service declares.

That gap has always been filled informally, by an experienced engineer asking the right questions. It scales badly, it depends entirely on who is assigned, and it is invisible until something breaks.

**Introducing an AI build agent makes the gap worse, not better.** The agent removes the build bottleneck, which moves the constraint upstream to specification quality. An agent can only build what it has been told, and it will either ask (costing turns and time) or assume (costing a defect).

### 1.2 The cost of an incomplete specification

| Outcome | Cost |
|---|---|
| **Clarification loop** | Each round trip costs time and, with an AI agent, tokens and latency. It also lets the conversation drift from the original intent. |
| **Silent wrong assumption** | Far worse. The build succeeds, the demo passes, and the defect surfaces in production. |
| Complete specification | Rare today, and dependent on the individual engineer's platform experience rather than on process. |

The second outcome is what justifies this product. The characteristic failure is an interface that **looks like it works**:

- Acknowledgments configured on an inbound feed that has no return channel — the platform logs a warning, and the acknowledgment goes nowhere
- A routing rule that never matches, because the inbound service was never told which message schema it is receiving
- A transformation that emits only its first segment, because the output was created without a segment terminator

None of these fail loudly. Every one is the direct consequence of a decision nobody was asked to make.

### 1.3 Business outcomes to be measured

| Outcome | Mechanism | Measure |
|---|---|---|
| Fewer clarification cycles before build | Required decisions are captured before the agent is engaged | Turns from request to agreed build plan |
| Fewer production defects from unstated assumptions | Every known-critical decision is either answered or explicitly raised | Defects traced to unspecified configuration |
| Specification quality independent of individual experience | The tool asks what an expert would ask | Completeness variance across engineers |
| Non-specialists can produce a usable specification | Guided, grounded, defaulted | Specifications completed without platform expertise |
| Specifications become reusable assets | Captured, searchable, reloadable | Reuse across environments and projects |

### 1.4 The insight this product depends on

**Do not invent the definition of a complete specification. Extract it from what the build process already requires.**

Any mature integration platform, and any competent build agent, already encodes the list of decisions that must not be guessed. That list — transport, message schema and version, acknowledgment handling, error and dead-letter destinations, retry and timeout behaviour, ordering guarantees, archival — *is* the specification schema.

The questionnaire is that list, asked **up front in a form**, rather than discovered mid-conversation. Anything the implementing team's platform documentation prescribes as best practice (intake templates, naming conventions, modularity rules) should be treated as source material, so the tool encodes documented practice rather than inventing a parallel one.

### 1.5 Where the need arises

The diagram below is the argument for building this. It is drawn in terms of
who is doing what and where the work goes wrong — no components, because at
this point in the reasoning none have been chosen.

```
  TODAY — the decisions are discovered late, by whoever happens to know

  Business asks         Engineer receives            Engineer builds
  for an interface      a human-readable spec        against the platform
       │                       │                            │
       │  "send admissions     │  intent is clear           │  platform demands
       │   to the lab"         │  decisions are absent      │  ~15 decisions
       ▼                       ▼                            ▼
  ┌──────────┐          ┌──────────────┐            ┌────────────────────┐
  │  intent  │─────────▶│  a document  │───────────▶│  ????              │
  └──────────┘          │  written for │            │  ack mode?         │
                        │  humans      │            │  where do acks go? │
                        └──────────────┘            │  failure path?     │
                                                    │  ordering?         │
                                                    │  schema version?   │
                                                    └─────────┬──────────┘
                                                              │
                                     ┌────────────────────────┴───────────┐
                                     ▼                                    ▼
                            experienced engineer              anyone else
                            asks the right questions          guesses, or is
                            (slow, unrepeatable,              never asked
                            depends who is assigned)          (silent defect)


  THE SHIFT — an agent removes the build effort, so the constraint moves upstream

           build effort ▼▼▼        specification quality ▲▲▲ now the bottleneck

           The agent will either ASK (costing turns, drifting from intent)
           or ASSUME (costing a defect that survives the demo).
           Neither is acceptable at scale. Both have the same cause:
           the decisions were never captured.


  WITH THIS PRODUCT — the same decisions, asked up front, by the tool

  Business asks         Engineer answers             Agent receives
  for an interface      a guided question set        a complete specification
       │                       │                            │
       │                       │  every decision the        │  nothing to guess,
       │                       │  build requires is         │  little to ask
       ▼                       ▼  asked or explicitly       ▼
  ┌──────────┐          ┌──────────────┐  deferred   ┌────────────────────┐
  │  intent  │─────────▶│  answered    │────────────▶│  buildable         │
  └──────────┘          │  decisions   │             │  specification     │
                        └──────────────┘             └────────────────────┘
                               ▲
                               │ options grounded in what this
                               │ environment actually offers
                        ┌──────┴───────┐
                        │  reference   │
                        │  data        │
                        └──────────────┘
```

The product's whole job is the middle box: turn intent into answered decisions
**before** anyone or anything starts building.

---

## 2. Product definition

### 2.1 What it is

A **specification capture tool**. It collects, validates and records everything needed to build a healthcare integration, and produces a specification artefact that a build agent — or a human engineer — can act on.

### 2.2 What it is not

| Not | Because |
|---|---|
| A build tool | It creates nothing in the target environment. Every change stays behind the build agent's approval gate. |
| A mapping tool | Complex field-level mapping belongs in a dedicated visual tool. This captures intent and hands off. |
| A replacement for document intake | It complements uploaded documents; the two should converge (§4.6). |
| A replacement for the build agent's own judgement | It removes guesswork, it does not remove planning. |

### 2.3 Actors

| Actor | Role |
|---|---|
| **Integration Engineer** (primary) | Domain expert in healthcare data; limited platform expertise; does not write code. Completes the questionnaire, verifies what was captured, hands it to the agent. |
| **Reviewer / Operator** | May produce or review a specification but not trigger a build. |
| **Administrator** | Maintains the reference data the questionnaire draws its options from; owns the question set if it is made configurable. |
| **Build agent** | Downstream consumer of the specification. Not a user. |

### 2.4 Needs the product must satisfy

Each need below belongs to an actor and earns its requirements. A capability
that traces to no need does not belong in this build.

```
  ACTOR NEED                        WHAT THE PRODUCT MUST DO           SO THAT
  ───────────────────────────────────────────────────────────────────────────────

  Integration Engineer
  ─────────────────────
  "I know the clinical intent   ──▶ Ask the platform's required    ──▶ Expertise
   but not what the platform        decisions in plain language        stops being
   needs to be told"                                                   the gate

  "I don't know which of these  ──▶ Offer only what this            ──▶ No invented
   options my site supports"        environment actually provides       or unavailable
                                                                        choices

  "Typing a form is slower      ──▶ Accept a free description and  ──▶ Speed without
   than describing it"              fill the form for review           losing rigour

  "I don't want to be blamed    ──▶ Show exactly what will be      ──▶ Trust in what
   for what the agent assumed"      handed over, before handover       gets built

  "Unknowns shouldn't become    ──▶ Let a decision be deferred     ──▶ Silence never
   silent guesses"                  explicitly, and carry it           reads as
                                    forward as an open question        agreement

  "Last month's interface is    ──▶ Save, search and reopen        ──▶ Specifications
   nearly the same as this one"     past specifications                become assets

  Reviewer / Operator
  ─────────────────────
  "I must review without        ──▶ Separate producing a spec      ──▶ Review is safe
   risking a build"                 from triggering a build

  Administrator
  ─────────────────────
  "Our practice changes"        ──▶ Question set and reference     ──▶ No code change
                                    data maintained as data            to change policy

  Build agent  (consumer, not a user)
  ─────────────────────
  "I must not have to guess"    ──▶ Emit machine-readable answers  ──▶ Fewer turns,
                                    alongside human-readable prose     fewer assumptions
```

### 2.5 Lifecycle of a specification

State belongs to the specification, not to any screen. A build is a
**consequence** of a specification, never a side effect of editing one.

```
        ┌───────────┐   answer / describe    ┌───────────┐
        │  empty    │───────────────────────▶│  partial  │◀────┐
        └───────────┘                        └─────┬─────┘     │ reopen
                                                   │           │ and revise
                            all required answered  │           │
                                   or deferred     ▼           │
                                             ┌───────────┐     │
                              ┌─────────────▶│ complete  │─────┘
                              │              └─────┬─────┘
                        save  │                    │ review, then hand over
                     (at any  │                    ▼
                       point) │              ┌───────────┐
                              └──────────────│ handed to │
                                             │ the agent │
                                             └───────────┘
                                                   │
                          the handed-over text is retained verbatim,
                          because what was sent is the record — not
                          what the answers would render today
```

---

## 3. Use cases

The requirements in §4 derive from these. Each use case states its own acceptance criteria.

### UC-1 — Specify an interface from scratch

**Actor:** Integration Engineer
**Trigger:** a new interface is requested. The engineer knows the clinical and business intent but not necessarily the platform specifics.
**Precondition:** the engineer is authenticated and working in a known target environment.

**Main flow**

1. The engineer opens the questionnaire. It presents a compact index of the areas to cover, not a wall of inputs.
2. The engineer works through the essential questions. Questions that do not apply are never shown.
3. Where a decision has a defensible platform default, it is pre-filled and labelled as a recommendation.
4. Where the engineer does not know an answer, they record that explicitly.
5. The engineer reviews the generated specification.
6. The engineer hands it to the build agent.

**Acceptance criteria**

- A user with no platform expertise can complete the essential path unaided.
- Every question shown is relevant to answers already given.
- Unknown answers are preserved as open questions, never silently defaulted.
- The generated specification states every captured decision.

### UC-2 — Start from a description instead of a form

**Actor:** Integration Engineer
**Trigger:** the engineer would rather describe the interface in prose than fill in fields.

**Main flow**

1. The engineer writes a free-text description of the interface.
2. The system interprets it and populates the corresponding answers.
3. Every populated answer is marked as requiring verification.
4. Anything the description did not state is listed as still needed.
5. The engineer corrects, completes, and continues as UC-1.

**Acceptance criteria**

- Populated answers are visually distinguishable from ones the user entered.
- Nothing is inferred beyond what the description states; gaps are reported, not filled.
- An interpretation that cannot be mapped to a known field is discarded, not applied.
- The user always confirms before anything is handed downstream.

### UC-3 — Reuse what the environment already provides

**Actor:** Integration Engineer
**Trigger:** the engineer knows, or wants to discover, which platform component to use.

**Main flow**

1. The engineer chooses to specify a component explicitly rather than let the agent select one.
2. The system presents the components actually available in the target environment, with descriptions.
3. The engineer searches, reads, and selects.
4. The selection is recorded in the specification.

**Acceptance criteria**

- Options reflect the target environment, not a static list.
- Each option carries enough description to choose between candidates.
- Selection is optional throughout; unselected means "the agent decides".
- Browsing changes nothing in the environment.

### UC-4 — Review before committing

**Actor:** Integration Engineer
**Trigger:** the questionnaire is complete enough to act on.

**Main flow**

1. The engineer requests a preview of the specification.
2. The system renders it in the form the downstream consumer expects.
3. The engineer may edit the rendered text before sending.
4. The engineer sends it, or returns to the form.

**Acceptance criteria**

- The preview is the exact artefact that will be handed over.
- Outstanding required answers are reported, without blocking preview.
- Edits made in the preview are what get sent and recorded.

### UC-5 — Save work and come back to it

**Actor:** Integration Engineer
**Trigger:** the specification is not finished, or will be needed again later.

**Main flow**

1. The engineer saves the questionnaire under a name.
2. Later, the engineer finds it in a worklist and reopens it.
3. All previously captured answers are restored.
4. Work continues.

**Acceptance criteria**

- Saving is explicit and confirmed.
- A saved item is identifiable by name, owner and time.
- Reopening restores every answer, including repeating groups.
- Anything sent to the agent is recorded without the user having to remember to save it.

### UC-6 — Find an earlier specification

**Actor:** Integration Engineer or Reviewer
**Trigger:** the engineer needs a specification from days or weeks ago, or wants to reuse one as a starting point.

**Main flow**

1. The engineer opens the worklist.
2. They search by name, owner or other identifying attribute.
3. They mark frequently used entries so they surface first.
4. They open it, copy its specification text, or hand it to the agent again.

**Acceptance criteria**

- Search covers the attributes a user would actually recall.
- Search executes at the data source, not by filtering a fully-loaded list.
- Marked entries sort above unmarked ones regardless of age.
- The specification text can be copied without opening the questionnaire.

### UC-7 — Hand over to the build agent

**Actor:** Integration Engineer
**Trigger:** the specification is ready.

**Main flow**

1. The engineer sends the specification.
2. The build agent receives it as the opening context of a build conversation, scoped to the correct environment.
3. The agent proceeds to plan without re-asking questions the specification already answers.
4. The specification is recorded as having been sent.

**Acceptance criteria**

- The handed-over artefact conforms to the contract the agent already understands; no new agent pathway is required.
- The agent does not re-ask any decision the questionnaire captured.
- The environment the agent works in matches the one the engineer was working in.

### UC-8 — Escalate to a specialist tool

**Actor:** Integration Engineer
**Trigger:** the mapping work exceeds what a simple table should express.

**Main flow**

1. The engineer opts out to the dedicated mapping tool.
2. They complete the mapping there.
3. They return and reference it from the specification.

**Acceptance criteria**

- The hand-off is explicit and does not lose questionnaire state.
- The questionnaire does not attempt to become a mapping tool.

---

## 4. Functional requirements

### 4.1 Question model

| ID | Requirement |
|---|---|
| FR-1 | The question set is **defined as data**, not hard-coded, so questions can be added, removed, reordered or relabelled without changing rendering logic. |
| FR-2 | Every question traces to a decision the downstream build genuinely requires. No question exists for completeness alone. |
| FR-3 | Questions carry a tier — essential, recommended, advanced — and the essential path is short enough to complete in one sitting. |
| FR-4 | Questions appear conditionally, based on answers already given. A question that cannot apply is never shown. |
| FR-5 | Where a decision has a defensible domain default, it is pre-filled and explicitly labelled as a recommendation the user may override. |
| FR-6 | "I don't know" is a first-class answer that produces an open question in the output. The system must never substitute a default for an unknown. |
| FR-7 | Progress is visible per area and overall, counting only questions currently applicable. |
| FR-8 | Outstanding required answers are listed and each entry navigates directly to its question. |

### 4.2 Description-driven capture

| ID | Requirement |
|---|---|
| FR-9 | The user may supply a free-text description and have answers derived from it. |
| FR-10 | Interpretation receives the current question set, so a modified question set is honoured without redeploying the interpreter. |
| FR-11 | Derived answers are marked pending verification and visually distinct until confirmed. |
| FR-12 | Only known fields and, for constrained fields, permitted values are accepted. Anything else is discarded rather than applied. |
| FR-13 | Values are routed by what the question set declares a field to be, not by how the interpreter grouped them. |
| FR-14 | Anything the description did not state is surfaced as a gap, never inferred. |
| FR-15 | Worked examples can be loaded to demonstrate the expected level of detail. |

### 4.3 Environment-grounded options

| ID | Requirement |
|---|---|
| FR-16 | Where a question names a platform component, the available options are read from the target environment. |
| FR-17 | Options are searchable and presented with descriptions sufficient to choose between them. |
| FR-18 | Options are filtered to the kind of component the question is asking about. |
| FR-19 | All such selections are optional; unset means the build agent selects. |
| FR-20 | Reading environment metadata is strictly read-only. |

### 4.4 Output

| ID | Requirement |
|---|---|
| FR-21 | The system produces a specification artefact in the form the downstream consumer expects. |
| FR-22 | A human-readable rendering and a machine-readable payload are both available; the machine-readable form is authoritative where they could differ. |
| FR-23 | The machine-readable payload is keyed to the vocabulary the downstream consumer uses, so it maps to actions without inference. |
| FR-24 | An absent value in the payload means *not specified*, and the artefact must instruct the consumer to ask rather than assume. |
| FR-25 | The artefact carries an explicit block confirming the defaulted decisions, so the consumer need not re-ask them. |
| FR-26 | Names for artefacts to be created follow the platform's documented naming conventions and are derived automatically, shown before hand-over. |
| FR-27 | The output is previewable and editable before it is sent. |

### 4.5 Persistence and worklist

| ID | Requirement |
|---|---|
| FR-28 | A questionnaire can be saved explicitly, under a name supplied by the user. Saving refuses an unnamed item. |
| FR-29 | Sending a specification also records it, so anything acted upon is captured without user effort. |
| FR-30 | Both the answers and the generated specification are stored. Neither alone is sufficient: answers cannot reproduce an edited artefact, and the artefact cannot repopulate the form. |
| FR-31 | One record per named questionnaire per owner per environment. Re-saving or re-sending updates that record rather than accumulating duplicates. |
| FR-32 | The worklist is a **first-class screen**, discoverable from the questionnaire, not a dialog behind a secondary control. |
| FR-33 | Each entry shows its name as a link that reopens it, its owner, and when it was last saved. |
| FR-34 | Each entry allows: reopen, copy the specification text, re-send to the consumer, mark as favourite, delete. |
| FR-35 | Entries can be marked as favourite; favourites sort above all others regardless of age and can be filtered to exclusively. |
| FR-36 | Search executes at the data source across the attributes a user would recall, so a large history is never transferred to the client to be filtered. |
| FR-37 | A failed save must report clearly but must never block review or hand-over. Persistence is a side effect, not a gate. |

### 4.6 Convergence with document intake

| ID | Requirement |
|---|---|
| FR-38 | Where the wider product accepts specification documents, the questionnaire is the correction and completion surface for what a document leaves ambiguous. The target flow is: ingest the document, pre-populate the questionnaire from it, have the human verify and complete. |

---

## 5. Data requirements

Described as entities, not as a schema for any particular store.

| Entity | Purpose | Key attributes |
|---|---|---|
| **Question set** | The definition of what is asked | Identifier, version, ordered areas, questions with type, tier, applicability condition, option source, default, and the downstream vocabulary term each answer maps to |
| **Saved questionnaire** | One captured run | Name, owner, target environment, answer set, generated specification text, output format, state (saved / handed over), completeness, favourite flag, created and last-updated timestamps |
| **Environment reference data** | Option sources | Component identifier, kind, description, provenance |

**Requirements**

| ID | Requirement |
|---|---|
| DR-1 | The answer set must accommodate repeating groups of unbounded size (destinations, field mappings) without schema change. |
| DR-2 | The generated specification is stored as captured, including any user edits made at preview time. |
| DR-3 | The record notes the question-set version it was captured against, so a later reload can detect that the question set has moved on. |
| DR-4 | Records must distinguish **created** from **last updated**; the worklist orders and displays on last updated. |
| DR-5 | Updating a record replaces stored content rather than appending to it. |

---

## 6. Integration requirements

| ID | Requirement |
|---|---|
| IR-1 | The questionnaire is a client of existing services. It must not require a new backend surface where an existing one serves — specifically it should reuse the existing consumer interface, environment metadata interface, and authentication. |
| IR-2 | Hand-over must use the contract the downstream consumer already accepts, so no new consumer pathway is introduced. |
| IR-3 | Interpretation of free text (FR-9) should run against a **minimal, isolated configuration** of the language model — no tools, no auxiliary knowledge, deterministic settings, single round trip. It is a transformation, not a reasoning task, and loading it with unnecessary capability adds cost, latency and failure modes. |
| IR-4 | The component must be deployable as part of the existing product package with no separate installation step. |

---

## 7. Security and governance

| ID | Requirement |
|---|---|
| SR-1 | The component performs **no mutating operation** on the target environment. All state change remains behind the build agent's approval gate. |
| SR-2 | It operates as the authenticated user and inherits their permissions. It must never widen access. |
| SR-3 | Embedded in a host application it must inherit the existing session; opened independently it must offer a clear authentication path rather than failing silently. |
| SR-4 | **Records must be scoped to the environment the user is working in**, and that environment must be determined consistently on write and on read. See §9 — this is the single most likely defect in implementation. |
| SR-5 | An authorisation failure must be reported in terms the user can act on, and the interrupted action retried after authentication rather than lost. |
| SR-6 | All requests are subject to the product's existing audit trail. |
| SR-7 | The component handles no patient data. Anything captured is configuration intent; any sample data used for illustration must be synthetic. |

---

## 8. Non-functional requirements

| Requirement | Target |
|---|---|
| First render | Under 1 second |
| Environment option lookup | Under 2 seconds first use, immediate thereafter |
| Free-text interpretation | Under 30 seconds, with continuous visible progress; it must never appear frozen |
| Specification generation | Immediate; no server round trip required |
| Worklist search | Under 1 second at a realistic history size |
| Accessibility | Keyboard-navigable; controls labelled; state conveyed by more than colour alone |
| Resilience | No single failure — save, option lookup, interpretation — may prevent the user completing and handing over a specification |

---

## 9. Implementation hazards

These are not hypothetical. Each was encountered building the reference implementation and each produced a defect that looked like something else.

| Hazard | Consequence | Requirement |
|---|---|---|
| **Two meanings of "environment"** | The environment the *user is working in* is not the environment an *interface targets*; the latter is an answer the user can type. Filing records under the answer makes them vanish from the owner's worklist the moment it is edited. | Record identity uses the working environment. The target is specification content. |
| **Execution context ≠ user context** | Where shared code runs in one environment and serves users in many, reading the execution context on query while storing the user's context on write means the two never match, and the worklist appears permanently empty while data is stored correctly. | Resolve the user's environment from the request, identically on read and write. |
| **Asset caching** | If the page document is revalidated but its scripts are not versioned, a current page can load a stale script. Controls render but do nothing — no error, no request, no clue. | Version client assets so a document and its scripts are always a matched set. |
| **Seeded defaults leaking from hidden branches** | Defaults initialised for every question, including inapplicable ones, will surface in output unless gated by the same applicability rule the user saw. | Serialise only what was applicable. |
| **Client-side filtering of an unbounded list** | Works in demonstration, degrades in production. | Filter and search at the data source. |
| **Optimistic UI without rollback** | A favourite that silently fails to persist teaches users not to trust the tool. | Reflect intent immediately; reconcile with the server; roll back visibly on failure. |

---

## 10. Out of scope

- Authoring or editing the question set through a user interface. The question set must be *data* (FR-1), but the editor is a later increment.
- Field-level mapping construction; that is the specialist tool's job (UC-8).
- Deriving message schemas from sample traffic.
- Emitting platform-specific generator formats.
- Multi-user concurrent editing of one questionnaire.

---

## 11. Definition of done

1. An engineer with no platform expertise completes the essential path and produces a specification that the build agent acts on **without a clarification round**.
2. A free-text description populates the form, every populated answer is marked for verification, and nothing the description omitted has been invented.
3. Component options come from the target environment and a selection is honoured by the agent.
4. A questionnaire is saved by name, found later by search, reopened with every answer restored, and its specification copied without opening it.
5. Favourites sort above all other entries regardless of age.
6. Everything handed to the agent is recorded, under the environment the user was working in, and is visible to that user in that environment.
7. Nothing is created in the target environment by this component at any point.
8. Every hazard in §9 has an explicit test.

---

## 12. Glossary

| Term | Meaning |
|---|---|
| **Specification** | The artefact this tool produces: the complete, agreed statement of what an interface must do. |
| **Question set** | The data-defined collection of questions, their conditions and defaults. |
| **Working environment** | The environment context the user is operating in. Determines record ownership and visibility. |
| **Target environment** | Where the described interface will be built. An answer within the specification. |
| **Build agent** | The downstream consumer that turns a specification into working configuration. |
| **Open question** | A decision the specification explicitly records as unresolved, so the consumer asks rather than assumes. |
| **Confirmed default** | A decision resolved by a recommended default, recorded explicitly so the consumer need not re-ask. |
