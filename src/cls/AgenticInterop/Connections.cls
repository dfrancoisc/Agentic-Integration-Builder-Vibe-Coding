/// Facade for managing AgenticInterop.Data.Connection rows + their
/// secrets. Modeled on Catalog.Connections from
/// dfrancoisc/new-interoperability-health.
///
/// Secrets live in IRIS Secured Wallet — a CUSTOM-usage %Wallet.KeyValue
/// secret named AgenticInteropConnections.<connection-name>, with the
/// secret payload as {"value":"<api-key>"}. The wallet collection
/// AgenticInteropConnections must exist; EnsureWallet (called from
/// %EnsureSeed) creates it idempotently. Secrets are NEVER visible
/// through SQL or Connection; only SetSecret/ClearSecret/HasSecret/
/// GetProvider touch them.
///
/// On first access (List/Get), if no rows exist, a 'bedrock-default'
/// row is seeded — region us-east-1, the Sonnet 4 model id, no secret
/// yet. Run SetSecret("bedrock-default", "<token>") to activate.
Class AgenticInterop.Connections Extends %RegisteredObject
{

/// Wallet collection that holds LLM connection secrets.
Parameter WALLETCOLLECTION = "AgenticInteropConnections";

/// Wallet resource that gates access to the collection.
Parameter WALLETRESOURCE = "AgenticInteropConnections";

/// Default connection name shipped on first use.
Parameter DEFAULTNAME = "bedrock-default";

/// Return all connections as a %DynamicArray of objects (no secrets).
ClassMethod List() As %DynamicArray
{
    Do ..%EnsureSeed()
    Set arr = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT Name FROM AgenticInterop_Data.LLMConnection ORDER BY Name")
    While rs.%Next() {
        Do arr.%Push(..Get(rs.%GetData(1)))
    }
    Quit arr
}

/// Return one connection as a %DynamicObject (no secret), or "" if not
/// found. Includes hasSecret (boolean) — derived from the wallet, not
/// the row.
ClassMethod Get(name As %String) As %DynamicObject
{
    Set id = ..%IdOf(name)
    If id = "" Quit ""
    Set conn = ##class(AgenticInterop.Data.Connection).%OpenId(id)
    If '$isobject(conn) Quit ""
    Set obj = {}
    Set obj.name = conn.Name
    Set obj.displayName = conn.DisplayName
    Set obj.description = conn.Description
    Set obj.provider = conn.Provider
    Set obj.model = conn.Model
    Set obj.region = conn.Region
    Set obj.baseURL = conn.BaseURL
    Set obj.maxTokens = conn.MaxTokens
    Set obj.enabled = (''conn.Enabled)
    Set obj.isDefault = (''conn.IsDefault)
    Set obj.core = (''conn.Core)
    Set obj.hasSecret = ..HasSecret(name)
    Set obj.createdAt = conn.CreatedAt
    Set obj.updatedAt = conn.UpdatedAt
    Set obj.lastTestOk = $select(conn.LastTestAt = "" : "", conn.LastTestOk : 1, 1 : 0)
    Set obj.lastTestAt = conn.LastTestAt
    Set obj.lastTestModel = conn.LastTestModel
    Set obj.lastTestLatencyMs = conn.LastTestLatencyMs
    Set obj.lastTestError = conn.LastTestError
    Quit obj
}

/// Create a new connection. props is a %DynamicObject with the same
/// field shape as Get() returns (excluding hasSecret/createdAt/
/// updatedAt/core).
ClassMethod Create(name As %String, props As %DynamicObject) As %Status
{
    If '..%ValidName(name) Quit $$$ERROR($$$GeneralError, "Connection name must be lowercase, start with a letter, only contain a-z 0-9 -, max 100 chars: '"_name_"'")
    If ..%IdOf(name) '= "" Quit $$$ERROR($$$GeneralError, "Connection '"_name_"' already exists")
    Set conn = ##class(AgenticInterop.Data.Connection).%New()
    Set conn.Name = name
    Do ..%ApplyProps(conn, props)
    Set sc = conn.%Save()
    If $$$ISERR(sc) Quit sc
    Do ..%EnforceSingleDefault(conn)
    Quit $$$OK
}

/// Update an existing connection. Name is frozen — props.name is ignored.
ClassMethod Update(name As %String, props As %DynamicObject) As %Status
{
    Set id = ..%IdOf(name)
    If id = "" Quit $$$ERROR($$$GeneralError, "Connection '"_name_"' not found")
    Set conn = ##class(AgenticInterop.Data.Connection).%OpenId(id)
    Do ..%ApplyProps(conn, props)
    Set conn.UpdatedAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
    Set sc = conn.%Save()
    If $$$ISERR(sc) Quit sc
    Do ..%EnforceSingleDefault(conn)
    Quit $$$OK
}

/// Delete a connection. Refuses to delete Core rows. Also wipes the secret.
ClassMethod Delete(name As %String) As %Status
{
    Set id = ..%IdOf(name)
    If id = "" Quit $$$ERROR($$$GeneralError, "Connection '"_name_"' not found")
    Set conn = ##class(AgenticInterop.Data.Connection).%OpenId(id)
    If conn.Core Quit $$$ERROR($$$GeneralError, "Cannot delete core connection '"_name_"'")
    Do ..ClearSecret(name)
    Quit ##class(AgenticInterop.Data.Connection).%DeleteId(id)
}

/// Write or rotate the secret. Stored as a CUSTOM-usage %Wallet.KeyValue
/// with payload {"value":<value>}.
ClassMethod SetSecret(name As %String, value As %String) As %Status
{
    Do ..EnsureWallet()
    If ..%IdOf(name) = "" Quit $$$ERROR($$$GeneralError, "Connection '"_name_"' not found")
    If value = "" Quit $$$ERROR($$$GeneralError, "Secret value is empty")
    Set secretName = ..#WALLETCOLLECTION _ "." _ name
    Set existsObj = ""
    Set existsSc = $$$OK
    Set exists = ##class(%Wallet.KeyValue).Exists(secretName, .existsObj, .existsSc)
    If exists {
        Quit ##class(%Wallet.KeyValue).Modify(secretName, {"Secret":{"value":(value)}})
    }
    Quit ##class(%Wallet.KeyValue).Create(secretName, {"Secret":{"value":(value)},"Usage":["CUSTOM"]})
}

/// Remove the secret. Connection row remains.
ClassMethod ClearSecret(name As %String) As %Status
{
    Set secretName = ..#WALLETCOLLECTION _ "." _ name
    Set existsObj = ""
    Set existsSc = $$$OK
    If '##class(%Wallet.KeyValue).Exists(secretName, .existsObj, .existsSc) Quit $$$OK
    Quit ##class(%Wallet.KeyValue).Delete(secretName)
}

/// True iff a non-empty secret is on file in the wallet.
ClassMethod HasSecret(name As %String) As %Boolean
{
    Set secretName = ..#WALLETCOLLECTION _ "." _ name
    Set existsObj = ""
    Set existsSc = $$$OK
    Quit ''##class(%Wallet.KeyValue).Exists(secretName, .existsObj, .existsSc)
}

/// Make a minimal ChatComplete call against the configured provider to
/// verify network reachability + credentials + model access. Never
/// throws — returns {ok, error?, model?, latencyMs?, sample?} so the
/// UI can render either a green check or a red error inline.
ClassMethod Test(name As %String) As %DynamicObject
{
    Set out = {}
    Set out.connection = name
    Set ok = 0
    Set errMsg = ""
    Set sampleVal = ""
    Set latencyMs = ""
    Set modelVal = ""
    Try {
        Set obj = ..Get(name)
        If obj = "" {
            Set errMsg = "Connection '" _ name _ "' not found"
        } ElseIf 'obj.enabled {
            Set errMsg = "Connection is disabled"
        } ElseIf 'obj.hasSecret {
            Set errMsg = "No API key set — paste one and Save first"
        } ElseIf obj.model = "" {
            Set errMsg = "No model set"
        } Else {
            Set start = $zhorolog
            Set provider = ..GetProvider(name)
            Set messages = [{"role":"user","content":"reply with the single word ok"}]
            Set response = provider.ChatComplete(obj.model, messages, 0.0, 16)
            Set ok = 1
            Set modelVal = obj.model
            Set latencyMs = $fnumber(($zhorolog - start) * 1000, "", 0)
            If $isobject(response) {
                Try { Set sampleVal = response.Content } Catch  {}
                If sampleVal = "" { Try { Set sampleVal = response.content } Catch  {} }
                If sampleVal = "" { Try { Set sampleVal = response.Text } Catch  {} }
                If sampleVal = "" { Try { Set sampleVal = response.text } Catch  {} }
            }
        }
    } Catch ex {
        Set errMsg = $extract(ex.DisplayString(), 1, 400)
    }
    Set out.ok = ok
    If 'ok { Set out.error = errMsg }
    If ok {
        Set out.model = modelVal
        Set out.latencyMs = latencyMs
        Set out.sample = $extract(sampleVal, 1, 120)
    }
    // Persist on the row so a successful test survives reloads.
    Set id = ..%IdOf(name)
    If id '= "" {
        Set conn = ##class(AgenticInterop.Data.Connection).%OpenId(id)
        If $isobject(conn) {
            Set conn.LastTestOk = ''ok
            Set conn.LastTestAt = $ZDATETIME($ZTIMESTAMP, 3, 1)
            If ok {
                Set conn.LastTestModel = modelVal
                Set conn.LastTestLatencyMs = +latencyMs
                Set conn.LastTestError = ""
            } Else {
                Set conn.LastTestError = $extract(errMsg, 1, 1000)
            }
            Do conn.%Save()
        }
    }
    Quit out
}

