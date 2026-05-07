/// %AI.ToolSet wrapper for the Transform tool family. Composes the
/// AgenticInterop.Tool.Transform %AI.Tool subclass via <Include> so
/// the framework's auto-discovery picks up every public ClassMethod
/// as a tool. Create/Update/Compile/Validate operations route through
/// the confirmation gate.
Class AgenticInterop.ToolSet.Transform Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.Transform ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Transform">
    <Description>DTL (Data Transformation Language), BPL (Business Process Language), lookup tables, and routing rules. Read-only inventory + DryRunDTL; Create/Update/Compile/Validate operations gated by the confirmation policy.</Description>
    <Include Class="AgenticInterop.Tool.Transform"/>
</ToolSet>
}

}
