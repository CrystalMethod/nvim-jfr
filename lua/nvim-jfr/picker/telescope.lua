--- Telescope picker implementation
--- @module nvim-jfr.picker.telescope
---
--- NOTE: When implementing stop/dump commands that check for active recordings:
--- - If no recordings found on selected JVM, telescope can reopen via callback
--- - Consider using telescope's built-in actions or re-pick functionality

local M = {}

--- Pick using telescope
---@param items table List of items (JVMs or recordings)
---@param opts table Options: {title, on_confirm}
M.pick = function(items, opts)
  local telescope = require("telescope")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  -- Build entry maker based on item type
  local entry_maker = function(entry)
    -- Detect item type
    if entry.pid and entry.main_class then
      -- JVM item
      local disp
      if entry.java_version and tostring(entry.java_version) ~= "" then
        disp = string.format("%d - %s (Java %s)", entry.pid, entry.main_class, tostring(entry.java_version))
      else
        disp = string.format("%d - %s", entry.pid, entry.main_class)
      end
      return {
        value = entry,
        display = disp,
        ordinal = tostring(entry.pid) .. " " .. entry.main_class .. " " .. tostring(entry.java_version or ""),
      }
    elseif entry.display then
      -- Generic item with explicit display (e.g. file lists)
      return {
        value = entry,
        display = entry.display,
        ordinal = entry.display,
      }
    elseif entry.name and entry.id then
      -- Recording item
      return {
        value = entry,
        display = entry.display or entry.name,
        ordinal = entry.display or entry.name,
      }
    else
      -- Generic
      return {
        value = entry,
        display = tostring(entry),
        ordinal = tostring(entry),
      }
    end
  end

  -- NOTE: multi-select is not implemented yet for telescope backend.
  if opts and opts.multi == true then
    require("nvim-jfr.utils").notify("Multi-select is not implemented for telescope picker; using single-select", "warn")
  end

  pickers.new(opts, {
    prompt_title = opts.title or "Select",
    finder = finders.new_table({
      results = items,
      entry_maker = entry_maker,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      local function confirm_one()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if opts and type(opts.on_confirm) == "function" then
          opts.on_confirm(selection and selection.value or nil)
        end
      end

      actions.select_default:replace(confirm_one)
      map("i", "<CR>", confirm_one)
      map("n", "<CR>", confirm_one)
      return true
    end,
  }):find()
end

return M
