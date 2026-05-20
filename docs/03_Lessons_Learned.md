# Agentic Health Interoperability - Lessons Learned

> Version 1.0 | May 2026 | InterSystems AI Hub  
> Findings from the experimental build of an Agentic AI Copilot on IRIS for Health

---

## 1. Introduction

This document captures the key lessons learned during the experimental build of the Agentic Health Interoperability project on InterSystems IRIS for Health 2026.2 with the %AI Framework (build 162.0). These findings cover framework bugs, performance optimizations using Vector Search, and strategies for reducing token consumption and improving response speed.

---

## 2. %AI Framework Bugs and Extensions

The solution is built entirely on the %AI Framework primitives (Agent, MCP, ToolSet, Tool, Skill, KnowledgeBase). Where we extended the framework, it was to work around specific bugs -- not to replace framework functionality. These extensions are documented here as recommendations for InterSystems.

### Framework Bugs

### 2.1 BUG: %AI.Agent.Skill %OnNew $ZF marshaling error

**Severity**: Blocker (prevents skill instantiation)  
**Affected class**: `%AI.Agent.Skill`

**Problem**: When instantiating a skill via `%New()`, the parent `%OnNew` method passes a `%DynamicObject` to `$ZF` (the Foreign Function Interface call to the Rust LLM bridge). The `$ZF` call expects a JSON string, not an object reference, and throws a `<FUNCTION>` error.

**Root cause**: The `%OnNew` method in `%AI.Agent.Skill` calls `$ZF(-1, IrisLLMLibrary, LLMBUILDSKILLFROMJSON, config)` where `config` is a `%DynamicObject`. The Rust bridge expects the serialized JSON string `config.%ToJSON()`.

**Workaround**: Created `AgenticInterop.Skill.Base` that overrides `%OnNew`:
```objectscript
Method %OnNew(config As %DynamicObject) As %Status
{
    ; Serialize to JSON string before $ZF call
    Set jsonStr = config.%ToJSON()
    Set sc = $ZF(-1, 1042, 66, jsonStr)
    ; ... (literal macro values: IrisLLMLibrary=1042, LLMBUILDSKILLFROMJSON=66)
}
```

**Recommendation**: Fix `%AI.Agent.Skill.%OnNew` to serialize the DynamicObject to a JSON string before the `$ZF` call.

### 2.2 BUG: Bedrock tool-result round-trip hang

**Severity**: Blocker (prevents multi-turn tool use with Bedrock)  
**Affected path**: `%AI.Agent` -> Rust LLM bridge -> AWS Bedrock API

**Problem**: When the agent calls a tool and receives the result, the Rust bridge hangs indefinitely when sending the tool result back to the Bedrock Converse API. The hang occurs below the ObjectScript API surface -- the `StreamChat()` or `Run()` call never returns.

**Reproduction**: Any agent with tools, configured to use Bedrock (any model, any endpoint). The first LLM call succeeds, the tool executes successfully, but the second LLM call (with tool result) hangs.

**Tested configurations**:
- Claude Sonnet 4 via Bedrock (us-east-1)
- Claude Haiku 3.5 via Bedrock (us-east-1)
- Cross-region inference endpoint
- Direct region endpoint

**Workaround**: Use Anthropic direct (not via Bedrock) as the runtime LLM provider. The same agent + tools work correctly with the Anthropic API.

**Recommendation**: Investigate the Rust LLM bridge's Bedrock Converse API integration. The tool_result message format may differ from what the bridge sends. WRC ticket recommended.

### 2.3 ISSUE: %FromJSON instance method returns empty string

**Severity**: Medium (causes silent data loss)  
**Affected class**: `%DynamicObject`, `%DynamicAbstractObject`

**Problem**: Calling `{}.%FromJSON(jsonString)` returns `""` (empty string) instead of a populated object. The instance form of `%FromJSON` appears non-functional on this IRIS build.

**Workaround**: Use the class-method form:
```objectscript
Set obj = ##class(%DynamicAbstractObject).%FromJSON(jsonString)
```

### 2.4 ISSUE: $get() on %DynamicObject properties throws <INVALID CLASS>

**Severity**: Medium (causes runtime errors in otherwise valid code)

