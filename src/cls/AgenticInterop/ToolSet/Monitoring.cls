/// %AI.ToolSet wrapper for the Monitoring tool family. Composes
/// AgenticInterop.Tool.Monitoring so the framework auto-discovers
/// QueryEventLog, TopErrors, QueryMessageStatus, MessageSummary,
/// and QueueStatus as callable tools. All tools are read-only
/// SQL queries against Ens.MessageHeader and Ens.Util.Log.
Class AgenticInterop.ToolSet.Monitoring Extends %AI.ToolSet [ DependsOn = AgenticInterop.Tool.Monitoring ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Monitoring">
    <Description>Production monitoring and diagnostics tools: event log queries, message header searches, error summaries, queue depths.</Description>
    <Include Class="AgenticInterop.Tool.Monitoring"/>
</ToolSet>
}

}
