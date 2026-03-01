--- Picker abstraction module
--- @module nvim-jfr.picker
---
--- PICKER DESIGN NOTES:
--- - All pickers should handle both JVM items and Recording items
--- - For "stop recording" workflow where no recordings exist:
---   - Snacks: Cannot keep picker open - show message and let user retry
---   - Telescope: Could implement re-pick action for retry
---   - fzf-lua: Could implement action for retry
---   - vim.ui.select: Cannot keep open - same as Snacks

local M = {}

-- Available pickers in priority order
local PICKERS = { "snacks", "telescope", "fzf", "vim" }

--- Check if a picker is available
---@param picker string Picker name
---@return boolean True if picker is available
M.is_available = function(picker)
  if picker == "snacks" then
    local ok, _ = pcall(require, "snacks.picker")
    return ok
  elseif picker == "telescope" then
    local ok, _ = pcall(require, "telescope")
    return ok
  elseif picker == "fzf" then
    local ok, _ = pcall(require, "fzf-lua")
    return ok
  end
  return false
end

--- Detect the best available picker
---@param preferred string? User preferred picker
---@return string Picker name
M.detect = function(preferred)
  -- If user specified a preference, use it if available
  if preferred and preferred ~= "auto" then
    if M.is_available(preferred) then
      return preferred
    end
    require("nvim-jfr.utils").notify("Preferred picker '" .. preferred .. "' not available", "warn")
  end

  -- Auto-detect in priority order
  for _, picker in ipairs(PICKERS) do
    if M.is_available(picker) then
      return picker
    end
  end

  return "vim" -- Fallback to native
end

--- Pick an item from a list
---@param items table List of items to pick from
---@param opts table Options: {title, format, on_confirm, picker}
M.pick = function(items, opts)
  opts = opts or {}
  local picker = M.detect(opts.picker)

  if picker == "snacks" then
    require("nvim-jfr.picker.snacks").pick(items, opts)
  elseif picker == "telescope" then
    require("nvim-jfr.picker.telescope").pick(items, opts)
  elseif picker == "fzf" then
    require("nvim-jfr.picker.fzf").pick(items, opts)
  else
    require("nvim-jfr.picker.vim").pick(items, opts)
  end
end

return M
