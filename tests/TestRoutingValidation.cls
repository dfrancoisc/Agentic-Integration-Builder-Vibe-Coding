Class Test.RoutingValidation
{

ClassMethod Run()
{
    ; Create a test DTL: ADT_A01 -> ORU_R01
    Set cdef = ##class(%Dictionary.ClassDefinition).%New("Test.ValidationDTL")
    Set cdef.Super = "Ens.DataTransformDTL"
    Set xd = ##class(%Dictionary.XDataDefinition).%New()
    Set xd.Name = "DTLBody"
    Do xd.Data.Write("<transform sourceClass=""EnsLib.HL7.Message"" targetClass=""EnsLib.HL7.Message"" sourceDocType=""2.5:ADT_A01"" targetDocType=""2.5:ORU_R01"" create=""new"" language=""objectscript""></transform>")
    Do cdef.XDatas.Insert(xd)
    Do cdef.%Save()
    Do $SYSTEM.OBJ.Compile("Test.ValidationDTL", "ck-d")

    Write "=== Test 1: WRONG docName (ORU_R01 = DTL target) ===",!
    Set badXml = "<ruleDefinition alias="""" context=""EnsLib.HL7.MsgRouter.RoutingEngine"" production=""""><ruleSet name="""" effectiveBegin="""" effectiveEnd=""""><rule name=""RouteORU"" disabled=""false""><constraint name=""msgClass"" value=""EnsLib.HL7.Message""/><constraint name=""docCategory"" value=""2.5""/><constraint name=""docName"" value=""ORU_R01""/><when condition=""1""><send transform=""Test.ValidationDTL"" target=""FileOut""/><return/></when></rule></ruleSet></ruleDefinition>"
    Set r1 = ##class(AgenticInterop.Tool.Production).CreateRoutingRule("Test.BadRule", badXml)
    Write "ok=", r1.ok, " (expected 0)",!
    Write "error=", r1.error,!

    Write !,"=== Test 2: CORRECT docName (ADT_A01 = DTL source) ===",!
    Set goodXml = "<ruleDefinition alias="""" context=""EnsLib.HL7.MsgRouter.RoutingEngine"" production=""""><ruleSet name="""" effectiveBegin="""" effectiveEnd=""""><rule name=""RouteADT"" disabled=""false""><constraint name=""msgClass"" value=""EnsLib.HL7.Message""/><constraint name=""docCategory"" value=""2.5""/><constraint name=""docName"" value=""ADT_A01""/><when condition=""1""><send transform=""Test.ValidationDTL"" target=""FileOut""/><return/></when></rule></ruleSet></ruleDefinition>"
    Set r2 = ##class(AgenticInterop.Tool.Production).CreateRoutingRule("Test.GoodRule", goodXml)
    Write "ok=", r2.ok, " (expected 1)",!
    If r2.ok { Write "message=", r2.message,! }

    ; Cleanup
    Do ##class(%Dictionary.ClassDefinition).%DeleteId("Test.ValidationDTL")
    Do ##class(%Dictionary.ClassDefinition).%DeleteId("Test.BadRule")
    Do ##class(%Dictionary.ClassDefinition).%DeleteId("Test.GoodRule")
    Try { Do $SYSTEM.OBJ.Delete("Test.ValidationDTL", "-d") } Catch  {}
    Try { Do $SYSTEM.OBJ.Delete("Test.BadRule", "-d") } Catch  {}
    Try { Do $SYSTEM.OBJ.Delete("Test.GoodRule", "-d") } Catch  {}

    Write !,"=== Done ==="
}

}
