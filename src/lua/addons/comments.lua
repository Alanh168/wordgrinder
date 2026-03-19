-- © 2026 Alan Hernandez.
-- WordGrinder is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local GetWordText = wg.getwordtext
local bor = bit32.bor
local GetColorIndex = wg.getcolorindex
local commentColorIndex = GetColorIndex("cadmiumorange") or GetColorIndex("orange") or 208
local toDoColorIndex = GetColorIndex("yellow") or GetColorIndex("brightyellow") or 226

do
	local function count_comment_markers(text)
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

	local function count_bracket_markers(text)
		local opens = select(2, text:gsub("%[", ""))
		local closes = select(2, text:gsub("%]", ""))
		return opens, closes
	end

	local function in_comment_before(payload)
		local paragraph = payload.paragraph
		local wn = payload.wn
		if not paragraph or not wn then
			return false
		end

		local count = 0
		for i = 1, wn - 1 do
			count = count + count_comment_markers(GetWordText(paragraph[i]))
		end
		return (count % 2) == 1
	end

	local function in_bracket_before(payload)
		local paragraph = payload.paragraph
		local wn = payload.wn
		if not paragraph or not wn then
			return false
		end

		local opens, closes = 0, 0
		for i = 1, wn - 1 do
			local o, c = count_bracket_markers(GetWordText(paragraph[i]))
			opens = opens + o
			closes = closes + c
		end
		return opens > closes
	end

	local function cb(self, token, payload)
		local text = GetWordText(payload.word)
		local markers = count_comment_markers(text)
		local is_comment = in_comment_before(payload)
		local open_brackets, close_brackets = count_bracket_markers(text)
		local is_to_do = in_bracket_before(payload)
		
		local highlight_comment = is_comment or (markers > 0)
		local highlight_to_do = is_to_do or (open_brackets > 0) or (close_brackets > 0)

		if not highlight_comment and not highlight_to_do then
			return
		end

		payload.cstyle = bor(payload.cstyle, wg.DIM)
		if highlight_to_do then
			payload.colorindex = toDoColorIndex
		elseif highlight_comment then
			payload.colorindex = commentColorIndex
		end
	end

	AddEventListener(Event.DrawWord, cb)
end
