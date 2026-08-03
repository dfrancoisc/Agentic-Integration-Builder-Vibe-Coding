/// %AI.ToolSet wrapper for the Compat tool family. Composes
/// AgenticInterop.Tool.Compat via <Include> so the framework auto-discovers every
/// public ClassMethod as a tool. All tools are read-only (they read public
/// documentation), so none are gated by the confirmation policy.
Class AgenticInterop.ToolSet.Compat Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.Compat ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Compat">
    <Description>Health Connect cross-version downgrade / forward-incompatibility checks. Given a higher From version and a lower To version, report class members present in From but absent in To -- the API changes that compile in a newer BASE/UAT environment and break when promoted to an older LIVE server. Read-only; reads public Documatic.</Description>
    <Include Class="AgenticInterop.Tool.Compat"/>
</ToolSet>
}

}
