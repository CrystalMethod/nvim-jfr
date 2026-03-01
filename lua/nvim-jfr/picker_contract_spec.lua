--- Headless checks for picker backend contract.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.picker_contract_spec').run())" -c "qa"

local M = {}

M.run = function()
  local picker = require("nvim-jfr.picker")

  -- detect() always returns a backend string.
  local eff = picker.detect("auto")
  assert(type(eff) == "string" and eff ~= "")

  -- telescope/fzf modules should load without executing UI in headless.
  -- (We can't simulate picker UI headless; just ensure module functions exist.)
  local ok_t, t = pcall(require, "nvim-jfr.picker.telescope")
  if ok_t then
    assert(type(t.pick) == "function")
  end
  local ok_f, f = pcall(require, "nvim-jfr.picker.fzf")
  if ok_f then
    assert(type(f.pick) == "function")
  end
  local ok_v, v = pcall(require, "nvim-jfr.picker.vim")
  assert(ok_v and type(v.pick) == "function")

  return true
end

return M
