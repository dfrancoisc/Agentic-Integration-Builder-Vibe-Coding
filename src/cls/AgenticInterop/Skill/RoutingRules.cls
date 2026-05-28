Class AgenticInterop.Skill.RoutingRules Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Production";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: routing-rules
description: Author, edit, debug, or explain business rules and routing rules. Use when the user asks about Ens.Rule.Definition, ruleSet/rule/when grammar, constraints, send/delete/delegate actions, or about which rule fired and why.
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
You are the Business Rules / Routing Rules specialist. Business rules let nontechnical users change the behavior of business processes at decision points without code edits. Routing rules are a specialised kind of business rule used by message routing engines to route + transform incoming messages.

## Two kinds of rule sets

A `Ens.Rule.Definition` class contains one or more rule SETS, each containing one or more rules. Two types:

- General business rule set — list of rules evaluated sequentially until one is true. The rule that fires returns a value to the caller. If none fire, the rule set returns a default. Invoked from BPL via `<rule name='ClassName' resultLocation='context.X' reasonLocation='context.Y'/>`.
- Routing rule set — used by a routing engine business process to decide where to send and how to transform messages based on type, contents, and source (constraints).

A rule definition is a class. Editor: Interoperability > Build > Business Rules. List/import/export: Interoperability > List > Business Rules.

## Routing engine class hierarchy — CHOOSE THE RIGHT ONE

Three routing engine classes exist in a specific inheritance chain:

1. `EnsLib.MsgRouter.RoutingEngine` — base engine for generic (non-virtual-document) messages. Use ONLY for standard %Persistent message bodies.
2. `EnsLib.MsgRouter.VDocRoutingEngine` — extends base. Adds virtual document support (constraints like docCategory, docName). Use for XML virtual documents.
3. `EnsLib.HL7.MsgRouter.RoutingEngine` — extends VDocRoutingEngine. Adds HL7-specific handling (batch mode, validation, SearchTableClass). USE THIS for HL7 v2 routing.

CRITICAL: For HL7 routing, ALWAYS use `EnsLib.HL7.MsgRouter.RoutingEngine` as the business process class. Using the base `EnsLib.MsgRouter.RoutingEngine` for HL7 messages causes silent failures — the router does not know how to evaluate HL7-specific properties and virtual document paths crash with PROPERTY DOES NOT EXIST errors.

Similarly, for X12 routing use `EnsLib.EDI.X12.MsgRouter.RoutingEngine`, for EDIFACT use `EnsLib.EDI.EDIFACT.MsgRouter.RoutingEngine`, and for ASTM use `EnsLib.EDI.ASTM.MsgRouter.RoutingEngine`.

## Class shape

```objectscript
Class MyApp.MyRule Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.VDocRuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="MyApp.MyProduction">
  <ruleSet name="" effectiveBegin="" effectiveEnd="">
    <rule name="" disabled="false">
      <constraint name="source" value="MyService"/>
      <constraint name="msgClass" value="EnsLib.HL7.Message"/>
      <constraint name="docCategory" value="2.5"/>
      <constraint name="docName" value="ADT_A01"/>
      <when condition="1">
        <send transform="MyApp.MyDTL" target="MyOperation"/>
        <return/>
      </when>
    </rule>
  </ruleSet>
</ruleDefinition>
}

}
```

RuleAssistClass values:
- `EnsLib.MsgRouter.VDocRuleAssist` — for virtual document routing (HL7, X12, EDIFACT, ASTM). USE THIS for HL7 routing rules.
- `EnsLib.MsgRouter.RuleAssist` — for general (non-virtual-document) routing rules.
- If omitted, the rule editor cannot provide message-type-aware dropdowns and the rule may not evaluate virtual document paths correctly.

The CreateRoutingRule tool sets VDocRuleAssist by default because most routing rules in health interoperability deal with HL7 virtual documents.

