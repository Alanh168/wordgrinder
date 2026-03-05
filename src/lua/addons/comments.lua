-- © 2026 Alan Hernandez.
-- WordGrinder is licensed under the MIT open source license. See the COPYING
-- file in this distribution for the full text.

local GetWordText = wg.getwordtext
local bor = bit32.bor
local GetColorAttr = wg.getcolorattr
local commentColorAttr = GetColorAttr("cadmiumorange") or wg.RED

do
	local in_comment = false

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

	local function cb(self, token, payload)
		if payload.paragraphfirstword then
			in_comment = false
		end

		local text = GetWordText(payload.word)
		local markers = count_comment_markers(text)
		if (markers == 0) and (not in_comment) then
			return
		end

		local highlight = in_comment or (markers > 0)
		if highlight then
			payload.cstyle = bor(payload.cstyle, wg.DIM, commentColorAttr)
		end

		if (markers % 2) == 1 then
			in_comment = not in_comment
		end
	end

	AddEventListener(Event.DrawWord, cb)
end
