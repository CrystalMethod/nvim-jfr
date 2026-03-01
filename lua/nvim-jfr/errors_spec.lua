--- Minimal headless checks for nvim-jfr.errors.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.errors_spec').run())" -c "qa"

local M = {}

local errors = require("nvim-jfr.errors")

M.run = function()
  local msg1 = errors.format_jcmd_error("Failed", { ok = false, stderr = "jcmd not found", stdout = "" })
  assert(msg1:find("Recovery:", 1, true) ~= nil)
  assert(msg1:lower():find("jcmd", 1, true) ~= nil)

  local msg2 = errors.format_jcmd_error("Failed", { ok = false, stderr = "Flight Recorder is not enabled", stdout = "" })
  assert(msg2:lower():find("flight recorder", 1, true) ~= nil)
  assert(msg2:find("-XX:+FlightRecorder", 1, true) ~= nil)

  local msg3 = errors.format_jcmd_error("Failed", { ok = false, stderr = "Operation not permitted", stdout = "" })
  assert(msg3:lower():find("attach", 1, true) ~= nil)

  return true
end

return M
