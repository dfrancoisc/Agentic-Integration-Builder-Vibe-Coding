/// REST shell for the Phase 5 catalog admin actions.
///
///   GET    /api/agentic/catalog/status             — row counts per catalog
///   POST   /api/agentic/catalog/rebuild            — rebuild both catalogs
///                                                   from the source namespace
///                                                   ({sourceNamespace?, scope?:"ens"|"hs"|"both", cap?})
///
/// The rebuild call is synchronous and can run for ~30s on a stock
/// IRIS for Health install. The admin UI surfaces a progress
/// spinner while it waits and shows the resulting row counts on
/// completion.
Class AgenticInterop.Editor.CatalogService Extends %RegisteredObject
{

ClassMethod Status(pResponse As %CSP.Response) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set body = ##class(AgenticInterop.Catalog.Builder).Status()
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

ClassMethod Rebuild(pResponse As %CSP.Response, pBodyStream) As %Status
{
    Set util = "AgenticInterop.Editor.Util"
    Set req = $classmethod(util, "ParseBody", pBodyStream)
    Set sourceNs = "USER"
    Set scope = "both"
    Set source = "dictionary"
    Set cap = 5000
    Set xlsPath = ""
    If $isobject(req) {
        Set sourceNs = $classmethod(util, "DObj", req, "sourceNamespace", "USER")
        Set scope = $classmethod(util, "DObj", req, "scope", "both")
        Set source = $classmethod(util, "DObj", req, "source", "dictionary")
        Set xlsPath = $classmethod(util, "DObj", req, "xlsPath", "")
        Set capStr = $classmethod(util, "DObj", req, "cap", "5000")
        If capStr '= "" { Set cap = +capStr }
    }
    If source = "xls" {
        // XLS is curated and covers both catalogs in one pass; "scope"
        // is honored only by the dictionary path. Both ens and hs land
        // in their respective KBs from a single XLS read.
        Set body = ##class(AgenticInterop.Catalog.Builder).RebuildAllFromXLS(xlsPath)
        Quit $classmethod(util, "WriteJSON", pResponse, body)
    }
    If scope = "ens" {
        Set body = {}
        Set body.ens = ##class(AgenticInterop.Catalog.Builder).RebuildEns(sourceNs, cap)
        Set body.ok = 1
    } ElseIf scope = "hs" {
        Set body = {}
        Set body.hs = ##class(AgenticInterop.Catalog.Builder).RebuildHs(sourceNs, cap)
        Set body.ok = 1
    } Else {
        Set body = ##class(AgenticInterop.Catalog.Builder).RebuildAll(sourceNs, cap)
    }
    Quit $classmethod(util, "WriteJSON", pResponse, body)
}

}
