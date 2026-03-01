--- nvim-jfr - Java Flight Recorder control for Neovim
--- A plugin to start/stop/dump JFR recordings from within Neovim
---
--- @module nvim-jfr
--- @license MIT
--- @release 0.1.0

local M = {}

-- Load submodules
M.config = require("nvim-jfr.config")
M.platform = require("nvim-jfr.platform")
M.jvm = require("nvim-jfr.jvm")
M.jfr = require("nvim-jfr.jfr")
M.project = require("nvim-jfr.project")
M.picker = require("nvim-jfr.picker")
M.utils = require("nvim-jfr.utils")
M.jfc_templates = require("nvim-jfr.jfc_templates")

--- Setup the plugin with user configuration
---@param opts table? User configuration options
M.setup = function(opts)
  -- Merge user options with defaults
  M.config.setup(opts)

  -- Mark configured so plugin loader can distinguish between
  -- explicit user setup vs implicit defaults.
  vim.g.nvim_jfr_configured = true

  -- Setup project context refresh autocmds (respects config.watch_project_switch).
  pcall(function()
    require("nvim-jfr.context").setup()
  end)

  -- Setup keymaps (opt-in) and optional which-key registration.
  pcall(function()
    require("nvim-jfr.keymaps").setup(M.get_config())
  end)

  -- Register commands (deferred to plugin/loader for lazy loading)
end

--- Get the current configuration
---@return table Current configuration
M.get_config = function()
  return M.config.get()
end

return M
