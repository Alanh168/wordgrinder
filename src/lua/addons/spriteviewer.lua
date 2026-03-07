-- Sprite Viewer UI for candidate and generated monster sprite PNGs.

local int = math.floor
local min = math.min
local max = math.max
local string_format = string.format
local string_rep = string.rep
local table_sort = table.sort
local Write = wg.write
local GetChar = wg.getchar
local GetBoundedString = wg.getboundedstring
local GetCwd = wg.getcwd or function() return nil end
local ReadDir = wg.readdir or function() return {} end
local Stat = wg.stat or function() return nil end
local SetNormal = wg.setnormal
local SetBright = wg.setbright
local SetDim = wg.setdim

local SPRITES_PER_PAGE = 4

local PAGE_DEFINITIONS = {
	{ label = "Original", rel_dir = "candidates" },
	{ label = "64x64", rel_dir = "generated/64x64" },
	{ label = "32x32", rel_dir = "generated/32x32" },
	{ label = "16x16", rel_dir = "generated/16x16" },
	{ label = "8x8", rel_dir = "generated/8x8" },
}

local function pathJoin(a, b)
	if a:sub(-1) == "/" then
		return a .. b
	end
	return a .. "/" .. b
end

local function getLeafStem(filename)
	return (filename:gsub("%.png$", ""))
end

local function formatDisplayName(stem)
	local label = stem:gsub("[-_]+", " ")
	return label
end

local function compareCasefold(a, b)
	return a:lower() < b:lower()
end

local function isDirectory(path)
	local attr = path and Stat(path)
	return attr and (attr.mode == "directory")
end

local function isFile(path)
	local attr = path and Stat(path)
	return attr and (attr.mode == "file")
end

