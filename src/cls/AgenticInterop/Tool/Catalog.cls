/// %AI.Tool source for cross-cutting introspection: %Dictionary
/// metadata, IRIS namespace context, %Status decoding, error-code
/// lookup, glossary, and Detailed-API-Index search.
///
/// Each public ClassMethod is auto-discovered by the %AI framework as
/// a tool — the method name is the tool name the LLM sees.
///
/// Composed into AgenticInterop.ToolSet.Catalog via the framework's
/// `<Include Class="..."/>` directive (Pattern 5 in the ai-hub-tools
/// skill). The two RAG tools — SearchEns and SearchHs — are
/// registered separately at runtime by AgenticInterop.Catalog.Attach.
Class AgenticInterop.Tool.Catalog Extends %AI.Tool
{

/// Resolve the namespace this tool call should run against. Internal.
ClassMethod TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// Read %Dictionary metadata for a single InterSystems class so the
/// agent can ground its proposals in the real property + method
/// surface instead of guessing. CALL THIS whenever the user asks
/// "what does X do", "what fields does Y have", "is there a method
/// to Z on class W", or any time the agent is about to recommend a
/// class name and wants to confirm the signature first.
///
/// className: fully-qualified class (e.g., "EnsLib.HL7.Adapter.TCPInboundAdapter").
///
/// Returns: { ok, className, namespace, exists, super, description,
/// abstract, properties:[{name,type,required,description}],
/// methods:[{name,classmethod,returnType,description}],
/// totalProperties, totalMethods }. Read-only, fast, safe.
ClassMethod DescribeClass(className As %String) As %DynamicObject
{
    Set out = {}
    Set out.className = className
    Set targetNs = ..TargetNs()
    Set out.namespace = targetNs
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        If '##class(%Dictionary.CompiledClass).%ExistsId(className) {
            Set out.ok = 0
            Set out.exists = 0
            Set out.error = "Class not found in namespace " _ targetNs _ ": " _ className
            Quit
        }
        Set cls = ##class(%Dictionary.CompiledClass).%OpenId(className)
        Set out.exists = 1
        Set out.super = cls.Super
        Set out.description = $extract(cls.Description, 1, 1000)
        Set out.abstract = ''(cls.Abstract)
        Set out.properties = []
        Set propCount = 0
        Set propIter = cls.Properties
        For i=1:1:propIter.Count() {
            Set p = propIter.GetAt(i)
            If p.Internal { Continue }
            Set propObj = {}
            Set propObj.name = p.Name
            Set propObj.type = p.Type
            Set propObj.required = ''(p.Required)
            Set propObj.description = $extract(p.Description, 1, 240)
            Do out.properties.%Push(propObj)
            Set propCount = propCount + 1
        }
        Set out.methods = []
        Set methodCount = 0
        Set methodIter = cls.Methods
        For i=1:1:methodIter.Count() {
            Set m = methodIter.GetAt(i)
            If m.Internal { Continue }
            If $extract(m.Name, 1, 1) = "%" { Continue }
            Set methodObj = {}
            Set methodObj.name = m.Name
            Set methodObj.classmethod = ''(m.ClassMethod)
            Set methodObj.returnType = m.ReturnType
            Set methodObj.description = $extract(m.Description, 1, 240)
            Do out.methods.%Push(methodObj)
            Set methodCount = methodCount + 1
        }
        Set out.totalProperties = propCount
        Set out.totalMethods = methodCount
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Return the IRIS namespace this chat turn is logically scoped to —
/// the X-IRIS-Namespace header the chat surface attaches to every
/// request, fall back to $namespace if absent. CALL THIS FIRST in
/// every conversation so subsequent tool calls operate on the right
/// data set.
///
/// Returns: { ok, namespace, dispatchNamespace, source }. Read-only.
ClassMethod GetUserNamespace() As %DynamicObject
{
    Set out = {}
    Set targetNs = ""
    Try { Set targetNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If targetNs '= "" {
        Set out.namespace = targetNs
        Set out.source = "X-IRIS-Namespace header"
    } Else {
        Set out.namespace = $namespace
        Set out.source = "dispatch fallback"
    }
    Set out.dispatchNamespace = $namespace
    Set out.ok = 1
    Quit out
}

/// List the IRIS namespaces the authenticated user can read. Filters
/// out system + temp namespaces. CALL THIS for "what namespaces are
/// there", "what can I switch to".
///
/// Returns: { ok, current, namespaces:[name], total }. Read-only.
ClassMethod ListUserAccessibleNamespaces() As %DynamicObject
{
    Set out = {}
    Set out.current = $namespace
    Set out.namespaces = []
    Try { Set targetNs = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) Set out.current = $select(targetNs'="":targetNs, 1:$namespace) } Catch  {}
    Try {
        Set systemNs = ",%SYS,%ALL,IRISSYS,IRISTEMP,IRISLIB,IRISLOCALDATA,HSLIB,HSSYS,HSSYSLOCALTEMP,DOCBOOK,"
        Set list = ""
        Do List^%SYS.NAMESPACE(.list)
        Set count = 0
        Set ns = $order(list(""))
        While ns '= "" {
            If systemNs '[ ("," _ $zconvert(ns, "U") _ ",") {
                Try {
                    New $namespace
                    Set $namespace = ns
                    Do out.namespaces.%Push(ns)
                    Set count = count + 1
                } Catch  { /* no read perm — skip */ }
            }
            Set ns = $order(list(ns))
        }
        Set seen = 0
        Set iter = out.namespaces.%GetIterator()
        While iter.%GetNext(.k, .v) { If v = out.current { Set seen = 1 Quit } }
        If 'seen, out.current '= "" { Do out.namespaces.%Push(out.current) Set count = count + 1 }
        Set out.total = count
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Decode a serialized IRIS %Status value into a human-readable
/// message. CALL THIS whenever the user pastes something that looks
/// like a status — typically a string that starts with "0 " followed
/// by an error code and arguments — and asks "what does this mean"
/// or "why is this failing".
///
/// status: the serialized %Status string.
///
/// Returns: { ok, text }. Read-only.
ClassMethod ExplainStatus(status As %String) As %DynamicObject
{
    Set out = {}
    Try {
        If $get(status) = "" {
            Set out.ok = 0
            Set out.error = "Pass `status` (serialized %Status string)."
            Quit
        }
        Set out.text = $extract($system.Status.GetErrorText(status), 1, 1500)
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Look up a numeric IRIS error code from the InterSystems Error
/// Reference seed (~4500 codes). CALL THIS when the user asks about
/// a specific numeric code — "what does 5001 mean", "I'm seeing
/// ERROR #83 — what is that".
///
/// Symbolic Ensemble tokens like "<Ens>ErrFailureTimeout" are macros,
/// not numeric codes; use SearchEns with the token name for those.
///
/// code: the numeric error code (positive integer).
///
/// Returns: { ok, code, message, category, source, error? }.
/// Read-only.
ClassMethod LookupErrorCode(code As %Integer) As %DynamicObject
{
    Set out = {}
    Try {
        If $get(code) = "" {
            Set out.ok = 0
            Set out.error = "Pass `code` (numeric)."
            Quit
        }
        If '$isvalidnum(code) || (+code <= 0) {
            Set out.ok = 0
            Set out.error = "Code must be a positive integer. Got: '" _ code _ "'."
            Quit
        }
        Set out.code = +code
        Set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT TOP 1 Message, Category FROM AgenticInterop_Reference.ErrorCode WHERE Code = ?",
            +code)
        If rs.%Next() {
            Set out.found = 1
            Set out.message = rs.%Get("Message")
            Set out.category = rs.%Get("Category")
            Set out.source = "InterSystems Error Reference (seeded)"
        } Else {
            Set out.found = 0
            Set status = $system.Status.Error(+code)
            Set out.message = $extract($system.Status.GetErrorText(status), 1, 1500)
            Set out.source = "$system.Status fallback (code not in seeded reference)"
        }
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Look up a term in the InterSystems Glossary of Terms (~250 entries
/// covering ObjectScript, SQL, Objects, Java, Productions, FHIR, and
/// Health concepts). CALL THIS when the user uses an unfamiliar IRIS
/// term and asks "what is X" or "define X".
///
/// Match: exact normalized lookup first, then fuzzy LIKE on Term and
/// Definition for the top 3 related entries.
///
/// term: the term to look up (e.g., "abstract class", "$ZF function").
///
/// Returns: { ok, term, found, category?, definition?, related? }.
/// Read-only.
ClassMethod LookupGlossaryTerm(term As %String) As %DynamicObject
{
    Set out = {}
    Try {
        If $get(term) = "" {
            Set out.ok = 0
            Set out.error = "Pass `term` (string)."
            Quit
        }
        Set out.term = term
        Set norm = $zconvert($zstrip(term, "<>W"), "L")
        Set norm = $piece(norm, "^", 1)
        Set norm = $piece(norm, " ", 1)
        Set normSan = ""
        For i=1:1:$length(norm) {
            Set ch = $extract(norm, i)
            If ((ch >= "a") && (ch <= "z")) || ((ch >= "0") && (ch <= "9")) || (ch = "$") {
                Set normSan = normSan _ ch
            }
        }
        Set norm = normSan
        Set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT TOP 1 Term, Category, Definition FROM AgenticInterop_Reference.GlossaryTerm WHERE TermKey = ?",
            norm)
        If rs.%Next() {
            Set out.found = 1
            Set out.category = rs.%Get("Category")
            Set out.definition = rs.%Get("Definition")
            Set out.match = "exact"
            Set out.ok = 1
            Quit
        }
        Set out.related = []
        Set patt = "%" _ $zconvert(term, "L") _ "%"
        Set rs2 = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT TOP 3 Term, Category, Definition FROM AgenticInterop_Reference.GlossaryTerm "_
            "WHERE LOWER(Term) LIKE ? OR LOWER(Definition) LIKE ? ORDER BY LENGTH(Term)",
            patt, patt)
        While rs2.%Next() {
            Set hit = {}
            Set hit.term = rs2.%Get("Term")
            Set hit.category = rs2.%Get("Category")
            Set hit.definition = $extract(rs2.%Get("Definition"), 1, 800)
            Do out.related.%Push(hit)
        }
        If out.related.%Size() > 0 {
            Set out.found = 0
            Set out.match = "fuzzy"
        } Else {
            Set out.found = 0
            Set out.match = "none"
            Set out.message = "No entry for '" _ term _ "' in the InterSystems Glossary. Try SearchEns for class-name questions or SearchApiIndex for API topics."
        }
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Search the seeded Detailed API Index (~80 topic pages: HL7,
/// FHIR, Productions, Lookup Tables, etc.). CALL THIS when the user
/// asks "is there an API for X", "what tools does IRIS provide for Y".
///
/// query: search terms (e.g., "HL7 messages", "FHIR repository").
/// k:     number of results to return (1-20, default 5).
///
/// Returns: { ok, query, results:[{title, slug, summary, snippet,
/// namespaces, where}], total }. Read-only.
ClassMethod SearchApiIndex(query As %String, k As %Integer = 5) As %DynamicObject
{
    Set out = {}
    Set out.results = []
    Try {
        Set q = $get(query)
        If q = "" {
            Set out.ok = 0
            Set out.error = "Pass `query` (string). Optional `k` (1-20)."
            Quit
        }
        If '$isvalidnum(k) || (+k < 1) { Set k = 5 }
        If +k > 20 { Set k = 20 }
        Set out.query = q
        Set patt = "%" _ $zconvert(q, "L") _ "%"
        Set sql = "SELECT TOP " _ k _ " Title, Slug, Summary, Body, Namespaces, "
        Set sql = sql _ "CASE WHEN LOWER(Title)   LIKE ? THEN 1 "
        Set sql = sql _ "     WHEN LOWER(Summary) LIKE ? THEN 2 "
        Set sql = sql _ "     WHEN LOWER(Body)    LIKE ? THEN 3 "
        Set sql = sql _ "     ELSE 9 END AS Rank "
        Set sql = sql _ "FROM AgenticInterop_Reference.ApiTopic "
        Set sql = sql _ "WHERE LOWER(Title) LIKE ? OR LOWER(Summary) LIKE ? OR LOWER(Body) LIKE ? "
        Set sql = sql _ "ORDER BY Rank, LENGTH(Title)"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql,
            patt, patt, patt, patt, patt, patt)
        Set total = 0
        While rs.%Next() {
            Set hit = {}
            Set hit.title = rs.%Get("Title")
            Set hit.slug = rs.%Get("Slug")
            Set hit.summary = $extract(rs.%Get("Summary"), 1, 400)
            Set hit.namespaces = rs.%Get("Namespaces")
            Set rank = +rs.%Get("Rank")
            Set hit.where = $case(rank, 1:"title", 2:"summary", 3:"body", :"unknown")
            Set body = rs.%Get("Body")
            Set bl = $zconvert(body, "L")
            Set ql = $zconvert(q, "L")
            Set p = $find(bl, ql)
            If p > 0 {
                Set start = $select(p - 80 > 1: p - 80, 1: 1)
                Set hit.snippet = "…" _ $extract(body, start, p + 200) _ "…"
            } Else {
                Set hit.snippet = $extract(body, 1, 280)
            }
            Do out.results.%Push(hit)
            Set total = total + 1
        }
        Set out.total = total
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

}