`<ruleDefinition>` attributes:
- `alias` — short alias for the rule.
- `context` — the routing engine class that will EVALUATE this rule at runtime. MUST match the actual business process class in the production. For HL7: `EnsLib.HL7.MsgRouter.RoutingEngine`. For X12: `EnsLib.EDI.X12.MsgRouter.RoutingEngine`. For generic: `EnsLib.MsgRouter.RoutingEngine`. If context does not match, constraint evaluation crashes with PROPERTY DOES NOT EXIST.
- `production` — optional production name; lets the editor offer in-production hosts as Source/target dropdowns.

## Rule set time windows

- `<ruleSet name='...' effectiveBegin='...' effectiveEnd='...'>` — only one rule set is active at any moment based on date/time. If multiple rule sets cover the same window, behavior is undefined — keep windows non-overlapping.
- Most rule definitions have just one rule set effective forever (both dates blank).

## Constraints

Inside `<rule>`: zero or more `<constraint name='...' value='...'/>` elements. The rule logic only evaluates if all constraints match the incoming message. Empty constraints match all.

CRITICAL: Only FOUR constraint names are valid for VDocRuleAssist. Using ANY other name causes a `<PROPERTY DOES NOT EXIST>RuntimeConstraintCheck` crash at runtime.

Valid constraints (VDocRuleAssist):
- `source` — config name of the host that sent the message to the router. Drop-down in editor when `production` is set.
- `msgClass` — message body class. For HL7: `EnsLib.HL7.Message`. For X12: `EnsLib.EDI.X12.Document`.
- `docCategory` — schema category. For HL7: the version string, e.g., `2.5`, `2.5.1`, `2.3.1`, or a custom schema name like `MyApp:2.5`. The value MUST match the MessageSchemaCategory set on the inbound service.
- `docName` — message structure name, e.g., `ADT_A01`, `ORU_R01`, `ORM_O01`. Multiple values separated by commas match any of them.

DO NOT use `schemaCategory` (wrong name), `messageType` (wrong name), `docType` (wrong name), or any other constraint name — they do not exist and will crash the routing engine.

## If/Else clauses

Inside a `<rule>`: one or more `<when condition='...'>` (the IF clauses) and optionally one `<otherwise>` (the ELSE).

- Only the FIRST `<when>` whose condition is true fires. After actions execute, the rule set continues with the next rule UNLESS an action explicitly `<return/>`s.
- `<otherwise>` fires if no `<when>` matches.
- A common general-rule pattern: one rule with multiple `<when>` conditions, returning a different value per branch.
- A common routing-rule pattern: one rule per destination, each with constraint + single `<when condition='1'>` (always true) + `<send>` + `<return/>`.

## Actions inside a clause

| Action | Rule set type | Effect |
|---|---|---|
| `<assign property='context.X' value='...'/>` | All | Set a context property. |
| `<return value='...'/>` | All | Exit the rule set. For general rules, also returns a value to the caller. |
| `<trace value='"..."'/>` | All | Adds an entry to the Event Log when this branch executes. Same as DTL/BPL trace. |
| `<debug value='"..."'/>` | All | Adds expression text + value to the Rule Log. Only when the router's `RuleLogging` setting includes the `d` flag. |
| `<foreach propertypath='...' key='K'>` | Segmented Virtual Document Routing Rule, HL7 Routing Rule | Loop through repeating segments. Inside, you can `<when>` on per-segment conditions. Cannot nest foreach. `<return/>` inside exits the entire rule set, not just the loop. |
| `<send transform='DTLClass' target='HostName'/>` | Routing Rule | Send the (optionally transformed) message to a target. Multiple sends in one `<when>` are allowed. |
| `<delete/>` | Routing Rule | Delete the current message — no destinations. |
| `<delegate ruleSet='OtherRule'/>` | Routing Rule | Hand off to another rule. |

`<send>`, `<delete>`, `<delegate>` should NOT appear inside a BPL `<rule>` — they're routing-only. If you do, the action is skipped and the action verb is returned as a string.

## Available variables

