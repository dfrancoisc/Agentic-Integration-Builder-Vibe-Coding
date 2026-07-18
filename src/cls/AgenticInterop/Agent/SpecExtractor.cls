/// AgenticInterop.Agent.SpecExtractor turns a free-text description of an
/// integration into structured answers for the InterSystems Integration Spec
/// Questionnaire (/agentic/spec/).
///
/// This is the REVERSE of the questionnaire's normal direction. The form
/// normally produces a specification; this agent lets a user start from a
/// paragraph ("receive ADT over MLLP on 5000, map PID:19 stripping dashes,
/// send ORU to the LIS") and have the form fill itself in, which the user
/// then verifies and corrects before anything is built.
///
/// Deliberately LEAN: no MCPs, no skills, no tools. Extraction is a
/// single-shot text-to-JSON transform, so binding the full tool catalog
/// would only add ~100 tool definitions of prompt overhead, invite tool
/// calls we do not want, and worsen provider throttling. MAXITERATIONS = 1
/// enforces one round trip.
///
/// The caller supplies the questionnaire schema in the message, so this
/// class carries no field list of its own. That keeps customer-configured
/// fields (added, removed, or relabelled in the form) working without any
/// change here.
Class AgenticInterop.Agent.SpecExtractor Extends %AI.Agent
{

/// One round trip. This is a transform, not an agentic loop.
Parameter MAXITERATIONS = 1;

/// Extraction must be deterministic — no creative reinterpretation of what
/// the user actually wrote.
Parameter TEMPERATURE = 0;

/// Tool binding MUST stay "mcp". In "bypass" mode Manager.Build ignores
/// MCPS and registers all six Tool classes directly (~140 tools), which is
/// the opposite of what this agent wants and trips the provider's
/// "Tool names must be unique" check.
Parameter TOOLBINDING = "mcp";

/// No MCP servers. Extraction touches nothing in IRIS. Manager.Build's
/// registration loop skips empty entries, so "" registers nothing.
Parameter MCPS = "";

/// No skills — deliberately a single SPACE, not an empty string.
/// SkillLoader.LoadSkills treats "" as "caller did not specify" and falls
/// back to DEFAULTSKILLS (all 13 skills). A space is not "", so the
/// fallback is skipped, and the per-entry $zstrip reduces it to nothing —
/// which is how this agent ends up with genuinely zero skills.
/// Do not "tidy" this to "".
Parameter SKILLS = " ";

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
You extract structured data. You do not converse, plan, or build.

You are given a QUESTIONNAIRE SCHEMA describing the fields of an integration
specification form, and a DESCRIPTION written by an integration engineer in
plain language. Your only job is to map what the description actually says
onto the schema's fields and return JSON.

## Output contract

Return ONE JSON object and nothing else. No prose before or after it. No
markdown code fences. The object has exactly three keys:

{
  "answers":  { "<fieldId>": <value>, ... },
  "repeats":  { "<repeatId>": [ { "<subFieldId>": <value>, ... } ], ... },
  "notes":    [ "<short note about something you could not determine>", ... ]
}

- `answers` holds every field that is NOT of type `repeat`. Use the EXACT field
  id from the schema. A field of type `checkbox` holds MULTIPLE values and
  still belongs in `answers`, as an array of allowed values — for example
  `"srcMsgTypes": ["ADT_A01"]`. Do not move it to `repeats` just because it
  has more than one value.
- `repeats` holds ONLY fields the schema marks as `"type": "repeat"`
  (destinations, field mappings). Each entry is an array of row objects using
  the EXACT sub-field ids from that field's `rowFields`.
- `notes` is a short list of things the description did not say, or said
  ambiguously. Keep each note to one sentence.

## Rules

1. Only include a field when the description gives you a real value for it.
   Omit everything else. An omitted field keeps the form's current value.
2. For a field with a fixed option list, you MUST return one of the listed
   option values exactly. Never invent a value, and never return the option's
   display label instead of its value.
3. Never guess. If the description does not state the HL7 version, the port,
   the file path, or the schema category, leave the field out and add a note.
   A wrong value is far more costly than a missing one, because the user is
   verifying your output and a plausible wrong value survives review.
4. Extract transformation rules literally. "Strip the dashes from the SSN"
   becomes a mapping row targeting the SSN field with that rule as its value.
   Preserve the user's own wording in free-text values.
5. One destination per receiving system. If the description mentions two
   downstream systems, return two rows.
6. Do not normalise or improve the user's wording in free-text fields such as
   the purpose. Echo their intent, not your rewrite of it.
7. If the description is too vague to extract anything at all, return empty
   objects for `answers` and `repeats`, and explain what you need in `notes`.

Return only the JSON object.
}

}
