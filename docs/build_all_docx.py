"""Build the three project .docx documents with embedded screenshots.

Outputs:
  docs/01_Requirements_User_Stories.docx
  docs/02_Technical_Build_Specification.docx
  docs/03_Lessons_Learned.docx

Requires: pip install python-docx Pillow
"""
import os
from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn

DOCS = os.path.dirname(__file__)
IMG = os.path.join(DOCS, "img")


def img(name):
    """Return full path to a screenshot."""
    return os.path.join(IMG, name)


def style_doc(doc):
    """Apply consistent styling to the document."""
    style = doc.styles["Normal"]
    font = style.font
    font.name = "Calibri"
    font.size = Pt(11)
    font.color.rgb = RGBColor(0x33, 0x33, 0x33)

    for level in range(1, 5):
        hstyle = doc.styles[f"Heading {level}"]
        hstyle.font.name = "Calibri"
        hstyle.font.color.rgb = RGBColor(0x1A, 0x1A, 0x2E)

    doc.styles["Heading 1"].font.size = Pt(22)
    doc.styles["Heading 2"].font.size = Pt(16)
    doc.styles["Heading 3"].font.size = Pt(13)


def add_title_page(doc, title, subtitle, version="Version 1.0 | May 2026 | InterSystems AI Hub"):
    """Add a title page."""
    for _ in range(6):
        doc.add_paragraph("")
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run(title)
    run.font.size = Pt(28)
    run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x2E)
    run.bold = True

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run(subtitle)
    run.font.size = Pt(14)
    run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)

    doc.add_paragraph("")
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run(version)
    run.font.size = Pt(10)
    run.font.color.rgb = RGBColor(0x99, 0x99, 0x99)
    run.italic = True

    doc.add_page_break()


def add_figure(doc, image_path, caption, width=Inches(6.2)):
    """Add an image with caption below it."""
    if not os.path.exists(image_path):
        p = doc.add_paragraph(f"[Screenshot: {caption}]")
        p.italic = True
        return
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    run.add_picture(image_path, width=width)

    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = cap.add_run(f"Figure: {caption}")
    run.font.size = Pt(9)
    run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
    run.italic = True
    doc.add_paragraph("")


def add_table(doc, headers, rows):
    """Add a styled table."""
    table = doc.add_table(rows=1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.style = "Table Grid"

    # Header row
    hdr = table.rows[0]
    for i, h in enumerate(headers):
        cell = hdr.cells[i]
        cell.text = h
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                run.bold = True
                run.font.size = Pt(10)
        shading = cell._element.get_or_add_tcPr()
        bg = shading.makeelement(qn("w:shd"), {
            qn("w:val"): "clear",
            qn("w:color"): "auto",
            qn("w:fill"): "1A1A2E"
        })
        shading.append(bg)
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)

    for row_data in rows:
        row = table.add_row()
        for i, val in enumerate(row_data):
            row.cells[i].text = str(val)
            for paragraph in row.cells[i].paragraphs:
                for run in paragraph.runs:
                    run.font.size = Pt(10)

    doc.add_paragraph("")


