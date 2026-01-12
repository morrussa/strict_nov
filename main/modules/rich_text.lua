local M = {}

local function hex_to_color(hex)
	local r = tonumber(hex:sub(1, 2), 16) / 255
	local g = tonumber(hex:sub(3, 4), 16) / 255
	local b = tonumber(hex:sub(5, 6), 16) / 255
	return vmath.vector4(r, g, b, 1)
end

-- 保险的手动清空函数（兼容所有 Lua 版本）
local function force_clear(t)
	if type(t) == "table" then
		for k in pairs(t) do
			t[k] = nil
		end
	end
end

function M.prepare_table(output_table)
	output_table.base = output_table.base or {}
	output_table.modal = output_table.modal or {}

	-- base
	output_table.base.chars = output_table.base.chars or {}
	output_table.base.glyph_positions = output_table.base.glyph_positions or {}
	force_clear(output_table.base.chars)
	force_clear(output_table.base.glyph_positions)

	-- modal
	local modals = {"shake_x", "shake_y", "colours", "wave", "wave_sped"}
	for _, name in ipairs(modals) do
		output_table.modal[name] = output_table.modal[name] or {}
		force_clear(output_table.modal[name])
	end
end

function M.parse_rich_text(input_str, output_table)
	M.prepare_table(output_table)  -- 每次解析前彻底清空

	local current_colour = vmath.vector4(1, 1, 1, 1)
	local current_shake_x = 0
	local current_shake_y = 0
	local current_wave = 0
	local current_wave_sped = 0

	local i = 1
	while i <= #input_str do
		local tag_start, tag_end, tag_key, tag_val = string.find(input_str, "<([%a_]+):([^>]+)>", i)

		if tag_start == i then
			if tag_key == "colour" then
				current_colour = hex_to_color(tag_val)
			elseif tag_key == "shake" then
				current_shake_x = tonumber(tag_val) or 0
				current_shake_y = tonumber(tag_val) or 0
			elseif tag_key == "shake_x" then
				current_shake_x = tonumber(tag_val) or 0
			elseif tag_key == "shake_y" then
				current_shake_y = tonumber(tag_val) or 0
			elseif tag_key == "wave" then
				current_wave = tonumber(tag_val) or 0
			elseif tag_key == "wave_sped" then
				current_wave_sped = tonumber(tag_val) or 0
			end
			i = tag_end + 1
		else
			local code = utf8.codepoint(input_str, i)
			local char = utf8.char(code)

			table.insert(output_table.base.chars, char)
			table.insert(output_table.modal.shake_x, current_shake_x)
			table.insert(output_table.modal.shake_y, current_shake_y)
			table.insert(output_table.modal.colours, current_colour)
			table.insert(output_table.modal.wave, current_wave)
			table.insert(output_table.modal.wave_sped, current_wave_sped)

			i = i + #char
		end
	end
end

return M