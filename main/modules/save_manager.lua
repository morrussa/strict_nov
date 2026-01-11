-- save_manager.lua

-- -------------------------------------------------------------------------
-- 预设
-- -------------------------------------------------------------------------
local M = {}

local APP_NAME = "30dayswithosagechan"
local FILE_NAME = "save_data"
local SAVE_PATH = sys.get_save_file(APP_NAME, FILE_NAME)

-- 1. 建立内存缓存，避免频繁读写硬盘
local _cache = {}

-- 2. 加载函数：只在游戏初始化或需要强制刷新时调用
function M.load_all()
	local data = sys.load(SAVE_PATH)
	-- 如果是第一次玩（没存档），则初始化默认值
	if not next(data) then
		_cache = {
			time_of_day_sec = 114514,
			money = 1919,
			reason = 70
		}
		M.save_all()
	else
		_cache = data
	end
	print("已从"..SAVE_PATH.."读取")
	print("存档已加载至内存")
end
-- -------------------------------------------------------------------------
-- 保存
-- -------------------------------------------------------------------------
function M.save_all()
	local success = sys.save(SAVE_PATH, _cache)
	if success then
		print("内存数据已同步至硬盘")
	end
	return success
end

function M.set(key, value)
	if _cache[key] ~= nil then
		_cache[key] = value
		print("数据更新: " .. key .. " = " .. tostring(value))
	else
		print("警告：尝试设置一个不存在的键: " .. tostring(key))
	end
	msg.post("/status_menu#status_menu", "data_changed", { key = key, value = value })
end

-- function M.add(key, amount)
-- 	if type(_cache[key]) == "number" then
-- 		_cache[key] = _cache[key] + amount
-- 		-- 可以在这里做逻辑边界限制
-- 		-- if key == "hp" and _cache[key] > 100 then _cache[key] = 100 end
-- 	end
-- 	msg.post("/status_menu#status_menu", "data_changed", { key = key, value = amount })
-- end

function M.get(key)
	return _cache[key]
end


return M