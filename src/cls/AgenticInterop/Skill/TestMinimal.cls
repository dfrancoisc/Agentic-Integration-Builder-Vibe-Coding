/// Minimal skill - used to verify the Skill instantiation path works at all.
Class AgenticInterop.Skill.TestMinimal Extends AgenticInterop.Skill.Base
{

Parameter TOOLS = "AgenticInterop.ToolSet.Production";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: minimal-test
description: A trivial skill used only to smoke-test the scaffold.
}

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
You are a trivial test specialist. Reply with the word OK.
}

}
