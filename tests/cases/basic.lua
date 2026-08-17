---@module "tests/cases/basic"
---@description 基础功能测试：连接、注册、基础命令

---基础功能测试集合
---@param TF TestFramework 测试框架实例
return function(TF)
    -- 测试1: 连接欢迎信息
    TF.run_test("连接欢迎信息", function()
        local c = TF.connect()
        TF.assert_output_contains(c, "欢迎光临", "应显示欢迎信息")
        TF.assert_output_contains(c, "请输入用户名", "应提示输入用户名")
    end)

    -- 测试2: 新用户注册流程
    TF.run_test("新用户注册", function()
        local uname = "test_reg_" .. os.time()
        local c = TF.connect()
        TF.send(c, uname)
        TF.assert_output_contains(c, "设置密码", "应提示设置密码")
        TF.send(c, "pass123")
        TF.assert_output_contains(c, "再次输入密码", "应要求确认密码")
        TF.send(c, "pass123")
        TF.assert_output_contains(c, "创建成功", "应创建成功")
        TF.assert_output_contains(c, "登录成功", "应自动登录")
    end)

    -- 测试3: 密码不匹配
    TF.run_test("两次密码不一致", function()
        local uname = "test_mm_" .. os.time()
        local c = TF.connect()
        TF.send(c, uname)
        TF.send(c, "pass1")
        TF.send(c, "pass2")
        TF.assert_output_contains(c, "两次密码不一致", "应提示密码不一致")
    end)

    -- 测试4: 已存在用户登录
    TF.run_test("已有用户登录", function()
        local uname = "test_login_" .. os.time()
        local c1 = TF.register_user(uname, "mypass")
        TF.disconnect(c1)
        
        local c2 = TF.connect()
        TF.send(c2, uname)
        TF.assert_output_contains(c2, "请输入密码", "应提示输入密码")
        TF.send(c2, "mypass")
        TF.assert_output_contains(c2, "登录成功", "应登录成功")
    end)

    -- 测试5: 错误密码
    TF.run_test("错误密码", function()
        local uname = "test_wp_" .. os.time()
        TF.register_user(uname, "rightpass")
        
        local c = TF.connect()
        TF.send(c, uname)
        TF.send(c, "wrongpass")
        TF.assert_output_contains(c, "错误的用户名或密码", "应提示密码错误")
    end)

    -- 测试6: look命令
    TF.run_test("look命令", function()
        local c = TF.register_user("test_look_" .. os.time())
        TF.assert_output_contains(c, "车站入口大厅", "应看到房间名")
        TF.assert_output_contains(c, "出口", "应看到出口列表")
        TF.send(c, "look")
        TF.assert_output_contains(c, "车站入口大厅", "look后也应看到房间名")
    end)

    -- 测试7: say命令（对房间内所有人说话）
    TF.run_test("say说话命令", function()
        local n1 = "alice_" .. os.time()
        local n2 = "bob_" .. os.time()
        local c1 = TF.register_user(n1)
        local c2 = TF.register_user(n2)
        TF.send(c1, "say 你好")
        TF.assert_output_contains(c1, "你说道", "自己能看到说话内容")
        TF.assert_output_contains(c2, n1, "同房间的人能看到说话者")
        TF.assert_output_contains(c2, "你好", "同房间的人能听到内容")
    end)

    -- 测试8: go命令（移动）
    TF.run_test("go移动命令", function()
        local c = TF.register_user("gotest_" .. os.time())
        TF.send(c, "go east")
        TF.assert_output_contains(c, "月台", "移动后应看到月台房间描述")
    end)

    -- 测试9: who命令 - 多个用户
    TF.run_test("who命令-多个用户", function()
        local n1 = "whoalice_" .. os.time()
        local n2 = "whobob_" .. os.time()
        local c1 = TF.register_user(n1)
        local c2 = TF.register_user(n2)
        TF.send(c1, "who")
        TF.assert_output_contains(c1, n1, "应看到第一个用户")
        TF.assert_output_contains(c1, n2, "应看到第二个用户")
        TF.assert_output_contains(c1, "2 位玩家在线", "应显示在线人数2")
    end)
end