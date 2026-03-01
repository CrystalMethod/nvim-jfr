--- Error classification and recovery hints.
--- @module nvim-jfr.errors

local M = {}

local function lower(s)
  return (s or ""):lower()
end

local function first_line(s)
  s = s or ""
  for line in vim.gsplit(s, "\n", { plain = true }) do
    line = vim.trim(line)
    if line ~= "" then
      return line
    end
  end
  return ""
end

--- Build a pseudo jcmd result for shell/system() invocations.
--- @param stdout string
--- @param code integer
--- @param stderr string?
--- @return table
M.from_shell = function(stdout, code, stderr)
  return {
    ok = code == 0,
    code = code,
    stdout = stdout or "",
    stderr = stderr or "",
  }
end

--- Classify a jcmd failure and provide recovery guidance.
--- @param res table? Result from nvim-jfr.jfr.jcmd
--- @return table? info { kind:string, summary:string, recovery:string[] }
M.classify_jcmd = function(res)
  if not res then
    return {
      kind = "unknown",
      summary = "Unknown error",
      recovery = {},
    }
  end

  if res.timed_out then
    return {
      kind = "timeout",
      summary = "Timed out while running jcmd",
      recovery = {
        "Try again; jcmd attach can contend with other tools.",
        "If it keeps happening, ensure the JVM is responsive and you have permission to attach.",
      },
    }
  end

  local txt = (res.stderr or "") .. "\n" .. (res.stdout or "")
  local t = lower(txt)

  -- jcmd missing / not executable
  if t:find("jcmd not found", 1, true)
    or t:find("not found", 1, true)
    or t:find("not recognized", 1, true)
    or t:find("failed to start jcmd", 1, true)
  then
    return {
      kind = "jcmd_missing",
      summary = "jcmd is not available",
      recovery = {
        "Install a JDK (not just a JRE) and ensure `jcmd` is on your PATH.",
        "Verify in a terminal: `jcmd -l`.",
      },
    }
  end

  -- JFR not enabled / command unavailable
  if t:find("flight recorder is not enabled", 1, true)
    or t:find("jfr.start", 1, true) and t:find("not available", 1, true)
    or t:find("unknown diagnostic command", 1, true) and t:find("jfr", 1, true)
    or t:find("diagnostic command", 1, true) and t:find("not available", 1, true) and t:find("jfr", 1, true)
  then
    return {
      kind = "jfr_disabled",
      summary = "JFR is not enabled/available for this JVM",
      recovery = {
        "For JDK 8, start the JVM with: -XX:+UnlockCommercialFeatures -XX:+FlightRecorder (or vendor equivalent).",
        "For newer JDKs, ensure the JVM supports JFR and that the command is not disabled by policy.",
        "Check: `jcmd <pid> help JFR.start`.",
      },
    }
  end

  -- Permission / attach failures
  if t:find("attachnotsupportedexception", 1, true)
    or t:find("operation not permitted", 1, true)
    or t:find("permission denied", 1, true)
    or t:find("could not attach", 1, true)
    or t:find("unable to open socket file", 1, true)
    or t:find("cannot connect to", 1, true)
  then
    return {
      kind = "attach_denied",
      summary = "jcmd could not attach to the JVM",
      recovery = {
        "Run Neovim as the same OS user that owns the JVM process.",
        "On Linux, check ptrace restrictions (e.g. /proc/sys/kernel/yama/ptrace_scope).",
        "On macOS, ensure you have permission to inspect/attach to the target process.",
      },
    }
  end

  -- File/path related (dump/stop/start with filename)
  if t:find("could not write", 1, true)
    or t:find("unable to create", 1, true)
    or t:find("no such file", 1, true)
    or t:find("access is denied", 1, true)
  then
    return {
      kind = "io_error",
      summary = "Failed to write the recording file",
      recovery = {
        "Check that the output directory exists and is writable.",
        "Try an absolute `--filename=` path.",
      },
    }
  end

  return {
    kind = "unknown",
    summary = "jcmd failed",
    recovery = {},
  }
end

--- Format a user-facing error message.
--- @param prefix string
--- @param res table?
--- @return string
M.format_jcmd_error = function(prefix, res)
  prefix = prefix or "jcmd failed"
  local info = M.classify_jcmd(res)
  local details = first_line((res and ((res.stderr ~= "" and res.stderr) or res.stdout)) or "")

  local lines = { prefix }
  if details ~= "" then
    table.insert(lines, details)
  elseif info and info.summary and info.summary ~= "" then
    table.insert(lines, info.summary)
  end

  if info and info.recovery and #info.recovery > 0 then
    table.insert(lines, "")
    table.insert(lines, "Recovery:")
    for _, r in ipairs(info.recovery) do
      table.insert(lines, "- " .. r)
    end
  end

  return table.concat(lines, "\n")
end

return M
