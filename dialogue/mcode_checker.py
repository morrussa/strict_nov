import sys
from collections import defaultdict
import re
import datetime

def static_check_dialogue(filename="dialogue.txt"):

    log_filename = f"check_log_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    log_file = open(log_filename, "w", encoding="utf-8")
    class Tee:
        def __init__(self, *files):
            self.files = files
        def write(self, text):
            for f in self.files:
                f.write(text)
        def flush(self):
            for f in self.files:
                f.flush()
    original_stdout = sys.stdout
    sys.stdout = Tee(original_stdout, log_file)

    print(f"正在检查文件: {filename}\n")
    
    with open(filename, 'r', encoding='utf-8') as f:
        lines = [line.rstrip() for line in f.readlines()]
    
    o_index = {}                    
    a_index = {}                    
    option_jumps = defaultdict(list)  
    g_jumps = defaultdict(list)       
    
    block_has_E = defaultdict(bool)
    block_has_option = defaultdict(bool)
    block_has_G = defaultdict(bool)
    block_closed = defaultdict(bool)   # 新增：块是否已遇到闭合指令（G/>/E）
    
    block_has_conditional = defaultdict(bool)  # I 或 ?
    block_has_modify = defaultdict(bool)       # M
    
    current_block = None
    previous_block = None
    consecutive_options = 0
    current_option_block = None
    
    all_jumps = defaultdict(list)
    
    pending_anchor = None  # 仅记录独立或闭合后后置的 A
    
    conditional_lines = []  
    if_stack = []  # 新增：跟踪打开的 if，元素为 (block_id, line_num)

    
    
    for line_num, raw_line in enumerate(lines, 1):
        line = raw_line.strip()

        if not line:  # line 是 raw_line.strip() 后的结果，如果为空则为纯空白行（包括空格、制表符等）
            if current_block is not None and not block_closed[current_block]:
                # 只针对“当前正在处理的、尚未闭合的块”报错
                # 已闭合的块后出现的空行视为块间分隔，不报
                print(f" [行 {line_num}]: O{current_block} 块内出现空行，纯粹浪费性能而已，看我不爽就注释掉好啦！")
            # 块外或已闭合块后的空行不报（用于文件分隔正常）
            continue
        
        # A锚点
        if line.startswith("A"):
            anchor_id = line[1:].strip()
            if not anchor_id:
                print(f"警告 [行 {line_num}]: A指令缺少锚点ID")
                continue
            if anchor_id in a_index:
                print(f"错误 [行 {line_num}]: 重复定义 A 锚点 '{anchor_id}' (原行 {a_index[anchor_id]})")
            else:
                a_index[anchor_id] = line_num
                if current_block is None or block_closed[current_block]:
                    pending_anchor = anchor_id
                    print(f"信息 [行 {line_num}]: 注册独立/闭合后 A 锚点 '{anchor_id}'（将补全其后顺序流）")
                else:
                    print(f"信息 [行 {line_num}]: 注册嵌入式 A 锚点 '{anchor_id}'（位于未闭合块 O{current_block} 内，不补全顺序流）")
        
        # O块
        elif line.startswith("O"):
            block_id = line[1:].strip()
            if block_id in o_index:
                print(f"错误 [行 {line_num}]: 重复定义 O 块 '{block_id}'")
            else:
                o_index[block_id] = line_num
                print(f"信息 [行 {line_num}]: 注册 O 块 '{block_id}'")
                
                # 先补全 pending A 的顺序流（独立或闭合后 A）
                if pending_anchor is not None:
                    all_jumps[pending_anchor].append(block_id)
                    print(f"信息 [行 {line_num}]: 添加 A{pending_anchor} → O{block_id} 顺序流")
                    pending_anchor = None
                
                # 默认顺序流（仅无显式闭合时）
                if previous_block and not (block_has_E[previous_block] or block_has_option[previous_block] or block_has_G[previous_block]):
                    all_jumps[previous_block].append(block_id)
                    print(f"信息: 添加默认顺序流 O{previous_block} → O{block_id} (上一个块未显式闭合)")
                
                if previous_block and not (block_has_E[previous_block] or block_has_option[previous_block] or block_has_G[previous_block]):
                    print(f"警告 [块 O{previous_block} (行 {o_index[previous_block]})]: 未用 E 闭合且无选项/手动G，可能导致意外顺序流")
                
                previous_block = current_block
                current_block = block_id
                block_closed[current_block] = False  # 新块开始，重置 closed 状态
            
            if consecutive_options > 0:
                if consecutive_options == 1:
                    print(f"警告 [块 O{current_option_block or '未知'}]: 只有一个选项（假选项菜单）")
                consecutive_options = 0
            current_option_block = current_block
        
        # G跳转（遇到即闭合）
        elif line.startswith("G"):
            target = line[1:].strip()
            if not target:
                print(f"警告 [行 {line_num}]: G指令缺少目标")
                continue
            if current_block:
                g_jumps[current_block].append(target)
                block_has_G[current_block] = True
                block_closed[current_block] = True  # 遇到 G 即闭合
                all_jumps[current_block].append(target)
        
        # 选项 >（遇到即闭合）
        elif line.startswith(">"):
            parts = raw_line[1:].split("#", 1)
            target = parts[1].strip() if len(parts) > 1 else None
            if target and current_block:
                option_jumps[current_block].append(target)
                all_jumps[current_block].append(target)
            consecutive_options += 1
            block_has_option[current_block] = True
            block_closed[current_block] = True  # 遇到选项即闭合

        elif line.startswith("?("):
            # 尝试匹配 ?(条件)后面内容
            match = re.match(r"\?\((.+?)\)(.*)", line.strip())
            if not match:
                print(f"错误 [行 {line_num}]: ? 条件格式错误，无法解析条件部分")
                continue

            condition_str, rest = match.groups()
            rest = rest.strip()  # 模拟引擎的 gsub("^%s*","")

            # 1. 条件语法检查
            if "~=" in condition_str:
                print(f"错误 [行 {line_num}]: 条件中使用 '~=' （不支持，请用 '<>'）")
            # 可加更多条件合法性检查...

            # 2. 根据 rest 的首字符判断它要干什么，并做对应检查
            if not rest:
                print(f"警告 [行 {line_num}]: ?(条件) 后面没有任何内容（条件成立也无事可做）")

            elif rest.startswith(">"):
                # 条件选项 ?(...) > 文本 #target
                opt_match = re.match(r">\s*(.+?)(?:\s*#(\w+))?$", rest)
                if not opt_match:
                    print(f"错误 [行 {line_num}]: 条件选项格式不正确，应为 >文本#目标")
                else:
                    text, target = opt_match.groups()
                    if target and target not in o_index:
                        print(f"错误 [行 {line_num}]: 条件选项跳转到不存在的 O{target}")
                    block_has_option[current_block] = True
                    block_closed[current_block] = True

            elif rest.startswith(("T", "N", "C", "F", "S", "G", "E", "I", "A", "O")):
                # 条件化普通指令，基本合法，但提醒开发者注意潜在问题
                print(f"信息 [行 {line_num}]: 条件化指令 {rest[0]} （条件: {condition_str}）")

            else:
                print(f"警告 [行 {line_num}]: ?(条件) 后接未知/无效指令开头: {rest}")

            # 无论哪种情况，遇到 ?( 都视为可能闭合（尤其选项时）
            if rest.startswith(">"):
                block_closed[current_block] = True
                block_has_option[current_block] = True
        
        # E闭合
        elif line.startswith("E"):
            if current_block:
                block_has_E[current_block] = True
                block_closed[current_block] = True  # 显式闭合

        if line == "I":
            if current_block is None:
                print(f"错误 [行 {line_num}]: endif 出现在 O 块外部")
                # 不处理 stack
            elif block_closed[current_block]:
                print(f"错误 [行 {line_num}]: endif 出现在块已闭合后（O{current_block} 已由选项/G/E 闭合）")
                # 不 pop，保持 stack 原样（后续会报无尾或嵌套问题）
            elif len(if_stack) == 0:
                print(f"错误 [行 {line_num}]: 多余的 endif (无对应的起始 I 条件) —— 无头情况")
                # 不 pop
            else:
                open_block, open_line = if_stack.pop()
                if open_block != current_block:
                    print(f"错误 [行 {line_num}]: if 跨 O 块闭合 (起始 I 在 O{open_block} 行 {open_line}) —— 跨块情况")
                # else: 正常闭合，不输出
            continue  # 跳过后续处理

        # 新增：处理起始 if（I(条件...)）
        if line.startswith("I("):
            if current_block is None:
                print(f"错误 [行 {line_num}]: 起始 I 条件出现在 O 块外部")
            elif block_closed[current_block]:
                print(f"错误 [行 {line_num}]: 起始 I 条件出现在块已闭合后（O{current_block} 已由选项/G/E 闭合）")
                # 不 push，防止后续误报
            elif len(if_stack) > 0:
                prev_block, prev_line = if_stack[-1]
                print(f"错误 [行 {line_num}]: 不允许 if 嵌套 (已有未闭合的 if 在 O{prev_block} 行 {prev_line})")
                # 不 push（视作无效指令）
            else:
                if_stack.append((current_block, line_num))
            # 继续执行下面的原有标记逻辑
        
        # 标记条件/修改（用于死循环检测）
        elif line.startswith("I(") or line.startswith("?("):
            if current_block:
                block_has_conditional[current_block] = True
        elif line.startswith("M("):
            if current_block:
                block_has_modify[current_block] = True

        
        # 条件行收集
        if line.startswith("I("):
            conditional_lines.append((line_num, raw_line, 'I'))
        elif line.startswith("?("):
            conditional_lines.append((line_num, raw_line, '?'))
    
    # 文件末尾处理
    if pending_anchor is not None:
        print(f"警告: 独立/闭合后 A{pending_anchor} 后无后续 O 块（位于文件末尾）")
    
    if current_block and not (block_has_E[current_block] or block_has_option[current_block] or block_has_G[current_block]):
        print(f"警告 [块 O{current_block} (行 {o_index[current_block]})]: 文件末尾块未闭合，可能死端")
    
    # 跳转目标检查（不变）
    for from_block, targets in g_jumps.items():
        for t in set(targets):
            if t not in a_index:
                print(f"错误 [块 O{from_block} 的 G 指令]: 跳转到不存在的 A 锚点 '{t}'")
    for from_block, targets in option_jumps.items():
        for t in set(targets):
            if t not in o_index:
                print(f"错误 [块 O{from_block} 的选项跳转]: 跳转到不存在的 O 块 '{t}'")
    
    # 条件语法检查（不变）
    for line_num, raw_line, cond_type in conditional_lines:
        line = raw_line.strip()
        match = re.match(r"^[I?]\((.+)\)(.*)$", line)
        if not match:
            print(f"警告 [行 {line_num}]: {cond_type} 条件格式不标准")
            continue
        condition_str = match.group(1).strip()
        subsequent_content = match.group(2).strip()
        if "~=" in condition_str:
            print(f"错误 [行 {line_num}]: 条件中使用 '~=' （不支持，请用 '<>'）")
        if cond_type == '?' and not subsequent_content:
            print(f"警告 [行 {line_num}]: ? 条件后无后续指令（条件真时可能空行/停止）")
    
    # 控制流分析 & 环检测（不变）
    all_nodes = set(o_index.keys()) | set(a_index.keys())
    incoming = defaultdict(set)
    for fb, ts in all_jumps.items():
        for t in ts:
            if t in all_nodes:
                incoming[t].add(fb)
    
    unreachable_o = [b for b in o_index if b not in incoming and b]
    unreachable_a = [a for a in a_index if a not in incoming]
    if unreachable_o:
        print("警告: 可能不可达的 O 块（通常只有入口块正常）:")
        for b in sorted(unreachable_o):
            print(f"    O{b} (行 {o_index[b]})")
    if unreachable_a:
        print("警告: 可能不可达的 A 锚点:")
        for a in sorted(unreachable_a):
            print(f"    A{a} (行 {a_index[a]})")
    
    dead_ends = [b for b in o_index if not all_jumps[b]]
    if dead_ends:
        print("信息: 死端 O 块:")
        for b in sorted(dead_ends):
            print(f"    O{b} (行 {o_index[b]})")
    
    def has_cycle():
        visited = set()
        rec_stack = set()
        def dfs(node):
            visited.add(node)
            rec_stack.add(node)
            for neigh in all_jumps[node]:
                if neigh not in all_nodes:
                    continue
                if neigh not in visited:
                    if dfs(neigh):
                        return True
                elif neigh in rec_stack:
                    return True
            rec_stack.remove(node)
            return False
        for node in all_nodes:
            if node not in visited:
                if dfs(node):
                    return True
        return False
    
    if has_cycle():
        print("警告: 检测到控制流环（请确保环内有退出路径）")
    
    # 明显无条件自环检测（利用补全的顺序流）
    print("\n检查明显无条件无限循环（自环模式）:")
    found_dead_loop = False
    for block in o_index:
        targets = set(g_jumps[block])
        if len(targets) != 1:
            continue
        a_target = list(targets)[0]
        a_successors = all_jumps.get(a_target, [])
        if len(a_successors) != 1 or a_successors[0] != block:
            continue
        if not (block_has_option[block] or block_has_conditional[block] or block_has_modify[block] or block_has_E[block]):
            print(f"错误 [块 O{block} (行 {o_index[block]})]: 检测到明显无条件无限循环！")
            print(f"    单一 G{a_target} → A{a_target} → 回到本块，且无选项/条件/变量修改/E")
            found_dead_loop = True
    if not found_dead_loop:
        print("    未检测到明显无条件自环死循环。")

    if if_stack:
        print("错误: 存在未闭合的 if（缺少对应的 endif）:")
        for open_block, open_line in reversed(if_stack):
            print(f"    未闭合的 if 起始于 O{open_block} (行 {open_line}) —— 无尾情况")
    
    print(f"\n检查完成！ 共 {len(o_index)} 个 O 块， {len(a_index)} 个 A 锚点。")

    sys.stdout = original_stdout
    log_file.close()
    print(f"\n检查完成，完整日志已保存至当前目录的 {log_filename}")

if __name__ == "__main__":
    filename = sys.argv[1] if len(sys.argv) > 1 else "dialogue.txt"
    static_check_dialogue(filename)