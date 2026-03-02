-- Statistics addon for WordGrinder
-- Tracks daily word count by computing deltas on each document change.
-- Persists counts to ~/.wordgrinder/wordcount_log.lua

local string_format = string.format
local int = math.floor
local max = math.max
local Write = wg.write
local GetChar = wg.getchar
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetDim = wg.setdim

-----------------------------------------------------------------------------
-- State

local dailyLog = {}          -- { ["2026-03-02"] = 1500, ... }
local previousTotalWords = 0  -- baseline for delta computation
local logDirty = false        -- true if in-memory log differs from disk
local logFilePath = nil       -- set on init to CONFIGDIR.."/wordcount_log.lua"

-----------------------------------------------------------------------------
-- Helpers

local function getToday()
	return os.date("%Y-%m-%d")
end

local function computeTotalWordCount()
	local total = 0
	if not DocumentSet then
		return 0
	end
	local docs = DocumentSet:getDocumentList()
	if not docs then
		return 0
	end
	for _, doc in ipairs(docs) do
		for _, p in ipairs(doc) do
			total = total + #p
		end
	end
	return total
end

local function formatNumber(n)
	if n < 0 then
		return "-" .. formatNumber(-n)
	end
	local s = tostring(n)
	local result = ""
	local len = #s
	for i = 1, len do
		if i > 1 and (len - i + 1) % 3 == 0 then
			result = result .. ","
		end
		result = result .. s:sub(i, i)
	end
	return result
end

-----------------------------------------------------------------------------
-- Log file I/O

local function loadWordCountLog()
	if not logFilePath then
		return {}
	end
	local f = io.open(logFilePath, "r")
	if not f then
		return {}
	end
	local content = f:read("*a")
	f:close()
	if not content or content == "" then
		return {}
	end
	local fn, err = loadstring(content)
	if not fn then
		return {}
	end
	local ok, result = pcall(fn)
	if ok and type(result) == "table" then
		return result
	end
	return {}
end

