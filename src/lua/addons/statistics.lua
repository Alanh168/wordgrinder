-- Statistics addon for WordGrinder
-- Tracks daily word count by computing deltas on each document change.
-- Persists counts to ~/.wordgrinder/wordcount_log.lua

local string_format = string.format
local int = math.floor
local min = math.min
local max = math.max
local Write = wg.write
local GetChar = wg.getchar
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetDim = wg.setdim
local SetReverse = wg.setreverse
local SetColor = wg.setcolor
local GetWordText = wg.getwordtext
local GetBoundedString = wg.getboundedstring
local GetCwd = wg.getcwd or function() return nil end

-----------------------------------------------------------------------------
-- State

local dailyLog = {}          -- { ["2026-03-02"] = 1500, ... }
local previousTotalWords = 0  -- baseline for delta computation
local logDirty = false        -- true if in-memory log differs from disk
local logFilePath = nil       -- set on init to CONFIGDIR.."/wordcount_log.lua"

-- Monster defeat log: { ["2026-03-02"] = { {name="Agumon", time="14:30"}, ... }, ... }
local defeatLog = {}
local defeatLogDirty = false
local defeatLogFilePath = nil  -- set on init to CONFIGDIR.."/monster_defeat_log.lua"

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
	-- When CountParagraphWords exists, it already implements the desired behavior
	-- for comment markers ("++") and bracketed text ("[..."]). Keep the logic
	-- in sync by forwarding through it when available.
	if type(CountParagraphWords) == "function" then
		return CountParagraphWords(paragraph)
	end

	local count = 0
	local in_comment = false
	for _, word in ipairs(paragraph) do
		local text = GetWordText(word)
		local hasVisibleText = (text ~= "")
		local markers = countCommentMarkers(text)
		local is_comment = in_comment or (markers > 0)
		if hasVisibleText and not is_comment then
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

-- Public API for tests and plugins
function GetDailyWordCount(date)
	date = date or getToday()
	return dailyLog[date] or 0
end

function GetDocumentSetWordCount()
	return computeTotalWordCount()
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
-- Palette sprite rendering

local BLOCK = " "
local DEFAULT_SPRITE_PIXEL_WIDTH = 2
local SetColorIndex = wg.setcolorindex

