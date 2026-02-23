local M = {}

function M.parse_rich_text(input_str, output_table)
	-- 1. 清空并初始化
	output_table.chars = {}
	output_table.shake_x = {}
	output_table.shake_y = {}
	output_table.colours = {}
	output_table.wave = {}
	output_table.wave_sped = {}

	local current_colour = "ffffff"
	local current_shake_x = 0
	local current_shake_y = 0
	local current_wave = 0
	local current_wave_sped = 0

	local i = 1
	while i <= #input_str do
		-- 修正模式：使用括号捕获 key 和 value
		local tag_start, tag_end, tag_key, tag_val = string.find(input_str, "<([%a_]+):([^>]+)>", i)

		if tag_start == i then
			-- 情况 A：当前位置就是标签
			if tag_key == "colour" then
				current_colour = tag_val
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
			-- 情况 B：当前位置是普通文本，处理一个 UTF-8 字符
			-- 即使后面有标签，也要先把当前的字符存进去
			local code = utf8.codepoint(input_str, i)
			local char = utf8.char(code)

			table.insert(output_table.chars, char)
			table.insert(output_table.shake_x, current_shake_x)
			table.insert(output_table.shake_y, current_shake_y)
			table.insert(output_table.colours, current_colour)
			table.insert(output_table.wave,current_wave)
			table.insert(output_table.wave_sped,current_wave_sped)

			i = i + #char
		end
	end
end

return M