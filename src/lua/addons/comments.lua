-- © 2026 Alan Hernandez.
-- WordGrinder is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local GetWordText = wg.getwordtext
local bor = bit32.bor
local GetColorIndex = wg.getcolorindex
local commentColorIndex = GetColorIndex("cadmiumorange") or GetColorIndex("orange") or 208

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

	local function cb(self, token, payload)
		local text = GetWordText(payload.word)
		local markers = count_comment_markers(text)
		local is_comment = in_comment_before(payload)
		if (markers == 0) and (not is_comment) then
			return
		end

		local highlight = is_comment or (markers > 0)
		if highlight then
			payload.cstyle = bor(payload.cstyle, wg.DIM)
			payload.colorindex = commentColorIndex
		end
	end

	AddEventListener(Event.DrawWord, cb)
end
