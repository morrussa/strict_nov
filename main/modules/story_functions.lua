local save_manager = require("main.modules.save_manager")
local temp_var_manager = require("main.modules.temp_var_manager")

--推荐用story_functions，因为这玩意比B的msg.post安全，也不容易写出脏代码

local function goto_chat(chat)
	msg.post("/typewriter_core#typewriter", "start_dialogue", { target_id =chat })
end

local function non_modal_set(api, target, key, new_value)
	api._non_modal_stack = api._non_modal_stack or {}

	-- 1. 保存当前值（旧值）到栈中
	-- 注意：记录的是修改前的值
	table.insert(api._non_modal_stack, {
		target = target,    -- 目标表
		key = key,          -- 键名
		old_value = target[key] -- 旧值
	})

	-- 2. 执行修改
	target[key] = new_value
	print(string.format("[非模态] 临时修改 %s = %s", key, tostring(new_value)))
end
-- -------------------------------------------------------------------------
-- 工具函数
-- -------------------------------------------------------------------------


local M = {}


--测试函数
function M.test(api, arg)
	print("执行测试函数，对话速度已被修改。")
	api.story.talk_speed = tonumber(arg)
end


-- 生成随机数并设置到变量（支持 save_manager 或 temp_var_manager）
function M.random_set(api, arg)
	print("temp_var_manager type =", type(temp_var_manager))
	print("save_manager type =", type(save_manager))
	if not arg then
		print("random_set: 缺少参数！格式如 'my_var:1:10' 或 '#temp_var:5:20'")
		return
	end

	-- 解析 arg: var_name:min:max
	local parts = {}
	for part in arg:gmatch("[^:]+") do
		table.insert(parts, part)
	end
	if #parts < 3 then
		print("random_set: 参数格式错误！需要 'var_name:min:max'")
		return
	end

	local var_raw = parts[1]
	local min_val = tonumber(parts[2])
	local max_val = tonumber(parts[3])

	if not min_val or not max_val or min_val > max_val then
		print("random_set: min/max 必须是数字，且 min <= max")
		return
	end

	-- 生成随机整数（Lua 的 math.random(min, max) 返回整数）
	-- math.randomseed(os.time())  -- 可选：用时间种子确保随机性（但 Defold 中 os.time 可用）
	local random_value = math.random(min_val, max_val)

	-- 确定前缀和 manager
	local prefix = var_raw:sub(1,1)
	local var_name = (prefix == "$" or prefix == "#") and var_raw:sub(2) or var_raw
	local manager = (prefix == "#") and temp_var_manager or save_manager

	-- 设置变量
	manager.set(var_name, random_value)
	print(string.format("random_set: 设置 %s = %d (随机从 %d 到 %d)", var_raw, random_value, min_val, max_val))
end

--用法：
--F(random_set, my_var:1:10)  -- 设置 $my_var (save_manager) 到 1~10 的随机数
--F(random_set, #temp_var:5:20)  -- 设置 #temp_var (temp_var_manager) 到 5~20 的随机数

function M.set_option_style(api, anim_id)
	local target_anim = nil
	if not anim_id or anim_id == "default" then
		target_anim = nil
	else
		target_anim = anim_id
	end

	-- 使用 non_modal_set 修改 api.current_option_anim
	non_modal_set(api, api, "current_option_anim", target_anim)
	print("选项样式已设置为: " .. tostring(anim_id))
end


-- 用法: F(set_option_style, my_anim_hash) 或 F(set_option_style, default) (恢复默认)


return M