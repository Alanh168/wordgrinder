-- Battle Select screen for WordGrinder's game mode.

local string_format = string.format
local int = math.floor
local min = math.min
local max = math.max
local Write = wg.write
local GetChar = wg.getchar
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetDim = wg.setdim
local GetBoundedString = wg.getboundedstring

local BATTLE_SLOT_MIN_INNER_H = 8
local BATTLE_SLOT_MAX_INNER_H = 16

local function getMonsterBestiary()
	local getter = rawget(_G, "GetMonsterBestiary")
	if type(getter) ~= "function" then
		return {}
	end
	local ok, monsters = pcall(getter)
	if not ok or type(monsters) ~= "table" then
		return {}
	end
	return monsters
end

local function formatMonsterTimeLimit(minutes)
	local formatter = rawget(_G, "FormatMonsterTimeLimit")
	if type(formatter) == "function" then
		return formatter(minutes)
	end
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

local function getOverlayFns()
	return rawget(_G, "EmitSpriteOverlay"),
		rawget(_G, "ClearSpriteOverlay"),
		rawget(_G, "ReplaceSpriteOverlay")
end

local function clearOverlay()
	local _, clearer = getOverlayFns()
	if type(clearer) == "function" then
		clearer()
	end
end

local function replaceOverlaySprites(sprites)
	local emitter, _, replacer = getOverlayFns()
	if type(replacer) == "function" then
		replacer(sprites)
		return
	end

	clearOverlay()
	if type(emitter) ~= "function" then
		return
	end

	for _, sprite in ipairs(sprites or {}) do
		emitter(sprite.spriteId, sprite.cellX, sprite.cellY, sprite.targetCellHeight,
			sprite.targetCellWidth, sprite.anchor)
	end
end

local function buildMonsterOverlaySprite(monster, boxX, boxY, boxW, boxH)
	if not monster or not monster.sprite_ref or monster.sprite_ref == "" then
		return nil
	end

	if boxW < 1 or boxH < 1 then
		return nil
	end

	return {
		spriteId = monster.sprite_ref,
		cellX = boxX + (boxW / 2),
		cellY = boxY + (boxH - 1) / 2,
		targetCellHeight = boxH,
		targetCellWidth = boxW,
		anchor = "center",
	}
end

local function flushPendingWordCountLog()
	local utils = rawget(_G, "GlobalStatisticsUtils")
	if type(utils) ~= "table" then
		return
	end
	local flush = utils.flushPendingLog
	if type(flush) == "function" then
		flush()
	end
end