**Problem**: `$get(dynamicObj.propertyName, defaultValue)` throws `<INVALID CLASS>` when the property doesn't exist. The ObjectScript `$get` function doesn't handle `%DynamicObject` property access the way it handles local variables.

**Workaround**: Use `$select` with `%IsDefined`:
```objectscript
Set value = $select(obj.%IsDefined("propName"): obj.propName, 1: defaultValue)
```
Or capture to a local variable first:
```objectscript
Set local = obj.propName
Set value = $get(local, defaultValue)
```

### 2.5 ISSUE: CSP UseSession deadlock on REST endpoints

**Severity**: High (causes 401 errors on second request in same browser session)

**Problem**: When `UseSession=1` (the default) on a `%CSP.REST` class, the CSP gateway validates the CSRF token on every request. When the REST API is called from an iframe (the admin UI embedded in the Interop Editor), the second request in the same browser session gets a 401 because the CSRF token validation races with the iframe's credential handling.

**Workaround**: Set `UseSession=0` on every REST dispatch class. Each request is stateless and authenticated independently via Bearer token or Basic auth.

### 2.6 ISSUE: %OpenId returns stale data in cross-process polling

**Severity**: High (causes infinite polling loops)

**Problem**: `%OpenId(id)` uses a process-local OREF cache. In a polling loop where Process A writes a row and Process B polls with `%OpenId`, Process B's cache returns the stale pre-update state indefinitely. The poll never sees the update.

**Workaround**: Use SQL queries for cross-process polling:
```objectscript
Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status FROM MyTable WHERE ID = ?", id)
```

---

## 3. ObjectScript Language Gotchas

These are not framework bugs but language behaviors that caused significant debugging time during development.

### 3.1 Numeric comparison operators on strings

**Problem**: ObjectScript `>=`, `<=`, `>`, `<` operators are NUMERIC, not string-based. The expression `ch >= "A" && ch <= "Z"` always evaluates to true because both sides coerce to 0.

**Solution**: Use `$ascii()` for character range comparisons:
```objectscript
Set code = $ascii(ch)
If (code >= 65) && (code <= 90) { /* uppercase letter */ }
```

### 3.2 QUIT inside try/catch blocks

**Problem**: `quit value` only works at the method top level. Inside a block (if/for/while/try/catch), `quit` exits the block without a return value. This causes silent method exits with no return value.

**Solution**: Capture to a local variable and quit after the block:
```objectscript
Try {
    Set result = ..DoWork()
    Set sc = $$$OK
} Catch ex {
    Set sc = ex.AsStatus()
}
Quit sc  ; at method level, not inside the block
```
Or use `RETURN value` which works from anywhere.

### 3.3 Comment syntax inside method bodies

**Problem**: `//` comments work at the class level but cause `#1002` compile errors inside `ClassMethod`/`Method` bodies on some IRIS versions.

**Solution**: Use `;` (semicolon) for comments inside method bodies:
```objectscript
ClassMethod MyMethod() As %Status
{
    ; This is a valid comment inside a method body
    Set x = 1
    Quit $$$OK
}
```

---

## 4. Vector Search: Improving Velocity

### 4.1 The embedding quality problem

The initial catalog builder indexed every class by dumping its full `%Dictionary.ClassDefinition` content -- including auto-generated accessor methods, storage definitions, and parameter boilerplate. In a 384-dimensional embedding space, this structural noise drowned out the semantic signal (class description, purpose, key behaviors).

**Result**: Searches for "HL7 TCP service" returned generic base classes instead of `EnsLib.HL7.Service.TCPService` because the relevant description text was a tiny fraction of the indexed content.

### 4.2 The fix: curated prose over raw metadata

We rewrote the catalog builder to extract only semantically meaningful content:

| Before (noisy) | After (curated) |
|---|---|
| Full class dump including storage, indices, XData | Class name + description + superclass + key parameters |
| Auto-generated accessor methods (Get/Set/IsValid) | Removed entirely |
| Parameter definitions with internal flags | Only parameters the user would configure |
| Inherited method signatures from 5 levels of superclass | Only overridden methods with their descriptions |

**Impact**: Search relevance improved dramatically. "HL7 TCP inbound service" now returns `EnsLib.HL7.Service.TCPService` as the top result with a cosine similarity of 0.85+.

### 4.3 Query path discovery

