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
local SetReverse = wg.setreverse
local SetColor = wg.setcolor
local GetWordText = wg.getwordtext

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

local function countCommentMarkers(text)
	local count = 0
	local i = 1
	while true do
		i = text:find("%+%+", i)
		if not i then
			return count
		end
		count = count + 1
		i = i + 2
	end
end

local function countNonCommentWords(paragraph)
	local count = 0
	local in_comment = false
	for _, word in ipairs(paragraph) do
		local text = GetWordText(word)
		local markers = countCommentMarkers(text)
		local is_comment = in_comment or (markers > 0)
		if not is_comment then
			count = count + 1
		end
		if (markers % 2) == 1 then
			in_comment = not in_comment
		end
	end
	return count
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
			total = total + countNonCommentWords(p)
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
-- Big number rendering for Statistics UI

local BIG_DIGIT_HEIGHT = 7

local bigDigits = {
	["0"] = {
		" ██████ ",
		"██    ██",
		"██    ██",
		"██    ██",
		"██    ██",
		"██    ██",
		" ██████ ",
	},
	["1"] = {
		"   ██   ",
		"  ███   ",
		"   ██   ",
		"   ██   ",
		"   ██   ",
		"   ██   ",
		" ██████ ",
	},
	["2"] = {
		" ██████ ",
		"██    ██",
		"      ██",
		" ██████ ",
		"██      ",
		"██      ",
		"████████",
	},
	["3"] = {
		" ██████ ",
		"██    ██",
		"      ██",
		"  █████ ",
		"      ██",
		"██    ██",
		" ██████ ",
	},
	["4"] = {
		"██    ██",
		"██    ██",
		"██    ██",
		"████████",
		"      ██",
		"      ██",
		"      ██",
	},
	["5"] = {
		"████████",
		"██      ",
		"██      ",
		"███████ ",
		"      ██",
		"██    ██",
		" ██████ ",
	},
	["6"] = {
		" ██████ ",
		"██      ",
		"██      ",
		"███████ ",
		"██    ██",
		"██    ██",
		" ██████ ",
	},
	["7"] = {
		"████████",
		"      ██",
		"     ██ ",
		"    ██  ",
		"   ██   ",
		"  ██    ",
		"  ██    ",
	},
	["8"] = {
		" ██████ ",
		"██    ██",
		"██    ██",
		" ██████ ",
		"██    ██",
		"██    ██",
		" ██████ ",
	},
	["9"] = {
		" ██████ ",
		"██    ██",
		"██    ██",
		" ███████",
		"      ██",
		"      ██",
		" ██████ ",
	},
	[","] = {
		"    ",
		"    ",
		"    ",
		"    ",
		"    ",
		" ██ ",
		"██  ",
	},
	["-"] = {
		"        ",
		"        ",
		"        ",
		" ██████ ",
		"        ",
		"        ",
		"        ",
	},
}

local function utf8len(s)
	local len = 0
	local i = 1
	while i <= #s do
		local b = s:byte(i)
		if b < 128 then
			i = i + 1
		elseif b < 224 then
			i = i + 2
		elseif b < 240 then
			i = i + 3
		else
			i = i + 4
		end
		len = len + 1
	end
	return len
end

local function renderBigNumber(numStr)
	local lines = {}
	for row = 1, BIG_DIGIT_HEIGHT do
		lines[row] = ""
	end
	for i = 1, #numStr do
		local ch = numStr:sub(i, i)
		local glyph = bigDigits[ch]
		if glyph then
			for row = 1, BIG_DIGIT_HEIGHT do
				if lines[row] ~= "" then
					lines[row] = lines[row] .. " "
				end
				lines[row] = lines[row] .. glyph[row]
			end
		end
	end
	return lines
end

