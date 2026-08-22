package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

local safety = require("mud_lib/llm_safety")

local function expect(value, message)
  if not value then
    error(message or "expectation failed")
  end
end

local safe = safety.validate_command_result({
  results = { { func = "go", args = { "east" } } },
})
expect(safe and safe.results[1].func == "go", "safe go command should pass")

expect(not safety.validate_command_result({
  results = { { func = "reload", args = {} } },
}), "GM or unlisted command must be rejected")

expect(not safety.validate_command_result({
  results = {
    { func = "go", args = { "east" } },
    { func = "kill", args = { "enemy" } },
  },
}), "multiple commands must be rejected")

expect(not safety.validate_command_result({
  results = { { func = "go", args = { "east", "now" } } },
}), "extra command args must be rejected")

expect(not safety.validate_command_result({
  results = { { func = "look", args = { "door\nbye" } } },
}), "control characters must be rejected")

print("test_llm_safety: ok")
