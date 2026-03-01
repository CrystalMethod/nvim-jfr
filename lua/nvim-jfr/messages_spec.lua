--- Minimal headless checks for nvim-jfr.messages.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.messages_spec').run())" -c "qa"

local M = {}

M.run = function()
  local m = require("nvim-jfr.messages")
  local x = m.no_jvms()
  assert(type(x.text) == "string" and x.text ~= "")
  assert(type(x.level) == "string")
  assert(type(x.opts) == "table" and x.opts.title == "nvim-jfr")

  local y = m.start_ok("/tmp/a.jfr", { "foo" }, "profile")
  assert(y.level == "warn")
  assert(y.text:find("Next:", 1, true) ~= nil)
  assert(y.text:find("Settings:", 1, true) ~= nil)

  local z = m.dump_ok_one("/tmp/b.jfr")
  assert(z.text:find(":JFRRecordings", 1, true) ~= nil)

  local o = m.start_overrides_rejected({ "maxage" })
  assert(o.level == "warn")
  assert(o.text:find("Ignored unsupported overrides", 1, true) ~= nil)

  return true
end

return M