# =============================================================================
# Document 1: Requirements & User Stories
# =============================================================================
def build_doc1():
    doc = Document()
    style_doc(doc)
    add_title_page(doc,
        "Agentic Health Interoperability",
        "Requirements and User Stories")

    # Table of contents placeholder
    doc.add_heading("Table of Contents", level=1)
    doc.add_paragraph("1. Introduction")
    doc.add_paragraph("2. Core Use Cases")
    doc.add_paragraph("3. Developer Experience")
    doc.add_paragraph("4. Builder Experience - Admin UI")
    doc.add_paragraph("5. Builder Experience - Chatbot")
    doc.add_paragraph("6. End-to-End Scenario")
    doc.add_paragraph("7. Non-Functional Requirements")
    doc.add_page_break()

    # 1. Introduction
    doc.add_heading("1. Introduction", level=1)
    doc.add_paragraph(
        "This document defines the end-to-end requirements and user stories for the Agentic Health "
        "Interoperability project. The system enables two distinct personas to build, configure, and "
        "operate AI-powered agents for healthcare interoperability tasks inside InterSystems IRIS for Health.")
    doc.add_paragraph(
        "Product vision: A configuration-driven AI Copilot that helps integration engineers build "
        "Productions, create Transformations, test HL7/FHIR messages, and explore the IRIS class "
        "catalog -- entirely through natural-language conversation or a structured admin UI.")

    doc.add_heading("1.1 Personas", level=2)
    add_table(doc,
        ["Persona", "Role", "Primary Interface", "Security Scope"],
        [
            ["Developer", "Builds agent infrastructure, writes custom tools, deploys packages",
             "VS Code + ObjectScript extension + terminal",
             "Full %DB access, %Dictionary write, source control, IPM packaging"],
            ["Builder", "Configures agents, skills, connections, reviews mappings, operates the chatbot",
             "IRIS Management Portal (admin UI + chatbot)",
             "Restricted to /api/agentic/ endpoints, no direct SQL or class compilation"],
        ])

    # 2. Core Use Cases
    doc.add_page_break()
    doc.add_heading("2. Core Use Cases", level=1)
    doc.add_paragraph(
        "The Agentic Health Interoperability Copilot addresses three primary use cases that cover "
        "the full lifecycle of healthcare integration work inside IRIS for Health. Each use case "
        "represents a category of tasks that integration engineers perform daily and that the agent "
        "can accelerate through natural-language conversation.")
    add_figure(doc, img("15_chatbot.png"),
        "Chat interface showing starter prompts organized by use case category: Build, Transform, Operate, and Review")

    # UC-1: Build Productions
    doc.add_heading("2.1 Use Case 1: Build Productions", level=2)
    doc.add_paragraph(
        "The most common task for an integration engineer is building new Productions -- the "
        "runtime message-processing pipelines in IRIS for Health. A Production consists of Business "
        "Services (inbound), Business Processes (routing/orchestration), and Business Operations "
        "(outbound), wired together with settings, routing rules, and message transformations.")
    doc.add_paragraph(
        "The agent assists the Builder through the entire production lifecycle:")
    doc.add_paragraph(
        "Discovery: The Builder describes their integration goal in plain English (e.g., 'build a "
        "production that receives ADT messages over MLLP, transforms them to FHIR R4, and sends "
        "them to a REST endpoint'). The agent searches the Ens.* vector catalog to find the right "
        "Business Host classes (EnsLib.HL7.Service.TCPService, EnsLib.FHIR.Operation.REST, etc.).",
        style="List Bullet")
    doc.add_paragraph(
        "Proposal: The agent presents a production layout -- which hosts to add, what settings to "
        "configure, which adapters to use -- and asks the Builder to approve before making changes.",
        style="List Bullet")
    doc.add_paragraph(
        "Build: Upon approval, the agent creates the production class, adds each Business Host "
        "with appropriate settings, creates routing rules, and compiles everything. Each mutating "
        "step goes through the confirmation gate.",
        style="List Bullet")
    doc.add_paragraph(
        "Validation: The agent runs PostBuildValidation to check for configuration errors, sends "
        "a test HL7 message through the pipeline, and verifies that messages flow end-to-end "
        "without errors.",
        style="List Bullet")
    doc.add_paragraph("")
    doc.add_paragraph("Tools involved:", style="List Bullet")
    doc.add_paragraph("search_ens -- find the right Business Host classes from the vector catalog", style="List Bullet 2")
    doc.add_paragraph("describe_class -- inspect class details, parameters, and settings", style="List Bullet 2")
    doc.add_paragraph("create_production -- create the production class definition", style="List Bullet 2")
    doc.add_paragraph("add_business_host -- add Business Services, Processes, and Operations", style="List Bullet 2")
    doc.add_paragraph("update_business_host_settings -- configure adapter settings, file paths, connection parameters", style="List Bullet 2")
    doc.add_paragraph("create_routing_rule -- create routing rules with conditions and actions", style="List Bullet 2")
    doc.add_paragraph("start_production / stop_production -- lifecycle management", style="List Bullet 2")
    doc.add_paragraph("PostBuildValidation -- automated post-build health check", style="List Bullet 2")
    doc.add_paragraph("BuildAndSendHL7TestMessage -- generate and send test messages through the pipeline", style="List Bullet 2")
    doc.add_paragraph("")
    doc.add_paragraph("Example prompts:")
    doc.add_paragraph(
        '"Build a complete production that receives HL7 v2.5 ADT^A01 admission messages over an '
        'inbound folder, transforms each ADT into an ORU^R01 observation report, routes the '
        'transformed messages to an outbound folder, and sends failures to a dead-letter folder."',
        style="List Bullet")
    doc.add_paragraph(
        '"I need a production that receives X12 270 eligibility inquiries over SFTP, calls our '
        'internal eligibility REST API, constructs the X12 271 response, and writes it back to '
        'the payer\'s SFTP outbound folder."',
        style="List Bullet")

    # UC-2: Review and Improve Productions
    doc.add_heading("2.2 Use Case 2: Review and Improve Existing Productions", level=2)
    doc.add_paragraph(
        "Integration engineers inherit productions built by others, or maintain productions that "
        "were built months or years ago. They need to understand what a production does, identify "
        "problems, and find opportunities to modernize it using newer IRIS features and best practices.")
    doc.add_paragraph(
        "The agent helps the Builder review and optimize existing integrations:")
    doc.add_paragraph(
        "Error Triage: The agent queries the Event Log and Message Header tables to find recent "
        "errors, groups them by Business Host, identifies the most frequent error messages, and "
        "recommends remediation steps. It can spot suspended or errored messages that need manual "
        "intervention.",
        style="List Bullet")
    doc.add_paragraph(
        "Production Health Assessment: The agent inspects the production configuration, checks "
        "queue depths, reviews throughput statistics, and identifies bottlenecks. It can recommend "
        "settings changes (pool size, throttle, retry intervals) based on what it observes.",
        style="List Bullet")
    doc.add_paragraph(
        "DTL Review: The agent reviews Data Transformation Language (DTL) definitions and identifies "
        "hardcoded values that should be lookup tables, missing null checks on source fields, "
        "incorrect handling of repeating fields, and segments being dropped. It suggests refactored "
        "versions with explanations.",
        style="List Bullet")
    doc.add_paragraph(
        "Modernization Advice: The agent knows about newer IRIS features (via Skills) and can "
        "recommend upgrades -- for example, replacing a custom BPL with a built-in DTL, using "
        "record maps instead of custom parsers, or adopting the HL7-to-SDA-to-FHIR pipeline "
        "instead of point-to-point transformations.",
        style="List Bullet")
    doc.add_paragraph("")
    doc.add_paragraph("Tools involved:", style="List Bullet")
    doc.add_paragraph("get_production -- inspect the full production configuration and all hosts", style="List Bullet 2")
    doc.add_paragraph("query_event_log -- search the Event Log for errors, warnings, and trace messages", style="List Bullet 2")
    doc.add_paragraph("top_errors -- group errors by frequency and identify systemic issues", style="List Bullet 2")
    doc.add_paragraph("query_message_status -- find messages in Error or Suspended state", style="List Bullet 2")
    doc.add_paragraph("message_summary -- throughput statistics across all hosts", style="List Bullet 2")
    doc.add_paragraph("queue_status -- check for queue buildup indicating backpressure", style="List Bullet 2")
    doc.add_paragraph("describe_class -- look up what a Business Host class does and its available settings", style="List Bullet 2")
    doc.add_paragraph("list_dtls / get_dtl -- review existing transformation logic", style="List Bullet 2")
    doc.add_paragraph("Skills: Productions, DTL, BPL, Adapters, ESBPattern -- domain knowledge for recommendations", style="List Bullet 2")
    doc.add_paragraph("")
    doc.add_paragraph("Example prompts:")
    doc.add_paragraph(
        '"Review the last 2 hours of errors across all productions. Group them by Business Host, '
        'show the top 5 most frequent error messages with counts, identify messages stuck in '
        'Suspended or Error state, and recommend remediation steps."',
        style="List Bullet")
    doc.add_paragraph(
        '"Review our current ADT_A08_to_SDA3 DTL for: hardcoded values that should be lookup '
        'tables, missing null checks on source fields, incorrect handling of repeating PID-3 '
        'identifiers, and segments we are dropping that we should not."',
        style="List Bullet")

    # UC-3: Create/Provide Insights on Transformations
    doc.add_heading("2.3 Use Case 3: Create and Optimize Transformations", level=2)
    doc.add_paragraph(
        "Data Transformations are the heart of healthcare interoperability. Integration engineers "
        "spend most of their time writing, debugging, and optimizing DTL (Data Transformation "
        "Language) and BPL (Business Process Language) definitions that convert messages between "
        "formats -- HL7 v2 to SDA3, SDA3 to FHIR R4, CDA to SDA3, and more.")
    doc.add_paragraph(
        "The agent assists the Builder with transformation work at every stage:")
    doc.add_paragraph(
        "Pipeline Discovery: The agent traces the full transformation pipeline for any format "
        "pair (e.g., HL7 v2 to FHIR R4) showing which IRIS classes handle each step, what "
        "intermediate formats are used, and where the data flows. The Data Atlas (Transforms tab) "
        "provides this information visually at the field level.",
        style="List Bullet")
    doc.add_paragraph(
        "DTL Creation: The agent creates new DTL definitions by first searching the HS.* catalog "
        "for existing transformations that handle the same or similar format pair, then scaffolding "
        "a new DTL with the correct source/target classes and document types. It can populate field "
        "mappings based on the Data Atlas mappings.",
        style="List Bullet")
    doc.add_paragraph(
        "Schema Introspection: The agent can introspect HL7 v2 message schemas (segments, fields, "
        "components) and FHIR R4 resource structures so the Builder understands what data is "
        "available at each point in the pipeline. It knows about composite types (XAD for addresses, "
        "XPN for names, CX for identifiers) and can show sub-field level detail.",
        style="List Bullet")
    doc.add_paragraph(
        "Dry-Run Testing: The agent can execute a DTL against a sample message (DryRunDTL) to "
        "verify the transformation produces the expected output without deploying to a production. "
        "It can compare before/after messages field by field.",
        style="List Bullet")
    doc.add_paragraph(
        "Cross-Format Mapping Insights: Through the Data Atlas, the agent (and the Builder via "
        "the admin UI) can see exactly which HL7 fields map through SDA3 to FHIR, which fields "
        "are inbound-only (arrive but don't continue), and which are outbound-only (produced in "
        "the target but not sourced from the input). This enables gap analysis before writing "
        "any code.",
        style="List Bullet")
    doc.add_paragraph("")
    doc.add_paragraph("Tools involved:", style="List Bullet")
    doc.add_paragraph("list_dtls -- discover existing transformations in the namespace", style="List Bullet 2")
    doc.add_paragraph("create_dtl -- scaffold a new DTL with source/target classes", style="List Bullet 2")
    doc.add_paragraph("update_dtl / compile_dtl -- modify and compile transformation logic", style="List Bullet 2")
    doc.add_paragraph("dry_run_dtl -- test a transformation against sample data", style="List Bullet 2")
    doc.add_paragraph("list_sda_fhir_dtls -- find built-in SDA3-to-FHIR transformations", style="List Bullet 2")
    doc.add_paragraph("describe_transformation_pipeline -- trace the full format conversion path", style="List Bullet 2")
    doc.add_paragraph("get_hl7_schema_map / get_hl7_segment_fields -- introspect HL7 v2 message structures", style="List Bullet 2")
    doc.add_paragraph("search_hs -- semantic search for transformation classes in the HS.* catalog", style="List Bullet 2")
    doc.add_paragraph("compare_messages -- field-level diff between two messages", style="List Bullet 2")
    doc.add_paragraph("Skills: DTL, HL7v2, FHIRR4, SDA, CDA, X12 -- deep domain knowledge for each format", style="List Bullet 2")
    doc.add_paragraph("")
    doc.add_paragraph("Example prompts:")
    doc.add_paragraph(
        '"Create an interface that accepts any HL7 v2 message (ADT, ORU, ORM, MDM, SIU) on a '
        'single inbound MLLP service, transforms it to the appropriate FHIR R4 resources using '
        'the built-in HL7-to-SDA-to-FHIR pipeline, and POSTs the resulting Bundle to our FHIR '
        'Server."',
        style="List Bullet")
    doc.add_paragraph(
        '"Build a production that ingests C-CDA documents via a REST endpoint, validates them '
        'against the C-CDA R2.1 schema, transforms them to FHIR R4 Composition + DocumentReference '
        '+ Patient/Encounter/Condition resources using SDA3 as the intermediate model, and persists '
        'the Bundle to our FHIR repository."',
        style="List Bullet")

    add_figure(doc, img("13_transforms_hl7_fhir.png"),
        "Data Atlas: the Transforms tab showing field-level HL7 v2 to FHIR R4 mappings through SDA3, with coverage filters and IRIS class names -- a key reference tool for Use Cases 2 and 3")

    # 3. Developer Experience
    doc.add_page_break()
    doc.add_heading("3. Developer Experience", level=1)
    doc.add_paragraph(
        "Developers work exclusively through VS Code with the InterSystems ObjectScript extension. "
        "They write classes (Agent, MCP, ToolSet, Tool, Skill), compile them, and deploy via IPM. "
        "The admin UI is not their primary interface -- their deliverable is code that the Builder configures.")

    doc.add_heading("3.1 Security Requirements", level=2)
    add_table(doc,
        ["Requirement", "Implementation"],
        [
            ["Authentication", "IRIS native users with role-based access (%Developer role)"],
            ["Source control", "Git integration via VS Code; all classes under src/cls/"],
            ["Secret management", "IRIS Secured Wallet (collection: AgenticInteropConnections). No plaintext secrets in code, tables, or globals"],
            ["API key isolation", "Runtime LLM credentials are separate from development LLM. Agent's Bedrock/Anthropic key stored in Wallet, never in source"],
            ["Namespace isolation", "Code is namespace-agnostic ($namespace resolved at request time). No hardcoded namespace references"],
            ["IPM packaging", "zpm load on a clean instance produces a working system. Shipped classes survive upgrades; user customizations survive in override tables"],
        ])

    doc.add_heading("3.2 User Stories", level=2)

    stories_dev = [
        ("US-D01: Create a New Tool",
         "As a Developer, I want to write an ObjectScript class that extends %AI.Tool with defined "
         "parameters (NAME, DESCRIPTION, INPUT, OUTPUT), so that the tool appears in the agent's "
         "catalog and can be invoked during chat conversations.",
         ["Tool class compiles without errors",
          "Tool appears in the admin UI Tools tab after compilation",
          "Tool description follows the contract format: imperative verb, scope, side effects",
          "Tool input/output schemas are valid JSON Schema",
          "Tool includes at least one happy-path unit test"]),
        ("US-D02: Create a New Skill",
         "As a Developer, I want to write a Skill class with INSTRUCTIONS content (markdown text "
         "up to 32K characters), so that the agent can delegate domain-specific questions to a "
         "specialist sub-agent.",
         ["Skill class extends AgenticInterop.Skill.Base (not %AI.Agent.Skill directly)",
          "INSTRUCTIONS parameter contains domain knowledge in plain prose",
          "Skill registers automatically via SkillLoader at agent build time",
          "Builder can override INSTRUCTIONS content in the admin UI without code changes"]),
        ("US-D03: Create a New MCP Server",
         "As a Developer, I want to write an MCP Server class that groups related ToolSets under a "
         "named service, so that Builders can enable/disable entire capability domains from the admin UI.",
         ["MCP class extends AgenticInterop.MCP.Base (which extends %AI.MCP.Service)",
          "Parameters: NAME, DESCRIPTION, TOOLSETS (comma-separated list)",
          "MCP appears in the admin UI MCPs tab after compilation"]),
        ("US-D04: Deploy via IPM",
         "As a Developer, I want to package the entire project as an IPM module (agentic-interop), "
         "so that a Builder can install it on any IRIS for Health 2026.2+ instance.",
         ["module.xml defines all sources, CSP applications, seed data, and install hooks",
          "zpm load on a clean HSCUSTOM namespace produces a working system",
          "Install hooks: CSP timeout patch applied, Interop Editor patched with AI buttons",
          "Uninstall hooks: Interop Editor reverted to original state"]),
        ("US-D05: Write Custom Tool Implementations",
         "As a Developer, I want to implement tools using SQL statements, ObjectScript class methods, "
         "or Embedded Python, so that I can leverage the best language for each task.",
         ["SQL tools execute parameterized queries (no string concatenation)",
          "ObjectScript tools use $namespace for namespace-agnostic operation",
          "Python tools use ##class(%SYS.Python).Import() for LLM/MCP glue",
          "All tools handle errors gracefully and return structured error objects"]),
        ("US-D06: Build and Maintain Vector Catalogs",
         "As a Developer, I want to rebuild the Ens.* and HS.* vector catalogs from %Dictionary, "
         "so that the agent can semantically search for Business Hosts and transformation classes.",
         ["AgenticInterop.Catalog.Builder walks %Dictionary.ClassDefinition for relevant superclasses",
          "Embeddings use FastEmbed (384-dim HNSW vectors) via %AI.RAG.KnowledgeBase",
          "Curated prose descriptions (not auto-generated accessor signatures) feed the embeddings",
          "Catalog rebuild can be triggered from admin UI or scheduled"]),
    ]

    for title, story, criteria in stories_dev:
        doc.add_heading(title, level=3)
        doc.add_paragraph(story)
        doc.add_paragraph("Acceptance criteria:", style="List Bullet")
        for c in criteria:
            doc.add_paragraph(c, style="List Bullet 2")

    # 3. Builder Experience -- Admin UI
    doc.add_page_break()
    doc.add_heading("4. Builder Experience - Admin UI", level=1)
    doc.add_paragraph(
        "Builders work through the IRIS Management Portal. They configure agents, manage LLM connections, "
        "review transformation mappings, tune skills, and operate the chatbot. No code editing required.")
    doc.add_paragraph(
        "The admin UI is a vanilla JavaScript SPA served at /agentic/admin/. It communicates with "
        "/api/agentic/ REST endpoints using JWT or Basic authentication.")

    doc.add_heading("4.1 Security Requirements", level=2)
    add_table(doc,
        ["Requirement", "Implementation"],
        [
            ["Authentication", "IRIS native auth (Basic or JWT). No UI element visible before login"],
            ["Authorization", "Role-based: %ISCMgtPortal group membership required"],
            ["Audit", "Every REST request logged with username, namespace, session, job, path, method, status, duration"],
            ["Secret handling", "API keys entered in masked input, stored in IRIS Secured Wallet. Never displayed back, never logged"],
            ["Session isolation", "UseSession=0 on all REST classes. No CSRF cookies. Bearer token per request"],
        ])

    # US-B01 Connections
    doc.add_heading("4.2 US-B01: Configure an LLM Connection", level=2)
    doc.add_paragraph(
        "As a Builder, I want to create an LLM connection (provider, model, region, API key) and "
        "test it, so that the agent can communicate with the LLM provider.")
    doc.add_paragraph("The Connections tab shows all configured LLM connections with status indicators:")
    add_figure(doc, img("09_connections_list.png"),
        "Connections tab showing the configured AWS Bedrock connection with DEFAULT and CORE badges, green status dot")
    doc.add_paragraph("Clicking a connection opens the detail editor with all configuration fields:")
    add_figure(doc, img("10_connection_detail.png"),
        "Connection detail editor showing provider, model, region, API key (masked), and Test Connection button with green TESTED OK status")

    # US-B02 Agent
    doc.add_heading("4.3 US-B02: Configure the Agent", level=2)
    doc.add_paragraph(
        "As a Builder, I want to customize the agent's system prompt, temperature, max iterations, "
        "bound MCPs, and skills, so that the agent behaves according to our integration requirements.")
    add_figure(doc, img("02_agent_detail.png"),
        "Agent editor showing the HealthInterop agent configuration: class name, temperature slider, max iterations, tool binding mode, system prompt with persona and formatting rules")

    # US-B03 MCPs
    doc.add_heading("4.4 US-B03: Configure MCP Servers", level=2)
    doc.add_paragraph(
        "As a Builder, I want to enable/disable MCP servers and customize their descriptions, "
        "so that I can control which capability domains the agent has access to.")
    add_figure(doc, img("03_mcps_list.png"),
        "MCPs tab showing the four MCP servers: catalog, production, testing, and transform, each with their class name, description, and toolset count")

    # US-B04 ToolSets & Tools
    doc.add_heading("4.5 US-B04: Configure ToolSets and Tools", level=2)
    doc.add_paragraph(
        "As a Builder, I want to view and customize ToolSets and their individual tools, "
        "so that I can tune tool descriptions, toggle tools on/off, and dry-run tools.")
    add_figure(doc, img("04_toolsets_list.png"),
        "ToolSets tab showing the five ToolSets: Catalog (8 tools), Monitoring (6 tools), Production (13 tools), Testing (8 tools), Transform (13 tools)")
    add_figure(doc, img("05_tools_list.png"),
        "Tools tab listing all 42 tools across the five ToolSet classes, sorted alphabetically")
    doc.add_paragraph("Clicking a tool opens the detail editor with the LLM-facing description and input schema:")
    add_figure(doc, img("06_tool_detail.png"),
        "Tool detail editor for DescribeClass showing the contract-style description, method signature, JSON input schema, implementation kind, timeout, and confirmation requirement")

    # US-B05 Skills
    doc.add_heading("4.6 US-B05: Configure Skills", level=2)
    doc.add_paragraph(
        "As a Builder, I want to view and edit the INSTRUCTIONS content for each skill, "
        "so that I can refine the agent's domain knowledge without Developer involvement.")
    add_figure(doc, img("07_skills_list.png"),
        "Skills tab showing the 12 shipped skills: Adapters, BPL, CDA, DTL, ESBPattern, FHIRR4, HL7v2, Productions, and more")
    add_figure(doc, img("08_skill_detail.png"),
        "Skill editor for Adapters showing the class name, description field, bound ToolSets, and expandable class source viewer")

    # US-B06 Transforms (Data Atlas)
    doc.add_heading("4.7 US-B06: Review Transformation Mappings (Data Atlas)", level=2)
    doc.add_paragraph(
        "As a Builder, I want to explore field-level mappings between HL7 v2, SDA3, and FHIR R4 "
        "formats, so that I can understand how data flows through the transformation pipeline and "
        "identify which IRIS classes handle each mapping.")
    doc.add_paragraph(
        "The Transforms tab provides a Data Atlas: a visual field-level mapping explorer. The user "
        "selects a source format (e.g., HL7 v2) and target format (e.g., FHIR R4), then browses "
        "SDA3 data types in the sidebar. For each type, the three-column table shows:")
    doc.add_paragraph("Source field (e.g., PID.11.3 City) with the IRIS class that performs the inbound mapping", style="List Bullet")
    doc.add_paragraph("SDA3 canonical field (e.g., City)", style="List Bullet")
    doc.add_paragraph("Target field (e.g., city) with the IRIS class that performs the outbound mapping", style="List Bullet")
    add_figure(doc, img("13_transforms_hl7_fhir.png"),
        "Data Atlas: HL7 v2 to FHIR R4 via SDA3.Address, showing sub-field level mappings (PID.11.3 City, PID.11.6 Country), coverage filter chips (End-to-end, Inbound only, Outbound only), and IRIS class names inline (HS.Gateway.HL7.HL7ToSDA3, HS.FHIR.DTL.SDA3.vR4.Address.Address)")

    # US-B07 Catalogs
    doc.add_heading("4.8 US-B07: Browse Vector Catalogs", level=2)
    doc.add_paragraph(
        "As a Builder, I want to search the Ens.* and HS.* vector catalogs to find Business Hosts, "
        "adapters, and transformation classes.")
    add_figure(doc, img("11_catalogs.png"),
        "Catalogs tab showing search_ens (164 rows indexed) and search_hs (58 rows indexed) catalogs with kind breakdowns, rebuild buttons, test search panel, and browse panel")

    # US-B08 Audit
    doc.add_heading("4.9 US-B08: View Audit Log", level=2)
    doc.add_paragraph(
        "As a Builder, I want to view the audit trail of all API requests, so that I can track "
        "who did what, when, and how long it took.")
    add_figure(doc, img("14_audit.png"),
        "Audit tab showing the request log with status codes, HTTP methods, paths, kind classification, timestamps, usernames, namespace, duration, and byte counts")

    # 4. Builder Experience -- Chatbot
    doc.add_page_break()
    doc.add_heading("5. Builder Experience - Chatbot", level=1)

    doc.add_heading("5.1 US-B09: Chat with the Agent", level=2)
    doc.add_paragraph(
        "As a Builder, I want to type a natural-language request (e.g., 'build me a production that "
        "ingests ADT messages and routes them to two downstream systems'), so that the agent searches "
        "catalogs, proposes hosts, asks for confirmation, creates the production, sends a test HL7 "
        "message, and validates the result.")
    add_figure(doc, img("15_chatbot.png"),
        "Chat interface showing the welcome screen with starter prompts (Build, Transform, Operate, Review categories), conversation history sidebar, namespace and connection indicators in the top bar, and the message input area")
    doc.add_paragraph("Chat capabilities:", style="List Bullet")
    doc.add_paragraph("SSE streaming: tokens appear in real time, no loading spinner", style="List Bullet 2")
    doc.add_paragraph("Tool calls render as inline cards with name, arguments, status, and collapsible result", style="List Bullet 2")
    doc.add_paragraph("Mutating tool calls pause with Approve/Reject prompt (ConfirmationGate policy)", style="List Bullet 2")
    doc.add_paragraph("Monitor enforces 60s deadline + 50K token budget per turn", style="List Bullet 2")
    doc.add_paragraph("Top bar shows agent name, connection status, and New Chat button", style="List Bullet 2")

    # 5. End-to-End Scenario
    doc.add_page_break()
    doc.add_heading("6. End-to-End Scenario", level=1)
    doc.add_paragraph("This scenario demonstrates the full system working end-to-end:")
    steps = [
        "Developer writes a new Tool class that creates HL7 routing rules, compiles it, and deploys via zpm load",
        "Builder opens the admin UI, sees the new tool in the Tools tab, reviews its description",
        "Builder opens the Transforms tab, selects HL7 v2 -> FHIR R4, reviews Address field mappings to understand the data flow",
        "Builder opens the chatbot and asks: 'Build me a production that receives ADT^A04 messages via MLLP, transforms patient demographics to FHIR R4, and sends them to a REST endpoint'",
        "Agent searches the Ens.* catalog for appropriate Business Hosts (EnsLib.HL7.Service.TCPService, EnsLib.FHIR.Operation.REST)",
        "Agent proposes the production layout and asks the Builder to approve",
        "Builder clicks Approve",
        "Agent creates the production, adds the hosts, configures settings",
        "Agent builds and sends a test HL7 ADT^A04 message",
        "Agent validates the result and reports success",
        "Builder reviews the audit log to see the complete trace",
    ]
    for i, step in enumerate(steps, 1):
        doc.add_paragraph(f"{i}. {step}")

    # 6. Non-Functional Requirements
    doc.add_heading("7. Non-Functional Requirements", level=1)
    add_table(doc,
        ["Requirement", "Target"],
        [
            ["Response latency", "First token in < 2 seconds; full response in < 90 seconds per turn"],
            ["Concurrent users", "5 simultaneous chat sessions (single IRIS instance)"],
            ["Catalog rebuild", "< 30 seconds for full Ens.* + HS.* re-index"],
            ["Field mapping rebuild", "< 1 second for full HL7/SDA3/FHIR trace (1538 rows)"],
            ["Availability", "System operational whenever IRIS is running; no external dependencies except LLM provider"],
            ["Data retention", "Audit logs retained indefinitely; no automatic purge"],
            ["Browser support", "Chrome 120+, Edge 120+, Firefox 120+ (ES2020 baseline)"],
        ])

    # Appendix
    doc.add_heading("Appendix A: Admin UI Tab Summary", level=1)
    add_table(doc,
        ["Tab", "Purpose", "Entity Count"],
        [
            ["Agents", "Agent configuration (system prompt, MCPs, skills, provider)", "1 (HealthInterop)"],
            ["MCPs", "MCP server enable/disable and description", "4 (Production, Transform, Testing, Catalog)"],
            ["ToolSets", "ToolSet grouping and description", "5 (Production, Transform, Testing, Catalog, Monitoring)"],
            ["Tools", "Individual tool schemas and dry-run", "42 tools"],
            ["Skills", "Skill INSTRUCTIONS editor", "12 skills"],
            ["Connections", "LLM provider credentials and health check", "N (user-configured)"],
            ["Catalogs", "Vector catalog status, rebuild, search", "2 (Ens.*, HS.*)"],
            ["Transforms", "Field-level mapping explorer (Data Atlas)", "1538 pre-computed rows"],
            ["Audit", "Request audit trail", "All API calls"],
        ])

    path = os.path.join(DOCS, "01_Requirements_User_Stories.docx")
    doc.save(path)
    print(f"  saved {path}")


