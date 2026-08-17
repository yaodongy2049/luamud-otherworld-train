---@module "mud_lib/cmd/hp"
local cmd_sys = require("mud_lib/cmds")
local misc = require("mud_os/misc")

cmd_sys.command_desc_list.hp = "hp：查状态/血量，args=[]"

cmd_sys.command_list.hp = function(this_player, cmds)
  -- 构建HP字符串
  local hp_str = string.format("HP:【%d/%d】", this_player.hp, this_player.max_hp)
  
  -- 构建MP字符串
  local mp_str = this_player.mp and this_player.max_mp and
  string.format("MP:【%d/%d】", this_player.mp, this_player.max_mp) or nil
  
  -- 构建SAN字符串
  local san_str = this_player.san and
  string.format("SAN:【%d】", this_player.san) or nil

  -- 使用 create_sheet 函数创建表格（一行3列）
  local table_str = misc.create_sheet({ { hp_str, mp_str, san_str } })
  table_str = "状态：\n" .. table_str

  -- 构建核心属性描述（仅调查员角色）
  local attr_str = ""
  if this_player.core_attrs then
    attr_str = "核心属性：\n"
    local attr_str_line = {}
    local attr_names = { str = "力量", con = "体质", siz = "体型", dex = "敏捷", app = "外貌", int = "智力", pow = "意志", edu = "教育", luk =
    "幸运" }
    for key, name in pairs(attr_names) do
      local value = 0
      if key == "siz" or key == "luk" then
        value = this_player.game_tags.attrs and this_player.game_tags.attrs[string.upper(key)] or 0
      else
        value = this_player.core_attrs[key] or 0
      end
      table.insert(attr_str_line, string.format("%s: %d", name, value))
    end
    
    -- 添加信用和移动力
    local credit = this_player.game_tags and this_player.game_tags.credit or 0
    local mov = this_player.game_tags and this_player.game_tags.mov or 0
    table.insert(attr_str_line, string.format("信用: %d", credit))
    table.insert(attr_str_line, string.format("移动: %d", mov))
    
    -- 转换为一行3列的二维数组
    local attr_rows = {}
    for i = 1, #attr_str_line, 3 do
      table.insert(attr_rows, { attr_str_line[i], attr_str_line[i+1], attr_str_line[i+2] })
    end
    attr_str = attr_str .. misc.create_sheet(attr_rows)
  end

  -- 构建技能描述（仅调查员角色）
  local skill_str = ""
  if this_player.skill then
    -- 技能分类表
    local skill_categories = {
      ["核心生存/侦查技能"] = { "侦查", "聆听", "潜行", "追踪", "闪避" },
      ["社交/交涉技能"] = { "话术", "说服", "恐吓", "取悦", "心理学" },
      ["知识/学术技能"] = { "图书馆使用", "历史", "神秘学", "博物学", "考古学", "地质学", "法律", "其他语言", "母语", "拉丁语" },
      ["医疗/精神技能"] = { "急救", "医学", "精神分析", "诊断", "解剖" },
      ["战斗/武器技能"] = { "斗殴", "手枪", "步枪/霰弹枪", "近战武器", "投掷", "射击" },
      ["技术/手工技能"] = { "锁匠", "机械维修", "电气维修", "驾驶", "攀爬", "游泳", "导航", "航海", "机械", "工程", "技艺(木工/焊接)", "会计", "科学(生物)", "科学(药学)" },
      ["艺术/表演技能"] = { "艺术(文学)", "艺术(摄影)", "艺术(表演)", "伪装"},
      ["特殊技能"] = { "克苏鲁神话" }
    }
    
    skill_str = "技能：\n"
    for category_name, skills_in_category in pairs(skill_categories) do
      local category_skills = {}
      for _, skill_name in ipairs(skills_in_category) do
        if this_player.skill[skill_name] then
          table.insert(category_skills, string.format("%s: %d", skill_name, this_player.skill[skill_name]))
        end
      end
      if #category_skills > 0 then
        skill_str = skill_str .. "【" .. category_name .. "】\n"
        -- 转换为一行3列的二维数组
        local category_rows = {}
        for i = 1, #category_skills, 3 do
          table.insert(category_rows, { category_skills[i], category_skills[i+1], category_skills[i+2] })
        end
        skill_str = skill_str .. misc.create_sheet(category_rows) .. "\n\n"
      end
    end
  end

  -- 构建专属属性描述（仅调查员角色）
  local exclusive_str = ""
  if this_player.exclusive and this_player.exclusive ~= "nobody" and this_player.exclusive ~= "" then
    exclusive_str = string.format("专属限制：%s", this_player.exclusive)
  end

  -- 输出信息
  local ret = this_player:to_str() .. "\n\n"
  if attr_str ~= "" then
    ret = ret .. attr_str .. "\n\n"
  end
  if skill_str ~= "" then
    ret = ret .. skill_str .. ""
  end
  if exclusive_str ~= "" then
    ret = ret .. exclusive_str .. "\n\n"
  end
  this_player:reply(ret .. table_str)

  -- 发送GMCP数据
  this_player:send_vitals_gmcp()
end