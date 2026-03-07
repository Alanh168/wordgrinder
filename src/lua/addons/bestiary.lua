-- Monster bestiary for WordGrinder's game mode.
-- Lua is used instead of JSON so no extra parser is required in core.

local int = math.floor
local min = math.min
local max = math.max
local string_format = string.format
local string_rep = string.rep
local Write = wg.write
local GetChar = wg.getchar
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetDim = wg.setdim
local GetBoundedString = wg.getboundedstring

local monsters = {
	{
		name = "Agumon",
		sprite_ref = "agumon",
		target_word_count = 120,
		target_time_limit_minutes = nil,
	},
	{
		name = "Wolf",
		sprite_ref = "monster_wolf",
		target_word_count = 100,
		target_time_limit_minutes = 15,
	},
	-- The following are future monsters that don't have sprites and should not be uncommented until they do
	-- {
	-- 	name = "Paper Slime",
	-- 	sprite_ref = "",
	-- 	target_word_count = 120,
	-- 	target_time_limit_minutes = nil,
	-- },
	-- {
	-- 	name = "Ink Mite",
	-- 	sprite_ref = "",
	-- 	target_word_count = 180,
	-- 	target_time_limit_minutes = 10,
	-- },
	-- {
	-- 	name = "Count Daily",
	-- 	sprite_ref = "",
	-- 	target_word_count = 250,
	-- 	target_time_limit_minutes = 15,
	-- },
	-- {
	-- 	name = "Comma Wisp",
	-- 	sprite_ref = "",
	-- 	target_word_count = 320,
	-- 	target_time_limit_minutes = 20,
	-- },
	-- {
	-- 	name = "Plot Beetle",
	-- 	sprite_ref = "",
	-- 	target_word_count = 420,
	-- 	target_time_limit_minutes = nil,
	-- },
	-- {
	-- 	name = "Outline Hydra",
	-- 	sprite_ref = "",
	-- 	target_word_count = 550,
	-- 	target_time_limit_minutes = 30,
	-- },
	-- {
	-- 	name = "Revision Hound",
	-- 	sprite_ref = "",
	-- 	target_word_count = 700,
	-- 	target_time_limit_minutes = 35,
	-- },
	-- {
	-- 	name = "Chapter Ogre",
	-- 	sprite_ref = "",
	-- 	target_word_count = 900,
	-- 	target_time_limit_minutes = 45,
	-- },
	-- {
	-- 	name = "Deadline Drake",
	-- 	sprite_ref = "",
	-- 	target_word_count = 1200,
	-- 	target_time_limit_minutes = 60,
	-- },
	-- {
	-- 	name = "Final Draft Titan",
	-- 	sprite_ref = "",
	-- 	target_word_count = 1600,
	-- 	target_time_limit_minutes = 90,
	-- },
}

function GetMonsterBestiary()
	return monsters
end

-----------------------------------------------------------------------------
-- Bestiary UI

local MONSTERS_PER_PAGE = 4
local BESTIARY_SMALL_PIXEL_WIDTH = 2
local BESTIARY_LARGE_PIXEL_WIDTH = 2

local function getSpriteUtils()
	return rawget(_G, "GlobalSpriteUtils")
end

local function formatTimeLimitString(minutes)
	if not minutes then
		return "None"
	end
	if minutes >= 60 then
		local h = int(minutes / 60)
		local m = minutes % 60
		if m > 0 then
			return string_format("%dh %dm", h, m)
		end
		return string_format("%dh", h)
	end
	return string_format("%dm", minutes)
end

