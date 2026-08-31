-- © 2026. WordGrinder is licensed under the MIT open source license. See the
-- COPYING file in this distribution for the full text.
--
-- Exporter for Microsoft Word .docx files (Office Open XML / WordprocessingML).
--
-- A .docx is a zip package; we assemble the handful of parts a minimal valid
-- document needs ([Content_Types].xml, the relationship files, styles.xml,
-- numbering.xml and word/document.xml) and hand them to wg.writezip, mirroring
-- the ODT exporter in export/opendocument.lua.
--
-- The paragraph/character styles emitted here are exactly the ones the .docx
-- IMPORTER understands (see import/docx.lua), so a document can be exported and
-- re-imported without losing structure -- which is what makes this useful for
-- round-trip-checking the importer.

local table_concat = table.concat
local writezip = wg.writezip

local W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

-----------------------------------------------------------------------------
-- Mapping WordGrinder paragraph styles -> Word.
--
-- Only P/H1-H4/Q/LB/LN survive a round trip exactly (those are the styles the
-- importer can produce). L, V, PRE and RAW have no importer equivalent and are
-- normalised to their closest Word style.

local PARA_MAP =
{
	["H1"]  = { pstyle = "Heading1" },
	["H2"]  = { pstyle = "Heading2" },
	["H3"]  = { pstyle = "Heading3" },
	["H4"]  = { pstyle = "Heading4" },
	["P"]   = {},
	["Q"]   = { pstyle = "Quote" },
	["V"]   = { pstyle = "Quote" },
	["LB"]  = { pstyle = "ListParagraph", numid = 1 },
	["L"]   = { pstyle = "ListParagraph", numid = 1 },
	["LN"]  = { pstyle = "ListParagraph", numid = 2 },
	["PRE"] = {},
	["RAW"] = {},
}

local function xml_escape(s)
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	return s
end

-----------------------------------------------------------------------------
-- Render the paragraphs of one document into a chunk of <w:p>...</w:p> XML
-- (no document wrapper).

local function body_callback(writer, document)
	local bold, italic, underline = false, false, false

	local function emit_run(text)
		writer("<w:r>")
		if bold or italic or underline then
			writer("<w:rPr>")
			if bold then writer("<w:b/>") end
			if italic then writer("<w:i/>") end
			if underline then writer('<w:u w:val="single"/>') end
			writer("</w:rPr>")
		end
		writer('<w:t xml:space="preserve">')
		writer(xml_escape(text))
		writer("</w:t></w:r>")
	end

	return ExportFileUsingCallbacks(document,
	{
		prologue = function() end,
		epilogue = function() end,

		rawtext = function(s) emit_run(s) end,
		text = function(s) emit_run(s) end,
		notext = function() end,

		italic_on = function() italic = true end,
		italic_off = function() italic = false end,
		bold_on = function() bold = true end,
		bold_off = function() bold = false end,
		underline_on = function() underline = true end,
		underline_off = function() underline = false end,

		list_start = function() end,
		list_end = function() end,

		paragraph_start = function(para)
			local m = PARA_MAP[para.style] or {}
			writer("<w:p>")
			if m.pstyle or m.numid then
				writer("<w:pPr>")
				if m.pstyle then
					writer('<w:pStyle w:val="' .. m.pstyle .. '"/>')
				end
				if m.numid then
					writer('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="'
						.. m.numid .. '"/></w:numPr>')
				end
				writer("</w:pPr>")
			end
			bold, italic, underline = false, false, false
		end,

		paragraph_end = function(para)
			writer("</w:p>")
		end,
	})
end

local function render_body(document)
	return ExportToString(document, body_callback)
end

local function document_xml(bodyxml)
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
		.. '<w:document xmlns:w="' .. W_NS .. '"><w:body>'
		.. bodyxml
		.. '<w:sectPr/></w:body></w:document>\n'
end

-----------------------------------------------------------------------------
-- The static package parts.

local PAGE_BREAK = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'

local CONTENT_TYPES = [[<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>
]]

local ROOT_RELS = [[<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
]]

local DOCUMENT_RELS = [[<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>
]]

local STYLES = [[<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="3"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr><w:rPr><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720"/></w:pPr></w:style>
</w:styles>
]]

local NUMBERING = [[<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/></w:lvl></w:abstractNum>
<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>
]]

local function assemble_docx(filename, bodyxml)
	local parts =
	{
		["[Content_Types].xml"]        = CONTENT_TYPES,
		["_rels/.rels"]                = ROOT_RELS,
		["word/_rels/document.xml.rels"] = DOCUMENT_RELS,
		["word/styles.xml"]            = STYLES,
		["word/numbering.xml"]         = NUMBERING,
		["word/document.xml"]          = document_xml(bodyxml),
	}

	if not writezip(filename, parts) then
		ModalMessage(nil, "Unable to write the output file.")
		QueueRedraw()
		return false
	end

	QueueRedraw()
	return true
end

-----------------------------------------------------------------------------
-- Shared UI: prompt for a filename (single document or set).

local function pick_filename(defaultname, title, extension)
	local filename = defaultname or "(unnamed)"
	if not filename:find("%..-$") then
		filename = filename .. extension
	else
		filename = filename:gsub("%..-$", extension)
	end

	filename = FileBrowser(title, "Export as:", true, filename)
	if not filename then
		return nil
	end
	if filename:find("/[^.]*$") then
		filename = filename .. extension
	end
	return filename
end

-----------------------------------------------------------------------------
-- Commands.

function Cmd.ExportDOCXFile(filename)
	if not filename then
		filename = pick_filename(Document.name, "Export Word Document", ".docx")
		if not filename then
			return false
		end
	end

	ImmediateMessage("Exporting...")
	return assemble_docx(filename, render_body(Document))
end

function Cmd.ExportDOCXFileSet(filename)
	if not filename then
		filename = pick_filename(DocumentSet.name, "Export Word Document Set", ".docx")
		if not filename then
			return false
		end
	end

	ImmediateMessage("Exporting...")

	local scrapbookName = DocumentSet.addons.scrapbook
		and DocumentSet.addons.scrapbook.document
	local bodies = {}
	for _, doc in ipairs(DocumentSet:getDocumentList()) do
		if doc.name ~= scrapbookName then
			bodies[#bodies + 1] = render_body(doc)
		end
	end

	return assemble_docx(filename, table_concat(bodies, PAGE_BREAK))
end

-- Returns the word/document.xml for the current document (used by tests).
function Cmd.ExportToDOCXString()
	return document_xml(render_body(Document))
end
