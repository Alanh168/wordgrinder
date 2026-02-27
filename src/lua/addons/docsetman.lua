-- © 2008 David Given.
-- WordGrinder is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local int = math.floor
local Write = wg.write
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetReverse = wg.setreverse
local SetDim = wg.setdim
local GetBoundedString = wg.getboundedstring
local GetChar = wg.getchar
local HideCursor = wg.hidecursor
local string_rep = string.rep

function Cmd.AddBlankDocument(name)
	if not name then
		name = PromptForString("Name of new document?", "Please enter the new document name:")
		if not name or (name == "") then
			return false
		end
	end

	if DocumentSet.documents[name] then
		ModalMessage("Name in use", "Sorry! There's already a document with that name in this document set.")
		return false
	end

	DocumentSet:addDocument(CreateDocument(), name)
	DocumentSet:setCurrent(name)
	QueueRedraw()
	return true
end

local function countPreviewLines(doc, pw)
	-- Count total wrapped lines in a document for scroll clamping.
	local total = 0
	for pn = 1, #doc do
		local paragraph = doc[pn]
		local lines = paragraph:wrap(pw - 2)
		total = total + #lines

		if pn < #doc then
			local sa = doc:spaceBelow(pn)
			if sa < 1 then
				sa = doc:spaceAbove(pn + 1)
			end
			total = total + sa
		end
	end
	return total
end

local function drawDocManagerPreview(doc, px, py, pw, ph, scrollOffset)
	-- Render lines of a document in the preview area, skipping scrollOffset lines.
	scrollOffset = scrollOffset or 0

	local s = SpellcheckerOff()
	local lineNum = 0  -- absolute line counter (including spacing)
	local y = py
	for pn = 1, #doc do
		if y >= py + ph then
			break
		end

		local paragraph = doc[pn]
		local lines = paragraph:wrap(pw - 2)

		for ln, line in ipairs(lines) do
			if y >= py + ph then
				break
			end

			if lineNum >= scrollOffset then
				local x = paragraph:getIndentOfLine(ln)
				paragraph:renderLine(line, px + x, y)
				y = y + 1
			end
			lineNum = lineNum + 1
		end

		-- Add paragraph spacing
		local sa = 0
		if pn < #doc then
			sa = doc:spaceBelow(pn)
			if sa < 1 then
				sa = doc:spaceAbove(pn + 1)
			end
		end
		for _ = 1, sa do
			if lineNum >= scrollOffset then
				y = y + 1
			end
			lineNum = lineNum + 1
			if y >= py + ph then
				break
			end
		end
	end
	SpellcheckerRestore(s)
end

