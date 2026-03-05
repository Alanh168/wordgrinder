-- Color viewer addon for WordGrinder.
-- Shows xterm-256 colour indices in a paged grid.

local int = math.floor
local min = math.min
local max = math.max
local string_format = string.format
local string_rep = string.rep
local Write = wg.write
local GetChar = wg.getchar
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetReverse = wg.setreverse
local SetColorIndex = wg.setcolorindex
local GetBoundedString = wg.getboundedstring

local COLORS_PER_PAGE = 6
local TOTAL_COLORS = 256
local TOTAL_PAGES = int((TOTAL_COLORS + COLORS_PER_PAGE - 1) / COLORS_PER_PAGE)

local function drawColorCell(x, y, w, index)
	local swatchWidth = max(6, min(14, int(w * 0.33)))
	local labelWidth = w - swatchWidth - 1
	if labelWidth < 1 then
		swatchWidth = max(4, w - 2)
		labelWidth = w - swatchWidth - 1
	end

	local swatch = string_rep(" ", swatchWidth)
	local available = SetColorIndex(index)
	if available then
		SetReverse()
		Write(x, y, swatch)
		SetNormal()
	else
		SetNormal()
		Write(x, y, swatch)
		Write(x, y, GetBoundedString("Color Unavailable", swatchWidth))
	end

	local label = string_format("color # %3d", index)
	label = GetBoundedString(label, max(0, labelWidth))
	Write(x + swatchWidth + 1, y, label)
end

function Cmd.ColorViewerUI()
	local page = 0

	while true do
		ResizeScreen()
		wg.clearscreen()

		local sw, sh = ScreenWidth, ScreenHeight
		local hborder = string_rep("─", sw)
		local firstIndex = page * COLORS_PER_PAGE
		local lastIndex = min(TOTAL_COLORS - 1, firstIndex + COLORS_PER_PAGE - 1)

		SetBright()
		Write(0, 0, hborder)
		CentreInField(0, 0, sw, " Color Viewer ")
		Write(0, sh - 1, hborder)
		CentreInField(1, 2, sw - 2,
			string_format("Page %d/%d   init_pair(COLOR_PAIR_ID, color #, -1): %d to %d",
				page + 1, TOTAL_PAGES, firstIndex, lastIndex))
		SetNormal()

		local cols = 1
		local rows = int((COLORS_PER_PAGE + cols - 1) / cols)
		local innerX = 2
		local innerW = sw - 4
		local colGap = 4

		local gridTop = 4
		local gridBottom = sh - 6
		if gridBottom < gridTop then
			gridBottom = gridTop
		end

		-- Keep rows compact regardless of window size, then center the block.
		local rowStep = 2
		local blockHeight = 1 + (rows - 1) * rowStep
		local gridHeight = gridBottom - gridTop + 1
		if blockHeight > gridHeight then
			rowStep = 1
			blockHeight = rows
		end

		local gridStartY = gridTop
		if gridHeight > blockHeight then
			gridStartY = gridTop + int((gridHeight - blockHeight) / 2)
		end

		local desiredColWidth = min(innerW, 52)
		local colWidth = max(12, desiredColWidth)
		if colWidth > innerW then
			colWidth = innerW
		end
		local gridStartX = innerX
		if innerW > colWidth then
			gridStartX = innerX + int((innerW - colWidth) / 2)
		end

		for slot = 0, COLORS_PER_PAGE - 1 do
			local index = firstIndex + slot
			if index >= TOTAL_COLORS then
				break
			end

			local row = int(slot / cols)
			local col = slot % cols
			local x = gridStartX + col * (colWidth + colGap)
			local y = gridStartY + row * rowStep
			drawColorCell(x, y, colWidth, index)
		end

		CentreInField(1, sh - 4, sw - 2, "LEFT/RIGHT: Previous/Next page")
		CentreInField(1, sh - 3, sw - 2, "RETURN or ^C: Close")

		wg.hidecursor()
		wg.sync()

		local key = GetChar()
		if (key == "KEY_^C") or (key == "KEY_RETURN") or (key == "KEY_ENTER") or (key == "KEY_ESCAPE") then
			break
		elseif (key == "KEY_LEFT") or (key == "KEY_SLEFT") then
			page = max(0, page - 1)
		elseif (key == "KEY_RIGHT") or (key == "KEY_SRIGHT") then
			page = min(TOTAL_PAGES - 1, page + 1)
		elseif key == "KEY_HOME" then
			page = 0
		elseif key == "KEY_END" then
			page = TOTAL_PAGES - 1
		end
	end

	QueueRedraw()
	return true
end
