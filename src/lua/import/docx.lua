-- © 2026. WordGrinder is licensed under the MIT open source license. See the
-- COPYING file in this distribution for the full text.
--
-- Importer for Microsoft Word .docx files (Office Open XML / WordprocessingML).
--
-- A .docx file is a zip archive whose main body lives in word/document.xml.
-- The structure mirrors ODT closely, so this importer follows the same shape as
-- import/opendocument.lua: pull the XML out of the zip, parse it into a tree,
-- and walk the tree driving a CreateImporter() instance.
--
-- Design notes:
--   * Each <w:p> becomes exactly one WordGrinder paragraph, INCLUDING empty
--     ones, so blank lines / paragraph breaks in drafts survive a round trip.
--   * Elements are matched by their local name (the part after the namespace)
--     so both "transitional" and "strict" OOXML namespaces work, and so we are
--     not tripped up by whichever prefix Word/LibreOffice/Google Docs chose.
--   * Tracked changes are imported as if accepted: deletions (<w:del>) and move
--     sources (<w:moveFrom>) are dropped; insertions (<w:ins>) and move
--     destinations (<w:moveTo>) are kept. This is what you want when pulling in
--     a marked-up feedback copy.
--   * List type (bullet vs numbered) is resolved through word/numbering.xml,
--     because Word stores it there (via <w:numPr>) rather than in the style.

local ITALIC = wg.ITALIC
local UNDERLINE = wg.UNDERLINE
local BOLD = wg.BOLD
local ReadFromZip = wg.readfromzip
local string_find = string.find
local string_lower = string.lower
local string_gmatch = string.gmatch
local table_concat = table.concat

-----------------------------------------------------------------------------
-- Small helpers for poking at the ParseXML tree.

-- ParseXML stores element names as "<namespace> <localname>" (or just
-- "<localname>" when there is no namespace). Return just the local name.
local function localname(element)
	local n = element._name
	if not n then
		return nil
	end
	return n:match("([^ ]+)$")
end

-- Read an attribute by its local name. In WordprocessingML an element's
-- attributes share that element's namespace (e.g. <w:pStyle w:val="..."/>), so
-- we reuse the element's namespace to build the attribute key.
local function attrval(element, attrlocal)
	local ns = element._name and element._name:match("^(.-) [^ ]+$")
	if ns then
		return element[ns .. " " .. attrlocal]
	end
	return element[attrlocal]
end

-- Find the first child element with the given local name.
local function child_named(element, name)
	for _, c in ipairs(element) do
		if (type(c) == "table") and (localname(c) == name) then
			return c
		end
	end
	return nil
end

-- OOXML boolean toggle properties (<w:b/>, <w:i/>, ...) are "on" when present
-- with no value, and only "off" when given an explicitly false value.
local function istrue(v)
	if v == nil then
		return true
	end
	v = string_lower(v)
	return not (v == "false" or v == "0" or v == "off" or v == "none" or v == "no" or v == "f")
end

-----------------------------------------------------------------------------
-- Numbering (word/numbering.xml). Builds numId -> { ilvl -> numFmt } so we can
-- tell bulleted lists from numbered lists.

local function build_numbering(numxml)
	local abstract = {}  -- abstractNumId -> { ilvl -> numFmt }
	local numtoabs = {}  -- numId -> abstractNumId

	for _, el in ipairs(numxml) do
		if type(el) == "table" then
			local n = localname(el)
			if n == "abstractNum" then
				local id = attrval(el, "abstractNumId")
				if id then
					local lvls = {}
					for _, lvl in ipairs(el) do
						if (type(lvl) == "table") and (localname(lvl) == "lvl") then
							local li = attrval(lvl, "ilvl") or "0"
							local fmt = child_named(lvl, "numFmt")
							if fmt then
								lvls[li] = attrval(fmt, "val")
							end
						end
					end
					abstract[id] = lvls
				end
			elseif n == "num" then
				local id = attrval(el, "numId")
				local absid = child_named(el, "abstractNumId")
				if id and absid then
					numtoabs[id] = attrval(absid, "val")
				end
			end
		end
	end

	local result = {}
	for numid, absid in pairs(numtoabs) do
		result[numid] = abstract[absid] or {}
	end
	return result
end

-- Decide LB vs LN for a list paragraph. Falls back to a bullet list when the
-- numbering definition is missing or unresolvable.
local function list_style(numbering, numid, ilvl)
	if numbering and numid then
		local lvls = numbering[numid]
		if lvls then
			local fmt = lvls[ilvl or "0"] or lvls["0"]
			if fmt then
				fmt = string_lower(fmt)
				if (fmt == "bullet") or (fmt == "none") then
					return "LB"
				end
				return "LN"
			end
		end
	end
	return "LB"
