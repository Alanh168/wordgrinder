#!/usr/bin/env -S wordgrinder --lua

-- © 2020 David Given.
-- WordGrinder is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

-- This user script will concatenate all subdocuments in a file into a single one.
--
-- To use:
--
--     wordgrinder --lua concatandexport.lua mynovel.wg output.wg
--
-- (Note the quoting.)
--
-- If mynovel.wg contains subdocuments called Foo, Bar and Baz, this will
-- create a single file called output.wg with the contents of all the
-- subdocuments moved into a new subdocument called 'all'.

-- Main program

local function main(inputfile, outputfile)
	if not outputfile or not inputfile then
		print("Syntax: wordgrinder --lua concat.lua <inputfile.wg> <outputfile.wg>")
		os.exit(1)
	end

	print("Loading "..inputfile)
    if not Cmd.LoadDocumentSet(inputfile) then
        print("failed to load document")
        os.exit(1)
    end

	if DocumentSet:findDocument("all") then
		print("The input file already has a subdocument called 'all'.")
		os.exit(1)
	end

	print(outputfile)
	local outputfilenew = ""
	local docs = { unpack(DocumentSet:getDocumentList()) }
	local allDoc = DocumentSet:addDocument(CreateDocument(), "all")
	local style = "";
    for _, doc in ipairs(docs) do
		for _, p in ipairs(doc) do
			allDoc[#allDoc+1] = p
			style = p.style
		end
		allDoc[#allDoc+1] = CreateParagraph(style, "----")
		DocumentSet:deleteDocument(doc.name)
    end
	print(outputfilenew)

	print("Beginning export...")
    local export_table =
    {
        ["wg"] = Cmd.SaveCurrentDocumentAs,
        ["odt"] = Cmd.ExportODTFile,
        ["html"] = Cmd.ExportHTMLFile,
        ["tr"] = Cmd.ExportTroffFile,
        ["tex"] = Cmd.ExportLatexFile, 
        ["txt"] = Cmd.ExportTextFile,
		["md"] = Cmd.ExportMarkdownFile,
    }
    local _, _, extension = outputfile:find("%.(%w+)$")
    local exporter = export_table[extension or ""]

    if not exporter then
        print("Unknown output format")
        os.exit(1)
    end
	print("Exporting to: "..outputfile)

	if not exporter(outputfile) then
		print("failed to write output file")
		os.exit(1)
	end
end

main(...)
os.exit(0)

