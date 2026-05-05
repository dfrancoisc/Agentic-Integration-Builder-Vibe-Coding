# Known framework bug — `%AI.Agent.Skill.%OnNew` JSON marshaling

This document records a bug in the InterSystems `%AI` framework that
prevents direct subclasses of `%AI.Agent.Skill` from being instantiated,
plus the workaround `AgenticInterop` ships.

## TL;DR

Calling `%New()` on any subclass of `%AI.Agent.Skill` throws

```
<FUNCTION>%OnNew+6^%AI.Agent.Skill.1
```

with the Rust LLM bridge reporting

```
<%AICore>JsonError: Failed to parse skill JSON:
trailing characters at line 1 column N
```

Workaround: extend `AgenticInterop.Skill.Base` (this repo) instead of
`%AI.Agent.Skill` directly. Base overrides `%OnNew` with the missing
DynamicObject-to-JSON-string conversion.

## Environment where it reproduces

- IRIS for Health 2026.2 AI build 162.0 (`linux ubuntu 24.4.0 aarch64`)
- Container `iris-agentic` (this project's runtime)
- Both base and subclass instantiations fail
- Reproduces with no provider configured, no `_AI_DEFAULTS_` set, and
  with `_AI_DEFAULTS_` registered — provider state is irrelevant
- `%AI.Provider.Create("anthropic", {...})` works correctly in the same
  container, so the LLM bridge itself is functional

## How to reproduce

In HSCUSTOM:

```objectscript
set s = ##class(AnyClassExtending.AIAgentSkill).%New()
```

ZTRAP fires immediately. After the failure,
`##class(%AI.System).getlasterror()` returns a payload containing

```
JsonError: Failed to parse skill JSON: trailing characters at line 1 column N
```

`N` increments by 1 for each new attempt because the OREF id printed
into the buffer grows by one character. That correlation is the
diagnostic fingerprint of this bug.

## Root cause

`%AI.Agent.Skill.%OnNew` is implemented as

```objectscript
Method %OnNew(externalData As %DynamicObject = "") As %Status
{
    If $ISOBJECT(externalData) {
        Set ..IsExternal   = 1
        Set ..ExternalData = externalData
    }
    Set skillObject = ..%ToJSON()
    Set ..%token = $ZF(-6, $$$IrisLLMLibrary, $$$LLMBUILDSKILLFROMJSON, skillObject)
    Return $$$OK
}
```

Two relevant facts:

1. The Skill class overrides `%ToJSON` to return a `%DynamicObject`
   (not a JSON string). The override's return type is declared as
   `%DynamicObject` and the implementation builds and returns a `{}`.
2. The Rust function `LLMBUILDSKILLFROMJSON` (op code 66) expects a
   JSON string.

When `$ZF(-6, ..., skillObject)` marshals an OREF, it does not
auto-call `.%ToJSON()` to JSON-serialize it. The marshaler ends up
sending the OREF identity (a small integer string such as `"35"`) to
Rust. The Rust JSON parser successfully parses that integer as a JSON
number value, then chokes on whatever bytes follow it — hence the
"trailing characters at line 1 column N" error, where N is one past
the digit count of the OREF id.

By contrast, `%AI.Provider` does the same kind of call correctly. See
the compiled implementation around lines 649 and 717-718 of the
exported `%AI.Provider.cls`:

```objectscript
Set settingsJson = settings.%ToJSON()       // DynamicObject -> JSON string
Set messagesJson = messages.%ToJSON()
Set optionsJson  = options.%ToJSON()
```

The Provider serializes the DynamicObject to a JSON string before the
$ZF call. Skill does not.

## Impact

Without the workaround:

- No subclass of `%AI.Agent.Skill` can be constructed via `%New()`.
- `%AI.Agent.UseSubAgent("MySkillClass")` fails because internally it
  calls `%New()` on the skill class.
- The router-agent + skills pattern (one main `%AI.Agent` with several
  skill specialists attached as sub-agent tools) cannot be wired up.
- Loading skills from external `SKILL.md` URIs via `GetSkillFromURI` is
  also affected — that path also calls `..%New(externalData)` and
  triggers the same `$ZF` call with the same broken marshaling.

In short, the entire declarative-skill mechanism documented for the
`%AI` framework in this IRIS build is unusable until the workaround is
applied or the framework is patched upstream.

## Workaround in this repo

`AgenticInterop.Skill.Base` (`src/cls/AgenticInterop/Skill/Base.cls`)
inserts itself between `%AI.Agent.Skill` and the nine concrete skills.
It overrides `%OnNew` with a corrected version:

```objectscript
Class AgenticInterop.Skill.Base Extends %AI.Agent.Skill
{

Method %OnNew(externalData As %DynamicObject = "") As %Status
{
    If $ISOBJECT(externalData) {
        Set ..IsExternal   = 1
        Set ..ExternalData = externalData
    }
    Set skillJson = ..%ToJSON().%ToJSON()
    Set ..%token  = $ZF(-6, 1042, 66, skillJson)
    Return $$$OK
}

}
```

Two things to note:

- `..%ToJSON().%ToJSON()` — the first call uses the Skill override and
  returns a `%DynamicObject`. The second call is `%DynamicObject`'s own
  `%ToJSON` and returns a JSON string. That string is what the Rust
  side expects.
- Macro values are inlined: `IrisLLMLibrary` is `1042` and
  `LLMBUILDSKILLFROMJSON` is `66`. The `%AI` include file is not
  visible from `HSCUSTOM`, so `[ IncludeCode = %AI ]` does not resolve
  the macros for user-namespace classes. Macro values were extracted
  from the `%AI.INC` routine inside `%SYS`. For reference:

| Macro                       | Value |
| --------------------------- | ----- |
| `IrisLLMLibrary`            | 1042  |
| `LLMYAMLTODYNAMICOBJECT`    |   64  |
| `LLMFETCHSKILLFROMURI`      |   65  |
| `LLMBUILDSKILLFROMJSON`     |   66  |
| `LLMSKILLTOJSON`            |   67  |
| `LLMSKILLRELEASE`           |   68  |

All nine concrete skill classes now declare
`Extends AgenticInterop.Skill.Base` so that the fix is inherited in
exactly one place.

## Verification

After the workaround, running `do ^SMOKE` in `HSCUSTOM` reports

```
=== AgenticInterop scaffold smoke test ===

Default skill list (from SkillLoader):
  AgenticInterop.Skill.Productions
  AgenticInterop.Skill.DTL
  AgenticInterop.Skill.BPL
  AgenticInterop.Skill.RoutingRules
  AgenticInterop.Skill.HL7v2
  AgenticInterop.Skill.FHIRR4
  AgenticInterop.Skill.SDA
  AgenticInterop.Skill.RestInProductions
  AgenticInterop.Skill.ESBPattern

Per-skill instantiation:
  OK  Productions          TOOLS=...Production            SUMMARY=523b  INSTRUCTIONS=19774b
  OK  DTL                  TOOLS=...Transform             SUMMARY=435b  INSTRUCTIONS=12717b
  OK  BPL                  TOOLS=...Transform             SUMMARY=494b  INSTRUCTIONS=13197b
  OK  RoutingRules         TOOLS=...Production            SUMMARY=464b  INSTRUCTIONS=13778b
  OK  HL7v2                TOOLS=...Testing               SUMMARY=415b  INSTRUCTIONS=4666b
  OK  FHIRR4               TOOLS=...Testing               SUMMARY=433b  INSTRUCTIONS=3055b
  OK  SDA                  TOOLS=...Testing               SUMMARY=445b  INSTRUCTIONS=2608b
  OK  RestInProductions    TOOLS=...Production            SUMMARY=407b  INSTRUCTIONS=5525b
  OK  ESBPattern           TOOLS=...Production,...Transform SUMMARY=452b INSTRUCTIONS=8239b

ToolSet stubs:
  OK  AgenticInterop.ToolSet.Production
  OK  AgenticInterop.ToolSet.Transform
  OK  AgenticInterop.ToolSet.Testing
  OK  AgenticInterop.ToolSet.Catalog

Agent class:
  OK  AgenticInterop.Agent.HealthInterop

=== Smoke test complete ===
```

Each skill receives a positive Rust skill token from
`LLMBUILDSKILLFROMJSON`, confirming the JSON round-trip succeeded.

## Secondary YAML-parser gotcha

While verifying the workaround, one skill (BPL) failed at a different
spot — the `GetMetadata` method that converts XData `SUMMARY` YAML to a
DynamicObject via `LLMYAMLTODYNAMICOBJECT`:

```
JsonError: JSON parsing/serialization error: YAML parse error:
mapping values are not allowed in this context at line 2 column 152
```

The cause was an unquoted colon inside the `description:` value
(`... orchestration: synchronous/asynchronous ...`). The Rust YAML
parser interprets the second colon as a key/value separator. Fix is to
wrap descriptions that contain colons in double quotes:

```yaml
description: "Author... orchestration: synchronous/async..."
```

This is not a framework bug, just a YAML-authoring rule, but it is
worth flagging because the failure mode looks similar and the
`<%AICore>JsonError` prefix is identical.

## When this can be removed

When InterSystems patches `%AI.Agent.Skill.%OnNew` to JSON-serialize
the DynamicObject before passing it to `$ZF`, the workaround is no
longer needed. Removal is a one-line change per skill: switch the
`Extends` target back to `%AI.Agent.Skill` and delete `Base.cls`. The
behavior is otherwise identical — Base does nothing other than
correcting the `$ZF` argument.

A WRC ticket should reference:

- IRIS for Health build 2026.2 AI 162.0 (linux/aarch64)
- Class `%AI.Agent.Skill`, method `%OnNew`, line that calls
  `$ZF(-6, $$$IrisLLMLibrary, $$$LLMBUILDSKILLFROMJSON, skillObject)`
- Compare with `%AI.Provider` which calls `.%ToJSON()` on the
  DynamicObject before passing to `$ZF`
- Reproduces with `##class(<any subclass>).%New()` in any namespace