function Cmd.BattleSelectUI()
	local runner = rawget(_G, "RunWithMonsterBarHidden")

	local function runBattleSelect()
		flushPendingWordCountLog()

		local monsters = getMonsterBestiary()
		if #monsters == 0 then
			NonmodalMessage("No monsters are available in the bestiary.")
			return true
		end

		local maxQueueSlots = min(6, #monsters)
		local queueSelection = {}
		local selectedQueueSlot = 1
		local selectedMonster = 1
		local selectingMonster = false

		do
			local getBattleQueue = rawget(_G, "GetBattleSelectQueue")
			if getBattleQueue then
				local savedQueue = getBattleQueue(maxQueueSlots)
				if type(savedQueue) == "table" then
					for i = 1, maxQueueSlots do
						queueSelection[i] = savedQueue[i]
					end
				end
			end
		end

		local function clearSelections()
			for i = 1, maxQueueSlots do
				queueSelection[i] = nil
			end
		end

		local function persistSelections()
			local setBattleQueue = rawget(_G, "SetBattleSelectQueue")
			if setBattleQueue then
				setBattleQueue(queueSelection, maxQueueSlots)
			end
		end

		local function collectSelectedMonsters()
			local picked = {}
			for i = 1, maxQueueSlots do
				local monster = queueSelection[i]
				if monster then
					picked[#picked + 1] = monster
				end
			end
			return picked
		end

		local function findMonsterIndex(targetMonster)
			for i, monster in ipairs(monsters) do
				if monster == targetMonster then
					return i
				end
			end
			return 1
		end

		local function applySelectedQueue(picked)
			local setQueue = rawget(_G, "SetMonsterQueue")
			if setQueue then
				setQueue(picked)
				return
			end

			local clearQueue = rawget(_G, "ClearMonsterQueue")
			if clearQueue then
				clearQueue()
			end

			local queueMonster = rawget(_G, "QueueMonster")
			if queueMonster then
				for _, monster in ipairs(picked) do
					queueMonster(monster)
				end
			end
		end

		local function startBattle()
			local picked = collectSelectedMonsters()
			if #picked == 0 then
				NonmodalMessage("Select at least one monster first.")
				return false
			end
			applySelectedQueue(picked)
			NonmodalMessage("Battle started! Defeat monsters by writing.")
			return true
		end

		local function drawBattleBox(x, y, w, h, title, isSelected)
			local left = isSelected and "╔" or "┌"
			local right = isSelected and "╗" or "┐"
			local bottomLeft = isSelected and "╚" or "└"
			local bottomRight = isSelected and "╝" or "┘"
			local horizontal = string.rep(isSelected and "═" or "─", w)
			local vertical = isSelected and "║" or "│"
			local space = string.rep(" ", w)

			if isSelected then
				SetBright()
			else
				SetNormal()
			end

			Write(x - 1, y, " " .. left)
			Write(x + w + 1, y, right .. " ")
			Write(x - 1, y + h + 1, " " .. bottomLeft)
			Write(x + w + 1, y + h + 1, bottomRight .. " ")
			Write(x + 1, y, horizontal)
			Write(x + 1, y + h + 1, horizontal)

			for row = y + 1, y + h do
				Write(x - 1, row, " " .. vertical)
				Write(x + w + 1, row, vertical .. " ")
				Write(x + 1, row, space)
			end

			if title then
				CentreInField(x + 1, y, w, title)
			end
			SetNormal()
		end

		local function drawQueueSlot(x, y, w, h, slotIndex, monster, overlaySprites)
			local isTargetSlot = (slotIndex == selectedQueueSlot)
			drawBattleBox(x, y, w, h, string_format(" Slot %d ", slotIndex), isTargetSlot)

			local innerX = x + 1
			local innerY = y + 1
			local innerW = w
			local innerH = h

			if not monster then
				local emptyY = innerY + max(0, int(innerH / 2) - 1)
				SetDim()
				CentreInField(innerX, emptyY, innerW, "[ Empty ]")
				CentreInField(innerX, min(innerY + innerH - 1, emptyY + 1), innerW, "ENTER to choose")
				SetNormal()
				return
			end

			local infoLines = 2
			local spriteH = max(1, innerH - infoLines)
			local sprite = buildMonsterOverlaySprite(monster, innerX, innerY, innerW, spriteH)
			if sprite then
				overlaySprites[#overlaySprites + 1] = sprite
			end

			local infoY = min(innerY + innerH - 1, innerY + spriteH)
			SetNormal()
			CentreInField(innerX, infoY, innerW,
				string_format("Words: %d", monster.target_word_count or 0))
			CentreInField(innerX, min(innerY + innerH - 1, infoY + 1), innerW,
				string_format("Time: %s", formatMonsterTimeLimit(monster.target_time_limit_minutes)))
		end

		local function drawScreen()
			ResizeScreen()
			wg.clearscreen()

			local sw, sh = ScreenWidth, ScreenHeight
			local hborder = string.rep("─", sw)
			local innerX = 2
			local innerW = sw - 4
			local contentTop = 2
			local footerBorderY = sh - 3
			local contentBottom = footerBorderY - 2

			SetBright()
			Write(0, 0, hborder)
			CentreInField(0, 0, sw, " Battle Select ")
			Write(0, footerBorderY, hborder)
			SetNormal()

			local slotGap = 1
			local queueSlots = maxQueueSlots
			local slotY = contentTop
			local slotInnerW = int((innerW - (queueSlots - 1) * slotGap) / queueSlots) - 2
			if slotInnerW < 0 then
				slotGap = 0
				slotInnerW = int(innerW / queueSlots) - 2
			end
			slotInnerW = max(10, min(slotInnerW, 32))

			local footerY1 = sh - 2
			local footerY2 = sh - 1
			local monsterCardH = 3
			local monsterY = contentBottom - monsterCardH
			local dividerY = monsterY - 1
			local maxSlotInnerH = dividerY - slotY - 2
			local slotInnerH = min(BATTLE_SLOT_MAX_INNER_H, maxSlotInnerH)
			if slotInnerH < BATTLE_SLOT_MIN_INNER_H then
				slotInnerH = max(3, maxSlotInnerH)
			end

			local totalSlotsW = queueSlots * (slotInnerW + 2) + (queueSlots - 1) * slotGap
			local slotX = innerX + int((innerW - totalSlotsW) / 2)
			if slotX < innerX then
				slotX = innerX
			end

			local overlaySprites = {}
			for i = 1, queueSlots do
				local x = slotX + (i - 1) * (slotInnerW + 2 + slotGap)
				drawQueueSlot(x, slotY, slotInnerW, slotInnerH, i, queueSelection[i], overlaySprites)
			end
			replaceOverlaySprites(overlaySprites)
			SetNormal()

			if dividerY <= contentBottom then
				SetDim()
				Write(innerX, dividerY, string.rep("─", innerW))
				CentreInField(innerX, dividerY, innerW, " Available Monsters ")
				SetNormal()
			end

			local monsterGap = 1
			local monsterVisible = #monsters
			local minMonsterInnerW = 16
			while monsterVisible > 1 do
				local testW = int((innerW - (monsterVisible - 1) * monsterGap) / monsterVisible) - 2
				if testW >= minMonsterInnerW then
					break
				end
				monsterVisible = monsterVisible - 1
			end
			local monsterInnerW = int((innerW - (monsterVisible - 1) * monsterGap) / monsterVisible) - 2
			monsterInnerW = max(12, min(monsterInnerW, 20))
			local monsterStart = 1
			if selectedMonster > monsterVisible then
				monsterStart = selectedMonster - monsterVisible + 1
			end
			local maxMonsterStart = max(1, #monsters - monsterVisible + 1)
			if monsterStart > maxMonsterStart then
				monsterStart = maxMonsterStart
			end
			local visibleMonsterCount = min(monsterVisible, #monsters - monsterStart + 1)
			local monsterRowW = visibleMonsterCount * (monsterInnerW + 2) + (visibleMonsterCount - 1) * monsterGap
			local monsterX = innerX + int((innerW - monsterRowW) / 2)
			if monsterX < innerX then
				monsterX = innerX
			end

			for i = 1, visibleMonsterCount do
				local monsterIndex = monsterStart + i - 1
				local monster = monsters[monsterIndex]
				local x = monsterX + (i - 1) * (monsterInnerW + 2 + monsterGap)
				local isSelectedMonster = selectingMonster and (monsterIndex == selectedMonster)
				drawBattleBox(x, monsterY, monsterInnerW, monsterCardH, nil, isSelectedMonster)
				CentreInField(x + 1, monsterY + 1, monsterInnerW, GetBoundedString(monster.name or "", monsterInnerW))
				SetNormal()
				CentreInField(x + 1, monsterY + 2, monsterInnerW,
					string_format("Words: %d", monster.target_word_count or 0))
				CentreInField(x + 1, monsterY + 3, monsterInnerW,
					string_format("Time: %s", formatMonsterTimeLimit(monster.target_time_limit_minutes)))
			end

			if monsterStart > 1 then
				SetDim()
				Write(innerX, monsterY + 2, "<")
				SetNormal()
			end
			if (monsterStart + visibleMonsterCount - 1) < #monsters then
				SetDim()
				Write(innerX + innerW - 1, monsterY + 2, ">")
				SetNormal()
			end

			local footerMsg1
			local footerMsg2
			if selectingMonster then
				footerMsg1 = "LEFT/RIGHT: Select Monster   ENTER: Fill Slot"
				footerMsg2 = "ESC: Back to Queue   S: Start Battle   C: Clear"
			else
				footerMsg1 = "LEFT/RIGHT: Select Queue Slot   ENTER: Choose Monster"
				footerMsg2 = "S: Start Battle   C: Clear   ESC: Close"
			end
			CentreInField(0, footerY1, sw, footerMsg1)
			CentreInField(0, footerY2, sw, footerMsg2)

			wg.hidecursor()
			wg.sync()
		end

		while true do
			drawScreen()
			local key = GetChar()
			if key == "KEY_^C" then
				break
			elseif key == "KEY_ESCAPE" then
				if selectingMonster then
					selectingMonster = false
				else
					persistSelections()
					break
				end
			elseif (key == "KEY_RETURN") or (key == "KEY_ENTER") then
				if selectingMonster then
					queueSelection[selectedQueueSlot] = monsters[selectedMonster]
					persistSelections()
					selectingMonster = false
				else
					selectedMonster = findMonsterIndex(queueSelection[selectedQueueSlot])
					selectingMonster = true
				end
			elseif (key == "KEY_LEFT") or (key == "KEY_SLEFT") then
				if selectingMonster then
					selectedMonster = selectedMonster - 1
					if selectedMonster < 1 then
						selectedMonster = #monsters
					end
				else
					selectedQueueSlot = selectedQueueSlot - 1
					if selectedQueueSlot < 1 then
						selectedQueueSlot = maxQueueSlots
					end
				end
			elseif (key == "KEY_RIGHT") or (key == "KEY_SRIGHT") then
				if selectingMonster then
					selectedMonster = selectedMonster + 1
					if selectedMonster > #monsters then
						selectedMonster = 1
					end
				else
					selectedQueueSlot = selectedQueueSlot + 1
					if selectedQueueSlot > maxQueueSlots then
						selectedQueueSlot = 1
					end
				end
			elseif key == "KEY_HOME" then
				if selectingMonster then
					selectedMonster = 1
				else
					selectedQueueSlot = 1
				end
			elseif key == "KEY_END" then
				if selectingMonster then
					selectedMonster = #monsters
				else
					selectedQueueSlot = maxQueueSlots
				end
			elseif (key == "KEY_DELETE") or (key == "KEY_BACKSPACE") then
				if not selectingMonster then
					queueSelection[selectedQueueSlot] = nil
					persistSelections()
				end
			elseif (key == "s") or (key == "S") then
				if startBattle() then
					break
				end
			elseif (key == "c") or (key == "C") then
				clearSelections()
				persistSelections()
				selectingMonster = false
				local clearQueue = rawget(_G, "ClearMonsterQueue")
				if clearQueue then
					clearQueue()
				end
				NonmodalMessage("Monster queue cleared.")
			end
		end

		clearOverlay()
		QueueRedraw()
		return true
	end

	if type(runner) == "function" then
		return runner(runBattleSelect)
	end
	return runBattleSelect()
end
