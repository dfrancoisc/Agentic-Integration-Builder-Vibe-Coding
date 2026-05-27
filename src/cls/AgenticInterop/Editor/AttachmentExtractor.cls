/// Extract text from a chat attachment file so the agent can read it.
///
/// v1 supported types: pdf (PyMuPDF/fitz), xlsx/xlsm (openpyxl), txt, md.
/// Image-only / scanned PDFs (OCR) and docx are deferred to v2.
///
/// The Python helpers return JSON strings so the ObjectScript caller can
/// parse them with %DynamicAbstractObject.%FromJSON, avoiding the
/// per-IRIS-build quirks of returning typed IRIS objects from Python.
Class AgenticInterop.Editor.AttachmentExtractor Extends %RegisteredObject
{

/// Dispatch by file extension. Returns
/// { ok, type, name, bytes, text, pages?, sheets?, error? } as a
/// %DynamicObject. `text` is what the LLM sees; the agent never sees
/// the file bytes.
ClassMethod Extract(path As %String, originalName As %String = "") As %DynamicObject
{
    Set out = {}
    Set out.ok = 0
    Set name = $select(originalName="":##class(%File).GetFilename(path), 1:originalName)
    Set out.name = name
    Set ext = $zconvert($piece(name, ".", *), "L")
    Set out.type = ext
    Try {
        Set out.bytes = ##class(%File).GetFileSize(path)
        If ext = "pdf" {
            Set json = ..ExtractPDFJson(path)
            Set r = ##class(%DynamicAbstractObject).%FromJSON(json)
            Set out.text = r.text
            Set out.pages = r.pages
            Set out.ok = 1
        } ElseIf (ext = "xlsx") || (ext = "xlsm") {
            Set json = ..ExtractXLSXJson(path)
            Set r = ##class(%DynamicAbstractObject).%FromJSON(json)
            Set out.text = r.text
            Set out.sheets = r.sheets
            Set out.ok = 1
        } ElseIf (ext = "txt") || (ext = "md") || (ext = "markdown") {
            Set out.text = ..ExtractPlain(path)
            Set out.ok = 1
        } Else {
            Set out.error = "Unsupported file type: " _ ext _ ". v1 accepts pdf, xlsx, txt, md."
        }
    } Catch ex {
        Set out.error = $extract(ex.DisplayString(), 1, 400)
    }
    Quit out
}

/// PDF extraction via PyMuPDF. Returns a JSON string
/// { "text": "...", "pages": N }. Per-page text is separated by a
/// "--- page N ---" marker so the agent can refer to page numbers.
ClassMethod ExtractPDFJson(path As %String) As %String [ Language = python ]
{
    import fitz, json
    doc = fitz.open(path)
    parts = []
    for i in range(doc.page_count):
        t = doc[i].get_text("text").strip()
        if t:
            parts.append(f"--- page {i+1} ---\n{t}")
    pages = doc.page_count
    doc.close()
    return json.dumps({"text": "\n\n".join(parts), "pages": pages})
}

/// xlsx/xlsm extraction via openpyxl. Returns a JSON string
/// { "text": "...", "sheets": "Sheet1,Sheet2,..." }. Each sheet is
/// flattened to pipe-delimited rows; fully-empty rows are skipped.
ClassMethod ExtractXLSXJson(path As %String) As %String [ Language = python ]
{
    from openpyxl import load_workbook
    import json
    wb = load_workbook(path, read_only=True, data_only=True)
    parts = []
    sheet_names = []
    for name in wb.sheetnames:
        sh = wb[name]
        sheet_names.append(name)
        lines = [f"--- sheet: {name} ---"]
        for row in sh.iter_rows(values_only=True):
            if all(c is None for c in row):
                continue
            lines.append(" | ".join("" if c is None else str(c) for c in row))
        parts.append("\n".join(lines))
    return json.dumps({"text": "\n\n".join(parts), "sheets": ",".join(sheet_names)})
}

/// txt / md / markdown — stream-read the file. Encoding assumed UTF-8.
ClassMethod ExtractPlain(path As %String) As %String
{
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set sc = stream.LinkToFile(path)
    If 'sc { Quit "" }
    Set text = ""
    Do stream.Rewind()
    While 'stream.AtEnd { Set text = text _ stream.Read(32768) }
    Quit text
}

/// Whitelist gate used by ChatService before staging. Returns 1 if the
/// file extension is supported, 0 otherwise. Centralizes the type list
/// so the UI gate and the server gate cannot drift apart.
ClassMethod IsSupported(filename As %String) As %Boolean
{
    Set ext = $zconvert($piece(filename, ".", *), "L")
    Quit $case(ext, "pdf":1, "xlsx":1, "xlsm":1, "txt":1, "md":1, "markdown":1, :0)
}

}
