/// Symbolic production/interop error codes for InterSystems IRIS — the
/// named `$$$Err*` / status symbols that appear in the Event Log and in
/// `<Ens>`/`<HSErr>` exception text (e.g. `ErrProductionSettingInvalid`,
/// `ErrMapSegUnrecog`, `ErrBPTerminated`). These are DISTINCT from the
/// numeric codes in AgenticInterop.Reference.ErrorCode — the event log
/// surfaces the symbolic name, not the number, so the agent needs this
/// table to explain what it just read.
///
/// Source: InterSystems "Messages Related to Productions" reference
/// (Production, Workflow, XPATH, EDI, HL7 v2, X12 SEF, X12, DICOM error
/// tables). The catalog lives in the Catalog XData block; Seed() parses it
/// and (re)populates this table idempotently. Looked up by the
/// explain_production_error tool.
/// Backed by a simple global (^AgInt.ProdErr) rather than a %Persistent/SQL
/// table — this is static reference data looked up by exact (case-tolerant)
/// name, so a keyed global is simpler and avoids SQL-storage quirks. Layout:
/// ^AgInt.ProdErr(UPPER(name)) = $lb(name, description, category).
Class AgenticInterop.Reference.ProductionError Extends %RegisteredObject
{

/// Pipe-delimited catalog: Category|Name|Description (one row per line).
XData Catalog
{
Production|ErrAdapterAlreadyConnected|Adapter already connected
Production|ErrBPCancelled|BusinessProcess cancelled
Production|ErrBPCanNotOpen|Can not open BusinessProcess '%1'
Production|ErrBPLASyncTimeoutMustBeOnSync|ASynchronous Call timeout should be specified on <sync> tag, ignored
Production|ErrBPLBadExpressionValue|The indirect expression cannot be evaluated
Production|ErrBPLEnumeration|'%1' must be in enumeration '%2' for activity '%3'
Production|ErrBPLInvalidContextSuperclass|The context superclass '%1' is invalid as it is NOT a primary subclass of Ens.BP.Context
Production|ErrBPLInvalidLoopContext|'%1' cannot be used outside a containing loop construct
Production|ErrBPLLabelNameNotUnique|Label named '%1' is not unique, branch would be ambiguous
Production|ErrBPLLabelNotInScope|Cannot branch to label '%1' because the label is not in scope
Production|ErrBPLNodeMissing|Missing '%1' for activity '%2'
Production|ErrBPLNodeValidation|'%1' must NOT be empty string for activity '%2'
Production|ErrBPLThrownFault|%1
Production|ErrBPTerminated|Terminating BP %1 #%2 due to error: %3
Production|ErrBusinessDispatchNameNotRegistered|Business dispatch name '%1' is not registered to run
Production|ErrCanNotAcquireJobLock|Can not acquire lock for job registration global in job '%1'
Production|ErrCanNotAcquireJobRootLock|Can not acquire lock for job registration global
Production|ErrCanNotAcquireLaunchLock|Can not acquire lock to run Ens.Job:Launch()
Production|ErrClassNotConcrete|'%1' is not a concrete class
Production|ErrClassNotDefined|'%1' is not a defined class
Production|ErrClassNotDerived|'%1' is not derived from class '%2'
Production|ErrConfigDisabled|Configuration item '%1' is disabled
Production|ErrCredentialsAlreadyExists|Credentials with name '%1' already exists
Production|ErrDocImport|%1
Production|ErrDTLCannotBeCompiled|The DTL contains errors which prevent it from being compiled
Production|ErrDTLEnumeration|'%1' must be in enumeration '%2' for action '%3'
Production|ErrDTLNodeValidation|'%1' must NOT be empty string for action '%2'
Production|ErrDTSMultiSignature|Signature error in %1: input %2 does not match '%3'
Production|ErrDTSSignature|Signature error in %1: input '%2' does not match '%3'
Production|ErrException|%1 logged as '%2' number %3
Production|ErrFailureTimeout|FailureTimeout of %1 seconds exceeded in %3; status from last attempt was %2
Production|ErrFTPConnectFailed|FTP: Failed to connect to server '%1' (msg='%2',code=%3)
Production|ErrFTPDeleteFailed|FTP: Failed Delete file '%1' (msg='%2',code=%3)
Production|ErrFTPDirectoryChangeFailed|FTP: Failed to change to directory '%1' (msg='%2',code=%3)
Production|ErrFTPGetDirectoryFailed|FTP: Failed GetDirectory (msg='%1',code=%2)
Production|ErrFTPGetFailed|FTP: Failed to Get file '%1' (msg='%2',code=%3)
Production|ErrFTPListFailed|FTP: Failed List for %1 (msg='%2',code=%3)
Production|ErrFTPLogoutFailed|FTP: Failed to log out from server '%1' (msg='%2',code=%3)
Production|ErrFTPModeChangeFailed|FTP: Failed to set connection to '%1' mode (msg='%2',code=%3)
Production|ErrFTPNameListFailed|FTP: Failed NameList for '%1' (msg='%2',code=%3)
Production|ErrFTPPutFailed|FTP: Failed to Put file '%1' (msg='%2',code=%3)
Production|ErrFTPRenameFailed|FTP: Failed Rename file '%1' (msg='%2',code=%3)
Production|ErrGeneral|%1
Production|ErrInConnectionLost|Lost %1 connection on %2 - detected via %3
Production|ErrInvalidAssign|Cannot specify '%1' for '%2'
Production|ErrInvalidBPL|Invalid BPL
Production|ErrInvalidBPLDiagram|Invalid BPL Diagram: '%1'
Production|ErrInvalidDateTimeFormat|Invalid Date/Time format
Production|ErrInvalidDTL|Invalid DTL
Production|ErrInvalidDurationFormat|Invalid Duration format
Production|ErrInvalidProduction|Invalid Production
Production|ErrIWay|iWay XTE Error: %1 (%2)
Production|ErrIWayNoStatus|Failed to find %1 object in iWay XTE response stream '%2'
Production|ErrJobFailed|JOB command failed
Production|ErrJobNotStopped|Job '%1' failed to stop within %2 seconds
Production|ErrJobsNotStopped|The following jobs failed to stop within %2 seconds: %1
Production|ErrKeyWithAppend|'key' attribute must not be specified when 'type' attribute is 'append'
Production|ErrKeyWithClear|'key' attribute must not be specified when 'type' attribute is 'clear'
Production|ErrKeyWithInsert|'key' attribute must be specified when 'type' attribute is 'insert'
Production|ErrKeyWithRemove|'key' attribute must be specified when 'type' attribute is 'remove'
Production|ErrMissingBPL|Missing BPL XDATA block, NO EXECUTABLE CODE GENERATED
Production|ErrNoCallerCredentials|No Credentials property present in %1
Production|ErrNoClassname|-no Classname given-
Production|ErrNoCredentials|Unable to find Credentials for ID name '%1'
Production|ErrNoCredentialsSystemName|Unable to find Credentials for ID name '%1' : %2
Production|ErrNoElementContent|Cannot Find Element Content
Production|ErrNoFileFound|No File Found
Production|ErrNoMsgBody|MessageBody does not exist for MessageHeader #%1
Production|ErrNoObjFromStream|Failed to find element %1 / class %2 in Stream '%3'
Production|ErrNoObjFromString|Failed to find element %1 / class %2 in String '%3'
Production|ErrNoRawInputObj|No raw input object for '%1'
Production|ErrNoResponseClass|No Response Classname is assigned for Request class %1
Production|ErrNoSQLColumns|No Columns in Query '%1'
Production|ErrNoSQLCursor|No open Cursor for Query '%1'
Production|ErrNoSQLStatement|No Statement Executed for Query '%1'
Production|ErrNotImplemented|Method %1.%2() not implemented
Production|ErrNotRetryable|Non-Retryable %3 error (%2) received after %1 seconds
Production|ErrNoWebProtocol|Unsupported Protocol '%1'
Production|ErrObjectAlreadyExists|Object ID '%1' of class '%2' already exists
Production|ErrOutConnectException|Exception occured while making %2 connection %3 : %1
Production|ErrOutConnectExpired|%2 Connect timeout period (%1) expired for %3
Production|ErrOutConnectFailed|%2 Connect failed for %3 with error %1
Production|ErrOutConnectionLost|Lost %1 connection to %2 - detected via %3
Production|ErrOutNotConnected|%1 connection to %2 is not open in %3
Production|ErrParameterInvocationInvalid|Parameter value for INVOCATION in invalid in class '%1'
Production|ErrProductionAlreadyRunning|Production '%1' is already running
Production|ErrProductionMismatchInDeferredResponse|Production name mismatch while sending deferred response
Production|ErrProductionNetworkedMismatch|Production '%1' is already running on a different machine in the network, a production of a different name can not be started
Production|ErrProductionNotQuiescent|InterSystems IRIS can not become quiescent
Production|ErrProductionNotRegistered|Failed to open Production definition '%1': %2
Production|ErrProductionNotRunning|No production is running
Production|ErrProductionNotShutdownCleanly|Production '%1' was not shutdown cleanly
Production|ErrProductionQuiescent|InterSystems IRIS is in quiescent state
Production|ErrProductionSettingInvalid|Production setting '%2' for item '%1' is invalid
Production|ErrProductionSuspendedMismatch|Production '%1' was suspended, a new production of a different name can not be started
Production|ErrRequestNotHandled|Request message '%1' not handled
Production|ErrRetryable|Retryable %3 error (%2) received after %1 seconds
Production|ErrRulesetLoadFailed|RuleSet %1 failed to load: %2
Production|ErrRulesetNotFound|RuleSet %1 cannot be found
Production|ErrSOAPConfigClass|SOAP service %1 cannot be invoked because its associated class must match. The class found is %2
Production|ErrSOAPConfigName|SOAP class %1 cannot be invoked because there is no Ensemble service configured with this name
Production|ErrSOAPConfigType|SOAP service %1 cannot be invoked because it is not a service
Production|ErrSQLParmCount|Execute called with a different number of input parameters (%1) than SQLDescribeParameters() demands (%2)
Production|ErrSuspending|Suspending message %1 as requested by message handler with status: %2
Production|ErrTCPListen|Unable to open TCP/IP port %1 within timeout %2 - Details: %3
Production|ErrTCPReadBlockSize|TCP Read(%2) with timeout period (%1) failed with : %3
Production|ErrTCPReadBlockSizeTimeoutExpired|TCP block size Read (%2) timeout period (%1) expired
Production|ErrTCPReadTimeoutExpired|TCP Read(%2) timeout period (%1) expired (charset='%3')
Production|ErrTCPTerminatedReadTimeoutExpired|TCP Read timeout (%1) expired waiting for terminator %2, data received ='%3'
Production|ErrTelnetConnectFailed|Telnet: Failed to connect to Telnet server at %1, error code %2
Production|ErrTelnetFindFailed|Telnet: Failed to find %1 string(s): '%2', status %3)
Production|ErrTelnetLoginFailed|Telnet: Login attempt to %1 resulted in Failure Notice '%2'
Production|ErrTerminate|InterSystems IRIS system termination request detected
Production|ErrUnsupportedRequestType|Request type %1 is not in %2 signature '%3'
Production|ErrValueWithClear|'value' attribute must not be specified when 'type' attribute is 'clear'
Production|ErrValueWithRemove|'value' attribute must not be specified when 'type' attribute is 'remove'
Production|ErrXDataBlockNotDefined|XDATA block '%2' is not defined in class '%1'
Production|ErrXMLValidation|Error in XML Validation: %1 %2
Workflow|ErrNoRoleSet|Unable to create RoleSet
Workflow|ErrNoUserSet|Unable to create UserSet
Workflow|ErrNoUsersFound|No Users found to assign Task to
Workflow|ErrRoleUndefined|Workflow Role '%1' not defined
Workflow|ErrTaskAlreadyAssigned|Task '%1' is already assigned
Workflow|ErrTaskAssignedToOther|Task '%1' is assigned to another User '%2'
Workflow|ErrTaskCreateFailure|Unable to create TaskHandler '%1'
Workflow|ErrTaskWrongType|TaskHandler class '%1' has wrong Type
Workflow|ErrUserUndefined|Workflow User '%1' not defined
XPath|XPathDOMResult|XPath dom result returned when single value requested
XPath|XPathMultipleResults|XPath expression evaluation returned multiple results
XPath|XPathNOResult|XPath expression evaluation didn't return any results
EDI|ErrMapBuild1|%1 BuildMap error: %2
EDI|ErrMapBuilds|%1 BuildMap errors; first: %2
EDI|ErrMapDocType|No %1 schema structure is defined for DocType '%2'
EDI|ErrMapRequired|Missing required %1 element at segment %2
EDI|ErrMapRequiredUnion|Missing required %1 union element at segment %2
EDI|ErrMapSeg|Segment '%1' not mapped by schema
EDI|ErrMapSegCount|Missing required count (%1) for %2 segment at segment %3
EDI|ErrMapSegUnrecog|Unrecognized Segment %1 found after segment %2
EDI|ErrMapWildSegUnrecog|Unrecognized '%3' Segment %1 found after segment %2
EDI|ErrMapWildSegUnrecogAfterWild|Unrecognized '%3' Segment %1 found after '%3' segment %2
EDI|InvalidCategoryName|Category name %1 is invalid
EDI|InvalidDocType|Document Type '%1' is invalid
EDI|InvalidDocumentTypeName|Document Type Name '%1' is invalid
EDI|InvalidSegmentTypeName|Segment name '%1' is invalid
EDI|UnknownCategoryName|Category name %1 is unknown
EDI|UnknownDocumentTypeName|Document Type Name '%2' not found in Document Category '%1'
EDI|UnknownSegmentTypeName|Segment name '%1' is unknown
HL7v2|ErrAckSeqNum|ACKing to MSH Sequence Number query
HL7v2|ErrEndBlock|Received unexpected EndBlock '%1' in input "%3", expected '%2'
HL7v2|ErrStartBlock|Received unexpected StartBlock '%1' in input "%3", expected '%2'
X12-SEF|FileNotExists|EDI Schema definition file '%1' does not exist
X12-SEF|NodeEnumeration|%1 value '%2' is not in enumeration %3
X12-SEF|NodeIdentification|for Node %1
X12-SEF|NodeValidation|%1 value '%2' Failed Validation for Node %3
X12|BadBINLength|Binary '%1' segment contains invalid length value %2; text:'%3'
X12|BinaryLeftover|Binary segment contains extra text '%1'
X12|CannotDetermineSchema|Schema cannot be determined, cannot validate transaction
X12|CannotRespond|Not enough data to Generate valid Response
X12|ConstraintViolation|Constraint violated: %1 for: %2
X12|ControlSegment|Referenced SetSegment %1 is a Control Segment
X12|ControlSegmentNameMandatory|Control Segment name must NOT be empty
X12|ControlVersionUnsupported|This control version: %1 NOT supported; found in segment %2 at %3
X12|DuplicateControlNumber|Duplicate Interchange Control Number %1 for Sender %2
X12|DuplicateSegmentRef|Segment reference: %1 already exists
X12|DuplicateTSControlNumber|Duplicate Transaction Set Control Number %1
X12|ElementNameMandatory|Element Name cannot be empty
X12|EmptyElement|Element %1 has empty value in segment %2
X12|ExistsElement|Element %1 has non-empty value in segment %2
X12|ExpectedDelimiter|Expected delimiter Ascii %1; in segment %2
X12|ExpectedSegment|Expected %1 Segment; got segment: '%2' at %3
X12|FatalInterchangeError|Fatal X12 Interchange Error
X12|GroupControlNumberMismatch|Group control number mismatch, expected %1, received %2 at: %3
X12|ImplementationKeyReserved|Implementation key ISC reserved for use by InterSystems Corporation
X12|IncorrectFunctionalGroupCount|Number of included functional groups mismatch, expected: %1 tallied: %2 at: %3
X12|IncorrectSegmentCount|Number of included segments count is incorrect, expected %1, tallied: %2 at: %3
X12|IncorrectTransactionCount|Number of included transactions count is incorrect, expected %1, tallied: %2 at: %3
X12|IndexImmutable|Cannot modify by index, current access mode is by Path
X12|InterchangeControlNumberMismatch|Interchange control number mismatch, expected %1, received %2 at: %3
X12|InvalidCode|Element %1, code value %2 at segment: %3 is invalid
X12|InvalidComponentReference|Invalid component in path %1
X12|InvalidComponentSeparator|Invalid Component Element separator 'Ascii %1' in segment '%2' at %3
X12|InvalidCompositeElement|Composite Element: %1 is not valid for segment: %2
X12|InvalidDataSeparator|Invalid Data Element separator 'Ascii %1' in segment: at '%2' at %3
X12|InvalidExponent|Exponent Is Invalid must be signed/unsigned integer
X12|InvalidHSC|Invalid Hierarchical Structure Code %1
X12|InvalidIndex|Invalid syntax in property path %1, repetition index MUST be 1 or Greater
X12|InvalidItemName|Item name %1 is invalid
X12|InvalidItemReference|Invalid item in path %1
X12|InvalidNumericValue|Invalid numeric value: %1
X12|InvalidPropertyPath|Property Path %1 is invalid
X12|InvalidRepetitionSeparator|Invalid Repetition separator 'Ascii %1' in segment '%2' at %3
X12|InvalidSegmentItem|Item: %1 is not valid for segment: %2
X12|InvalidSegmentName|Segment name '%1' in segment '%2' is badly formed at %3
X12|InvalidSegmentRef|Segment reference: %1 is invalid
X12|InvalidSegmentTerminator|Invalid Segment Terminator 'Ascii %1' in segment '%2' at %3
X12|InvalidSegmentType|Segment Type %1 at %3 not allowed after segment %2
X12|InvalidType|Both Category and TName must be present in transaction set type reference %1
X12|ISATruncated|Interchange Header (ISA) segment is too short (must be 106 characters); found %1:'%2' at %3
X12|ItemNotBinary|Referenced Item: %1 is NOT binary
X12|ItemNotComposite|Referenced Item: %1 is NOT a Composite Value
X12|MaxIndex|Repetition index exceeds maximum : %1
X12|NotUsedHasValue|Item %1 marked as not used, has non-empty value
X12|PathImmutable|Cannot modify by path, current access mode is by Index
X12|SchemaUnresolved|Cannot use path as schema is unresolved (DocType Not Set or Invalid?)
X12|SegmentDoesNotExist|Segment ID: %1 does not exist in segment storage
X12|SegmentImmutable|Segment is immutable, cannot modify
X12|SegmentRuleViolated|%1 Rule %2 Violated for segment: %3
X12|TA1OrGroupNotSeen|At Least one TA1 Acknowledgment or Functional Group MUST be included in Interchange
X12|TA1ValidationFailed|Validation error occured for element: %1 of TA1 acknowledgment at segment: %2
X12|TransactionImmutable|TransactionSet is immutable, cannot modify
X12|TransactionSetControlNumberMismatch|TransactionSet control number mismatch, expected %1 received: %2 at: %3
X12|UnexpectedElement|Too many elements in segment %1
X12|UnexpectedEOD|Unexpected end of data after '%1' at %2 : %3
X12|UnexpectedEODBinary|Unexpected end of data while reading binary segment after '%1'
X12|UnhandledTA1|Unable to process TA1 see segment: %2
X12|UnknownBinarySegment|Unrecognized Binary Segment %1
X12|UnknownComponentReference|Unrecognized component in path %1
X12|UnknownElementName|Unrecognized element name: %1
X12|UnknownHSC|Unrecognized Hierarchical Structure Code %1
X12|UnknownItemName|Item name %1 is unknown
X12|UnknownItemReference|Unrecognized item in path %1
X12|UnknownSender|Unknown Sender
X12|ValidateComposite|Cannot Validate Composite
DICOM|AbstractSyntaxNotSupported|Abstract Syntax '%1' is NOT supported
DICOM|BadCalledAET|The Called AET has an invalid value
DICOM|BadCallingAET|The Calling AET has an invalid value
DICOM|BadCharacter|Expected '%1' found '%2' in property reference '%3' at position '%4'
DICOM|BadTagValue|The tag value '%1' must be 4 hexadecimal digits in property reference '%2' at position '%3'
DICOM|ContextMismatch|Context IDs in successive message fragments don't match
DICOM|ConvertToXML|Unable to convert DICOM file '%1' to XML
DICOM|DataElementIsNotASequence|The dataelement '%1' in property reference '%2' at position '%3' is not of type 'sequence'
DICOM|DataSetTagNotFound|The 'data-set' element could not be found in the XML meta data
DICOM|DataValueFailsVMConstraint|Data Value for Tag '%1' failed value multiplicity constraint '%2'
DICOM|DataValueFailsVRConstraint|Data Value for Tag '%1' failed value representation constraint '%2'
DICOM|FileNameForStoreOperationNotFound|The file name for the C-STORE operation could not be determined
DICOM|InvalidFileFormat|The Dicom File appears to contain invalid data
DICOM|InvalidMessageHandler|Message Handler must be a type of EnsLib.DICOM.Util.MessageHandler
DICOM|InvalidPropertyReference|The property reference '%1' is invalid
DICOM|MaxAbstractSyntaxCountExceeded|Maximum number of Abstract Syntax items exceeded
DICOM|MaxApplicationContextCountExceeded|Maximum number of Application Context items exceeded
DICOM|MaxReceivedPDULen|Received PDU Length of '%1' exceeds negotiated maximum of '%2'
DICOM|MaxTransferSyntaxCountExceeded|Maximum number of Transfer Syntax items exceeded
DICOM|MaxUserInfoItemsExceeded|Maximum number of User Information items exceeded
DICOM|MaxUserMaxLenCountExceeded|Maximum number of User MaxLen items exceeded
DICOM|MessageIncomplete|Message '%1' - incomplete
DICOM|NoActiveAssociation|No Active Association for Calling-AET '%1 and Called-AET '%2'
DICOM|NoAssociationDefinedForPeers|No AssociationContext defined for Calling-AET '%1' and Called-AET '%2'
DICOM|PDUBadLength|PDU '%1' - Item '%2', expected length of '%3', received '%4'
DICOM|PDUBadValue|PDU '%1' - Item '%2', expected value of '%3', received '%4'
DICOM|PeerAssociationNoLongerExists|The Peer Association no longer exists, processing cannot continue
DICOM|PeerClosedConnection|Peer closed connection
DICOM|PeerRejectedAssociation|Peer rejected Association. Source: '%1' Reason: '%2'
DICOM|PeerRequestedAbort|Peer requested Association Abort
DICOM|SyntaxError|Syntax Error in property reference '%1' at position '%2'
DICOM|TimedOutWaitingForResponseFromPeer|Timed-out waiting for response from peer
DICOM|TransferSyntaxNotSupported|Transport Syntax '%1' is NOT supported
DICOM|UnableToConnectToPeer|Unable to Connect to peer '%1 : '%2'
DICOM|UnableToCreateDirectory|UnableToCreateDirectory '%1'
DICOM|UnexpectedAdapterState|Protocol Error, Adapter is in state '%1', expected state '%2'
DICOM|UnexpectedItem|Unexpected Item type '%1' received
DICOM|UnexpectedMessage|Unexpected Message type '%1' received
DICOM|UnexpectedPDU|Unexpected PDU type '%1' received
DICOM|UnrecognizedAbstractSyntax|The Abstract Syntax '%1' is unrecognized
DICOM|UnrecognizedCommandReceived|Unrecognized (unsupported) command '%1' received
DICOM|UnrecognizedDataElement|The Data Element '%1' is unrecognized
DICOM|UnrecognizedTag|The Data Element Tag '%1' is unrecognized
DICOM|UnrecognizedTransferSyntax|The Transfer Syntax '%1' is unrecognized
DICOM|VDOCPropertyDoesNotExist|The property specified by property path %1 does not exist
}