# =============================================================================
# Document 2: Technical Build Specification
# =============================================================================
def build_doc2():
    doc = Document()
    style_doc(doc)
    add_title_page(doc,
        "Agentic Health Interoperability",
        "Technical Build Specification")

    # 1. Executive Summary
    doc.add_heading("1. Executive Summary", level=1)
    doc.add_paragraph(
        "This document specifies the components InterSystems must build to deliver a production-grade "
        "Agentic Health Interoperability solution. The system is a configuration-driven AI Copilot "
        "embedded in IRIS for Health that enables integration engineers to build Productions, create "
        "Transformations, and test healthcare messages through natural-language conversation.")
    doc.add_paragraph(
        "The solution is built on the IRIS %AI Framework (Agent, MCP, ToolSet, Tool, Skill primitives) "
        "and extends it with application-specific infrastructure: a chat UX, an admin UI, vector "
        "catalogs, a transformation data atlas, connection management, and audit/security controls.")

    # 2. Chatbot UX
    doc.add_page_break()
    doc.add_heading("2. Chatbot UX", level=1)
    doc.add_paragraph(
        "A streaming chat interface embedded in the IRIS Management Portal that connects to a "
        "%AI.Agent via Server-Sent Events (SSE). The chatbot is the Builder's primary interface "
        "for interacting with the agent.")
    add_figure(doc, img("15_chatbot.png"),
        "Chat interface with streaming responses, starter prompts, conversation sidebar, and connection status")

    doc.add_heading("2.1 Streaming Responses", level=2)
    doc.add_paragraph("SSE endpoint (POST /chat/stream) emits tokens as they arrive from the LLM. "
        "Each token is a data: event with JSON payload. Tool lifecycle events (tool_start, tool_args, "
        "tool_result, tool_error) render as inline cards.")

    doc.add_heading("2.2 Confirmation Gate", level=2)
    doc.add_paragraph("Mutating tools (create, update, delete) pause execution and surface an "
        "Approve/Reject prompt. The AgenticInterop.Policy.ConfirmationGate policy intercepts "
        "tool calls before execution. Rejection feeds back to the agent as a tool error.")

    doc.add_heading("2.3 Performance Guardrails", level=2)
    doc.add_paragraph("AgenticInterop.Agent.Monitor enforces per-turn limits: 60-second deadline "
        "and 50,000 token budget. If a turn exceeds limits, the monitor triggers a graceful stop "
        "and the agent summarizes partial results.")

    # 3. Agent
    doc.add_page_break()
    doc.add_heading("3. Agent", level=1)
    doc.add_paragraph(
        "A single %AI.Agent instance ('HealthInterop') serves as the router agent. It receives "
        "user messages, decides which tools or skills to invoke, and orchestrates multi-step workflows.")
    add_figure(doc, img("02_agent_detail.png"),
        "Agent configuration editor showing system prompt, temperature, max iterations, tool binding mode, and MCP/skill bindings")

    doc.add_heading("3.1 Agent Architecture", level=2)
    doc.add_paragraph("AgenticInterop.Agent.HealthInterop (extends %AI.Agent)")
    doc.add_paragraph("  Manager: builds configured agent at request time (loads provider, binds MCPs, loads skills, attaches policies)", style="List Bullet")
    doc.add_paragraph("  Monitor: iteration callback enforcing 60s deadline + 50K token budget", style="List Bullet")
    doc.add_paragraph("  SkillLoader: discovers Skill.Base subclasses and registers as tools", style="List Bullet")

    doc.add_heading("3.2 Runtime Configuration", level=2)
    add_table(doc,
        ["Parameter", "Default", "Configurable Via"],
        [
            ["System prompt", "Shipped class INSTRUCTIONS", "Admin UI Agent editor"],
            ["Temperature", "0.3", "Admin UI slider"],
            ["Max iterations", "25", "Admin UI input"],
            ["Bound MCPs", "All 4", "Admin UI checkbox list"],
            ["Bound skills", "All 12", "Admin UI checkbox list"],
            ["LLM provider", "bedrock-default", "Admin UI dropdown"],
            ["Tool binding", "MCP chain", "Admin UI radio (mcp/bypass)"],
        ])

    doc.add_heading("3.3 Overlay Pattern", level=2)
    doc.add_paragraph(
        "Shipped class defaults and user customizations both survive across IPM upgrades. "
        "Override tables (AgentOverride, MCPOverride, ToolSetOverride) store admin UI changes. "
        "At build time, the Overlay class merges overrides on top of compiled defaults. "
        "'Reset to defaults' deletes the override row.")

    # 4. Skills
    doc.add_page_break()
    doc.add_heading("4. Skills", level=1)
    doc.add_paragraph(
        "Declarative sub-agents that package domain knowledge as markdown INSTRUCTIONS. The main "
        "agent delegates domain-specific questions to the appropriate skill rather than answering "
        "from general training data.")
    add_figure(doc, img("07_skills_list.png"),
        "Skills tab listing the 12 shipped skills covering IRIS interoperability domains")
    add_figure(doc, img("08_skill_detail.png"),
        "Skill editor showing class name, description, bound ToolSets, and expandable class source")

    doc.add_heading("4.1 Skill Catalog (v1)", level=2)
    add_table(doc,
        ["Skill", "Domain", "Content Source"],
        [
            ["Productions", "Production anatomy, BS/BP/BO patterns, settings", "IRIS documentation"],
            ["DTL", "Data Transformation Language syntax, foreach, subtransforms", "IRIS documentation"],
            ["BPL", "Business Process Language activities, compensation, async", "IRIS documentation"],
            ["RoutingRules", "Rule sets, constraints, when conditions, HL7 routing", "IRIS documentation"],
            ["HL7v2", "Message types, segments, ACK semantics, composite types", "HL7 v2 specification"],
            ["FHIRR4", "Resources, references, search params, server operations", "FHIR R4 specification"],
            ["SDA", "SDA3 model, common pitfalls, mapping to FHIR", "IRIS documentation"],
            ["RestInProductions", "RESTful services inside productions, HTTP adapters", "IRIS documentation"],
            ["ESBPattern", "Enterprise Service Bus patterns, routing, transformation", "Architecture guides"],
            ["X12", "X12 transaction sets, EDI healthcare claims", "X12 specification"],
            ["CDA", "Clinical Document Architecture, CCD, C-CDA", "CDA specification"],
            ["Adapters", "Inbound/outbound adapters, TCP, HTTP, SOAP, file, FTP", "IRIS documentation"],
        ])

    # 5. MCP Servers
    doc.add_page_break()
    doc.add_heading("5. MCP Servers", level=1)
    doc.add_paragraph(
        "Four internal MCP (Model Context Protocol) servers group related capabilities into "
        "named service domains. Each MCP maps to one or more ToolSets.")
    add_figure(doc, img("03_mcps_list.png"),
        "MCP servers: catalog, production, testing, and transform")

    add_table(doc,
        ["MCP Server", "ToolSets", "Purpose"],
        [
            ["mcp.production", "Production", "CRUD productions, business hosts, settings, start/stop"],
            ["mcp.transform", "Transform", "CRUD DTL/BPL, routing rules, lookup tables, HL7 schema"],
            ["mcp.testing", "Testing", "Send HL7/FHIR messages, validate, compare"],
            ["mcp.catalog", "Catalog, Monitoring", "Vector search, class introspection, event log, throughput"],
        ])

    # 6. Tools
    doc.add_page_break()
    doc.add_heading("6. Tools", level=1)
    doc.add_paragraph(
        "42 tools across 5 tool classes implement the agent's capabilities. Each tool is a method "
        "with [Tool] annotation, JSON Schema input/output, and a natural-language description.")
    add_figure(doc, img("05_tools_list.png"),
        "All 42 tools listed across the five ToolSet classes")
    add_figure(doc, img("06_tool_detail.png"),
        "Tool detail editor showing the LLM contract description, method signature, input schema, and configuration")

    doc.add_heading("6.1 Tool Catalog by ToolSet", level=2)
    add_table(doc,
        ["ToolSet", "Tool Count", "Tools"],
        [
            ["Production", "13", "list_productions, get_production, create_production, delete_production, start_production, stop_production, add_business_host, remove_business_host, update_settings, PostBuildValidation, ..."],
            ["Transform", "13", "list_dtls, get_dtl, create_dtl, update_dtl, compile_dtl, delete_dtl, list_bpls, create_bpl, list_routing_rules, create_routing_rule, introspect_hl7_schema, ..."],
            ["Testing", "8", "send_hl7, send_fhir, validate_hl7_structure, validate_fhir_resource, compare_messages, BuildAndSendHL7TestMessage, ..."],
            ["Catalog", "8", "search_ens, search_hs, describe_class, get_namespace, list_classes, lookup_reference, search_glossary, ..."],
            ["Monitoring", "6", "query_event_log, group_errors, message_status, throughput_stats, queue_depth, ..."],
        ])

    doc.add_heading("6.2 Tool Policies", level=2)
    doc.add_paragraph("ConfirmationGate: Mutating tools require explicit user approval before execution.", style="List Bullet")
    doc.add_paragraph("ToolFilter: Strips framework waste tools (FileSystem, SQL, ShellTools) from the LLM catalog. Saves ~3K tokens per request.", style="List Bullet")

    # 7. Catalogs
    doc.add_page_break()
    doc.add_heading("7. Vector Catalogs", level=1)
    doc.add_paragraph(
        "Two semantic search catalogs index the IRIS class library so the agent can find relevant "
        "Business Hosts, adapters, and transformation classes by natural-language query.")
    add_figure(doc, img("11_catalogs.png"),
        "Catalogs tab showing search_ens (164 rows) and search_hs (58 rows) with kind breakdowns, rebuild controls, and test search panel")

    add_table(doc,
        ["Catalog", "Name", "Row Count", "Source"],
        [
            ["Ens.*", "search_ens", "164", "%Dictionary for Ens.Host, Ens.BusinessService, Ens.BusinessProcess, Ens.BusinessOperation, adapters"],
            ["HS.*", "search_hs", "58", "%Dictionary for HS.* transformation classes, FHIR mappers, SDA helpers"],
        ])

    doc.add_heading("7.1 Technical Implementation", level=2)
    doc.add_paragraph("Embedding model: FastEmbed (384-dimensional vectors, bundled with IRIS)", style="List Bullet")
    doc.add_paragraph("Vector storage: %AI.RAG.KnowledgeBase with HNSW index", style="List Bullet")
    doc.add_paragraph("Query path: %AI.ToolMgr.ExecuteTool(kbName, args) -- the only working path (SQL EMBEDDING() does not work with FastEmbed)", style="List Bullet")
    doc.add_paragraph("Document format: Curated prose descriptions, not raw method signatures", style="List Bullet")

    # 8. Data Atlas
    doc.add_page_break()
    doc.add_heading("8. Data Atlas (Transformation Mappings)", level=1)
    doc.add_paragraph(
        "A visual field-level mapping explorer showing how data flows between external formats "
        "(HL7 v2, FHIR R4, CDA, X12) through the SDA3 canonical model.")
    add_figure(doc, img("12_transforms_empty.png"),
        "Transforms tab initial state: format pair selection (Data From / Data To dropdowns) with 1538 pre-computed rows")
    add_figure(doc, img("13_transforms_hl7_fhir.png"),
        "Data Atlas with HL7 v2 to FHIR R4 selected, showing SDA3.Address mappings at sub-field level with IRIS class names and coverage filters")

    doc.add_heading("8.1 Data Flow Model", level=2)
    doc.add_paragraph("SDA3 is the universal pivot: all external formats map through it.")
    doc.add_paragraph("HL7 v2 (inbound) --> SDA3 (canonical) --> FHIR R4 (outbound)")
    doc.add_paragraph("Example: PID.11.3 City --> City --> city")

    doc.add_heading("8.2 Data Sources", level=2)
    doc.add_paragraph("HL7 to SDA3: Programmatic extraction from HS.Gateway.HL7.HL7ToSDA3 ObjectScript methods (not DTL)", style="List Bullet")
    doc.add_paragraph("SDA3 to FHIR: DTL class analysis via HS.FHIR.DTL.SDA3.vR4.* with backward-walk algorithm", style="List Bullet")
    doc.add_paragraph("Sub-field enrichment: Static lookup mapping composite HL7 types (XAD, XPN, CX, XTN) to component fields", style="List Bullet")

    # 9. Connection Management
    doc.add_page_break()
    doc.add_heading("9. Connection Management", level=1)
    doc.add_paragraph(
        "A multi-provider LLM connection manager that stores credentials securely and provides "
        "health-check (connection test) functionality.")
    add_figure(doc, img("10_connection_detail.png"),
        "Connection editor showing Bedrock configuration with provider, model, region, masked API key, and Test Connection button")

    add_table(doc,
        ["Provider", "Config Fields", "Secret Field"],
        [
            ["AWS Bedrock", "region, model", "AWS_BEARER_TOKEN_BEDROCK (Wallet)"],
            ["Anthropic", "model, base URL", "ANTHROPIC_API_KEY (Wallet)"],
            ["OpenAI", "model, base URL", "OPENAI_API_KEY (Wallet)"],
            ["Azure OpenAI", "endpoint, deployment, API version", "AZURE_OPENAI_API_KEY (Wallet)"],
            ["Google Gemini", "model, region", "GEMINI_API_KEY (Wallet)"],
            ["NVIDIA NIM", "model, base URL", "NIM_API_KEY (Wallet)"],
        ])

    doc.add_heading("9.1 Security Invariants", level=2)
    doc.add_paragraph("API keys are NEVER stored in SQL tables, globals, or source code", style="List Bullet")
    doc.add_paragraph("API keys are NEVER returned by any REST endpoint", style="List Bullet")
    doc.add_paragraph("API keys are NEVER logged in audit trail", style="List Bullet")
    doc.add_paragraph("The only storage location is the IRIS Secured Wallet", style="List Bullet")

    # 10. Audit & Security
    doc.add_page_break()
    doc.add_heading("10. Audit and Security", level=1)
    add_figure(doc, img("14_audit.png"),
        "Audit log showing all API requests with status codes, methods, paths, timestamps, users, and durations")

    doc.add_heading("10.1 Audit Log Fields", level=2)
    add_table(doc,
        ["Field", "Description"],
        [
            ["Timestamp", "When the request was received"],
            ["Username", "Authenticated IRIS user"],
            ["Namespace", "Active namespace at request time"],
            ["SessionId", "Browser session identifier"],
            ["Job", "IRIS job number"],
            ["Method", "GET, POST, PUT, DELETE"],
            ["Path", "/api/agentic/chat/stream"],
            ["StatusCode", "HTTP response status"],
            ["Duration", "End-to-end request time"],
            ["Kind", "registry, editor.agent, chat, namespace, etc."],
        ])

    # 11. Performance
    doc.add_page_break()
    doc.add_heading("11. Performance", level=1)
    add_table(doc,
        ["Metric", "Target", "How Achieved"],
        [
            ["First token latency", "< 2 seconds", "SSE streaming, no buffering"],
            ["Turn completion", "< 90 seconds", "Monitor: 60s deadline + 50K token budget"],
            ["Catalog search", "< 500ms", "Pre-built HNSW vector index, in-process query"],
            ["Field mapping load", "< 100ms", "Pre-computed SQL table (1538 rows)"],
            ["Catalog rebuild", "< 30 seconds", "Batch %Dictionary walk + FastEmbed"],
            ["Concurrent users", "5 sessions", "Per-process agent instances, no shared state"],
            ["Token efficiency", "< 50K tokens/task", "ToolFilter, curated skills, no markdown overhead"],
        ])

    # 12. Implementation Summary
    doc.add_heading("12. Implementation Summary", level=1)
    add_table(doc,
        ["Component", "Classes", "Status"],
        [
            ["Agent", "4 classes (HealthInterop, Manager, Monitor, SkillLoader)", "Built"],
            ["MCP Servers", "5 classes (Base + 4 servers)", "Built"],
            ["ToolSets", "5 classes", "Built"],
            ["Tools", "5 classes, 42 tools", "Built"],
            ["Skills", "13 classes (Base + 12 skills)", "Built"],
            ["Data model", "6 persistent classes", "Built"],
            ["REST API", "1 dispatcher + 13 service classes", "Built"],
            ["Admin UI", "3 HTML + 2 JS + 2 CSS files", "Built"],
            ["Chat UI", "1 HTML + 1 JS + 1 CSS file", "Built"],
            ["Vector catalogs", "2 classes (Builder, Attach)", "Built"],
            ["Data Atlas", "2 classes (TransformService, FieldMapping)", "Built"],
            ["Policies", "2 classes (ConfirmationGate, ToolFilter)", "Built"],
            ["Install hooks", "2 classes (CSPTimeoutPatch, InteropEditorPatch)", "Built"],
            ["IPM package", "module.xml", "Built"],
            ["Total", "61 ObjectScript classes, 8 web files, 95 commits", ""],
        ])

    path = os.path.join(DOCS, "02_Technical_Build_Specification.docx")
    doc.save(path)
    print(f"  saved {path}")


