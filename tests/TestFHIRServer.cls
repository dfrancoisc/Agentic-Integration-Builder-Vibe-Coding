/// Smoke + contract test for the FHIR Server toolset
/// (AgenticInterop.Tool.FHIRServer). Discovers a FHIR-enabled foundation
/// namespace, then exercises the read-only tools and a full
/// create -> read -> search -> $validate -> delete data cycle against the
/// discovered endpoint. Self-cleaning. Run from any HS-enabled namespace:
///   do ##class(Test.FHIRServer).Run()
Class Test.FHIRServer
{

ClassMethod Run()
{
    Write "=== FHIR Server toolset test ===",!
    Set pass = 0, fail = 0

    ; --- Contract: tool discovery ---
    Set co = ##class(%Dictionary.CompiledClass).%OpenId("AgenticInterop.Tool.FHIRServer")
    Set tc = 0
    If $isobject(co) {
        For i=1:1:co.Methods.Count() {
            Set m = co.Methods.GetAt(i)
            If m.ClassMethod, $extract(m.Name) '= "%" { Set tc = tc + 1 }
        }
    }
    Do ..Assert("tool class exposes >= 15 tools (got " _ tc _ ")", tc >= 15, .pass, .fail)

    ; --- Discover a FHIR-enabled namespace ---
    Set rDisc = ##class(AgenticInterop.Tool.FHIRServer).DiscoverFHIRNamespaces()
    Do ..Assert("DiscoverFHIRNamespaces ok", rDisc.ok = 1, .pass, .fail)

    If rDisc.namespaces.%Size() = 0 {
        Write "SKIP: no FHIR-enabled namespace with an endpoint found — data tests skipped.",!
        Write "=== Done: ", pass, " passed, ", fail, " failed (data tests skipped) ===",!
        Quit
    }

    Set first = rDisc.namespaces.%Get(0)
    Set ns = first.namespace
    Set url = first.endpoints.%Get(0)
    Write "Using endpoint ", url, " in namespace ", ns,!

    ; --- List + describe + capability ---
    Set rList = ##class(AgenticInterop.Tool.FHIRServer).ListFHIREndpoints(ns)
    Do ..Assert("ListFHIREndpoints ok with >=1 endpoint", (rList.ok = 1) && (rList.total >= 1), .pass, .fail)

    Set rGet = ##class(AgenticInterop.Tool.FHIRServer).GetFHIREndpoint(url, ns)
    Do ..Assert("GetFHIREndpoint ok and exists", (rGet.ok = 1) && (rGet.exists = 1), .pass, .fail)

    Set rCap = ##class(AgenticInterop.Tool.FHIRServer).GetCapabilityStatement(url, 0, ns)
    Do ..Assert("GetCapabilityStatement ok with resource types", (rCap.ok = 1) && (rCap.resourceTypeCount > 0), .pass, .fail)

    Set rCount = ##class(AgenticInterop.Tool.FHIRServer).CountFHIRResources(url, "", ns)
    Do ..Assert("CountFHIRResources survey ok", rCount.ok = 1, .pass, .fail)

    ; --- Data cycle: create -> read -> search -> validate -> delete ---
    Set pat = ##class(%DynamicObject).%New()
    Set pat.resourceType = "Patient"
    Set pat.gender = "female"
    Set nm = ##class(%DynamicObject).%New()
    Set nm.family = "ZZTestFHIRMCP"
    Set ga = ##class(%DynamicArray).%New()
    Do ga.%Push("Ada")
    Set nm.given = ga
    Set na = ##class(%DynamicArray).%New()
    Do na.%Push(nm)
    Set pat.name = na

    Set rCreate = ##class(AgenticInterop.Tool.FHIRServer).CreateFHIRResource(url, pat, ns)
    Do ..Assert("CreateFHIRResource ok (HTTP 201)", (rCreate.ok = 1) && (rCreate.created = 1), .pass, .fail)
    Set pid = $select(rCreate.%IsDefined("id"):rCreate.id, 1:"")

    If pid '= "" {
        Set rRead = ##class(AgenticInterop.Tool.FHIRServer).ReadFHIRResource(url, "Patient", pid, ns)
        Do ..Assert("ReadFHIRResource ok", rRead.ok = 1, .pass, .fail)

        Set rSearch = ##class(AgenticInterop.Tool.FHIRServer).SearchFHIRResources(url, "Patient", "family=ZZTestFHIRMCP", 5, ns)
        Do ..Assert("SearchFHIRResources finds the patient", (rSearch.ok = 1) && (rSearch.resourceCount >= 1), .pass, .fail)

        Set rValid = ##class(AgenticInterop.Tool.FHIRServer).ValidateFHIRResource(url, pat, "", ns)
        Do ..Assert("ValidateFHIRResource ok and valid", (rValid.ok = 1) && (rValid.valid = 1), .pass, .fail)

        Set rDel = ##class(AgenticInterop.Tool.FHIRServer).DeleteFHIRResource(url, "Patient", pid, ns)
        Do ..Assert("DeleteFHIRResource ok (cleanup)", (rDel.ok = 1) && (rDel.deleted = 1), .pass, .fail)
    } Else {
        Write "WARN: create returned no id; skipping read/search/validate/delete.",!
    }

    ; --- Guard: provisioning refuses to overwrite an existing endpoint ---
    Set rProv = ##class(AgenticInterop.Tool.FHIRServer).CreateFHIREndpoint(url, "hl7.fhir.r4.core@4.0.1", "HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy", "", ns)
    Do ..Assert("CreateFHIREndpoint refuses existing endpoint", rProv.ok = 0, .pass, .fail)

    Write "=== Done: ", pass, " passed, ", fail, " failed ===",!
}

ClassMethod Assert(label As %String, cond As %Boolean, ByRef pass, ByRef fail)
{
    If cond {
        Set pass = pass + 1
        Write "  PASS: ", label,!
    } Else {
        Set fail = fail + 1
        Write "  FAIL: ", label,!
    }
}

}