/// (Re)populate the ^AgInt.ProdErr global from the Catalog XData block.
/// Idempotent — kills and reloads. Returns a %Status. Safe to call on every
/// module activation.
ClassMethod Seed() As %Status
{
    Set sc = $$$OK
    Try {
        Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($classname() _ "||Catalog")
        If '$isobject(xdata) {
            Set xdata = ##class(%Dictionary.XDataDefinition).IDKEYOpen($classname(), "Catalog")
        }
        If '$isobject(xdata) { Return $$$ERROR($$$GeneralError, "Catalog XData not found") }
        Set stream = xdata.Data
        Do stream.Rewind()
        Kill ^AgInt.ProdErr
        Set n = 0
        While 'stream.AtEnd {
            Set line = stream.ReadLine()
            If line = "" { Continue }
            Set cat  = $piece(line, "|", 1)
            Set name = $piece(line, "|", 2)
            Set desc = $piece(line, "|", 3, 999)
            If name = "" { Continue }
            Set ^AgInt.ProdErr($zconvert(name, "U")) = $listbuild(name, desc, cat)
            Set n = n + 1
        }
        Set ^AgInt.ProdErr = n   ; top node = count
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// How many entries are seeded.
ClassMethod Count() As %Integer
{
    Quit +$get(^AgInt.ProdErr)
}

