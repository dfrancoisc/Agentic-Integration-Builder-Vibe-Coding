/// %AI.Tool source for the Compat (cross-version downgrade) toolset. Each public
/// ClassMethod is auto-discovered by the framework as a tool. These tools answer
/// the Health Connect BASE/UAT -> LIVE promotion question: "will code that
/// compiles on a newer version break when deployed to an older one?"
///
/// Direction matters. InterSystems documents UPGRADE breakage (old code, new
/// server). These tools do the opposite -- forward-incompatibility: members
/// present in the higher (From) version but absent in the lower (To) version, so
/// code authored in a newer BASE/UAT fails to compile/run when promoted to an
/// older LIVE server. Data comes from public Documatic; read-only, no mutation.
///
/// Composed into AgenticInterop.ToolSet.Compat via <Include>.
Class AgenticInterop.Tool.Compat Extends %AI.Tool
{

Parameter DISCOVERYLIMIT = "AgenticInterop.Tool.Compat";

/// Check whether a specific class member exists in a lower Health Connect version.
/// Use this to answer "if I promote code that uses <Class>.<member> from
/// <fromVersion> to <toVersion>, will it break?" -- e.g.
/// Ens.BPL.Property / DeleteWithContext promoted from 2026.1 to 2025.1.
///
/// className: fully-qualified class, e.g. "Ens.BPL.Property".
/// member: property/method/parameter name, e.g. "DeleteWithContext".
/// fromVersion: the HIGHER version the code was authored on (e.g. "2026.1", "latest").
/// toVersion: the LOWER version being promoted to (e.g. "2025.1", "2025.1.3").
/// library: Documatic library, default "ENSLIB" (use "HSLIB" for HS.* classes).
///
/// Returns: { ok, class, member, kind, existsInFrom, existsInTo, classExistsInTo,
/// breaks }. breaks=1 means the reference will fail on toVersion. Read-only.
ClassMethod CheckDowngradeRisk(className As %String, member As %String, fromVersion As %String = "2026.1", toVersion As %String = "2025.1", library As %String = "ENSLIB") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("CheckDowngradeRisk")
    Set out = {}
    Try {
        Set json = ##class(AgenticInterop.Compat.Scraper).CheckMember(fromVersion, toVersion, library, className, member)
        Set out = ##class(%DynamicAbstractObject).%FromJSON(json)
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("CheckDowngradeRisk", out)
    Quit out
}

/// List every member of a class that exists in a higher Health Connect version but
/// is missing from a lower one -- the full set of forward-incompatible additions
/// for that class. Use when the user asks "what changed in <Class> between
/// <fromVersion> and <toVersion>?" or "is <Class> safe to downgrade?".
///
/// className: fully-qualified class, e.g. "Ens.BPL.Property".
/// fromVersion: HIGHER version (e.g. "2026.1"). toVersion: LOWER version (e.g. "2025.1").
/// library: Documatic library, default "ENSLIB" ("HSLIB" for HS.*).
///
/// Returns: { ok, class, from, to, newClass, added:{property:[...],method:[...],
/// parameter:[...]}, totalAdded }. newClass=1 means the whole class is absent in
/// toVersion. Read-only.
ClassMethod ListVersionAdditions(className As %String, fromVersion As %String = "2026.1", toVersion As %String = "2025.1", library As %String = "ENSLIB") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ListVersionAdditions")
    Set out = {}
    Try {
        Set json = ##class(AgenticInterop.Compat.Scraper).DiffClass(fromVersion, toVersion, library, className)
        Set out = ##class(%DynamicAbstractObject).%FromJSON(json)
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ListVersionAdditions", out)
    Quit out
}

/// Scan a block of ObjectScript / DTL / BPL code for fully-qualified member
/// references (##class(Class).Method(...) and ##class(Class).#Parameter) that will
/// fail when the code is promoted from a higher Health Connect version to a lower
/// one. Use when the user pastes code and asks "will this deploy to our older LIVE
/// server?" before promoting from BASE/UAT.
///
/// code: the source text to scan.
/// fromVersion: HIGHER version the code was authored on. toVersion: LOWER target.
/// library: Documatic library to resolve classes against, default "ENSLIB".
///
/// Returns: { ok, from, to, scanned, findings:[{class, member, kind, reason}] }.
/// An empty findings array means no fully-qualified reference will break. Note:
/// references through a typed local variable and DTL virtual-document paths are not
/// resolved here -- use list_version_additions on the relevant class for those.
/// Read-only.
ClassMethod ScanCodeForDowngradeRisk(code As %String, fromVersion As %String = "2026.1", toVersion As %String = "2025.1", library As %String = "ENSLIB") As %DynamicObject
{
    Do ##class(AgenticInterop.Agent.Manager).ToolStart("ScanCodeForDowngradeRisk")
    Set out = {}
    Try {
        Set json = ##class(AgenticInterop.Compat.Scraper).ScanCode(fromVersion, toVersion, code, library)
        Set out = ##class(%DynamicAbstractObject).%FromJSON(json)
    } Catch ex {
        Set out.ok = 0
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Do ##class(AgenticInterop.Agent.Manager).ToolDone("ScanCodeForDowngradeRisk", out)
    Quit out
}

}
