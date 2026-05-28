/// InterSystems IRIS system runtime error messages — the `<ANGLE BRACKET>`
/// ObjectScript runtime errors (e.g. `<UNDEFINED>`, `<SUBSCRIPT>`,
/// `<CLASS DOES NOT EXIST>`, `<PROPERTY DOES NOT EXIST>`, `<STORE>`,
/// `<PROTECT>`, `<MAXSTRING>`) and the ISO 11756-1999 standard `Mnn` error
/// codes returned in $ECODE. These are what appear in $ZERROR, process
/// stack traces, and tool-execution failures — DISTINCT from the numeric
/// %Status codes in AgenticInterop.Reference.ErrorCode (which the
/// lookup_error_code tool covers) and the symbolic Ens production codes in
/// AgenticInterop.Reference.ProductionError (explain_production_error).
///
/// Backed by ^AgInt.SysErr(UPPER(name)) = $lb(name, description, category).
/// Names are stored WITHOUT the surrounding angle brackets ("CLASS DOES NOT
/// EXIST", "UNDEFINED"); the explain_system_error tool strips `<...>` from
/// the caller's input before lookup. Looked up by explain_system_error.
Class AgenticInterop.Reference.SystemError Extends %RegisteredObject
{

/// Pipe-delimited catalog: Category|Name|Description (one row per line).
/// Name has NO angle brackets. Category: System | Network | ISO.
XData Catalog
{
System|ALARM|An internal timer for user events has expired.
System|ARRAY DIMENSION|The expected dimensionality of the variable or argument is incorrect.
System|BAD IMPLICIT|Invalid implicit data conversion requested.
System|BLOCKNUMBER|A reference has been made to a block outside the range of the database file.
System|_CALLBACK SYNTAX|A name has been specified beginning with an underscore character followed by a letter.
System|CANNOT GET THIS PROPERTY|There has been an attempt to get a property of a class for which getting this property is invalid.
System|CANNOT SET THIS PROPERTY|There has been an attempt to set a property of a class for which setting this property is invalid.
System|CLASS COMPILING|Attempt to instantiate a class or invoke a class method of a class currently being recompiled on the local system.
System|CLASS DESCRIPTOR|There has been an attempt to run a routine which is actually a class descriptor.
System|CLASS DOES NOT EXIST|A reference has been made to a nonexistent class. Verify the exact class name; check $ZERROR for the class.
System|CLASS EDITED|Attempt to use an object whose class has been recompiled from a remote system since the object was created.
System|CLASS PROPERTY|IRIS does not support class properties. Rewrite as a proper class method instead of a calculated property.
System|CLASS RECOMPILED|Attempt to use an object whose class has been recompiled on the local system since the object was created.
System|CLASS TOO BIG TO LOAD|A class cannot be used because its class descriptor is too large to fit into a routine buffer.
System|CLASS TOO BIG TO SAVE|A class cannot be created because its class descriptor is too large to fit into a routine buffer.
System|CLIENT-SERVER MISMATCH|A network request cannot be processed due to incompatibility between the client and server.
System|CLUSTERFAIL|A cluster member has failed during global buffer lock processing.
System|COLLATECHANGE|Attempt to change the collation algorithm while subscripted local variables are defined.
System|COLLATEMISMATCH|Subscript level mapping failed due to misconfigured collation type.
System|COLLATION NOT SUPPORTED|A reference has been made to a global whose collation type is not supported on the current system.
System|COMMAND|A command has been used improperly in this context (e.g. an argumentless GoTo in a routine). Check $ZERROR.
System|COMMITFAIL|Error during a COMMIT processing a TCommit; IRIS is unsure whether remote machines processed the commit.
System|COMPLEX PATTERN|The combination of pattern and input string generates too many possible matches to manage.
System|CONFLICTING BLOCK NUMBERS|There has been an attempt to reserve a block that was already reserved.
System|CORRUPT OBJECT|An internal object system error occurred. Contact InterSystems WRC.
System|CORRUPT VOLUME SET|The volume set is corrupted (usually a wrong label). Use the LABEL utility to correct it.
System|CP NOT STARTED|A major process required for proper operation failed to start. Potentially serious; notify system manager.
System|DATABASE MAP LABEL|There is an invalid label in a database map block.
System|DATABASE|IRIS has detected degradation in this database. Potentially serious; notify system manager.
System|DIRECTORY|No such directory / no IRIS database / database not mounted / database locked by another configuration. Check $ZERROR.
System|DISCONNECT|A TCP disconnect was detected while a long-duration request was being processed.
System|DISKHARD|IRIS encountered an uncorrectable disk hardware error (may also be a database problem); notify system manager.
System|DIVIDE|There has been an attempt to divide by zero.
System|DOMAINSPACERETRY|Repeated attempts to contact the domain space master have failed.
System|DSCON|There has been an attempt to read from a disconnected terminal.
System|DSKFUL|A write to disk failed because the file reached its maximum size; some but not all data was written.
System|DUPLICATEARG|Attempt to use $SORTBEGIN with an ancestor or descendant of an already-defined $SORTBEGIN global.
System|DYNAMIC LIBRARY LOAD|An error occurred loading a dynamic library via callout. See messages.log.
System|ECODETRAP|A user-generated software trap was generated by setting $ECODE to a non-null string value.
System|EDITED|Incorrect modification of a routine caused a mismatch (e.g. timestamp mismatch, or class routine vs class descriptor).
System|ENDOFFILE|There has been an attempt to read past the end-of-file marker of a sequential file.
System|ERRTRAP|There are insufficient system resources remaining to run an error trap procedure.
System|EXTERNAL INTERRUPT|Another process has attempted to interrupt this process.
System|FILEFULL|IRIS attempted to allocate a disk block but the database is full and could not be expanded.
System|FRAMESTACK|The routine has too many nested calls to Do, For, Xecute, New, or user functions. Check $ZERROR.
System|FUNCTION|The specified function does not exist or is being used improperly.
System|GARBAGE COLLECTOR FAILED|A process that reclaims database space has failed. Potentially serious; notify system manager.
System|HALTED|An internal error message.
System|ILLEGAL VALUE|Attempt to use a negative value where one is not allowed (e.g. for $X or $Y).
System|INSUFFICIENT CLASS MEMORY|A class cannot be used because IRIS has run out of shared memory.
System|INTERNAL OBJECT ERROR|An internal object system error. Contact InterSystems WRC.
System|INTERRUPT|A user has interrupted the routine (often CTRL-C).
System|INVALID ARGUMENT|Invalid argument prototype in the zfentry specification of a callout function.
System|INVALID BIT STRING|The bit string used in a bit string operation is not valid.
System|INVALID CLASS|Attempt to use a class that has been corrupted. Recompile the class and try again.
System|INVALID FILE VARIABLE|A file variable was expected but none was supplied.
System|INVALID GLOBAL REFERENCE|A global reference failed length validation.
System|INVALID OREF|No object with the specified OREF is currently in memory.
System|INVALID SELECT LIST|A SELECT list was expected but not supplied.
System|INVALID TYPE|An OREF has been used where not allowed.
System|Java Exception|An exception occurred during a call into the Java runtime environment.
System|Java VM not loaded|No Java Virtual Machine is available.
System|LABELREDEF|A routine has a duplicate label. Labels must be unique within the routine.
System|LANGUAGE MISMATCH|While compiling/inserting code into a routine, the current language mode differs from the routine's.
System|LICENSE ALLOCATION EXCEEDED|Attempt to exceed the operational user limit set via $SYSTEM.License.SetUserLimit().
System|LICENSE LIMIT EXCEEDED|Attempt to exceed the number of users allowed by the active license.
System|LICENSE SERVER UNAVAILABLE|The license server is unreachable. Check your network.
System|LIST|An improperly-formed list has been used.
System|LOCKLOST|Some locks once owned by this job have been reset.
System|LOGIN INHIBITED|The system is initializing. No users are permitted to begin work.
System|MAGTAPE|A magnetic tape operation encountered an error. Check $ZA.
System|MAXARRAY|There are too many subscripts at this level.
System|MAXINCREMENT|An attempt to $INCREMENT a variable did not change its value.
System|MAX LOCKS|The maximum lock count (32766) has been exceeded.
System|MAXNUMBER|An arithmetic operation produced a number larger than the implementation allows.
System|MAX ROUTINES|There are no slots available to invoke a new routine.
System|MAXSCOPE|Attempt to issue more than 31 levels of New commands.
System|MAXSTRING|Attempt to create a data string longer than the string length limit (concatenation that exceeds the max).
System|METHOD DOES NOT EXIST|The method does not exist in the specified class or the class of the specified object. Check $ZERROR.
System|METHOD NOT SUPPORTED|The method exists but is not supported in this context (e.g. nested %ToJSON() on a non-dynamic object).
System|MNEMONICSPACE|Attempt to use control mnemonics for a device with no associated mnemonic space.
System|NAKED|Attempt to use a naked global reference when the naked state was undefined.
System|NAME|There is invalid syntax in a name.
System|NAMEADD|Overflow of device name table, resulting from the Open command.
System|NAMESPACE|The specified namespace is undefined or not active.
System|NESTED TOO DEEP|Signaled processing %DynamicArray/%DynamicObject blocks where the nesting level is too deep.
System|NETFORMAT|Network message error; the remote system found fault with the format of a request. Call support.
System|NETGLOREF|Network message error; the remote system found fault with the format of a request. Call support.
System|NETJOBMAX|Another high-speed networking process cannot be added (usually insufficient global buffers).
System|NETLOCK|A Lock command was attempted to a remote computer whose remote system index is greater than 31.
System|NETRETRY|An operation failed at the network level in a way that could be immediately retried.
System|NETSRVFAIL|During COMMIT or Set/Kill/ZKill, a client detected that a server in the transaction restarted while the transaction was open.
Network|NETWORK DATA UPDATE FAILED|An asynchronous network error occurred and updates sent over the network were lost (reasons undetermined). Call support.
Network|NETWORK DATA UPDATE FAILED - BLOCKNUMBER|Async network error; updates lost because the remote referred to a block outside the database bounds.
Network|NETWORK DATA UPDATE FAILED - CLIENT-SERVER MISMATCH|Async network error; updates lost due to client/server incompatibility.
Network|NETWORK DATA UPDATE FAILED - CLUSTERFAILED|Async network error; updates lost because a cluster member failed during global buffer lock processing.
Network|NETWORK DATA UPDATE FAILED - DATABASE|Async network error; updates lost because the server detected database degradation. Notify system manager.
Network|NETWORK DATA UPDATE FAILED - DIRECTORY|Async network error; updates lost because the referenced directory is not on the remote system.
Network|NETWORK DATA UPDATE FAILED - DISKHARD|Async network error; updates lost because the server hit an uncorrectable disk hardware error.
Network|NETWORK DATA UPDATE FAILED - FILEFULL|Async network error; updates lost because the server hit a <FILEFULL>.
Network|NETWORK DATA UPDATE FAILED - MAXSTRING|Async network error; updates lost because the server hit a string longer than 32,767 characters.
Network|NETWORK DATA UPDATE FAILED - NETFORMAT|Async network error; updates lost because the remote faulted the request format. Call support.
Network|NETWORK DATA UPDATE FAILED - NETGLOREF|Async network error; updates lost because the remote faulted the request format. Call support.
Network|NETWORK DATA UPDATE FAILED - NETVERSION|Async network error; updates lost because client and server run different ECP versions.
Network|NETWORK DATA UPDATE FAILED - PROTECT|Async network error; updates lost because a <PROTECT> error occurred.
Network|NETWORK DATA UPDATE FAILED - STRINGSTACK|Async network error; updates lost because a <STRINGSTACK> error occurred.
Network|NETWORK DATA UPDATE FAILED - STRMISMATCH|Async network error; updates lost due to an internal error handling big strings over the network.
Network|NETWORK DATA UPDATE FAILED - SUBSCRIPT|Async network error; updates lost because a <SUBSCRIPT> error occurred.
Network|NETWORK DATA UPDATE FAILED - SYSTEM|Async network error; updates lost because a <SYSTEM> error occurred on the server.
Network|NETWORK DATA UPDATE FAILED - WIDECHAR|Async network error; updates lost because a <WIDECHAR> error occurred.
System|NETWORK UNLICENSED|Attempt to access a remote directory but there is no license for IRIS networking.
System|NETWORK|Network timeout expired / local port down / accessed node down / remote server connection disabled.
System|NLS TABLE|Attempt to perform NLS translation using data that is not proper for the conversion table.
System|NO CURRENT OBJECT|There is no current object.
System|NO MAILBOX|A resource needed for interprocess communication is unavailable.
System|NO SOURCE|A source line is missing from a routine in the routine source global.
System|NODEV|Attempt to a write-only device, or write to a read-only device, with interjob communication.
System|NOJOB|Attempt to specify an incorrect process number in a View command, or an error occurred in a Job command.
System|NOLINE|There has been an attempt to refer to a nonexistent routine line.
System|NORESTART|The application or function cannot be restarted.
System|NOROUTINE|There has been an attempt to refer to a nonexistent routine. Check $ZERROR.
System|NOSYS|Extended/implicit reference to a remote system not reachable in the current network configuration.
System|NOT PRIMARY VOLUME|Volume sequence is not 1; the volume label disagrees with the function of the volume.
System|NOTOPEN|The device cannot be opened, or attempt to use an unopened device.
System|NULL VALUE|A null string appears where one is not allowed.
System|OBJECT DISPATCH|A non-multidimensional object property was supplied to a function that requires a multidimensional one. Check $DATA/$GET.
System|OUT OF $ZF HEAP SPACE|The $ZF heap lacks space for an input/output parameter passed between IRIS and the external program via $ZF.
System|PARAMETER|The number of parameters passed to a labeled line exceeded the number of formal parameters declared.
System|PRIVATE METHOD|Attempt to invoke a private (unavailable) method.
System|PRIVATE PROPERTY|Attempt to access a private (unavailable) property.
System|PROPERTY DOES NOT EXIST|The property is not part of the class of the specified object. Check $ZERROR. (Common with HL7/X12 vdoc paths on wrong routing-engine class.)
System|PROTECT|Unauthorized global Read/Write/Kill, or write to a dismounted database, or a directory the user lacks permission for. Check $ZERROR.
System|RANGE|A bit or list position is out of allowable range.
System|READ|The record cannot be read.
System|RECOMPILE|A routine was compiled under a different IRIS version. Transfer as source (%RO/%RI) and recompile.
System|REGULAR EXPRESSION|Error in the syntax of a regular expression (invalid/ambiguous, or an unimplemented feature).
System|REMOTE CLASS EDITED|Attempt to use a remote object whose class was recompiled from a remote system since creation.
System|REMOTE CLASS RECOMPILED|Attempt to use a remote object whose class was recompiled from the local system since creation.
System|REMOTE EXECUTE INVALID READ|A method called from $System.IS.Execute() tried to read from the current device (forbidden).
System|REMOTE EXECUTE INVALID WRITE|A method called from $System.IS.Execute() tried to write to the current device (forbidden).
System|RESJOB|A process was intentionally terminated.
System|ROLLFAIL|Error processing a call to TRollBack; IRIS is unsure whether remote machines processed the rollback.
System|ROUTINELOAD|Error loading a routine (corrupt OBJ code, or no routine buffers available and timeout expired). Contact system manager.
System|SELECT|A $Select function contains no true condition.
System|SHARED MEM HEAP|The request for shared memory cannot be satisfied. Reconfigure with more heap (gmheap) space.
System|SLMSPAN|Attempt to kill a global across a subscript level mapping boundary.
System|STACK|The argument stack is out of room or contains an incorrect type.
System|STORE|The process ran out of memory. Increase the process memory ($bigstring/$STORAGE), or find why it uses so much.
System|STRINGSTACK|An expression is too long / too many expressions in one argument / very long strings. Simplify the expression.
System|STRMISMATCH|There has been an internal error handling big strings over the network.
System|SUBSCRIPT|A subscript has an illegal value or a global reference is too long. Check $ZERROR.
System|SWIZZLE FAIL|Opened an oref then tried to swizzle in a related object that could not be referenced (deleted, or locked by another process).
System|SYNTAX|A syntax error (malformed language construct, e.g. misspelled/missing keyword).
System|SYSTEM|Either an operation not allowed by the OS, or an internal IRIS error. Notify support with details.
System|TCPWRITE|A timeout occurred on a TCP write operation.
System|TERMINATOR|Attempt to read on a terminal/device in image mode with no terminator and not a fixed-length read.
System|THROW|A THROW was issued but no CATCH was found on the call stack. Check $ZERROR.
System|TOO MANY CLASSES|This process has attempted to access too many active classes.
System|TOO MANY LONG STRINGS|Too many intermediate long strings are present on the string stack.
System|TOO MANY OREFS|This process has attempted to create too many simultaneously open objects.
System|TOO MANY USERS OF CLASS|Too many processes (>65561) are trying to use a particular class simultaneously.
System|TOO MANY USERS|Too many users are attempting to use the system at the same time.
System|TOOMANYFILES|IRIS cannot open a file because the OS has run out of file descriptors.
System|TRANSACTION LEVEL|The application has too many nested transactions pending.
System|TRANSLATE|IRIS read an input value for which it has no translation; it carries out the NLS Default Action.
System|TRANSLOST|A distributed transaction initiated by this job was asynchronously rolled back by the server.
System|UNDEFINED|There has been a reference to an undefined variable. Check $ZERROR for the variable name.
System|UNIMPLEMENTED|Attempt to use an unimplemented function or an unimplemented argument of a legitimate command/function.
System|UNIMPLEMENTED DOUBLE|The use of a floating-point number is not supported in this context.
System|UNKNOWN ERROR|An unexpected error occurred. Call support.
System|UNLICENSED|The available license key does not permit the requested operation (e.g. creating an encrypted database with an entry license).
System|VALUE OUT OF RANGE|The value is outside the maximum or minimum permissible range.
System|VOLUME IS NOT FORMATTED|The volume does not have the required formatting.
System|VOLUME SET ALREADY CREATED|Attempt to format an IRIS database that is already formatted.
System|WIDE CHAR|IRIS read a multibyte character where a 1-byte character was expected.
System|WRITE DEMON FAILED|The write daemon is unable to continue. Call support.
System|WRITE|The record cannot be written.
System|WRONG NAMESPACE|Attempt to load the class from a private implied namespace.
System|ZDDIF|A DATEDIFF operation was attempted with an invalid date.
System|ZDPT2|A DATEPART operation was attempted with an invalid date.
System|ZTRAP|Attempt to issue a ZTrap command with no argument.
ISO|M1|Naked indicator undefined.
ISO|M2|Invalid $FNUMBER code string combination.
ISO|M3|$RANDOM argument less than 1.
ISO|M4|No true condition in $SELECT.
ISO|M5|Line reference less than 0 (zero).
ISO|M6|Undefined local variable.
ISO|M7|Undefined global variable.
ISO|M8|Undefined special variable.
ISO|M9|Divide by zero.
ISO|M10|Invalid pattern match range.
ISO|M11|No parameters passed.
ISO|M12|Invalid line reference (negative offset).
ISO|M13|Invalid line reference (line not found).
ISO|M14|Line level not one (1). (DO command.)
ISO|M15|Undefined index variable. (FOR command.)
ISO|M16|QUIT with an argument not allowed.
ISO|M17|QUIT with an argument required.
ISO|M18|Fixed-length READ not greater than 0 (zero).
ISO|M19|Cannot merge a tree or subtree into itself.
ISO|M20|Line must have a formal parameter list.
ISO|M21|Formal parameter list name duplication.
ISO|M22|SET or KILL to ^$GLOBAL SSVN when data in global.
ISO|M23|SET or KILL to ^$JOB SSVN for nonexistent job number.
ISO|M24|Change to collation algorithm while subscripted local variables defined.
ISO|M26|Nonexistent environment (nonexistent namespace).
ISO|M27|Attempt to roll back a transaction that is not restartable.
ISO|M28|Mathematical function, parameter out of range.
ISO|M29|SET or KILL on SSVN not allowed by implementation.
ISO|M30|Reference to global variable with different collating sequence within a collating algorithm.
ISO|M31|Device control mnemonic expression used for a device without a mnemonic space selected.
ISO|M32|Device control mnemonic used in user-defined mnemonic space which has no associated line.
ISO|M33|SET or KILL to ^$ROUTINE when the specified routine exists.
ISO|M35|Device does not support mnemonic spaces. (OPEN or USE command.)
ISO|M36|Incompatible mnemonic spaces. (OPEN or USE command.)
ISO|M37|READ from device identified by null string.
ISO|M38|Invalid SSVN subscript.
ISO|M39|Invalid $NAME argument.
ISO|M40|Call by reference in the actual parameter list in JOB command.
ISO|M41|Invalid LOCK argument within a transaction.
ISO|M42|Invalid QUIT within a transaction.
ISO|M43|Invalid range value ($X or $Y). (SET command.)
ISO|M44|Invalid command outside a transaction.
ISO|M45|Invalid GOTO reference.
ISO|M57|A label is defined more than once in a routine.
ISO|M58|Too few formal parameters.
}

/// (Re)populate ^AgInt.SysErr from the Catalog XData block. Idempotent.
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
        Kill ^AgInt.SysErr
        Set n = 0
        While 'stream.AtEnd {
            Set line = stream.ReadLine()
            If line = "" { Continue }
            Set cat  = $piece(line, "|", 1)
            Set name = $piece(line, "|", 2)
            Set desc = $piece(line, "|", 3, 999)
            If name = "" { Continue }
            Set ^AgInt.SysErr($zconvert(name, "U")) = $listbuild(name, desc, cat)
            Set n = n + 1
        }
        Set ^AgInt.SysErr = n
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// How many entries are seeded.
ClassMethod Count() As %Integer
{
    Quit +$get(^AgInt.SysErr)
}

/// Case-insensitive exact lookup by name (no angle brackets). Returns
/// { found, name, description, category }.
ClassMethod Find(pName As %String) As %DynamicObject
{
    Set out = {}
    Set up = $zconvert($get(pName), "U")
    If (up '= ""), $data(^AgInt.SysErr(up)) {
        Set row = ^AgInt.SysErr(up)
        Set out.found = 1
        Set out.name = $listget(row, 1)
        Set out.description = $listget(row, 2)
        Set out.category = $listget(row, 3)
    } Else {
        Set out.found = 0
    }
    Quit out
}

/// Fuzzy contains-match (up to pMax) for when an exact Find misses.
ClassMethod Fuzzy(pNeedle As %String, pMax As %Integer = 5) As %DynamicArray
{
    Set arr = []
    Set needle = $zconvert($get(pNeedle), "U")
    If needle = "" { Quit arr }
    Set k = ""
    For {
        Set k = $order(^AgInt.SysErr(k))
        Quit:k=""
        If k [ needle {
            Set row = ^AgInt.SysErr(k)
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