end

-----------------------------------------------------------------------------
-- Map a Word paragraph style id (w:pStyle/@w:val) to a WordGrinder style.

local function map_style(v)
	if not v then
		return "P"
	end
	local s = string_lower(v):gsub("[%s_%-]", "")

	local h = s:match("^heading(%d+)$")
	if h then
		local n = tonumber(h)
		if n > 4 then n = 4 end
		if n < 1 then n = 1 end
		return "H" .. n
	end

	if s == "title" then
		return "H1"
	elseif s == "subtitle" then
		return "H2"
	elseif string_find(s, "quote") then
		return "Q"
	elseif string_find(s, "listnumber") or string_find(s, "listparanumber") then
		return "LN"
	elseif s == "listparagraph" or string_find(s, "listbullet") then
		return "LB"
	end

	return "P"
end

-- Work out the WordGrinder style for a <w:p>, considering both its named style
-- (<w:pStyle>) and any list membership (<w:numPr>). Headings/quotes win over
-- list membership; otherwise a numbered/bulleted paragraph is resolved via the
-- numbering definitions.
local function paragraph_style(p, numbering)
	local pstyle_val, numid, ilvl, has_numpr

	local pPr = child_named(p, "pPr")
	if pPr then
		for _, pc in ipairs(pPr) do
			if type(pc) == "table" then
				local n = localname(pc)
				if n == "pStyle" then
					pstyle_val = attrval(pc, "val")
				elseif n == "numPr" then
					has_numpr = true
					local numidel = child_named(pc, "numId")
					local ilvlel = child_named(pc, "ilvl")
					if numidel then numid = attrval(numidel, "val") end
					if ilvlel then ilvl = attrval(ilvlel, "val") end
				end
			end
		end
	end

	local mapped = map_style(pstyle_val)

	-- A heading or block quote is a heading/quote even if it also carries list
	-- numbering (e.g. a numbered heading).
	if (mapped == "H1") or (mapped == "H2") or (mapped == "H3")
		or (mapped == "H4") or (mapped == "Q") then
		return mapped
	end

	if has_numpr then
		return list_style(numbering, numid, ilvl)
	end

	return mapped
end

-----------------------------------------------------------------------------
-- Text emission.

