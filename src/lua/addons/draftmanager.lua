--!nonstrict
-- Draft Manager: stores named draft snapshots embedded inside the project file.
-- Drafts are stored in DocumentSet.addons.drafts so they travel with the .wg file.

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
