local M = {}

local languages = {
	zh_cn = require("assets.localization.zh_cn"),
	en = require("assets.localization.en")
}

local current_lang = "zh_cn"

-- 获取翻译文本
function M.t(key)
	return languages[current_lang][key] or key
end

-- 切换语言
function M.set_language(lang_code)
	if languages[lang_code] then
		current_lang = lang_code
		-- 切换语言后，向所有脚本广播更新 UI 的消息
		msg.post("@render:", "layout_changed") 
		-- 或者发送给具体的 UI 控制器
		msg.post("/status_menu#status_menu", "lang_changed")
	end
end

return M