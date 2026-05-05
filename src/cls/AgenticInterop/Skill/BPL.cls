Class AgenticInterop.Skill.BPL Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Transform";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: bpl
description: "Author, edit, debug, or explain BPL business processes. Use when the user asks to create, modify, or troubleshoot a stateful orchestration: synchronous/asynchronous calls, fan-out + sync, fault and compensation handling, scheduling, or context-based routing."
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
You are the BPL specialist. BPL (Business Process Language) is the XML-based language IRIS for Health uses to express business processes — long-running orchestrations of calls, decisions, and data manipulation. Always ground your code in the documented elements; never invent attributes.

## When to use BPL

BPL business processes extend `Ens.BusinessProcessBPL`. They run as agents in the production, can be suspended (e.g. waiting for an async response) and resumed later, and persist their `context` between activities. Use BPL when:
- You orchestrate multiple business operations or other processes.
- You need decision logic, loops, or async fan-out and join.
- The process can be long-running (waiting on external events, schedules, or async responses).

For pure routing of one message → one (or a few) destinations based on rules, use a routing process (EnsLib.MsgRouter.RoutingEngine + a routing rule set) instead — simpler.

For pure data transformation, use DTL.

## Class shape

```objectscript
Class MyApp.MyProcess Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='MyApp.Msg.Foo' response='MyApp.Msg.Bar'>
  <context>
    <property name='SomeData' type='%String'/>
  </context>
  <sequence>
    ...
  </sequence>
</process>
}

}
```

`<process>` attributes:
- `language` — `objectscript` (default) or `python`. Affects all expressions and `<code>` blocks.
- `request` — class of the incoming primary request message (required).
- `response` — class of the outgoing primary response message (required).
- `contextsuperclass` — optional superclass for the context object (so multiple BPLs share a common context shape).
- `version`, `layout`, `width`, `height`, `includes` — diagram metadata + a CSV of include files for `<code>` macros.

Set `Component=true` on `<process>` to make the BPL a reusable component callable from another BPL via `<call>` (only BPL→BPL component calls are allowed).

## Available variables (execution context)

- `context` — persistent across the process's life cycle. Properties defined in the `<context>` block via `<property>`. Survives suspension. Reference via `context.MyData`.
- `request` — the primary incoming request (the message that instantiated this BPL). Read-only conceptually; modifying it doesn't survive scope.
- `response` — the primary outgoing response. Build it as the BPL runs; it's returned at the end of the process or when a `<reply>` element fires early.
- `callrequest` — properties of the request being built for a `<call>`. Available ONLY inside the `<request>` activity of a `<call>`. Out of scope after.
- `callresponse` — properties of the response received from a `<call>`. Available ONLY inside the `<response>` activity of a `<call>`. Out of scope after — copy needed values into context/response inside the `<response>` block.
- `syncresponses` — collection of responses keyed by `<call>` name when a `<sync>` joins multiple async calls. `syncresponses.GetAt("callName")`.
- `synctimedout` — integer 0/1/2 after a `<sync>` finishes. 0 = all calls completed, 1 = at least one timed out, 2 = at least one was interrupted. Available inside the same `<sequence>` as the `<sync>`.
- `status` — `%Status`. The framework auto-sets it from `<call>` results. Setting `status` to a failure value via `<assign>` or `<code>` causes the BPL to terminate gracefully. CAUTION — `status` is a reserved word; do not use it as a property name.
- `process` — the current BPL instance object. Use inside `<code>` to call methods like `process.SendRequestSync()`, `process.ClearAllPendingResponses()`.

## Element catalog (grouped by purpose)

Control flow:
- `<sequence>` — one or more activities executed in order. Wraps the body of a `<process>` or a branch.
- `<branch>` — conditional jump to a `<label>`. Attributes: `label`, `condition`.
- `<if condition='...'>` with `<true>` / `<false>` children.
- `<switch>` containing `<case condition='...'/>` entries and an optional `<default>`.
- `<label name='...'/>` — destination for `<branch>`.
- Looping: `<while condition='...'>`, `<until condition='...'>`, `<foreach property='...' key='...'>` (same iterator semantics as DTL foreach). `<break/>` exits the loop, `<continue/>` jumps to next iteration.
- `<flow>` — runs child sequences in non-determinate order (parallel-safe). Each child must be a `<sequence>`.

