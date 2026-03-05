-- Monster bestiary for WordGrinder's game mode.
-- Lua is used instead of JSON so no extra parser is required in core.

local monsters = {
	{
		name = "Paper Slime",
		sprite_ref = "",
		target_word_count = 120,
		target_time_limit_minutes = nil,
	},
	{
		name = "Ink Mite",
		sprite_ref = "",
		target_word_count = 180,
		target_time_limit_minutes = 10,
	},
	{
		name = "Count Daily",
		sprite_ref = "",
		target_word_count = 250,
		target_time_limit_minutes = 15,
	},
	{
		name = "Comma Wisp",
		sprite_ref = "",
		target_word_count = 320,
		target_time_limit_minutes = 20,
	},
	{
		name = "Plot Beetle",
		sprite_ref = "",
		target_word_count = 420,
		target_time_limit_minutes = nil,
	},
	{
		name = "Outline Hydra",
		sprite_ref = "",
		target_word_count = 550,
		target_time_limit_minutes = 30,
	},
	{
		name = "Revision Hound",
		sprite_ref = "",
		target_word_count = 700,
		target_time_limit_minutes = 35,
	},
	{
		name = "Chapter Ogre",
		sprite_ref = "",
		target_word_count = 900,
		target_time_limit_minutes = 45,
	},
	{
		name = "Deadline Drake",
		sprite_ref = "",
		target_word_count = 1200,
		target_time_limit_minutes = 60,
	},
	{
		name = "Final Draft Titan",
		sprite_ref = "",
		target_word_count = 1600,
		target_time_limit_minutes = 90,
	},
}

function GetMonsterBestiary()
	return monsters
end
