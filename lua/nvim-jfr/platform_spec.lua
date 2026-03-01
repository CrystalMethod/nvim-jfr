--- Minimal headless checks for nvim-jfr.platform.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.platform_spec').run())" -c "qa"

local M = {}

M.run = function()
  local p = require("nvim-jfr.platform")
  local a1 = p._system_open_argv("/tmp/x", "macos")
  assert(a1[1] == "open")

  local a2 = p._system_open_argv("C:/x", "windows")
  assert(a2[1] == "cmd.exe")

  local a3 = p._system_open_argv("/tmp/x", "linux")
  assert(a3[1] == "xdg-open")

  return true
end

return M
