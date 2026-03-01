--- JFR command execution module
--- @module nvim-jfr.jfr

local M = {}

--- Execute a jcmd command asynchronously.
---
--- Callback receives a result table:
---   { ok:boolean, code:integer, stdout:string, stderr:string, timed_out:boolean? }
---
---@param pid number JVM process ID
---@param command string JFR command (e.g., "JFR.start")
---@param args string|table? Command arguments (prefer table)
---@param callback fun(res: table)?
---@param opts table? Options: { timeout_ms: number? }
M.jcmd = function(pid, command, args, callback, opts)
  opts = opts or {}

  -- Fail fast when jcmd is not available.
  if vim.fn.executable("jcmd") ~= 1 then
    if callback then
      callback({
        ok = false,
        code = 127,
        stdout = "",
        stderr = "jcmd not found",
      })
    end
    return
  end

  local function normalize_args(a)
    if a == nil then
      return {}
    end
    if type(a) == "table" then
      return a
    end
    if type(a) == "string" then
      local s = vim.trim(a)
      if s == "" then
        return {}
      end
      -- Best-effort legacy behavior: split on whitespace.
      -- If you need spaces inside a value, pass args as a table.
      return vim.split(s, "%s+", { trimempty = true })
    end
    return {}
  end

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

  local argv = { "jcmd", tostring(pid), command }
  vim.list_extend(argv, normalize_args(args))

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
    on_exit = function(_, code)
      if callback then
        callback({
          ok = code == 0,
          code = code,
          stdout = table.concat(stdout_lines, "\n"),
          stderr = table.concat(stderr_lines, "\n"),
          timed_out = timed_out,
        })
      end
    end,
  })

  if jobid <= 0 then
    if callback then
      callback({
        ok = false,
        code = jobid,
        stdout = "",
        stderr = "Failed to start jcmd job (jobid=" .. tostring(jobid) .. ")",
      })
    end
    return
  end

  if opts.timeout_ms and opts.timeout_ms > 0 then
    vim.defer_fn(function()
      -- jobwait returns -1 when still running
      local status = vim.fn.jobwait({ jobid }, 0)
      if status and status[1] == -1 then
        timed_out = true
        pcall(vim.fn.jobstop, jobid)
      end
    end, opts.timeout_ms)
  end
end

--- Start a JFR recording
---
--- opts may optionally provide `_start_opts_override` (table) which will be
--- used instead of the defaults-derived start options. This enables
--- higher-level modules to add additional keys (overrides) while still
--- benefiting from capability-based filtering.
---
---@param opts table Options: {pid, name, duration, filename, settings, _start_opts_override?:table}
---@param callback fun(res: table)?
M.start = function(opts, callback)
  local start_opts = opts._start_opts_override
  if type(start_opts) ~= "table" then
    start_opts = {
      name = opts.name or "recording",
      duration = opts.duration or "60s",
      filename = opts.filename or "recording.jfr",
    }
    if opts.settings then
      start_opts.settings = opts.settings
    end
  end

  local function to_args(tbl)
    local out = {}
    for k, v in pairs(tbl or {}) do
      table.insert(out, string.format("%s=%s", k, tostring(v)))
    end
    table.sort(out)
    return out
  end

  -- Capability-aware option gating.
  local ok_caps, caps = pcall(require, "nvim-jfr.capabilities")
  if ok_caps and caps then
    caps.detect(opts.pid, function(cap)
      local supported = cap and cap.jfr and cap.jfr.start_options or nil
      local filtered, dropped = caps.filter_start_opts(start_opts, supported)
      local args = to_args(filtered)
      M.jcmd(opts.pid, "JFR.start", args, function(res)
        if dropped and #dropped > 0 then
          res.dropped_options = dropped
        end
        res.message = res.ok and "Recording started" or (res.stderr ~= "" and res.stderr or "Failed to start recording")
        if callback then
          callback(res)
        end
      end)
    end)
    return
  end

  local args = to_args(start_opts)

  M.jcmd(opts.pid, "JFR.start", args, function(res)
    res.message = res.ok and "Recording started" or (res.stderr ~= "" and res.stderr or "Failed to start recording")
    if callback then
      callback(res)
    end
  end)
