--!nonstrict
-- Draft Manager: stores named draft snapshots embedded inside the project file.
-- Drafts are stored in DocumentSet.addons.drafts so they travel with the .wg file.

local int = math.floor
local min = math.min
local max = math.max
local Write = wg.write
local GetChar = wg.getchar
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetReverse = wg.setreverse
local SetRed = wg.setred
local GetBoundedString = wg.getboundedstring
local GetStringWidth = wg.getstringwidth
local GetWordText = wg.getwordtext

-- Tracks which draft was last loaded this session (for status bar display).
LastLoadedDraftName = nil

-- Hex encoding so that draft snapshot strings (which are full .wg files) are
-- safe to embed as property values in the outer .wg file's text format.
-- The .wg parser splits on ". key: value" patterns, which would misfire if the
-- raw .wg content were stored directly.
local function hexencode(s)
	return (s:gsub(".", function(c)
		return string.format("%02x", string.byte(c))
	end))
end

local function hexdecode(s)
	return (s:gsub("%x%x", function(h)
		return string.char(tonumber(h, 16))
	end))
end

-- Detect whether a draft's data blob is hex-encoded (new format) or raw (old).
local function decodeData(data)
	if data:match("^[0-9a-f]+$") then
		return hexdecode(data)
	end
	return data  -- legacy raw format
end

-- Initialize the per-document-set drafts table on load.
AddEventListener(Event.RegisterAddons, function()
	DocumentSet.addons.drafts = DocumentSet.addons.drafts or {}
	RebuildDocumentSetsMenu()
end)

AddEventListener(Event.DocumentLoaded, function()
	RebuildDocumentSetsMenu()
end)

AddEventListener(Event.DocumentCreated, function()
	RebuildDocumentSetsMenu()
end)

-- Captures the current document set as a binary string, with the drafts list
-- stripped out to prevent exponential nesting of draft-within-draft data.
local function captureDocumentSetData()
	local savedDrafts = DocumentSet.addons.drafts
	DocumentSet.addons.drafts = nil

	local tmpPath = os.tmpname()
	local ok = SaveToStream(tmpPath, DocumentSet)

	DocumentSet.addons.drafts = savedDrafts

	if not ok then return nil end

	local f = io.open(tmpPath, "rb")
	if not f then os.remove(tmpPath); return nil end
	local data = f:read("*all")
	f:close()
	os.remove(tmpPath)
	return hexencode(data)
end

-- Loads a draft by writing its data to a temp file, then loading normally.
-- Preserves DocumentSet.name and DocumentSet.addons.drafts so the rest of the
-- session is unaffected.
local function loadDraftData(draft)
	local tmpPath = os.tmpname()
	local f = io.open(tmpPath, "wb")
	if not f then
		ModalMessage("Cannot load draft", "Failed to create temporary file.")
		return false
	end
	f:write(decodeData(draft.data))
	f:close()

	local origName    = DocumentSet.name
	local origDrafts  = DocumentSet.addons.drafts
	-- Snapshot recents so the temp-file load doesn't pollute the list.
	local origRecents = {}
	for i, v in ipairs(GlobalSettings.recents or {}) do
		origRecents[i] = v
	end

	-- User already confirmed; bypass the internal "unsaved changes" prompt.
	DocumentSet.changed = false
	local ok = Cmd.LoadDocumentSet(tmpPath)
	os.remove(tmpPath)

	if ok then
		DocumentSet.name          = origName
		DocumentSet.addons.drafts = origDrafts
		LastLoadedDraftName       = draft.name
		GlobalSettings.recents    = origRecents
		SaveGlobalSettings()
		RebuildDocumentSetsMenu()
	end
	return ok
end

-- Globally accessible so menu.lua's RebuildDocumentSetsMenu can call it.
function LoadDraft(draft)
	return loadDraftData(draft)
end

-- Saves the project file with the current drafts list embedded.
-- Only writes if the project already has a file path.
local function persistDrafts()
	if DocumentSet.name then
		Cmd.SaveCurrentDocument()
	end
end

-----------------------------------------------------------------------------
-- Draft Manager UI (Save Set as...)