/// Resolve a connection name to a configured %AI.Provider, ready to
/// pass to %AI.Agent.%New(provider). Throws on missing/disabled/no-secret.
ClassMethod GetProvider(name As %String = "") As %AI.Provider
{
    If name = "" Set name = ..%DefaultName()
    If name = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "No default connection configured"))
    Set obj = ..Get(name)
    If obj = "" $$$ThrowStatus($$$ERROR($$$GeneralError, "Connection '"_name_"' not found"))
    If 'obj.enabled $$$ThrowStatus($$$ERROR($$$GeneralError, "Connection '"_name_"' is disabled"))
    If 'obj.hasSecret $$$ThrowStatus($$$ERROR($$$GeneralError, "Connection '"_name_"' has no secret — call SetSecret first"))
    Set secretName = ..#WALLETCOLLECTION _ "." _ name
    Set raw = ##class(%Wallet.KeyValue).GetSecretValue(secretName)
    Set parsed = ##class(%DynamicAbstractObject).%FromJSON(raw)
    Set secret = parsed.value
    Set settings = ..%BuildSettings(obj, secret)
    // Bedrock's API-key flow uses AWS_BEARER_TOKEN_BEDROCK at the
    // process level (the Rust LLM library reads it directly).
    If obj.provider = "bedrock" {
        Try { Do $system.Util.SetEnviron("AWS_BEARER_TOKEN_BEDROCK", secret) } Catch  {}
        Try { If obj.region '= "" Do $system.Util.SetEnviron("AWS_REGION", obj.region) } Catch  {}
    }
    Quit ##class(%AI.Provider).Create(obj.provider, settings)
}