/// Case-insensitive exact lookup by symbolic name. Returns
/// { found, name, description, category } or { found:0 }.
ClassMethod Find(pName As %String) As %DynamicObject
{
    Set out = {}
    Set up = $zconvert($get(pName), "U")
    If (up '= ""), $data(^AgInt.ProdErr(up)) {
        Set row = ^AgInt.ProdErr(up)
        Set out.found = 1
        Set out.name = $listget(row, 1)
        Set out.description = $listget(row, 2)
        Set out.category = $listget(row, 3)
    } Else {
        Set out.found = 0
    }
    Quit out
}

/// Fuzzy contains-match: returns up to pMax names whose UPPER(name) contains
/// the (uppercased) needle. Used when an exact Find misses.
ClassMethod Fuzzy(pNeedle As %String, pMax As %Integer = 5) As %DynamicArray
{
    Set arr = []
    Set needle = $zconvert($get(pNeedle), "U")
    If needle = "" { Quit arr }
    Set k = ""
    For {
        Set k = $order(^AgInt.ProdErr(k))
        Quit:k=""
        If k [ needle {
            Set row = ^AgInt.ProdErr(k)
            Set e = {}
            Set e.name = $listget(row, 1)
            Set e.description = $listget(row, 2)
            Set e.category = $listget(row, 3)
            Do arr.%Push(e)
            If arr.%Size() >= pMax { Quit }
        }
    }
    Quit arr
}

}
