--- Minimal headless checks for nvim-jfr.context.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.context_spec').run())" -c "qa"

local M = {}

M.run = function()
  local ctx = require("nvim-jfr.context")

  -- setup is idempotent
  ctx.setup()
  ctx.setup()

  -- refresh should never error
  ctx.refresh()

  return true
end

return M
