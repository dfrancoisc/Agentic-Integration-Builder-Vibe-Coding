/// Health Connect cross-version compatibility scraper (Embedded Python).
///
/// Backs the downgrade-risk tools. Given a From (higher) and To (lower) Health
/// Connect version, it fetches class member inventories from the public
/// Documatic site and reports members present in From but absent in To -- the
/// forward-incompatibility set that breaks when code authored on a newer BASE/UAT
/// environment is promoted to an older LIVE server.
///
/// Pure standard-library Python (urllib + re); no third-party packages, no
/// running Health Connect instance required -- reads only public documentation.
/// Member anchors on a Documatic page are id="<KIND>_<Name>" with the name still
/// percent-encoded, so parsing keys off those ids and un-quotes the name.
///
/// These are helper ClassMethods, NOT %AI tools. AgenticInterop.Tool.Compat wraps
/// them for the agent.
Class AgenticInterop.Compat.Scraper
{

/// Resolve a user version ('2026.2', '2025.1.3', 'latest', bare '20262') to a
/// Documatic segment for the given product. Returns the segment string.
ClassMethod ResolveSegment(version As %String, product As %String = "healthconnect") As %String [ Language = python ]
{
    import re
    v = (version or "").strip().lower()
    if v in ("", "latest"):
        return f"{product}latest"
    if v.startswith(("healthconnect", "irisforhealth", "iris")):
        return v
    digits = re.findall(r"\d+", v)
    if not digits:
        raise ValueError(f"Cannot parse version '{version}'")
    if len(digits) == 1 and len(digits[0]) >= 5:
        return f"{product}{digits[0]}"
    year = digits[0]
    minor = digits[1] if len(digits) >= 2 else "1"
    return f"{product}{year}{minor}"
}

/// Fetch the declared-member inventory of one class in one version segment.
/// Returns a JSON string: {"exists":bool,"error":str?,"members":{KIND:[names]}}.
ClassMethod Fetch(versionSeg As %String, library As %String, classname As %String) As %String [ Language = python ]
{
    import json, re, urllib.parse, urllib.request
    cls = urllib.parse.quote(classname, safe=".")
    url = (f"https://docs.intersystems.com/{versionSeg}/csp/documatic/"
           f"%25CSP.Documatic.cls?LIBRARY={library}&CLASSNAME={cls}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hc-compat/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as exc:
        return json.dumps({"exists": False, "error": str(exc), "members": {}})
    ids = re.findall(r'id="(PARAMETER|PROPERTY|METHOD|QUERY|INDEX)_([%A-Za-z0-9]+)"', html)
    members = {}
    for kind, name in ids:
        members.setdefault(kind, set()).add(urllib.parse.unquote(name))
    exists = bool(ids) or (f"CLASSNAME={classname}" in html.replace("%25", "%"))
    return json.dumps({"exists": exists, "members": {k: sorted(v) for k, v in members.items()}})
}

/// Compare one class between From (higher) and To (lower). Returns JSON:
/// {ok, class, from, to, newClass, added:{KIND:[names]}, totalAdded}.
ClassMethod DiffClass(fromV As %String, toV As %String, library As %String, classname As %String) As %String [ Language = python ]
{
    import json
    import iris
    scr = "AgenticInterop.Compat.Scraper"
    fromSeg = iris.cls(scr).ResolveSegment(fromV)
    toSeg = iris.cls(scr).ResolveSegment(toV)
    hi = json.loads(iris.cls(scr).Fetch(fromSeg, library, classname))
    lo = json.loads(iris.cls(scr).Fetch(toSeg, library, classname))
    out = {"ok": True, "class": classname, "from": fromSeg, "to": toSeg,
           "newClass": False, "added": {}, "totalAdded": 0}
    if not hi.get("exists"):
        out["ok"] = False
        out["error"] = f"{classname} does not exist in {fromSeg}"
        return json.dumps(out)
    if not lo.get("exists"):
        out["newClass"] = True
        out["added"] = hi.get("members", {})
        out["totalAdded"] = sum(len(v) for v in out["added"].values())
        return json.dumps(out)
    added = {}
    for kind, names in hi.get("members", {}).items():
        gained = sorted(set(names) - set(lo.get("members", {}).get(kind, [])))
        if gained:
            added[kind] = gained
    out["added"] = added
    out["totalAdded"] = sum(len(v) for v in added.values())
    return json.dumps(out)
}

/// Check a single member (property/method/parameter) of a class. Returns JSON:
/// {ok, class, member, from, to, existsInFrom, existsInTo, breaks, kind?}.
ClassMethod CheckMember(fromV As %String, toV As %String, library As %String, classname As %String, member As %String) As %String [ Language = python ]
{
    import json
    import iris
    scr = "AgenticInterop.Compat.Scraper"
    fromSeg = iris.cls(scr).ResolveSegment(fromV)
    toSeg = iris.cls(scr).ResolveSegment(toV)
    hi = json.loads(iris.cls(scr).Fetch(fromSeg, library, classname))
    lo = json.loads(iris.cls(scr).Fetch(toSeg, library, classname))

    def find(inv, name):
        for kind, names in inv.get("members", {}).items():
            if name in names:
                return kind
        return None

    kindHi = find(hi, member)
    kindLo = find(lo, member)
    out = {"ok": True, "class": classname, "member": member,
           "from": fromSeg, "to": toSeg,
           "classExistsInTo": bool(lo.get("exists")),
           "existsInFrom": kindHi is not None,
           "existsInTo": kindLo is not None,
           "kind": kindHi or kindLo,
           "breaks": (kindHi is not None) and (kindLo is None)}
    return json.dumps(out)
}

/// Scan an ObjectScript / DTL / BPL code string for fully-qualified member
/// references (##class(Class).Method( and ##class(Class).#Parameter) that exist
/// in From but not in To. Returns JSON {ok, from, to, findings:[...], scanned}.
ClassMethod ScanCode(fromV As %String, toV As %String, code As %String, library As %String = "ENSLIB") As %String [ Language = python ]
{
    import json, re
    import iris
    scr = "AgenticInterop.Compat.Scraper"
    param_re = re.compile(r'##class\(\s*([%A-Za-z][%A-Za-z0-9.]*)\s*\)\.#([A-Za-z][A-Za-z0-9]*)')
    method_re = re.compile(r'##class\(\s*([%A-Za-z][%A-Za-z0-9.]*)\s*\)\.([A-Za-z][A-Za-z0-9]*)\s*\(')
    refs = set()
    for cls, name in param_re.findall(code or ""):
        refs.add((cls, name))
    for cls, name in method_re.findall(code or ""):
        refs.add((cls, name))
    findings = []
    for cls, name in sorted(refs):
        res = json.loads(iris.cls(scr).CheckMember(fromV, toV, library, cls, name))
        if res.get("breaks"):
            findings.append({"class": cls, "member": name,
                             "kind": res.get("kind"),
                             "reason": f"{res.get('kind','member')} '{name}' on {cls} "
                                       f"is new in {res.get('from')}; absent in {res.get('to')}"})
    return json.dumps({"ok": True, "from": iris.cls(scr).ResolveSegment(fromV),
                       "to": iris.cls(scr).ResolveSegment(toV),
                       "scanned": len(refs), "findings": findings})
}

}
