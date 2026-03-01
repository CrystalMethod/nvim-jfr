--- Minimal headless checks for nvim-jfr.overrides.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.overrides_spec').run())" -c "qa"

local M = {}

M.run = function()
  local o = require("nvim-jfr.overrides")

  local base = { name = "r", duration = "10s" }
  local supported = { name = true, duration = true, maxage = true }

  local merged, applied, rejected = o.apply(base, { maxage = "1m", nope = "x" }, supported)
  assert(merged.maxage == "1m")
  assert(merged.nope == nil)
  assert(#applied == 1 and applied[1] == "maxage")
  assert(#rejected == 1 and rejected[1] == "nope")

  -- Empty supported-set should allow keys (unknown capabilities).
  local merged_empty = select(1, o.apply(base, { foo = "bar" }, {}))
  assert(merged_empty.foo == "bar")

  -- When supported is nil, accept all keys.
  local merged2 = select(1, o.apply(base, { foo = "bar" }, nil))
  assert(merged2.foo == "bar")

  return true
end

return M
