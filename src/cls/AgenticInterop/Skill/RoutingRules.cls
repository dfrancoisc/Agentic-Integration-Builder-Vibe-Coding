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
- Routing rule set — used by `EnsLib.MsgRouter.RoutingEngine` (or `EnsLib.MsgRouter.VDocRoutingEngine` for virtual documents). Based on message type/contents/source (constraints), the rule set decides where to send and how to transform.

A rule definition is a class. Editor: Interoperability > Build > Business Rules. List/import/export: Interoperability > List > Business Rules.

## Class shape

```objectscript
Class MyApp.MyRule Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="MyApp.MyProduction">
  <ruleSet name="" effectiveBegin="" effectiveEnd="">
    <rule name="" disabled="false">
      <constraint name="source" value="MyService"/>
      <constraint name="msgClass" value="EnsLib.HL7.Message"/>
      <when condition="HL7.{MSH:MessageType}=&quot;ADT_A01&quot;">
        <send transform="MyApp.MyDTL" target="MyOperation"/>
        <return/>
      </when>
    </rule>
  </ruleSet>
</ruleDefinition>
}

}
```

`<ruleDefinition>` attributes:
- `alias` — short alias for the rule.
- `context` — context class. For routing rules, this is typically the routing engine class (`EnsLib.MsgRouter.RoutingEngine`). For general business rules invoked from BPL, this is the BPL class's `.Context` companion (auto-generated when the BPL has a `<context>` block).
- `production` — optional production name; lets the editor offer in-production hosts as Source/target dropdowns.

## Rule set time windows

- `<ruleSet name='...' effectiveBegin='...' effectiveEnd='...'>` — only one rule set is active at any moment based on date/time. If multiple rule sets cover the same window, behavior is undefined — keep windows non-overlapping.
- Most rule definitions have just one rule set effective forever (both dates blank).

## Constraints

Inside `<rule>`: zero or more `<constraint name='...' value='...'/>` elements. The rule logic only evaluates if all constraints match the incoming message. Empty constraints match all.

Standard constraints:
- `source` — config name of a business service (or another routing process if chained). Drop-down in editor when `production` is set.
- `msgClass` — message body class. For virtual documents, choose from defined virtual document classes.
- `schemaCategory` — for virtual document routing rules, schema category (e.g., `2.5` for HL7 v2.5 or your custom category).
- `docName` — for virtual document routing rules, message structure name (e.g., `ADT_A01`). Multiple values match any of them.

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

Send to one operation when constraint matches:
```xml
<rule name="ToLab" disabled="false">
  <constraint name="source" value="HL7Inbound"/>
  <constraint name="msgClass" value="EnsLib.HL7.Message"/>
  <when condition="1">
    <send transform="MyApp.HL7ToLab" target="LabOperation"/>
    <return/>
  </when>
</rule>
```

Multiple destinations in one rule:
```xml
<rule name="Fanout" disabled="false">
  <constraint name="source" value="HL7Inbound"/>
  <when condition="HL7.{MSH:MessageType.MessageCode}=&quot;ADT&quot;">
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

## Common pitfalls

- Forgetting `<return/>` in a routing rule's `<when>` — the rule set continues to the next rule and may double-route.
- Setting Message Class but constraints don't match → no `Document` variable available, conditions fail silently.
- Using literal `&quot;` in the editor's GUI — the editor handles entities; type plain quotes.
- Single rule trying to do everything — split per destination for clarity.
- Forgetting to enable Rule Logging when triage requires `<debug>` — the `d` flag must be in `RuleLogging` setting on the routing process.
- Constraint `source` set to a routing process name when the message actually arrived from a BS — constraint won't match.
}

}
