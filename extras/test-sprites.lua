-- On/Off Coloring:

localEvolutionWithNoShading = {
    {
        threshold = 250,
        sprite = {
                "     █████     ",
                "    █     █    ",
                "   ██ ██   █   ",
                " ██    ██  █   ",
                "█     ███   █  ",
                "████        █  ",
                " █          █  ",
                "  █████    █   ",
                "   ██      █   ",
                "  █ █   █   █  ",
                "  ███   ███ █  ",
                "    ██    █  █ ",
                "  ██  ████   █ ",
                " █ █  █ █ █ █ █",
                " ██████ ███████",
            },
    },
}

-- Braille Shading:

local SHADE_MAP = {
	["#"] = "█",
	["D"] = "▓",
	["M"] = "▒",
	["L"] = "░",
	["."] = " ",
}

local evolutionStagesWithBasicShading = {
	{
		threshold = 0,
		sprite = {
			".....####.....",
			"...##MMMM##...",
			"..#MMLLLLMM#..",
			".#MLLLLLLLLM#.",
			"#MLLLLLLLLLLM#",
			".#MLLLLLLLLM#.",
			"..#MMLLLLMM#..",
			"...##MMMM##...",
			".....####.....",
		},
	},
	{
		threshold = 0,
		sprite = {
			".....LLLLL.....",
			"....LDDDDDL....",
			"...LLDLLDDML...",
			".LLDDDDLLDML...",
			"LDDDDDLLLDDML..",
			"LLLLDDDDDDDML..",
			".LMMDDDDDDDML..",
			"..LLLLLDDMML...",
			"...LLMMMMLDL...",
			"..L#LDDDL#DDL..",
			"..LLLDDDLLLDL..",
			"....LLDDMMLDML.",
			"..LLDMLLLLDDML.",
			".L#L#ML.L#L#L#L",
			".LLLLLL.LLLLLLL",
		},
	},
	{
		threshold = 500,
		sprite = {
			"..########..",
			".#DDMMMMDD#.",
			".#DD.##.DD#.",
			"..#DMMMD#...",
			"#.#DDDDDD#..",
			"#D#DDMMDD#.#",
			".#.DDDDDD.#.",
			"..#DDMMDD#..",
			"...#DDDD#...",
			"...#DMMD#...",
			"..#DM..MD#..",
			"..#ML..LM#..",
			"..##....##..",
		},
	},
	{
		threshold = 1000,
		sprite = {
			"...########...",
			"..#MMDDDDMM#..",
			"..#MD.##.DM#..",
			"..#MDDMMDDM#..",
			".##DDDDDDDD##.",
			"#.#DDDDDDDD#.#",
			"#D#DDDDMMDD#D#",
			".#.DDDDDDDD.#.",
			"...#DDDDDD#...",
			"....#DDDD#....",
			"...#DDMMDD#...",
			"...#DM..MD#...",
			"..##ML..LM##..",
			"..##......##..",
		},
	},
	{
		threshold = 2000,
		sprite = {
			"....########....",
			"...#DDMMMMDD#...",
			"...#DM.##.MD#...",
			"...#DDMMMMDD#...",
			"..##DDDDDDDD##..",
			"#..#DDDDDDDD#..#",
			"#D.#DDMMMMDD#.D#",
			".#.#DDDDDDDD#.#.",
			"...#DDDDDDDD#...",
			"....#DDDDDD#....",
			"....#DDMMDD#....",
			"...#DM....MD#...",
			"...#ML....LM#...",
			"...##......##...",
		},
	},
}

-- Character evolution sprite
		local spriteTop = countY + BIG_DIGIT_HEIGHT + 1
		local spriteBottom = historyHeaderY - 1
		local availableHeight = spriteBottom - spriteTop
		local sprite, isSmall = getEvolutionSprite(todayCount, availableHeight)
		local spriteHeight = #sprite
		local spriteY = spriteTop + int((spriteBottom - spriteTop - spriteHeight) / 2)
		if spriteY < spriteTop then spriteY = spriteTop end
		-- For small sprites (containing Unicode), measure visual width
		local spriteWidth
		if isSmall then
			spriteWidth = utf8len(sprite[1] or "")
		else
			spriteWidth = #(sprite[1] or "")
		end
		local spriteX = innerX + int((innerW - spriteWidth) / 2)
		SetBright()
		for i, line in ipairs(sprite) do
			if spriteY + i - 1 < historyHeaderY then
				Write(spriteX, spriteY + i - 1, decodeSpriteRow(line))
			end
		end
		SetNormal()

local function decodeBrailleSpriteRow(encoded)
	local result = ""
	local i = 1
	local len = #encoded
	while i <= len do
		local b = encoded:byte(i)
		if b < 128 then
			-- ASCII: apply shade map
			local ch = encoded:sub(i, i)
			result = result .. (SHADE_MAP[ch] or ch)
			i = i + 1
		elseif b < 224 then
			-- 2-byte UTF-8 (e.g. box drawing)
			result = result .. encoded:sub(i, i + 1)
			i = i + 2
		elseif b < 240 then
			-- 3-byte UTF-8 (e.g. ▀ ▄ █ ▌ ▐ ░ ▒ ▓)
			result = result .. encoded:sub(i, i + 2)
			i = i + 3
		else
			-- 4-byte UTF-8
			result = result .. encoded:sub(i, i + 3)
			i = i + 4
		end
	end
	return result
end