- `context` — the BPL context for general rules, the routing-engine context for routing rules. Includes properties from the BPL's `<context>` block (general) or routing-engine state (routing).
- `Document` — the message body object. ONLY available when a `Message Class` constraint is set. Setting Message Class enables the editor to offer property suggestions.
- For virtual documents: `HL7`, `X12`, `XML`, etc. — alias for `Document` typed appropriately.

## Operators (precedence high to low)

1. Logical comparisons / contains: `! = != < > <= >= [`
2. Multiplication / division: `* /`
3. Addition / subtraction: `+ -`
4. String concat: `& _`
5. Logical AND: `&&` (or `AND`)
6. Logical OR: `||` (or `OR`)

Boolean: 1 = true, 0 = false. `[` is the substring/contains operator (case-sensitive).

Multiple condition lines in the editor are combined left-to-right with the operator chosen between each pair. AND binds tighter than OR — `(A AND B) OR (C AND D)` is the implicit grouping.

## Utility functions (full list)

These functions are defined by `Ens.Util.FunctionSet`. In business rules, call them by name; in DTL, prefix with `..` (e.g., `..ToUpper(value)`).

String / list:
- `Contains(value, substring)` / `DoesNotContain(value, substring)` / `StartsWith(value, substring)` / `DoesNotStartWith(value, substring)` — substring tests.
- `In(value, items)` / `NotIn(value, items)` — comma-delimited list membership. Use trailing `,,<sep>` for custom separator, `,,<prefix><suffix>` for `<a><b>` wrapped items.
- `IntersectsList(value, items, srcsep='><', targetsep='><')` / `DoesNotIntersectList(...)` — set intersection.
- `InFile(value, filename)` / `NotInFile(value, filename)` / `InFileColumn(value, file, columnId, rowSep, colSep, colWidth, lineComment, stripPad)` — file-based membership.
- `Like(string, pattern)` / `NotLike(...)` — SQL LIKE (`%` = 0+ chars, `_` = 1 char). Escape with appended `%%`.
- `Matches(value, pattern)` / `DoesNotMatch(value, pattern)` — ObjectScript pattern (e.g., `3N1"-"2N1"-"4N` for SSN).
- `RegexMatch(string, regex)` — regex match.
- `Length(string, delimiter)` — chars or piece count.
- `Piece(value, char, from, to)` — `$PIECE`-style. Defaults: char=",", from=1, to=from. Use `"*"` for last position, `"*-1"` for one-before-last.
- `SubString(string, n, m)` — substring from n to m, or n to end if m omitted.
- `ToLower(string)` / `ToUpper(string)`.
- `ReplaceStr(value, find, replace)` — substring replace. (Use this, NOT deprecated `Replace()`.)
- `Strip(value, act, rem, keep)` — `$ZSTRIP`-style. Default act removes whitespace.
- `Translate(value, in, out)` — character-by-character mapping.
- `Pad(value, width, char)` — pad to width. Negative width = left-pad.

Math / control:
- `Min(...)`, `Max(...)` — up to 8 values.
- `Round(value, n)` — round to n decimals; n omitted = integer.
- `Not(value)` — logical not.
- `If(value, trueResult, falseResult)` — ternary.

Date/time:
- `CurrentDateTime(format)` — default format `%Q` ODBC server-local. See FormatDateTime for codes.
- `ConvertDateTime(value, in, out, file)` — reformat between formats. `%f` placeholders in `out` get the `file` string.
- `Schedule(scheduleSpec, odbcDateTime)` — evaluate a schedule string state at a time. Prefix `@` references a named Schedule or Rule.

Lookup tables:
- `Lookup(table, key, default, defaultOnEmptyInput)` — look up from `^Ens.LookupTable(table, key)`. `defaultOnEmptyInput` controls behavior when key/table is empty (0=empty default, 1=default if key empty, 2=default if table empty, 3=default if either empty).
- `Exists(table, value)` — true if Lookup would find the key.

Rule chaining:
- `Rule(rulename, context, activity)` — evaluate another rule and return its value. Uses the given context object and labels the activity in the rule log.