# =============================================================================
# Document 3: Lessons Learned
# =============================================================================
def build_doc3():
    doc = Document()
    style_doc(doc)
    add_title_page(doc,
        "Agentic Health Interoperability",
        "Lessons Learned\nFindings from the experimental build of an Agentic AI Copilot on IRIS for Health")

    # 1. Introduction
    doc.add_heading("1. Introduction", level=1)
    doc.add_paragraph(
        "This document captures the key lessons learned during the experimental build of the "
        "Agentic Health Interoperability project on InterSystems IRIS for Health 2026.2 with the "
        "%AI Framework (build 162.0). These findings cover framework bugs, performance optimizations "
        "using Vector Search, and strategies for reducing token consumption and improving response speed.")

    # 2. Bugs in the %AI Framework
    doc.add_page_break()
    doc.add_heading("2. Bugs in the %AI Framework", level=1)

    doc.add_heading("2.1 BUG: %AI.Agent.Skill %OnNew $ZF Marshaling Error", level=2)
    doc.add_paragraph("Severity: Blocker (prevents skill instantiation)")
    doc.add_paragraph(
        "When instantiating a skill via %New(), the parent %OnNew method passes a %DynamicObject "
        "to $ZF (the Foreign Function Interface call to the Rust LLM bridge). The $ZF call expects "
        "a JSON string, not an object reference, and throws a <FUNCTION> error.")
    doc.add_paragraph(
        "Workaround: Created AgenticInterop.Skill.Base that overrides %OnNew to serialize the "
        "DynamicObject to a JSON string before the $ZF call using literal macro values "
        "(IrisLLMLibrary=1042, LLMBUILDSKILLFROMJSON=66).")
    doc.add_paragraph(
        "Recommendation: Fix %AI.Agent.Skill.%OnNew to serialize the DynamicObject to a JSON "
        "string before the $ZF call.")

    doc.add_heading("2.2 BUG: Bedrock Tool-Result Round-Trip Hang", level=2)
    doc.add_paragraph("Severity: Blocker (prevents multi-turn tool use with Bedrock)")
    doc.add_paragraph(
        "When the agent calls a tool and receives the result, the Rust bridge hangs indefinitely "
        "when sending the tool result back to the Bedrock Converse API. The hang occurs below the "
        "ObjectScript API surface -- the StreamChat() or Run() call never returns.")
    doc.add_paragraph(
        "Tested with Claude Sonnet 4 and Claude Haiku 3.5 via Bedrock (us-east-1), both cross-region "
        "and direct endpoints. All configurations reproduce the hang.")
    doc.add_paragraph(
        "Workaround: Use Anthropic direct (not via Bedrock) as the runtime LLM provider.")

    doc.add_heading("2.3 ISSUE: %FromJSON Instance Method Returns Empty String", level=2)
    doc.add_paragraph("Severity: Medium (causes silent data loss)")
    doc.add_paragraph(
        "Calling {}.%FromJSON(jsonString) returns '' (empty string) instead of a populated object. "
        "The instance form of %FromJSON appears non-functional on this IRIS build.")
    doc.add_paragraph(
        "Workaround: Use the class-method form: "
        "Set obj = ##class(%DynamicAbstractObject).%FromJSON(jsonString)")

    doc.add_heading("2.4 ISSUE: $get() on %DynamicObject Properties Throws <INVALID CLASS>", level=2)
    doc.add_paragraph("Severity: Medium (causes runtime errors in otherwise valid code)")
    doc.add_paragraph(
        "$get(dynamicObj.propertyName, defaultValue) throws <INVALID CLASS> when the property "
        "doesn't exist. ObjectScript $get doesn't handle %DynamicObject property access the way "
        "it handles local variables.")
    doc.add_paragraph(
        "Workaround: Use $select with %IsDefined: "
        "Set value = $select(obj.%IsDefined(\"propName\"): obj.propName, 1: defaultValue)")

    doc.add_heading("2.5 ISSUE: CSP UseSession Deadlock on REST Endpoints", level=2)
    doc.add_paragraph("Severity: High (causes 401 errors on second request in same browser session)")
    doc.add_paragraph(
        "When UseSession=1 (the default) on a %CSP.REST class, the CSP gateway validates the "
        "CSRF token on every request. When called from an iframe, the second request in the same "
        "browser session gets a 401 because the CSRF token validation races with the iframe's "
        "credential handling.")
    doc.add_paragraph("Workaround: Set UseSession=0 on every REST dispatch class.")

    doc.add_heading("2.6 ISSUE: %OpenId Returns Stale Data in Cross-Process Polling", level=2)
    doc.add_paragraph("Severity: High (causes infinite polling loops)")
    doc.add_paragraph(
        "%OpenId(id) uses a process-local OREF cache. In a polling loop where Process A writes "
        "a row and Process B polls with %OpenId, Process B's cache returns the stale pre-update "
        "state indefinitely. The poll never sees the update.")
    doc.add_paragraph(
        "Workaround: Use SQL queries for cross-process polling instead of %OpenId.")

    # 3. ObjectScript Language Gotchas
    doc.add_page_break()
    doc.add_heading("3. ObjectScript Language Gotchas", level=1)
    doc.add_paragraph(
        "These are not framework bugs but language behaviors that caused significant debugging "
        "time during development.")

    doc.add_heading("3.1 Numeric Comparison Operators on Strings", level=2)
    doc.add_paragraph(
        'ObjectScript >=, <=, >, < operators are NUMERIC, not string-based. The expression '
        'ch >= "A" && ch <= "Z" always evaluates to true because both sides coerce to 0.')
    doc.add_paragraph(
        "Solution: Use $ascii() for character range comparisons: "
        "Set code = $ascii(ch); If (code >= 65) && (code <= 90)")

    doc.add_heading("3.2 QUIT Inside try/catch Blocks", level=2)
    doc.add_paragraph(
        "quit value only works at the method top level. Inside a block (if/for/while/try/catch), "
        "quit exits the block without a return value. This causes silent method exits.")
    doc.add_paragraph(
        "Solution: Capture to a local variable and quit after the block, or use RETURN value "
        "which works from anywhere.")

    doc.add_heading("3.3 Comment Syntax Inside Method Bodies", level=2)
    doc.add_paragraph(
        "// comments work at the class level but cause #1002 compile errors inside "
        "ClassMethod/Method bodies on some IRIS versions.")
    doc.add_paragraph(
        "Solution: Use ; (semicolon) for comments inside method bodies.")

    # 4. Vector Search
    doc.add_page_break()
    doc.add_heading("4. Vector Search: Improving Velocity", level=1)

    add_figure(doc, img("11_catalogs.png"),
        "Vector catalogs admin panel showing indexed class counts and kind breakdowns")

    doc.add_heading("4.1 The Embedding Quality Problem", level=2)
    doc.add_paragraph(
        "The initial catalog builder indexed every class by dumping its full %Dictionary.ClassDefinition "
        "content -- including auto-generated accessor methods, storage definitions, and parameter "
        "boilerplate. In a 384-dimensional embedding space, this structural noise drowned out the "
        "semantic signal (class description, purpose, key behaviors).")
    doc.add_paragraph(
        'Result: Searches for "HL7 TCP service" returned generic base classes instead of '
        "EnsLib.HL7.Service.TCPService because the relevant description text was a tiny fraction "
        "of the indexed content.")

    doc.add_heading("4.2 The Fix: Curated Prose Over Raw Metadata", level=2)
    add_table(doc,
        ["Before (Noisy)", "After (Curated)"],
        [
            ["Full class dump including storage, indices, XData", "Class name + description + superclass + key parameters"],
            ["Auto-generated accessor methods (Get/Set/IsValid)", "Removed entirely"],
            ["Parameter definitions with internal flags", "Only parameters the user would configure"],
            ["Inherited method signatures from 5 levels of superclass", "Only overridden methods with their descriptions"],
        ])
    doc.add_paragraph(
        'Impact: Search relevance improved dramatically. "HL7 TCP inbound service" now returns '
        "EnsLib.HL7.Service.TCPService as the top result with a cosine similarity of 0.85+.")

    doc.add_heading("4.3 Query Path Discovery", level=2)
    doc.add_paragraph(
        "The documented EMBEDDING() SQL function does NOT work with the bundled FastEmbed embedding "
        "model. After extensive testing, the only working query path is "
        "%AI.ToolMgr.ExecuteTool(kbName, args), which routes through the %AI.RAG.KnowledgeBase "
        "internal search pipeline.")

    # 5. Reducing Token Consumption
    doc.add_page_break()
    doc.add_heading("5. Reducing Token Consumption and Improving Speed", level=1)

    doc.add_heading("5.1 The Problem", level=2)
    doc.add_paragraph(
        "A naive agent configuration with all framework tools exposed consumed 15K+ tokens per "
        "request just for the tool catalog. Complex multi-turn tasks could exceed 100K tokens "
        "before producing a useful result. Response times were 30-60 seconds per turn.")

    doc.add_heading("5.2 Strategy 1: ToolFilter Policy (saved ~3K tokens per request)", level=2)
    doc.add_paragraph(
        "The %AI Framework exposes default tools (FileSystem, SQL, ShellTools) that are irrelevant "
        "for healthcare interoperability tasks. The ToolFilter strips these before each LLM call.")
    doc.add_paragraph("Before: 57 tools in the LLM catalog (~15K tokens)")
    doc.add_paragraph("After: 42 tools in the LLM catalog (~10K tokens)")

    doc.add_heading("5.3 Strategy 2: Concise Tool Descriptions (saved ~2K tokens)", level=2)
    doc.add_paragraph(
        "Early tool descriptions were verbose explanations. We rewrote them as imperative contracts: "
        "verb, scope, side effects, expected inputs. The concise versions convey the same information "
        "in 80% fewer tokens. Multiply by 42 tools and the savings are significant.")

    doc.add_heading("5.4 Strategy 3: No Markdown Formatting (eliminated rendering bugs)", level=2)
    doc.add_paragraph(
        "The chat UI renders plain text. Markdown bold (**text**) and italic (*text*) appear as "
        "literal asterisks. We instructed the agent to use plain prose with line breaks and - bullets.")

    doc.add_heading("5.5 Strategy 4: Monitor Callback with Token Budget", level=2)
    doc.add_paragraph(
        "AgenticInterop.Agent.Monitor enforces a 50K token budget per turn. This prevents infinite "
        "tool-call loops, excessive catalog searches, and runaway conversation depth.")

    doc.add_heading("5.6 Strategy 5: Breaking Complex Tasks into Multiple Short Turns", level=2)
    doc.add_paragraph("Instead of one massive prompt, the agent works in phases:")
    doc.add_paragraph("1. Research phase: Search catalogs, introspect schemas (read-only, fast)")
    doc.add_paragraph("2. Proposal phase: Present a plan, ask for approval (no tool calls)")
    doc.add_paragraph("3. Build phase: Execute step by step (mutating tools, confirmation gates)")
    doc.add_paragraph("4. Validation phase: Run PostBuildValidation, send test messages")
    doc.add_paragraph("5. Report phase: Summarize what was done")
    doc.add_paragraph("Each phase is a short LLM turn (< 30 seconds, < 20K tokens).")

    doc.add_heading("5.7 Results", level=2)
    add_table(doc,
        ["Metric", "Before Optimization", "After Optimization"],
        [
            ["Tool catalog tokens", "~15K", "~10K"],
            ["System prompt tokens", "~5K", "~2K"],
            ["Simple query (list productions)", "~25K total tokens", "~15K total tokens"],
            ["Complex task (build production)", "~120K total tokens", "~50K total tokens"],
            ["Simple query latency", "8-12 seconds", "3-5 seconds"],
            ["Complex task latency", "90+ seconds (often timeout)", "45-60 seconds (across 3-4 turns)"],
        ])

    # 6. Additional Findings
    doc.add_page_break()
    doc.add_heading("6. Additional Findings", level=1)

    doc.add_heading("6.1 SDA3 as the Universal Pivot", level=2)
    doc.add_paragraph(
        "The most powerful architectural insight for the Data Atlas was that SDA3 is the universal "
        "pivot format in IRIS for Health. Every external format (HL7 v2, FHIR R4, CDA, X12) maps "
        "through SDA3. This means field-level mappings can be pre-computed as a three-column join: "
        "Source -> SDA3 -> Target. Any format pair can be traced by chaining two half-maps through SDA3.")
    add_figure(doc, img("13_transforms_hl7_fhir.png"),
        "Data Atlas showing the SDA3 pivot pattern: HL7 v2 fields map into SDA3, SDA3 maps out to FHIR R4")

    doc.add_heading("6.2 HL7 v2 Programmatic Mappings Are NOT DTL", level=2)
    doc.add_paragraph(
        "The HL7 -> SDA3 direction is implemented in ObjectScript methods "
        "(HS.Gateway.HL7.HL7ToSDA3), not in DTL classes. This required a completely different "
        "extraction approach -- parsing ObjectScript source for Set statements targeting SDA properties.")

    doc.add_heading("6.3 Vanilla JS vs. React for the Admin UI", level=2)
    doc.add_paragraph(
        "The original plan called for React 18 + TypeScript + Vite. During implementation, we "
        "switched to vanilla JavaScript because: the IRIS CSP gateway serves static files (no build "
        "step), the admin UI is a configuration tool (not complex interactive), and it eliminates "
        "framework bundle size (React + ReactDOM = 130KB gzipped).")

    doc.add_heading("6.4 The Overlay Pattern for Configuration Persistence", level=2)
    doc.add_paragraph(
        "The 'class-as-data' model created a tension between shipped defaults and user customizations. "
        "IPM zpm load recompiles shipped classes, overwriting manual edits. The overlay pattern "
        "resolves this: shipped class parameters define defaults, override tables store user edits, "
        "at build time the overlay merges overrides on top, and 'Reset to defaults' deletes the row.")

    # 7. Recommendations
    doc.add_page_break()
    doc.add_heading("7. Summary of Recommendations for InterSystems", level=1)
    add_table(doc,
        ["#", "Category", "Recommendation", "Impact"],
        [
            ["1", "Framework bug", "Fix %AI.Agent.Skill.%OnNew $ZF marshaling", "Eliminates need for Skill.Base workaround"],
            ["2", "Framework bug", "Fix Bedrock tool-result round-trip hang", "Enables Bedrock as a production runtime provider"],
            ["3", "API fix", "Fix %DynamicObject.%FromJSON() instance method", "Eliminates silent data loss"],
            ["4", "API fix", "Document that $get() doesn't work on %DynamicObject properties", "Prevents runtime errors"],
            ["5", "Documentation", "Document %AI.ToolMgr.ExecuteTool() as the RAG query path", "SQL EMBEDDING() doesn't work with FastEmbed"],
            ["6", "Performance", "Add ToolFilter-like policy to framework defaults", "Prevents token waste from generic tools"],
            ["7", "Performance", "Expose token usage metrics from Rust bridge", "Enables application-level token budgeting"],
            ["8", "CSP", "Add Cache-Control: no-cache option for development web apps", "Eliminates static file caching during development"],
        ])

    path = os.path.join(DOCS, "03_Lessons_Learned.docx")
    doc.save(path)
    print(f"  saved {path}")


if __name__ == "__main__":
    print("Building .docx documents with screenshots...")
    build_doc1()
    build_doc2()
    build_doc3()
    print("\nAll three documents built.")
