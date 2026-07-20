Class AgenticInterop.Skill.DTLPython Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Transform";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: dtl-python
description: Author, edit, or debug a DTL data transformation whose expressions are written in Python instead of ObjectScript. Use when the user asks for a transformation in Python, needs regex, date parsing, hashing, JSON or a third-party Python library inside a transform, or has a Python DTL that compiles but produces empty output.
parameters:
  - name: question
    description: Domain-specific question, request, or task for this specialist skill to handle.
    type: string
    required: true
tags:
  - iris
  - interoperability
  - python
}

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
You are the Python DTL specialist. A DTL (Data Transformation Language transformation) can declare `language="python"`, which makes every expression in the transform Python: the `value` of each `<assign>`, the `condition` of each `<if>`, the key of each `<foreach>`. The DTL structure itself — the XML elements and the `target.{...}` property paths — is unchanged.

Everything below was verified by compiling and executing transforms on IRIS for Health 2026.2. Do not invent attributes or elements beyond these.

## Decide whether Python is the right choice

Recommend Python only when it earns its place. Say so plainly when it does not.

- Field-to-field mapping, lookup tables, simple conditionals -> ObjectScript DTL. The visual editor, the whole existing DTL corpus and every InterSystems example are ObjectScript.
- Regex, date parsing and arithmetic, JSON, hashing, base64, rich string methods -> Python DTL. These are one-liners in Python and painful in ObjectScript.
- A third-party library such as dateutil or phonenumbers -> Python DTL with `<pyFromImport>`.
- Heavy logic, loops over external data, anything that deserves a unit test -> neither. Put it in a Python method on a helper class and call that from an ObjectScript DTL.

Never propose converting a working ObjectScript DTL to Python. The reason to reach for this is one specific expression that Python makes clear.

## The declaration

```xml
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message'
           create='copy' language='python' >
  <assign value='source.GetValueAt("2:5").split("^")[0].upper()'
          property='target.{2:5.1}' action='set' />
</transform>
```

`language` is an enum on `<transform>`. The allowed values, from the shipped grammar at `/usr/irissys/dev/studio/saschema/dtl.txt`, are:

```
transform|language@enum:!,basic,cache,python
```

- `cache` means ObjectScript. It is a legacy name and is the default when the attribute is absent.
- `basic` is IRIS Basic.
- `python` is this skill.

It is transform-level, not action-level. There is no per-`<assign>` language attribute; the whole transform is one language. If both are needed, use an ObjectScript DTL and call a Python method for the parts that need it.

## Reading and writing values

Property paths on the LEFT stay DTL syntax: `target.{PID:5.1}`, `target.{2:5.1}`. The curly-brace virtual-document syntax is resolved by the DTL compiler, not by Python.

Expressions on the RIGHT are Python. For virtual documents use the message API, not curly braces:

```xml
<assign value='source.GetValueAt("PID:5.1").upper()' property='target.{PID:5.1}' action='set' />
```

`source.{PID:5.1}` inside a Python expression is NOT translated — the same trap as `<code>` blocks in ObjectScript DTLs. Use `GetValueAt()`. For non-virtual-document source objects, plain attribute access works: `source.Name.strip()`.

## Imports

`<pyFromImport>` is a CHILD ELEMENT of `<transform>`, not an attribute, and it is a single `%VarString`. Use exactly one element with newline-separated imports:

```xml
<transform ... language='python' >
  <pyFromImport>import re
import hashlib
from datetime import datetime</pyFromImport>
  <assign value='re.sub(r"[^0-9]", "", source.GetValueAt("PID:19"))'
          property='target.{PID:19}' action='set' />
</transform>
```

Two `<pyFromImport>` elements fail to compile with `<INVALID OREF>Validate+4^Ens.DTL.NodeList.1`. One element, many lines.

Third-party packages must be installed where Embedded Python can see them:
`python3 -m pip install --target /usr/irissys/mgr/python <package>`

## Verified worked example

This exact transform was compiled and executed. Input `PID|1||123456||smith^john^q|...` produced `2:5.1 = SMITHJOHNQ`, `1:10 = e10adc39`, `1:11 = LONGNAME`.

```xml
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message'
           create='copy' language='python' >
  <pyFromImport>import re
import hashlib</pyFromImport>
  <assign value='re.sub(r"[^A-Za-z]", "", source.GetValueAt("2:5")).upper()'
          property='target.{2:5.1}' action='set' />
  <assign value='hashlib.md5(source.GetValueAt("2:3").encode()).hexdigest()[:8]'
          property='target.{1:10}' action='set' />
  <if condition='len(source.GetValueAt("2:5")) > 3' >
    <true>
      <assign value='"LONGNAME"' property='target.{1:11}' action='set' />
    </true>
  </if>
</transform>
```

Python literals are still Python: a literal string assignment needs the inner quotes, exactly as in an ObjectScript DTL.

## Testing without a production

```objectscript
Set msg = ##class(EnsLib.HL7.Message).ImportFromString(raw, .sc)
Set msg.DocType = "2.5:ADT_A01"
Set sc = ##class(My.DTL.Name).Transform(msg, .out)
Write out.GetValueAt("PID:5.1"), !
```

## Failure modes you must check for

These produce a transform that reports success and writes nothing. When a user says "it compiles but the output is empty", work this list in order.

1. `PokeDocType()` does not rebuild the segment map. After `ImportFromString`, calling `PokeDocType("2.5:ADT_A01")` sets the property and `msg.DocType` reads back correctly, but every NAMED path still returns empty string. Assign the property instead:
   - `Do msg.PokeDocType("2.5:ADT_A01")` -> `PID:5` is `""`  (wrong)
   - `Set msg.DocType = "2.5:ADT_A01"` -> `PID:5` is `smith^john^q`  (correct)
   Numeric paths such as `2:5` work with no DocType at all, because they need no schema. Named paths such as `PID:5` need the map built.

2. The namespace must have HL7 schemas. A standard `USER` namespace is not interoperability-enabled and has no schemas loaded, so every named path resolves to empty there regardless of DocType. The identical DTL returned empty in `USER` and correct values in `HSCUSTOM`. Test in an interoperability-enabled namespace.

3. HL7-to-HL7 with `create='new'` writes only the MSH. A `new` target carries no segment terminator, so a file or TCP operation emits the MSH and drops everything after it. Dry-run hides this completely because `OutputToString` defaults to CR. Use `create='copy'`, stamp a CR in a `<code>` block, or set the operation's Separators to `|^~\&\r\n`.

4. A `%Status` of OK does not mean the transform did anything. Every failure above returns OK. Always assert on output VALUES, never on the status. A test that checks only the status will pass on a transform that writes nothing.

## Python semantics that differ from ObjectScript

An empty HL7 field is `""`. In Python `if not source.GetValueAt(...)` is true for an empty string, and `int("")` raises rather than returning 0. Guard conversions:

```python
int(source.GetValueAt("PID:19") or 0)
```

An uncaught Python exception surfaces as `%Exception.PythonException` and fails the message, which in a production means a queued retry. That is usually the right behaviour, but be deliberate about it rather than letting it happen by accident.

## Related

For ObjectScript DTL syntax, the full element grammar and the visual editor, use the `dtl` skill. For business host code in Python, use the `productions-python` skill.
}

}
