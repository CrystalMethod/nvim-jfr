--- Keymap setup for nvim-jfr
-- Extracted so it can be invoked from setup().

local M = {}

M.setup = function(config)
  config = config or require("nvim-jfr.config").get()

  if config.keymaps == false then
    return
  end
  if type(config.keymaps) ~= "table" then
    return
  end
  if config.keymaps.enabled ~= true then
    return
  end

  local function map(key, cmd, desc)
    if not key or key == "" then
      return
    end
    vim.keymap.set("n", key, cmd, { desc = desc, silent = true })
  end

  local km = config.keymaps

  map(km.start, ":JFRStart<CR>", "nvim-jfr: Start recording")
  map(km.stop, ":JFRStop<CR>", "nvim-jfr: Stop recording")
  map(km.dump, ":JFRDump<CR>", "nvim-jfr: Dump recording")
  map(km.status, ":JFRStatus<CR>", "nvim-jfr: Status")
  -- km.open is an alias for recordings
  map(km.open, ":JFRRecordings<CR>", "nvim-jfr: Recordings")
  map(km.recordings, ":JFRRecordings<CR>", "nvim-jfr: List recordings")
  map(km.capabilities, ":JFRCapabilities<CR>", "nvim-jfr: Capabilities")

  -- Optional which-key integration.
  if km.which_key == true then
    pcall(function()
      local ok, wk = pcall(require, "which-key")
      if not ok or not wk then
        return
      end
      if type(wk.add) ~= "function" then
        return
      end

      local items = {}
      local function add(key, cmd, desc)
        if key and key ~= "" then
          table.insert(items, { key, cmd, desc = desc, mode = "n" })
        end
      end

      add(km.start, ":JFRStart<CR>", "Start recording")
      add(km.stop, ":JFRStop<CR>", "Stop recording")
      add(km.dump, ":JFRDump<CR>", "Dump recording")
      add(km.status, ":JFRStatus<CR>", "Status")
      add(km.open, ":JFRRecordings<CR>", "Recordings")
      add(km.recordings, ":JFRRecordings<CR>", "List recordings")
      add(km.capabilities, ":JFRCapabilities<CR>", "Capabilities")

      table.insert(items, { "<leader>jfr", group = "JFR", mode = "n" })
      wk.add(items)
    end)
  end
end

return M
