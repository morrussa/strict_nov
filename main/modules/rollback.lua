-- rollback.lua
-- 增量快照回滚模块，支持保存外部状态（如 typewriter 的 self）

local M = {}

-- 变更日志：每个条目 { source, key, old, new }
local log = {}
-- 快照栈：每个元素 { log_index, self }
local snapshots = {}
-- 当前游标位置
local current_snapshot_index = 0

-- 深拷贝函数（处理简单类型和表，忽略循环引用）
local function deep_copy(orig)
	if type(orig) ~= 'table' then return orig end
	local copy = {}
	for k, v in pairs(orig) do
		copy[deep_copy(k)] = deep_copy(v)
	end
	setmetatable(copy, deep_copy(getmetatable(orig)))
	return copy
end

-- 记录一次变更
function M.record(source, key, old, new)
	if old == new then return end
	table.insert(log, {source = source, key = key, old = old, new = new})
	-- print(string.format("[rollback] 记录变更: %s.%s = %s -> %s", source, key, tostring(old), tostring(new)))
end

-- 创建新快照点
-- @param self_state 可选，typewriter 的 self 对象，将被深拷贝保存
function M.push_snapshot(self_state)
	-- 如果当前游标不在栈顶，截断未来
	if current_snapshot_index < #snapshots then
		-- 删除 current_snapshot_index+1 到末尾的所有快照
		for i = #snapshots, current_snapshot_index+1, -1 do
			table.remove(snapshots)
		end
		-- 截断日志到当前快照的 log_index
		local current_log_index = snapshots[current_snapshot_index].log_index
		while #log > current_log_index do
			table.remove(log)
		end
		print(string.format("[rollback] 截断未来到快照 #%d，日志长度 %d", current_snapshot_index, current_log_index))
	end

	local self_copy = nil
	if self_state then
		self_copy = deep_copy(self_state)
	end
	table.insert(snapshots, {log_index = #log, self = self_copy})
	current_snapshot_index = #snapshots
	print(string.format("[rollback] 创建快照 #%d，日志长度 %d", #snapshots, #log))
	return true
end

-- 移动历史游标
-- @param steps 步数，正数为前进（如果有未来），负数为回滚（默认 -1）
-- 返回值: success, changes (变更列表), self_state (如果保存了), direction (1 前进, -1 回滚)
function M.move(steps)
	steps = steps or -1
	local target_index = current_snapshot_index + steps
	if target_index < 1 or target_index > #snapshots then
		print("[rollback] 无法移动 " .. steps .. " 步，超出范围（当前: " .. current_snapshot_index .. ", 总: " .. #snapshots .. "）")
		return false, {}, nil, 0
	end

	local from_log = snapshots[current_snapshot_index].log_index
	local target_log = snapshots[target_index].log_index
	local direction = steps > 0 and 1 or -1

	-- 收集变更（从低到高索引）
	local changes = {}
	local start_i = math.min(from_log, target_log) + 1
	local end_i = math.max(from_log, target_log)
	for i = start_i, end_i do
		table.insert(changes, log[i])
	end

	-- 对于回滚，反转changes顺序（从高到低）
	if direction < 0 then
		local rev_changes = {}
		for i = #changes, 1, -1 do
			table.insert(rev_changes, changes[i])
		end
		changes = rev_changes
	end

	-- 更新游标
	current_snapshot_index = target_index
	print(string.format("[rollback] 移动 %d 步到快照 #%d，应用 %d 条变更（方向: %d）", steps, target_index, #changes, direction))
	return true, changes, snapshots[target_index].self, direction
end

-- 调试函数：打印当前状态
function M.debug_info()
	print("=== rollback 调试信息 ===")
	print("当前游标位置:", current_snapshot_index)
	print("快照栈数量:", #snapshots)
	for i, s in ipairs(snapshots) do
		print(string.format("  快照 #%d: log_index=%d, has_self=%s", i, s.log_index, tostring(s.self ~= nil)))
	end
	print("日志长度:", #log)
	for i, entry in ipairs(log) do
		print(string.format("  日志 #%d: %s.%s = %s -> %s", i, entry.source, entry.key, tostring(entry.old), tostring(entry.new)))
	end
	print("========================")
end

-- 获取快照数量（用于外部判断）
function M.get_snapshot_count()
	return #snapshots
end

-- 获取日志长度（用于外部判断）
function M.get_log_length()
	return #log
end

-- 清空所有数据（用于测试或重置）
function M.clear()
	log = {}
	snapshots = {}
	current_snapshot_index = 0
	print("[rollback] 已清空所有数据")
end


function M.dump_snapshots()
	print("=== 快照文本内容 ===")
	for i, s in ipairs(snapshots) do
		local text = "无"
		if s.self and s.self.target_text then
			text = s.self.target_text
		elseif s.self and s.self.is_rich_text then
			text = "[富文本]"
		end
		print(string.format("快照 #%d: 行号=%d, 文本=%s", 
		i, s.self and s.self.current_line_index or 0, text))
	end
	print("====================")
end

-- rollback.lua 中添加
function M.get_latest_snapshot()
	if #snapshots == 0 then
		return nil
	end
	return snapshots[#snapshots]
end

-- 也可以添加获取当前游标位置的函数
function M.get_current_snapshot_index()
	return current_snapshot_index
end

-- 获取指定索引的快照
function M.get_snapshot(index)
	if index < 1 or index > #snapshots then
		return nil
	end
	return snapshots[index]
end

return M