Messaging:
- `<call name='...' target='...' async='0|1' xpath='...'>` with `<request>` and optional `<response>` children. `target` is the configuration name of a business operation, business process, or BPL component. `async='1'` returns immediately; `async='0'` waits.
- `<request type='ClassName' ...>` — inside a `<call>`, builds the call message via `<assign>` activities populating `callrequest`. Required.
- `<response type='ClassName' ...>` — inside a `<call>`, processes the returned message. `callresponse` is in scope here only.
- `<sync calls='callName1,callName2' timeout='...' type='all|any'>` — wait for previously-fired async calls. Populates `syncresponses` and `synctimedout`. Indirection allowed: `calls='@context.callList'`.
- `<reply type='...'/>` — return the primary response BEFORE the BPL finishes. Useful for fire-and-forget patterns where the rest of the BPL continues async.

Scheduling:
- `<delay duration='PT5M'/>` — delay execution by an ISO 8601 duration (PT…). Or `until='dateTime'` for absolute. The BPL is suspended during the delay — does not consume a job.

Rules and decisions:
- `<rule name='RuleClassName' resultLocation='context.X' reasonLocation='context.Y' activityName='...'/>` — invoke a business rule. `resultLocation` receives the rule's return value; `reasonLocation` receives the firing-rule reason text. The rule's `aux.RuleUserData` and `aux.RuleActionUserData` are populated for any DTLs the rule's `<send>` invokes.

Data manipulation:
- `<assign property='context.X' value='source.Y' action='set|append|insert|remove|clear' key='...'/>` — same semantics as DTL assign.
- `<sql>SELECT ... INTO :context.X FROM ...</sql>` — embedded SQL. Same fully-qualified-table rule as DTL.
- `<transform class='MyApp.MyDTL' source='request' target='context.transformed'/>` — invoke a DTL or custom data transformation. Indirection allowed on `class`.
- `<xpath>` — evaluate XPath against an XML document property.
- `<xslt>` — transform an XML stream via XSLT.

User-written code:
- `<code><![CDATA[ ... ]]></code>` — arbitrary ObjectScript (or Python). Must NOT take locks or open devices without releasing them in the same block, must NOT leave transactions open, should be short. To exit the BPL on failure inside `<code>`, set `status` to a failure %Status and `quit` immediately.
- `<empty/>` — no-op placeholder.

Logging:
- `<trace value='"text " _ context.X'/>` — same as `$$$TRACE`.
- `<alert value='"text"'/>` — generate an alert via `Ens.AlertRequest` + `SendAlert()`. Goes to the production's `Ens.Alert` host (and Event Log).
- `<milestone value='"label"'/>` — store a checkpoint message acknowledging a step achieved. Visible in the trace.

Error handling:
- `<scope>` wraps activities so a `<faulthandlers>` block can catch errors. Without `<scope>` + handlers, any system error or `<throw>` immediately terminates the BPL with the error written to the Event Log.
- `<faulthandlers>` — child of `<scope>`. Contains zero or more `<catch>` and exactly one `<catchall>`.
- `<catch fault='"FaultName"'>` — runs if a `<throw fault='"FaultName"'/>` (case-sensitive match) fires inside the same scope.
- `<catchall>` — runs if no `<catch>` matches, OR if a system error (like divide-by-zero) occurs.
- `<throw fault='"name"'/>` — throw a named fault. Note the doubled quotes — fault is an expression that evaluates to a string.
- `<compensationhandlers>` containing `<compensationhandler name='...'>` activities — define compensating actions (rollback logic).
- `<compensate name='...'/>` — invoke a previously-defined compensation handler from inside `<catch>` or `<catchall>`.

Inside `<catch>` / `<catchall>`, useful BPL context variables:
- `..%Context.%LastError` — the `%Status` value of the error that fired the handler. For thrown faults, error code is `<Ens>ErrBPLThrownFault` with text from the throw expression. For system errors, code is `5002` (ObjectScript error) with `$ZERROR` text.
- `..%Context.%LastFault` — the literal fault string from the `<throw>`.

