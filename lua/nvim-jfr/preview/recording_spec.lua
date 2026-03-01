--- Headless checks for nvim-jfr.preview.recording.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.preview.recording_spec').run())" -c "qa"

local M = {}

local preview = require("nvim-jfr.preview.recording")

M.run = function()
  local tmp = vim.fn.tempname() .. "_jfr_preview.jfr"
  local f = assert(io.open(tmp, "w"))
  f:write("x")
  f:close()

  local got = {}
  preview.render_async(tmp, {
    enabled = true,
    summary_max_kb = 128,
    timeout_ms = 50,
    jfr_command = "__definitely_missing_jfr__",
  }, function(text)
    table.insert(got, text)
  end)

  -- We should have at least one immediate render.
  assert(#got >= 1, "expected at least one callback")
  assert(got[1]:match("Path:") ~= nil)

  -- We should also see an error about missing jfr command.
  local ok2 = false
  for _, t in ipairs(got) do
    if t:match("jfr command not found") then
      ok2 = true
      break
    end
  end
  assert(ok2, "expected missing jfr command message")

  -- Cache behavior: same file+mtime+size should serve cached summary block.
  local got2 = {}
  preview.render_async(tmp, {
    enabled = true,
    summary_max_kb = 128,
    timeout_ms = 50,
    jfr_command = "__definitely_missing_jfr__",
  }, function(text)
    table.insert(got2, text)
  end)
  assert(#got2 >= 1)
  assert(got2[#got2]:match("jfr command not found") ~= nil)

  os.remove(tmp)
  return true
end

return M
