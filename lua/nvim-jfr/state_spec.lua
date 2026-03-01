--- Minimal headless checks for nvim-jfr.state.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.state_spec').run())" -c "qa"

local M = {}

M.run = function()
  local s = require("nvim-jfr.state")
  assert(s.get_last_artifact() == nil)
  s.set_last_artifact("/tmp/a.jfr")
  assert(s.get_last_artifact() == "/tmp/a.jfr")

  assert(s.get_last_output_dir() == nil)
  s.set_last_output_dir("/tmp/out")
  assert(s.get_last_output_dir() == "/tmp/out")

  assert(s.get_current_recording() == nil)
  s.set_current_recording({ pid = 1, name = "x", filename = "y" })
  local r = s.get_current_recording()
  assert(type(r) == "table" and r.pid == 1)
  return true
end

return M
