--- Project context tracking / cache invalidation.
--- @module nvim-jfr.context

local M = {}

local _setup = false

--- Clear caches that depend on project/cwd context.
M.refresh = function()
  -- Root cache is keyed by buffer/cwd; clear so next call recomputes.
  pcall(function()
    require("nvim-jfr.project").clear_root_cache()
  end)

  -- JVM list cache affects scoped pickers; clear to avoid stale lists.
  pcall(function()
    require("nvim-jfr.jvm").clear_cache()
  end)
end

--- Setup autocmds to refresh context when switching projects.
M.setup = function()
  if _setup then
    return
  end
  _setup = true

  local ok_cfg, cfg_mod = pcall(require, "nvim-jfr.config")
  local cfg = ok_cfg and cfg_mod and cfg_mod.get() or {}
  if cfg.watch_project_switch == false then
    return
  end

  local group = vim.api.nvim_create_augroup("nvim-jfr-context", { clear = true })

  -- :cd/:tcd/:lcd and similar
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    desc = "nvim-jfr: refresh project context",
    callback = function()
      M.refresh()
    end,
  })

  -- When editing a file in a different tree, ensure caches don't pin old cwd.
  vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost" }, {
    group = group,
    desc = "nvim-jfr: refresh project context on buffer switch",
    callback = function()
      -- Cheap + safe: root cache has a TTL, but this makes switches immediate.
      M.refresh()
    end,
  })
end

return M