The documented `EMBEDDING()` SQL function does NOT work with the bundled FastEmbed embedding model. After extensive testing, the only working query path is:

```objectscript
Set args = {"query": "HL7 TCP service", "k": 5}
Set result = ##class(%AI.ToolMgr).ExecuteTool("search_ens", args)
```

This routes through the `%AI.RAG.KnowledgeBase` internal search pipeline which correctly handles FastEmbed embeddings.

### 4.4 Don't rebuild what you don't need to

Once the catalog is indexed with good embeddings, DO NOT re-index on every application start. The vector index is persistent. Rebuilds should only happen when:
- IRIS is upgraded (new classes may be available)
- The embedding model changes
- The document format changes

For all other cases, tune queries (topK, filters) rather than rebuilding the index.

---

## 5. Reducing Token Consumption and Improving Speed

### 5.1 The problem

A naive agent configuration with all framework tools exposed consumed 15K+ tokens per request just for the tool catalog. Complex multi-turn tasks could exceed 100K tokens before producing a useful result. Response times were 30-60 seconds per turn.

### 5.2 Strategy 1: ToolFilter policy (saved ~3K tokens per request)

The %AI Framework exposes default tools (FileSystem, SQL, ShellTools) that are irrelevant for healthcare interoperability tasks. The `AgenticInterop.Policy.ToolFilter` strips these before each LLM call.

**Before**: 57 tools in the LLM catalog (~15K tokens for tool definitions)  
**After**: 42 tools in the LLM catalog (~10K tokens for tool definitions)  
**Savings**: ~5K tokens per request, plus the LLM makes fewer irrelevant tool calls

### 5.3 Strategy 2: Concise tool descriptions (saved ~2K tokens)

Early tool descriptions were verbose explanations. We rewrote them as imperative contracts:

**Before** (verbose):
```
This tool allows you to list all the productions that are currently defined 
in the active namespace. It will return an array of objects containing the 
production name, its current status (running, stopped, suspended, troubled), 
and the number of business items configured within the production. You can 
use this to discover what productions exist before creating new ones.
```

**After** (concise):
```
List all productions in the current namespace. Returns: name, status 
(running/stopped/suspended/troubled), item count.
```

The concise version conveys the same information in 80% fewer tokens. Multiply by 42 tools and the savings are significant.

### 5.4 Strategy 3: No markdown formatting in responses (eliminated rendering bugs)

The chat UI renders plain text. Markdown bold (`**text**`) and italic (`*text*`) appear as literal asterisks. Headers (`## text`) appear as hash marks. We instructed the agent to use plain prose with line breaks and `-` bullets instead.

This also reduces token count slightly (no formatting tokens) and improves readability in the chat UI.

### 5.5 Strategy 4: Monitor callback with token budget (prevented runaway costs)

`AgenticInterop.Agent.Monitor` enforces a 50K token budget per turn. When the budget is exceeded, the monitor triggers a graceful stop and the agent summarizes partial results. This prevents:
- Infinite tool-call loops (agent calls the same tool repeatedly)
- Excessive catalog searches (agent searches 10 times instead of using the first result)
- Runaway conversation depth (agent keeps asking clarifying questions instead of acting)

### 5.6 Strategy 5: Breaking complex tasks into multiple short turns

Instead of one massive prompt that tries to do everything ("build a production, add hosts, create DTLs, send test messages, validate"), we structured the agent to work in phases:

1. **Research phase**: Search catalogs, introspect schemas (read-only, fast)
2. **Proposal phase**: Present a plan to the user, ask for approval (no tool calls)
3. **Build phase**: Execute the plan step by step (mutating tools, confirmation gates)
4. **Validation phase**: Run PostBuildValidation, send test messages
5. **Report phase**: Summarize what was done

Each phase is a short LLM turn (< 30 seconds, < 20K tokens). The user sees progress after each phase rather than waiting 90 seconds for a monolithic response.

### 5.7 Strategy 6: System prompt compactness

The agent's system prompt is kept under 2K tokens. It defines:
- Persona (1 paragraph)
- Formatting rules (3 lines: no bold, no headers, use `-` bullets)
- Behavioral guardrails (always search before creating, always validate after building)

Domain knowledge is NOT in the system prompt -- it lives in Skills which are only loaded when the LLM calls them. This means a simple "list my productions" request doesn't pay the token cost of 12 skill definitions.

