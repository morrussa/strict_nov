-- typewriter.lua
local rtext_parser = require("main.modules.rich_text")
local temp_var_manager = require("main.modules.temp_var_manager")
local save_manager = require("main.modules.save_manager")
local story_functions = require("main.modules.story_functions")
local rollback = require("main.modules.rollback")

local total_timer = 0
-- -------------------------------------------------------------------------
-- 1. 辅助工具
-- -------------------------------------------------------------------------
local function check_and_index(index_table, key, line_num, type_label)
    if index_table[key] then
        print(string.format("！！！数据错误：检测到重复的%s索引 [%s]！原行号：%d，新行号：%d", 
        type_label, tostring(key), index_table[key], line_num))
        return false
    else
        index_table[key] = line_num
        print(string.format("已建立%s索引 %s -> 行号%d", type_label, tostring(key), line_num))
        return true
    end
end

local function left(text, count)
    if count <= 0 then return "" end
    return utf8.sub(text, 1, count)
end

local function auto_warp(text, threshold)
    local result = ""
    local count = 0
    for p in utf8.next, text do
        local next_p = utf8.next(text, p)
        local char = text:sub(p, (next_p or #text + 1) - 1)

        if char == "\n" then
            count = 0
        else
            count = count + 1
        end

        result = result .. char

        if count >= threshold then
            result = result .. "\n"
            count = 0
        end
    end
    return result
end

-- -------------------------------------------------------------------------
-- 1.1逻辑对比封装
-- -------------------------------------------------------------------------
local function evaluate_condition(condition_str)
    if not condition_str or condition_str == "" then return true end

    local expr = condition_str:match("%((.+)%)") or condition_str
    local conditions = {}
    for part in expr:gmatch("[^&]+") do
        table.insert(conditions, part)
    end

    for _, cond in ipairs(conditions) do
        local var_raw, op, val_raw = cond:match("([%$#]?[%w_]+)%s*([<>=!]+)%s*([%w_]+)")

        if var_raw and op and val_raw then
            local prefix = var_raw:sub(1,1)
            local key = (prefix == "$" or prefix == "#") and var_raw:sub(2) or var_raw
            local manager = (prefix == "#") and temp_var_manager or save_manager

            local current_val = manager.get(key)
            local target_val = tonumber(val_raw) or (val_raw == "true" and true) or (val_raw == "false" and false) or val_raw

            local result = false
            if op == "==" then result = (current_val == target_val)
            elseif op == "<>" or op == "!=" then result = (current_val ~= target_val)
            elseif op == ">" then result = (tonumber(current_val) or 0) > (tonumber(target_val) or 0)
            elseif op == "<" then result = (tonumber(current_val) or 0) < (tonumber(target_val) or 0)
            elseif op == ">=" then result = (tonumber(current_val) or 0) >= (tonumber(target_val) or 0)
            elseif op == "<=" then result = (tonumber(current_val) or 0) <= (tonumber(target_val) or 0)
            end

            if not result then return false end
        end
    end
    return true
end
-- -------------------------------------------------------------------------
-- 1.2 文本变量解析
-- -------------------------------------------------------------------------
local function lookup_variable(var_content)
    local clean_var = var_content:match("^%s*(.-)%s*$")
    if clean_var == "" then return nil, "空变量名" end

    local prefix = clean_var:sub(1,1)
    local key
    local manager

    if prefix == "#" then
        manager = temp_var_manager
        key = clean_var:sub(2)
    elseif prefix == "$" then
        manager = save_manager
        key = clean_var:sub(2)
    else
        return nil, "缺少前缀 # 或 $"
    end

    local value = manager.get(key)
    if value == nil then
        return nil, "变量未找到"
    end

    return value, nil, manager, key   -- 返回值和额外信息（如果需要）
end

local function parse_text_variables(text)
    if not text then return "" end

    local result = text:gsub("<!(.-)>", function(var_content)
        local value, err = lookup_variable(var_content)
        if value == nil then
            print("警告：文本变量解析失败，" .. err .. " [" .. var_content .. "]")
            return ""
        end
        return tostring(value)   -- 纯文本插入
    end)

    return result
end

local function replace_variables_for_lua(str)
    return (str:gsub("<!(.-)>", function(var_content)
        local value, err = lookup_variable(var_content)
        if value == nil then
            print("警告：B命令变量解析失败，" .. err .. " [" .. var_content .. "]")
            return "nil"
        end

        -- 转换为 Lua 字面量
        local t = type(value)
        if t == "number" then
            return tostring(value)
        elseif t == "boolean" then
            return value and "true" or "false"
        elseif t == "string" then
            -- 转义双引号和反斜杠
            local escaped = value:gsub('\\', '\\\\'):gsub('"', '\\"')
            return '"' .. escaped .. '"'
        else
            print("警告：B命令变量类型不支持转换为字面量：" .. t)
            return "nil"
        end
    end))
end
-- -------------------------------------------------------------------------
-- 1.3
-- -------------------------------------------------------------------------
local function clear_non_modal_state(self)
    if not self._non_modal_stack or #self._non_modal_stack == 0 then return end

    print("[非模态] 离开O块，还原变量...")
    for i = #self._non_modal_stack, 1, -1 do
        local item = self._non_modal_stack[i]
        item.target[item.key] = item.old_value
        print(string.format("  -> 还原 %s = %s", item.key, tostring(item.old_value)))
    end

    self._non_modal_stack = {}
end
-- -------------------------------------------------------------------------
-- 1.5选项实现
-- -------------------------------------------------------------------------
local option_instances = {}

-- 修改：只传递索引号
local function create_option(self, text, index)
    local pos = vmath.vector3(320, 330 - (index * 50), 0)
    -- 只传递数字索引，这是合法的 property 类型
    local p = factory.create("#options_factory", pos, nil, { option_index = index })

    local text_processed = parse_text_variables(text)
    label.set_text(msg.url(nil, p, "options_label"), text_processed) 
    local buttom_anim =  self.current_option_anim or "选项"
    sprite.play_flipbook(msg.url(nil, p, "options_button"),buttom_anim)

    table.insert(option_instances, p)
end

local function clear_options()
    for _, instance in ipairs(option_instances) do
        go.delete(instance)
    end
    option_instances = {}
end
-- -------------------------------------------------------------------------
-- 1.75 富文本
-- -------------------------------------------------------------------------
local rich_text_table = {}
local glyph_instances = {}
local glyph_positions = {}

local function hex_to_color(hex)
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return vmath.vector4(r, g, b, 1)
end

local function clear_glyphs()
    for _, p in ipairs(glyph_instances) do
        go.delete(p)
    end
    glyph_instances = {}
    glyph_positions = {}
end

local function render_rich_char(self,index)
    local col = (index - 1)%self.story.max_warp
    local row = math.floor((index-1)/self.story.max_warp)

    local pos = vmath.vector3(self.story.r_base_x + (col*self.story.r_kerning),self.story.r_base_y - (row*self.story.r_leading),1)

    local p = factory.create("#glyph_factory", pos)
    local label_url = msg.url(nil, p, "glyph_instance")

    local color_vec = hex_to_color(rich_text_table.colours[index])
    label.set_text(label_url, rich_text_table.chars[index])
    go.set(label_url,"color",color_vec)
    table.insert(glyph_instances, p)
    table.insert(glyph_positions,pos)
end


-- -------------------------------------------------------------------------
-- 2. 解析核心
-- -------------------------------------------------------------------------
local dialogue_data = {}
local o_index = {}
local a_index = {}

local function load_dialogue()
    local sub_event_map = {}
    local sub_path = "/dialogue/se.mol_sub"
    local sub_data, sub_err = sys.load_resource(sub_path)
    if sub_data then
        print("--- 开始解析子事件文件---")
        local current_tag = nil
        local current_lines = {}
        for line in sub_data:gmatch("[^\r\n]+") do
            line = line:gsub("^%s+", "")
            if line ~= "" then
                if line:sub(1,1) == "!" then
                    if current_tag then
                        sub_event_map[current_tag] = current_lines
                    end
                    current_tag = line
                    current_lines = {}
                else
                    if current_tag then
                        table.insert(current_lines, line)
                    end
                end
            end
        end
        if current_tag then
            sub_event_map[current_tag] = current_lines
        end
    else
        print("子事件文件加载失败：" .. (sub_err or "未知错误"))
    end

    local path = "/dialogue/dialogue.mol"
    local data, error = sys.load_resource(path)
    local expanded_lines = {}

    if data then
        print("--- 开始对话文件展开 ---")
        for line in data:gmatch("[^\r\n]+") do
            line = line:gsub("^%s+", "")

            if line ~= "" then
                if line:sub(1,1) == "!" then
                    local tag = line
                    local insert_lines = sub_event_map[tag]
                    if insert_lines then
                        for _, sub_line in ipairs(insert_lines) do
                            sub_line = sub_line:gsub("%s+$", "")
                            if sub_line ~= "" then
                                table.insert(expanded_lines, sub_line)
                            end
                        end
                    end
                else
                    table.insert(expanded_lines, line)
                end
            end
        end

        print("--- 开始建立索引 ---")
        dialogue_data = expanded_lines
        for line_num, line in ipairs(dialogue_data) do
            if line:sub(1,1) == "O" then
                local key = hash(line)
                check_and_index(o_index, key, line_num, "对话块(O)")
            elseif line:sub(1,1) == "A" then
                local key = hash(line)
                check_and_index(a_index, key, line_num, "锚点(A)")
            end
        end
        print("--- 索引建立完成 ---")
    else
        print("对话文件加载失败：" .. (error or "未知错误"))
    end
end

-- -------------------------------------------------------------------------
-- 跳转辅助函数
-- -------------------------------------------------------------------------
local function handle_jump(self, target_str)
    if target_str:sub(1, 2) == "GO" then
        local name = target_str:sub(3)
        local target_key = hash("O" .. name)
        local target_line = o_index[target_key]
        if target_line then
            self.current_line_index = target_line
            self.scope_end_index = nil
            print("GO跳转 -> O" .. name .. " 行号：" .. target_line)
            return true
        else
            print("错误 GO：找不到 O锚点 O" .. name)
        end

    elseif target_str:sub(1, 2) == "GA" then
        local name = target_str:sub(3)
        local target_key = hash("A" .. name)
        local target_line = a_index[target_key]
        if target_line then
            self.current_line_index = target_line
            self.scope_end_index = nil
            print("GA跳转 -> A" .. name .. " 行号：" .. target_line)
            return true
        else
            print("错误 GA：找不到 A锚点 A" .. name)
        end
    else
        return false
    end
end

local function process_commands(self)
    while true do
        local line = dialogue_data[self.current_line_index]
        if not line then break end

        if self.scope_end_index and self.current_line_index >= self.scope_end_index then
            print("选项分支作用域结束，跳转到结束行 " .. self.scope_end_index)
            self.current_line_index = self.scope_end_index
            self.scope_end_index = nil
        end

        local active = true
        if #self.condition_stack > 0 then
            active = self.condition_stack[#self.condition_stack].active
        end

        if active then
            local is_skip = false

            if line:sub(1,1) == "?" then
                if line:match("^%?IF%s*%(") or line:match("^%?IF$") or
                line:match("^%?ELSIF%s*%(") or
                line:match("^%?ELSE$") or
                line:match("^%?ENDIF$") or line:match("^%?END$") then

                    if line:match("^%?IF") then
                        local condition = line:match("^%?IF%s*%((.+)%)%s*$") or line:match("^%?IF%s*$")
                        if not condition then condition = "false" end
                        local cond_result = evaluate_condition(condition)
                        table.insert(self.condition_stack, {active = cond_result, executed = cond_result})
                        self.current_line_index = self.current_line_index + 1

                    elseif line:match("^%?ELSIF") then
                        if #self.condition_stack > 0 then
                            local top = self.condition_stack[#self.condition_stack]
                            if top.executed then
                                top.active = false
                            else
                                local condition = line:match("^%?ELSIF%s*%((.+)%)%s*$")
                                local cond_result = condition and evaluate_condition(condition) or false
                                top.active = cond_result
                                if cond_result then top.executed = true end
                            end
                        end
                        self.current_line_index = self.current_line_index + 1

                    elseif line:match("^%?ELSE$") then
                        if #self.condition_stack > 0 then
                            local top = self.condition_stack[#self.condition_stack]
                            if top.executed then top.active = false else top.active = true; top.executed = true end
                        end
                        self.current_line_index = self.current_line_index + 1

                    elseif line:match("^%?ENDIF$") or line:match("^%?END$") then
                        if #self.condition_stack > 0 then table.remove(self.condition_stack) end
                        self.current_line_index = self.current_line_index + 1
                    end
                else
                    local condition,rest = line:match("^?%((.-)%)(.*)")
                    if condition then
                        if evaluate_condition(condition) then
                            line = rest:gsub("^%s*", "")
                            is_skip = false
                        else
                            self.current_line_index = self.current_line_index + 1
                            is_skip = true
                        end
                    else
                        self.current_line_index = self.current_line_index + 1
                        is_skip = true
                    end
                end
            end

            if not is_skip then
                if line:sub(1, 2) == "<<" then
                    print("遇到 << ，结束选项块结构")
                    self.scope_end_index = nil 
                    self.current_line_index = self.current_line_index + 1

                elseif line:sub(1,1) == ">" then
                    clear_options()
                    self.is_typing = false
                    self.is_selecting = true
                    local options_to_create = {}
                    local scan_index = self.current_line_index
                    local block_end_index = scan_index

                    while true do
                        local scan_line = dialogue_data[scan_index]
                        if not scan_line then break end

                        if scan_line:sub(1, 2) == "<<" then
                            block_end_index = scan_index
                            break
                        end

                        if scan_line:sub(1,1) == ">" then
                            local is_double = scan_line:sub(2, 2) == ">"
                            local content = is_double and scan_line:sub(3) or scan_line:sub(2)

                            local opt_data = {}

                            if is_double then
                                local text, cmd = content:match("^(.-)#(.*)$")
                                if text and cmd then
                                    opt_data.text = text
                                    opt_data.type = "immediate"
                                    opt_data.command = cmd
                                    table.insert(options_to_create, opt_data)
                                end
                            else
                                opt_data.text = content
                                opt_data.type = "branch"
                                opt_data.start_line = scan_index + 1

                                local sub_scan = scan_index + 1
                                while true do
                                    local sub_line = dialogue_data[sub_scan]
                                    if not sub_line then break end
                                    if sub_line:sub(1,1) == ">" or sub_line:sub(1,2) == "<<" then
                                        opt_data.end_line = sub_scan
                                        break
                                    end
                                    sub_scan = sub_scan + 1
                                end
                                if not opt_data.end_line then opt_data.end_line = #dialogue_data + 1 end

                                table.insert(options_to_create, opt_data)

                                -- 【修复点】：
                                -- 这是一个分支选项，它的内容（如C, G命令）在它和下一个选项之间。
                                -- 我们已经记录了 end_line（下一个选项或<<的位置）。
                                -- 为了继续扫描下一个选项，我们必须直接跳到 end_line 的前一行。
                                -- 循环末尾的 scan_index = scan_index + 1 会正好把我们带到 end_line。
                                scan_index = opt_data.end_line - 1
                            end
                        else
                            -- 如果遇到既不是 > 开头，也不是 << 的行，说明选项列表中断了（通常是逻辑错误，但为了兼容性保留break）
                            break
                        end
                        scan_index = scan_index + 1
                    end

                    msg.post("#对话框", "disable")
                    msg.post("#文字", "disable")
                    msg.post("#文字送", "disable")
                    msg.post("#名字", "disable")
                    for _, p in ipairs(glyph_instances) do
                        msg.post(msg.url(nil, p, "glyph_instance"), "disable")
                    end

                    -- 【关键修改】存储选项数据到 self
                    self.current_options_list = options_to_create

                    -- 生成选项，传递索引 i
                    for i, opt in ipairs(options_to_create) do
                        create_option(self, opt.text, i)
                    end

                    self.scope_end_index = block_end_index
                    self.current_line_index = block_end_index 
                    break

                elseif line:sub(1,1) == "G" then
                    local success = handle_jump(self, line)
                    if not success then
                        print("警告：跳转命令执行失败，跳过该行。")
                        self.current_line_index = self.current_line_index + 1
                    end
                elseif line:sub(1,1) == "S" then
                    local value_str = line:sub(2)
                    local value_num = tonumber(value_str)
                    if value_num then self.story.talk_speed = value_num end
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "B" then
                    local content = line:sub(2):match("^%s*(.-)%s*$")
                    if content ~= "" then
                        local url_part, msg_part, param_part = content:match("^(%S+)%s+(%S+)%s*(.*)$")
                        if url_part and msg_part then
                            local target_url = msg.url(url_part)
                            local message_id = hash(msg_part)
                            local message_table = {}

                            if param_part and param_part ~= "" then
                                -- 先替换变量为 Lua 字面量
                                local expr_str = replace_variables_for_lua(param_part)

                                -- 执行 Lua 表达式（要求 expr_str 是一个表构造，如 {r=255, g=100}）
                                local func, err = loadstring("return " .. expr_str)
                                if func then
                                    local ok, result = pcall(func)
                                    if ok and type(result) == "table" then
                                        message_table = result
                                    else
                                        print("错误：B命令表表达式执行失败，返回非表或出错")
                                    end
                                else
                                    print("错误：B命令表表达式语法错误：" .. (err or "未知错误"))
                                end
                            end

                            if next(message_table) == nil then
                                msg.post(target_url, message_id)
                            else
                                msg.post(target_url, message_id, message_table)
                            end
                        end
                    end
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "M" then
                    local expr = line:match("M%((.-)%)")
                    if expr then
                        expr = expr:match("^%s*(.-)%s*$")
                        local var_part, op_part, value_part = expr:match("^([%s$#_%w]+)%s*([%+%-*/=]+=?)%s*(.*)$")
                        if var_part and value_part then
                            local prefix = var_part:match("^[$#]")
                            local varname = (prefix and var_part:sub(2) or var_part):match("^%s*(.-)%s*$")
                            if varname ~= "" then
                                local manager = (prefix == "#") and temp_var_manager or save_manager
                                local value, value_type
                                value_part = value_part:match("^%s*(.-)%s*$")
                                if value_part:match('^".*"$') then
                                    value = value_part:sub(2, -2); value_type = "string"
                                elseif value_part == "true" or value_part == "false" then
                                    value_type = "boolean"; value = (value_part == "true")
                                else
                                    local num = tonumber(value_part)
                                    if num then value = num; value_type = "number" end
                                end
                                if value ~= nil then
                                    local current = manager.get(varname)
                                    if current == nil then 
                                        if value_type == "number" then current = 0
                                        elseif value_type == "boolean" then current = false
                                        else current = "" end
                                    end
                                    local new_value = current
                                    local clean_op = op_part or "="
                                    if clean_op:match("[=]$") or clean_op == "=" then new_value = value
                                    elseif clean_op == "+=" then new_value = current + value
                                    elseif clean_op == "-=" then new_value = current - value
                                    elseif clean_op == "*=" then new_value = current * value
                                    elseif clean_op == "/=" then new_value = math.floor(current / value) end
                                    manager.set(varname, new_value)
                                end
                            end
                        end
                    end
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "I" then
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "N" then
                    local namestr = line:sub(2)
                    label.set_text("#名字", namestr)
                    msg.post("#名字", "set_text", { text = namestr })
                    msg.post("#名字", "enable")
                    self.readonly.namestr = namestr
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "C" then
                    local biaoqing = line:sub(2)
                    sprite.play_flipbook("/typewriter_core#character_collection", biaoqing)
                    self.current_expression = biaoqing
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "E" then
                    self.is_typing = false
                    self.had_chat_box = false
                    self.current_line_index = 0
                    self.current_char_count = 0
                    self.target_text = ""
                    label.set_text("#文字", "")
                    label.set_text("#名字", "")
                    msg.post("/typewriter_core", "disable")
                    self.condition_stack = {}
                    clear_non_modal_state(self)
                    return
                elseif line:sub(1,1) == "O" then
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "A" then
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "F" then
                    local func_name, param = line:match('F%(([%w_-]+),?%s*([^%)]*)%)')
                    if func_name and story_functions[func_name] then
                        local arg = tonumber(param) or param
                        if param == "" then arg = nil end
                        story_functions[func_name](self,arg)
                    end
                    self.current_line_index = self.current_line_index + 1
                elseif line:sub(1,1) == "T" then
                    clear_glyphs()
                    self.current_char_count = 0
                    local raw_text = line:sub(2)
                    local processed_text = raw_text:gsub("\\n","\n")
                    processed_text = parse_text_variables(processed_text)
                    if string.find(processed_text, "<%a+:%w+>") then
                        label.set_text("#文字", "")
                        rtext_parser.parse_rich_text(processed_text, rich_text_table)
                        self.is_rich_text = true
                        self.target_text = ""
                    else
                        self.target_text = auto_warp(processed_text, self.story.max_warp)
                        self.is_rich_text = false
                    end
                    self.is_typing = true
                    msg.post("#文字送", "disable")
                    break
                else
                    self.current_line_index = self.current_line_index + 1
                end
            end
        else
            if line:sub(1,1) == "?" then
                if line:match("^%?ENDIF$") or line:match("^%?END$") then
                    if #self.condition_stack > 0 then table.remove(self.condition_stack) end
                end
            end
            self.current_line_index = self.current_line_index + 1
        end
    end
end

-- -------------------------------------------------------------------------
-- 3. 脚本逻辑
-- -------------------------------------------------------------------------

local function complete_text(self)
    self.is_typing = false
    if self.is_rich_text then
        for i = self.current_char_count + 1, #rich_text_table.chars do
            render_rich_char(self, i)
        end
        self.current_char_count = #rich_text_table.chars
    else
        self.current_char_count = utf8.len(self.target_text)
        label.set_text("#文字", self.target_text)
    end

    if not self.is_selecting then
        msg.post("#文字送", "enable")
    end
end

local function apply_rollback(self, changes, self_state, direction)
    clear_glyphs()
    clear_options()

    for _, ch in ipairs(changes) do
        local value = (direction == -1) and ch.old or ch.new
        if ch.source == "save" then
            save_manager._set_direct(ch.key, value)
            msg.post("/status_menu#status_menu", "data_changed", {key = ch.key, value = value})
        elseif ch.source == "temp" then
            temp_var_manager._set_direct(ch.key, value)
        end
    end

    if self_state then
        for k, v in pairs(self_state) do
            self[k] = v
        end

        if self.is_rich_text and self_state.rich_text_table then
            rich_text_table = self_state.rich_text_table
        end

        if self.is_rich_text then
            for i = 1, #rich_text_table.chars do
                render_rich_char(self, i)
            end
            self.current_char_count = #rich_text_table.chars
            label.set_text("#文字", "")
        else
            label.set_text("#文字", self.target_text)
            self.current_char_count = utf8.len(self.target_text)
        end

        label.set_text("#名字", self.readonly.namestr)

        if self.current_expression then
            sprite.play_flipbook("/typewriter_core#character_collection", self.current_expression)
        end

        if not self.is_typing and not self.is_selecting then
            msg.post("#文字送", "enable")
        else
            msg.post("#文字送", "disable")
        end

        msg.post("#对话框", "enable")
        msg.post("#文字", "enable")
        msg.post("#名字", "enable")
    end
end

function init(self)
    load_dialogue()
    self.frame_counter = 0
    self.is_typing = false
    self.is_selecting = false
    self.target_text = ""
    self.current_char_count = 0
    self.current_line_index = 1
    self.is_rich_text = false
    self.had_chat_box = false

    self.current_option_anim = nil 
    self.current_expression = nil
    self.scope_end_index = nil

    -- 新增：用于存储当前显示的选项数据
    self.current_options_list = {}

    msg.post("#文字送", "disable")
    msg.post(".", "acquire_input_focus")
    msg.post(".", "disable")

    self.story = {
        talk_speed = 5,
        max_warp = 23,
        r_kerning= 20,
        r_leading = 24,
        r_base_x = 93,
        r_base_y = 134,
    }

    self.readonly = {
        namestr = "",
    }

    self.condition_stack = {}
    self.is_viewing_history = false
end

function update(self, dt)
    total_timer = total_timer + 1
    if not self.had_chat_box then return end

    self.frame_counter = self.frame_counter + 1
    if self.frame_counter >= self.story.talk_speed then
        self.frame_counter = 0
        self.current_char_count = self.current_char_count + 1
        if self.is_rich_text then
            if self.current_char_count <= #rich_text_table.chars then
                render_rich_char(self,self.current_char_count)
            else
                complete_text(self)
            end
        else
            local display_str = left(self.target_text, self.current_char_count)
            label.set_text("#文字", display_str)
            if display_str == self.target_text then
                complete_text(self)
            end
        end
    end
    if self.is_rich_text then
        for i = 1,#glyph_instances do
            local offset_x = 0
            local offset_y = 0

            local p = glyph_instances[i]
            local base_pos = glyph_positions[i]
            local shake_x = rich_text_table.shake_x[i] or 0
            local shake_y = rich_text_table.shake_y[i] or 0
            local wave = rich_text_table.wave[i] or 0
            local wave_sped = rich_text_table.wave_sped[i] or 0

            if shake_x ~= 0 or shake_y ~= 0 then
                offset_x = offset_x + math.random(-shake_x,shake_x)
                offset_y = offset_y +math.random(-shake_y,shake_y)
            end
            if wave ~= 0 then
                offset_y = offset_y + math.sin(wave_sped*total_timer+i*self.story.talk_speed)*wave
            end
            go.set_position(vmath.vector3(base_pos.x + offset_x, base_pos.y + offset_y, base_pos.z), p)
        end
    end
end

function fixed_update(self, dt)
end

function on_message(self, message_id, message, sender)
    if message_id == hash("start_dialogue") then
        msg.post(".", "enable")
        msg.post(".", "acquire_input_focus")

        local target_key = hash("O" .. message.target_id)
        local target_line = o_index[target_key]

        if target_line then
            self.had_chat_box = true
            self.current_line_index = target_line
            self.condition_stack = {}
            self.scope_end_index = nil
            self.current_options_list = {} -- 清空选项列表
            process_commands(self)
        end

    elseif message_id == hash("option_selected") then
        self.is_selecting = false
        clear_options()

        -- 【关键修改】从索引获取数据
        local opt_data = self.current_options_list[message.index]

        if not opt_data then 
            print("错误：未获取到选项数据 index=" .. tostring(message.index))
            return 
        end

        msg.post("#对话框", "enable")
        msg.post("#文字", "enable")
        msg.post("#名字", "enable")

        self.condition_stack = {} 

        if opt_data.type == "branch" then
            self.current_line_index = opt_data.start_line
            self.scope_end_index = opt_data.end_line
            process_commands(self)

        elseif opt_data.type == "immediate" then
            local cmd = "GO"..opt_data.command
            print("执行即时命令: " .. cmd)
            handle_jump(self, cmd)
            process_commands(self)
        end
    end
end

local function save_snapshot(self)
    local snapshot_state = {
        frame_counter      = self.frame_counter,
        is_typing          = self.is_typing,
        is_selecting       = self.is_selecting,
        target_text        = self.target_text,
        current_char_count = self.current_char_count,
        current_line_index = self.current_line_index,
        is_rich_text       = self.is_rich_text,
        had_chat_box       = self.had_chat_box,
        condition_stack    = self.condition_stack,
        story              = self.story,
        readonly           = self.readonly,
        rich_text_table    = self.is_rich_text and rich_text_table or nil,
        current_expression = self.current_expression,
        current_option_anim = self.current_option_anim,
        scope_end_index    = self.scope_end_index,
        -- 选项数据不需要存入快照，因为回滚会重新生成UI
    }
    rollback.push_snapshot(snapshot_state)
end

function on_input(self, action_id, action)
    if action_id == hash("key_space") and action.pressed and self.had_chat_box == true then
        if self.is_typing then
            complete_text(self)
        elseif not self.is_selecting then
            self.is_viewing_history = false
            save_snapshot(self)

            if self.is_rich_text then
                clear_glyphs()
            end
            self.scope_end_index = nil 
            self.current_line_index = self.current_line_index + 1
            process_commands(self)
        end
    end

    if action_id == hash("key_up") and action.pressed then
        local current_idx = rollback.get_current_snapshot_index()
        local total_cnt   = rollback.get_snapshot_count()
        if not self.is_viewing_history and current_idx == total_cnt then
            save_snapshot(self)
            self.is_viewing_history = true
        end

        local success, changes, self_state, direction = rollback.move(-1)
        if success then
            apply_rollback(self, changes, self_state, direction)
        end
    end

    if action_id == hash("key_down") and action.pressed then
        local success, changes, self_state, direction = rollback.move(1)
        if success then
            apply_rollback(self, changes, self_state, direction)
        end
    end
end

function on_reload(self)
end