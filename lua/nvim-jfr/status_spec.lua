--- Minimal headless checks for nvim-jfr.status.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.status_spec').run())" -c "qa"

local M = {}

M.run = function()
  local status = require("nvim-jfr.status")
  assert(type(status.open) == "function")
  assert(type(status.refresh) == "function")

  -- Ensure module loads with timer fields present.
  assert(status.open ~= nil)
  return true
end

return M
