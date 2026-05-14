/// Testing ToolSet — initial cut (Phase 4). Two read-only validators
/// the agent can call to ground answers about specific HL7 v2 (Health
/// Level Seven version 2) messages or FHIR R4 (Fast Healthcare
/// Interoperability Resources release 4) resources the user pastes
/// into chat.
///
/// Roadmap (not yet built): send_hl7, send_fhir, send_sda3,
/// send_dicom, send_mft_file (mutating — gated), validate_hl7_semantics
/// (profile-driven), compare_messages, test_rest_endpoint,
/// get_test_message_samples, get_iris_fhir_capability_statement.
/// See docs/TOOLS.md "ToolSet.Testing".
/// %AI.Tool source for the Testing toolset. Each public ClassMethod
/// is auto-discovered by the framework as a tool — the method name
/// is the tool name the LLM sees. Composed into AgenticInterop.ToolSet.
/// Testing via <Include Class="AgenticInterop.Tool.Testing"/> (Pattern 5
/// of the ai-hub-tools skill).
Class AgenticInterop.Tool.Testing Extends %AI.Tool
{


/// Resolve the active namespace for this tool call. Internal helper.
ClassMethod %TargetNs() As %String [ Internal ]
{
    Set ns = ""
    Try { Set ns = $get(%request.CgiEnvs("HTTP_X_IRIS_NAMESPACE")) } Catch  {}
    If ns = "" { Set ns = $namespace }
    Quit ns
}

/// Parse a raw HL7 v2 message string and report whether it is
/// well-formed plus its key headers (message type, control id,
/// version, sending and receiving applications, segment count).
/// Optionally runs the framework's schema validator if the message
/// version is known. CALL THIS whenever the user pastes an HL7 v2
/// message and asks "what's wrong with this", "is this valid",
/// "parse this", or anything that needs to inspect message structure.
///
/// message: the HL7 v2 message text. CR or CRLF segment separators
/// both work. The function will trim leading whitespace before parsing.
///
/// Returns: { ok, valid, messageType, controlId, version, sendingApp,
/// receivingApp, segmentCount, schemaValid?, schemaError?, error? }.
/// Read-only.
ClassMethod ValidateHL7Structure(message As %String) As %DynamicObject
{
    Set out = {}
    If $get(message) = "" {
        Set out.ok = 0
        Set out.valid = 0
        Set out.error = "Empty message — pass the raw HL7 v2 text as `message`."
        Quit out
    }
    Try {
        Set sc = $$$OK
        Set msg = ##class(EnsLib.HL7.Message).ImportFromString(message, .sc)
        If $$$ISERR(sc) {
            Set out.ok = 1
            Set out.valid = 0
            Set out.error = $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.ok = 1
        Set out.valid = 1
        // EnsLib.HL7.Message uses position-based paths ("1:9" = segment
        // 1 (MSH), field 9) when no DocType / schema is bound. The
        // schema-aware "MSH:9" path returns "" without a DocType, so
        // we go straight to the position form, which always works.
        Try { Set out.messageType = msg.GetValueAt("1:9") } Catch  { Set out.messageType = "" }
        Try { Set out.controlId   = msg.GetValueAt("1:10") } Catch { Set out.controlId   = "" }
        Try { Set out.version     = msg.GetValueAt("1:12") } Catch { Set out.version     = "" }
        Try { Set out.sendingApp   = msg.GetValueAt("1:3") } Catch { Set out.sendingApp   = "" }
        Try { Set out.receivingApp = msg.GetValueAt("1:5") } Catch { Set out.receivingApp = "" }
        Try { Set out.segmentCount = msg.SegCount } Catch { Set out.segmentCount = 0 }
        Try {
            Set scSchema = msg.Validate("dmsrt")
            If $$$ISERR(scSchema) {
                Set out.schemaValid = 0
                Set out.schemaError = $extract($system.Status.GetErrorText(scSchema), 1, 600)
            } Else {
                Set out.schemaValid = 1
            }
        } Catch  { /* schema check not possible — leave properties unset */ }
    } Catch ex {
        Set out.ok = 0
        Set out.valid = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Validate that a FHIR R4 (Fast Healthcare Interoperability Resources
/// release 4) JSON resource is well-formed. Performs structural checks
/// the LLM can act on: parses the JSON, requires a known resourceType,
/// checks for an id, surfaces meta and reference shapes. Does NOT call
/// the IRIS FHIR Server endpoint (that requires a configured FHIR
/// repository); for terminology / profile validation, the user runs
/// the resource through their FHIR Server's $validate operation.
///
/// resource: a FHIR R4 JSON resource — either an already-parsed
/// %DynamicObject or a JSON string. Strings are parsed with
/// %DynamicAbstractObject.%FromJSON (the instance form is broken on
/// this IRIS build).
///
/// Returns: { ok, valid, resourceType, id?, hasMeta, references,
/// issues:[{severity,code,location,details}] }. Read-only.
ClassMethod ValidateFHIRResource(resource) As %DynamicObject
{
    Set out = {}
    Set out.issues = []
    Try {
        Set rs = resource
        If '$isobject(rs) {
            If $get(rs) = "" {
                Set out.ok = 0
                Set out.valid = 0
                Set out.error = "Empty resource — pass a FHIR R4 JSON object."
                Quit
            }
            Set rs = ##class(%DynamicAbstractObject).%FromJSON(rs)
        }
        Set rt = ""
        If rs.%IsDefined("resourceType") { Set rt = rs.resourceType }
        Set out.resourceType = rt
        Set ok = 1
        If rt = "" {
            Set issue = {}
            Set issue.severity = "error"
            Set issue.code = "structure"
            Set issue.location = "resourceType"
            Set issue.details = "Missing required 'resourceType' property."
            Do out.issues.%Push(issue)
            Set ok = 0
        }
        Set known = ",Patient,Practitioner,PractitionerRole,Organization,Encounter,Condition,Observation,DiagnosticReport,ServiceRequest,MedicationRequest,MedicationAdministration,MedicationStatement,Medication,AllergyIntolerance,Immunization,Procedure,Composition,DocumentReference,Bundle,OperationOutcome,Coverage,EligibilityRequest,EligibilityResponse,Claim,ClaimResponse,Questionnaire,QuestionnaireResponse,RelatedPerson,Location,Appointment,Schedule,Slot,Goal,CarePlan,CareTeam,Specimen,Binary,List,Provenance,AuditEvent,Subscription,MessageHeader,Parameters,"
        If rt '= "", known '[ ("," _ rt _ ",") {
            Set issue = {}
            Set issue.severity = "warning"
            Set issue.code = "code-invalid"
            Set issue.location = "resourceType"
            Set issue.details = "Unknown FHIR R4 resourceType: " _ rt _ ". Verify against the spec."
            Do out.issues.%Push(issue)
        }
        If rs.%IsDefined("id") {
            Set out.id = rs.id
        }
        Set out.hasMeta = ''rs.%IsDefined("meta")
        // Bundle: check entries
        If rt = "Bundle", rs.%IsDefined("entry") {
            Set entryCount = 0
            Set iter = rs.entry.%GetIterator()
            While iter.%GetNext(.k, .v) { Set entryCount = entryCount + 1 }
            Set out.bundleEntries = entryCount
        }
        Set out.references = ..%CountReferences(rs)
        Set out.valid = ok
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.valid = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Count occurrences of a `reference` field anywhere in the resource
/// tree. Cheap structural signal — answers "how connected is this
/// resource to others". Internal helper.
ClassMethod %CountReferences(node) As %Integer [ Internal ]
{
    Set count = 0
    If '$isobject(node) { Quit count }
    Try {
        Set iter = node.%GetIterator()
        While iter.%GetNext(.k, .v) {
            If k = "reference", '$isobject(v) { Set count = count + 1 Continue }
            If $isobject(v) { Set count = count + ..%CountReferences(v) }
        }
    } Catch  { /* not iterable — skip */ }
    Quit count
}

/// Schema-aware HL7 v2 validation. Binds the message to a DocType
/// (a known schema like "2.5:ADT_A01" or whatever the user names)
/// and runs the full IsValid() check, which catches missing required
/// fields, wrong field cardinality, and unknown segments. CALL THIS
/// when validate_hl7_structure passed but the user wants stronger
/// guarantees — "is this strictly valid for ADT^A01 v2.5".
///
/// message: the HL7 v2 message text.
/// docType: optional DocType (e.g., "2.5:ADT_A01"). If empty, the
///   tool tries to derive it from MSH-12 and MSH-9.
///
/// Returns: { ok, valid, docType, schemaError?, error? }. Read-only.
ClassMethod ValidateHL7Semantics(message As %String, docType As %String = "") As %DynamicObject
{
    Set out = {}
    If $get(message) = "" {
        Set out.ok = 0
        Set out.valid = 0
        Set out.error = "Empty message — pass the raw HL7 v2 text as `message`."
        Quit out
    }
    Try {
        Set sc = $$$OK
        Set msg = ##class(EnsLib.HL7.Message).ImportFromString(message, .sc)
        If $$$ISERR(sc) {
            Set out.ok = 1
            Set out.valid = 0
            Set out.error = $system.Status.GetErrorText(sc)
            Quit
        }
        Set bound = docType
        If bound = "" {
            // Try to derive from MSH-12 (version) + MSH-9 (message type).
            Set ver = ""
            Set mtype = ""
            Try { Set ver = msg.GetValueAt("1:12") } Catch  {}
            Try { Set mtype = msg.GetValueAt("1:9") } Catch  {}
            // Normalize "ADT^A01" -> "ADT_A01"
            Set mt = $piece(mtype, "^", 1)
            Set evt = $piece(mtype, "^", 2)
            If mt '= "", evt '= "", ver '= "" {
                Set bound = ver _ ":" _ mt _ "_" _ evt
            }
        }
        If bound '= "" {
            Try { Set msg.DocType = bound } Catch  {}
        }
        Set out.docType = msg.DocType
        // EnsLib.EDI.Document.Validate(spec) is the schema validator.
        // Spec letters: d=DocType, m=message structure, s=segments,
        // r=required fields, t=data types. + = strict, - = lenient.
        // "dmsrt" with no qualifiers does the standard pass.
        Set scSchema = $$$OK
        Try { Set scSchema = msg.Validate("dmsrt") } Catch ex { Set scSchema = ex.AsStatus() }
        If $$$ISERR(scSchema) {
            Set out.ok = 1
            Set out.valid = 0
            Set out.schemaError = $extract($system.Status.GetErrorText(scSchema), 1, 2000)
        } Else {
            Set out.ok = 1
            Set out.valid = 1
        }
    } Catch ex {
        Set out.ok = 0
        Set out.valid = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Diff two HL7 v2 messages segment-by-segment and field-by-field.
/// CALL THIS when the user pastes two messages and asks "what's
/// different", "compare these", or "did the transform change X".
/// Read-only.
///
/// messageA / messageB: HL7 v2 message text (CR or CRLF segment seps).
///
/// Returns: { ok, segmentCountA, segmentCountB, sameSegments,
/// addedInB, removedFromA, fieldDiffs:[{segment, segIndex, field, a, b}], total }.
ClassMethod CompareMessages(messageA As %String, messageB As %String) As %DynamicObject
{
    Set out = {}
    Set out.fieldDiffs = []
    If $get(messageA) = "" || ($get(messageB) = "") {
        Set out.ok = 0
        Set out.error = "Pass both `messageA` and `messageB`."
        Quit out
    }
    Try {
        Set scA = $$$OK Set scB = $$$OK
        Set msgA = ##class(EnsLib.HL7.Message).ImportFromString(messageA, .scA)
        Set msgB = ##class(EnsLib.HL7.Message).ImportFromString(messageB, .scB)
        If $$$ISERR(scA) {
            Set out.ok = 0
            Set out.error = "messageA failed to parse: " _ $system.Status.GetErrorText(scA)
            Quit
        }
        If $$$ISERR(scB) {
            Set out.ok = 0
            Set out.error = "messageB failed to parse: " _ $system.Status.GetErrorText(scB)
            Quit
        }
        Set out.segmentCountA = msgA.SegCount
        Set out.segmentCountB = msgB.SegCount
        Set sameSegs = 0
        Set diffCount = 0
        Set maxSeg = $select(msgA.SegCount > msgB.SegCount: msgA.SegCount, 1: msgB.SegCount)
        For i=1:1:maxSeg {
            Set segA = "" Set segB = ""
            // OutputToString gives the raw "PID|1||100||DOE^JOHN..."
            // text — what we need for field-by-field comparison.
            // GetValueAt("0") returns only the segment id (the "PID"
            // prefix), which would make every same-id segment look
            // identical and skip the actual field diff.
            Try { Set segA = msgA.GetSegmentAt(i).OutputToString("|^~\&") } Catch  {}
            Try { Set segB = msgB.GetSegmentAt(i).OutputToString("|^~\&") } Catch  {}
            // Identify segment by its 3-char id (MSH, PID, OBR, etc.).
            Set segIdA = $piece(segA, "|", 1)
            Set segIdB = $piece(segB, "|", 1)
            If segA = segB { Set sameSegs = sameSegs + 1 Continue }
            // Walk fields. HL7 segment fields are pipe-separated.
            Set partsA = $LENGTH(segA, "|")
            Set partsB = $LENGTH(segB, "|")
            Set maxFld = $select(partsA > partsB: partsA, 1: partsB)
            For f=1:1:maxFld {
                Set vA = $piece(segA, "|", f)
                Set vB = $piece(segB, "|", f)
                If vA = vB { Continue }
                Set d = {}
                Set d.segment  = $select(segIdA'="":segIdA, 1:segIdB)
                Set d.segIndex = i
                Set d.field    = f - 1   // HL7 fields are 1-indexed AFTER the segment id; field 0 = segment id itself
                Set d.a = $extract(vA, 1, 200)
                Set d.b = $extract(vB, 1, 200)
                Do out.fieldDiffs.%Push(d)
                Set diffCount = diffCount + 1
                If diffCount > 200 { Quit }
            }
            If diffCount > 200 { Quit }
        }
        Set out.sameSegments  = sameSegs
        Set out.addedInB      = $select(msgB.SegCount > msgA.SegCount: msgB.SegCount - msgA.SegCount, 1: 0)
        Set out.removedFromA  = $select(msgA.SegCount > msgB.SegCount: msgA.SegCount - msgB.SegCount, 1: 0)
        Set out.total = diffCount
        Set out.ok = 1
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Push an HL7 v2 message into a configured Business Service so the
/// production processes it as a real inbound message. MUTATING — the
/// send_ prefix triggers the confirmation gate so the user explicitly
/// approves before IRIS routes the message. The Business Service must
/// already exist in the active production.
///
/// message:    raw HL7 v2 text.
/// targetHost: the logical host name of the Business Service (the
///             "Item Name" in the production, NOT the class name).
///
/// Returns: { ok, namespace, target, ack?, response?, error? }.
ClassMethod SendHL7(message As %String, targetHost As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "send_hl7"
    Set out.target = targetHost
    Set targetNs = ..%TargetNs()
    Set out.namespace = targetNs
    If $get(message) = "" || ($get(targetHost) = "") {
        Set out.ok = 0
        Set out.error = "Pass both `message` and `targetHost`."
        Quit out
    }
    New $namespace
    Try { Set $namespace = targetNs } Catch  {
        Set out.ok = 0
        Set out.error = "Cannot access namespace: " _ targetNs
        Quit
    }
    Try {
        Set sc = $$$OK
        Set msg = ##class(EnsLib.HL7.Message).ImportFromString(message, .sc)
        If $$$ISERR(sc) {
            Set out.ok = 0
            Set out.error = "Message failed to parse: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set svc = ""
        Set scSvc = ##class(Ens.Director).CreateBusinessService(targetHost, .svc)
        If $$$ISERR(scSvc) {
            Set out.ok = 0
            Set out.error = "Cannot create business service '" _ targetHost _ "': " _ $system.Status.GetErrorText(scSvc) _ ". Is the production running and the host name correct?"
            Quit
        }
        Set response = ""
        ; HL7 TCP/File/HTTP services override OnProcessInput to handle
        ; raw adapter data ($LIST for TCP, stream for file). Calling
        ; ProcessInput with an EnsLib.HL7.Message causes <LIST> errors.
        ; Use standardOnProcessInput which accepts an HL7.Message
        ; directly and dispatches through the production's routing
        ; chain — same path as adapter-driven messages, minus the wire.
        If svc.%IsA("EnsLib.HL7.Service.Standard") {
            Set scProc = svc.standardOnProcessInput(msg, .response)
        } Else {
            Set scProc = svc.ProcessInput(msg, .response)
        }
        If $$$ISERR(scProc) {
            Set out.ok = 0
            Set out.error = "ProcessInput failed: " _ $system.Status.GetErrorText(scProc)
            Quit
        }
        Set out.ok = 1
        Set out.message = "Sent HL7 message to '" _ targetHost _ "' — " _ msg.SegCount _ " segment(s)."
        If $isobject(response) {
            Try { Set out.ack = response.OutputToString("|^~\&", .scOut) } Catch  { Set out.ack = "(non-HL7 response)" }
        }
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// HTTP POST a FHIR R4 JSON resource to an external FHIR endpoint.
/// MUTATING — the send_ prefix triggers the confirmation gate. Does
/// NOT use a Business Operation; this is a direct %Net.HttpRequest
/// so the agent can probe an arbitrary FHIR server quickly. For
/// production-grade routing, the user should add a FHIR Operation to
/// their production.
///
/// resource:  the FHIR R4 JSON resource (object or string).
/// endpoint:  full URL ending in the resource type
///            (e.g., "https://fhir.example.com/r4/Patient").
/// authBearer: optional Authorization Bearer token; pass "" if open.
///
/// Returns: { ok, status, statusCode, location?, response?, error? }.
ClassMethod SendFHIR(resource, endpoint As %String, authBearer As %String = "") As %DynamicObject
{
    Set out = {}
    Set out.tool = "send_fhir"
    Set out.endpoint = endpoint
    If $get(endpoint) = "" {
        Set out.ok = 0
        Set out.error = "Empty endpoint — pass the full URL."
        Quit out
    }
    Try {
        Set body = resource
        If $isobject(body) { Set body = body.%ToJSON() }
        If $get(body) = "" {
            Set out.ok = 0
            Set out.error = "Empty resource — pass a FHIR R4 JSON object or string."
            Quit
        }
        // Parse URL: https?://host[:port]/path
        Set scheme = $piece(endpoint, "://", 1)
        Set rest = $piece(endpoint, "://", 2, *)
        If rest = "" {
            Set out.ok = 0
            Set out.error = "Invalid URL: " _ endpoint
            Quit
        }
        Set hostPort = $piece(rest, "/", 1)
        Set path = "/" _ $piece(rest, "/", 2, *)
        Set host = $piece(hostPort, ":", 1)
        Set port = $piece(hostPort, ":", 2)
        If port = "" { Set port = $select($zconvert(scheme,"L")="https": 443, 1: 80) }
        Set req = ##class(%Net.HttpRequest).%New()
        Set req.Server = host
        Set req.Port   = port
        Set req.Https  = ''($zconvert(scheme,"L") = "https")
        If req.Https {
            Set req.SSLConfiguration = "DefaultSSL"
            Try { Do ##class(%Net.HttpRequest).%New() } Catch  {}
        }
        Set req.ContentType = "application/fhir+json"
        Do req.SetHeader("Accept", "application/fhir+json")
        If $get(authBearer) '= "" { Do req.SetHeader("Authorization", "Bearer " _ authBearer) }
        Do req.EntityBody.Write(body)
        Set sc = req.Post(path)
        If $$$ISERR(sc) {
            Set out.ok = 0
            Set out.error = "HTTP request failed: " _ $system.Status.GetErrorText(sc)
            Quit
        }
        Set out.statusCode = req.HttpResponse.StatusCode
        Set out.statusLine = req.HttpResponse.StatusLine
        Set out.location   = req.HttpResponse.GetHeader("LOCATION")
        // Read response body (truncate; can be large)
        Set resp = ""
        If $isobject(req.HttpResponse.Data) {
            Try {
                Do req.HttpResponse.Data.Rewind()
                While 'req.HttpResponse.Data.AtEnd, $length(resp) < 4096 {
                    Set resp = resp _ req.HttpResponse.Data.Read(4096)
                }
            } Catch  {}
        }
        Set out.response = $extract(resp, 1, 4096)
        Set out.ok = (out.statusCode >= 200) && (out.statusCode < 300)
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Build a syntactically correct HL7 v2 test message from a docType and
/// a set of named field values. The agent passes field paths (the same
/// schema property names returned by GetHL7SchemaMap) and values, and
/// this tool uses SetValueAt() to place each value at the correct field
/// position in the segment. The agent NEVER needs to count pipe
/// separators — IRIS handles all field positioning.
///
/// CALL THIS instead of hand-crafting raw HL7 message strings. Manual
/// pipe-counting is error-prone (e.g., placing AttendingDoctor at PV1-6
/// instead of PV1-7 due to one missing pipe). This tool eliminates
/// that class of error entirely.
///
/// docType:  schema-qualified message type, e.g. "2.5:ADT_A01".
/// fields:   a JSON object mapping virtual-document property paths to
///           values. Example:
///           {
///             "MSH:SendingApplication": "ADT_SYS",
///             "MSH:MessageType": "ADT^A01^ADT_A01",
///             "MSH:VersionID": "2.5",
///             "PID:PatientIdentifierList(1).IDNumber": "PAT12345",
///             "PID:PatientName(1).FamilyName.Surname": "SMITH",
///             "PID:PatientName(1).GivenName": "JOHN",
///             "PV1:AttendingDoctor(1).IDNumber": "ATT54321",
///             "PV1:AttendingDoctor(1).FamilyName.Surname": "JONES"
///           }
///
/// Returns: { ok, docType, rawMessage, segmentCount, fieldCount,
///            failedFields? }.
/// Read-only (does not persist the message).
ClassMethod BuildHL7TestMessage(docType As %String, fields As %DynamicObject) As %DynamicObject
{
    Set out = {}
    Set out.tool = "build_hl7_test_message"
    If $get(docType) = "" {
        Set out.ok = 0
        Set out.error = "Pass `docType` (e.g. '2.5:ADT_A01') and `fields` (JSON object of field paths to values)."
        Quit out
    }
    If '$isobject($get(fields)) {
        Set out.ok = 0
        Set out.error = "Pass `fields` as a JSON object mapping field paths to values. Example: {""PID:PatientName(1).FamilyName.Surname"": ""SMITH""}."
        Quit out
    }
    Try {
        ; Create the HL7 message object with the specified DocType.
        ; SetValueAt uses the schema to resolve field names to positions.
        Set msg = ##class(EnsLib.HL7.Message).%New()
        Set msg.DocType = docType
        ; Walk the fields object and set each value
        Set iter = fields.%GetIterator()
        Set fieldCount = 0
        Set failedFields = []
        While iter.%GetNext(.path, .value) {
            Set sc = msg.SetValueAt($select($isobject(value):value.%ToJSON(), 1:value), path)
            If sc {
                Set fieldCount = fieldCount + 1
            } Else {
                Set failObj = {}
                Set failObj.path = path
                Set failObj.error = $system.Status.GetErrorText(sc)
                Do failedFields.%Push(failObj)
            }
        }
        ; Auto-fill MSH standard fields if not provided
        If msg.GetValueAt("MSH:FieldSeparator") = "" {
            Do msg.SetValueAt("|", "MSH:FieldSeparator")
        }
        If msg.GetValueAt("MSH:EncodingCharacters") = "" {
            Do msg.SetValueAt("^~\&", "MSH:EncodingCharacters")
        }
        If msg.GetValueAt("MSH:DateTimeOfMessage") = "" {
            Do msg.SetValueAt($translate($zdatetime($horolog, 3, 1), "- :", ""), "MSH:DateTimeOfMessage")
        }
        If msg.GetValueAt("MSH:ProcessingID") = "" {
            Do msg.SetValueAt("P", "MSH:ProcessingID")
        }
        If msg.GetValueAt("MSH:MessageControlID") = "" {
            Do msg.SetValueAt("TEST"_$random(999999), "MSH:MessageControlID")
        }
        If msg.GetValueAt("MSH:VersionID") = "" {
            Do msg.SetValueAt($piece(docType, ":", 1), "MSH:VersionID")
        }
        ; Build the raw HL7 string using CR (0x0D) as segment separator
        Set rawMsg = ""
        For i = 1:1:msg.SegCount {
            Set seg = msg.GetSegmentAt(i)
            If $isobject(seg) {
                If rawMsg '= "" Set rawMsg = rawMsg _ $char(13)
                Set rawMsg = rawMsg _ seg.OutputToString()
            }
        }
        Set out.ok = 1
        Set out.docType = docType
        Set out.rawMessage = rawMsg
        Set out.segmentCount = msg.SegCount
        Set out.fieldCount = fieldCount
        If failedFields.%Size() > 0 {
            Set out.failedFields = failedFields
        }
        Set out.hint = "Use this rawMessage value in SendHL7(message, targetHost) to test the production."
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// Build a test HL7 message from named fields AND send it to a
/// production business service in ONE call. This is the PREFERRED
/// way to test an HL7 production — it combines BuildHL7TestMessage
/// and SendHL7 so the agent never needs to hand-craft raw HL7.
///
/// ALWAYS use this instead of SendHL7 for testing. SendHL7 requires
/// a raw HL7 string which the LLM will hand-craft with wrong field
/// positions (e.g., PV1 AttendingDoctor at field 6 instead of 7).
/// This tool uses SetValueAt() internally to place every value at the
/// correct schema position, then immediately sends the message.
///
/// docType:     schema-qualified message type (e.g. "2.5:ADT_A01")
/// fields:      JSON object mapping field paths to values (same as
///              BuildHL7TestMessage)
/// targetHost:  production business service to send to
///
/// Returns: { ok, docType, rawMessage, segmentCount, fieldCount,
///   sendResult: { ok, messages, errors }, hint }
ClassMethod BuildAndSendHL7TestMessage(docType As %String, fields As %DynamicObject, targetHost As %String) As %DynamicObject
{
    Set out = {}
    Set out.tool = "build_and_send_hl7_test_message"
    ; Step 1: Build the message using BuildHL7TestMessage
    Set buildResult = ..BuildHL7TestMessage(docType, fields)
    If 'buildResult.ok {
        Set out.ok = 0
        Set out.error = "Build failed: " _ buildResult.error
        Quit out
    }
    Set out.docType = buildResult.docType
    Set out.rawMessage = buildResult.rawMessage
    Set out.segmentCount = buildResult.segmentCount
    Set out.fieldCount = buildResult.fieldCount
    If buildResult.%IsDefined("failedFields") {
        Set out.failedFields = buildResult.failedFields
    }
    ; Step 2: Send the built message using SendHL7
    If $get(targetHost) = "" {
        Set out.ok = 1
        Set out.hint = "Message built successfully but no targetHost specified. Pass targetHost to also send the message."
        Quit out
    }
    Set sendResult = ..SendHL7(buildResult.rawMessage, targetHost)
    Set out.sendResult = sendResult
    If 'sendResult.ok {
        Set out.ok = 0
        Set out.error = "Message built OK but send failed: " _ sendResult.error
        Set out.hint = "The rawMessage is valid HL7. Check that the production is running and the targetHost name is correct."
        Quit out
    }
    Set out.ok = 1
    Set out.hint = "Message built with correct field positions via SetValueAt() and sent to " _ targetHost _ ". Check the transformed output in the production message trace."
    Quit out
}

}