function Cmd.ManageDraftSetsUI()
	local browser = Form.Browser {
		focusable = true,
		x1 = 1, y1 = 2,
		x2 = -1, y2 = -4,
		changed = function(self)
			return "redraw"
		end
	}

	local function refresh_data()
		local drafts = DocumentSet.addons.drafts or {}
		local data = {}
		for i, draft in ipairs(drafts) do
			data[i] = { draft = draft, label = draft.name or "(unnamed)" }
		end
		data[#data+1] = { label = "--NEW DRAFT--", isNew = true }
		browser.data = data
		browser.cursor = math.max(1, math.min(browser.cursor or 1, #browser.data))
	end

	local function up_cb()
		local drafts = DocumentSet.addons.drafts
		if browser.cursor > 1 and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor-1] = drafts[browser.cursor-1], drafts[browser.cursor]
			browser.cursor = browser.cursor - 1
			persistDrafts()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function down_cb()
		local drafts = DocumentSet.addons.drafts
		if browser.cursor < #drafts and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor+1] = drafts[browser.cursor+1], drafts[browser.cursor]
			browser.cursor = browser.cursor + 1
			persistDrafts()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function rename_cb()
		local draft = DocumentSet.addons.drafts[browser.cursor]
		if not draft then return "confirm" end
		local name = PromptForString("Rename draft", "Enter new name:", draft.name)
		if name and name ~= "" and name ~= draft.name then
			draft.name = name
			persistDrafts()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function delete_cb()
		local drafts = DocumentSet.addons.drafts
		local draft = drafts[browser.cursor]
		if not draft then return "confirm" end
		if not PromptForYesNo("Delete draft?",
			"Remove '" .. (draft.name or "") .. "' from the draft list?") then
			return "confirm"
		end
		table.remove(drafts, browser.cursor)
		persistDrafts()
		RebuildDocumentSetsMenu()
		return "confirm"
	end

	local function save_cb()
		local item = browser.data[browser.cursor]
		if not item then return "confirm" end

		if item.isNew then
			local name = PromptForString("Save current as...", "Enter draft name:", "")
			if not name or name == "" then return "confirm" end

			if not DocumentSet.name then
				ModalMessage("Cannot save draft", "Please save your project first before creating a draft.")
				return "confirm"
			end

			local data = captureDocumentSetData()
			if not data then
				ModalMessage("Cannot save draft", "Failed to capture document state.")
				return "confirm"
			end

			DocumentSet.addons.drafts = DocumentSet.addons.drafts or {}
			table.insert(DocumentSet.addons.drafts, { name = name, data = data })
			persistDrafts()
			RebuildDocumentSetsMenu()
		else
			local draft = item.draft
			if not draft then return "confirm" end

			if not PromptForYesNo("Overwrite draft?",
				"Overwrite '" .. (draft.name or "") .. "' with the current document set?") then
				return "confirm"
			end

			if not DocumentSet.name then
				ModalMessage("Cannot save draft", "Please save your project first before creating a draft.")
				return "confirm"
			end

			local data = captureDocumentSetData()
			if not data then
				ModalMessage("Cannot save draft", "Failed to capture document state.")
				return "confirm"
			end

			draft.data = data
			persistDrafts()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local dialogue = {
		title = "Draft Manager",
		width = Form.Large,
		height = Form.Large,
		stretchy = false,

		["KEY_^C"] = "cancel",
		["KEY_RETURN"] = save_cb,
		["KEY_ENTER"] = save_cb,

		["u"] = up_cb, ["U"] = up_cb,
		["d"] = down_cb, ["D"] = down_cb,
		["r"] = rename_cb, ["R"] = rename_cb,
		["x"] = delete_cb, ["X"] = delete_cb,
		["n"] = save_cb, ["N"] = save_cb,

		Form.Label {
			x1 = 1, y1 = 1,
			x2 = -1, y2 = 1,
			value = "Select document set:"
		},

		Form.Label {
			x1 = 1, y1 = -3,
			x2 = -1, y2 = -3,
			value = "U: Move document set up          R: Rename document set"
		},

		Form.Label {
			x1 = 1, y1 = -2,
			x2 = -1, y2 = -2,
			value = "D: Move document set down        X: Delete document set"
		},

		Form.Label {
			x1 = 1, y1 = -1,
			x2 = -1, y2 = -1,
			value = "N/RETURN: Save current as...     ^C: Close dialogue"
		},

		browser,
	}

	while true do
		refresh_data()
		local result = Form.Run(dialogue, RedrawScreen)
		QueueRedraw()
		if not result then
			return true
		end
	end
end

-----------------------------------------------------------------------------
-- Load Draft UI (Load Set)

function Cmd.LoadDraftSetUI()
	local browser = Form.Browser {
		focusable = true,
		x1 = 1, y1 = 2,
		x2 = -1, y2 = -4,
		changed = function(self)
			return "redraw"
		end
	}

	local function refresh_data()
		local drafts = DocumentSet.addons.drafts or {}
		local data = {}
		for i, draft in ipairs(drafts) do
			data[i] = { draft = draft, label = draft.name or "(unnamed)" }
		end
		if #data == 0 then
			data[1] = { label = "(no drafts saved)", draft = nil }
		end
		browser.data = data
		browser.cursor = math.max(1, math.min(browser.cursor or 1, #browser.data))
	end

	local function up_cb()
		local drafts = DocumentSet.addons.drafts
		if browser.cursor > 1 and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor-1] = drafts[browser.cursor-1], drafts[browser.cursor]
			browser.cursor = browser.cursor - 1
			persistDrafts()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function down_cb()
		local drafts = DocumentSet.addons.drafts
		if browser.cursor < #drafts and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor+1] = drafts[browser.cursor+1], drafts[browser.cursor]
			browser.cursor = browser.cursor + 1
			persistDrafts()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function rename_cb()
		local draft = DocumentSet.addons.drafts[browser.cursor]
		if not draft then return "confirm" end
		local name = PromptForString("Rename draft", "Enter new name:", draft.name)
		if name and name ~= "" and name ~= draft.name then
			draft.name = name
			persistDrafts()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function delete_cb()
		local drafts = DocumentSet.addons.drafts
		local draft = drafts[browser.cursor]
		if not draft then return "confirm" end
		if not PromptForYesNo("Delete draft?",
			"Remove '" .. (draft.name or "") .. "' from the draft list?") then
			return "confirm"
		end
		table.remove(drafts, browser.cursor)
		persistDrafts()
		RebuildDocumentSetsMenu()
		return "confirm"
	end

	local function load_cb()
		local drafts = DocumentSet.addons.drafts or {}
		local draft = drafts[browser.cursor]
		if not draft then return "confirm" end

		-- Warn the user before overriding the current set.
		if not PromptForYesNo("Load draft?",
			"This will permanently override the current document set. Do you still wish to proceed?") then
			-- Offer to save the current set as a draft first.
			if PromptForYesNo("Save current set?",
				"Would you like to cancel and save the current set as a draft first?") then
				local name = PromptForString("Create draft from current set", "Enter draft name:", "")
				if name and name ~= "" and DocumentSet.name then
					local data = captureDocumentSetData()
					if data then
						DocumentSet.addons.drafts = DocumentSet.addons.drafts or {}
						table.insert(DocumentSet.addons.drafts, { name = name, data = data })
						persistDrafts()
						RebuildDocumentSetsMenu()
					end
				end
			end
			return "confirm"
		end

		loadDraftData(draft)
		return "cancel"
	end

	local dialogue = {
		title = "Load Draft",
		width = Form.Large,
		height = Form.Large,
		stretchy = false,

		["KEY_^C"] = "cancel",
		["KEY_RETURN"] = "cancel",
		["KEY_ENTER"] = "cancel",

		["u"] = up_cb, ["U"] = up_cb,
		["d"] = down_cb, ["D"] = down_cb,
		["r"] = rename_cb, ["R"] = rename_cb,
		["x"] = delete_cb, ["X"] = delete_cb,
		["l"] = load_cb, ["L"] = load_cb,

		Form.Label {
			x1 = 1, y1 = 1,
			x2 = -1, y2 = 1,
			value = "Select document set:"
		},

		Form.Label {
			x1 = 1, y1 = -3,
			x2 = -1, y2 = -3,
			value = "U: Move document set up          R: Rename document set"
		},

		Form.Label {
			x1 = 1, y1 = -2,
			x2 = -1, y2 = -2,
			value = "D: Move document set down        X: Delete document set"
		},

		Form.Label {
			x1 = 1, y1 = -1,
			x2 = -1, y2 = -1,
			value = "L: Load selected draft           RETURN, ^C: Close dialogue"
		},

		browser,
	}

	while true do
		refresh_data()
		local result = Form.Run(dialogue, RedrawScreen)
		QueueRedraw()
		if not result then
			return true
		end
	end
end

-----------------------------------------------------------------------------
-- Draft Comparison Viewer (Manage drafts...)

local function loadDraftDocumentSet(draft)
	local tmpPath = os.tmpname()
	local f = io.open(tmpPath, "wb")
	if not f then
		return nil, "Failed to create temporary file."
	end

	f:write(decodeData(draft.data))
	f:close()

	local ds, e = LoadFromStream(tmpPath)
	os.remove(tmpPath)

	if not ds then
		return nil, e or "Failed to load draft data."
	end

	return ds
end

local function drawValueBar(x, y, w, title, value)
	SetBright()
	Write(x, y, "┌" .. string.rep("─", w - 2) .. "┐")
	Write(x, y + 1, "│" .. string.rep(" ", w - 2) .. "│")
	Write(x, y + 2, "└" .. string.rep("─", w - 2) .. "┘")
	CentreInField(x + 1, y, w - 2, title)
	SetNormal()
	CentreInField(x + 1, y + 1, w - 2, GetBoundedString(value or "", w - 2))
end

local function buildPreview(doc, width)
	local preview = { lines = {}, words = {} }
	if not doc then
		return preview
	end

	local globalWord = 0
	width = max(1, width)

	local function pushLine(items)
		preview.lines[#preview.lines + 1] = { items = items or {} }
	end

	for pn = 1, #doc do
		local paragraph = doc[pn]
		local lineItems = {}
		local lineWidth = 0

		for _, w in ipairs(paragraph) do
			local text = GetWordText(w) or w
			globalWord = globalWord + 1
			preview.words[globalWord] = text

			local ww = GetStringWidth(text)
			local needSpace = (#lineItems > 0) and 1 or 0
			if (#lineItems > 0) and ((lineWidth + needSpace + ww) > width) then
				pushLine(lineItems)
				lineItems = {}
				lineWidth = 0
				needSpace = 0
			end

			lineItems[#lineItems + 1] = { text = text, idx = globalWord }
			if #lineItems == 1 then
				lineWidth = ww
			else
				lineWidth = lineWidth + 1 + ww
			end
		end

		pushLine(lineItems)

		if pn < #doc then
			local spacing = doc:spaceBelow(pn)
			if spacing < 1 then
				spacing = doc:spaceAbove(pn + 1)
			end
			for _ = 1, spacing do
				pushLine({})
			end
		end
	end

	return preview
end

-- Split a UTF-8 string into a table of individual codepoint strings.
local function utf8chars(s)
	local chars = {}
	local i = 1
	local len = #s
	while i <= len do
		local b = s:byte(i)
		local clen
		if b < 0x80 then clen = 1
		elseif b < 0xE0 then clen = 2
		elseif b < 0xF0 then clen = 3
		else clen = 4 end
		if i + clen - 1 > len then clen = len - i + 1 end
		chars[#chars + 1] = s:sub(i, i + clen - 1)
		i = i + clen
	end
	return chars
end

local function buildFullCharMask(text)
	local mask = {}
	for i = 1, #utf8chars(text) do
		mask[i] = true
	end
	return mask
end

local function buildTrimmedCharMasks(leftWord, rightWord)
	local leftChars = utf8chars(leftWord)
	local rightChars = utf8chars(rightWord)
	local leftLen = #leftChars
	local rightLen = #rightChars

	local prefix = 0
	while (prefix < leftLen) and (prefix < rightLen)
		and (leftChars[prefix + 1] == rightChars[prefix + 1]) do
		prefix = prefix + 1
	end

	local leftRemain = leftLen - prefix
	local rightRemain = rightLen - prefix
	local suffix = 0
	while (suffix < leftRemain) and (suffix < rightRemain)
		and (leftChars[leftLen - suffix] == rightChars[rightLen - suffix]) do
		suffix = suffix + 1
	end

	local leftMask = {}
	for i = prefix + 1, leftLen - suffix do
		leftMask[i] = true
	end

	local rightMask = {}
	for i = prefix + 1, rightLen - suffix do
		rightMask[i] = true
	end

	return leftMask, rightMask
end

local function buildWordDiffMasks(leftWords, rightWords)
	local leftMasks = {}
	local rightMasks = {}
	local leftCount = #leftWords
	local rightCount = #rightWords

	local dp = {}
	for i = 0, leftCount + 1 do
		dp[i] = {}
	end

	for i = leftCount, 1, -1 do
		for j = rightCount, 1, -1 do
			if leftWords[i] == rightWords[j] then
				dp[i][j] = (dp[i + 1][j + 1] or 0) + 1
			else
				local dropLeft = dp[i + 1][j] or 0
				local dropRight = dp[i][j + 1] or 0
				dp[i][j] = (dropLeft > dropRight) and dropLeft or dropRight
			end
		end
	end

	local function markRun(leftStart, leftFinish, rightStart, rightFinish)
		local leftLen = max(0, leftFinish - leftStart + 1)
		local rightLen = max(0, rightFinish - rightStart + 1)
		local paired = min(leftLen, rightLen)

		for offset = 0, paired - 1 do
			local leftIdx = leftStart + offset
			local rightIdx = rightStart + offset
			local leftMask, rightMask = buildTrimmedCharMasks(leftWords[leftIdx], rightWords[rightIdx])
			if next(leftMask) then
				leftMasks[leftIdx] = leftMask
			end
			if next(rightMask) then
				rightMasks[rightIdx] = rightMask
			end
		end

		for offset = paired, leftLen - 1 do
			local leftIdx = leftStart + offset
			leftMasks[leftIdx] = buildFullCharMask(leftWords[leftIdx])
		end

		for offset = paired, rightLen - 1 do
			local rightIdx = rightStart + offset
			rightMasks[rightIdx] = buildFullCharMask(rightWords[rightIdx])
		end
	end

	local leftRunStart = 1
	local rightRunStart = 1
	local i, j = 1, 1
	while (i <= leftCount) and (j <= rightCount) do
		if leftWords[i] == rightWords[j] then
			markRun(leftRunStart, i - 1, rightRunStart, j - 1)
			i = i + 1
			j = j + 1
			leftRunStart = i
			rightRunStart = j
		else
			local dropLeft = dp[i + 1][j] or 0
			local dropRight = dp[i][j + 1] or 0
			if dropLeft >= dropRight then
				i = i + 1
			else
				j = j + 1
			end
		end
	end

	markRun(leftRunStart, leftCount, rightRunStart, rightCount)
	return leftMasks, rightMasks
end

local function drawPreviewLine(x, y, w, line, wordMasks, mode)
	SetNormal()
	Write(x, y, string.rep(" ", w))

	if not line or not line.items or (#line.items == 0) then
		return
	end

	local cx = x
	for i, item in ipairs(line.items) do
		if i > 1 then
			SetNormal()
			if (cx - x) < w then
				Write(cx, y, " ")
				cx = cx + 1
			end
		end
		if (cx - x) >= w then
			break
		end

		local text = item.text
		local wordIdx = item.idx
		local wordMask = wordMasks and wordMasks[wordIdx]

		if not wordMask then
			-- No diff data; render plain
			SetNormal()
			local segment = GetBoundedString(text, w - (cx - x))
			if #segment > 0 then
				Write(cx, y, segment)
				cx = cx + GetStringWidth(segment)
			end
		else
			-- Render character by character with diff styling (UTF-8 aware)
			local uchars = utf8chars(text)
			for ci = 1, #uchars do
				if (cx - x) >= w then break end
				local ch = uchars[ci]
				local changed = wordMask[ci]

				if not changed then
					SetNormal()
				else
					if mode == "current" then
						SetBright()
						SetReverse()
					else
						SetRed()
					end
				end

				Write(cx, y, ch)
				cx = cx + GetStringWidth(ch)
			end
		end
	end

	SetNormal()
end

function Cmd.ManageDraftComparisonUI()
	local drafts = DocumentSet.addons.drafts or {}
	if #drafts == 0 then
		ModalMessage("No drafts", "There are no saved drafts to compare.")
		return true
	end

	local draftCursor = 1
	local docCursor = 1
	local scrollOffset = 0

	local selectedDraftSet = nil
	local selectedDraftName = nil
	local commonNames = {}
	local leftPreview = { lines = {}, words = {} }
	local rightPreview = { lines = {}, words = {} }
	local leftWordMasks = {}
	local rightWordMasks = {}
	local loadError = nil

	local function clampState(previewHeight)
		if docCursor < 1 then docCursor = 1 end
		if docCursor > #commonNames then docCursor = #commonNames end
		if docCursor < 1 then docCursor = 1 end

			local totalLines = max(#leftPreview.lines, #rightPreview.lines)
			local maxScroll = max(0, totalLines - previewHeight)
			scrollOffset = max(0, min(scrollOffset, maxScroll))
		end

	local function rebuildCommonDocumentNames()
		commonNames = {}
		if not selectedDraftSet then
			return
		end

		local draftByName = {}
		for _, d in ipairs(selectedDraftSet:getDocumentList()) do
			draftByName[d.name] = true
		end

		for _, d in ipairs(DocumentSet:getDocumentList()) do
			if draftByName[d.name] then
				commonNames[#commonNames+1] = d.name
			end
		end
	end

		local function rebuildRows(previewWidth)
			leftPreview = { lines = {}, words = {} }
			rightPreview = { lines = {}, words = {} }
			leftWordMasks = {}
			rightWordMasks = {}

			if (not selectedDraftSet) or (#commonNames == 0) then
				return
			end

		local name = commonNames[docCursor]
		local leftDoc = DocumentSet:findDocument(name)
		local rightDoc = selectedDraftSet:findDocument(name)
			if (not leftDoc) or (not rightDoc) then
				return
			end

			leftPreview = buildPreview(leftDoc, previewWidth)
			rightPreview = buildPreview(rightDoc, previewWidth)
			leftWordMasks, rightWordMasks = buildWordDiffMasks(leftPreview.words, rightPreview.words)
		end

	local function loadSelectedDraft(previewWidth)
			loadError = nil
			selectedDraftSet = nil
			selectedDraftName = nil
			commonNames = {}
			leftPreview = { lines = {}, words = {} }
			rightPreview = { lines = {}, words = {} }
			leftWordMasks = {}
			rightWordMasks = {}

		local draft = drafts[draftCursor]
		if not draft then
			return
		end

		local ds, e = loadDraftDocumentSet(draft)
		if not ds then
			loadError = e
			return
		end

		selectedDraftSet = ds
		selectedDraftName = draft.name or "(unnamed)"

		rebuildCommonDocumentNames()
		if docCursor > #commonNames then
			docCursor = #commonNames
		end
		if docCursor < 1 then
			docCursor = 1
		end
		rebuildRows(previewWidth)
	end

	local function drawScreen()
		ResizeScreen()
		wg.clearscreen()

		local sw, sh = ScreenWidth, ScreenHeight
		local outerW, outerH = sw - 2, sh - 2
		DrawTitledBox(0, 0, outerW, outerH, "Draft Manager")

		local innerX = 2
		local innerY = 2
		local innerW = sw - 4
		local helpRows = 2
		local topBarsH = 6
		local gap = 2
		local previewTop = innerY + topBarsH
		local previewH = (sh - 6) - topBarsH - helpRows
		if previewH < 4 then previewH = 4 end

		local previewW = int((innerW - gap) / 2)
		local leftX = innerX
		local rightX = innerX + previewW + gap
		local textW = previewW - 2
		if textW < 1 then textW = 1 end

		drawValueBar(innerX, innerY, innerW, "Draft", selectedDraftName or "(none)")
		-- Draw left/right arrows for Draft bar
		SetNormal()
		if draftCursor > 1 then
			Write(innerX + innerW - 4, innerY + 1, "<")
		end
		if draftCursor < #drafts then
			Write(innerX + innerW - 2, innerY + 1, ">")
		end

		local docName = commonNames[docCursor] or "(no shared documents)"
		drawValueBar(innerX, innerY + 3, innerW, "Document", docName)
		-- Draw up/down arrows for Document bar
		SetNormal()
		if docCursor > 1 then
			Write(innerX + innerW - 4, innerY + 4, "^")
		end
		if docCursor < #commonNames then
			Write(innerX + innerW - 2, innerY + 4, "v")
		end

		SetBright()
		DrawTitledBox(leftX, previewTop, previewW, previewH, "Current")
		DrawTitledBox(rightX, previewTop, previewW, previewH, selectedDraftName or "Draft")
		SetNormal()

		local previewInnerY = previewTop + 1
		local previewInnerH = previewH

		clampState(previewInnerH)

		if loadError then
			CentreInField(innerX, previewInnerY + int(previewInnerH / 2), innerW, "Unable to load draft: " .. loadError)
		elseif #commonNames == 0 then
			local msg = "No documents with matching names between Current Project and '" ..
				(selectedDraftName or "(unknown)") .. "'."
			CentreInField(innerX, previewInnerY + int(previewInnerH / 2), innerW, GetBoundedString(msg, innerW))
			else
				for row = 1, previewInnerH do
					local idx = scrollOffset + row
					local leftLine = leftPreview.lines[idx]
					local rightLine = rightPreview.lines[idx]
					drawPreviewLine(leftX + 1, previewInnerY + row - 1, textW, leftLine, leftWordMasks, "current")
					drawPreviewLine(rightX + 1, previewInnerY + row - 1, textW, rightLine, rightWordMasks, "draft")
				end
			end

		CentreInField(innerX, sh - 4, innerW,
			"LEFT/RIGHT: Draft    UP/DOWN: Document    SHIFT+UP/DOWN: Scroll")
		CentreInField(innerX, sh - 3, innerW, "RETURN or ^C: Close")
		wg.hidecursor()
		wg.sync()
	end

	local function refreshForDraftSelection()
		local previewWidth = max(1, int((ScreenWidth - 4 - 2) / 2) - 2)
		loadSelectedDraft(previewWidth)
		scrollOffset = 0
	end

	local function refreshForDocumentSelection()
		local previewWidth = max(1, int((ScreenWidth - 4 - 2) / 2) - 2)
		rebuildRows(previewWidth)
		scrollOffset = 0
	end

	refreshForDraftSelection()

	while true do
		drawScreen()
		local key = GetChar()

		if (key == "KEY_^C") or (key == "KEY_RETURN") or (key == "KEY_ENTER") then
			break
		elseif key == "KEY_RESIZE" then
			refreshForDocumentSelection()
		elseif key == "KEY_LEFT" then
			if draftCursor > 1 then
				draftCursor = draftCursor - 1
				refreshForDraftSelection()
			end
		elseif key == "KEY_RIGHT" then
			if draftCursor < #drafts then
				draftCursor = draftCursor + 1
				refreshForDraftSelection()
			end
		elseif key == "KEY_UP" then
			if docCursor > 1 then
				docCursor = docCursor - 1
				refreshForDocumentSelection()
			end
		elseif key == "KEY_DOWN" then
			if docCursor < #commonNames then
				docCursor = docCursor + 1
				refreshForDocumentSelection()
			end
		elseif key == "KEY_SUP" then
			scrollOffset = max(0, scrollOffset - 1)
		elseif key == "KEY_SDOWN" then
			scrollOffset = scrollOffset + 1
		elseif key == "KEY_PGUP" then
			scrollOffset = max(0, scrollOffset - int((ScreenHeight - 12) / 2))
		elseif key == "KEY_PGDN" then
			scrollOffset = scrollOffset + int((ScreenHeight - 12) / 2)
		end
	end

	QueueRedraw()
	return true
end