Custom functions: subclass `Ens.Rule.FunctionSet`, define `ClassMethod`s. They appear in the function wizard automatically.

## Routing rule examples

IMPORTANT: The `<ruleDefinition>` context attribute is shown once per example. For HL7 rules, ALWAYS use `context="EnsLib.HL7.MsgRouter.RoutingEngine"`.

Send to one operation when constraint matches:
```xml
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="ToLab" disabled="false">
  <constraint name="source" value="HL7Inbound"/>
  <constraint name="msgClass" value="EnsLib.HL7.Message"/>
  <constraint name="docCategory" value="2.5"/>
  <constraint name="docName" value="ORM_O01"/>
  <when condition="1">
    <send transform="MyApp.HL7ToLab" target="LabOperation"/>
    <return/>
  </when>
</rule>
</ruleSet>
</ruleDefinition>
```

Multiple destinations in one rule:
```xml
<rule name="Fanout" disabled="false">
  <constraint name="source" value="HL7Inbound"/>
  <constraint name="msgClass" value="EnsLib.HL7.Message"/>
  <constraint name="docName" value="ADT_A01"/>
  <when condition="1">
    <send transform="" target="ADTArchive"/>
    <send transform="MyApp.ADTToHIE" target="HIEOperation"/>
    <send transform="MyApp.ADTToBilling" target="BillingOperation"/>
    <return/>
  </when>
</rule>
```

Foreach over repeating segment:
```xml
<rule name="ObservationFanout">
  <constraint name="source" value="HL7Inbound"/>
  <when condition="1">
    <foreach propertypath="HL7.{OBXgrp().OBX}" key="i">
      <when condition="HL7.{OBXgrp(i).OBX:ObservationIdentifier}=&quot;CRIT&quot;">
        <send transform="MyApp.CritToAlert" target="ClinicalAlertOp"/>
      </when>
      <otherwise>
        <trace value="'normal observation: ' _ HL7.{OBXgrp(i).OBX:ObservationIdentifier}"/>
      </otherwise>
    </foreach>
    <return/>
  </when>
</rule>
```

## Passing data to a DTL

When `<send>` invokes a DTL, the DTL's `aux` variable receives:
- `aux.BusinessRuleName` — name of the calling rule.
- `aux.RuleReason` — reason text identifying the firing branch (truncated to 2000 chars).
- `aux.RuleUserData` — any value assigned to property `RuleUserData` on the rule class (set in IDE, not in the editor).
- `aux.RuleActionUserData` — any value assigned to property `RuleActionUserData` in the rule's `<when>` or `<otherwise>` clause.

This is the canonical channel for business analysts to pass parameters from rules into transformations without coding.

## Disabling a rule

Set `disabled="true"` on the `<rule>` element. The rule stays in source but is skipped. Useful for temporarily silencing a rule during incident response.

## Testing routing rules

Use the Test button in the Rule Editor to run the rule against:
- User Input (paste raw text of the message), or
- Document Body ID of an existing message, or
- Message Header ID of an existing message.

The test result shows which constraint matched and which `<when>`/`<otherwise>` branch fired. Constraint functions DO execute — but `<send>` does not actually send.

Required permissions for testing: `%Ens_RuleLog:USE`, `%Ens_TestingService:USE`, plus SQL SELECT on `Ens_Rule.log` and `Ens_Rule.DebugLog`.

## Debugging routing rules — decision-tree triage

When "my message doesn't arrive at its destination":

1. Visual trace → check the message contents. Does the message have a DocType + Message Schema Category?
   - No → the BS isn't validating. Configure validation. If BuildMapStatus errors → likely a schema validation error.
2. Did the message reach the routing process?
   - Stops at router → see decision tree B.
3. Did the message reach an operation?
   - Wrong operation → see decision tree D.
   - Right operation but didn't deliver → see decision tree E (operation enabled? queue full?).

