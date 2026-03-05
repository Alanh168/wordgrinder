-- Central color registry and helper API for WordGrinder.
-- This file is the single source of truth for named xterm-256 colors.
-- Color names are mapped from /Users/alanmhernandez/Desktop/color-names-to-rgb.csv
-- by nearest RGB match against the xterm-256 palette.

local floor = math.floor

local color_name_by_index = {}
local color_index_by_canonical_name = {}

local setcolorindex_native = wg.setcolorindex

local function canonicalise_name(name)
	if type(name) ~= "string" then
		return nil
	end
	return (name:lower():gsub("[^a-z0-9]+", ""))
end

local function register_color_name(index, name)
	color_name_by_index[index] = name
	local canonical = canonicalise_name(name)
	if canonical and (color_index_by_canonical_name[canonical] == nil) then
		color_index_by_canonical_name[canonical] = index
	end
end

local function register_alias(alias, index)
	local canonical = canonicalise_name(alias)
	if canonical then
		color_index_by_canonical_name[canonical] = index
	end
end

local csv_mapped_color_names = {
	[0] = "black",
	[1] = "maroon",
	[2] = "green",
	[3] = "olive",
	[4] = "navy",
	[5] = "purple",
	[6] = "teal",
	[7] = "silver",
	[8] = "gray",
	[9] = "red1",
	[10] = "green1",
	[11] = "yellow1",
	[12] = "blue",
	[13] = "magenta",
	[14] = "cyanaqua",
	[15] = "white",
	[16] = "black",
	[17] = "navy",
	[18] = "blue4",
	[19] = "blue3",
	[20] = "blue3",
	[21] = "blue",
	[22] = "darkgreen",
	[23] = "deepskyblue4",
	[24] = "deepskyblue4",
	[25] = "deepskyblue4",
	[26] = "dodgerblue3",
	[27] = "dodgerblue2",
	[28] = "green4",
	[29] = "springgreen3",
	[30] = "turquoise4",
	[31] = "deepskyblue3",
	[32] = "deepskyblue3",
	[33] = "dodgerblue1",
	[34] = "green3",
	[35] = "emeraldgreen",
	[36] = "manganeseblue",
	[37] = "manganeseblue",
	[38] = "deepskyblue2",
	[39] = "deepskyblue1",
	[40] = "green3",
	[41] = "springgreen2",
	[42] = "turquoiseblue",
	[43] = "cyan3",
	[44] = "darkturquoise",
	[45] = "turquoise2",
	[46] = "green1",
	[47] = "springgreen1",
	[48] = "springgreen",
	[49] = "mediumspringgreen",
	[50] = "cyan2",
	[51] = "cyanaqua",
	[52] = "darkmaroon",
	[53] = "indigo",
	[54] = "indigo",
	[55] = "purple4",
	[56] = "purple3",
	[57] = "blueviolet",
	[58] = "orange4",
	[59] = "gray37",
	[60] = "mediumpurple4",
	[61] = "slateblue3",
	[62] = "slateblue3",
	[63] = "royalblue1",
	[64] = "chartreuse4",
	[65] = "darkseagreen4",
	[66] = "paleturquoise4",
	[67] = "steelblue",
	[68] = "steelblue3",
	[69] = "cornflowerblue",
	[70] = "chartreuse3",
	[71] = "sgichartreuse",
	[72] = "cadetblue",
	[73] = "cadetblue",
	[74] = "skyblue3",
	[75] = "steelblue1",
	[76] = "chartreuse3",
	[77] = "sgichartreuse",
	[78] = "seagreen3",
	[79] = "aquamarine3",
	[80] = "mediumturquoise",
	[81] = "steelblue1",
	[82] = "chartreuse2",
	[83] = "seagreen2",
	[84] = "seagreen1",
	[85] = "seagreen1",
	[86] = "aquamarine1",
	[87] = "darkslategray2",
	[88] = "red4",
	[89] = "deeppink4",
	[90] = "magenta4",
	[91] = "magenta4",
	[92] = "darkviolet",
	[93] = "darkviolet",
	[94] = "orange4",
	[95] = "lightpink4",
	[96] = "plum4",
	[97] = "mediumpurple3",
	[98] = "mediumpurple3",
	[99] = "slateblue1",
	[100] = "yellow4",
	[101] = "wheat4",
	[102] = "gray53",
	[103] = "lightslategray",
	[104] = "mediumpurple",
	[105] = "lightslateblue",
	[106] = "yellow4",
	[107] = "sgichartreuse",
	[108] = "darkseagreen",
	[109] = "sgilightblue",
	[110] = "lightskyblue3",
	[111] = "skyblue2",
	[112] = "chartreuse2",
	[113] = "darkolivegreen3",
	[114] = "palegreen3",
	[115] = "darkseagreen3",
	[116] = "darkslategray3",
	[117] = "skyblue1",
	[118] = "chartreuse1",
	[119] = "palegreen2",
	[120] = "palegreen2",
	[121] = "palegreen1",
	[122] = "aquamarine1",
	[123] = "darkslategray1",
	[124] = "red3",
	[125] = "deeppink4",
	[126] = "mediumvioletred",
	[127] = "magenta3",
	[128] = "darkviolet",
	[129] = "darkviolet",
	[130] = "darkorange3",
	[131] = "indianred",
	[132] = "hotpink3",
	[133] = "mediumorchid3",
	[134] = "mediumorchid",
	[135] = "mediumpurple2",
	[136] = "darkgoldenrod",
	[137] = "lightsalmon3",
	[138] = "rosybrown",
	[139] = "gray63",
	[140] = "mediumpurple2",
	[141] = "mediumpurple1",
	[142] = "gold3",
	[143] = "darkkhaki",
	[144] = "navajowhite3",
	[145] = "gray69",
	[146] = "lightsteelblue3",
	[147] = "lightsteelblue",
	[148] = "yellow3",
	[149] = "darkolivegreen3",
	[150] = "darkseagreen3",
	[151] = "darkseagreen2",
	[152] = "lightcyan3",
	[153] = "lightskyblue1",
	[154] = "greenyellow",
	[155] = "darkolivegreen2",
	[156] = "palegreen1",
	[157] = "darkseagreen2",
	[158] = "mint",
	[159] = "paleturquoise1",
	[160] = "red3",
	[161] = "deeppink3",
	[162] = "deeppink3",
	[163] = "magenta3",
	[164] = "magenta3",
	[165] = "magenta2",
	[166] = "darkorange3",
	[167] = "indianred",
	[168] = "hotpink3",
	[169] = "hotpink2",
	[170] = "orchid",
	[171] = "mediumorchid1",
	[172] = "orange3",
	[173] = "lightsalmon3",
	[174] = "lightpink3",
	[175] = "pink3",
	[176] = "plum3",
	[177] = "violet",
	[178] = "gold3",
	[179] = "melon",
	[180] = "tan",
	[181] = "mistyrose3",
	[182] = "thistle3",
	[183] = "plum2",
	[184] = "yellow3",
	[185] = "banana",
	[186] = "lightgoldenrod2",
	[187] = "lightyellow3",
	[188] = "gray84",
	[189] = "lightsteelblue1",
	[190] = "yellow2",
	[191] = "darkolivegreen1",
	[192] = "darkolivegreen1",
	[193] = "darkseagreen1",
	[194] = "honeydew2",
	[195] = "lightcyan1",
	[196] = "red1",
	[197] = "deeppink2",
	[198] = "deeppink1",
	[199] = "deeppink1",
	[200] = "magenta2",
	[201] = "magenta",
	[202] = "cadmiumorange",
	[203] = "indianred1",
	[204] = "indianred1",
	[205] = "hotpink",
	[206] = "hotpink",
	[207] = "mediumorchid1",
	[208] = "darkorange",
	[209] = "salmon1",
	[210] = "lightcoral",
	[211] = "palevioletred1",
	[212] = "orchid2",
	[213] = "orchid1",
	[214] = "orange1",
	[215] = "sandybrown",
	[216] = "lightsalmon1",
	[217] = "lightpink1",
	[218] = "pink1",
	[219] = "plum1",
	[220] = "gold1",
	[221] = "banana",
	[222] = "lightgoldenrod2",
	[223] = "navajowhite1",
	[224] = "mistyrose1",
	[225] = "thistle1",
	[226] = "yellow1",
	[227] = "lightgoldenrod1",
	[228] = "khaki1",
	[229] = "wheat1",
	[230] = "cornsilk1",
	[231] = "white",
	[232] = "gray3",
	[233] = "gray7",
	[234] = "gray11",
	[235] = "gray15",
	[236] = "gray19",
	[237] = "gray23",
	[238] = "gray27",
	[239] = "gray31",
	[240] = "gray35",
	[241] = "gray39",
	[242] = "gray42",
	[243] = "gray46",
	[244] = "gray",
	[245] = "gray54",
	[246] = "gray58",
	[247] = "gray62",
	[248] = "gray66",
	[249] = "gray70",
	[250] = "gray74",
	[251] = "gray78",
	[252] = "gray82",
	[253] = "gray86",
	[254] = "gray90",
	[255] = "gray93",
}

for index = 0, 255 do
	register_color_name(index, csv_mapped_color_names[index])
end

register_alias("grey", 8)
register_alias("darkgrey", 8)
register_alias("darkgray", 8)
register_alias("lightgrey", 7)
register_alias("lightgray", 7)
register_alias("orange", 208)
register_alias("darkorange", 130)
register_alias("beige", 223)

local function resolve_color_index(color)
	if type(color) == "number" then
		local index = floor(color)
		if (index >= 0) and (index <= 255) then
			return index
		end
		return nil
	end

	local canonical = canonicalise_name(color)
	if not canonical then
		return nil
	end
	return color_index_by_canonical_name[canonical]
end

function wg.getcolorname(index)
	if type(index) ~= "number" then
		return nil
	end
	index = floor(index)
	if (index < 0) or (index > 255) then
		return nil
	end
	return color_name_by_index[index]
end

function wg.getcolorindex(name)
	return resolve_color_index(name)
end

function wg.setcolor(color)
	local index = resolve_color_index(color)
	if index == nil then
		return false
	end

	return setcolorindex_native(index)
end

wg.COLOR_NAME_BY_INDEX = color_name_by_index
