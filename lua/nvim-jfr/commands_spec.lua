--- Minimal headless checks for nvim-jfr.commands.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.commands_spec').run())" -c "qa"

local M = {}

local commands = require("nvim-jfr.commands")

M.run = function()
  local o = commands.parse_args({ "--duration=10s", "--settings=profile" })
  assert(o.duration == "10s")
  assert(o.settings == "profile")

  local o2 = commands.parse_args({ "--settings=default" })
  assert(o2.settings == "default")

  -- ensure :JFRCapabilities modifier is wired (signature accepts cmdopts)
  assert(type(commands.capabilities) == "function")

  -- Start overrides: unknown keys become overrides (direct style)
  local ov = commands.parse_start_overrides({ "--duration=10s", "--maxage=5m", "--maxsize=250M" })
  assert(ov.maxage == "5m")
  assert(ov.maxsize == "250M")
  assert(ov.duration == nil)

  -- Start overrides: wrapper style
  local ov2 = commands.parse_start_overrides({ "--opt=maxage=10m" })
  assert(ov2.maxage == "10m")

  -- Reserved settings should not become overrides
  local ov3 = commands.parse_start_overrides({ "--settings=profile" })
  assert(next(ov3) == nil)

  -- Reserved run config selector should not become overrides
  local ov4 = commands.parse_start_overrides({ "--run=none", "--maxage=5m" })
  assert(ov4.run == nil)
  assert(ov4.maxage == "5m")

  -- Run configs list items should be shaped for pickers (name/id/display)
  local run_mod = require("nvim-jfr.run_configs")
  -- List on missing root should not throw
  local items = select(1, run_mod.list(""))
  assert(type(items) == "table")
  return true
end

return M
