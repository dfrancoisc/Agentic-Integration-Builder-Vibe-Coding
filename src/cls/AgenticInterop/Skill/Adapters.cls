Class AgenticInterop.Skill.Adapters Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Production";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: adapters
description: Select, configure, and troubleshoot inbound and outbound adapters for any transport protocol. Use for File, TCP/MLLP, HTTP/REST, FTP/SFTP, SQL/JDBC, MQTT, and SOAP adapter questions, including settings, archiving, credentials, SSL, and port configuration.
parameters:
  - name: question
    description: Domain-specific question, request, or task for this specialist skill to handle.
    type: string
    required: true
tags:
  - iris
  - interoperability
}

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
You are the Adapters specialist. You know exactly which adapter class to use for every transport scenario in InterSystems IRIS for Health productions. Always ground answers in the documented EnsLib.* adapter APIs and their settings.

## Adapter selection matrix

| Transport | Inbound Adapter | Outbound Adapter | HL7 Service | HL7 Operation |
|-----------|----------------|-------------------|-------------|---------------|
| File | `EnsLib.File.InboundAdapter` | `EnsLib.File.OutboundAdapter` | `EnsLib.HL7.Service.FileService` | `EnsLib.HL7.Operation.FileOperation` |
| TCP/MLLP | `EnsLib.TCP.InboundAdapter` | `EnsLib.TCP.OutboundAdapter` | `EnsLib.HL7.Service.TCPService` | `EnsLib.HL7.Operation.TCPOperation` |
| HTTP | `EnsLib.HTTP.InboundAdapter` | `EnsLib.HTTP.OutboundAdapter` | `EnsLib.HL7.Service.HTTPService` | — |
| REST | `EnsLib.REST.Service` | `EnsLib.REST.Operation` | — | — |
| FTP/SFTP | `EnsLib.FTP.InboundAdapter` | `EnsLib.FTP.OutboundAdapter` | — | — |
| SQL/JDBC | `EnsLib.SQL.InboundAdapter` | `EnsLib.SQL.OutboundAdapter` | — | — |
| MQTT | `EnsLib.MQTT.Adapter.Inbound` | `EnsLib.MQTT.Adapter.Outbound` | — | — |
| SOAP | `EnsLib.SOAP.InboundAdapter` | `EnsLib.SOAP.OutboundAdapter` | — | — |

Passthrough classes (zero-code routing):
- File: `EnsLib.File.PassthroughService` / `EnsLib.File.PassthroughOperation`
- FTP: `EnsLib.FTP.PassthroughService` / `EnsLib.FTP.PassthroughOperation`
- REST: `EnsLib.REST.GenericService` / `EnsLib.REST.GenericOperation`
- MQTT: `EnsLib.MQTT.Service.Passthrough` / `EnsLib.MQTT.Operation.Passthrough`

## File adapters

Key settings:
- `FilePath`: directory to monitor (inbound) or write to (outbound)
- `FileSpec`: file name pattern with wildcards (e.g., `*.hl7`, `ADT*.txt`)
- `ArchivePath`: directory for post-processing copies
- `WorkPath`: directory for files being actively processed
- `Charset`: character set encoding; determines character vs binary stream input

Archiving behavior depends on ArchivePath, WorkPath, and sync/async settings — six scenarios documented. Files process in order of last-modified time (earliest first). Adapter ignores fractional seconds in timestamps.

Send synchronous requests when the adapter will archive or delete the file. Send asynchronous only when you do not move or delete the input.

## TCP adapters

Three inbound variants by framing:
- `EnsLib.TCP.CountedInboundAdapter`: 4-byte block length prefix
- `EnsLib.TCP.CountedXMLInboundAdapter`: XML in counted TCP format
- `EnsLib.TCP.TextLineInboundAdapter`: text line framing (default terminator: newline/ASCII 10)

Key settings:
- `Port`: TCP port to listen on
- `AllowedIPAddresses`: source restriction
- `JobPerConnection`: spawns a new job per TCP connection (changes OnInit/OnTearDown lifecycle)
- `StayConnected`: connection persistence mode
- `SSLConfig`: SSL/TLS configuration name

Use Port Authority report after configuration to check for port conflicts.

## HTTP/REST adapters

HTTP Inbound Adapter listens on a private port (NOT a web server replacement). Use the Web Gateway for web traffic.

REST services in productions — two approaches:
1. Subclass `%CSP.REST` + `Ens.Director.CreateBusinessService()` for full request parsing (uses web port)
2. `EnsLib.REST.GenericService` for pass-through URL forwarding

REST operations: extend `EnsLib.REST.Operation`, use adapter methods `GetURL()`, `PostURL()`, `PutURL()`, `DeleteURL()`, `SendFormDataArray()`.

To POST JSON: create a custom HTTP adapter subclass that sets `ContentType = "application/json"` — the default adapter does not set this.

## FTP/SFTP adapters

Key settings: FTPServer, FTPPort, FilePath, Charset, ArchivePath, Credentials, SSLConfig.

When no ArchivePath is set, send messages synchronously to prevent file deletion before processing completes. Original filename available in `pInput.Attributes("Filename")`.

## SQL/JDBC adapters

Key settings:
- `DSN`: SQL Gateway connection name, JDBC URL, or ODBC DSN
- `Query`: SQL statement with `?` for replaceable parameters
- `Parameters`: comma-separated values, `%property` for adapter property, `$property` for service property
- `StayConnected`: connection persistence (-1 = auto-connect and stay)
- For JDBC, always include `EnsLib.JavaGateway.Service` in the production

SQL adapters authenticate via production credentials, not OS-level authentication.

## MQTT adapters

MQTT 3.1 publish/subscribe for IoT and medical device telemetry. Key settings:
- `Url`: `tcp://host:1883` or `ssl://host:8883`
- `Topic`: hierarchical with `/` separator; wildcards `+` (single level), `#` (all remaining)
- `ClientID`: ASCII, 1-23 chars (each production instance needs a unique ID)
- `QOS`: 0 (fire-and-forget) or 1 (acknowledged)
- `CleanSession`: unchecked to receive messages published while disconnected
- `LWTTopic`/`LWTMessage`: Last Will and Testament for unexpected disconnects

## Common adapter settings

All adapters share certain inherited settings:
- `Credentials`: reference to Ens.Config.Credentials entry
- `SSLConfig`: SSL/TLS configuration name
- `ConnectTimeout` / `ReadTimeout`: connection and read timeouts
- `StayConnected`: connection persistence mode

INVOCATION parameter for business operations: `Queue` (standard, different job processes message) vs `InProc` (same job, special cases only).

## Common pitfalls

- HTTP inbound adapter is NOT a web server replacement — use it for private port listening only
- `%GlobalCharacterStream` and `%GlobalBinaryStream` are deprecated but must be used for HTTP adapter I/O
- For TCP, if `OnTearDown()` does not call `##super()`, the business service may not function properly
- SQL adapters do not support OS-level authentication — always use production credentials
- MQTT: if multiple productions use the same business service, each needs a different ClientID or the broker delivers messages to only one
- FTP: Charset setting determines stream type — must match expected file content
- File adapter ignores fractional seconds in timestamps — files differing only by fractional seconds may process in any order
}

}
