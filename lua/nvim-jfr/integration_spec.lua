--- Opt-in integration smoke test for nvim-jfr against a real JVM.
--
-- Disabled by default.
--
-- Run (opt-in):
--   NVIM_JFR_ITEST=1 NVIM_JFR_PID=<pid> \
--     nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.integration_spec').run())" -c "qa"
--
-- Notes:
-- - If NVIM_JFR_PID is not set, we'll pick the first non-jcmd JVM from `jcmd -l`.

local M = {}

local function getenv_bool(name)
  local v = vim.env[name]
  if not v then
    return false
  end
  v = tostring(v):lower()
  return v == "1" or v == "true" or v == "yes" or v == "on"
end

local function pick_pid()
  local pid = tonumber(vim.env.NVIM_JFR_PID or "")
  if pid then
    return pid
  end

  local jvm = require("nvim-jfr.jvm")
  local list = jvm.list({ refresh = true })
  for _, p in ipairs(list or {}) do
    if p and p.pid and p.main_class and not tostring(p.main_class):find("jdk%.jcmd", 1, true) then
      return tonumber(p.pid)
    end
  end
  return nil
end

M.run = function()
  if not getenv_bool("NVIM_JFR_ITEST") then
    -- Skip by default.
    return true
  end

  local pid = pick_pid()
  assert(pid, "NVIM_JFR_ITEST=1 but no PID found; set NVIM_JFR_PID or start a JVM")

  local jfr = require("nvim-jfr.jfr")

  local function await(fn)
    local done = false
    local res
    fn(function(r)
      res = r
      done = true
    end)
    vim.wait(8000, function()
      return done
    end, 50)
    return res
  end

  -- Start a short recording.
  local start_res = await(function(cb)
    jfr.start({
      pid = pid,
      name = "nvim-jfr-itest",
      duration = "10s",
      filename = "nvim-jfr-itest.jfr",
      settings = "profile",
    }, cb)
  end)
  assert(start_res and start_res.ok, "JFR.start failed: " .. vim.inspect(start_res))

  -- Check should list at least one recording.
  local check_res = await(function(cb)
    jfr.check(pid, cb)
  end)
  assert(check_res and check_res.ok, "JFR.check failed: " .. vim.inspect(check_res))

  local recs = jfr.parse_recordings(check_res.stdout or "")
  assert(type(recs) == "table" and #recs >= 1, "expected at least one recording from JFR.check")

  -- Stop the recording; use recording number if we can find it.
  local target_rec = nil
  for _, r in ipairs(recs) do
    if r and r.name == "nvim-jfr-itest" then
      target_rec = r
      break
    end
  end

  local stop_name = target_rec and target_rec.rec_num and tostring(target_rec.rec_num) or "nvim-jfr-itest"
  local stop_res = await(function(cb)
    jfr.stop({ pid = pid, name = stop_name, filename = "nvim-jfr-itest-stop.jfr" }, cb)
  end)
  assert(stop_res and stop_res.ok, "JFR.stop failed: " .. vim.inspect(stop_res))

  return true
end

return M
