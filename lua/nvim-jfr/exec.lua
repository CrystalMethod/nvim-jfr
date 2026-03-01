--- Tiny process execution helper.
--
-- Provides a minimal, synchronous wrapper over `vim.system` (0.10+)
-- and `jobstart/jobwait` (0.8+) to avoid shell quoting issues.

local M = {}

local function append_lines(dst, data)
  if not data then
    return
  end
  for _, line in ipairs(data) do
    if line and line ~= "" then
      table.insert(dst, line)
    end
  end
end

--- Run argv synchronously.
--- @param argv string[]
--- @param opts? table { timeout_ms?:integer }
--- @return table res { ok:boolean, code:integer, stdout:string, stderr:string, timed_out:boolean }
M.run = function(argv, opts)
  opts = opts or {}
  local timeout_ms = opts.timeout_ms or 5000

  -- Prefer vim.system on newer Neovim.
  if type(vim.system) == "function" then
    local obj = vim.system(argv, { text = true, timeout = timeout_ms })
    local res = obj:wait()
    return {
      ok = (res.code == 0),
      code = res.code or -1,
      stdout = res.stdout or "",
      stderr = res.stderr or "",
      timed_out = res.signal == 9, -- best-effort
    }
  end

  -- Fallback: jobstart/jobwait.
  local stdout_lines, stderr_lines = {}, {}
  local timed_out = false

  local jobid = vim.fn.jobstart(argv, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      append_lines(stdout_lines, data)
    end,
    on_stderr = function(_, data)
      append_lines(stderr_lines, data)
    end,
  })

  if jobid <= 0 then
    return {
      ok = false,
      code = jobid,
      stdout = "",
      stderr = "Failed to start job (jobid=" .. tostring(jobid) .. ")",
      timed_out = false,
    }
  end

  local wait = vim.fn.jobwait({ jobid }, timeout_ms)
  local code = (wait and wait[1]) or -1
  if code == -1 then
    timed_out = true
    pcall(vim.fn.jobstop, jobid)
  end

  return {
    ok = code == 0,
    code = code,
    stdout = table.concat(stdout_lines, "\n"),
    stderr = table.concat(stderr_lines, "\n"),
    timed_out = timed_out,
  }
end

return M