local function drawMonsterSlot(x, y, w, h, monster, isSelected, spriteUtils)
	-- Draw selection indicator
	if isSelected then
		SetBright()
		Write(x, y, ">")
	else
		SetNormal()
		Write(x, y, " ")
	end

	-- Layout: [sprite area] [info area]
	-- Sprite gets left portion, info gets right portion
	local spriteAreaW = min(40, int(w * 0.45))
	local infoX = x + 2 + spriteAreaW
	local infoW = w - spriteAreaW - 3

	-- Draw monster name
	if isSelected then
		SetBright()
	else
		SetNormal()
	end
	local nameStr = GetBoundedString(monster.name, infoW)
	Write(infoX, y, nameStr)

	-- Draw word count target
	SetNormal()
	local wcStr = string_format("Words: %d", monster.target_word_count or 0)
	Write(infoX, y + 1, GetBoundedString(wcStr, infoW))

	-- Draw time limit
	local tlStr = string_format("Time: %s", formatTimeLimitString(monster.target_time_limit_minutes))
	Write(infoX, y + 2, GetBoundedString(tlStr, infoW))

	-- Draw sprite (small) using full-block rendering
	if spriteUtils and monster.sprite_ref and monster.sprite_ref ~= "" then
		local termRows = max(1, h - 1)
		local resampleMode = spriteUtils.RESAMPLE_NEAREST or "nearest"
		local getSprite = spriteUtils.getSpriteByKeyMultiRes or spriteUtils.getSpriteByKey
		local sprite, palette = getSprite(
			monster.sprite_ref, "_md",
			spriteAreaW,
			termRows,
			BESTIARY_SMALL_PIXEL_WIDTH,
			0,
			resampleMode)
		if sprite and palette then
			local spriteW = spriteUtils.getSpriteSize(sprite, BESTIARY_SMALL_PIXEL_WIDTH)
			local drawX = x + 2 + int((spriteAreaW - spriteW) / 2)
			local drawY = y + int((h - #sprite) / 2)
			for row = 1, #sprite do
				spriteUtils.renderSpriteRow(drawX, drawY + row - 1, sprite[row], palette, BESTIARY_SMALL_PIXEL_WIDTH)
			end
			SetNormal()
		end
	end

	-- Draw separator line below (unless at bottom)
	SetDim()
	Write(x + 1, y + h, string_rep("─", w - 2))
	SetNormal()
end

local function drawDetailView(monster, spriteUtils)
	ResizeScreen()
	wg.clearscreen()

	local sw, sh = ScreenWidth, ScreenHeight
	local hborder = string_rep("─", sw)

	-- Title bar
	SetBright()
	Write(0, 0, hborder)
	CentreInField(0, 0, sw, string_format(" %s ", monster.name))
	SetNormal()

	-- Info line
	local infoLine = string_format("Words: %d   Time Limit: %s",
		monster.target_word_count or 0,
		formatTimeLimitString(monster.target_time_limit_minutes))
	CentreInField(0, 2, sw, infoLine)

	-- Sprite area (large) — full-block rendering
	local spriteTop = 4
	local spriteBottom = sh - 4
	local termRows = spriteBottom - spriteTop
	local availableW = sw - 4

	if spriteUtils and monster.sprite_ref and monster.sprite_ref ~= "" then
		local sprite, palette = spriteUtils.getSpriteByKey(
			monster.sprite_ref,
			availableW,
			termRows,
			BESTIARY_LARGE_PIXEL_WIDTH,
			0)
		if sprite and palette then
			local spriteW = spriteUtils.getSpriteSize(sprite, BESTIARY_LARGE_PIXEL_WIDTH)
			local drawX = int((sw - spriteW) / 2)
			local drawY = spriteTop + int((termRows - #sprite) / 2)
			for row = 1, #sprite do
				spriteUtils.renderSpriteRow(drawX, drawY + row - 1, sprite[row], palette, BESTIARY_LARGE_PIXEL_WIDTH)
			end
			SetNormal()
		end
	else
		SetDim()
		CentreInField(0, int(sh / 2), sw, "[ No sprite available ]")
		SetNormal()
	end

	-- Footer
	SetBright()
	Write(0, sh - 2, hborder)
	SetNormal()
	CentreInField(0, sh - 1, sw, "ENTER: Back to Bestiary")

	wg.hidecursor()
	wg.sync()
end

function Cmd.BestiaryUI()
	local allMonsters = GetMonsterBestiary()
	if #allMonsters == 0 then
		return true
	end

	local totalPages = max(1, int((#allMonsters + MONSTERS_PER_PAGE - 1) / MONSTERS_PER_PAGE))
	local page = 0
	local selected = 0  -- 0-based index within the page
	local inDetailView = false
	local spriteUtils = getSpriteUtils()

	while true do
		if inDetailView then
			local globalIndex = page * MONSTERS_PER_PAGE + selected + 1
			local monster = allMonsters[globalIndex]
			if monster then
				drawDetailView(monster, spriteUtils)
			end

			local key = GetChar()
			if (key == "KEY_RETURN") or (key == "KEY_ENTER") then
				inDetailView = false
			elseif (key == "KEY_^C") or (key == "KEY_ESCAPE") then
				inDetailView = false
			end
		else
			-- List view
			ResizeScreen()
			wg.clearscreen()

			local sw, sh = ScreenWidth, ScreenHeight
			local hborder = string_rep("─", sw)

			local firstIndex = page * MONSTERS_PER_PAGE
			local lastIndex = min(#allMonsters - 1, firstIndex + MONSTERS_PER_PAGE - 1)
			local monstersOnPage = lastIndex - firstIndex + 1

			-- Clamp selected to valid range
			if selected >= monstersOnPage then
				selected = monstersOnPage - 1
			end

			-- Title bar
			SetBright()
			Write(0, 0, hborder)
			CentreInField(0, 0, sw, string_format(" Bestiary  [Page %d/%d] ", page + 1, totalPages))
			SetNormal()

			-- Content area
			local contentTop = 2
			local contentBottom = sh - 4
			local contentH = contentBottom - contentTop
			local slotH = max(4, int(contentH / max(1, monstersOnPage)))
			local innerW = sw - 4
			local innerX = 2

			for slot = 0, monstersOnPage - 1 do
				local monsterIndex = firstIndex + slot + 1
				local monster = allMonsters[monsterIndex]
				if monster then
					local slotY = contentTop + slot * slotH
					local isSelected = (slot == selected)
					drawMonsterSlot(innerX, slotY, innerW, slotH - 1, monster, isSelected, spriteUtils)
				end
			end

			-- Footer
			SetBright()
			Write(0, sh - 3, hborder)
			SetNormal()
			CentreInField(0, sh - 2, sw, "UP/DOWN: Select   LEFT/RIGHT: Page   ENTER: View sprite")
			CentreInField(0, sh - 1, sw, "ESC or ^C: Close")

			wg.hidecursor()
			wg.sync()

			local key = GetChar()
			if (key == "KEY_^C") or (key == "KEY_ESCAPE") then
				break
			elseif (key == "KEY_RETURN") or (key == "KEY_ENTER") then
				inDetailView = true
			elseif (key == "KEY_UP") or (key == "KEY_SUP") then
				if selected > 0 then
					selected = selected - 1
				end
			elseif (key == "KEY_DOWN") or (key == "KEY_SDOWN") then
				if selected < monstersOnPage - 1 then
					selected = selected + 1
				end
			elseif (key == "KEY_LEFT") or (key == "KEY_SLEFT") then
				if page > 0 then
					page = page - 1
					selected = 0
				end
			elseif (key == "KEY_RIGHT") or (key == "KEY_SRIGHT") then
				if page < totalPages - 1 then
					page = page + 1
					selected = 0
				end
			elseif key == "KEY_HOME" then
				page = 0
				selected = 0
			elseif key == "KEY_END" then
				page = totalPages - 1
				selected = 0
			end
		end
	end

	QueueRedraw()
	return true
end
