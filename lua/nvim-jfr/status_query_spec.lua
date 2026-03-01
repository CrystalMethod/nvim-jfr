--- Minimal headless checks for nvim-jfr.status_query.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.status_query_spec').run())" -c "qa"

local M = {}

M.run = function()
  local q = require("nvim-jfr.status_query")
  assert(type(q.query) == "function")

  -- pid validation path should be synchronous.
  local got = nil
  q.query(nil, function(p)
    got = p
  end)
  assert(type(got) == "table")
  assert(got.ok == false)
  assert(got.recordings and type(got.recordings) == "table")
  return true
end

return M
