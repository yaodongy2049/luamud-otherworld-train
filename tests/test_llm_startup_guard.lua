IS_LLM_ENABLED = true
OLLAMA_HOST = "http://127.0.0.1:1"
LLM_MODEL = "unused"
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

-- The legacy self-test must remain opt-in; module loading should not change this flag.
local llm = require("mud_os/llm_input")
if not llm or not IS_LLM_ENABLED then
  error("LLM module load must not run the legacy self-test or disable LLM")
end

print("test_llm_startup_guard: ok")