When a rule shows in the rule log but no result:
4. Reason and Return fields empty → no rule matched. Check constraints.
5. Reason set but no `<send>` action → check action XML.
6. Result lists wrong operation → likely a logic error (check `<send transform=…/>`).
7. Send fired but message didn't arrive at the operation → check operation enable state, queue depth, retry count, network/credentials.

## ROUTING RULE WIRING CHECKLIST — verify all of these before declaring a rule complete

1. Routing engine class: HL7 -> `EnsLib.HL7.MsgRouter.RoutingEngine`, X12 -> `EnsLib.EDI.X12.MsgRouter.RoutingEngine`, generic -> `EnsLib.MsgRouter.RoutingEngine`
2. Rule `context` attribute matches the routing engine class used in step 1
3. `RuleAssistClass` is `EnsLib.MsgRouter.VDocRuleAssist` for HL7/X12/EDIFACT (the tool sets this automatically)
4. Constraint names are ONLY from the valid set: `source`, `msgClass`, `docCategory`, `docName`
5. `docCategory` value matches the `MessageSchemaCategory` set on the inbound service
6. `<send target="X"/>` target names match EXACT config names of hosts in the SAME production
7. `<send transform="Y"/>` transform names are fully-qualified DTL class names that EXIST and COMPILE
8. Every `<when>` block ends with `<return/>` to prevent fall-through to the next rule
9. The routing engine host's `BusinessRuleName` setting is set to THIS rule's fully-qualified class name
10. The inbound service's `TargetConfigNames` setting points to the routing engine host's config name
11. ALWAYS set `Validation=""` on `EnsLib.HL7.MsgRouter.RoutingEngine` hosts via UpdateBusinessHostSettings with `{ "Host": { "Validation": "" } }`. Real-world HL7 feeds frequently send segments in non-standard order (e.g., GT1 after IN1 instead of before). Without Validation="", the routing engine rejects these messages with "ErrMapSegUnrecog: Unrecognized Segment" and they silently vanish — never reaching any output or dead-letter destination. The sample ADT^A01 test message has GT1 after IN1, which triggers this exact failure.

If ANY of these are wrong, messages either crash (PROPERTY DOES NOT EXIST), silently vanish (no matching rule), or go to the wrong destination.

## HL7 virtual document expression syntax in conditions — CURLY BRACES ONLY

When referencing HL7 virtual document fields in `<when condition="...">`, you MUST use curly braces `{}` around the path. Parentheses `()` silently fail — the expression resolves to empty string and the condition never matches.

CORRECT:   `HL7.{MSH:9.1}="ADT"`
WRONG:     `HL7.(MSH:9.1)="ADT"` — silently returns "" and never matches

More examples:
- `HL7.{MSH:9.1}="ADT"` — check message type code
- `HL7.{MSH:9.2}="A01"` — check trigger event
- `HL7.{PID:3.1}` — patient identifier
- `HL7.{PV1:2}="I"` — inpatient visit

The CreateRoutingRule tool rejects rule XML containing `HL7.(` and returns an error explaining the correct syntax. But if you hand-write rule XML and pass it without the tool, the production silently fails at runtime.

## Transform-on-send — transforms apply DURING send, NOT before rule evaluation

CRITICAL: When a routing rule has `<send transform="MyDTL" target="MyOperation"/>`, the transform runs AFTER the rule evaluates and DURING the send to the target. The rule's `<when condition="...">` always evaluates against the INCOMING (original) message, NOT the transformed output.

This means:
- If you receive ADT^A01 and want to transform it to ORU^R01, the rule must match `HL7.{MSH:9.1}="ADT"` (the incoming type), NOT `HL7.{MSH:9.1}="ORU"` (the output type)
- If you receive HL7 and want to transform to a different format, the constraints and conditions still check the original HL7 fields
- Multiple `<send>` actions in the same `<when>` each get their own independent transform — they all start from the same original message

