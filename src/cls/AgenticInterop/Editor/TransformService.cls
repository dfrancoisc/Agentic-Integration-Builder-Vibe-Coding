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

}
