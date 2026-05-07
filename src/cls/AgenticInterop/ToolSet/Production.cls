/// %AI.ToolSet wrapper for the Production tool family. Composes the
/// AgenticInterop.Tool.Production %AI.Tool subclass via <Include> so
/// the framework's auto-discovery picks up every public ClassMethod
/// as a tool.
///
/// Mutating tool dispatches (Start/Stop/Create/Delete/Add/Remove/
/// Update*) flow through AgenticInterop.Policy.ConfirmationGate so
/// the user explicitly approves each action via the inline gate card.
Class AgenticInterop.ToolSet.Production Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.Production ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Production">
    <Description>Production CRUD, lifecycle, and business host management. Read-only inventory + describe; mutating start/stop/create/delete/host-edit operations gated by the confirmation policy.</Description>
    <Include Class="AgenticInterop.Tool.Production"/>
</ToolSet>
}

}