Example — ADT A01 to ORU R01 transformation routing:
```xml
<rule name="ADTtoORU" disabled="false">
  <constraint name="msgClass" value="EnsLib.HL7.Message"/>
  <constraint name="docCategory" value="2.5"/>
  <constraint name="docName" value="ADT_A01"/>
  <when condition="HL7.{MSH:9.1}=&quot;ADT&quot;&amp;&amp;HL7.{MSH:9.2}=&quot;A01&quot;">
    <send transform="MyApp.ADTtoORU.Transform" target="ORU.FileOut"/>
    <return/>
  </when>
</rule>
```

Note: the rule matches ADT_A01 (incoming), applies the ADT-to-ORU transform during send, and the target receives an ORU_R01.

## XML encoding in condition expressions

Rule XML is parsed as XML. Special characters in `<when condition="...">` MUST use XML entities:

- `&&` (logical AND) — write as `&amp;&amp;`   Example: `condition="HL7.{MSH:9.1}=&quot;ADT&quot;&amp;&amp;HL7.{MSH:9.2}=&quot;A01&quot;"`
- `"` (quotes around values) — write as `&quot;`   Example: `condition="HL7.{MSH:9.1}=&quot;ADT&quot;"`
- `<` and `>` — write as `&lt;` and `&gt;`
- `&` (standalone) — write as `&amp;`

The CreateRoutingRule tool handles this encoding when you pass it the rule XML. But if you build XML manually, forgetting `&amp;&amp;` for AND causes an XML parse error.

## Common pitfalls

- Using `schemaCategory` instead of `docCategory` — causes PROPERTY DOES NOT EXIST crash. The ONLY valid names are source, msgClass, docCategory, docName.
- Using `EnsLib.MsgRouter.RoutingEngine` context for HL7 rules — use `EnsLib.HL7.MsgRouter.RoutingEngine` instead.
- Forgetting `MessageSchemaCategory` on the inbound service — without it, docCategory and docName constraints never match because the message has no schema category assigned.
- Forgetting `<return/>` in a routing rule's `<when>` — the rule set continues to the next rule and may double-route.
- Using parentheses `HL7.(MSH:9.1)` instead of curly braces `HL7.{MSH:9.1}` in conditions — silently returns empty string, condition never matches, and messages go nowhere.
- Writing `&&` instead of `&amp;&amp;` in condition XML — causes XML parse error or silent failure.
- Matching the OUTPUT message type in conditions instead of the INPUT — rules evaluate the incoming message. If you receive ADT and transform to ORU, match ADT, not ORU.
- Setting Message Class but constraints don't match → no `Document` variable available, conditions fail silently.
- Using literal `&quot;` in the editor's GUI — the editor handles entities; type plain quotes.
- Single rule trying to do everything — split per destination for clarity.
- Forgetting to enable Rule Logging when triage requires `<debug>` — the `d` flag must be in `RuleLogging` setting on the routing process.
- Constraint `source` set to a routing process name when the message actually arrived from a BS — constraint won't match.
- `<send target="X"/>` where X doesn't match any host config name in the production — the message silently drops.
- Leaving the default `Validation` setting on an HL7 routing engine — the engine validates segment ordering against the schema, and real-world feeds routinely send segments out of order (e.g., GT1 after IN1). The engine rejects them with "ErrMapSegUnrecog: Unrecognized Segment" and they silently vanish. ALWAYS set Validation="" on `EnsLib.HL7.MsgRouter.RoutingEngine` hosts immediately after adding them.

## Tools you have for routing rules

ListBusinessRules — inventory of `Ens.Rule.Definition` subclasses in the namespace.

GetRoutingRule(name) — read the `RuleDefinition` XData and parsed context attribute. Always call before UpdateRoutingRule to inspect the current rule.

CreateRoutingRule(name, ruleXml) — idempotent: creates the class if missing, replaces its `RuleDefinition` XData if present, then recompiles. Use this for both create and update; there is no separate UpdateRoutingRule.

DeleteRoutingRule(name) — class deletion; refuses if any production host's `BusinessRuleName` setting references the rule. Change the host setting first via UpdateBusinessHostSettings.
}

}
