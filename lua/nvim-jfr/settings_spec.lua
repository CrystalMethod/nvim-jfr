--- Minimal headless checks for nvim-jfr.settings.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.settings_spec').run())" -c "qa"

local M = {}

local settings = require("nvim-jfr.settings")

M.run = function()
  -- Create a temp .jfc file
  local tmp = vim.fn.tempname() .. ".jfc"
  local f = assert(io.open(tmp, "w"))
  f:write("<?xml version='1.0' encoding='UTF-8'?>\n")
  f:close()

  -- Explicit settings value wins (path)
  local v1 = assert(settings.resolve({ settings_value = tmp }))
  assert(v1 == tmp)

  -- Configured settings value wins when no explicit one
  local v2 = assert(settings.resolve({ configured_settings_value = tmp }))
  assert(v2 == tmp)

  -- Built-in settings
  local v3 = assert(settings.resolve({ settings_value = "default" }))
  assert(v3 == "default")

  -- Missing file should error
  local missing = tmp .. ".missing"
  local ok, err = settings.resolve({ settings_value = missing })
  assert(ok == nil)
  assert(type(err) == "string" and err:find("does not exist", 1, true))

  -- Capability validation: reject if settings option missing
  local ok2, err2 = settings.validate_supported("profile", { jfr = { start_options = { name = true } } })
  assert(ok2 == false)
  assert(err2:find("settings=", 1, true) ~= nil)

  os.remove(tmp)
  return true
end

return M
