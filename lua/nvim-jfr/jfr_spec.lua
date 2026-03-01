--- Minimal headless checks for nvim-jfr.jfr.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.jfr_spec').run())" -c "qa"

local M = {}

local jfr = require("nvim-jfr.jfr")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq failed") .. ": expected=" .. vim.inspect(b) .. " got=" .. vim.inspect(a))
  end
end

M.run = function()
  -- parse_recordings should tolerate richer values (non-%w)
  local sample = table.concat({
    "24152:",
    "Recording 1: name=recording,duration=60 s,filename=/tmp/rec 1.jfr,settings=profile maxsize=250.0MB (running)",
    "Recording 2: name=my-recording,duration=5m,filename=recording_2.jfr,settings=default (running)",
    "",
  }, "\n")

  local recs = jfr.parse_recordings(sample)
  assert_eq(#recs, 2, "expected two recordings")
  assert_eq(recs[1].rec_num, 1)
  assert_eq(recs[1].filename, "/tmp/rec 1.jfr")
  assert_eq(recs[2].name, "my-recording")

  -- Some JDKs omit filename; we should still return a recording entry.
  local sample_no_filename = table.concat({
    "Recording 7: name=recording,duration=60s,settings=profile maxsize=250.0MB (running)",
  }, "\n")
  local recs2 = jfr.parse_recordings(sample_no_filename)
  assert_eq(#recs2, 1, "expected one recording without filename")
  assert_eq(recs2[1].rec_num, 7)
  assert_eq(recs2[1].filename, nil)

  return true
end

-- Optional integration spec lives in nvim-jfr.integration_spec (opt-in via env).

return M
