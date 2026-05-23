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

    ; Verify DTL is available for the validator
    Set dtlExists = ##class(%Dictionary.CompiledXData).%ExistsId("Test.ValidationDTL||DTLBody")
    Write "DTL XData exists: ", dtlExists,!

    Write !,"=== Test 1: WRONG docName + condition (should AUTO-CORRECT) ===",!
    ; Use single-encoded entities as the agent would produce
    Set badXml = "<ruleDefinition alias="""" context=""EnsLib.HL7.MsgRouter.RoutingEngine"" production=""""><ruleSet name="""" effectiveBegin="""" effectiveEnd=""""><rule name=""RouteORU"" disabled=""false""><constraint name=""msgClass"" value=""EnsLib.HL7.Message""/><constraint name=""docCategory"" value=""2.5""/><constraint name=""docName"" value=""ORU_R01""/><when condition=""HL7.{MSH:9.1}=&quot;ORU&quot;&amp;&amp;HL7.{MSH:9.2}=&quot;R01&quot;""><send transform=""Test.ValidationDTL"" target=""FileOut""/><return/></when></rule><rule name=""DeadLetter"" disabled=""false""><when condition=""1""><send transform="""" target=""DeadLetter""/><return/></when></rule></ruleSet></ruleDefinition>"
    Set r1 = ##class(AgenticInterop.Tool.Production).CreateRoutingRule("Test.CorrectedRule", badXml)
    Write "ok=", r1.ok,!
    If 'r1.ok {
        Write "ERROR: ", r1.error,!
        If r1.%IsDefined("compileError") { Write "compileError: ", r1.compileError,! }
    }
    If r1.%IsDefined("corrected") { Write "corrected=", r1.corrected,! }
    If r1.%IsDefined("correctionNote") { Write "note=", r1.correctionNote,! }
    ; Verify the saved rule XML
    If r1.ok {
        Set xdId = "Test.CorrectedRule||RuleDefinition"
        If ##class(%Dictionary.CompiledXData).%ExistsId(xdId) {
            Set xdObj = ##class(%Dictionary.CompiledXData).%OpenId(xdId)
            Set ruleBody = xdObj.Data.Read(10000)
            Set hasADT = (ruleBody [ "ADT_A01")
            Set hasORU = (ruleBody [ "ORU_R01")
            Write "docName corrected to ADT_A01: ", hasADT,!
            Write "ORU_R01 still present: ", hasORU, " (expected 0)",!
        }
    }

    Write !,"=== Test 2: CORRECT docName (should pass unchanged) ===",!
    Set goodXml = "<ruleDefinition alias="""" context=""EnsLib.HL7.MsgRouter.RoutingEngine"" production=""""><ruleSet name="""" effectiveBegin="""" effectiveEnd=""""><rule name=""RouteADT"" disabled=""false""><constraint name=""msgClass"" value=""EnsLib.HL7.Message""/><constraint name=""docCategory"" value=""2.5""/><constraint name=""docName"" value=""ADT_A01""/><when condition=""1""><send transform=""Test.ValidationDTL"" target=""FileOut""/><return/></when></rule></ruleSet></ruleDefinition>"
    Set r2 = ##class(AgenticInterop.Tool.Production).CreateRoutingRule("Test.GoodRule", goodXml)
    Write "ok=", r2.ok,!
    If 'r2.ok { Write "ERROR: ", r2.error,! }

    ; Cleanup
    Do ##class(%Dictionary.ClassDefinition).%DeleteId("Test.ValidationDTL")
    Do ##class(%Dictionary.ClassDefinition).%DeleteId("Test.CorrectedRule")
    Do ##class(%Dictionary.ClassDefinition).%DeleteId("Test.GoodRule")
    Try { Do $SYSTEM.OBJ.Delete("Test.ValidationDTL", "-d") } Catch  {}
    Try { Do $SYSTEM.OBJ.Delete("Test.CorrectedRule", "-d") } Catch  {}
    Try { Do $SYSTEM.OBJ.Delete("Test.GoodRule", "-d") } Catch  {}

    Write !,"=== Done ==="
}

}
