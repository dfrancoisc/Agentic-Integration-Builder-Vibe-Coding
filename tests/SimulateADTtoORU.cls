/// Full end-to-end simulation of the ADT-to-ORU FileProduction build
/// sequence. Calls each AgenticInterop.Tool.* method directly in the
/// exact order the %AI.Agent must follow. Reports pass/fail for every step.
Class Tests.SimulateADTtoORU Extends %RegisteredObject
{

ClassMethod Run() As %Status
{
    Set startTime = $zhorolog
    Write !,"=========================================================="
    Write !,"  ADT-to-ORU FileProduction — Full Simulation"
    Write !,"=========================================================="
    Write !,"  Start: ",$zdatetime($horolog, 3, 1)
    Write !,""

    ; ---------- CLEANUP ----------
    Write !,"--- PHASE 0: CLEANUP ---"
    Do ..Cleanup()

    ; ---------- STEP 1: GetHL7SchemaMap (source + target) ----------
    Write !,""
    Write !,"--- STEP 1: GetHL7SchemaMap (Research) ---"
    Set srcSchema = ##class(AgenticInterop.Tool.Transform).GetHL7SchemaMap("2.5", "ADT_A01")
    If srcSchema.ok {
        Write !,"  [PASS] Source schema 2.5:ADT_A01 loaded. Segments: ",srcSchema.totalSegments
    } Else {
        Write !,"  [FAIL] Source schema: ",srcSchema.error
        Return $$$OK
    }

    Set tgtSchema = ##class(AgenticInterop.Tool.Transform).GetHL7SchemaMap("2.5", "ORU_R01")
    If tgtSchema.ok {
        Write !,"  [PASS] Target schema 2.5:ORU_R01 loaded. Segments: ",tgtSchema.totalSegments
    } Else {
        Write !,"  [FAIL] Target schema: ",tgtSchema.error
        Return $$$OK
    }

    ; ---------- STEP 2: BuildDTLXml ----------
    Write !,""
    Write !,"--- STEP 2: BuildDTLXml ---"
    Set mappings = []
    ; 1. Copy MSH segment
    Set m1 = {}
    Set m1.action = "copy-segment"
    Set m1.sourceSegment = "MSH"
    Set m1.targetSegment = "MSH"
    Do mappings.%Push(m1)
    ; 2. Set MSH:9 to ORU^R01
    Set m2 = {}
    Set m2.action = "set"
    Set m2.targetPath = "MSH:MessageType.MessageCode"
    Set m2.value = """ORU"""
    Do mappings.%Push(m2)
    Set m2b = {}
    Set m2b.action = "set"
    Set m2b.targetPath = "MSH:MessageType.TriggerEvent"
    Set m2b.value = """R01"""
    Do mappings.%Push(m2b)
    ; 3. Set MSH:12 VersionID
    Set m3 = {}
    Set m3.action = "set"
    Set m3.targetPath = "MSH:VersionID"
    Set m3.value = """2.5"""
    Do mappings.%Push(m3)
    ; 4. Copy PID segment
    Set m4 = {}
    Set m4.action = "copy-segment"
    Set m4.sourceSegment = "PID"
    Set m4.targetSegment = "PID"
    Do mappings.%Push(m4)
    ; 5. Map PID:3 -> OBR:3 (FillerOrderNumber)
    Set m5 = {}
    Set m5.action = "copy-field"
    Set m5.sourcePath = "PID:PatientIdentifierList(1).IDNumber"
    Set m5.targetPath = "OBR:FillerOrderNumber.EntityIdentifier"
    Do mappings.%Push(m5)
    ; 6. Map PV1:7 -> OBR:16 (OrderingProvider) — all components
    Set m6 = {}
    Set m6.action = "copy-all-components"
    Set m6.sourcePath = "PV1:AttendingDoctor(1)"
    Set m6.targetPath = "OBR:OrderingProvider(1)"
    Do mappings.%Push(m6)
    ; 7. Set OBR:4 UniversalServiceIdentifier
    Set m7 = {}
    Set m7.action = "set"
    Set m7.targetPath = "OBR:UniversalServiceIdentifier.Identifier"
    Set m7.value = """ADT-OBS"""
    Do mappings.%Push(m7)
    Set m7b = {}
    Set m7b.action = "set"
    Set m7b.targetPath = "OBR:UniversalServiceIdentifier.Text"
    Set m7b.value = """Admission Observation"""
    Do mappings.%Push(m7b)
    Set m7c = {}
    Set m7c.action = "set"
    Set m7c.targetPath = "OBR:UniversalServiceIdentifier.NameofCodingSystem"
    Set m7c.value = """L"""
    Do mappings.%Push(m7c)
    ; 8. Set OBR:7 from EVN:2
    Set m8 = {}
    Set m8.action = "copy-field"
    Set m8.sourcePath = "EVN:RecordedDateTime"
    Set m8.targetPath = "OBR:ObservationDateTime"
    Do mappings.%Push(m8)
    ; 9. OBX:1 SetID
    Set m9 = {}
    Set m9.action = "set"
    Set m9.targetPath = "OBX(1):SetIDOBX"
    Set m9.value = """1"""
    Do mappings.%Push(m9)
    ; 10. OBX:2 ValueType
    Set m10 = {}
    Set m10.action = "set"
    Set m10.targetPath = "OBX(1):ValueType"
    Set m10.value = """ST"""
    Do mappings.%Push(m10)
    ; 11. OBX:3 ObservationIdentifier
    Set m11 = {}
    Set m11.action = "set"
    Set m11.targetPath = "OBX(1):ObservationIdentifier.Identifier"
    Set m11.value = """PATNAME"""
    Do mappings.%Push(m11)
    Set m11b = {}
    Set m11b.action = "set"
    Set m11b.targetPath = "OBX(1):ObservationIdentifier.Text"
    Set m11b.value = """Patient Name"""
    Do mappings.%Push(m11b)
    Set m11c = {}
    Set m11c.action = "set"
    Set m11c.targetPath = "OBX(1):ObservationIdentifier.NameofCodingSystem"
    Set m11c.value = """L"""
    Do mappings.%Push(m11c)
    ; 12. OBX:5 ObservationValue — concat of family, given, middle
    Set m12 = {}
    Set m12.action = "concat"
    Set m12.targetPath = "OBX(1):ObservationValue"
    Set m12.parts = ["PID:PatientName.FamilyName.Surname", "PID:PatientName.GivenName", "PID:PatientName.SecondandFurtherGivenNamesor"]
    Set m12.separator = " "
    Do mappings.%Push(m12)
    ; 13. OBX:11 ObservationResultStatus
    Set m13 = {}
    Set m13.action = "set"
    Set m13.targetPath = "OBX(1):ObservationResultStatus"
    Set m13.value = """F"""
    Do mappings.%Push(m13)

    Set dtlResult = ##class(AgenticInterop.Tool.Transform).BuildDTLXml("2.5:ADT_A01", "2.5:ORU_R01", mappings, "new")
    If dtlResult.ok {
        Write !,"  [PASS] DTL XML built successfully."
        Write !,"         Paths used: ",dtlResult.segmentPathsUsed.%Size()
        If dtlResult.%IsDefined("warnings"), dtlResult.warnings.%Size() > 0 {
            Write !,"         WARNINGS: "
            Set wIter = dtlResult.warnings.%GetIterator()
            While wIter.%GetNext(.wk, .wv) {
                Write !,"           - ",wv
            }
        }
        Set dtlXml = dtlResult.dtlXml
        Write !,"         XML length: ",$length(dtlXml)
    } Else {
        Write !,"  [FAIL] BuildDTLXml: ",dtlResult.error
        Return $$$OK
    }

    ; ---------- STEP 3: CreateDTL ----------
    Write !,""
    Write !,"--- STEP 3: CreateDTL ---"
    Set dtlName = "ADT.ToORU.Transform"
    Set createDTL = ##class(AgenticInterop.Tool.Transform).CreateDTL(dtlName, "EnsLib.HL7.Message", "EnsLib.HL7.Message", "2.5:ADT_A01", "2.5:ORU_R01", dtlXml)
    If createDTL.ok, createDTL.created {
        Write !,"  [PASS] DTL '",dtlName,"' created and compiled."
    } Else {
        Write !,"  [FAIL] CreateDTL: ",$select(createDTL.%IsDefined("error"):createDTL.error, 1:"created="_createDTL.created)
        Return $$$OK
    }

    ; ---------- STEP 4: CreateRoutingRule ----------
    Write !,""
    Write !,"--- STEP 4: CreateRoutingRule ---"
    Set ruleName = "ADT.ToORU.RoutingRule"
    Set ruleXml = "<ruleDefinition alias="""" context=""EnsLib.HL7.MsgRouter.RoutingEngine"">"
    Set ruleXml = ruleXml _ "<ruleSet name="""">"
    ; Rule 1: Route ORU^R01 to outbound (evaluates INCOMING message after transform-on-send)
    ; But wait - transform-on-send means the condition evaluates the INCOMING ADT, not the transformed ORU.
    ; The prompt says: "If MSH:9.1 equals ORU and MSH:9.2 equals R01" — this means
    ; the rule was intended to evaluate AFTER transformation. In IRIS, transforms happen
    ; during <send>, so the rule condition sees the ORIGINAL message.
    ; For the ADT-to-ORU use case with transform-on-send, we need:
    ; Rule 1: If incoming is ADT^A01, send to FileOut WITH transform
    ; Rule 2: Otherwise, send to DeadLetter
    Set ruleXml = ruleXml _ "<rule name=""Route ADT to outbound with transform"">"
    Set ruleXml = ruleXml _ "<constraint name=""msgClass"" value=""EnsLib.HL7.Message""/>"
    Set ruleXml = ruleXml _ "<when condition=""HL7.{MSH:9.1}=&quot;ADT&quot;&amp;&amp;HL7.{MSH:9.2}=&quot;A01&quot;"">"
    Set ruleXml = ruleXml _ "<send transform=""ADT.ToORU.Transform"" target=""ADT.ToORU.FileOut""/>"
    Set ruleXml = ruleXml _ "<return/>"
    Set ruleXml = ruleXml _ "</when>"
    Set ruleXml = ruleXml _ "</rule>"
    ; Rule 2: Dead letter (anything else)
    Set ruleXml = ruleXml _ "<rule name=""Dead letter"">"
    Set ruleXml = ruleXml _ "<constraint name=""msgClass"" value=""EnsLib.HL7.Message""/>"
    Set ruleXml = ruleXml _ "<when condition=""1"">"
    Set ruleXml = ruleXml _ "<send transform="""" target=""ADT.ToORU.DeadLetter""/>"
    Set ruleXml = ruleXml _ "<return/>"
    Set ruleXml = ruleXml _ "</when>"
    Set ruleXml = ruleXml _ "</rule>"
    Set ruleXml = ruleXml _ "</ruleSet>"
    Set ruleXml = ruleXml _ "</ruleDefinition>"

    Set createRule = ##class(AgenticInterop.Tool.Production).CreateRoutingRule(ruleName, ruleXml)
    If createRule.ok {
        Write !,"  [PASS] Routing rule '",ruleName,"' created."
    } Else {
        Write !,"  [FAIL] CreateRoutingRule: ",createRule.error
        Return $$$OK
    }

    ; ---------- STEP 5: CreateProduction ----------
    Write !,""
    Write !,"--- STEP 5: CreateProduction ---"
    Set prodName = "ADT.ToORU.FileProduction"
    Set createProd = ##class(AgenticInterop.Tool.Production).CreateProduction(prodName, "ADT to ORU file-based production with dead-letter routing")
    If createProd.ok, createProd.created {
        Write !,"  [PASS] Production '",prodName,"' created."
    } Else {
        Write !,"  [FAIL] CreateProduction: ",$select(createProd.%IsDefined("error"):createProd.error, 1:"already exists")
        Return $$$OK
    }

    ; ---------- STEP 6: AddBusinessHost x4 ----------
    Write !,""
    Write !,"--- STEP 6: AddBusinessHost (x4) ---"
    ; 6a. File service
    Set addSvc = ##class(AgenticInterop.Tool.Production).AddBusinessHost(prodName, "ADT.ToORU.FileIn", "EnsLib.HL7.Service.FileService")
    If addSvc.ok, addSvc.added {
        Write !,"  [PASS] Added host: ADT.ToORU.FileIn (FileService)"
    } Else {
        Write !,"  [FAIL] AddBusinessHost FileIn: ",$select(addSvc.%IsDefined("error"):addSvc.error, 1:"unknown")
        Return $$$OK
    }

    ; 6b. Routing engine
    Set addRouter = ##class(AgenticInterop.Tool.Production).AddBusinessHost(prodName, "ADT.ToORU.Router", "EnsLib.HL7.MsgRouter.RoutingEngine")
    If addRouter.ok, addRouter.added {
        Write !,"  [PASS] Added host: ADT.ToORU.Router (RoutingEngine)"
    } Else {
        Write !,"  [FAIL] AddBusinessHost Router: ",$select(addRouter.%IsDefined("error"):addRouter.error, 1:"unknown")
        Return $$$OK
    }

    ; 6c. File out operation
    Set addOut = ##class(AgenticInterop.Tool.Production).AddBusinessHost(prodName, "ADT.ToORU.FileOut", "EnsLib.HL7.Operation.FileOperation")
    If addOut.ok, addOut.added {
        Write !,"  [PASS] Added host: ADT.ToORU.FileOut (FileOperation)"
    } Else {
        Write !,"  [FAIL] AddBusinessHost FileOut: ",$select(addOut.%IsDefined("error"):addOut.error, 1:"unknown")
        Return $$$OK
    }

    ; 6d. Dead letter operation
    Set addDL = ##class(AgenticInterop.Tool.Production).AddBusinessHost(prodName, "ADT.ToORU.DeadLetter", "EnsLib.HL7.Operation.FileOperation")
    If addDL.ok, addDL.added {
        Write !,"  [PASS] Added host: ADT.ToORU.DeadLetter (FileOperation)"
    } Else {
        Write !,"  [FAIL] AddBusinessHost DeadLetter: ",$select(addDL.%IsDefined("error"):addDL.error, 1:"unknown")
        Return $$$OK
    }

    ; ---------- STEP 7: UpdateBusinessHostSettings (x4) ----------
    Write !,""
    Write !,"--- STEP 7: UpdateBusinessHostSettings (x4) ---"

    ; 7a. File service settings
    Set svcSettings = {}
    Set svcHost = {}
    Set svcHost.TargetConfigNames = "ADT.ToORU.Router"
    Set svcHost.MessageSchemaCategory = "2.5"
    Set svcSettings.Host = svcHost
    Set svcAdapter = {}
    Set svcAdapter.FilePath = "/tmp/hl7-in/"
    Set svcAdapter.FileSpec = "*.hl7"
    Set svcAdapter.ArchivePath = "/tmp/hl7-in/archive/"
    Set svcSettings.Adapter = svcAdapter
    Set updSvc = ##class(AgenticInterop.Tool.Production).UpdateBusinessHostSettings(prodName, "ADT.ToORU.FileIn", svcSettings)
    If updSvc.ok {
        Write !,"  [PASS] Settings: ADT.ToORU.FileIn (",updSvc.updated.%Size()," settings)"
    } Else {
        Write !,"  [FAIL] UpdateSettings FileIn: ",updSvc.error
        Return $$$OK
    }

    ; 7b. Router settings
    Set routerSettings = {}
    Set routerHost = {}
    Set routerHost.BusinessRuleName = "ADT.ToORU.RoutingRule"
    Set routerHost.Validation = ""
    Set routerSettings.Host = routerHost
    Set updRouter = ##class(AgenticInterop.Tool.Production).UpdateBusinessHostSettings(prodName, "ADT.ToORU.Router", routerSettings)
    If updRouter.ok {
        Write !,"  [PASS] Settings: ADT.ToORU.Router (",updRouter.updated.%Size()," settings)"
    } Else {
        Write !,"  [FAIL] UpdateSettings Router: ",updRouter.error
        Return $$$OK
    }

    ; 7c. File out settings
    Set outSettings = {}
    Set outAdapter = {}
    Set outAdapter.FilePath = "/tmp/hl7-out/"
    Set outAdapter.Overwrite = 0
    Set outSettings.Adapter = outAdapter
    Set updOut = ##class(AgenticInterop.Tool.Production).UpdateBusinessHostSettings(prodName, "ADT.ToORU.FileOut", outSettings)
    If updOut.ok {
        Write !,"  [PASS] Settings: ADT.ToORU.FileOut (",updOut.updated.%Size()," settings)"
    } Else {
        Write !,"  [FAIL] UpdateSettings FileOut: ",updOut.error
        Return $$$OK
    }

    ; 7d. Dead letter settings
    Set dlSettings = {}
    Set dlAdapter = {}
    Set dlAdapter.FilePath = "/tmp/dead-letter/"
    Set dlAdapter.Overwrite = 0
    Set dlSettings.Adapter = dlAdapter
    Set updDL = ##class(AgenticInterop.Tool.Production).UpdateBusinessHostSettings(prodName, "ADT.ToORU.DeadLetter", dlSettings)
    If updDL.ok {
        Write !,"  [PASS] Settings: ADT.ToORU.DeadLetter (",updDL.updated.%Size()," settings)"
    } Else {
        Write !,"  [FAIL] UpdateSettings DeadLetter: ",updDL.error
        Return $$$OK
    }

    ; ---------- STEP 8: EnsureDirectory (x4) ----------
    Write !,""
    Write !,"--- STEP 8: EnsureDirectory (x4) ---"
    Set dirs = $listbuild("/tmp/hl7-in/", "/tmp/hl7-in/archive/", "/tmp/hl7-out/", "/tmp/dead-letter/")
    Set ptr = 0
    While $listnext(dirs, ptr, dir) {
        Set ensDir = ##class(AgenticInterop.Tool.Production).EnsureDirectory(dir)
        If ensDir.ok {
            Write !,"  [PASS] Directory: ",dir," (",ensDir.message,")"
        } Else {
            Write !,"  [FAIL] EnsureDirectory ",dir,": ",ensDir.error
            Return $$$OK
        }
    }

    ; ---------- STEP 9: StartProduction ----------
    Write !,""
    Write !,"--- STEP 9: StartProduction ---"
    Set startProd = ##class(AgenticInterop.Tool.Production).StartProduction(prodName)
    If startProd.ok {
        Write !,"  [PASS] Production started: ",startProd.message
    } Else {
        Write !,"  [FAIL] StartProduction: ",startProd.error
        Return $$$OK
    }

    ; Brief pause to let the production initialize
    Hang 2

    ; ---------- STEP 10: BuildAndSendHL7TestMessage ----------
    Write !,""
    Write !,"--- STEP 10: BuildAndSendHL7TestMessage ---"
    Set fields = {}
    Set fields."MSH:SendingApplication.NamespaceID" = "EPIC"
    Set fields."MSH:SendingFacility.NamespaceID" = "MAIN-HOSP"
    Set fields."MSH:ReceivingApplication.NamespaceID" = "LIS"
    Set fields."MSH:ReceivingFacility.NamespaceID" = "LAB-SYS"
    Set fields."MSH:MessageType.MessageCode" = "ADT"
    Set fields."MSH:MessageType.TriggerEvent" = "A01"
    Set fields."MSH:MessageType.MessageStructure" = "ADT_A01"
    Set fields."MSH:MessageControlID" = "MSG-SIM-001"
    Set fields."MSH:ProcessingID" = "P"
    Set fields."MSH:VersionID" = "2.5"
    Set fields."MSH:AcceptAcknowledgmentType" = "AL"
    Set fields."MSH:ApplicationAcknowledgmentType" = "NE"
    Set fields."EVN:EventTypeCode" = "A01"
    Set fields."EVN:RecordedDateTime" = "20260522142800"
    Set fields."PID:SetIDPID" = "1"
    Set fields."PID:PatientIdentifierList(1).IDNumber" = "MRN-88402"
    Set fields."PID:PatientIdentifierList(1).AssigningAuthority.NamespaceID" = "MAIN-HOSP"
    Set fields."PID:PatientIdentifierList(1).IdentifierTypeCode" = "MR"
    Set fields."PID:PatientName(1).FamilyName.Surname" = "Nakamura"
    Set fields."PID:PatientName(1).GivenName" = "Kenji"
    Set fields."PID:PatientName(1).SecondandFurtherGivenNamesor" = "Takeshi"
    Set fields."PID:DateTimeofBirth" = "19870314"
    Set fields."PID:AdministrativeSex" = "M"
    Set fields."PID:PatientAddress(1).StreetAddress.StreetOrMailingAddress" = "2200 Coral Way"
    Set fields."PID:PatientAddress(1).City" = "Miami"
    Set fields."PID:PatientAddress(1).StateorProvince" = "FL"
    Set fields."PID:PatientAddress(1).ZiporPostalCode" = "33145"
    Set fields."PID:PatientAddress(1).Country" = "USA"
    Set fields."PV1:SetIDPV1" = "1"
    Set fields."PV1:PatientClass" = "I"
    Set fields."PV1:AttendingDoctor(1).IDNumber" = "ATTEND-4401"
    Set fields."PV1:AttendingDoctor(1).FamilyName.Surname" = "Reeves"
    Set fields."PV1:AttendingDoctor(1).GivenName" = "Samantha"
    Set fields."PV1:AttendingDoctor(1).SecondandFurtherGivenNamesor" = "L"
    Set fields."PV1:AttendingDoctor(1).Prefix" = "Dr."
    Set fields."PV1:AttendingDoctor(1).Degree" = "MD"

    Set sendResult = ##class(AgenticInterop.Tool.Testing).BuildAndSendHL7TestMessage("2.5:ADT_A01", fields, "ADT.ToORU.FileIn")
    If sendResult.ok {
        Write !,"  [PASS] Test message built (",sendResult.segmentCount," segments, ",sendResult.fieldCount," fields) and sent."
        If sendResult.%IsDefined("sendResult"), sendResult.sendResult.%IsDefined("ack") {
            Write !,"         ACK received: ",$extract(sendResult.sendResult.ack, 1, 100)
        }
    } Else {
        Write !,"  [FAIL] BuildAndSendHL7TestMessage: ",sendResult.error
        Write !,"  (continuing to PostBuildValidation to see what failed)"
    }

    ; Wait for messages to flow through the production
    Hang 3

    ; ---------- STEP 11: PostBuildValidation ----------
    Write !,""
    Write !,"--- STEP 11: PostBuildValidation ---"
    Set validation = ##class(AgenticInterop.Tool.Production).PostBuildValidation(prodName, 5)
    If validation.ok {
        Write !,"  Verdict: ",validation.verdict
        Write !,"  Checks: ",validation.passed,"/",validation.total
        Set checkIter = validation.checks.%GetIterator()
        While checkIter.%GetNext(.ck, .cv) {
            Set pass = $select(cv.pass:"PASS", 1:"FAIL")
            Write !,"    [",pass,"] ",cv.check,": ",cv.detail
            ; Show error details
            If 'cv.pass, cv.%IsDefined("recentErrors") {
                Set eIter = cv.recentErrors.%GetIterator()
                While eIter.%GetNext(.ek, .ev) {
                    Write !,"           -> ",ev.host,": ",$extract(ev.text, 1, 120)
                }
            }
        }
    } Else {
        Write !,"  [FAIL] PostBuildValidation error: ",validation.error
    }

    ; ---------- STEP 12: Verify GetProduction ----------
    Write !,""
    Write !,"--- STEP 12: GetProduction (verify settings persisted) ---"
    Set getProd = ##class(AgenticInterop.Tool.Production).GetProduction(prodName)
    If getProd.ok, getProd.exists {
        Write !,"  Production: ",prodName
        Write !,"  Hosts: ",getProd.total
        Set itemIter = getProd.items.%GetIterator()
        While itemIter.%GetNext(.ik, .iv) {
            Write !,"    - ",iv.name," (",iv.className,") enabled=",iv.enabled
            If iv.settings.%Size() > 0 {
                Set sIter = iv.settings.%GetIterator()
                While sIter.%GetNext(.sk, .sv) {
                    Write !,"        ",sv.target,".",sv.name," = ",$extract(sv.value, 1, 60)
                }
            }
        }
    } Else {
        Write !,"  [FAIL] GetProduction: ",$select(getProd.%IsDefined("error"):getProd.error, 1:"not found")
    }

    ; ---------- DRY RUN DTL (bonus verification) ----------
    Write !,""
    Write !,"--- BONUS: DryRunDTL (verify transform output) ---"
    Set testHL7 = "MSH|^~\&|EPIC|MAIN-HOSP|LIS|LAB-SYS|20260522143027||ADT^A01^ADT_A01|MSG-DRY-001|P|2.5"
    Set testHL7 = testHL7 _ $char(13) _ "EVN|A01|20260522142800"
    Set testHL7 = testHL7 _ $char(13) _ "PID|1||MRN-88402^^^MAIN-HOSP^MR||Nakamura^Kenji^Takeshi^^^^L||19870314|M"
    Set testHL7 = testHL7 _ $char(13) _ "PV1|1|I|4-EAST^4E-201^A||||ATTEND-4401^Reeves^Samantha^L^Dr.^MD^L"
    Set dryRun = ##class(AgenticInterop.Tool.Transform).DryRunDTL(dtlName, testHL7)
    If dryRun.ok {
        Write !,"  [PASS] DryRunDTL succeeded."
        If dryRun.%IsDefined("output") {
            ; Show key fields from the output
            Set outMsg = dryRun.output
            Write !,"  Output length: ",$length(outMsg)
            ; Check for ORU in the output
            If outMsg [ "ORU" {
                Write !,"  [PASS] Output contains ORU message type."
            } Else {
                Write !,"  [WARN] Output does not contain 'ORU' - check MSH:9 mapping."
            }
            If outMsg [ "Nakamura Kenji Takeshi" {
                Write !,"  [PASS] Output contains full patient name 'Nakamura Kenji Takeshi' in OBX:5."
            } ElseIf outMsg [ "Nakamura" {
                Write !,"  [FAIL] Output contains 'Nakamura' but missing middle name 'Takeshi' — check XPN component 3 field name in concat parts."
            } Else {
                Write !,"  [FAIL] Output missing patient name entirely."
            }
            If outMsg [ "MRN-88402" {
                Write !,"  [PASS] Output contains MRN-88402 (from PID:3 -> OBR:3)."
            } Else {
                Write !,"  [WARN] Output missing MRN-88402 filler order number."
            }
            If outMsg [ "ATTEND-4401" {
                Write !,"  [PASS] Output contains ATTEND-4401 (PV1:7 -> OBR:16)."
            } Else {
                Write !,"  [WARN] Output missing ATTEND-4401 ordering provider."
            }
            If outMsg [ "PATNAME" {
                Write !,"  [PASS] Output contains PATNAME observation identifier."
            } Else {
                Write !,"  [WARN] Output missing PATNAME in OBX:3."
            }
            ; Check that ADT-only segments did NOT leak through
            If outMsg [ "NK1" {
                Write !,"  [FAIL] NK1 segment leaked into ORU output!"
            }
            If outMsg [ "AL1" {
                Write !,"  [FAIL] AL1 segment leaked into ORU output!"
            }
            If outMsg [ "DG1" {
                Write !,"  [FAIL] DG1 segment leaked into ORU output!"
            }
            If outMsg [ "IN1" {
                Write !,"  [FAIL] IN1 segment leaked into ORU output!"
            }
            If outMsg [ "GT1" {
                Write !,"  [FAIL] GT1 segment leaked into ORU output!"
            }
            ; Print first 400 chars of output
            Write !,"  Output preview:"
            Write !,"    ",$extract(outMsg, 1, 200)
            If $length(outMsg) > 200 {
                Write !,"    ",$extract(outMsg, 201, 400)
            }
        }
    } Else {
        Write !,"  [FAIL] DryRunDTL: ",dryRun.error
    }

    ; ---------- CLEANUP: Stop production ----------
    Write !,""
    Write !,"--- CLEANUP: Stopping production ---"
    Set stopProd = ##class(AgenticInterop.Tool.Production).StopProduction(30, 0)
    If stopProd.ok {
        Write !,"  Production stopped."
    } Else {
        Write !,"  Stop failed: ",stopProd.error
    }

    ; ---------- SUMMARY ----------
    Set elapsed = $zhorolog - startTime
    Write !,""
    Write !,"=========================================================="
    Write !,"  SIMULATION COMPLETE"
    Write !,"  Duration: ",elapsed," seconds"
    Write !,"  End: ",$zdatetime($horolog, 3, 1)
    Write !,"=========================================================="
    Write !,""
    Return $$$OK
}

/// Clean up artifacts from any prior simulation run
ClassMethod Cleanup()
{
    ; Stop any running production
    Try {
        Set activeName = ##class(Ens.Director).GetActiveProductionName()
        If activeName '= "" {
            Write !,"  Stopping active production: ",activeName
            Set sc = ##class(Ens.Director).StopProduction(10, 1)
            Hang 2
        }
    } Catch {}
    ; Delete classes
    Set classes = $listbuild("ADT.ToORU.FileProduction", "ADT.ToORU.Transform", "ADT.ToORU.RoutingRule")
    Set ptr = 0
    While $listnext(classes, ptr, cls) {
        If ##class(%Dictionary.ClassDefinition).%ExistsId(cls) {
            Write !,"  Deleting class: ",cls
            Set sc = $SYSTEM.OBJ.Delete(cls, "d")
        }
    }
    ; Purge recent messages (last hour)
    Try {
        Set sql = "DELETE FROM Ens.MessageHeader WHERE TimeCreated >= DATEADD('hh', -1, CURRENT_TIMESTAMP)"
        Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
    } Catch {}
    ; Clear event log (last hour)
    Try {
        Set sql2 = "DELETE FROM Ens_Util.Log WHERE TimeLogged >= DATEADD('hh', -1, CURRENT_TIMESTAMP)"
        Set rs2 = ##class(%SQL.Statement).%ExecDirect(, sql2)
    } Catch {}
    Write !,"  Cleanup done."
}

}