-- Emit the text held in a <w:t> element. The XML tokeniser aggressively
-- collapses whitespace, so a space-only run can arrive as an empty element; we
-- detect those via xml:space="preserve" and emit a word break for them.
local function add_text_element(importer, telem, state)
	local buf = {}
	for _, c in ipairs(telem) do
		if type(c) == "string" then
			buf[#buf + 1] = c
		end
	end
	local t = table_concat(buf)

	if t == "" then
		local preserve = telem["xml space"]
			or telem["http://www.w3.org/XML/1998/namespace space"]
		if preserve == "preserve" then
			importer:flushword(false)
		end
		return
	end

	local needsflush = (string_find(t, "^%s") ~= nil)
	for word in string_gmatch(t, "%S+") do
		if needsflush then
			importer:flushword(false)
		end
		importer:text(word)
		state.emitted = true
		needsflush = true
	end
	if string_find(t, "%s$") then
		importer:flushword(false)
	end
end

-- Process a single <w:r> run: apply its character formatting, then emit its
-- text/break children.
local function process_run(importer, r, state)
	local bold, italic, underline = false, false, false

	local rPr = child_named(r, "rPr")
	if rPr then
		for _, pc in ipairs(rPr) do
			if type(pc) == "table" then
				local n = localname(pc)
				if n == "b" then
					bold = istrue(attrval(pc, "val"))
				elseif n == "i" then
					italic = istrue(attrval(pc, "val"))
				elseif n == "u" then
					local v = attrval(pc, "val")
					underline = (v ~= nil) and (string_lower(v) ~= "none")
				end
			end
		end
	end

	if bold then importer:style_on(BOLD) end
	if italic then importer:style_on(ITALIC) end
	if underline then importer:style_on(UNDERLINE) end

	for _, child in ipairs(r) do
		if type(child) == "table" then
			local n = localname(child)
			if n == "t" then
				add_text_element(importer, child, state)
			elseif n == "noBreakHyphen" then
				importer:text("-")
				state.emitted = true
			elseif (n == "br") or (n == "cr") or (n == "tab") then
				importer:flushword(false)
			end
			-- rPr, delText, softHyphen, drawing, etc. are ignored.
		end
	end

	if underline then importer:style_off(UNDERLINE) end
	if italic then importer:style_off(ITALIC) end
	if bold then importer:style_off(BOLD) end
end

-- For <mc:AlternateContent>, a consumer must pick exactly one branch: the first
-- <mc:Choice>, else <mc:Fallback>. Picking both would duplicate the content.
local function alternate_branch(element)
	local fallback
	for _, sub in ipairs(element) do
		if type(sub) == "table" then
			local ln = localname(sub)
			if ln == "Choice" then
				return sub
			elseif (ln == "Fallback") and not fallback then
				fallback = sub
			end
		end
	end
	return fallback
end

-- Walk the contents of a paragraph (or any run container: hyperlinks, content
-- controls, accepted insertions, ...) emitting runs as we find them.
local function process_para_content(importer, node, state)
	for _, child in ipairs(node) do
		if type(child) == "table" then
			local n = localname(child)
			if n == "pPr" then
				-- paragraph properties: handled separately
			elseif n == "r" then
				process_run(importer, child, state)
			elseif (n == "del") or (n == "delText") or (n == "moveFrom") then
				-- tracked deletion / move source: drop it
			elseif (n == "br") or (n == "cr") or (n == "tab") then
				importer:flushword(false)
			elseif n == "AlternateContent" then
				local branch = alternate_branch(child)
				if branch then
					process_para_content(importer, branch, state)
				end
			else
				-- hyperlink, ins, moveTo, smartTag, sdt, sdtContent, fldSimple,
				-- ... Recurse to pick up any runs nested inside.
				process_para_content(importer, child, state)
			end
		end
	end
end

-- Turn one <w:p> into one WordGrinder paragraph, preserving empties.
local function process_paragraph(importer, document, p, numbering)
	local style = paragraph_style(p, numbering)
	local state = { emitted = false }
	process_para_content(importer, p, state)

	if state.emitted then
		importer:flushparagraph(style)
	else
		document:appendParagraph(CreateParagraph(style, {""}))
	end
end

-- Recursively find every <w:p> in document order, descending through tables,
-- content controls, etc., but never into a paragraph itself.
local function walk_body(importer, document, node, numbering)
	for _, child in ipairs(node) do
		if type(child) == "table" then
			local n = localname(child)
			if n == "p" then
				process_paragraph(importer, document, child, numbering)
			elseif n == "sectPr" then
				-- section properties: nothing to import
			elseif n == "AlternateContent" then
				local branch = alternate_branch(child)
				if branch then
					walk_body(importer, document, branch, numbering)
				end
			else
				walk_body(importer, document, child, numbering)
			end
		end
	end
end

-----------------------------------------------------------------------------
-- The command itself.

function Cmd.ImportDOCXFile(filename)
	if not filename then
		filename = FileBrowser("Import Word Document", "Import from:", false)
		if not filename then
			return false
		end
	end

	ImmediateMessage("Importing...")

	-- The body of a .docx lives in word/document.xml inside the zip.

	local contentxml = ReadFromZip(filename, "word/document.xml")
	if not contentxml then
		ModalMessage(nil, "The import failed, probably because the file could "..
			"not be found or is not a valid .docx file.")
		QueueRedraw()
		return false
	end

	local ok, parsed = pcall(ParseXML, contentxml)
	if (not ok) or (type(parsed) ~= "table") or (not parsed._name) then
		ModalMessage(nil, "The import failed, probably because the file is not "..
			"a valid .docx file.")
		QueueRedraw()
		return false
	end
	contentxml = parsed

	-- word/numbering.xml is optional (only present when the document has lists).

	local numbering = {}
	local numxml = ReadFromZip(filename, "word/numbering.xml")
	if numxml then
		local nok, nparsed = pcall(ParseXML, numxml)
		if nok and (type(nparsed) == "table") then
			numbering = build_numbering(nparsed)
		end
	end

	local document = CreateDocument()
	local importer = CreateImporter(document)
	importer:reset()

	walk_body(importer, document, contentxml, numbering)

	-- CreateDocument() seeds a blank paragraph; drop it if we imported anything.

	if (#document > 1) then
		document:deleteParagraphAt(1)
	end

	-- Name the new document after the file (without the .docx extension), making
	-- the name unique within the set if necessary.

	local docname = Leafname(filename):gsub("%.[Dd][Oo][Cc][Xx]?$", "")
	if (docname == "") then
		docname = Leafname(filename)
	end

	if DocumentSet.documents[docname] then
		local id = 1
		while true do
			local f = docname .. "-" .. id
			if not DocumentSet.documents[f] then
				docname = f
				break
			end
			id = id + 1
		end
	end

	DocumentSet:addDocument(document, docname)
	DocumentSet:setCurrent(docname)

	QueueRedraw()
	return true
end