local function saveWordCountLog()
	if not logFilePath or not logDirty then
		return
	end

	-- Collect and sort dates
	local dates = {}
	for date, _ in pairs(dailyLog) do
		dates[#dates + 1] = date
	end
	table.sort(dates)

	local f = io.open(logFilePath, "w")
	if not f then
		return
	end
	f:write("return {\n")
	for _, date in ipairs(dates) do
		f:write(string_format('  ["%s"] = %d,\n', date, dailyLog[date]))
	end
	f:write("}\n")
	f:close()
	logDirty = false
end

-----------------------------------------------------------------------------
-- Delta tracking

local function onChanged(event, token)
	local currentTotal = computeTotalWordCount()
	local delta = currentTotal - previousTotalWords
	if delta ~= 0 then
		local today = getToday()
		dailyLog[today] = (dailyLog[today] or 0) + delta
		logDirty = true
	end
	previousTotalWords = currentTotal
end

local function resetBaseline(event, token)
	previousTotalWords = computeTotalWordCount()
end

-----------------------------------------------------------------------------
-- Periodic save on idle

local function onIdle(event, token)
	if logDirty then
		saveWordCountLog()
	end
end

-----------------------------------------------------------------------------
-- Full-screen Statistics UI

function Cmd.StatisticsUI()
	-- Save any pending data before displaying
	if logDirty then
		saveWordCountLog()
	end

	-- Gather sorted history (most recent first)
	local dates = {}
	for date, _ in pairs(dailyLog) do
		dates[#dates + 1] = date
	end
	table.sort(dates, function(a, b) return a > b end)

	local scrollOffset = 0

	local function drawScreen()
		ResizeScreen()
		wg.clearscreen()

		local sw, sh = ScreenWidth, ScreenHeight
		local outerW, outerH = sw - 2, sh - 2
		DrawTitledBox(0, 0, outerW, outerH, "Statistics")

		local innerX = 2
		local innerW = sw - 6

		-- Today's word count (prominent display)
		local today = getToday()
		local todayCount = dailyLog[today] or 0

		local headerY = 3
		SetBright()
		CentreInField(innerX, headerY, innerW, "Today's Word Count")
		SetNormal()

		local countY = headerY + 2
		SetBright()
		CentreInField(innerX, countY, innerW, formatNumber(todayCount))
		SetNormal()

		local dateY = countY + 1
		SetDim()
		CentreInField(innerX, dateY, innerW, today)
		SetNormal()

		-- Recent history section
		local historyHeaderY = dateY + 2
		SetBright()
		CentreInField(innerX, historyHeaderY, innerW, "Recent History")
		SetNormal()

		-- Divider line
		local dividerY = historyHeaderY + 1
		local divider = string.rep("─", max(1, innerW))
		SetDim()
		CentreInField(innerX, dividerY, innerW, divider)
		SetNormal()

		-- History list
		local listStartY = dividerY + 1
		local helpRows = 2
		local listEndY = sh - 3 - helpRows
		local visibleRows = listEndY - listStartY
		if visibleRows < 1 then visibleRows = 1 end

		-- Clamp scroll
		local maxScroll = max(0, #dates - visibleRows)
		if scrollOffset > maxScroll then
			scrollOffset = maxScroll
		end
		if scrollOffset < 0 then
			scrollOffset = 0
		end

		for row = 1, visibleRows do
			local idx = scrollOffset + row
			if idx <= #dates then
				local date = dates[idx]
				local count = dailyLog[date]
				local line = string_format("  %s    %s", date, formatNumber(count))
				if date == today then
					SetBright()
				else
					SetNormal()
				end
				LAlignInField(innerX + 2, listStartY + row - 1, innerW - 4, line)
			end
		end
		SetNormal()

		-- Scroll indicator
		if #dates > visibleRows then
			local barH = max(1, int(visibleRows * visibleRows / #dates))
			local barPos = int(scrollOffset * (visibleRows - barH) / maxScroll)
			for row = 0, visibleRows - 1 do
				if row >= barPos and row < barPos + barH then
					Write(innerX + innerW - 1, listStartY + row, "║")
				else
					Write(innerX + innerW - 1, listStartY + row, "│")
				end
			end
		end

		-- Help text
		CentreInField(innerX, sh - 4, innerW, "UP/DOWN: Scroll history")
		CentreInField(innerX, sh - 3, innerW, "RETURN or ^C: Close")

		wg.hidecursor()
		wg.sync()
	end

	while true do
		drawScreen()
		local key = GetChar()

		if (key == "KEY_^C") or (key == "KEY_RETURN") or (key == "KEY_ENTER") or (key == "KEY_ESCAPE") then
			break
		elseif key == "KEY_RESIZE" then
			-- Just redraw on resize
		elseif (key == "KEY_UP") or (key == "KEY_SUP") then
			scrollOffset = max(0, scrollOffset - 1)
		elseif (key == "KEY_DOWN") or (key == "KEY_SDOWN") then
			scrollOffset = scrollOffset + 1
		elseif key == "KEY_PGUP" then
			local sw, sh = ScreenWidth, ScreenHeight
			local pageSize = max(1, sh - 14)
			scrollOffset = max(0, scrollOffset - pageSize)
		elseif key == "KEY_PGDN" then
			local sw, sh = ScreenWidth, ScreenHeight
			local pageSize = max(1, sh - 14)
			scrollOffset = scrollOffset + pageSize
		end
	end

	QueueRedraw()
	return true
end

-----------------------------------------------------------------------------
-- Initialization

do
	local function initCb(event, token)
		logFilePath = CONFIGDIR .. "/wordcount_log.lua"
		dailyLog = loadWordCountLog()
		previousTotalWords = computeTotalWordCount()
	end

	AddEventListener(Event.RegisterAddons, initCb)
	AddEventListener(Event.Changed, onChanged)
	AddEventListener(Event.DocumentLoaded, resetBaseline)
	AddEventListener(Event.DocumentCreated, resetBaseline)
	AddEventListener(Event.Idle, onIdle)
end
