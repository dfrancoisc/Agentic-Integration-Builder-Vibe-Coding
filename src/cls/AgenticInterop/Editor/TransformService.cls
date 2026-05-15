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
