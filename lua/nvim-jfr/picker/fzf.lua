--- fzf-lua picker implementation
--- @module nvim-jfr.picker.fzf
---
--- NOTE: fzf-lua supports actions that can reopen picker on no results
--- Consider implementing a "retry" action for stop/dump when no recordings found

local M = {}

--- Pick using fzf-lua
---@param items table List of items (JVMs or recordings)
---@param opts table Options: {title, on_confirm}
M.pick = function(items, opts)
  local fzf = require("fzf-lua")

  -- NOTE: multi-select is not implemented yet for fzf-lua backend.
  if opts and opts.multi == true then
    require("nvim-jfr.utils").notify("Multi-select is not implemented for fzf-lua picker; using single-select", "warn")
  end

  -- Build display strings based on item type
  local formatted = {}
  for _, item in ipairs(items) do
    local display
    if item.pid and item.main_class then
      if item.java_version and tostring(item.java_version) ~= "" then
        display = string.format("%d - %s (Java %s)", item.pid, item.main_class, tostring(item.java_version))
      else
        display = string.format("%d - %s", item.pid, item.main_class)
      end
    elseif item.display then
      display = item.display
    elseif item.name and item.id then
      display = item.display or item.name
    else
      display = tostring(item)
    end
    -- Ensure display is unique so reverse-mapping works.
    if formatted._seen == nil then
      formatted._seen = {}
    end
    local base = display
    local n = 1
    while formatted._seen[display] do
      n = n + 1
      display = string.format("%s (%d)", base, n)
    end
    formatted._seen[display] = true
    table.insert(formatted, display)
  end

  -- Map display string -> original item for reliable selection.
  local display_to_item = {}
  for i, disp in ipairs(formatted) do
    display_to_item[disp] = items[i]
  end

  local function normalize_selected(sel)
    if sel == nil then
      return nil
    end
    if type(sel) == "table" then
      return sel
    end
    return { sel }
  end

  fzf.fzf(formatted, {
    prompt = (opts.title or "Select") .. ": ",
    -- NOTE: This does not enable multi-select; it just normalizes callback shape
    -- across different fzf-lua versions.
  }, function(selected)
    if type(opts and opts.on_confirm) ~= "function" then
      return
    end
    local sel = normalize_selected(selected)
    if not sel or #sel == 0 then
      return
    end
    local chosen = {}
    for _, disp in ipairs(sel) do
      local item = display_to_item[disp]
      if item ~= nil then
        table.insert(chosen, item)
      end
    end
    if opts and opts.multi == true then
      opts.on_confirm(chosen)
    else
      opts.on_confirm(chosen[1])
    end
  end)
end

return M