-----------------------------------------------------------------------------
-- Color-attribute sprite rendering
--
-- Every visible pixel is drawn as a solid terminal cell background color.
-- We set REVERSE and draw a space to fill the entire cell height, which also
-- fills cool-retro-term line-spacing gaps between rows.
-- CRT's shader detects chromatic colors (saturation > 0.2) and passes them
-- through as actual colors. Achromatic colors (white/grey) are converted to
-- the terminal's green fontColor as usual.
--
-- 256-color palette (accurate sprite colors):
--   O = Orange      (index 208, #ff8700) → main body
--   D = Dark orange (index 130, #af5f00) → darker body areas
--   B = Beige       (index 223, #ffd7af) → claws/skin
--
-- Standard colors (used in other sprites / UI):
--   R = Red, Y = Yellow, C = Cyan, M = Magenta, U = blUe, W = White
--
--   . = empty   (transparent, draws nothing)
-- cool-retro-term applies post-processing (tint/chroma/bloom/rgb-shift), so
-- some source palette colors do not survive as expected. To keep regular text
-- coloring unchanged, we only remap sprite colors here.
-- Override with WG_SPRITE_COLOR_PROFILE=default for the original palette.

local BLOCK = " "
local spriteColorProfile = (os.getenv("WG_SPRITE_COLOR_PROFILE") or "crt"):lower()
local useCrtSpriteCompensation = (spriteColorProfile ~= "default")

local function setPixelAttr(ch)
	-- Clear all attributes first (BRIGHT/DIM/BOLD from previous draws persist
	-- via dpy_setattr's OR mask, turning every color into bold-yellow)
	SetNormal()
	if ch == "R" then
		SetColor("red")
	elseif ch == "Y" then
		SetColor("yellow")
	elseif ch == "C" then
		SetColor("cyan")
	elseif ch == "U" then
		SetColor("blue")
	elseif ch == "M" then
		SetColor("magenta")
	elseif ch == "W" then
		SetColor("white")
	elseif ch == "O" then
		-- CRT compensation: darker source to land closer to orange on-screen.
		if useCrtSpriteCompensation then
			SetColor("darkorange")
		else
			SetColor("orange")
		end
	elseif ch == "D" then
		-- CRT compensation: less-dark source to avoid turning pure red.
		if useCrtSpriteCompensation then
			SetColor("orange")
		else
			SetColor("darkorange")
		end
	elseif ch == "B" then
		-- CRT compensation: beige often collapses toward green tint.
		if useCrtSpriteCompensation then
			SetColor("yellow")
		else
			SetColor("beige")
		end
	end
	SetReverse()
end

local function renderSpriteRow(x, y, encoded)
	local col = 0
	for i = 1, #encoded do
		local ch = encoded:sub(i, i)
		if ch ~= "." then
			setPixelAttr(ch)
			Write(x + col, y, BLOCK)
		end
		col = col + 1
	end
end

-----------------------------------------------------------------------------
-- Character evolution sprites
-- Each stage has:
--   sprite       = full-size sprite (1 pixel = 1 char cell, color-encoded)
--   sprite_small = compact version for tight screens
--
-- Color encoding:
--   O = Orange (256-color 208) — main body
--   D = Dark orange (256-color 130) — darker body, outline details
--   B = Beige (256-color 223) — claws, teeth, skin
--   R/Y/C = Red/Yellow/Cyan — used in evolution sprites
--   . = empty (black outline / transparent — bg is already black)
--
-- Enable "Color Conversion" in CRT View menu to see actual colors.

local evolutionStages = {
	{
		-- Agumon sprite (from orange pixel art reference)
		-- Pixel-accurate mapping from 15×14 reference:
		--   Black outline/eyes → . (empty, CRT bg is black)
		--   Dark orange body   → D (256-color 130)
		--   Orange body        → O (256-color 208)
		--   Beige/skin claws   → B (256-color 223)
		threshold = 0,
		sprite = {
			"..........DDOO.",
			".....DDDDOOOO..",
			"....DD.DDOOO...",
			"..BBBB..DDO....",
			".DBBBBB..DOOO..",
			"....DOOOOOOOOOO",
			"..OOOOOOOOOOOO.",
			".....DDOOOOO...",
			"....OOOOOOOOO..",
			"...B.OOO.BOOO..",
			"....DOOO..DO...",
			".....OOOOO.....",
			"...OO..........",
			"..B.B..B.B.B...",
		},
		sprite_small = {
			".....DDDDOOOO.",
			"..BBBB.DDOOO..",
			".DBBBBB..DOOO.",
			"..OOOOOOOOOOOO.",
			"...B.OOO.BOOO.",
			".....OOOOO.....",
			"..B.B..B.B.B...",
		},
	},
	{
		threshold = 500,
		sprite = {
			"..YYYYYYYY..",
			".YRRCCCCRRRY.",
			".YRR.YY.RRY.",
			"..YRCCCCY...",
			"Y.YRRRRRRRY.",
			"YRYRRCCRRRY.Y",
			".Y.RRRRRR.Y.",
			"..YRRCCRRRY..",
			"...YRRRRY...",
			"...YRCCRY...",
			"..YRC..CRY..",
			"..YCR..RCY..",
			"..YY....YY..",
		},
		sprite_small = {
			"..YYYYYYYY..",
			".YRR.YY.RRY.",
			"Y.YRRRRRRY..",
			".Y.RRRRRR.Y.",
			"...YRRRRY...",
			"..YRC..CRY..",
			"..YY....YY..",
		},
	},
	{
		threshold = 1000,
		sprite = {
			"...YYYYYYYY...",
			"..YCCRRRRCCCY..",
			"..YCR.YY.RCY..",
			"..YCRRCCRCCY..",
			".YYRRRRRRRRYY.",
			"Y.YRRRRRRRRY.Y",
			"YRYRRRCCRRRYRRR",
			".Y.RRRRRRRR.Y.",
			"...YRRRRRRYR..",
			"....YRRRRY....",
			"...YRRCCRRRY...",
			"...YRC..CRY...",
			"..YYCR..RCYY..",
			"..YY......YY..",
		},
		sprite_small = {
			"..YYYYYYYYYY..",
			"..YCR.YY.RCY..",
			".YYRRRRRRRRYY.",
			"YRYRRRCCRRRYRRR",
			"...YRRRRRRYR..",
			"...YRRCCRRRY...",
			"..YYCR..RCYY..",
			"..YY......YY..",
		},
	},
	{
		threshold = 2000,
		sprite = {
			"....YYYYYYYY....",
			"...YRRCCCCRRRY...",
			"...YRC.YY.CRY...",
			"...YRRCCCCRRRY...",
			"..YYRRRRRRRRYY..",
			"Y..YRRRRRRRRY..Y",
			"YR.YRRCCCCRRRY.RY",
			".Y.YRRRRRRRR.Y.",
			"...YRRRRRRRRY...",
			"....YRRRRRRYR...",
			"....YRRCCRRRY....",
			"...YRC....CRY...",
			"...YCR....RCY...",
			"...YY......YY...",
		},
		sprite_small = {
			"...YYYYYYYYYY...",
			"...YRC.YY.CRY...",
			"..YYRRRRRRRRYY..",
			"YR.YRRCCCCRRRY.RY",
			"...YRRRRRRRRY...",
			"....YRRCCRRRY....",
			"...YCR....RCY...",
			"...YY......YY...",
		},
	},
}

local function getEvolutionSprite(wordCount, availableHeight)
	local stage = evolutionStages[1]
	for _, s in ipairs(evolutionStages) do
		if wordCount >= s.threshold then
			stage = s
		end
	end
	-- Pick small sprite if not enough vertical space for the full one
	if availableHeight and stage.sprite_small then
		local fullHeight = #stage.sprite
		if fullHeight > availableHeight and #stage.sprite_small <= availableHeight then
			return stage.sprite_small
		end
	end
	return stage.sprite
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
		dailyLog[today] = max(0, (dailyLog[today] or 0) + delta)
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

		-- Draw top and bottom borders only (no side borders)
		SetBright()
		local hborder = string.rep("─", sw)
		Write(0, 0, hborder)
		CentreInField(0, 0, sw, " Statistics ")
		Write(0, sh - 1, hborder)
		SetNormal()

		local innerX = 1
		local innerW = sw - 2

		-- Today's word count (prominent display)
		local today = getToday()
		local todayCount = dailyLog[today] or 0

		-- Recent history starts at 80% of screen height
		local historyHeaderY = int(sh * 0.8)
		if historyHeaderY > sh - 7 then
			historyHeaderY = sh - 7
		end

		local headerY = 2
		SetBright()
		CentreInField(innerX, headerY, innerW, "Today's Word Count")
		SetNormal()

		-- Render big number near the top
		local bigLines = renderBigNumber(formatNumber(todayCount))
		local countY = headerY + 2
		SetBright()
		local visualWidth = utf8len(bigLines[1] or "")
		if visualWidth > innerW then
			-- Fallback to single-line if terminal too narrow
			CentreInField(innerX, countY + 3, innerW, formatNumber(todayCount))
		else
			local bigX = innerX + int((innerW - visualWidth) / 2)
			for i, line in ipairs(bigLines) do
				Write(bigX, countY + i - 1, line)
			end
		end
		SetNormal()

		-- Character evolution sprite
		local spriteTop = countY + BIG_DIGIT_HEIGHT + 1
		local spriteBottom = historyHeaderY - 1
		local availableHeight = spriteBottom - spriteTop
		local sprite = getEvolutionSprite(todayCount, availableHeight)
		local spriteHeight = #sprite
		local spriteY = spriteTop + int((spriteBottom - spriteTop - spriteHeight) / 2)
		if spriteY < spriteTop then spriteY = spriteTop end
		local spriteWidth = #(sprite[1] or "")
		local spriteX = innerX + int((innerW - spriteWidth) / 2)
		for i, line in ipairs(sprite) do
			if spriteY + i - 1 < historyHeaderY then
				renderSpriteRow(spriteX, spriteY + i - 1, line)
			end
		end
		SetNormal()

		-- Recent history section
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
