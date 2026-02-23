-- temp_var_manager.lua
local M = {}
local rollback = require "main.modules.rollback"

M.temp_vars = {
	test1 = true,
	test3 = 30,
	test2 = "keyboard",
	random1 = 0
}

function M.get(key) return M.temp_vars[key] end

function M.set(key, value)
	local old = M.temp_vars[key]
	if old ~= value then
		rollback.record("temp", key, old, value)
		M.temp_vars[key] = value
	end
end

-- 回滚时使用的直接操作接口
function M._set_direct(key, value)
	M.temp_vars[key] = value
end

return M