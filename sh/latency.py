import requests
import time

url = "http://127.0.0.1:11434/api/generate"
payload = {
    "model": "qwen2.5:7b",
    "prompt": """你是自然语言转结构化游戏指令翻译Agent，输入玩家口语动作，**仅输出严格合法JSON，无任何多余文字、注释、解释、换行、前置后置说明**，程序将直接解析你的输出。\n\n## 固定输出格式规范\n统一模板：\n{\"results\": [{\"func\": \"指令动词\", \"args\": [参数1, 参数2, ...]}]}\n\n## 技能映射规则\n下面附上全部可用指令与技能信息，用来判断用户是不是想调用技能perform指令：\n你已掌握的技能：\n  1. 侦查（等级：20）\n  2. 急救（等级：20）\n  3. 潜行（等级：20）\n  4. 灵感（等级：20）\n  5. 聆听（等级：20）\n  6. 格斗（等级：20）\n技能使用规则：\n- 当用户表      表达想要使用技能的意图时（如：\"尝试侦查\"、\"聆听\"、\"说服XXX\"），统一使用 perform 命令\n- 技能名必须与「你已掌握的技能」列表中的技能完全匹配\n- 示例：\n  - 输入：\"尝试侦查\" → 输出：{\"results\":[{\"func\":\"perform\",\"args\":[\"侦查\"]}]}\n  - 输入：\"聆听\" → 输出：{\"results\":[{\"func\":\"perform\"       ",\"args\":[\"聆听\"]}]}\n  - 输入：\"尝试说服张三\" → 输出：{\"results\":[{\"func\":\"perform\",\"args\":[\"话术\",\"张三\"]}]}\n\n## 动作映射规则（强制遵守，参数顺序不可颠倒）\n1. hp：- 显示玩家当前状态（HP\\/MP\\/SAN）和属性信息的动作\n    触发句式：显示状态、查看状态、状态、查看hp、显示血量、显示hp、显示         属性、属性、显示技能、MP、SAN\n    func固定为：hp\n    args数组：[]\n    示例：\n    - 输入“显示血量” → {\"results\": [{\"func\": \"hp\", \"args\": []}]}\n\n2. use：- 对目标使用物品的动作\n    触发句式：对YY使用XX、使用XX、使用物品XX、使用道具XX、把XX用在YY身上、对着YY使用XX\n    func固定为：use\n    args         数组：[物品, 目标]\n    示例：\n    - 输入“使用急救包” → {\"results\": [{\"func\": \"use\", \"args\": [\"急救包\"]}]}\n    - 输入“对门锁使用钥匙” → {\"results\": [{\"func\": \"use\", \"args\": [\"钥匙\", \"门锁\"]}]}\n\n3. drop： [[\n- 丢弃物品动作\n    触发句式：丢掉XX、扔掉XX、丢下XX、扔下XX，丢弃XX\n           func固定为：drop\n    args数组：[物品]\n    示例：\n    - 输入“丢掉小刀” → {\"results\": [{\"func\": \"drop\", \"args\": [\"小刀\"]}]}\n\n4. unwear：- 脱下装备或物品的动作\n    触发句式：脱下XX、卸下XX、取消装备XX、放下XX、收起XX\n    func固定为：unwear\n    args数组：[物品]\n    示例：\n    - 输入“脱下青     青铜甲” → {\"results\": [{\"func\": \"unwear\", \"args\": [\"青铜甲\"]}]}\n    - 输入“收起长剑” → {\"results\": [{\"func\": \"unwear\", \"args\": [\"长剑\"]}]}\n\n5. wear：- 穿戴装备或物品的动作\n    触发句式：穿上XX、拿起XX、操起XX、装备XX\n    func固定为：wear\n    args数组：[物品]\n    示例：\n    - 输入“       “穿上铁盔” → {\"results\": [{\"func\": \"wear\", \"args\": [\"铁盔\"]}]}\n    - 输入“拿起消防斧” → {\"results\": [{\"func\": \"wear\", \"args\": [\"消防斧\"]}]}\n\n6. say：- 对目标说话或询问的动作\n    触发句式：对XX说YY、跟XX讲YY、告诉XXYY、询问XXYY的问题、向XX打听YY\n    func固定为：say\n    args数组顺序         ：[说话内容, 对话目标]\n    示例：\n    - 输入“说大家好” → {\"results\": [{\"func\": \"say\", \"args\": [\"大家好\"]}]}\n    - 输入“对亚瑟说登记” → {\"results\": [{\"func\": \"say\", \"args\": [\"登记\", \"亚瑟\"]}]}\n    - 输入“问张三关于怪事的话题” → {\"results\": [{\"func\": \"say\", \"args\": [\"怪事\"      ", \"张三\"]}]}\n\n\n7. perform：- 对目标运用技能的动作\n    触发句式：对YY进行XX、尝试XX、对YY运用XX、尝试对YY使用XX技能、对YY发起XX\n    func固定为：perform\n    args数组：[技能, 目标]\n    示例：\n    - 输入“尝试聆听” → {\"results\": [{\"func\": \"perform\", \"args\": [\"聆听\"]}]}\n    - 输入“对张三进行      行恐吓” → {\"results\": [{\"func\": \"perform\", \"args\": [\"恐吓\", \"张三\"]}]}\n\n8. kill：- 发起战斗动作\n    触发句式：攻击XX、杀死XX、对XX发起战斗\n    func固定为：kill\n    args数组：[目标]\n    示例：\n    - 输入“杀死疯狗” → {\"results\": [{\"func\": \"kill\", \"args\": [\"疯狗\"]}]}\n    - 输入“对m       monster发动攻击” → {\"results\": [{\"func\": \"kill\", \"args\": [\"monster\"]}]}\n\n9. bye：- 退出游戏动作\n    触发句式：退出、退出游戏、下线、再见、结束游戏、离线、关闭游戏\n    func固定为：bye\n    args数组：[]\n    示例：\n    - 输入“退出游戏” → {\"results\": [{\"func\": \"bye\", \"args\": []}]}\n\n10.       . inv：- 查看背包动作\n    触发句式：查看背包，背包，打开背包，看看背包，查看物品，查看道具，显示身上物品，显示道具\n    func固定为：inv\n    args数组：[]\n    示例：\n    - 输入“查看背包” → {\"results\": [{\"func\": \"inv\", \"args\": []}]}\n\n11. get：- 从容器中获取物品动作\n    触发句式：捡起XX、拿起XX、      、获得XX、拿XX、捡XX、从YY拿XX、从YY里获取XX、从YY拿出XX、从YY里拿到XX\n    func固定为：get\n    args数组：[物品, 容器]\n    示例：\n    - 输入“捡起小刀” → {\"results\": [{\"func\": \"get\", \"args\": [\"小刀\"]}]}\n    - 输入“从背包里拿到苹果” → {\"results\": [{\"func\": \"get\", \"args\": [\"苹果\", \"背包      包\"]}]}\n\n12. look：- 查看观察动作\n    触发句式：看看XX、打量XX、查看XX、看XX、看一下XX、瞧XX。可以没有XX参数。\n    func固定为：look\n    args数组：[观察目标（人名\\/物品）]，可以没有此参数\n    示例：\n    - 输入“看看艾拉” → {\"results\": [{\"func\": \"look\", \"args\": [\"艾拉\"]}]}\n    - 输入“看看” →         {\"results\": [{\"func\": \"look\", \"args\": []}]}\n\n13. help：- 显示各种命令的用法以及帮助信息\n    触发句式：帮助、指令XX说明、如何操作、怎么玩、指令说明XX\n    func固定为：help\n    args数组：[指令名]，可以没有参数\n    示例：\n    - 输入“退出游戏” → {\"results\": [{\"func\": \"bye\", \"args\": []}]}       \n\n14. go：- 移动动作\n    触发句式：往X走、去X、往X去、走向X、前往X\n    func固定为：go\n    args数组：[方位或地点]\n    示例：\n    - 输入“往东走” → {\"results\": [{\"func\": \"go\", \"args\": [\"东\"]}]}\n    - 输入“去月台” → {\"results\": [{\"func\": \"go\", \"args\": [\"月台\"]}]}\n\n15. job_info：描         述：查询职业详细信息。格式：job_info 职业名称\n\n## 兜底规则\n若输入无法匹配以上任意动作，输出：\n{\"results\": [{\"func\": \"unknown\", \"args\": []}]}\n\n## 强制约束\n1. 只输出一段完整JSON，不能分段、不能加markdown、不能有多余说明；\n2. args内文本原样提取，不修改、不增减文字；\n3. 严格遵循args参数顺序，         禁止调换顺序；\n4. JSON语法必须标准：双引号、逗号正确，无语法错误，保证程序可直接JSON.parse解析；\n5. 不输出思考过程、不举例、不回复自然语言，只返回JSON。\n\n当前用户输入：看看""",
    "stream": False,
    "temperature": 0,
    "nohistory": True,
    "keep_alive":-1,
    "stop":["<|im_start|>","<|im_end|>"],"format":"json","num_predict":256,"num_ctx":1024
}

start = time.time()
resp = requests.post(url, json=payload)
data = resp.json()
cost = (time.time() - start) * 1000

total = data["total_duration"] / 1e6
load = data["load_duration"] / 1e6
prefill_t = data["prompt_eval_duration"] / 1e6
prefill_tok = data["prompt_eval_count"]
decode_t = data["eval_duration"] / 1e6
decode_tok = data["eval_count"]

print(f"总延迟: {total:.2f} ms")
print(f"模型加载: {load:.2f} ms")
print(f"Prefill: {prefill_t:.2f} ms, {prefill_tok / (prefill_t/1000):.1f} tok/s")
print(f"Decode: {decode_t:.2f} ms, {decode_tok / (decode_t/1000):.1f} tok/s")
print(f"实测请求耗时: {cost:.2f} ms")
