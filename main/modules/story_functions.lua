-- main/modules/story_functions.lua

local M = {}

function M.test(api, arg)
	print("执行测试函数，对话速度已被修改。")
	api.story.talk_speed = tonumber(arg)
end

return M