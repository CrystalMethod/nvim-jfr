--- Utility functions for nvim-jfr
--- @module nvim-jfr.utils

local M = {}

local notify_state = {
  last_by_key = {},
}

local function now_ms()
  local uv = vim.uv or vim.loop
  if uv and uv.now then
    return uv.now()
  end
  return math.floor(os.time() * 1000)
end

local function normalize_level(level)
  level = (level or "info")
  if type(level) ~= "string" then
    return "info"
  end
  level = level:lower()
  if level == "warning" then
    level = "warn"
  end
  if level ~= "info" and level ~= "warn" and level ~= "error" and level ~= "debug" and level ~= "trace" then
    level = "info"
  end
  return level
end

local function to_vim_level(level)
  level = normalize_level(level)
  local map = {
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
    debug = vim.log.levels.DEBUG,
    trace = vim.log.levels.TRACE,
  }
  return map[level] or vim.log.levels.INFO
end

--- Show a notification
---@param message string Notification message
---@param level string? Log level: "info", "warn", "error"
---@param opts table? Options: { title?:string, dedupe?:boolean, dedupe_key?:string, throttle_ms?:number }
---@return boolean shown
M.notify = function(message, level, opts)
  level = normalize_level(level)
  opts = opts or {}

  local ok_cfg, cfgmod = pcall(require, "nvim-jfr.config")
  if ok_cfg and cfgmod and type(cfgmod.get) == "function" then
    local cfg = cfgmod.get() or {}
    if cfg.notifications == false then
      return false
    end
  end

  local title = opts.title or "nvim-jfr"

  -- Optional dedupe / rate-limit.
  do
    local throttle_ms = opts.throttle_ms
    if opts.dedupe and (not throttle_ms or throttle_ms <= 0) then
      -- Default window for dedupe.
      throttle_ms = 2000
    end

    if opts.dedupe or (throttle_ms and throttle_ms > 0) then
      local key = opts.dedupe_key or (tostring(level) .. ":" .. tostring(message))
      local last = notify_state.last_by_key[key]
      local t = now_ms()

      if last and type(last) == "table" then
        if throttle_ms and throttle_ms > 0 and last.ts and (t - last.ts) < throttle_ms then
          if (not opts.dedupe) or (last.msg == message and last.level == level) then
            return false
          end
        end
        if opts.dedupe and last.msg == message and last.level == level then
          -- Suppress duplicates within the dedupe window (or forever when caller groups keys tightly).
          if not throttle_ms or throttle_ms <= 0 or (last.ts and (t - last.ts) < throttle_ms) then
            return false
          end
        end
      end

      notify_state.last_by_key[key] = { ts = t, msg = message, level = level }
    end
  end

  local ok_snacks, snacks = pcall(require, "snacks.notifier")
  if ok_snacks and snacks and type(snacks.notify) == "function" then
    snacks.notify(message, { level = level, title = title })
    return true
  end

  -- vim.notify will use nvim-notify automatically if installed.
  vim.notify(message, to_vim_level(level), { title = title })
  return true
end

--- Generate a default recording filename (basename only).
---@param pid number JVM PID
---@return string Filename
M.generate_filename = function(pid)
  local timestamp = os.date("%Y%m%d_%H%M%S")
  return string.format("recording_%d_%s.jfr", pid, timestamp)
end

--- Get the current timestamp
---@return string Timestamp string
M.timestamp = function()
  return os.date("%Y-%m-%d %H:%M:%S")
end

--- Deep merge tables
---@vararg table Tables to merge
---@return table Merged table
M.merge = function(...)
  return vim.tbl_deep_extend("force", ...)
end

--- Check if a string is empty
---@param str string? String to check
---@return boolean True if empty or nil
M.is_empty = function(str)
  return str == nil or str == ""
end

return M
