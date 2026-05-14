/// %AI.ToolSet wrapper for the Production tool family. Composes the
/// AgenticInterop.Tool.Production %AI.Tool subclass via <Include> so
/// the framework's auto-discovery picks up every public ClassMethod
/// as a tool.
///
/// Covers production CRUD, business host management, routing rules,
/// and post-build validation. Mutating tools (Start/Stop/Create/
/// Delete/Add/Remove/Update*, CreateRoutingRule) flow through the
/// confirmation gate.
Class AgenticInterop.ToolSet.Production Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.Production ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Production">
    <Description>Production CRUD, lifecycle, business host management, and routing rules. Read-only inventory + describe + validation; mutating start/stop/create/delete/host-edit/routing-rule operations gated by the confirmation policy.</Description>
    <Include Class="AgenticInterop.Tool.Production"/>
</ToolSet>
}

}
