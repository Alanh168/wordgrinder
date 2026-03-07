-- © 2008 David Given.
-- WordGrinder is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local int = math.floor
local min = math.min
local table_concat = table.concat
local Write = wg.write
local GotoXY = wg.gotoxy
local ClearArea = wg.cleararea
local SetNormal = wg.setnormal
local SetBold = wg.setbold
local SetBright = wg.setbright
local SetUnderline = wg.setunderline
local SetReverse = wg.setreverse
local SetDim = wg.setdim
local GetStringWidth = wg.getstringwidth
local ShowCursor = wg.showcursor
local HideCursor = wg.hidecursor
local Sync = wg.sync

local BLINK_TIME = 0.8

local messages = {}
local leftpadding = 0
local monsterBarHeight = 0
local monsterBarHiddenDepth = 0
local spriteOverlayFrameId = 0

function NonmodalMessage(s)
	messages[#messages+1] = s
	QueueRedraw()
end

function ResetNonmodalMessages()
	messages = {}
end

function ResizeScreen()
	ScreenWidth, ScreenHeight = wg.getscreensize()
	local w = GetMaximumAllowedWidth(ScreenWidth)
	local rw = w - Document.margin - 1
	leftpadding = math.floor(ScreenWidth/2 - rw/2)
	Document:wrap(w - Document.margin - 1)
end

local function drawmargin(y, pn, p)
	local controller = MarginControllers[Document.viewmode]
	if controller.getcontent then
		local s = controller:getcontent(pn, p)

		if s then
			SetDim()
			RAlignInField(leftpadding, y, Document.margin - 1, s)
			SetNormal()
		end
	end

	local style = DocumentStyles[p.style]
	local function drawbullet(n)
		local w = GetStringWidth(n) + 1
		local i = style.indent
		if (i >= w) then
			Write(leftpadding + Document.margin + i - w, y, n)
		end
	end

	local bullet = style.bullet
	if bullet then
		drawbullet(bullet)
	else
		local numbered = style.numbered
		if numbered then
			local n = tostring(p.number or 0).."."
			drawbullet(n)
		end
	end
end

local changed_tab =
{
	[true] = "CHANGED"
}

local function redrawstatus()
	local y = ScreenHeight - 1

	if DocumentSet.statusbar then
		local displayName
		if LastLoadedDraftName then
			displayName = LastLoadedDraftName .. " "
		else
			displayName = (Leafname(DocumentSet.name or "(unnamed)")):gsub("%.wg$", " ")
		end
		local s = {
			displayName,
			"[",
			Document.name or "",
			"] ",
			changed_tab[DocumentSet.changed] or "",
		}

		SetReverse()
		ClearArea(0, ScreenHeight-1, ScreenWidth-1, ScreenHeight-1)
		LAlignInField(0, ScreenHeight-1, ScreenWidth, table.concat(s, ""))

		local ss = {}
		FireEvent(Event.BuildStatusBar, ss)
		table.sort(ss, function(x, y) return x.priority < y.priority end)

		local s = {" "}
		for _, v in ipairs(ss) do
			s[#s+1] = v.value
		end
		s = table.concat(s, " │ ")
		if (string.sub(s, #s) == " ") then
			s = string.sub(s, 1, #s-1)
		end

		RAlignInField(0, ScreenHeight-1, ScreenWidth, s)
		SetNormal()

		y = y - 1
	end

	if (#messages > 0) then
		SetReverse()

		for i = #messages, 1, -1 do
			ClearArea(0, y, ScreenWidth-1, y)
			Write(0, y, messages[i])
			y = y - 1
		end

		SetNormal()
	end
end

-- Emit an OSC 99 sprite command to Cool Retro Term's Image Overlay.
-- Format: \027]99;sprite_id;cell_x;cell_y;target_cell_height[;target_cell_width;anchor]\007
-- cell_x/cell_y may be fractional for more precise placement.
-- target_cell_height: how many cells tall the sprite should be (can be fractional).
-- target_cell_width/anchor are optional and allow fit-within-box centering.
-- CRT calculates the actual pixel scale from this and the image's native size.
-- Clear: \027]99;clear\007
local function emitSpriteCommand(spriteId, cellX, cellY, targetCellHeight, targetCellWidth, anchor)
	local command = string.format("%s;%.2f;%.2f;%.2f",
		spriteId, cellX, cellY, targetCellHeight)

	if (type(targetCellWidth) == "number") or (type(anchor) == "string") then
		local widthField = ""
		if type(targetCellWidth) == "number" and targetCellWidth > 0 then
			widthField = string.format("%.2f", targetCellWidth)
		end

		command = command .. ";" .. widthField
		if type(anchor) == "string" and anchor ~= "" then
			command = command .. ";" .. anchor
		end
	end

	io.write("\027]99;" .. command .. "\007")
	io.flush()
end

local function clearSpriteOverlay()
	io.write("\027]99;clear\007")
	io.flush()
end

local function replaceSpriteOverlay(sprites)
	spriteOverlayFrameId = spriteOverlayFrameId + 1

	local encoded = {}
	if type(sprites) == "table" then
		for _, sprite in ipairs(sprites) do
			local spriteId = sprite and sprite.spriteId
			local cellX = sprite and sprite.cellX
			local cellY = sprite and sprite.cellY
			local targetCellHeight = sprite and sprite.targetCellHeight
			local targetCellWidth = sprite and sprite.targetCellWidth
			local anchor = sprite and sprite.anchor
			if type(spriteId) == "string"
				and type(cellX) == "number"
				and type(cellY) == "number"
				and type(targetCellHeight) == "number" then
				local entry = string.format("%s,%.2f,%.2f,%.2f",
					spriteId, cellX, cellY, targetCellHeight)
				if (type(targetCellWidth) == "number") or (type(anchor) == "string") then
					local widthField = ""
					if type(targetCellWidth) == "number" and targetCellWidth > 0 then
						widthField = string.format("%.2f", targetCellWidth)
					end
					entry = entry .. "," .. widthField .. ","
					if type(anchor) == "string" and anchor ~= "" then
						entry = entry .. anchor
					end
				end
				encoded[#encoded + 1] = entry
			end
		end
	end

	io.write(string.format("\027]99;frame;%d;%s\007",
		spriteOverlayFrameId, table_concat(encoded, "|")))
	io.flush()
end

function EmitSpriteOverlay(spriteId, cellX, cellY, targetCellHeight, targetCellWidth, anchor)
	emitSpriteCommand(spriteId, cellX, cellY, targetCellHeight, targetCellWidth, anchor)
end

function ClearSpriteOverlay()
	clearSpriteOverlay()
end

function ReplaceSpriteOverlay(sprites)
	replaceSpriteOverlay(sprites)
end

local function isMonsterBarVisible()
	return monsterBarHiddenDepth == 0
end

function IsMonsterBarVisible()
	return isMonsterBarVisible()
end

function PushMonsterBarHidden()
	monsterBarHiddenDepth = monsterBarHiddenDepth + 1
	monsterBarHeight = 0
	clearSpriteOverlay()
end

function PopMonsterBarHidden()
	if monsterBarHiddenDepth > 0 then
		monsterBarHiddenDepth = monsterBarHiddenDepth - 1
	end
	if monsterBarHiddenDepth > 0 then
		monsterBarHeight = 0
		clearSpriteOverlay()
	end
end

function RunWithMonsterBarHidden(callback, ...)
	local args = {...}
	PushMonsterBarHidden()
	local results = {xpcall(function()
		return callback(unpack(args))
	end, Traceback)}
	PopMonsterBarHidden()
	if not results[1] then
		error(results[2])
	end
	return unpack(results, 2)
end

local function redrawmonsterbar()
	if not isMonsterBarVisible() then
		monsterBarHeight = 0
		clearSpriteOverlay()
		return
	end

	local isActive = rawget(_G, "IsMonsterQueueActive")
	if not isActive or not isActive() then
		monsterBarHeight = 0
		clearSpriteOverlay()
		return
	end

	local getCurrent = rawget(_G, "GetCurrentMonster")
	local getState = rawget(_G, "GetMonsterQueueState")
	if not getCurrent or not getState then
		monsterBarHeight = 0
		clearSpriteOverlay()
		return
	end

	local monster = getCurrent()
	local state = getState()
	if not monster then
		monsterBarHeight = 0
		clearSpriteOverlay()
		return
	end

	local parts = {}

	-- Monster name
	parts[#parts + 1] = monster.name or "???"

	if monster.target_word_count then
		parts[#parts + 1] = string.format("%d/%d words",
			state.wordsTyped or 0, monster.target_word_count)
	end

	if monster.target_time_limit_minutes then
		local elapsed = 0
		if state.startTime then
			elapsed = int((os.time() - state.startTime) / 60)
		end
		parts[#parts + 1] = string.format("%d/%d min",
			elapsed, monster.target_time_limit_minutes)
	end

	local barText = table.concat(parts, "  ")

	-- Reserve space on the right for the sprite icon (4 cells wide).
	local spriteReserved = 0
	if monster.sprite_ref and monster.sprite_ref ~= "" then
		spriteReserved = 4
	end

	SetNormal()
	RAlignInField(0, 0, ScreenWidth - spriteReserved, barText)

	-- Emit OSC 99 to render the monster sprite via the Image Overlay.
	-- Clear first because the overlay can now display multiple sprites at once.
	-- Sprite is right-anchored to spriteX by CRT's ImageOverlay.
	if spriteReserved > 0 then
		clearSpriteOverlay()
		emitSpriteCommand(monster.sprite_ref, ScreenWidth, 0, 1.5)
	end

	monsterBarHeight = 1
end

local topmarker = {
	"     ▲          ▲          ▲          ▲          ▲     ",
	"───────────────────────────────────────────────────────"
}
local topmarkerwidth = GetStringWidth(topmarker[1])

local function drawtopmarker(y)
	local x = int((ScreenWidth - topmarkerwidth)/2)

	SetBright()
	for i = #topmarker, 1, -1 do
		if (y >= 0) then
			Write(x, y, topmarker[i])
		end
		y = y - 1
	end
	SetNormal()
end

local bottommarker = {
	"───────────────────────────────────────────────────────",
	"     ▼          ▼          ▼          ▼          ▼     ",
}
local bottommarkerwidth = GetStringWidth(bottommarker[1])

local function drawbottommarker(y)
	local x = int((ScreenWidth - bottommarkerwidth)/2)

	SetBright()
	for i = 1, #bottommarker do
		if (y <= ScreenHeight) then
			Write(x, y, bottommarker[i])
		end
		y = y + 1
	end
	SetNormal()
end

function RedrawScreen()
	wg.clearscreen()

	-- Determine top offset for monster bar
	local topOffset = 0
	local isQueueActive = rawget(_G, "IsMonsterQueueActive")
	if isMonsterBarVisible() and isQueueActive and isQueueActive() then
		topOffset = 1
	end

	local cp, cw, co = Document.cp, Document.cw, Document.co
	local cy = int(ScreenHeight / 2)
	local margin = Document.margin

	-- Find out the offset of the current paragraph.

	local paragraph = Document[cp]
	local ocw = cw
	local cl
	cl, cw = paragraph:getLineOfWord(cw)
	if not cl then
		error("word "..ocw.." not in para "..cp.." of len "..#paragraph)
	end

	-- Position the cursor.

	do
		local cw = Document.cw
		local word = paragraph[cw]
		GotoXY(leftpadding + margin + paragraph.xs[cw] +
			GetWidthFromOffset(word, Document.co) + paragraph:getIndentOfLine(cl),
			cy - 1)
	end

	-- Cache values for mark drawing.

	local mp = Document.mp
	local mw = Document.mw
	local mo = Document.mo

	-- Draw backwards.

	local pn = cp - 1
	local y = cy - cl - 1 - Document:spaceAbove(cp)

	Document.topp = nil
	Document.topw = nil
	while (y >= topOffset) do
		local paragraph = Document[pn]
		if not paragraph then
			break
		end

		local lines = paragraph:wrap()
		for ln = #lines, 1, -1 do
			local x = paragraph:getIndentOfLine(ln)
			local l = lines[ln]

			if not mp then
				paragraph:renderLine(l,
					leftpadding + margin + x, y)
			else
				paragraph:renderMarkedLine(l,
					leftpadding + margin + x, y, nil, pn)
			end

			if (ln == 1) then
				drawmargin(y, pn, paragraph)
			end

			Document.topp = pn
			Document.topw = l.wn
			y = y - 1

			if (y < topOffset) then
				break
			end
		end

		y = y - Document:spaceAbove(pn)
		pn = pn - 1
	end

	if (y >= topOffset) and WantTerminators() then
		drawtopmarker(y)
	end

	-- Draw forwards.

	y = cy - cl
	pn = cp
	while (y < ScreenHeight) do
		local paragraph = Document[pn]
		if not paragraph then
			break
		end

		drawmargin(y, pn, paragraph)

		for ln, l in ipairs(paragraph:wrap()) do
			local x = paragraph:getIndentOfLine(ln)
			if not mp then
				paragraph:renderLine(l,
					leftpadding + margin + x, y)
			else
				paragraph:renderMarkedLine(l,
					leftpadding + margin + x, y, nil, pn)
			end

			-- If the top of the page hasn't already been set, then the
			-- current paragraph extends off the top of the screen.

			if not Document.topp and (y == topOffset) then
				Document.topp = pn
				Document.topw = l.wn
			end

			Document.botp = pn
			Document.botw = l.wn
			y = y + 1

			if (y > ScreenHeight) then
				break
			end
		end
		y = y + Document:spaceBelow(pn)
		pn = pn + 1
	end

	-- If the top of the page *still* hasn't been set, then we're on the
	-- first paragraph of the document.

	if not Document.topp then
		Document.topp = 1
		Document.topw = 1
	end

	if (y <= ScreenHeight) and WantTerminators() then
		drawbottommarker(y)
	end

	-- Draw monster bar at top (after text so it overwrites any overflow)
	redrawmonsterbar()

	redrawstatus()

	FireEvent(Event.Redraw)
end

function GetCharWithBlinkingCursor(timeout)
	ShowCursor()

	timeout = timeout or 1E10
	local shown = true
	while timeout > 0 do
		local t = shown and BLINK_ON_TIME or BLINK_OFF_TIME
		t = min(t, timeout)
		local c = wg.getchar(t)
		if (c ~= "KEY_TIMEOUT") then
			ShowCursor();
			return c
		end

		shown = not shown
		local cb = shown and ShowCursor or HideCursor
		cb()

		timeout = timeout - t
	end
	
	return "KEY_TIMEOUT"
end

-----------------------------------------------------------------------------
-- Does assorted fast updates in the current document on changes:
--   - word count
--   - numbered paragraph styles

do
	local function cb(event, token)
		Document:renumber()
	end

	AddEventListener(Event.Changed, cb)
end
