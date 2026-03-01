--- Headless checks for nvim-jfr.jfc_templates.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.jfc_templates_spec').run())" -c "qa"

local M = {}

M.run = function()
  local mod = require("nvim-jfr.jfc_templates")

  -- list() should return an empty list when dirs don't exist
  do
    local cfg = {
      jfc_templates = {
        project_dirs = { "nope" },
      },
    }
    local items = mod.list(cfg)
    assert(type(items) == "table")
    assert(#items == 0)
  end

  -- get_template_dirs should include java_home when enabled + JAVA_HOME set
  do
    local old = vim.env.JAVA_HOME
    vim.env.JAVA_HOME = "/tmp"
    local cfg = {
      jfc_templates = {
        project_dirs = {},
        include_java_home = true,
      },
    }
    local dirs = mod.get_template_dirs(cfg)
    assert(type(dirs) == "table")
    assert(dirs[1] and dirs[1].source == "java_home")
    vim.env.JAVA_HOME = old
  end

  return true
end

return M
