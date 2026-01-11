-- 用来管理运行时不存储的变量的，当然设计里你确实可以一整个全部丢存档里然后疯狂的保存也没什么问题
local M = {}

-- 这里存放不需要写入存档的临时数据
M.temp_vars = {
	test1 = true,
	test3 = 30,
	test2 = "keyboard"
}

function M.get(key) return M.temp_vars[key] end
function M.set(key, value) M.temp_vars[key] = value end

-- function M.add(key,amount)
-- 	local amount2 = amount
-- 	local val = M.temp_vars[key] or 0
-- 	if type(val) == "number" and type(amount2) == "number" then
-- 		M.temp_vars[key] = val + amount
-- 		print("临时变量“"..key.."”增加了:"..tostring(amount).."，现在是"..tostring(val + amount))
-- 	else
-- 		print("有笨蛋试图加减非数字")
-- 	end
-- end
-- 
-- function M.muti(key,amount)
-- 	local amount2 = amount
-- 	local val = M.temp_vars[key] or 0
-- 	if type(val) == "number" and type(amount2) == "number" then
-- 		M.temp_vars[key] = val + amount
-- 		print("临时变量“"..key.."”增加了:"..tostring(amount).."，现在是"..tostring(val + amount))
-- 	else
-- 		print("有笨蛋试图加减非数字")
-- 	end
-- end

return M