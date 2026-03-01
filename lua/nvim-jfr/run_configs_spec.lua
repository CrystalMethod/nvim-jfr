--- Headless spec for nvim-jfr.run_configs.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.run_configs_spec').run())" -c "qa"

local M = {}

M.run = function()
  local run_mod = require("nvim-jfr.run_configs")
  local platform = require("nvim-jfr.platform")

  -- Use a temp dir as a fake project root.
  local root = vim.fn.tempname()
  vim.fn.mkdir(platform.join_path(root, ".jfr", "templates"), "p")

  -- Create a settings file under the required dir.
  local jfc = platform.join_path(root, ".jfr", "templates", "ok.jfc")
  vim.fn.writefile({ "<xml/>" }, jfc)

  -- A path outside should be rejected.
  local outside = platform.join_path(root, "..", "outside.jfc")
  local _, err1 = run_mod.resolve_run_settings(root, outside)
  assert(err1 ~= nil)

  -- Relative path under .jfr/templates should resolve.
  local ok_path, err2 = run_mod.resolve_run_settings(root, ".jfr/templates/ok.jfc")
  assert(err2 == nil)
  assert(ok_path ~= nil)
  assert(vim.fn.filereadable(ok_path) == 1)

  -- Built-ins pass through.
  local p = assert(run_mod.resolve_run_settings(root, "profile"))
  assert(p == "profile")
  local d = assert(run_mod.resolve_run_settings(root, "default"))
  assert(d == "default")

  return true
end

return M
