--- vim.ui.select fallback picker implementation
--- @module nvim-jfr.picker.vim
---
--- NOTE: vim.ui.select doesn't support keeping picker open on empty results
--- The calling code needs to handle the "no recording" case by showing
--- a message and allowing user to retry

local M = {}

--- Pick using vim.ui.select (native Neovim)
---@param items table List of items (JVMs or recordings)
---@param opts table Options: {title, on_confirm, format_item?}
M.pick = function(items, opts)
  if opts and opts.multi == true then
    require("nvim-jfr.utils").notify("Multi-select is not supported by vim.ui.select; falling back to single-select", "warn")
  end
  vim.ui.select(items, {
    prompt = opts.title or "Select:",
    ---@param item any
    format_item = function(item)
      if type(opts.format_item) == "function" then
        return opts.format_item(item)
      end
      if type(item) ~= "table" then
        return tostring(item)
      end
      if item.pid and item.main_class then
        local v = item.java_version
        if v and tostring(v) ~= "" then
          return string.format("%d - %s (Java %s)", item.pid, item.main_class, tostring(v))
        end
        return string.format("%d - %s", item.pid, item.main_class)
      end
      if item.display then
        return item.display
      end
      if item.filename and item.rec_num then
        return tostring(item.rec_num) .. ": " .. tostring(item.filename)
      end
      if item.name then
        return tostring(item.name)
      end
      return vim.inspect(item)
    end,
  }, function(item)
    if item and opts.on_confirm then
      opts.on_confirm(item)
    end
  end)
end

return M