local function loadFormattedSprites()
	local paths = {}
	local seen = {}
	local function addPath(path)
		if type(path) == "string" and path ~= "" and not seen[path] then
			seen[path] = true
			paths[#paths + 1] = path
		end
	end

	local envPath = os.getenv("WG_FORMATTED_SPRITES")
	addPath(envPath)
	addPath(CONFIGDIR and (CONFIGDIR .. "/formatted_sprites.lua"))
	addPath(CONFIGDIR and (CONFIGDIR .. "/sprites/formatted_sprites.lua"))
	addPath("extras/sprites/formatted_sprites.lua")
	addPath("wordgrinder/extras/sprites/formatted_sprites.lua")

	if debug and debug.getinfo then
		local info = debug.getinfo(1, "S")
		if info and type(info.source) == "string" and info.source:sub(1, 1) == "@" then
			local scriptPath = info.source:sub(2)
			local scriptDir = scriptPath:match("^(.*)[/\\][^/\\]+$")
			addPath(scriptDir and (scriptDir .. "/../../../extras/sprites/formatted_sprites.lua"))
		end
	end

	local cwd = GetCwd()
	addPath(cwd and (cwd .. "/extras/sprites/formatted_sprites.lua"))
	addPath(cwd and (cwd .. "/wordgrinder/extras/sprites/formatted_sprites.lua"))

	for _, path in ipairs(paths) do
		local loader = loadfile(path)
		if loader then
			local ok, sprites = pcall(loader)
			if ok and type(sprites) == "table" then
				return sprites
			end
		end
	end
	return {}
end

local formattedSprites = loadFormattedSprites()


local function getSpriteDefinition(spriteKey)
	if type(formattedSprites[spriteKey]) ~= "table" then
		-- Retry in case the sprite table was generated after startup.
		formattedSprites = loadFormattedSprites()
	end
	local def = formattedSprites[spriteKey]
	if type(def) ~= "table" then
		return nil
	end
	local palette = def.color_palette or def.palette
	if type(def.sprite) ~= "table" or type(palette) ~= "table" then
		return nil
	end
	return def
end

local function getSpriteSize(spriteRows, pixelWidth)
	pixelWidth = pixelWidth or DEFAULT_SPRITE_PIXEL_WIDTH
	local width = 0
	for _, row in ipairs(spriteRows) do
		if type(row) == "table" and #row > width then
			width = #row
		end
	end
	return width * pixelWidth, #spriteRows
end

local function getSpriteGridSize(spriteRows)
	local width = 0
	for _, row in ipairs(spriteRows) do
		if type(row) == "table" and #row > width then
			width = #row
		end
	end
	return width, #spriteRows
end

local function trimSprite(spriteRows)
	local srcWidth, srcHeight = getSpriteGridSize(spriteRows)
	local minX = srcWidth
	local minY = srcHeight
	local maxX = 0
	local maxY = 0

	for y, row in ipairs(spriteRows) do
		for x, value in ipairs(row) do
			if value and value ~= 0 then
				if x < minX then
					minX = x
				end
				if y < minY then
					minY = y
				end
				if x > maxX then
					maxX = x
				end
				if y > maxY then
					maxY = y
				end
			end
		end
	end

	if maxX == 0 or maxY == 0 then
		return {}
	end

	local trimmed = {}
	for y = minY, maxY do
		local srcRow = spriteRows[y] or {}
		local dstRow = {}
		for x = minX, maxX do
			dstRow[#dstRow + 1] = srcRow[x] or 0
		end
		trimmed[#trimmed + 1] = dstRow
	end
	return trimmed
end

local function downscaleSpriteBy2(spriteRows)
	local reduced = {}
	for y = 1, #spriteRows, 2 do
		local src = spriteRows[y]
		local dst = {}
		for x = 1, #src, 2 do
			dst[#dst + 1] = src[x]
		end
		reduced[#reduced + 1] = dst
	end
	return reduced
end

-- Resample mode: "majority" picks the most common non-zero colour in each
-- source block (preserves body mass / silhouette).  "nearest" picks the
-- centre pixel with a transparent-fallback scan (preserves fine details
-- like eyes, outlines, claws).
local RESAMPLE_MAJORITY = "majority"
local RESAMPLE_NEAREST  = "nearest"

local function resampleBlock_majority(spriteRows, x0, y0, x1, y1)
	local counts = {}
	local bestValue = 0
	local bestCount = 0
	for sy = y0 + 1, y1 + 1 do
		local srcRow = spriteRows[sy] or {}
		for sx = x0 + 1, x1 + 1 do
			local value = srcRow[sx] or 0
			if value ~= 0 then
				local count = (counts[value] or 0) + 1
				counts[value] = count
				if count > bestCount then
					bestCount = count
					bestValue = value
				end
			end
		end
	end
	if bestCount == 0 then
		local cy = int((y0 + y1) / 2) + 1
		local cx = int((x0 + x1) / 2) + 1
		bestValue = (spriteRows[cy] and spriteRows[cy][cx]) or 0
	end
	return bestValue
end

local function resampleBlock_nearest(spriteRows, x0, y0, x1, y1)
	local cy = int((y0 + y1) / 2) + 1
	local cx = int((x0 + x1) / 2) + 1
	local centerValue = (spriteRows[cy] and spriteRows[cy][cx]) or 0
	if centerValue ~= 0 then
		return centerValue
	end
	for sy = y0 + 1, y1 + 1 do
		local srcRow = spriteRows[sy] or {}
		for sx = x0 + 1, x1 + 1 do
			local v = srcRow[sx] or 0
			if v ~= 0 then
				return v
			end
		end
	end
	return 0
end

local function resampleSprite(spriteRows, targetWidth, targetHeight, mode)
	local srcWidth, srcHeight = getSpriteGridSize(spriteRows)
	if srcWidth == 0 or srcHeight == 0 then
		return {}
	end

	local blockFn = (mode == RESAMPLE_NEAREST)
		and resampleBlock_nearest
		or  resampleBlock_majority

	local resized = {}
	for ty = 0, targetHeight - 1 do
		local y0 = int(ty * srcHeight / targetHeight)
		local y1 = int(((ty + 1) * srcHeight) / targetHeight) - 1
		if y1 < y0 then y1 = y0 end

		local dstRow = {}
		for tx = 0, targetWidth - 1 do
			local x0 = int(tx * srcWidth / targetWidth)
			local x1 = int(((tx + 1) * srcWidth) / targetWidth) - 1
			if x1 < x0 then x1 = x0 end

			dstRow[#dstRow + 1] = blockFn(spriteRows, x0, y0, x1, y1)
		end
		resized[#resized + 1] = dstRow
	end
	return resized
end

local function fitSpriteToArea(spriteRows, maxWidth, maxHeight, pixelWidth, extraDownscaleSteps, resampleMode)
	pixelWidth = pixelWidth or DEFAULT_SPRITE_PIXEL_WIDTH

	local trimmed = trimSprite(spriteRows)
	local srcWidth, srcHeight = getSpriteGridSize(trimmed)
	if srcWidth == 0 or srcHeight == 0 then
		return {}
	end

	local maxSpriteWidth = max(1, int(maxWidth / pixelWidth))
	local maxSpriteHeight = max(1, maxHeight)
	local scale = min(maxSpriteWidth / srcWidth, maxSpriteHeight / srcHeight, 1)
	local targetWidth = max(1, int(srcWidth * scale + 0.5))
	local targetHeight = max(1, int(srcHeight * scale + 0.5))
	local fitted = trimmed

	if targetWidth < srcWidth or targetHeight < srcHeight then
		fitted = resampleSprite(trimmed, targetWidth, targetHeight, resampleMode)
	end

	local extra = extraDownscaleSteps or 0
	local width, height = getSpriteGridSize(fitted)
	while extra > 0 and width > 1 and height > 1 do
		fitted = downscaleSpriteBy2(fitted)
		width, height = getSpriteGridSize(fitted)
		extra = extra - 1
	end
	return fitted
end

local function trySetPaletteIndex(colorindex)
	if SetColorIndex(colorindex) then
		return true
	end
	-- Some terminals expose only 8/16 colors; remap high xterm values to a
	-- lower fallback index so sprites still render.
	if colorindex >= 16 then
		local fallback = colorindex % 16
		if SetColorIndex(fallback) then
			return true
		end
	end
	return SetColorIndex(7)
end

local function setPaletteCellAttr(paletteEntry)
	SetNormal()

	local ok = false
	if type(paletteEntry) == "number" then
		ok = trySetPaletteIndex(paletteEntry)
	elseif type(paletteEntry) == "string" then
		ok = SetColor(paletteEntry)
	elseif type(paletteEntry) == "table" then
		if type(paletteEntry.index) == "number" then
			ok = trySetPaletteIndex(paletteEntry.index)
		elseif type(paletteEntry.name) == "string" then
			ok = SetColor(paletteEntry.name)
		else
			ok = false
		end
	else
		ok = false
	end

	if not ok then
		if not SetColor("green") then
			-- Last resort: render as reversed default terminal colors.
		end
	end

	SetReverse()
	return true
end

local function renderSpriteRow(x, y, row, palette, pixelWidth)
	pixelWidth = pixelWidth or DEFAULT_SPRITE_PIXEL_WIDTH
	local fill = string.rep(BLOCK, pixelWidth)
	for col, paletteSlot in ipairs(row) do
		if paletteSlot and paletteSlot ~= 0 then
			local paletteEntry = palette[paletteSlot]
			if paletteEntry and setPaletteCellAttr(paletteEntry) then
				Write(x + (col - 1) * pixelWidth, y, fill)
			end
		end
	end
end

-- Resolve a palette entry to a raw xterm-256 colour index.
local function paletteEntryToIndex(entry)
	if type(entry) == "number" then
		return entry
	elseif type(entry) == "table" then
		if type(entry.index) == "number" then
			return entry.index
		end
	end
	return nil
end

local SetColorPair = wg.setcolorpair
local HALF_UPPER = string.char(0xe2, 0x96, 0x80) -- ▀ (UTF-8)
local HALF_LOWER = string.char(0xe2, 0x96, 0x84) -- ▄ (UTF-8)

-- Render two sprite rows into one terminal row using half-block characters.
-- Each terminal cell encodes a top pixel (fg via ▀) and bottom pixel (bg).
-- This doubles the effective vertical resolution of sprites.
local function renderHalfBlockRow(x, y, topRow, bottomRow, palette, pixelWidth)
	pixelWidth = pixelWidth or DEFAULT_SPRITE_PIXEL_WIDTH
	local cols = max(#topRow, bottomRow and #bottomRow or 0)
	for col = 1, cols do
		local topSlot = topRow[col] or 0
		local botSlot = bottomRow and bottomRow[col] or 0
		local topIdx = (topSlot ~= 0) and paletteEntryToIndex(palette[topSlot]) or nil
		local botIdx = (botSlot ~= 0) and paletteEntryToIndex(palette[botSlot]) or nil

		local px = x + (col - 1) * pixelWidth
		if topIdx and botIdx then
			-- Both halves have colour: use ▀ with fg=top, bg=bottom
			SetNormal()
			if SetColorPair(topIdx, botIdx) then
				local fill = string.rep(HALF_UPPER, pixelWidth)
				Write(px, y, fill)
			end
		elseif topIdx then
			-- Only top half: use ▀ with fg=top (bg = default/black)
			SetNormal()
			if trySetPaletteIndex(topIdx) then
				local fill = string.rep(HALF_UPPER, pixelWidth)
				Write(px, y, fill)
			end
		elseif botIdx then
			-- Only bottom half: use ▄ with fg=bottom (bg = default/black)
			SetNormal()
			if trySetPaletteIndex(botIdx) then
				local fill = string.rep(HALF_LOWER, pixelWidth)
				Write(px, y, fill)
			end
		end
	end
end

-- Render a full sprite using half-block characters.  Takes the sprite grid,
-- palette, position, and pixel width.  Returns the number of terminal rows
-- consumed (half the sprite grid height, rounded up).
local function renderSpriteHalfBlock(x, y, spriteRows, palette, pixelWidth)
	pixelWidth = pixelWidth or DEFAULT_SPRITE_PIXEL_WIDTH
	local termRow = 0
	for i = 1, #spriteRows, 2 do
		local topRow = spriteRows[i]
		local botRow = spriteRows[i + 1]  -- may be nil on odd-height sprites
		renderHalfBlockRow(x, y + termRow, topRow, botRow, palette, pixelWidth)
		termRow = termRow + 1
	end
	SetNormal()
	return termRow
end

local function getSpriteByKey(spriteKey, availableWidth, availableHeight, pixelWidth, extraDownscaleSteps, resampleMode)
	local def = getSpriteDefinition(spriteKey)
	if not def then
		return nil, nil
	end
	local spriteRows = fitSpriteToArea(
		def.sprite,
		availableWidth,
		availableHeight,
		pixelWidth,
		extraDownscaleSteps,
		resampleMode)
	return spriteRows, (def.color_palette or def.palette)
end

-- Try a size-suffixed key first (_md, _sm), fall back to the base key.
-- This lets callers request a pre-made smaller sprite when available.
local function getSpriteByKeyMultiRes(spriteKey, suffix, availableWidth, availableHeight, pixelWidth, extraDownscaleSteps, resampleMode)
	if suffix and suffix ~= "" then
		local rows, pal = getSpriteByKey(spriteKey .. suffix, availableWidth, availableHeight, pixelWidth, extraDownscaleSteps, resampleMode)
		if rows then
			return rows, pal
		end
	end
	return getSpriteByKey(spriteKey, availableWidth, availableHeight, pixelWidth, extraDownscaleSteps, resampleMode)
end

-----------------------------------------------------------------------------
-- Expose sprite utilities for other addons (e.g. bestiary)

GlobalSpriteUtils = {
	getSpriteByKey = getSpriteByKey,
	getSpriteByKeyMultiRes = getSpriteByKeyMultiRes,
	getSpriteSize = getSpriteSize,
	renderSpriteRow = renderSpriteRow,
	renderSpriteHalfBlock = renderSpriteHalfBlock,
	fitSpriteToArea = fitSpriteToArea,
	getSpriteDefinition = getSpriteDefinition,
	DEFAULT_PIXEL_WIDTH = DEFAULT_SPRITE_PIXEL_WIDTH,
	RESAMPLE_MAJORITY = RESAMPLE_MAJORITY,
	RESAMPLE_NEAREST = RESAMPLE_NEAREST,
}

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
-- Monster defeat log I/O

local function loadDefeatLog()
	if not defeatLogFilePath then
		return {}
	end
	local f = io.open(defeatLogFilePath, "r")
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

local function saveDefeatLog()
	if not defeatLogFilePath or not defeatLogDirty then
		return
	end

	local dates = {}
	for date, _ in pairs(defeatLog) do
		dates[#dates + 1] = date
	end
	table.sort(dates)

	local f = io.open(defeatLogFilePath, "w")
	if not f then
		return
	end
	f:write("return {\n")
	for _, date in ipairs(dates) do
		local entries = defeatLog[date]
		f:write(string_format('  ["%s"] = {\n', date))
		for _, entry in ipairs(entries) do
			-- Escape any quotes in monster names
			local safeName = entry.name:gsub('"', '\\"')
			f:write(string_format('    { name = "%s", time = "%s" },\n', safeName, entry.time or ""))
		end
		f:write("  },\n")
	end
	f:write("}\n")
	f:close()
	defeatLogDirty = false
end

-- Global API for other addons (e.g. bestiary) to record a monster defeat.
function LogMonsterDefeat(monsterName)
	local today = getToday()
	local timeStr = os.date("%H:%M")
	if not defeatLog[today] then
		defeatLog[today] = {}
	end
	local dayLog = defeatLog[today]
	dayLog[#dayLog + 1] = { name = monsterName, time = timeStr }
	defeatLogDirty = true
end

GlobalStatisticsUtils = {
	flushPendingLog = function()
		if logDirty then
			saveWordCountLog()
		end
		if defeatLogDirty then
			saveDefeatLog()
		end
	end,
}

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
	if defeatLogDirty then
		saveDefeatLog()
	end
end

-----------------------------------------------------------------------------
-- Full-screen Statistics UI

function Cmd.StatisticsUI()
	-- Save any pending data before displaying
	if logDirty then
		saveWordCountLog()
	end
	if defeatLogDirty then
		saveDefeatLog()
	end

	-- Gather sorted word-count history (most recent first)
	local wcDates = {}
	for date, _ in pairs(dailyLog) do
		wcDates[#wcDates + 1] = date
	end
	table.sort(wcDates, function(a, b) return a > b end)

	-- Gather sorted defeat history (most recent first)
	local defeatDates = {}
	for date, _ in pairs(defeatLog) do
		defeatDates[#defeatDates + 1] = date
	end
	table.sort(defeatDates, function(a, b) return a > b end)

	-- Build a flat list of defeat-log rows for scrolling.
	-- Each entry is either a date header or a monster entry.
	local defeatRows = {}
	for _, date in ipairs(defeatDates) do
		defeatRows[#defeatRows + 1] = { kind = "date", date = date }
		local entries = defeatLog[date]
		for _, entry in ipairs(entries) do
			defeatRows[#defeatRows + 1] = { kind = "monster", name = entry.name, time = entry.time, date = date }
		end
	end

	local NUM_PAGES = 2
	local currentPage = 1  -- 1 = Word Count, 2 = Monster Defeats
	local scrollOffset = 0

	local function drawWordCountPage(sw, sh, innerX, innerW)
		local today = getToday()
		local todayCount = dailyLog[today] or 0

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
			CentreInField(innerX, countY + 3, innerW, formatNumber(todayCount))
		else
			local bigX = innerX + int((innerW - visualWidth) / 2)
			for i, line in ipairs(bigLines) do
				Write(bigX, countY + i - 1, line)
			end
		end
		SetNormal()

		-- Recent history section (directly after big number, no sprite)
		local historyHeaderY = countY + BIG_DIGIT_HEIGHT + 2
		SetBright()
		CentreInField(innerX, historyHeaderY, innerW, "Recent History")
		SetNormal()

		local dividerY = historyHeaderY + 1
		SetDim()
		CentreInField(innerX, dividerY, innerW, string.rep("─", max(1, innerW)))
		SetNormal()

		local listStartY = dividerY + 1
		local listEndY = sh - 5
		local visibleRows = listEndY - listStartY
		if visibleRows < 1 then visibleRows = 1 end

		local maxScroll = max(0, #wcDates - visibleRows)
		if scrollOffset > maxScroll then scrollOffset = maxScroll end
		if scrollOffset < 0 then scrollOffset = 0 end

		local today_ = getToday()
		for row = 1, visibleRows do
			local idx = scrollOffset + row
			if idx <= #wcDates then
				local date = wcDates[idx]
				local count = dailyLog[date]
				local line = string_format("  %s    %s", date, formatNumber(count))
				if date == today_ then
					SetBright()
				else
					SetNormal()
				end
				LAlignInField(innerX + 2, listStartY + row - 1, innerW - 4, line)
			end
		end
		SetNormal()

		-- Scroll indicator
		if #wcDates > visibleRows then
			local barH = max(1, int(visibleRows * visibleRows / #wcDates))
			local barPos = int(scrollOffset * (visibleRows - barH) / maxScroll)
			for row = 0, visibleRows - 1 do
				if row >= barPos and row < barPos + barH then
					Write(innerX + innerW - 1, listStartY + row, "║")
				else
					Write(innerX + innerW - 1, listStartY + row, "│")
				end
			end
		end
	end

	local function drawDefeatLogPage(sw, sh, innerX, innerW)
		local headerY = 2
		SetBright()
		CentreInField(innerX, headerY, innerW, "Monster Defeat Log")
		SetNormal()

		local dividerY = headerY + 1
		SetDim()
		CentreInField(innerX, dividerY, innerW, string.rep("─", max(1, innerW)))
		SetNormal()

		if #defeatRows == 0 then
			SetDim()
			CentreInField(innerX, int(sh / 2), innerW, "No monsters defeated yet.")
			SetNormal()
			return
		end

		local listStartY = dividerY + 1
		local listEndY = sh - 5
		local visibleRows = listEndY - listStartY
		if visibleRows < 1 then visibleRows = 1 end

		local maxScroll = max(0, #defeatRows - visibleRows)
		if scrollOffset > maxScroll then scrollOffset = maxScroll end
		if scrollOffset < 0 then scrollOffset = 0 end

		local today = getToday()
		for row = 1, visibleRows do
			local idx = scrollOffset + row
			if idx <= #defeatRows then
				local entry = defeatRows[idx]
				if entry.kind == "date" then
					SetBright()
					local dateLabel = entry.date
					if entry.date == today then
						dateLabel = dateLabel .. "  (today)"
					end
					LAlignInField(innerX + 2, listStartY + row - 1, innerW - 4, dateLabel)
				else
					SetNormal()
					local line = string_format("    %s  %s", entry.time, entry.name)
					LAlignInField(innerX + 2, listStartY + row - 1, innerW - 4, line)
				end
			end
		end
		SetNormal()

		-- Scroll indicator
		if #defeatRows > visibleRows then
			local barH = max(1, int(visibleRows * visibleRows / #defeatRows))
			local barPos = int(scrollOffset * (visibleRows - barH) / maxScroll)
			for row = 0, visibleRows - 1 do
				if row >= barPos and row < barPos + barH then
					Write(innerX + innerW - 1, listStartY + row, "║")
				else
					Write(innerX + innerW - 1, listStartY + row, "│")
				end
			end
		end
	end

	local function drawScreen()
		ResizeScreen()
		wg.clearscreen()

		local sw, sh = ScreenWidth, ScreenHeight

		-- Top and bottom borders
		SetBright()
		local hborder = string.rep("─", sw)
		Write(0, 0, hborder)
		CentreInField(0, 0, sw, string_format(" Statistics [%d/%d] ", currentPage, NUM_PAGES))
		Write(0, sh - 1, hborder)
		SetNormal()

		local innerX = 1
		local innerW = sw - 2

		if currentPage == 1 then
			drawWordCountPage(sw, sh, innerX, innerW)
		else
			drawDefeatLogPage(sw, sh, innerX, innerW)
		end

		-- Help text
		CentreInField(innerX, sh - 4, innerW, "LEFT/RIGHT: Switch page   UP/DOWN: Scroll")
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
		elseif (key == "KEY_LEFT") or (key == "KEY_SLEFT") then
			if currentPage > 1 then
				currentPage = currentPage - 1
				scrollOffset = 0
			end
		elseif (key == "KEY_RIGHT") or (key == "KEY_SRIGHT") then
			if currentPage < NUM_PAGES then
				currentPage = currentPage + 1
				scrollOffset = 0
			end
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

-- Full-screen Character UI (equipment slots)

function Cmd.CharacterUI()
	local function drawEquipBox(x, y, w, h, label)
		SetNormal()
		DrawBox(x, y, w, h)
		SetDim()
		CentreInField(x + 1, y + int(h / 2), w, label)
		SetNormal()
	end

	local function drawScreen()
		ResizeScreen()
		wg.clearscreen()

		local sw, sh = ScreenWidth, ScreenHeight

		SetBright()
		local hborder = string.rep("─", sw)
		Write(0, 0, hborder)
		CentreInField(0, 0, sw, " Character ")
		Write(0, sh - 1, hborder)
		SetNormal()

		-- Equipment layout: 6 boxes arranged like a paper-doll
		--       [  Head  ]
		-- [L.Arm][ Torso ][R.Arm]
		-- [L.Leg]         [R.Leg]

		local innerW = sw - 4
		local innerX = 2
		local contentTop = 2
		local contentBottom = sh - 4
		local contentH = contentBottom - contentTop

		-- Box dimensions
		local boxW = max(8, min(16, int(innerW / 3) - 2))
		local boxH = max(3, min(8, int(contentH / 3) - 1))

		-- Center the grid horizontally
		local gridW = boxW * 3 + 4  -- 3 columns + gaps
		local gridX = innerX + int((innerW - gridW) / 2)
		if gridX < innerX then gridX = innerX end

		-- Center the grid vertically
		local gridH = boxH * 3 + 4  -- 3 rows + gaps
		local gridY = contentTop + int((contentH - gridH) / 2)
		if gridY < contentTop then gridY = contentTop end

		local col1 = gridX
		local col2 = gridX + boxW + 2
		local col3 = gridX + (boxW + 2) * 2

		local row1 = gridY
		local row2 = gridY + boxH + 2
		local row3 = gridY + (boxH + 2) * 2

		-- Row 1: Head (center column)
		drawEquipBox(col2, row1, boxW, boxH, "Head")

		-- Row 2: Left Arm, Torso, Right Arm
		drawEquipBox(col1, row2, boxW, boxH, "L.Arm")
		drawEquipBox(col2, row2, boxW, boxH, "Torso")
		drawEquipBox(col3, row2, boxW, boxH, "R.Arm")

		-- Row 3: Left Leg (col1), Right Leg (col3)
		drawEquipBox(col1, row3, boxW, boxH, "L.Leg")
		drawEquipBox(col3, row3, boxW, boxH, "R.Leg")

		CentreInField(innerX, sh - 3, innerW, "RETURN or ^C: Close")
		wg.hidecursor()
		wg.sync()
	end

	while true do
		drawScreen()
		local key = GetChar()
		if (key == "KEY_^C") or (key == "KEY_RETURN") or (key == "KEY_ENTER") or (key == "KEY_ESCAPE") then
			break
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

		defeatLogFilePath = CONFIGDIR .. "/monster_defeat_log.lua"
		defeatLog = loadDefeatLog()
	end

	AddEventListener(Event.RegisterAddons, initCb)
	AddEventListener(Event.Changed, onChanged)
	AddEventListener(Event.DocumentLoaded, resetBaseline)
	AddEventListener(Event.DocumentCreated, resetBaseline)
	AddEventListener(Event.Idle, onIdle)
end
