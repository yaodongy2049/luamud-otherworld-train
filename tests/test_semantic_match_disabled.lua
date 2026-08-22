IS_LLM_ENABLED = true
IS_SEMANTIC_MATCH_ENABLED = false
OLLAMA_HOST = "http://127.0.0.1:1"
EMB_MODEL = "unused"
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

local semantic = require("mud_os/semantic_match")
semantic.add_match_src("月台")

if semantic.best_match("月台", { "月台" }) ~= nil then
  error("semantic matching must remain disabled without an explicit embedding backend")
end

-- This must return without opening any HTTP connection.
semantic.preload_base_emb()
print("test_semantic_match_disabled: ok")
