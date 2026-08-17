---@module "mud_lib/combat"

local class = require("mud_os/class")
local log = require("mud_os/log")

-- 攻击命中消息
local def_attack_msg = {
  "%s狠狠的向%s挥出一拳，正中鼻梁。",
  "%s对准%s的心窝飞起一脚，踹个正着。",
  "%s拼了老命的对准%s一头撞去，碰了个满怀。",
  "%s怪叫一声，对着%s的脑门就是一掌。"
}

-- 未命中消息
local def_miss_msg = {
  "%s向%s挥出一拳，却打了个空。",
  "%s对准%s飞起一脚，可惜差之毫厘。",
  "%s用力过猛，差点失去平衡。",
  "%s的攻击被%s轻松躲开了。"
}

-- 伤害消息
local def_hurt_msg = {
  "造成%s的伤害如同搔痒一般。",
  "造成%s一片擦伤。",
  "%s闷哼一声，晃了一下还是站住了。",
  "%s身上出现了一个深深的伤口，血流不止。",
  "一声巨响，%s被连人击飞。"
}

---战斗函数，每帧调用一次
---@param attacker Investigator
---@param target Investigator
local function combat(attacker, target)
  local atk_player = nil
  local tar_player = nil
  local Investigator = require("mud_lib/chars/investigator")
  if class.is_instance(attacker, Investigator) then
    atk_player = attacker --[[@as Investigator]]
  end
  if class.is_instance(target, Investigator) then
    tar_player = target --[[@as Investigator]]
  end

  -- 简化COC命中率计算：d100 <= dex属性值则命中
  local hit_roll = math.random(1, 100)
  local hit_chance = 50
  if attacker["core_attrs"] and attacker["skill"] then
    local skill = attacker.skill["格斗"] or 0
    hit_chance = attacker.core_attrs.dex // 2 + skill
  end
  local is_hit = hit_roll <= hit_chance

  -- 检查右手武器
  local right_hand = attacker.equipment and attacker.equipment["right_hand"] --[[@as Weapon]]

  -- 处理战斗逻辑
  -- 如果装备了武器且武器有自定义消息，则使用武器的消息，否则使用攻击者自身的消息或默认消息
  local attack_msg = (right_hand and right_hand.attack_msg) or attacker.attack_msg or def_attack_msg
  local hurt_msg = (right_hand and right_hand.hurt_msg) or target.hurt_msg or def_hurt_msg
  local miss_msg = (right_hand and right_hand.miss_msg) or attacker.miss_msg or def_miss_msg
  local this_place = attacker.environment --[[@as Room]]

  -- 判断是否命中
  -- this_place.channel:say(attacker.name.."命中："..hit_roll.."/"..hit_chance)
  if not is_hit then
    -- 未命中
    local mmsg = miss_msg[math.random(1, #miss_msg)]
    this_place.channel:say(
      string.format(mmsg, attacker.name, target.name),
      attacker, target)
    if atk_player then
      atk_player:reply(string.format(mmsg, "你", target.name) .. "\n")
    end
    if tar_player then
      tar_player:reply(string.format(mmsg, attacker.name, "你") .. "\n")
    end
    return
  end

  -- 命中，计算伤害值
  local damage = 0
  local str = 50
  if attacker["core_attrs"] then
    str = attacker.core_attrs.str
  end

  if right_hand and right_hand.damage then
    -- 使用武器伤害
    damage = right_hand.damage
  else
    -- 徒手攻击：1D3 + 伤害加成
    damage = math.random(1, 3)
  end

  -- 根据str计算伤害加成
  local db = 0
  if str < 30 then
    db = 0 - math.random(1, 4) -- -1D4
  elseif str <= 50 then
    -- 无加成
  elseif str <= 80 then
    db = math.random(1, 4) -- +1D4
  else
    db = math.random(1, 6) -- +1D6
  end
  damage = damage + db
  -- 确保伤害至少为1
  damage = math.max(1, damage)

  -- 输出伤害产生的文字描述
  local a_i = math.random(1, #attack_msg)
  local amsg = attack_msg[a_i]

  -- 根据伤害占现有HP的百分比选择伤害消息
  local hp_percent = damage / target.hp            -- 伤害占HP的比例
  local dm_idx = math.ceil(hp_percent * #hurt_msg) -- 根据比例计算消息索引

  -- 确保索引在有效范围内
  dm_idx = math.max(1, math.min(dm_idx, #hurt_msg))
  local hmsg = hurt_msg[dm_idx] .. "\n"

  this_place.channel:say(
    string.format(amsg, attacker.name, target.name),
    attacker, target)
  this_place.channel:say(
    string.format(hmsg, target.name),
    attacker, target)
  this_place.channel:say(attacker.name .. "造成伤害：" .. damage)
  if atk_player then
    atk_player:reply(string.format(amsg, "你", target.name))
    atk_player:reply(string.format(hmsg, target.name))
  end

  if tar_player then
    tar_player:reply(string.format(amsg, attacker.name, "你", damage))
    tar_player:reply(string.format(hmsg, "你"))
    tar_player:send_vitals_gmcp()
  end

  -- 计算目标的HP
  target:modify_hp(-damage)
  if not target:is_alive() then
    -- 目标死亡，使用统一的方法清理敌人列表
    attacker:clean_dead_enemies()
    target.fright_list = {}
    target.is_in_combat = false

    if atk_player then
      atk_player:reply(string.format("%s已经奄奄一息，你终于停手了。", target.name))
    end
    if tar_player then
      tar_player:reply("你不支倒地，奄奄一息。")
    end
    this_place.channel:say(
      string.format("%s已经奄奄一息，%s终于停手了。", target.name, attacker.name), target, attacker)
  end
end

return combat
