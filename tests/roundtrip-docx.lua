require("tests/testsuite")

-- Build a document exercising every faithfully-round-tripping style: plain
-- paragraphs, bold/italic/underline words, headings, a block quote, a bullet
-- list, a numbered list, and an empty paragraph.

Cmd.InsertStringIntoParagraph("one two three")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("plain")
Cmd.SplitCurrentWord()
Cmd.SetMark()
Cmd.InsertStringIntoParagraph("boldword")
Cmd.SetStyle("b")
Cmd.SetStyle("o")
Cmd.SplitCurrentWord()
Cmd.SetMark()
Cmd.InsertStringIntoParagraph("italicword")
Cmd.SetStyle("i")
Cmd.SetStyle("o")
Cmd.SplitCurrentWord()
Cmd.SetMark()
Cmd.InsertStringIntoParagraph("underword")
Cmd.SetStyle("u")
Cmd.SetStyle("o")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("Heading one")
Cmd.ChangeParagraphStyle("H1")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("Heading two")
Cmd.ChangeParagraphStyle("H2")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("a quote")
Cmd.ChangeParagraphStyle("Q")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("bullet item")
Cmd.ChangeParagraphStyle("LB")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("numbered item")
Cmd.ChangeParagraphStyle("LN")
Cmd.SplitCurrentParagraph()

-- an empty paragraph
Cmd.ChangeParagraphStyle("P")
Cmd.SplitCurrentParagraph()

Cmd.InsertStringIntoParagraph("the end")
Cmd.ChangeParagraphStyle("P")

-- Canonical form of the original document.
local original = Cmd.ExportToDOCXString()

-- Export to a real .docx file, then re-import it.
local tmp = "roundtrip-test.docx"
AssertNotNull(Cmd.ExportDOCXFile(tmp))
AssertNotNull(Cmd.ImportDOCXFile(tmp))
os.remove(tmp)

-- The re-imported document must export to exactly the same OOXML: this proves
-- that export followed by import loses nothing structural.
local roundtripped = Cmd.ExportToDOCXString()
AssertEquals(original, roundtripped)

-- Human-readable dump (only shown when run manually / on failure).
local function dump(doc, label)
	print("---- " .. label .. " (" .. #doc .. " paragraphs) ----")
	for i = 1, #doc do
		local p = doc[i]
		local ws = {}
		for _, w in ipairs(p) do
			local out = {}
			for j = 1, #w do
				local b = string.byte(w, j)
				if (b >= 16) and (b <= 31) then
					out[#out+1] = "<" .. (b - 16) .. ">"
				else
					out[#out+1] = string.sub(w, j, j)
				end
			end
			ws[#ws+1] = "'" .. table.concat(out) .. "'"
		end
		print(string.format("  [%d] %-3s %s", i, p.style, table.concat(ws, " ")))
	end
end
dump(Document, "round-tripped document")
