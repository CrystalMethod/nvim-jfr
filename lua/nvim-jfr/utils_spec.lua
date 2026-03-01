--- Minimal headless checks for nvim-jfr.utils.notify.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.utils_spec').run())" -c "qa"

local M = {}

M.run = function()
  local utils = require("nvim-jfr.utils")
  local cfg = require("nvim-jfr.config")

  local calls = {}
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    table.insert(calls, { msg = msg, level = level, opts = opts })
  end

  -- notifications enabled
  cfg.setup({ notifications = true })
  local shown = utils.notify("hello", "info")
  assert(shown == true)
  assert(#calls == 1)
  assert(calls[1].msg == "hello")
  assert(type(calls[1].opts) == "table" and calls[1].opts.title == "nvim-jfr")

  -- throttle: second call suppressed
  local shown2 = utils.notify("throttle", "info", { throttle_ms = 1000, dedupe_key = "k" })
  local shown3 = utils.notify("throttle", "info", { throttle_ms = 1000, dedupe_key = "k" })
  assert(shown2 == true)
  assert(shown3 == false)

  -- notifications disabled
  cfg.setup({ notifications = false })
  local shown4 = utils.notify("nope", "warn")
  assert(shown4 == false)

  vim.notify = orig
  return true
end

return M