end

--- Stop a JFR recording
---@param opts table Options: {pid, name, filename}
---@param callback fun(res: table)?
M.stop = function(opts, callback)
  local args = { "name=" .. (opts.name or "recording") }
  if opts.filename then
    table.insert(args, "filename=" .. opts.filename)
  end

  M.jcmd(opts.pid, "JFR.stop", args, function(res)
    res.message = res.ok and "Recording stopped" or (res.stderr ~= "" and res.stderr or "Failed to stop recording")
    if callback then
      callback(res)
    end
  end)
end

--- Dump a JFR recording (without stopping)
---@param opts table Options: {pid, name, filename}
---@param callback fun(res: table)?
M.dump = function(opts, callback)
  if not opts.filename then
    if callback then
      callback({ ok = false, code = -1, stdout = "", stderr = "filename required", message = "filename required" })
    end
    return
  end

  local args = {
    "name=" .. (opts.name or "recording"),
    "filename=" .. opts.filename,
  }

  M.jcmd(opts.pid, "JFR.dump", args, function(res)
    res.message = res.ok and "Recording dumped" or (res.stderr ~= "" and res.stderr or "Failed to dump recording")
    if callback then
      callback(res)
    end
  end)
end

--- Check active JFR recordings
---@param pid number JVM process ID
---@param callback fun(res: table)?
M.check = function(pid, callback)
  M.jcmd(pid, "JFR.check", {}, function(res)
    res.message = res.ok and "JFR.check" or (res.stderr ~= "" and res.stderr or "JFR.check failed")
    if callback then
      callback(res)
    end
  end)
end

--- Parse JFR.check output into structured recording list
---@param output string Raw output from JFR.check
---@return table List of recordings: {{name, id, duration, state}, ...}
M.parse_recordings = function(output)
  local recordings = {}
  if not output or output == "" then
    return recordings
  end

  -- JFR.check output format:
  -- Recording 1: name=recording,duration=60s,filename=recording_23334_20260227_222831.jfr,settings=profile maxsize=250.0MB (running)

  -- Some JDKs print explicit "No recording" lines; treat those as empty.
  -- Do NOT treat "(not running)" as empty, because JFR.check can list
  -- stopped recordings as well.
  if output:match("No recording") or output:match("No recordings") then
    return recordings
  end

  for line in vim.gsplit(output, "\n", { plain = true }) do
    -- Skip empty lines and PID line
    line = vim.trim(line)
    if line == "" or line:match("^%d+:") then
      goto continue
    end

    -- Extract fields individually.
    -- Known formats vary slightly between JDKs.
    local rec_num = line:match("Recording%s+(%d+):")
    local name = line:match("name=([^,]+)")
    local duration = line:match("duration=([^,]+)")
    local filename = line:match("filename=([^,]+)")
    local state = line:match("%(([^)]+)%)")

    -- Some JDKs omit the comma before the state suffix, e.g.:
    --   duration=1m (running)
    -- In that case our duration match would include the state. Strip it.
    if duration then
      duration = vim.trim(duration)
      duration = duration:gsub("%s*%([^%)]+%)%s*$", "")
      duration = vim.trim(duration)
    end

    if filename then
      filename = vim.trim(filename)
      filename = filename:gsub("%s*%([^%)]+%)%s*$", "")
      filename = vim.trim(filename)
    end

    -- Some JDKs omit filename for running recordings. We still want to surface it.
    if rec_num and name then
      local file_for_display = filename or "<no filename>"
      table.insert(recordings, {
        name = name,
        rec_num = tonumber(rec_num),
        duration = duration,
        filename = filename,
        state = state,
        display = rec_num .. ": " .. file_for_display,
      })
    end

    ::continue::
  end

  return recordings
end

--- Get help for JFR commands
---@param pid number JVM process ID
---@param callback function? Callback: function(help_text)
M.help = function(pid, callback)
  M.jcmd(pid, "help", { "JFR.start" }, function(res)
    if callback then
      callback(res.stdout ~= "" and res.stdout or res.stderr)
    end
  end)
end

return M
