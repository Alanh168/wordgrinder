--!nonstrict
-- Draft Manager: stores and manages named drafts (copies of the current document set).

-- Tracks which draft was last loaded this session (for status bar display).
LastLoadedDraftName = nil

-- Initialize GlobalSettings storage for drafts.
AddEventListener(Event.RegisterAddons, function()
	GlobalSettings.drafts = GlobalSettings.drafts or {}
	RebuildDocumentSetsMenu()
end)

-- Rebuild the menu whenever a document set is loaded or created.
AddEventListener(Event.DocumentLoaded, function()
	RebuildDocumentSetsMenu()
end)

AddEventListener(Event.DocumentCreated, function()
	RebuildDocumentSetsMenu()
end)

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
		local drafts = GlobalSettings.drafts or {}
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
		local drafts = GlobalSettings.drafts
		if browser.cursor > 1 and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor-1] = drafts[browser.cursor-1], drafts[browser.cursor]
			browser.cursor = browser.cursor - 1
			SaveGlobalSettings()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function down_cb()
		local drafts = GlobalSettings.drafts
		if browser.cursor < #drafts and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor+1] = drafts[browser.cursor+1], drafts[browser.cursor]
			browser.cursor = browser.cursor + 1
			SaveGlobalSettings()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function rename_cb()
		local draft = GlobalSettings.drafts[browser.cursor]
		if not draft then return "confirm" end
		local name = PromptForString("Rename document set", "Enter new name:", draft.name)
		if name and name ~= "" and name ~= draft.name then
			draft.name = name
			SaveGlobalSettings()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function delete_cb()
		local drafts = GlobalSettings.drafts
		local draft = drafts[browser.cursor]
		if not draft then return "confirm" end
		if not PromptForYesNo("Delete document set?",
			"Remove '" .. (draft.name or "") .. "' from the draft list? The file will not be deleted.") then
			return "confirm"
		end
		table.remove(drafts, browser.cursor)
		SaveGlobalSettings()
		RebuildDocumentSetsMenu()
		return "confirm"
	end

	local function new_cb()
		local name = PromptForString("Create draft from current set", "Enter draft name:", "")
		if not name or name == "" then return "confirm" end

		if not DocumentSet.name then
			ModalMessage("Cannot create draft", "Please save your project first before creating a draft.")
			return "confirm"
		end

		-- Save current file first so the draft is up to date.
		Cmd.SaveCurrentDocument()

		-- Determine new path in the same directory as the current file.
		local dir = DocumentSet.name:match("^(.*)/[^/]*$") or "."
		local newPath = dir .. "/" .. name .. ".wg"

		-- Save a copy to the new path, then restore the original name.
		local origName = DocumentSet.name
		Cmd.SaveCurrentDocumentAs(newPath)
		DocumentSet.name = origName

		-- Register the draft.
		table.insert(GlobalSettings.drafts, { name = name, path = newPath })
		SaveGlobalSettings()
		RebuildDocumentSetsMenu()
		return "confirm"
	end

	local dialogue = {
		title = "Draft Manager",
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
		["n"] = new_cb, ["N"] = new_cb,

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
			value = "N: Create draft from current set RETURN, ^C: Close dialogue"
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
		local drafts = GlobalSettings.drafts or {}
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
		local drafts = GlobalSettings.drafts
		if browser.cursor > 1 and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor-1] = drafts[browser.cursor-1], drafts[browser.cursor]
			browser.cursor = browser.cursor - 1
			SaveGlobalSettings()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function down_cb()
		local drafts = GlobalSettings.drafts
		if browser.cursor < #drafts and drafts[browser.cursor] then
			drafts[browser.cursor], drafts[browser.cursor+1] = drafts[browser.cursor+1], drafts[browser.cursor]
			browser.cursor = browser.cursor + 1
			SaveGlobalSettings()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function rename_cb()
		local draft = GlobalSettings.drafts[browser.cursor]
		if not draft then return "confirm" end
		local name = PromptForString("Rename document set", "Enter new name:", draft.name)
		if name and name ~= "" and name ~= draft.name then
			draft.name = name
			SaveGlobalSettings()
			RebuildDocumentSetsMenu()
		end
		return "confirm"
	end

	local function delete_cb()
		local drafts = GlobalSettings.drafts
		local draft = drafts[browser.cursor]
		if not draft then return "confirm" end
		if not PromptForYesNo("Delete document set?",
			"Remove '" .. (draft.name or "") .. "' from the draft list? The file will not be deleted.") then
			return "confirm"
		end
		table.remove(drafts, browser.cursor)
		SaveGlobalSettings()
		RebuildDocumentSetsMenu()
		return "confirm"
	end

	local function load_cb()
		local draft = GlobalSettings.drafts[browser.cursor]
		if not draft then return "confirm" end

		-- Warn the user before overriding the current set.
		if not PromptForYesNo("Load draft?",
			"This will permanently override the current document set. Do you still wish to proceed?") then
			-- Offer to save the current set as a draft first.
			if PromptForYesNo("Save current set?",
				"Would you like to cancel and save the current set as a draft first?") then
				local name = PromptForString("Create draft from current set", "Enter draft name:", "")
				if name and name ~= "" and DocumentSet.name then
					Cmd.SaveCurrentDocument()
					local dir = DocumentSet.name:match("^(.*)/[^/]*$") or "."
					local newPath = dir .. "/" .. name .. ".wg"
					local origName = DocumentSet.name
					Cmd.SaveCurrentDocumentAs(newPath)
					DocumentSet.name = origName
					table.insert(GlobalSettings.drafts, { name = name, path = newPath })
					SaveGlobalSettings()
					RebuildDocumentSetsMenu()
				end
			end
			return "confirm"
		end

		-- Load the draft content but keep the current file as the save target.
		local origName = DocumentSet.name
		if Cmd.LoadDocumentSet(draft.path) then
			DocumentSet.name = origName
			LastLoadedDraftName = draft.name
		end
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