local function getParentDir(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	return path:match("^(.*)[/\\][^/\\]+$")
end

local function isLikelySpriteRoot(path)
	if not isDirectory(path) then
		return false
	end
	return isDirectory(pathJoin(path, "candidates"))
		or isDirectory(pathJoin(path, "generated"))
		or isDirectory(pathJoin(path, "official"))
		or isFile(pathJoin(path, "formatted_sprites.lua"))
end

local function findSpriteRoot()
	local tried = {}
	local function addCandidate(paths, path)
		if type(path) == "string" and path ~= "" and not tried[path] then
			tried[path] = true
			paths[#paths + 1] = path
		end
	end

	local paths = {}
	local home = rawget(_G, "HOME") or os.getenv("HOME") or os.getenv("USERPROFILE")
	local configDir = rawget(_G, "CONFIGDIR")
	local formattedSpritesPath = os.getenv("WG_FORMATTED_SPRITES")

	addCandidate(paths, os.getenv("WG_SPRITE_ROOT"))
	addCandidate(paths, os.getenv("CRT_SPRITE_DIRECTORY"))
	addCandidate(paths, formattedSpritesPath and getParentDir(formattedSpritesPath))
	addCandidate(paths, configDir and pathJoin(configDir, "sprites"))
	addCandidate(paths, home and pathJoin(home, ".config/cool-retro-term/sprites"))
	addCandidate(paths, "extras/sprites")
	addCandidate(paths, "wordgrinder/extras/sprites")

	local cwd = GetCwd()
	addCandidate(paths, cwd and pathJoin(cwd, "extras/sprites"))
	addCandidate(paths, cwd and pathJoin(cwd, "wordgrinder/extras/sprites"))

	if debug and debug.getinfo then
		local info = debug.getinfo(1, "S")
		if info and type(info.source) == "string" and info.source:sub(1, 1) == "@" then
			local scriptPath = info.source:sub(2)
			local scriptDir = scriptPath:match("^(.*)[/\\][^/\\]+$")
			addCandidate(paths, scriptDir and (scriptDir .. "/../../../extras/sprites"))
		end
	end

	if home then
		local checkoutParents = {
			pathJoin(home, "repos"),
			pathJoin(home, "src"),
			pathJoin(home, "dev"),
			pathJoin(home, "code"),
		}
		for _, parent in ipairs(checkoutParents) do
			if isDirectory(parent) then
				local entries = ReadDir(parent)
				if type(entries) == "table" then
					table_sort(entries, compareCasefold)
					for _, name in ipairs(entries) do
						if name ~= "." and name ~= ".." then
							local checkout = pathJoin(parent, name)
							if isDirectory(checkout) then
								addCandidate(paths, pathJoin(checkout, "wordgrinder/extras/sprites"))
							end
						end
					end
				end
			end
		end
	end

	for _, path in ipairs(paths) do
		if isLikelySpriteRoot(path) then
			return path
		end
	end
	return nil
end

local function listPngFiles(dir)
	local files = ReadDir(dir)
	if type(files) ~= "table" then
		return {}
	end

	local pngs = {}
	for _, filename in ipairs(files) do
		if filename ~= "." and filename ~= ".." and filename:lower():match("%.png$") then
			local path = pathJoin(dir, filename)
			if isFile(path) then
				pngs[#pngs + 1] = filename
			end
		end
	end

	table_sort(pngs, compareCasefold)
	return pngs
end

local function readPngSize(path)
	local fp = io.open(path, "rb")
	if not fp then
		return nil, nil
	end
	local data = fp:read(24)
	fp:close()

	if not data or #data < 24 then
		return nil, nil
	end
	if data:sub(1, 8) ~= "\137PNG\r\n\26\n" then
		return nil, nil
	end

	local b = { data:byte(17, 24) }
	local width = b[1] * 16777216 + b[2] * 65536 + b[3] * 256 + b[4]
	local height = b[5] * 16777216 + b[6] * 65536 + b[7] * 256 + b[8]
	return width, height
end

local function buildVersion(root, filename, def)
	local stem = getLeafStem(filename)
	local path = pathJoin(pathJoin(root, def.rel_dir), filename)
	local exists = isFile(path)
	local width, height = nil, nil
	if exists then
		width, height = readPngSize(path)
	end
	return {
		label = def.label,
		filename = filename,
		path = path,
		rel_dir = def.rel_dir,
		sprite_id = def.rel_dir .. "/" .. stem,
		exists = exists and width and height,
		width = width,
		height = height,
	}
end

local function buildSpriteEntries(root)
	local entries = {}
	local filenames = listPngFiles(pathJoin(root, "candidates"))
	for _, filename in ipairs(filenames) do
		local stem = getLeafStem(filename)
		local versions = {}
		for _, def in ipairs(PAGE_DEFINITIONS) do
			versions[#versions + 1] = buildVersion(root, filename, def)
		end
		entries[#entries + 1] = {
			filename = filename,
			stem = stem,
			name = formatDisplayName(stem),
			versions = versions,
		}
	end
	return entries
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

local function buildOverlaySprite(version, boxX, boxY, boxW, boxH)
	if not version or not version.exists then
		return nil
	end

	local imgW = version.width or 0
	local imgH = version.height or 0
	if imgW < 1 or imgH < 1 or boxW < 1 or boxH < 1 then
		return nil
	end

	local targetH = min(boxH, (boxW * imgH) / imgW)
	if targetH <= 0 then
		return nil
	end

	local drawW = imgW * (targetH / imgH)
	return {
		spriteId = version.sprite_id,
		cellX = boxX + (boxW + drawW) / 2,
		cellY = boxY + (boxH - 1) / 2,
		targetCellHeight = targetH,
	}
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
		emitter(sprite.spriteId, sprite.cellX, sprite.cellY, sprite.targetCellHeight)
	end
end

local function drawSlotSeparator(x, y, w)
	SetDim()
	Write(x, y, string_rep("─", w))
	SetNormal()
end

local function drawSelectionBox(x, y, w, h, title, isSelected)
	local left = isSelected and "╔" or "┌"
	local right = isSelected and "╗" or "┐"
	local bottomLeft = isSelected and "╚" or "└"
	local bottomRight = isSelected and "╝" or "┘"
	local horizontal = string_rep(isSelected and "═" or "─", w)
	local vertical = isSelected and "║" or "│"
	local space = string_rep(" ", w)

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

local function drawListSlot(x, y, w, h, entry, isSelected)
	local previewW = min(36, max(16, int(w * 0.40)))
	local infoX = x + previewW + 2
	local infoW = max(10, w - previewW - 2)

	if isSelected then
		SetBright()
		Write(x - 1, y, ">")
	else
		SetNormal()
		Write(x - 1, y, " ")
	end

	drawSelectionBox(x, y, previewW - 2, h - 2, " Sprite ", isSelected)

	if isSelected then
		SetBright()
	else
		SetNormal()
	end
	Write(infoX, y, GetBoundedString(entry.name, infoW))

	SetNormal()
	Write(infoX, y + 1, GetBoundedString(entry.filename, infoW))

	local pageBits = {}
	for _, version in ipairs(entry.versions) do
		pageBits[#pageBits + 1] = version.exists and version.label or "-"
	end
	local pagesText = "Pages: " .. table.concat(pageBits, "  ")
	Write(infoX, y + 2, GetBoundedString(pagesText, infoW))

	if isSelected then
		SetBright()
	else
		SetDim()
	end
	Write(x, y + h - 1, string_rep("─", w))
	SetNormal()
end

local function drawMissingMessage(boxX, boxY, boxW, boxH, text)
	SetDim()
	CentreInField(boxX + 1, boxY + max(1, int(boxH / 2)), boxW, GetBoundedString(text, boxW))
	SetNormal()
end

local function getBattlePreviewBoxSize(sw, sh)
	local innerW = sw - 4
	local slotGap = 1
	local queueSlots = 6
	local slotInnerW = int((innerW - (queueSlots - 1) * slotGap) / queueSlots) - 2
	if slotInnerW < 0 then
		slotGap = 0
		slotInnerW = int(innerW / queueSlots) - 2
	end
	slotInnerW = max(10, min(slotInnerW, 24))

	local footerBorderY = sh - 3
	local contentBottom = footerBorderY - 2
	local contentTop = 2
	local monsterCardH = 3
	local monsterY = contentBottom - monsterCardH
	local dividerY = monsterY - 1
	local maxSlotInnerH = dividerY - contentTop - 2
	local slotInnerH = min(12, maxSlotInnerH)
	if slotInnerH < 8 then
		slotInnerH = max(6, maxSlotInnerH)
	end

	return slotInnerW, max(6, slotInnerH)
end

local function getListPreviewBoxSize(sw, sh)
	local contentTop = 2
	local contentBottom = sh - 4
	local contentH = contentBottom - contentTop
	local slotH = max(4, int(contentH / SPRITES_PER_PAGE))
	local innerW = sw - 4
	local previewW = min(36, max(16, int(innerW * 0.40))) - 2
	return max(14, previewW), max(4, slotH - 2)
end

local function findVersion(entry, label)
	for _, version in ipairs(entry.versions) do
		if version.label == label then
			return version
		end
	end
	return nil
end

local function drawDetailView(entry, versionIndex)
	ResizeScreen()
	wg.clearscreen()

	local sw, sh = ScreenWidth, ScreenHeight
	local hborder = string_rep("─", sw)
	local currentVersion = entry.versions[versionIndex]
	local statusVersion = findVersion(entry, "8x8") or currentVersion

	local statusW = min(16, max(12, int(sw * 0.18)))
	local statusH = 4
	local statusX = sw - statusW - 3
	local statusY = 2

	local leftW, leftH = getBattlePreviewBoxSize(sw, sh)
	local rightW, rightH = getListPreviewBoxSize(sw, sh)
	local sideTop = 6
	local sideBottom = sh - 5
	local leftX = 2
	local leftY = sideTop + max(0, int((sideBottom - sideTop - leftH) / 2))
	local rightY = sideTop + max(0, int((sideBottom - sideTop - rightH) / 2))
	if rightY < statusY + statusH + 2 then
		rightY = statusY + statusH + 2
	end
	local rightX = sw - rightW - 3

	local centerX = leftX + leftW + 4
	local centerY = sideTop
	local centerW = rightX - centerX - 4
	if centerW < 18 then
		centerW = sw - 8
		centerX = 2
		rightX = sw - rightW - 3
	end
	local centerH = max(8, sideBottom - centerY + 1)

	SetBright()
	Write(0, 0, hborder)
	CentreInField(0, 0, sw, string_format(" Sprite Viewer  [%s] ", entry.name))
	SetNormal()

	CentreInField(0, 2, sw,
		string_format("Version %d/%d: %s", versionIndex, #entry.versions, currentVersion.label))
	CentreInField(0, 3, sw, entry.filename)

	DrawTitledBox(statusX, statusY, statusW, statusH, "Status")
	DrawTitledBox(leftX, leftY, leftW, leftH, "Battle Box")
	DrawTitledBox(centerX, centerY, centerW, centerH, currentVersion.label)
	DrawTitledBox(rightX, rightY, rightW, rightH, "List Slot")

	local overlaySprites = {}

	local statusSprite = buildOverlaySprite(statusVersion, statusX + 1, statusY + 1, statusW, statusH)
	local statusRendered = statusSprite ~= nil
	if statusSprite then
		overlaySprites[#overlaySprites + 1] = statusSprite
	end
	if not statusRendered then
		drawMissingMessage(statusX, statusY, statusW, statusH, "[ missing 8x8 ]")
	end

	local leftSprite = buildOverlaySprite(currentVersion, leftX + 1, leftY + 1, leftW, leftH)
	local leftRendered = leftSprite ~= nil
	if leftSprite then
		overlaySprites[#overlaySprites + 1] = leftSprite
	end
	if not leftRendered then
		drawMissingMessage(leftX, leftY, leftW, leftH, "[ preview unavailable ]")
	end

	local centerSprite = buildOverlaySprite(currentVersion, centerX + 1, centerY + 1, centerW, centerH)
	local centerRendered = centerSprite ~= nil
	if centerSprite then
		overlaySprites[#overlaySprites + 1] = centerSprite
	end
	if not centerRendered then
		drawMissingMessage(centerX, centerY, centerW, centerH, "[ missing page image ]")
	end

	local rightSprite = buildOverlaySprite(currentVersion, rightX + 1, rightY + 1, rightW, rightH)
	local rightRendered = rightSprite ~= nil
	if rightSprite then
		overlaySprites[#overlaySprites + 1] = rightSprite
	end
	if not rightRendered then
		drawMissingMessage(rightX, rightY, rightW, rightH, "[ missing page image ]")
	end

	replaceOverlaySprites(overlaySprites)

	SetBright()
	Write(0, sh - 3, hborder)
	SetNormal()
	CentreInField(0, sh - 2, sw, "LEFT/RIGHT: Change Version   ENTER: Back")
	CentreInField(0, sh - 1, sw, "ESC or ^C: Close")

	wg.hidecursor()
	wg.sync()
end

local function drawListView(entries, page, selected)
	ResizeScreen()
	wg.clearscreen()

	local sw, sh = ScreenWidth, ScreenHeight
	local hborder = string_rep("─", sw)
	local totalPages = max(1, int((#entries + SPRITES_PER_PAGE - 1) / SPRITES_PER_PAGE))
	local firstIndex = page * SPRITES_PER_PAGE
	local lastIndex = min(#entries - 1, firstIndex + SPRITES_PER_PAGE - 1)
	local itemsOnPage = lastIndex - firstIndex + 1
	local contentTop = 2
	local contentBottom = sh - 4
	local contentH = max(1, contentBottom - contentTop)
	local slotH = max(5, int(contentH / max(1, itemsOnPage)))
	local innerX = 2
	local innerW = sw - 5
	local previewW = min(36, max(16, int(innerW * 0.40))) - 2

	SetBright()
	Write(0, 0, hborder)
	CentreInField(0, 0, sw, string_format(" Sprite Viewer  [Page %d/%d] ", page + 1, totalPages))
	SetNormal()

	local overlaySprites = {}
	for slot = 0, itemsOnPage - 1 do
		local entry = entries[firstIndex + slot + 1]
		if entry then
			local slotY = contentTop + slot * slotH
			local isSelected = (slot == selected)
			drawListSlot(innerX, slotY, innerW, slotH, entry, isSelected)
			local sprite = buildOverlaySprite(
				entry.versions[1],
				innerX + 1,
				slotY + 1,
				previewW,
				max(3, slotH - 2))
			if sprite then
				overlaySprites[#overlaySprites + 1] = sprite
			end
		end
	end

	replaceOverlaySprites(overlaySprites)

	SetBright()
	Write(0, sh - 3, hborder)
	SetNormal()
	CentreInField(0, sh - 2, sw, "UP/DOWN: Select   LEFT/RIGHT: Page   ENTER: View sprite")
	CentreInField(0, sh - 1, sw, "ESC or ^C: Close")

	wg.hidecursor()
	wg.sync()
end

function Cmd.SpriteViewerUI()
	local runner = rawget(_G, "RunWithMonsterBarHidden")
	local function runViewer()
		local spriteRoot = findSpriteRoot()
		if not spriteRoot then
			NonmodalMessage("Sprite Viewer could not find a sprite workspace.")
			return true
		end

		local entries = buildSpriteEntries(spriteRoot)
		if #entries == 0 then
			NonmodalMessage("No candidate sprite PNGs were found.")
			return true
		end

		local totalPages = max(1, int((#entries + SPRITES_PER_PAGE - 1) / SPRITES_PER_PAGE))
		local page = 0
		local selected = 0
		local inDetailView = false
		local versionIndex = 1

		while true do
			if inDetailView then
				local entry = entries[page * SPRITES_PER_PAGE + selected + 1]
				if entry then
					drawDetailView(entry, versionIndex)
				end

				local key = GetChar()
				if (key == "KEY_^C") or (key == "KEY_ESCAPE") then
					break
				elseif (key == "KEY_RETURN") or (key == "KEY_ENTER") then
					inDetailView = false
				elseif (key == "KEY_LEFT") or (key == "KEY_SLEFT") then
					versionIndex = versionIndex - 1
					if versionIndex < 1 then
						versionIndex = #PAGE_DEFINITIONS
					end
				elseif (key == "KEY_RIGHT") or (key == "KEY_SRIGHT") then
					versionIndex = versionIndex + 1
					if versionIndex > #PAGE_DEFINITIONS then
						versionIndex = 1
					end
				elseif key == "KEY_HOME" then
					versionIndex = 1
				elseif key == "KEY_END" then
					versionIndex = #PAGE_DEFINITIONS
				end
			else
				drawListView(entries, page, selected)
				local itemsOnPage = min(SPRITES_PER_PAGE, #entries - page * SPRITES_PER_PAGE)
				local key = GetChar()
				if (key == "KEY_^C") or (key == "KEY_ESCAPE") then
					break
				elseif (key == "KEY_RETURN") or (key == "KEY_ENTER") then
					inDetailView = true
					versionIndex = 1
				elseif (key == "KEY_UP") or (key == "KEY_SUP") then
					if selected > 0 then
						selected = selected - 1
					end
				elseif (key == "KEY_DOWN") or (key == "KEY_SDOWN") then
					if selected < itemsOnPage - 1 then
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

		clearOverlay()
		QueueRedraw()
		return true
	end

	if type(runner) == "function" then
		return runner(runViewer)
	end
	return runViewer()
end
