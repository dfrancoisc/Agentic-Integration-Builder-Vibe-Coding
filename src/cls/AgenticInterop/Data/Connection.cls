/// One configured LLM connection — non-secret metadata only. Modeled on
/// the Catalog.Connection pattern in dfrancoisc/new-interoperability-health,
/// adapted to AgenticInterop naming.
///
/// The secret (API key / Bearer token / etc.) lives in the IRIS Secured
/// Wallet under collection "AgenticInteropConnections" — never in this
/// row, never selectable through SQL, never returned by Get/List. Set,
/// rotate, or clear it via the dedicated methods on AgenticInterop.Connections.
///
/// SqlTableName is overridden because "Connection" is an IRIS SQL
/// reserved word — the SQL table is exposed as AgenticInterop_Data.LLMConnection.
Class AgenticInterop.Data.Connection Extends %Persistent [ SqlTableName = LLMConnection ]
{

/// Stable identifier — frozen once created, used as the lookup key
/// from agent code. Format constraint (lowercase, alpha-start,
/// alphanumeric+dash, 1-100 chars) is enforced in
/// AgenticInterop.Connections.Create rather than via a PATTERN here —
/// keeps the validation message friendlier.
Property Name As %String(MAXLEN = 100) [ Required ];

/// Operator-facing label.
Property DisplayName As %String(MAXLEN = 200);

/// Free-form notes — what this connection is for, who owns the key, etc.
Property Description As %String(MAXLEN = 2000);

/// LLM provider — one of openai, anthropic, bedrock, gemini, azure-openai, nim.
Property Provider As %String(MAXLEN = 50, VALUELIST = ",openai,anthropic,bedrock,gemini,azure-openai,nim") [ Required ];

/// Provider-specific model identifier (free text).
///   openai:        "gpt-4o", "gpt-4o-mini", ...
///   anthropic:     "claude-sonnet-4-6", "claude-opus-4-7", ...
///   bedrock:       "anthropic.claude-sonnet-4-20250514-v1:0", ...
///   gemini:        "gemini-2.5-pro", ...
///   azure-openai:  the deployment name
Property Model As %String(MAXLEN = 200);

/// AWS region (Bedrock) or Azure region. Empty for other providers.
Property Region As %String(MAXLEN = 50);

/// Optional override for the provider's base URL. Leave empty for the
/// default per-provider endpoint.
Property BaseURL As %String(MAXLEN = 500);

/// Default token cap for completions issued through this connection.
/// 0 / unset = use the provider default.
Property MaxTokens As %Integer(MAXVAL = 200000, MINVAL = 0) [ InitialExpression = 8192 ];

/// Whether this connection is available for use. Disabled rows still
/// exist for audit / re-enable but GetProvider rejects them.
Property Enabled As %Boolean [ InitialExpression = 1 ];

/// Marked as the default connection. Exactly one row should be
/// IsDefault=1 at any time — Connections enforces this on Save.
Property IsDefault As %Boolean [ InitialExpression = 0 ];

/// Built-in / shipped row that the user should not delete. Set on the
/// seeded bedrock-default row.
Property Core As %Boolean [ InitialExpression = 0 ];

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

Property UpdatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)} ];

/// Result of the most recent Test Connection. Null/empty = never tested.
Property LastTestOk As %Boolean;

Property LastTestAt As %TimeStamp;

Property LastTestModel As %String(MAXLEN = 200);

Property LastTestLatencyMs As %Integer;

Property LastTestError As %String(MAXLEN = 1000);

Index NameIdx On Name [ Unique ];

Index DefaultIdx On IsDefault;

Storage Default
{
<Data name="ConnectionDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>Name</Value></Value>
<Value name="3"><Value>DisplayName</Value></Value>
<Value name="4"><Value>Description</Value></Value>
<Value name="5"><Value>Provider</Value></Value>
<Value name="6"><Value>Model</Value></Value>
<Value name="7"><Value>Region</Value></Value>
<Value name="8"><Value>BaseURL</Value></Value>
<Value name="9"><Value>MaxTokens</Value></Value>
<Value name="10"><Value>Enabled</Value></Value>
<Value name="11"><Value>IsDefault</Value></Value>
<Value name="12"><Value>Core</Value></Value>
<Value name="13"><Value>CreatedAt</Value></Value>
<Value name="14"><Value>UpdatedAt</Value></Value>
<Value name="15"><Value>LastTestOk</Value></Value>
<Value name="16"><Value>LastTestAt</Value></Value>
<Value name="17"><Value>LastTestModel</Value></Value>
<Value name="18"><Value>LastTestLatencyMs</Value></Value>
<Value name="19"><Value>LastTestError</Value></Value>
</Data>
<DataLocation>^AgenticInterop.Data.ConnectionD</DataLocation>
<DefaultData>ConnectionDefaultData</DefaultData>
<IdLocation>^AgenticInterop.Data.ConnectionD</IdLocation>
<IndexLocation>^AgenticInterop.Data.ConnectionI</IndexLocation>
<StreamLocation>^AgenticInterop.Data.ConnectionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
