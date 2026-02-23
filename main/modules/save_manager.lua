-- save_manager.lua
local M = {}
local rollback = require "main.modules.rollback"   -- 只用于记录

local APP_NAME = "30dayswithosagechan"
local FILE_NAME = "save_data"
local SAVE_PATH = sys.get_save_file(APP_NAME, FILE_NAME)

local _cache = {}

function M.load_all()
	local data = sys.load(SAVE_PATH)
	if not next(data) then
		_cache = {
			tea1 = 11,
			tea2 = 45,
			tea3 = 14,
			
			time_of_day_sec = 570,
			money = 2000,
			reason = 70,
			osagechan_mood = 3,
			osage_in_fangjian = 0,

			O0101_start = false
		}
		M.save_all()
	else
		_cache = data
	end
	print("已从"..SAVE_PATH.."读取")
	print("存档已加载至内存")
end

function M.save_all()
	local success = sys.save(SAVE_PATH, _cache)
	if success then
		print("内存数据已同步至硬盘")
	end
	return success
end

function M.set(key, value)
	local old = _cache[key]
	if old ~= value then
		rollback.record("save", key, old, value)  -- 只记录，不处理回滚
		_cache[key] = value
		print("数据更新: " .. key .. " = " .. tostring(value))
	else
		print("数据未变: " .. key)
	end
	msg.post("/status_menu#status_menu", "data_changed", { key = key, value = value })
end

function M.get(key)
	return _cache[key]
end

-- 回滚时使用的直接操作接口（不触发记录）
function M._set_direct(key, value)
	_cache[key] = value
end

return M