function Cmd.ManageDocumentsUI()
	local cursor = 1
	local offset = 1
	local previewScroll = 0
	local data = {}

	local function rebuildData()
		data = {}
		local current = nil
		for dn, d in ipairs(DocumentSet:getDocumentList()) do
			data[dn] = {
				document = d,
				label = d.name or "(unnamed)"
			}
			if (d == Document) then
				current = dn
			end
		end
		if current then
			cursor = current
		end
		if cursor > #data then
			cursor = #data
		end
		if cursor < 1 then
			cursor = 1
		end
	end

	local function adjustOffset(listHeight)
		offset = math.min(offset, cursor)
		offset = math.max(offset, cursor - (listHeight - 1))
		offset = math.min(offset, math.max(1, #data - (listHeight - 1)))
		offset = math.max(offset, 1)
	end

	local function switchToSelected()
		if data[cursor] then
			Cmd.ChangeDocument(data[cursor].document.name)
			previewScroll = 0
		end
	end

	local function drawScreen()
		ResizeScreen()
		wg.clearscreen()

		local sw = ScreenWidth
		local sh = ScreenHeight

		-- Outer frame
		SetBright()
		DrawTitledBox(0, 0, sw - 2, sh - 2, "Document Manager")
		SetNormal()

		-- Layout constants
		local innerX = 2
		local innerY = 2
		local innerW = sw - 4
		local innerH = sh - 6  -- leave room for help text at bottom

		local listW = int(innerW / 3)
		local previewX = innerX + listW + 2
		local previewW = innerW - listW - 2

		-- Left panel border (Documents)
		SetBright()
		do
			local border = string_rep("─", listW - 2)
			Write(innerX, innerY, "┌")
			Write(innerX + 1, innerY, border)
			Write(innerX + listW - 1, innerY, "┐")
			for i = 1, innerH - 1 do
				Write(innerX, innerY + i, "│")
				Write(innerX + listW - 1, innerY + i, "│")
			end
			Write(innerX, innerY + innerH, "└")
			Write(innerX + 1, innerY + innerH, border)
			Write(innerX + listW - 1, innerY + innerH, "┘")
		end
		SetNormal()

		-- Right panel border (Preview)
		SetBright()
		do
			local border = string_rep("─", previewW - 2)
			Write(previewX, innerY, "┌")
			Write(previewX + 1, innerY, border)
			Write(previewX + previewW - 1, innerY, "┐")
			for i = 1, innerH - 1 do
				Write(previewX, innerY + i, "│")
				Write(previewX + previewW - 1, innerY + i, "│")
			end
			Write(previewX, innerY + innerH, "└")
			Write(previewX + 1, innerY + innerH, border)
			Write(previewX + previewW - 1, innerY + innerH, "┘")
		end
		SetNormal()

		-- Panel titles
		SetBright()
		CentreInField(innerX + 1, innerY, listW - 2, "Documents")
		CentreInField(previewX + 1, innerY, previewW - 2, "Preview")
		SetNormal()

		-- Draw document list
		local listInnerH = innerH - 1  -- rows available inside the box (excluding top border)
		adjustOffset(listInnerH)

		local space = string_rep(" ", listW - 2)
		for i = 0, listInnerH - 1 do
			local index = offset + i
			local item = data[index]
			if not item then
				break
			end

			local ly = innerY + 1 + i
			if (index == cursor) then
				SetReverse()
			else
				SetNormal()
			end

			Write(innerX + 1, ly, space)
			local label = GetBoundedString(item.label, listW - 4)
			Write(innerX + 2, ly, label)

			-- Scrollbar
			if (#data > listInnerH) then
				SetNormal()
				SetBright()
				local s = "│"
				local yf = (i + 1) * #data / listInnerH
				if (yf >= offset) and (yf <= (offset + listInnerH)) then
					s = "║"
				end
				Write(innerX + listW - 1, ly, s)
			end
			SetNormal()
		end
		SetNormal()

		-- Draw preview
		if data[cursor] then
			local doc = data[cursor].document
			-- Find the document object in the DocumentSet
			local docObj = nil
			for _, d in ipairs(DocumentSet:getDocumentList()) do
				if d == doc then
					docObj = d
					break
				end
			end

			if docObj then
				local prevX = previewX + 2
				local prevY = innerY + 1
				local prevW = previewW - 3
				local prevH = innerH - 1

				SetDim()
				drawDocManagerPreview(docObj, prevX, prevY, prevW, prevH, previewScroll)
				SetNormal()
			end
		end

		-- Help text at bottom
		local helpY = innerY + innerH + 1
		SetNormal()
		CentreInField(innerX, helpY, innerW,
			"U: Move up  D: Move down  R: Rename  X: Delete  N: New")
		CentreInField(innerX, helpY + 1, innerW,
			"SHIFT+UP/DOWN: Scroll preview    RETURN, ^C: Close")

		HideCursor()
		wg.sync()
	end

	-- Callbacks (same logic as before)

	local function up_cb()
		if (cursor > 1) then
			local document = data[cursor].document
			DocumentSet:moveDocumentIndexTo(document.name, cursor - 1)
			cursor = cursor - 1
			rebuildData()
			switchToSelected()
			return true
		end
		return false
	end

	local function down_cb()
		if (cursor < #data) then
			DocumentSet:moveDocumentIndexTo(Document.name, cursor + 1)
			cursor = cursor + 1
			rebuildData()
			switchToSelected()
			return true
		end
		return false
	end

	local function rename_cb()
		local name = PromptForString("Change name of current document",
			"Please enter the new document name:", Document.name)
		if not name or (name == Document.name) then
			return true
		end

		if not DocumentSet:renameDocument(Document.name, name) then
			ModalMessage("Name in use",
				"Sorry! There's already a document with that name in this document set.")
			return true
		end

		rebuildData()
		return true
	end

	local function delete_cb()
		if (#data == 1) then
			ModalMessage("Unable to delete document",
				"You can't delete the last document from the document set.")
			return true
		end

		if not PromptForYesNo("Delete this document?",
			"Are you sure you want to delete the document '"
			.. Document.name .."'? It will be removed from the current document set, and will be gone forever.") then
			return true
		end

		if not DocumentSet:deleteDocument(Document.name) then
			ModalMessage("Unable to delete document", "You can't delete that document.")
			return true
		end

		rebuildData()
		switchToSelected()
		return true
	end

	local function new_cb()
		Cmd.AddBlankDocument()
		rebuildData()
		return true
	end

	-- Main loop
	rebuildData()
	switchToSelected()

	while true do
		drawScreen()

		local key = GetChar()

		if (key == "KEY_RESIZE") then
			-- just redraw on next iteration

		elseif (key == "KEY_^C") or (key == "KEY_RETURN") or (key == "KEY_ENTER") then
			break

		elseif (key == "KEY_UP") then
			if (cursor > 1) then
				cursor = cursor - 1
				switchToSelected()
			end

		elseif (key == "KEY_DOWN") then
			if (cursor < #data) then
				cursor = cursor + 1
				switchToSelected()
			end

		elseif (key == "KEY_SUP") then
			if previewScroll > 0 then
				previewScroll = previewScroll - 1
			end

		elseif (key == "KEY_SDOWN") then
			if data[cursor] then
				local doc = data[cursor].document
				local innerH = ScreenHeight - 6
				local previewW = (ScreenWidth - 4) - int((ScreenWidth - 4) / 3) - 2
				local prevH = innerH - 1
				local totalLines = countPreviewLines(doc, previewW - 3)
				local maxScroll = math.max(0, totalLines - prevH)
				if previewScroll < maxScroll then
					previewScroll = previewScroll + 1
				end
			end

		elseif (key == "KEY_PGUP") then
			local listInnerH = ScreenHeight - 7
			cursor = math.max(1, cursor - int(listInnerH / 2))
			switchToSelected()

		elseif (key == "KEY_PGDN") then
			local listInnerH = ScreenHeight - 7
			cursor = math.min(#data, cursor + int(listInnerH / 2))
			switchToSelected()

		elseif (key == "KEY_HOME") then
			cursor = 1
			switchToSelected()

		elseif (key == "KEY_END") then
			cursor = #data
			switchToSelected()

		elseif (key == "u") or (key == "U") then
			up_cb()

		elseif (key == "d") or (key == "D") then
			down_cb()

		elseif (key == "r") or (key == "R") then
			rename_cb()

		elseif (key == "x") or (key == "X") then
			delete_cb()

		elseif (key == "n") or (key == "N") then
			new_cb()
		end
	end

	QueueRedraw()
	return true
end