/// Idempotent — creates the wallet resource + collection if missing.
/// Run from %SYS so we can touch Security.Resources.
ClassMethod EnsureWallet() As %Status
{
    Set sc = $$$OK
    New $namespace
    Set $namespace = "%SYS"
    If '##class(Security.Resources).Exists(..#WALLETRESOURCE) {
        Set sc = ##class(Security.Resources).Create(..#WALLETRESOURCE, "AgenticInterop LLM connection secrets", "")
        If $$$ISERR(sc) Quit sc
    }
    If '##class(%Wallet.Collection).%ExistsId(..#WALLETCOLLECTION) {
        Set sc = ##class(%Wallet.Collection).Create(..#WALLETCOLLECTION, {"Resource":(..#WALLETRESOURCE)})
        If $$$ISERR(sc) Quit sc
    }
    Quit sc
}

ClassMethod %BuildSettings(obj As %DynamicObject, secret As %String) As %DynamicObject [ Internal ]
{
    Set s = {}
    If obj.provider = "openai" {
        Set s."api_key" = secret
        If obj.baseURL '= "" Set s."base_url" = obj.baseURL
    } ElseIf obj.provider = "anthropic" {
        Set s."api_key" = secret
        If obj.baseURL '= "" Set s."base_url" = obj.baseURL
    } ElseIf obj.provider = "gemini" {
        Set s."api_key" = secret
        If obj.baseURL '= "" Set s."base_url" = obj.baseURL
    } ElseIf obj.provider = "bedrock" {
        // Bedrock specifically wants `bearer_token`, NOT `api_key`. The
        // Rust LLM library's Bedrock client looks bearer_token up in
        // settings; api_key is silently ignored.
        If obj.region '= "" Set s.region = obj.region
        Set s."bearer_token" = secret
        If obj.baseURL '= "" Set s."base_url" = obj.baseURL
    } ElseIf obj.provider = "azure-openai" {
        Set s."api_key" = secret
        If obj.baseURL '= "" Set s.endpoint = obj.baseURL
        If obj.model '= "" Set s.deployment = obj.model
    } ElseIf obj.provider = "nim" {
        If obj.baseURL '= "" Set s."base_url" = obj.baseURL
        If secret '= "" Set s."api_key" = secret
    }
    Quit s
}

