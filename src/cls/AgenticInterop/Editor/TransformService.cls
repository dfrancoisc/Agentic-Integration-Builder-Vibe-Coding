/// REST shell for the Transformation Catalog — read-only inventory of all
/// HS.* transformation classes shipped with IRIS for Health, organized by
/// pipeline direction. SDA3 (Summary Document Architecture version 3) is
/// the universal pivot format; every external format (HL7, FHIR, CDA, X12)
/// maps to and from SDA3.
///
///   GET /api/agentic/transforms/inventory — full pipeline inventory
Class AgenticInterop.Editor.TransformService Extends %RegisteredObject
{

/// Returns the full transformation inventory organized by pipeline.
/// Each pipeline contains: id, source format, target format, implementation
/// kind (DTL, Programmatic, XSLT), class count, and the list of classes
/// with parsed source/target data types.
ClassMethod Inventory(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set out = {}
    Set out.ok = 1
    Set out.generatedAt = $zdatetime($now(), 3, 1)
    Set out.hub = "SDA3"
    Set out.formats = ["HL7 v2", "FHIR R4", "FHIR STU3", "CDA", "X12"]
    Set out.pipelines = []

    ; --- Inbound to SDA3 ---
    Do ..BP(out.pipelines, "hl7_to_sda3", "HL7 v2", "SDA3", "Programmatic", "HS.Gateway.HL7.HL7ToSDA3%", "", "none")
    Do ..BP(out.pipelines, "fhir_r4_to_sda3", "FHIR R4", "SDA3", "DTL", "HS.FHIR.DTL.vR4.SDA3.%", "HS.FHIR.DTL.vR4.SDA3.", "fhir.sda")
    Do ..BP(out.pipelines, "fhir_stu3_to_sda3", "FHIR STU3", "SDA3", "DTL", "HS.FHIR.DTL.vSTU3.SDA3.%", "HS.FHIR.DTL.vSTU3.SDA3.", "fhir.sda")
    Do ..BP(out.pipelines, "cda_to_sda3", "CDA", "SDA3", "XSLT", "HS.Doc.Mapping.CDAToSDA%|HS.Doc.Mapping.ImportCDAToSDA%", "", "none")
    Do ..BP(out.pipelines, "x12_to_sda3", "X12", "SDA3", "Programmatic", "HS.Gateway.X12.%ToSDA3%", "", "none")

    ; --- Outbound from SDA3 ---
    Do ..BP(out.pipelines, "sda3_to_fhir_r4", "SDA3", "FHIR R4", "DTL", "HS.FHIR.DTL.SDA3.vR4.%", "HS.FHIR.DTL.SDA3.vR4.", "sda.fhir")
    Do ..BP(out.pipelines, "sda3_to_fhir_stu3", "SDA3", "FHIR STU3", "DTL", "HS.FHIR.DTL.SDA3.vSTU3.%", "HS.FHIR.DTL.SDA3.vSTU3.", "sda.fhir")
    Do ..BP(out.pipelines, "sda3_to_hl7", "SDA3", "HL7 v2", "DTL", "HS.Gateway.SDA3.SDA3ToHL7.%", "HS.Gateway.SDA3.SDA3ToHL7.", "suffix")
    Do ..BP(out.pipelines, "sda3_to_cda", "SDA3", "CDA", "XSLT", "HS.Doc.Mapping.SDAToCDA%|HS.Doc.Mapping.ImportSDAToCDA%", "", "none")
    Do ..BP(out.pipelines, "sda3_to_x12", "SDA3", "X12", "DTL", "HS.Gateway.SDA3.SDA3ToX12.%", "HS.Gateway.SDA3.SDA3ToX12.", "suffix")

    ; Compute totals
    Set total = 0
    Set iter = out.pipelines.%GetIterator()
    While iter.%GetNext(.k, .p) {
        Set total = total + p.count
    }
    Set out.totalClasses = total

    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

/// Build one Pipeline entry and push it onto the array. Queries
/// %Dictionary.ClassDefinition for each pipe-delimited LIKE pattern.
///
/// pPrefix is the fixed portion of the class name to strip before parsing.
/// pMode controls how the remainder is parsed into source/target types:
///   "sda.fhir" — rest = SDAType.FHIRResource (SDA may be multi-part)
///   "fhir.sda" — rest = FHIRResource.SDAType (SDA may be multi-part)
///   "suffix"   — last dot-segment of the rest is the target type
///   "none"     — no per-class type parsing (monolithic classes)
ClassMethod BP(pArr As %DynamicArray, pId As %String, pSrc As %String, pTgt As %String, pKind As %String, pPatterns As %String, pPrefix As %String, pMode As %String) [ Private ]
{
    Set pipeline = {}
    Set pipeline.id = pId
    Set pipeline.source = pSrc
    Set pipeline.target = pTgt
    Set pipeline.kind = pKind
    Set pipeline.classes = []
    Set count = 0

    ; Run query for each pipe-separated LIKE pattern
    For i=1:1:$LENGTH(pPatterns, "|") {
        Set pat = $ZSTRIP($PIECE(pPatterns, "|", i), "<>W")
        If pat = "" { Continue }
        Set sql = "SELECT Name, Description FROM %Dictionary.ClassDefinition WHERE Name LIKE ? ORDER BY Name"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, pat)
        While rs.%Next() {
            Set count = count + 1
            Set name = rs.%Get("Name")
            Set desc = rs.%Get("Description")
            Set cls = {}
            Set cls.name = name
            Set cls.shortName = $PIECE(name, ".", $LENGTH(name, "."))
            If desc '= "" { Set cls.description = $extract(desc, 1, 300) }
            Else  { Set cls.description = "" }
            Set cls.isSubTransform = (name [ "SubTransform") || (name [ "TransformUtil")
            ; Type parsing based on mode
            Set cls.sourceType = ""
            Set cls.targetType = ""
            If (pPrefix '= "") && (pMode '= "none") {
                Set rest = $PIECE(name, pPrefix, 2)
                If rest '= "" {
                    Do ..PT(cls, rest, pMode)
                }
            }
            Do pipeline.classes.%Push(cls)
        }
    }

    Set pipeline.count = count
    Do pArr.%Push(pipeline)
}

/// Extract field-level mappings from a DTL class's XData definition.
/// Parses <assign>, <subtransform>, and <foreach> elements to return
/// individual source-to-target field paths. Non-DTL classes (Programmatic,
/// XSLT) have no XData DTL block; the response indicates that.
///
///   GET /api/agentic/transforms/dtl-fields?class=HS.FHIR.DTL.SDA3.vR4.Allergy.AllergyIntolerance
ClassMethod DTLFields(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set className = $get(%request.Data("class",1))

    Set out = {}
    Set out.ok = 1
    Set out.className = className
    Set out.sourceClass = ""
    Set out.targetClass = ""
    Set out.mappings = []

    If className = "" {
        Set out.ok = 0
        Set out.error = "Missing required parameter: class"
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }

    ; Check class exists
    If '##class(%Dictionary.ClassDefinition).%ExistsId(className) {
        Set out.ok = 0
        Set out.error = "Class not found: " _ className
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }

    ; Open XData DTL
    Set xdataId = className _ "||DTL"
    Set xdata = ##class(%Dictionary.XDataDefinition).%OpenId(xdataId)
    If '$IsObject(xdata) {
        Set out.ok = 0
        Set out.error = "No DTL definition found (class may be programmatic or XSLT)"
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }

    ; Parse XML stream using %XML.TextReader
    Set stream = xdata.Data
    Do stream.Rewind()
    Set sc = ##class(%XML.TextReader).ParseStream(stream, .reader)
    If $system.Status.IsError(sc) {
        Set out.ok = 0
        Set out.error = "Failed to parse DTL XML"
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }

    ; Walk all XML element nodes and extract field-level actions
    While reader.Read() {
        If reader.NodeType '= "element" Continue
        Set tag = reader.LocalName

        If tag = "transform" {
            ; Pull sourceClass / targetClass from the root <transform> element
            For ai = 1:1:reader.AttributeCount {
                Do reader.MoveToAttributeIndex(ai)
                If reader.LocalName = "sourceClass" Set out.sourceClass = reader.Value
                If reader.LocalName = "targetClass" Set out.targetClass = reader.Value
            }
            Do reader.MoveToElement()
        }
        ElseIf tag = "assign" {
            Set m = {}
            Set m.type = "assign"
            Set m.source = ""
            Set m.target = ""
            Set m.action = ""
            For ai = 1:1:reader.AttributeCount {
                Do reader.MoveToAttributeIndex(ai)
                If reader.LocalName = "value" Set m.source = reader.Value
                If reader.LocalName = "property" Set m.target = reader.Value
                If reader.LocalName = "action" Set m.action = reader.Value
            }
            Do reader.MoveToElement()
            ; Derive clean field names by stripping "source." / "target." prefixes
            Set m.sourceField = ..StripObjPrefix(m.source)
            Set m.targetField = ..StripObjPrefix(m.target)
            Do out.mappings.%Push(m)
        }
        ElseIf tag = "subtransform" {
            Set m = {}
            Set m.type = "subtransform"
            Set m.class = ""
            Set m.sourceObj = ""
            Set m.targetObj = ""
            For ai = 1:1:reader.AttributeCount {
                Do reader.MoveToAttributeIndex(ai)
                If reader.LocalName = "class" Set m.class = reader.Value
                If reader.LocalName = "sourceObj" Set m.sourceObj = reader.Value
                If reader.LocalName = "targetObj" Set m.targetObj = reader.Value
            }
            Do reader.MoveToElement()
            Set m.sourceField = ..StripObjPrefix(m.sourceObj)
            Set m.targetField = ..StripObjPrefix(m.targetObj)
            Do out.mappings.%Push(m)
        }
        ElseIf tag = "foreach" {
            Set m = {}
            Set m.type = "foreach"
            Set m.property = ""
            For ai = 1:1:reader.AttributeCount {
                Do reader.MoveToAttributeIndex(ai)
                If reader.LocalName = "property" Set m.property = reader.Value
            }
            Do reader.MoveToElement()
            Do out.mappings.%Push(m)
        }
    }

    Set out.count = out.mappings.%Size()
    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

/// Strip the "source." or "target." prefix from a DTL expression
/// to expose the clean field path. If the expression starts with
/// a function call (##class(...)), returns the full expression.
ClassMethod StripObjPrefix(pExpr As %String) As %String [ Private ]
{
    If $extract(pExpr, 1, 7) = "source." Quit $extract(pExpr, 8, *)
    If $extract(pExpr, 1, 7) = "target." Quit $extract(pExpr, 8, *)
    Quit pExpr
}

/// Parse Types — sets sourceType and targetType on the class object
/// based on the remainder of the class name (after prefix stripping)
/// and the parse mode.
ClassMethod PT(pCls As %DynamicObject, pRest As %String, pMode As %String) [ Private ]
{
    Set n = $LENGTH(pRest, ".")
    If pMode = "sda.fhir" {
        ; rest = SDAType...FHIRResource — last part is FHIR, rest is SDA
        If n > 1 {
            Set pCls.sourceType = $PIECE(pRest, ".", 1, n - 1)
            Set pCls.targetType = $PIECE(pRest, ".", n)
        }
        Else  {
            Set pCls.sourceType = pRest
            Set pCls.targetType = pRest
        }
    }
    ElseIf pMode = "fhir.sda" {
        ; rest = FHIRResource.SDAType... — first part is FHIR, rest is SDA
        Set pCls.sourceType = $PIECE(pRest, ".", 1)
        If n > 1 {
            Set pCls.targetType = $PIECE(pRest, ".", 2, n)
        }
        Else  {
            Set pCls.targetType = pRest
        }
    }
    ElseIf pMode = "suffix" {
        ; rest = some.path.Type — last segment is the target type
        Set pCls.targetType = $PIECE(pRest, ".", n)
        If n > 1 {
            Set pCls.sourceType = $PIECE(pRest, ".", 1, n - 1)
        }
    }
}

/// Extract field-level mappings from HL7 v2 programmatic transforms.
/// Parses the ObjectScript method code for the given SDA type's HL7
/// segment(s) in HS.Gateway.HL7.HL7ToSDA3. Returns the same shape as
/// DTLFields so the UI can join HL7 fields with FHIR DTL fields on
/// the SDA3 property name.
///
///   GET /api/agentic/transforms/hl7-fields?sdaType=Patient
///   GET /api/agentic/transforms/hl7-fields?segment=PID
ClassMethod HL7Fields(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set sdaType = $get(%request.Data("sdaType",1))
    Set segment = $get(%request.Data("segment",1))

    Set out = {}
    Set out.ok = 1
    Set out.hl7 = 1
    Set out.sdaType = sdaType

    ; Resolve SDA type to segment(s) if not given directly
    If segment = "" {
        Set segment = ..HL7SegForSDA(sdaType)
    }

    If segment = "" {
        Set out.ok = 0
        Set out.error = "No HL7 segment mapping for: " _ $select(sdaType'="":sdaType, 1:"(empty)")
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }

    Set out.segment = segment
    Set out.sourceClass = "HS.Gateway.HL7.HL7ToSDA3"
    Set out.targetClass = "SDA3"
    Set out.mappings = []

    ; Parse each segment (comma-separated for multi-segment SDA types)
    For si = 1:1:$L(segment, ",") {
        Set seg = $ZSTRIP($P(segment, ",", si), "<>W")
        If seg = "" Continue
        Do ..ParseHL7Seg(seg, out.mappings)
    }

    Set out.count = out.mappings.%Size()
    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

/// Map an SDA3 type name to the HL7 v2 segment(s) that populate it.
/// Derived from the ..start() calls in HS.Gateway.HL7.HL7ToSDA3 and
/// from knowledge of which PID fields map to which SDA sub-types.
ClassMethod HL7SegForSDA(pType As %String) As %String [ Private ]
{
    ; Direct SDA container types from ..start() calls
    If pType = "Patient" Quit "PID"
    If pType = "Encounter" Quit "PV1,PV2"
    If pType = "Allergy" Quit "AL1,IAM"
    If pType = "Diagnosis" Quit "DG1"
    If pType = "SupportContact" Quit "NK1"
    If pType = "HealthFund" Quit "IN1"
    If pType = "Procedure" Quit "PR1"
    If pType = "Guarantor" Quit "GT1"
    If pType = "Problem" Quit "PRB"
    If pType = "Document" Quit "TXA"
    If pType = "Observation" Quit "OBX"
    If pType = "Vaccination" Quit "RXA"
    If pType = "Appointment" Quit "SCH"

    ; Sub-types of Patient (live inside PID segment)
    If pType = "Address" Quit "PID"
    If pType = "PatientNumber" Quit "PID"
    If pType = "Name" Quit "PID"
    If pType = "ContactInfo" Quit "PID"

    ; Medication-related
    If pType = "Medication" Quit "RXE,RXO,ORC"
    If pType = "LabOrder" Quit "OBR,ORC"
    If pType = "RadOrder" Quit "OBR,ORC"

    ; Sub-types that share a segment with their parent
    If pType [ "CodeTableDetail" Quit "PID"

    ; Fallback: try pType as segment name directly
    Set methodId = "HS.Gateway.HL7.HL7ToSDA3||" _ pType
    If ##class(%Dictionary.MethodDefinition).%ExistsId(methodId) Quit pType

    Quit ""
}

/// Parse one HL7 segment method from HS.Gateway.HL7.HL7ToSDA3 and
/// extract (HL7 field position, SDA element name) pairs. The code
/// uses a consistent pattern:
///
///   #; PID-7 : DateTimeofBirth
///   do ..write(cr_"<BirthTime>"_value_"</BirthTime>")
///
/// For each field comment, we extract ALL XML opening tags in the
/// subsequent write() calls (until the next field comment). This
/// captures sub-properties (City, State, Zip under PID-11) for joins.
ClassMethod ParseHL7Seg(pSeg As %String, pArr As %DynamicArray) [ Private ]
{
    Set methodId = "HS.Gateway.HL7.HL7ToSDA3||" _ pSeg
    Set def = ##class(%Dictionary.MethodDefinition).%OpenId(methodId)
    If '$IsObject(def) Quit

    Set stream = def.Implementation
    Do stream.Rewind()
    Set code = stream.Read(64000)

    ; Strip carriage returns (method streams use CR+LF)
    Set code = $REPLACE(code, $C(13), "")
    Set lineCount = $L(code, $C(10))
    Set curField = ""
    Set curDesc = ""
    Kill seen

    For i = 1:1:lineCount {
        Set line = $P(code, $C(10), i)
        Set trim = $ZSTRIP(line, "<>W")

        ; ── Check for HL7 field comment ──
        ; Pattern: #; PID-7 : DateTimeofBirth
        If ($E(trim, 1, 2) = "#;") {
            Set rest = $ZSTRIP($E(trim, 3, *), "<W")
            ; Must start with segment name and a dash+digit
            Set dashPos = $F(rest, "-")
            If dashPos > 0 {
                Set segPart = $E(rest, 1, dashPos - 2)
                If segPart = pSeg {
                    Set colonPos = $F(rest, ":")
                    If colonPos > 0 {
                        Set pos = $ZSTRIP($E(rest, 1, colonPos - 2), "<>W")
                        Set desc = $ZSTRIP($E(rest, colonPos, *), "<>W")
                        ; Skip meta-comments ("see above", "value from")
                        If desc '= "" && (desc '[ "see ") && (desc '[ "done in") {
                            Set curField = pos
                            Set curDesc = desc
                        }
                    }
                }
            }
        }

        ; ── Look for XML write in current field section ──
        ; Extract ALL leaf XML elements (not just first) so sub-properties
        ; like City, State, Street under PID-11 are all captured for joins.
        If curField '= "" && (trim [ "write(") {
            ; Find pattern: "<TagName>" in the write call
            Set searchStr = """<"
            Set wPos = $F(trim, searchStr)
            While wPos > 0 {
                ; wPos points after "<", extract tag name up to ">"
                Set closeGt = $F(trim, ">", wPos)
                If closeGt = 0 Quit
                Set tagName = $E(trim, wPos, closeGt - 2)
                ; Must start with uppercase A-Z (not closing tag "/")
                Set ch = $A(tagName)
                If (ch >= 65) && (ch <= 90) {
                    ; Skip common structural sub-elements that are not
                    ; meaningful SDA property names for joining
                    Set skip = 0
                    If tagName = "Code" Set skip = 1
                    If tagName = "Description" Set skip = 1
                    If tagName = "SDACodingStandard" Set skip = 1
                    If tagName = "Text" Set skip = 1
                    If tagName = "Type" Set skip = 1
                    If tagName = "SourceFormat" Set skip = 1
                    If 'skip {
                        ; Deduplicate: don't push same field+tag twice
                        Set dupKey = curField _ "|" _ tagName
                        If '$data(seen(dupKey)) {
                            Set seen(dupKey) = 1
                            Set m = {}
                            Set m.sourceField = curField _ " " _ curDesc
                            Set m.targetField = tagName
                            Do pArr.%Push(m)
                        }
                    }
                }
                ; Move past this tag for the next search
                Set wPos = $F(trim, searchStr, closeGt)
            }
        }
    }
}

/// Return the HL7 v2 sub-field position for a known SDA property within
/// a given segment-field. E.g., ("PID-11", "City") → "PID.11.3 City".
/// Returns the original sourceField unchanged if no sub-field is known.
///
/// This knowledge comes from the HL7 v2 XAD/XPN/CX/XTN composite type
/// definitions and how HS.Gateway.HL7.HL7ToSDA3 decomposes them.
ClassMethod EnrichHL7SubField(pSourceField As %String, pSdaProp As %String) As %String [ Private ]
{
    ; Build lookup on first call; cache in process-private global
    If '$data(^||hl7sub) {
        ; PID-3 PatientIdentifierList (CX)
        Set ^||hl7sub("PID-3","Number") = "PID.3.1 ID Number"
        Set ^||hl7sub("PID-3","ISOAssigningAuthority") = "PID.3.4 Assigning Authority"
        Set ^||hl7sub("PID-3","NumberType") = "PID.3.5 Identifier Type Code"

        ; PID-5 PatientName (XPN)
        Set ^||hl7sub("PID-5","FamilyName") = "PID.5.1 Family Name"
        Set ^||hl7sub("PID-5","FamilyNamePrefix") = "PID.5.1.2 Surname Prefix"
        Set ^||hl7sub("PID-5","GivenName") = "PID.5.2 Given Name"
        Set ^||hl7sub("PID-5","MiddleName") = "PID.5.3 Second Name"
        Set ^||hl7sub("PID-5","NameSuffix") = "PID.5.4 Suffix"
        Set ^||hl7sub("PID-5","NamePrefix") = "PID.5.5 Prefix"
        Set ^||hl7sub("PID-5","ProfessionalSuffix") = "PID.5.14 Professional Suffix"
        Set ^||hl7sub("PID-5","FromTime") = "PID.5.12 Effective Date"
        Set ^||hl7sub("PID-5","ToTime") = "PID.5.13 Expiration Date"
        Set ^||hl7sub("PID-5","BlankNameReason") = "PID.5.7 Name Type Code"

        ; PID-9 PatientAlias (XPN — same structure as PID-5)
        Set ^||hl7sub("PID-9","FamilyName") = "PID.9.1 Family Name"
        Set ^||hl7sub("PID-9","GivenName") = "PID.9.2 Given Name"
        Set ^||hl7sub("PID-9","MiddleName") = "PID.9.3 Second Name"

        ; PID-11 PatientAddress (XAD)
        Set ^||hl7sub("PID-11","Street") = "PID.11.1 Street Address"
        Set ^||hl7sub("PID-11","City") = "PID.11.3 City"
        Set ^||hl7sub("PID-11","State") = "PID.11.4 State/Province"
        Set ^||hl7sub("PID-11","Zip") = "PID.11.5 Zip/Postal Code"
        Set ^||hl7sub("PID-11","Country") = "PID.11.6 Country"
        Set ^||hl7sub("PID-11","County") = "PID.11.9 County/Parish"
        Set ^||hl7sub("PID-11","Address") = "PID.11 Address (composite)"
        Set ^||hl7sub("PID-11","Addresses") = "PID.11 Address (repeating)"
        Set ^||hl7sub("PID-11","FromTime") = "PID.11.12 Effective Date"
        Set ^||hl7sub("PID-11","ToTime") = "PID.11.13 Expiration Date"

        ; PID-13/14 Phone (XTN)
        Set ^||hl7sub("PID-13","HomePhoneNumber") = "PID.13.7 Home Phone"
        Set ^||hl7sub("PID-13","MobilePhoneNumber") = "PID.13.7 Mobile Phone"
        Set ^||hl7sub("PID-13","EmailAddress") = "PID.13.4 Email Address"
        Set ^||hl7sub("PID-14","WorkPhoneNumber") = "PID.14.7 Work Phone"
        Set ^||hl7sub("PID-14","EmailAddress") = "PID.14.4 Email Address"
        Set ^||hl7sub("PID-14","ContactInfo") = "PID.14 Contact Info"

        ; NK1 fields (XPN + XAD + XTN)
        Set ^||hl7sub("NK1-2","FamilyName") = "NK1.2.1 Family Name"
        Set ^||hl7sub("NK1-2","GivenName") = "NK1.2.2 Given Name"
        Set ^||hl7sub("NK1-4","Street") = "NK1.4.1 Street Address"
        Set ^||hl7sub("NK1-4","City") = "NK1.4.3 City"
        Set ^||hl7sub("NK1-4","State") = "NK1.4.4 State"
        Set ^||hl7sub("NK1-4","Zip") = "NK1.4.5 Zip"
        Set ^||hl7sub("NK1-4","Country") = "NK1.4.6 Country"

        ; PV1 fields
        Set ^||hl7sub("PV1-3","Code") = "PV1.3.1 Point of Care"
        Set ^||hl7sub("PV1-7","Code") = "PV1.7.1 Attending Doctor ID"
        Set ^||hl7sub("PV1-8","Code") = "PV1.8.1 Referring Doctor ID"
        Set ^||hl7sub("PV1-9","Code") = "PV1.9.1 Consulting Doctor ID"
        Set ^||hl7sub("PV1-17","Code") = "PV1.17.1 Admitting Doctor ID"

        ; GT1 fields (XPN + XAD)
        Set ^||hl7sub("GT1-3","FamilyName") = "GT1.3.1 Family Name"
        Set ^||hl7sub("GT1-3","GivenName") = "GT1.3.2 Given Name"
        Set ^||hl7sub("GT1-5","Street") = "GT1.5.1 Street Address"
        Set ^||hl7sub("GT1-5","City") = "GT1.5.3 City"
        Set ^||hl7sub("GT1-5","State") = "GT1.5.4 State"
        Set ^||hl7sub("GT1-5","Zip") = "GT1.5.5 Zip"

        ; IN1 fields
        Set ^||hl7sub("IN1-4","FamilyName") = "IN1.4.1 Company Name"
        Set ^||hl7sub("IN1-5","Street") = "IN1.5.1 Street Address"
        Set ^||hl7sub("IN1-5","City") = "IN1.5.3 City"
        Set ^||hl7sub("IN1-5","State") = "IN1.5.4 State"
        Set ^||hl7sub("IN1-5","Zip") = "IN1.5.5 Zip"
    }

    ; Extract the segment-field key (e.g., "PID-11" from "PID-11 PatientAddress")
    Set segField = $P(pSourceField, " ", 1)

    ; Look up
    If $data(^||hl7sub(segField, pSdaProp)) {
        Quit $get(^||hl7sub(segField, pSdaProp))
    }

    ; Fallback: return original
    Quit pSourceField
}

/// Rebuild the entire FieldMapping table. Parses HL7 programmatic code
/// and FHIR R4 DTL classes, joins them on normalized SDA key, and
/// persists rows for instant UI retrieval.
///
///   POST /api/agentic/transforms/field-trace/rebuild
ClassMethod RebuildFieldMappings(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set out = {}
    Set out.ok = 1
    Set startTime = $zhorolog

    ; Purge existing rows
    Set sc = ##class(AgenticInterop.Data.FieldMapping).PurgeAll()
    If $system.Status.IsError(sc) {
        Set out.ok = 0
        Set out.error = $system.Status.GetOneErrorText(sc)
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }

    Set totalRows = 0

    ; ── HL7 v2 → SDA3 → FHIR R4 pipeline ──
    ; Get the list of SDA types we can map from HL7
    Set hl7SdaTypes = $LB("Patient","Encounter","Allergy","Diagnosis","SupportContact","HealthFund","Procedure","Guarantor","Problem","Document","Observation","Vaccination","Appointment","Address","PatientNumber","Name","ContactInfo","Medication","LabOrder","RadOrder")

    For ti = 1:1:$LL(hl7SdaTypes) {
        Set sdaType = $LI(hl7SdaTypes, ti)

        ; --- Inbound: HL7 → SDA3 ---
        Set inArr = []
        Set segment = ..HL7SegForSDA(sdaType)
        If segment '= "" {
            For si = 1:1:$L(segment, ",") {
                Set seg = $ZSTRIP($P(segment, ",", si), "<>W")
                If seg '= "" { Do ..ParseHL7Seg(seg, inArr) }
            }
        }

        ; Build inbound lookup: normalized SDA key → row data
        Kill inBySda
        Set iter = inArr.%GetIterator()
        While iter.%GetNext(.idx, .m) {
            Set sdaRaw = m.%Get("targetField")
            Set normKey = $ZCVT(sdaRaw, "L")
            If '$data(inBySda(normKey)) {
                Set inBySda(normKey) = $LB(m.%Get("sourceField"), sdaRaw, segment)
            }
        }

        ; --- Outbound: SDA3 → FHIR R4 ---
        ; Find the DTL class for this SDA type
        Set outDtlClass = ""
        Set dtlPattern = "HS.FHIR.DTL.SDA3.vR4." _ sdaType _ ".%"
        Set sql = "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name LIKE ? AND Name NOT LIKE '%SubTransform%' AND Name NOT LIKE '%TransformUtil%' ORDER BY Name"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, dtlPattern)
        If rs.%Next() {
            Set outDtlClass = rs.%Get("Name")
        }

        ; Parse DTL fields — backward-walk algorithm
        ; SDA3→FHIR DTLs use intermediate vars (value, tmp) between
        ; source.X reads and target.Y writes. For each target.* assign,
        ; walk backwards up to 8 assigns to find the nearest source.X ref.
        Kill outBySda
        If outDtlClass '= "" {
            Set xdataId = outDtlClass _ "||DTL"
            Set xdata = ##class(%Dictionary.XDataDefinition).%OpenId(xdataId)
            If $IsObject(xdata) {
                Set stream = xdata.Data
                Do stream.Rewind()
                Set sc2 = ##class(%XML.TextReader).ParseStream(stream, .reader)
                If $system.Status.IsOK(sc2) {
                    ; First pass: collect all assigns in order
                    Kill dtlAssigns Set dtlIdx = 0
                    While reader.Read() {
                        If reader.NodeType '= "element" Continue
                        If reader.LocalName = "assign" {
                            Set srcVal = "", tgtVal = ""
                            For ai = 1:1:reader.AttributeCount {
                                Do reader.MoveToAttributeIndex(ai)
                                If reader.LocalName = "value" Set srcVal = reader.Value
                                If reader.LocalName = "property" Set tgtVal = reader.Value
                            }
                            Do reader.MoveToElement()
                            Set dtlIdx = dtlIdx + 1
                            Set dtlAssigns(dtlIdx, "src") = srcVal
                            Set dtlAssigns(dtlIdx, "tgt") = tgtVal
                        }
                    }
                    ; Second pass: for each target.* assign, walk back for source.*
                    For i = 1:1:dtlIdx {
                        Set tgtVal = dtlAssigns(i, "tgt")
                        If $E(tgtVal, 1, 7) '= "target." Continue
                        Set tgtField = $E(tgtVal, 8, *)
                        If tgtField = "" Continue
                        ; Skip extension/meta/index/coding internals
                        If tgtField [ "extension" Continue
                        If tgtField [ "meta." Continue
                        If tgtField = "index" Continue
                        If tgtField [ ".system" Continue
                        If tgtField [ ".coding." Continue
                        ; Walk backwards to find nearest source.X reference
                        Set sdaRef = ""
                        Set startJ = i
                        If startJ > 8 Set startJ = i - 8
                        Else  Set startJ = 1
                        For j = i:-1:startJ {
                            Set jSrc = dtlAssigns(j, "src")
                            ; Look for source.PropertyName in the expression
                            Set srcPos = $F(jSrc, "source.")
                            If srcPos > 0 {
                                ; Extract property name (letters + digits only)
                                Set propEnd = srcPos
                                For {
                                    Set ch = $A(jSrc, propEnd)
                                    If ch = -1 Quit
                                    If (ch >= 65) && (ch <= 90) { Set propEnd = propEnd + 1 Continue }
                                    If (ch >= 97) && (ch <= 122) { Set propEnd = propEnd + 1 Continue }
                                    If (ch >= 48) && (ch <= 57) { Set propEnd = propEnd + 1 Continue }
                                    Quit
                                }
                                Set sdaRef = $E(jSrc, srcPos, propEnd - 1)
                                If sdaRef '= "" Quit
                            }
                        }
                        If sdaRef = "" Continue
                        ; Normalize the SDA property name
                        Set normKey = $ZCVT(sdaRef, "L")
                        If '$data(outBySda(normKey)) {
                            Set outBySda(normKey) = $LB(sdaRef, tgtField, outDtlClass)
                        }
                    }
                }
            }
        }

        ; --- Join on normalized SDA key and persist ---
        ; Collect all normalized keys from both sides
        Kill allKeys
        Set k = "" For { Set k = $ORDER(inBySda(k)) Quit:k=""  Set allKeys(k) = "" }
        Set k = "" For { Set k = $ORDER(outBySda(k)) Quit:k=""  Set allKeys(k) = "" }

        Set k = "" For {
            Set k = $ORDER(allKeys(k))
            Quit:k=""

            Set hasIn = $data(inBySda(k))
            Set hasOut = $data(outBySda(k))
            Set status = $select(hasIn&&hasOut:"complete", hasIn:"in-only", 1:"out-only")

            Set obj = ##class(AgenticInterop.Data.FieldMapping).%New()
            Set obj.SourceFormat = "HL7 v2"
            Set obj.TargetFormat = "FHIR R4"
            Set obj.SdaType = sdaType
            Set obj.SdaNormalized = k
            Set obj.Status = status

            If hasIn {
                Set rawSrc = $LI(inBySda(k), 1)
                Set rawSda = $LI(inBySda(k), 2)
                ; Enrich HL7 source with sub-field position
                Set obj.SourceField = ..EnrichHL7SubField(rawSrc, rawSda)
                Set obj.SdaField = rawSda
                Set obj.SourceSegment = $LI(inBySda(k), 3)
                Set obj.SourceClass = "HS.Gateway.HL7.HL7ToSDA3"
            }
            If hasOut {
                If 'hasIn { Set obj.SdaField = $LI(outBySda(k), 1) }
                Set obj.TargetField = $LI(outBySda(k), 2)
                Set obj.TargetClass = $LI(outBySda(k), 3)
            }

            Set sc = obj.%Save()
            If $system.Status.IsOK(sc) { Set totalRows = totalRows + 1 }
        }
    }

    ; ── FHIR R4 → SDA3 → HL7 v2 (reverse direction) ──
    ; Parse FHIR-to-SDA DTLs as inbound, HL7 as outbound
    For ti = 1:1:$LL(hl7SdaTypes) {
        Set sdaType = $LI(hl7SdaTypes, ti)

        ; Inbound: FHIR R4 → SDA3
        ; Pattern: HS.FHIR.DTL.vR4.SDA3.<FhirResource>.<SdaType>
        Set inDtlClass = ""
        Set dtlPattern = "HS.FHIR.DTL.vR4.SDA3.%." _ sdaType
        Set sql = "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name LIKE ? AND Name NOT LIKE '%SubTransform%' AND Name NOT LIKE '%TransformUtil%' ORDER BY Name"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, dtlPattern)
        If rs.%Next() {
            Set inDtlClass = rs.%Get("Name")
        }

        Kill fhirBySda
        If inDtlClass '= "" {
            Set xdataId = inDtlClass _ "||DTL"
            Set xdata = ##class(%Dictionary.XDataDefinition).%OpenId(xdataId)
            If $IsObject(xdata) {
                Set stream = xdata.Data
                Do stream.Rewind()
                Set sc2 = ##class(%XML.TextReader).ParseStream(stream, .reader)
                If $system.Status.IsOK(sc2) {
                    ; Collect all assigns
                    Kill dtlAssigns Set dtlIdx = 0
                    While reader.Read() {
                        If reader.NodeType '= "element" Continue
                        If reader.LocalName = "assign" {
                            Set srcVal = "", tgtVal = ""
                            For ai = 1:1:reader.AttributeCount {
                                Do reader.MoveToAttributeIndex(ai)
                                If reader.LocalName = "value" Set srcVal = reader.Value
                                If reader.LocalName = "property" Set tgtVal = reader.Value
                            }
                            Do reader.MoveToElement()
                            Set dtlIdx = dtlIdx + 1
                            Set dtlAssigns(dtlIdx, "src") = srcVal
                            Set dtlAssigns(dtlIdx, "tgt") = tgtVal
                        }
                    }
                    ; For FHIR→SDA3: target.* is SDA side; walk back for source.*
                    For i = 1:1:dtlIdx {
                        Set tgtVal = dtlAssigns(i, "tgt")
                        If $E(tgtVal, 1, 7) '= "target." Continue
                        Set tgtField = $E(tgtVal, 8, *)
                        If tgtField = "" Continue
                        ; Walk backwards to find nearest source.X reference
                        Set srcRef = ""
                        Set startJ = i
                        If startJ > 8 Set startJ = i - 8
                        Else  Set startJ = 1
                        For j = i:-1:startJ {
                            Set jSrc = dtlAssigns(j, "src")
                            Set srcPos = $F(jSrc, "source.")
                            If srcPos > 0 {
                                Set propEnd = srcPos
                                For {
                                    Set ch = $A(jSrc, propEnd)
                                    If ch = -1 Quit
                                    If (ch >= 65) && (ch <= 90) { Set propEnd = propEnd + 1 Continue }
                                    If (ch >= 97) && (ch <= 122) { Set propEnd = propEnd + 1 Continue }
                                    If (ch >= 48) && (ch <= 57) { Set propEnd = propEnd + 1 Continue }
                                    Quit
                                }
                                Set srcRef = $E(jSrc, srcPos, propEnd - 1)
                                If srcRef '= "" Quit
                            }
                        }
                        If srcRef = "" Continue
                        ; Normalize on SDA target (the target.* field IS the SDA property)
                        Set normKey = $P($P(tgtField, ".", 1), "(", 1)
                        Set normKey = $ZCVT(normKey, "L")
                        If '$data(fhirBySda(normKey)) {
                            Set fhirBySda(normKey) = $LB(srcRef, tgtField, inDtlClass)
                        }
                    }
                }
            }
        }

        ; Outbound: SDA3 → HL7 (reuse ParseHL7Seg but as outbound)
        ; For this direction, HL7 fields ARE the target
        Set outArr = []
        Set segment = ..HL7SegForSDA(sdaType)
        If segment '= "" {
            For si = 1:1:$L(segment, ",") {
                Set seg = $ZSTRIP($P(segment, ",", si), "<>W")
                If seg '= "" { Do ..ParseHL7Seg(seg, outArr) }
            }
        }
        Kill hl7BySda
        Set iter = outArr.%GetIterator()
        While iter.%GetNext(.idx, .m) {
            Set sdaRaw = m.%Get("targetField")
            Set normKey = $ZCVT(sdaRaw, "L")
            If '$data(hl7BySda(normKey)) {
                Set hl7BySda(normKey) = $LB(sdaRaw, m.%Get("sourceField"), segment)
            }
        }

        ; Join
        Kill allKeys
        Set k = "" For { Set k = $ORDER(fhirBySda(k)) Quit:k=""  Set allKeys(k) = "" }
        Set k = "" For { Set k = $ORDER(hl7BySda(k)) Quit:k=""  Set allKeys(k) = "" }

        Set k = "" For {
            Set k = $ORDER(allKeys(k))
            Quit:k=""

            Set hasIn = $data(fhirBySda(k))
            Set hasOut = $data(hl7BySda(k))
            Set status = $select(hasIn&&hasOut:"complete", hasIn:"in-only", 1:"out-only")

            Set obj = ##class(AgenticInterop.Data.FieldMapping).%New()
            Set obj.SourceFormat = "FHIR R4"
            Set obj.TargetFormat = "HL7 v2"
            Set obj.SdaType = sdaType
            Set obj.SdaNormalized = k
            Set obj.Status = status

            If hasIn {
                Set obj.SourceField = $LI(fhirBySda(k), 1)
                Set obj.SdaField = $LI(fhirBySda(k), 2)
                Set obj.SourceClass = $LI(fhirBySda(k), 3)
            }
            If hasOut {
                Set rawSdaHL7 = $LI(hl7BySda(k), 1)
                Set rawHL7Tgt = $LI(hl7BySda(k), 2)
                If 'hasIn { Set obj.SdaField = rawSdaHL7 }
                ; Enrich HL7 target with sub-field position
                Set obj.TargetField = ..EnrichHL7SubField(rawHL7Tgt, rawSdaHL7)
                Set obj.TargetClass = "HS.Gateway.HL7.HL7ToSDA3"
                Set obj.SourceSegment = $LI(hl7BySda(k), 3)
            }

            Set sc = obj.%Save()
            If $system.Status.IsOK(sc) { Set totalRows = totalRows + 1 }
        }
    }

    Set elapsed = $fnumber(($zhorolog - startTime), "", 2)
    Set out.totalRows = totalRows
    Set out.elapsedSeconds = +elapsed
    Set out.sdaTypes = $LL(hl7SdaTypes)
    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

/// Query pre-built field trace from the persistent table.
///
///   GET /api/agentic/transforms/field-trace?source=HL7+v2&target=FHIR+R4&sdaType=Patient
ClassMethod QueryFieldTrace(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set srcFmt = $get(%request.Data("source",1))
    Set tgtFmt = $get(%request.Data("target",1))
    Set sdaType = $get(%request.Data("sdaType",1))

    Set out = {}
    Set out.ok = 1
    Set out.sourceFormat = srcFmt
    Set out.targetFormat = tgtFmt
    Set out.sdaType = sdaType

    If srcFmt = "" || (tgtFmt = "") {
        Set out.ok = 0
        Set out.error = "Required parameters: source, target"
        Quit $classmethod(util, "WriteJSON", pResponse, out)
    }

    ; Use QueryPartial for SDA3 half-chain queries, otherwise standard Query
    If (srcFmt = "SDA3") || (tgtFmt = "SDA3") {
        Set out.mappings = ##class(AgenticInterop.Data.FieldMapping).QueryPartial(srcFmt, tgtFmt, sdaType)
    } Else {
        Set out.mappings = ##class(AgenticInterop.Data.FieldMapping).Query(srcFmt, tgtFmt, sdaType)
    }
    Set out.count = out.mappings.%Size()

    ; Also return available SDA types for this pair
    If sdaType = "" {
        If (srcFmt = "SDA3") || (tgtFmt = "SDA3") {
            Set out.sdaTypes = ##class(AgenticInterop.Data.FieldMapping).ListAllSdaTypes()
        } Else {
            Set out.sdaTypes = ##class(AgenticInterop.Data.FieldMapping).ListSdaTypes(srcFmt, tgtFmt)
        }
    }

    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

/// Return metadata about the field mapping table: row count, last
/// rebuild time, available format pairs.
///
///   GET /api/agentic/transforms/field-trace/status
ClassMethod FieldTraceStatus(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set out = {}
    Set out.ok = 1
    Set out.totalRows = ##class(AgenticInterop.Data.FieldMapping).CountAll()

    ; Last rebuild time
    Set sql = "SELECT TOP 1 RebuiltAt FROM AgenticInterop_Data.FieldMapping ORDER BY RebuiltAt DESC"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    If rs.%Next() {
        Set out.lastRebuiltAt = rs.%Get("RebuiltAt")
    } Else {
        Set out.lastRebuiltAt = ""
    }

    ; Available format pairs
    Set pairs = []
    Set sql = "SELECT DISTINCT SourceFormat, TargetFormat FROM AgenticInterop_Data.FieldMapping ORDER BY SourceFormat, TargetFormat"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    While rs.%Next() {
        Set p = {}
        Set p.source = rs.%Get("SourceFormat")
        Set p.target = rs.%Get("TargetFormat")
        Do pairs.%Push(p)
    }
    Set out.formatPairs = pairs

    Quit $classmethod(util, "WriteJSON", pResponse, out)
}

}
