/// One persisted FHIR directory-load run, written by LoadFHIRDirectory's
/// background job (Tool.FHIRServer.%RunLoadJob) on completion. This is the
/// DURABLE ingestion-metrics history — duration, throughput, totals — so the
/// ListFHIRLoadRuns tool and the FHIR Server Audit panel can show trends
/// across loads, independent of the transient ^AgInt.FHIRLoad progress global.
///
/// Stored in the app namespace (HSCUSTOM) like every AgenticInterop.Data.*
/// class; the Namespace property records which FHIR namespace the load
/// targeted. SQL table: AgenticInterop_Data.FHIRLoadRun.
Class AgenticInterop.Data.FHIRLoadRun Extends (%Persistent, %JSON.Adaptor)
{

/// FHIR namespace the load targeted (not where this row is stored).
Property Namespace As %String(MAXLEN = 100);

/// FHIR endpoint cspUrl the data was loaded into.
Property Endpoint As %String(MAXLEN = 500);

/// LoadFHIRDirectory jobId.
Property JobId As %String(MAXLEN = 100);

/// Display timestamps (as recorded by the load job).
Property StartedAt As %String(MAXLEN = 40);

Property FinishedAt As %String(MAXLEN = 40);

/// Wall-clock seconds for the whole load.
Property DurationSec As %Numeric(SCALE = 2);

Property TotalFiles As %Integer;

Property FilesDone As %Integer;

Property FilesFailed As %Integer;

/// Total FHIR resources ingested (sum of bundle entries across files).
Property TotalResources As %Integer;

/// Throughput.
Property ResourcesPerSec As %Numeric(SCALE = 2);

Property TotalMB As %Numeric(SCALE = 2);

/// completed | error.
Property Status As %String(MAXLEN = 40);

/// When this history row was written.
Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Index ByCreated On CreatedAt;

Index ByNamespace On Namespace;

/// Persist a completed load run. Called by Tool.FHIRServer.%RunLoadJob.
/// Never throws to the caller (a metrics-history failure must not fail the
/// load) — returns a %Status the caller may ignore.
ClassMethod Record(pNs As %String, pEndpoint As %String, pJobId As %String, pStarted As %String, pFinished As %String, pDurationSec As %Numeric, pTotalFiles As %Integer, pFilesDone As %Integer, pFilesFailed As %Integer, pTotalResources As %Integer, pResourcesPerSec As %Numeric, pTotalMB As %Numeric, pStatus As %String) As %Status
{
    Set st = $$$OK
    Try {
        Set r = ..%New()
        Set r.Namespace = pNs
        Set r.Endpoint = pEndpoint
        Set r.JobId = pJobId
        Set r.StartedAt = pStarted
        Set r.FinishedAt = pFinished
        Set r.DurationSec = pDurationSec
        Set r.TotalFiles = pTotalFiles
        Set r.FilesDone = pFilesDone
        Set r.FilesFailed = pFilesFailed
        Set r.TotalResources = pTotalResources
        Set r.ResourcesPerSec = pResourcesPerSec
        Set r.TotalMB = pTotalMB
        Set r.Status = pStatus
        Set st = r.%Save()
    } Catch ex {
        Set st = ex.AsStatus()
    }
    Quit st
}

}