ClassMethod %ApplyProps(conn As AgenticInterop.Data.Connection, props As %DynamicObject) [ Internal ]
{
    If props.%IsDefined("displayName") Set conn.DisplayName = $zstrip(props.displayName, "<>W")
    If props.%IsDefined("description") Set conn.Description = props.description
    If props.%IsDefined("provider")    Set conn.Provider    = $zstrip(props.provider, "<>W")
    If props.%IsDefined("model")       Set conn.Model       = $zstrip(props.model, "<>W")
    If props.%IsDefined("region")      Set conn.Region      = $zstrip(props.region, "<>W")
    If props.%IsDefined("baseURL")     Set conn.BaseURL     = $zstrip(props.baseURL, "<>W")
    If props.%IsDefined("maxTokens")   Set conn.MaxTokens   = props.maxTokens
    If props.%IsDefined("enabled")     Set conn.Enabled     = ''props.enabled
    If props.%IsDefined("isDefault")   Set conn.IsDefault   = ''props.isDefault
}

ClassMethod %EnforceSingleDefault(conn As AgenticInterop.Data.Connection) [ Internal ]
{
    If 'conn.IsDefault Quit
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"UPDATE AgenticInterop_Data.LLMConnection SET IsDefault = 0 WHERE Name <> ?", conn.Name)
}

ClassMethod %IdOf(name As %String) As %String [ Internal ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM AgenticInterop_Data.LLMConnection WHERE Name = ?", name)
    If rs.%Next() Quit rs.%GetData(1)
    Quit ""
}

ClassMethod %DefaultName() As %String [ Internal ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 Name FROM AgenticInterop_Data.LLMConnection WHERE IsDefault = 1 AND Enabled = 1")
    If rs.%Next() Quit rs.%GetData(1)
    Quit ""
}

ClassMethod %ValidName(name As %String) As %Boolean [ Internal ]
{
    If (name = "") || ($length(name) > 100) Quit 0
    Quit name?1L.99(1L,1N,1"-")
}

/// Idempotent — ensures the wallet AND the bedrock-default row exist.
ClassMethod %EnsureSeed() [ Internal ]
{
    Do ..EnsureWallet()
    If ..%IdOf(..#DEFAULTNAME) '= "" Quit
    Set conn = ##class(AgenticInterop.Data.Connection).%New()
    Set conn.Name = ..#DEFAULTNAME
    Set conn.DisplayName = "AWS Bedrock (default)"
    Set conn.Description = "Default Bedrock connection. Set the secret via the admin UI to activate."
    Set conn.Provider = "bedrock"
    Set conn.Model = "global.anthropic.claude-sonnet-4-20250514-v1:0"
    Set conn.Region = "us-east-1"
    Set conn.MaxTokens = 8192
    Set conn.Enabled = 1
    Set conn.IsDefault = 1
    Set conn.Core = 1
    $$$ThrowOnError(conn.%Save())
}

}
