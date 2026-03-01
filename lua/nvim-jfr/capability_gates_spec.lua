--- Test matrix for capability gating.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.capability_gates_spec').run())" -c "qa"

local M = {}

M.run = function()
  local settings = require("nvim-jfr.settings")

  -- 1) If JVM explicitly does not support settings=, reject.
  do
    local ok, err = settings.validate_supported("profile", { jfr = { start_options = { name = true } } })
    assert(ok == false)
    assert(type(err) == "string" and err:find("settings=", 1, true) ~= nil)
  end

  -- 2) If JVM reports a preset list and profile isn't in it, reject with supported list.
  do
    local cap = {
      jfr = {
        start_options = { settings = true },
        settings_presets_found = true,
        settings_presets = { default = true },
      },
    }
    local ok, err = settings.validate_supported("profile", cap)
    assert(ok == false)
    assert(err:find("Supported presets", 1, true) ~= nil)
    assert(err:find("default", 1, true) ~= nil)
  end

  -- 3) Paths should not be validated against preset list.
  do
    local cap = {
      jfr = {
        start_options = { settings = true },
        settings_presets_found = true,
        settings_presets = { default = true },
      },
    }
    local ok, err = settings.validate_supported("/tmp/custom.jfc", cap)
    assert(ok == true)
    assert(err == nil)
  end

  return true
end

return M