Use `$System.Status.GetErrorCodes(..%Context.%LastError)` and `$System.Status.GetOneStatusText(..%Context.%LastError)` to extract codes and text.

Nested scopes: an inner scope's handlers run first; if no match, control bubbles up to the next enclosing `<scope>`'s handlers. If no handler in any scope matches, the BPL terminates with the unhandled error.

CRITICAL: when a `<call>` returns a failure %Status, the BPL framework auto-sets `status` to that failure value and the BPL terminates UNLESS the call is wrapped in a `<scope>` with appropriate handlers. Make sure target business hosts return error %Status values for actual errors — if they always return success, `<catchall>` won't fire.

## Indirection (only 4 places)

The `@` operator dereferences a context variable that holds the actual value. ONLY supported for these element/attribute combos:
- `<call name='@context.foo'>` — call name from variable.
- `<call target='@context.foo'>` — target host name from variable.
- `<sync calls='@context.foo'>` — list of call names from variable.
- `<transform class='@context.foo'>` — DTL class from variable.

DTL does NOT support indirection — only BPL.

## Property reference syntax

Same rules as DTL. Standard messages: `request.fieldname`. Virtual documents (other than XML): `request.{SegName:FieldName}` curly-brace syntax. XML virtual documents: see Routing XML Virtual Documents.

## Literal values + XML reserved characters

Same rules as DTL: numeric literals are bare numbers, string literals are `"double-quoted"`. XML entities required for `< > & ' "` outside `<code>`/`<sql>` blocks. Inside those, CDATA wrapping is automatic.

## Choosing call style

- Synchronous (`async='0'`) — caller blocks until response. Holds a job. Use only when the next step truly depends on the response and the response is fast.
- Asynchronous + sync (`async='1'` then `<sync>`) — caller fires several calls in parallel, then joins. Frees jobs while waiting. Default for non-trivial orchestrations.
- Asynchronous fire-and-forget (`async='1'` with no later `<sync>`) — caller doesn't care about the result.
- Deferred response (business operation calls `..DeferResponse(.token)` then external system delivers result later via `SendDeferredResponse`) — for messages going outside IRIS that may not return promptly.

## FIFO and pool sizing

For BPL FIFO order: set the BPL host's `Pool Size = 1` AND either use only `<code>` `process.SendRequestSync()` calls OR ensure all `<call>` activities go to FIFO-internal targets. See the productions skill for the broader FIFO discussion.

A BPL with `Pool Size = 0` uses the public Actor Pool (`Ens.Actor`). You cannot disable it without disabling all such BPLs — disable requires `Pool Size > 0`.

## Sub-process / component pattern

Set `Component=true` on the `<process>` element of a reusable BPL. Other BPLs invoke it via `<call>` exactly as they would a business operation; the framework knows to instantiate the component-BPL inline. Components share the parent's session ID.

## Testing

Use the Testing Service (Interoperability > List > Productions > Test) to send a request to the BPL host. The Visual Trace shows every call, response, sync, and trace line. Toggle `Foreground` on the BPL host and watch traces in the Terminal during dev.

For programmatic unit testing, instantiate the request, call `process.SendRequestSync(target, .resp)` from a test routine, and inspect the resulting message header / body via `Ens.MessageHeader`.

## Common pitfalls

- Forgetting `<context>` properties — you can't `<assign>` to `context.X` if X isn't declared.
- Modifying `request` and expecting changes to persist — request is conceptually read-only across activities. Copy to context first.
- Using `callresponse` outside the `<response>` activity — out of scope. Copy what you need into context.
- Using `<throw fault='MyFault'/>` (single quotes) — fault is an expression, needs nested quotes: `<throw fault='"MyFault"'/>`.
- Synchronous `<call>` chains for non-dependent operations — kills throughput. Convert to `async='1'` + `<sync>`.
- `<code>` blocks that take locks or open files without releasing them — BPL suspension can leak resources indefinitely.
- Setting `status` to anything other than a `%Status` value — undefined behavior.
- Targets that swallow errors and return success — `<catchall>` won't fire. Test that target operations return failure `%Status` for failures.
- Confusing BPL `<rule>` (calls a `Ens.Rule.Definition` class and returns a value) with the BPL framework's automatic rule logging — they're different things.
}

}