### 5.8 Results

| Metric | Before optimization | After optimization |
|---|---|---|
| Tool catalog tokens | ~15K | ~10K |
| System prompt tokens | ~5K | ~2K |
| Simple query (list productions) | ~25K total tokens | ~15K total tokens |
| Complex task (build production) | ~120K total tokens | ~50K total tokens |
| Simple query latency | 8-12 seconds | 3-5 seconds |
| Complex task latency | 90+ seconds (often timeout) | 45-60 seconds (across 3-4 turns) |

---

## 6. Additional Findings

### 6.1 CSP gateway caching of static files

The CSP gateway sets `Expires: +1h` on static files served from `/agentic/*`. During development, this caused the browser to serve stale JavaScript and CSS after deployments. 

**Solution**: Cache-busting via `Date.now()` query parameter in the HTML entry point:
```html
<script>
  var v = Date.now();
  document.write('<link rel="stylesheet" href="admin.css?v=' + v + '">');
</script>
```

### 6.2 SDA3 as the universal pivot

The most powerful architectural insight for the Transformation and Mapping Catalog was that SDA3 is the universal pivot format in IRIS for Health. Every external format (HL7 v2, FHIR R4, CDA, X12) maps through SDA3. This means:
- Field-level mappings can be pre-computed as a three-column join: Source -> SDA3 -> Target
- Any format pair can be traced by chaining two half-maps through SDA3
- Coverage gaps (fields that arrive but don't continue) become immediately visible

### 6.3 HL7 v2 programmatic mappings are NOT DTL

The HL7 -> SDA3 direction is implemented in ObjectScript methods (`HS.Gateway.HL7.HL7ToSDA3`), not in DTL classes. This required a completely different extraction approach -- parsing ObjectScript source for `Set` statements targeting SDA properties, rather than walking DTL XData action nodes.

### 6.4 Vanilla JS vs. React for the admin UI

The original plan called for React 18 + TypeScript + Vite. During implementation, we switched to vanilla JavaScript for the admin UI because:
- The IRIS CSP gateway serves static files; a build step (Vite) adds deployment complexity
- The admin UI is a configuration tool, not a complex interactive application
- Vanilla JS eliminates framework bundle size (React + ReactDOM = 130KB gzipped)
- The chat UI has similar requirements and works well as vanilla JS

The trade-off: no component reuse patterns, no type safety, manual DOM manipulation. For a larger team or more complex UI, React would be the right choice.

### 6.5 The overlay pattern for configuration persistence

The "class-as-data" model (using `%Dictionary.*` APIs to manipulate class definitions) created a tension between "shipped defaults" and "user customizations." IPM `zpm load` recompiles shipped classes, overwriting any manual edits.

The overlay pattern resolves this:
- Shipped class parameters define defaults
- Override tables (`AgentOverride`, `MCPOverride`, `ToolSetOverride`) store user edits
- At build time, the overlay merges overrides on top of compiled defaults
- "Reset to defaults" deletes the override row

This pattern is reusable for any IRIS application where configuration is stored in class definitions but must survive package upgrades.

---

## 7. Summary of Recommendations for InterSystems

| # | Category | Recommendation | Impact |
|---|---|---|---|
| 1 | Framework bug | Fix `%AI.Agent.Skill.%OnNew` $ZF marshaling | Eliminates need for Skill.Base workaround |
| 2 | Framework bug | Fix Bedrock tool-result round-trip hang | Enables Bedrock as a production runtime provider |
| 3 | API fix | Fix `%DynamicObject.%FromJSON()` instance method | Eliminates silent data loss |
| 4 | API fix | Document that `$get()` doesn't work on `%DynamicObject` properties | Prevents runtime errors |
| 5 | Documentation | Document `%AI.ToolMgr.ExecuteTool()` as the RAG query path | SQL `EMBEDDING()` doesn't work with FastEmbed |
| 6 | Performance | Add ToolFilter-like policy to framework defaults | Prevents token waste from generic tools |
| 7 | Performance | Expose token usage metrics from Rust bridge | Enables application-level token budgeting |
| 8 | CSP | Add `Cache-Control: no-cache` option for development web apps | Eliminates static file caching during development |
