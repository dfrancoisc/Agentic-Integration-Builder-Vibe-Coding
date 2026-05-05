Class AgenticInterop.Skill.RestInProductions Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Production";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: rest-in-productions
description: Build REST services and REST operations inside productions. Use for %CSP.REST subclasses, EnsLib.REST.Operation, HTTP adapter methods, or JSON POST patterns.
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
You are the REST-in-productions specialist. IRIS productions can both expose REST services (inbound) and call external REST services (outbound).

## REST services (inbound) — three approaches

1. Subclass `%CSP.REST` and instantiate it as a business service via `Ens.Director.CreateBusinessService()`. Use this when the production needs to PARSE and PROCESS the request body. Uses the IRIS web port.
2. Use the pass-through `EnsLib.REST.GenericService` — passes the URL through to an external server with minimal change. The ESB pattern, see Configuring ESB Services and Operations.
3. Use `EnsLib.REST.Service` — built-in business service that works with the HTTP/REST inbound adapter. The dispatch methods receive additional arguments containing input/output streams. Classes receiving forwarded `<Map>` requests must extend `%CSP.REST`, NOT `EnsLib.REST.Service`.

For approach 1, register a CSP web app with `DispatchClass = MyApp.MyRESTService`. The class declares a `UrlMap` XData block:

```objectscript
XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/patients/:id" Method="GET" Call="GetPatient"/>
  <Route Url="/patients" Method="POST" Call="CreatePatient"/>
</Routes>
}
```

The dispatch class extends `%CSP.REST`. Inside, use `%request.Content` to read body, `%response.SetHeader()` for response headers, write JSON via `Set obj = ##class(%DynamicObject).%New() ... Do obj.%ToJSON()`.

## REST operations (outbound) — class shape

Subclass `EnsLib.REST.Operation` (which uses the HTTP outbound adapter):

```objectscript
Class MyApp.WeatherOp Extends EnsLib.REST.Operation
{
Parameter INVOCATION = "Queue";

Method GetWeather(pRequest As MyApp.WeatherRequest, Output pResponse As MyApp.WeatherResponse) As %Status
{
    Try {
        Set tURL = ..Adapter.URL_"?q="_pRequest.City_"&units=imperial"
        Set tSC = ..Adapter.GetURL(tURL, .tHttpResponse)

        // On error with response body, append the response body to the status
        If $$$ISERR(tSC), $IsObject(tHttpResponse), $IsObject(tHttpResponse.Data), tHttpResponse.Data.Size {
            Set tSC = $$$ERROR($$$EnsErrGeneral, $$$StatusDisplayString(tSC)_":"_tHttpResponse.Data.Read())
        }
        Quit:$$$ISERR(tSC) tSC

        If $IsObject(tHttpResponse) {
            Set pResponse = ##class(MyApp.WeatherResponse).%New()
            Set tSC = ..JSONStreamToObject(tHttpResponse.Data, .tProxy)
            If tSC {
                Set pResponse.Temperature = tProxy.main.temp_"F"
            }
        }
    } Catch {
        Set tSC = $$$SystemError
    }
    Quit tSC
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="MyApp.WeatherRequest"><Method>GetWeather</Method></MapItem>
</MapItems>
}
}
```

## HTTP adapter methods
The HTTP outbound adapter (`EnsLib.HTTP.OutboundAdapter`) provides:
- `GetURL(url, .response)` — HTTP GET.
- `PostURL(url, .response, body)` — HTTP POST.
- `PutURL(url, .response, body)` — HTTP PUT.
- `DeleteURL(url, .response)` — HTTP DELETE.
- `SendFormDataArray(.response, method, request, .formVarNames, .formData)` — variadic HTTP method, form-encoded.

All operate relative to the adapter's `URL` setting (the base URL of the external service).

## Posting JSON

Default ContentType is `application/x-www-form-urlencoded`. To POST JSON, override the adapter:

```objectscript
Class MyApp.JSONHTTPAdapter Extends EnsLib.HTTP.OutboundAdapter
{
Method Post(Output pHttpResponse As %Net.HttpResponse, pFormVarNames As %String, pData...) As %Status
{
    Quit ..SendFormDataArray(.pHttpResponse, "POST", ..GetRequest(), .pFormVarNames, .pData)
}

ClassMethod GetRequest() As %Net.HttpRequest
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set request.ContentType = "application/json"
    Quit request
}
}
```

Then build the JSON body:

```objectscript
Set tRequest = ##class(%DynamicObject).%New()
Set tRequest.transactionid = pRequest.transactionid
Set tRequest.participantid = pRequest.participantid
Set tPayload = tRequest.%ToJSON()
Set tSC = ..Adapter.Post(.tHttpResponse, , tPayload)
```

Note the empty middle parameter — formVarNames is unused when posting raw JSON.

## Helper methods

- `..JSONStreamToObject(stream, .obj)` — parse a JSON HTTP response stream into a `%DynamicObject` proxy. Methods on the proxy: `obj.main.temp`, `obj.results.%GetIterator()`, etc.
- `..JSONObjectToStream(obj)` — serialize back to a stream.

## Testing in the Production Configuration page

If you don't have a business process driving the operation, test it from Interoperability > Configure > Production: select the operation, click the Actions tab, click Test. Provide a sample request message — the operation runs and the response shows in the test output.

## Common pitfalls
- Forgetting `INVOCATION = "Queue"` on the operation — defaults to `"InProc"` requiring `Pool Size = 0`. Mismatch → operation never runs.
- Using `..Adapter.GetURL` with a full URL → the adapter prepends its `URL` setting → double base URL. Use the relative path only.
- Forgetting to set `ContentType = "application/json"` for JSON POSTs — the server rejects with 415 Unsupported Media Type.
- Reading `tHttpResponse.Data` twice — it's a stream; rewind with `Do tHttpResponse.Data.Rewind()` before re-read.
- Catch block swallowing `tSC` instead of `$$$SystemError` — loses the original error context. Always `Set tSC = $$$SystemError` in the catch.
}

}
