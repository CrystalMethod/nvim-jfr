--- Status model + query function for nvim-jfr.
--
-- This module provides a single function that queries a JVM for active
-- recordings and returns a small payload suitable for rendering in a float
-- or for generating notifications.

local M = {}

--- Query active recordings and return a status payload.
---
--- Payload shape:
--- {
---   pid: number,
---   recordings: table[],
---   last_artifact?: string,
---   last_output_dir?: string,
---   ok: boolean,
---   error?: string,
--- }
---
--- @param pid number
--- @param callback fun(payload: table)
M.query = function(pid, callback)
  pid = tonumber(pid)
  if not pid then
    callback({ ok = false, pid = nil, recordings = {}, error = "pid required" })
    return
  end

  local state = require("nvim-jfr.state")
  local jfr = require("nvim-jfr.jfr")
  local errors = require("nvim-jfr.errors")

  jfr.check(pid, function(res)
    if not res or not res.ok then
      callback({
        ok = false,
        pid = pid,
        recordings = {},
        last_artifact = state.get_last_artifact(),
        last_output_dir = state.get_last_output_dir(),
        error = errors.format_jcmd_error("JFR.check failed", res),
        raw = res,
      })
      return
    end

    callback({
      ok = true,
      pid = pid,
      recordings = jfr.parse_recordings(res.stdout or ""),
      last_artifact = state.get_last_artifact(),
      last_output_dir = state.get_last_output_dir(),
      raw = res,
    })
  end)
end

return M
