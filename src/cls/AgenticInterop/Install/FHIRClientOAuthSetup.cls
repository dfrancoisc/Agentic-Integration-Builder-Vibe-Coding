/// Provisions the IRIS-standard OAuth 2.0 client used by the universal
/// HL7-to-FHIR pipeline's outbound HTTPOperation.
///
/// This class creates THREE separate config items per the InterSystems
/// Security Reference (System Administration > Security > OAuth 2.0):
///
///   1. SSL/TLS configuration `FHIR-Client-SSL` (TLS client, no client cert),
///      used to encrypt requests to the FHIR server and OAuth token endpoint.
///   2. `OAuth2.ServerDefinition` for the authorization server, with manual
///      metadata (issuer + token endpoint + supported grant types). Manual
///      because the placeholder host `fhir.example.com` does not implement
///      OpenID discovery; replace the issuer + token endpoint when a real
///      FHIR server URL is known.
///   3. `OAuth2.Client` named `FHIR-OAuth-Client`, `ClientType=confidential`,
///      grant type `client_credentials`. ClientId + ClientSecret are
///      placeholders; replace them with the real credentials issued by the
///      target FHIR server when known.
///
/// Why this class instead of the BFC OAuth installer (HS.HC.OAuth2.Server.
/// Installer): the BFC installer provisions an INTERNAL IRIS-as-authorization-
/// server and requires HS.HC.SecureCommunication to be active. We only need
/// the CLIENT side here (calling out to an EXTERNAL FHIR server), so the
/// documented OAuth2.Client.Create() API is the right entry point.
///
/// All steps are idempotent (treat "already exists" as success), so this
/// hook can run on every module activation without side effects.
///
/// Operator action after deploy: when the real FHIR server URL is known,
///   1. Update the OAuth2.ServerDefinition issuer + token_endpoint via
///      System Administration > Security > OAuth 2.0 > Client Configuration.
///   2. Update OAuth2.Client `FHIR-OAuth-Client` ClientId + ClientSecret to
///      the values issued by the FHIR server.
///   3. Update the production's `FHIR.Outbound.Server` Adapter settings
///      (HTTPServer, URL, SSLConfig) to match.
Class AgenticInterop.Install.FHIRClientOAuthSetup Extends %RegisteredObject
{

Parameter SSLCONFIGNAME = "FHIR-Client-SSL";

Parameter OAUTHCLIENTNAME = "FHIR-OAuth-Client";

Parameter ISSUERENDPOINT = "https://fhir.example.com";

Parameter TOKENENDPOINT = "https://fhir.example.com/oauth/token";

Parameter AUTHENDPOINT = "https://fhir.example.com/oauth/authorize";

Parameter PLACEHOLDERCLIENTID = "agentic-fhir-client";

Parameter PLACEHOLDERCLIENTSECRET = "placeholder-replace-when-real-server-is-known";

ClassMethod Apply() As %Status
{
    Set originalNs = $namespace
    Set status = $$$OK
    Try {
        ; Step 1: SSL config (in %SYS)
        Set $namespace = "%SYS"
        Set sslName = ..#SSLCONFIGNAME
        If '##class(Security.SSLConfigs).Exists(sslName) {
            Kill props
            Set props("Enabled") = 1
            Set sc = ##class(Security.SSLConfigs).Create(sslName, .props)
            If $$$ISERR(sc) {
                Write "FHIRClientOAuthSetup: SSL Create FAILED: "_$system.Status.GetErrorText(sc),!
                Set status = sc
                Goto done
            }
            Write "FHIRClientOAuthSetup: created SSL config "_sslName,!
        } Else {
            Write "FHIRClientOAuthSetup: SSL config "_sslName_" already exists",!
        }

        ; Step 2: OAuth2.ServerDefinition for the FHIR auth server
        Set issuer = ..#ISSUERENDPOINT
        Set existingSrv = ##class(OAuth2.ServerDefinition).OpenByIssuer(issuer)
        If '$isobject(existingSrv) {
            Set md = ##class(OAuth2.Server.Metadata).%New()
            Set md.issuer = issuer
            Set md."token_endpoint" = ..#TOKENENDPOINT
            Set md."authorization_endpoint" = ..#AUTHENDPOINT
            Set md."grant_types_supported" = $listbuild("client_credentials")
            Set md."response_types_supported" = $listbuild("token")
            Set md."subject_types_supported" = $listbuild("public")
            Set md."id_token_signing_alg_values_supported" = $listbuild("RS256")
            Kill props2
            Set props2("SSLConfiguration") = sslName
            Set props2("Metadata") = md.ExportJSON(0)
            Set sc2 = ##class(OAuth2.ServerDefinition).Create(issuer, .props2)
            If $$$ISERR(sc2) {
                Write "FHIRClientOAuthSetup: ServerDefinition Create FAILED: "_$system.Status.GetErrorText(sc2),!
                Set status = sc2
                Goto done
            }
            Write "FHIRClientOAuthSetup: created OAuth2.ServerDefinition for "_issuer,!
        } Else {
            Write "FHIRClientOAuthSetup: ServerDefinition for "_issuer_" already exists",!
        }

        ; Step 3: OAuth2.Client
        Set clientName = ..#OAUTHCLIENTNAME
        Set existingCli = ##class(OAuth2.Client).Open(clientName, .tSCcli)
        If '$isobject(existingCli) {
            Set cliMd = ##class(OAuth2.Client.Metadata).%New()
            Set cliMd."grant_types" = $listbuild("client_credentials")
            Set cliMd."token_endpoint_auth_method" = "client_secret_basic"
            Kill props3
            Set props3("ClientType") = "confidential"
            Set props3("SSLConfiguration") = sslName
            Set props3("ServerDefinition") = issuer
            Set props3("ClientId") = ..#PLACEHOLDERCLIENTID
            Set props3("ClientSecret") = ..#PLACEHOLDERCLIENTSECRET
            Set props3("Enabled") = 1
            Set props3("Metadata") = cliMd.ExportJSON(0)
            ; RedirectionEndpoint is required for confidential type; pass as
            ; URL string (the OAuth2.Endpoint serial-object form via .Create
            ; rejects with #8850 in IRIS 2026.x). Never called for the
            ; client_credentials grant — server-to-server, no user redirect.
            Set props3("RedirectionEndpoint") = "https://localhost/csp/sys/oauth2/OAuth2.Response.cls"
            Set sc3 = ##class(OAuth2.Client).Create(clientName, .props3)
            If $$$ISERR(sc3) {
                Write "FHIRClientOAuthSetup: OAuth2.Client Create FAILED: "_$system.Status.GetErrorText(sc3),!
                Set status = sc3
                Goto done
            }
            Write "FHIRClientOAuthSetup: created OAuth2.Client "_clientName,!
        } Else {
            Write "FHIRClientOAuthSetup: OAuth2.Client "_clientName_" already exists",!
        }
done    ; (label for goto on error)
    } Catch ex {
        Set status = ex.AsStatus()
    }
    Set $namespace = originalNs
    Quit status
}

ClassMethod Revert() As %Status
{
    Set originalNs = $namespace
    Set status = $$$OK
    Try {
        Set $namespace = "%SYS"
        ; Delete OAuth2.Client first (it references the ServerDefinition)
        Set cli = ##class(OAuth2.Client).Open(..#OAUTHCLIENTNAME, .tSC)
        If $isobject(cli) {
            Do ##class(OAuth2.Client).%DeleteId(cli.%Id())
            Write "FHIRClientOAuthSetup: removed OAuth2.Client "_..#OAUTHCLIENTNAME,!
        }
        ; Delete ServerDefinition
        Set srv = ##class(OAuth2.ServerDefinition).OpenByIssuer(..#ISSUERENDPOINT)
        If $isobject(srv) {
            Do ##class(OAuth2.ServerDefinition).%DeleteId(srv.%Id())
            Write "FHIRClientOAuthSetup: removed ServerDefinition "_..#ISSUERENDPOINT,!
        }
        ; Leave SSL config in place — other features may reference it.
    } Catch ex {
        Set status = ex.AsStatus()
    }
    Set $namespace = originalNs
    Quit status
}

}
