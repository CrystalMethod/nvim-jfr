--- Recording preview (metadata + optional `jfr summary`).
--- @module nvim-jfr.preview.recording

local M = {}

local platform = require("nvim-jfr.platform")

local uv = vim.uv or vim.loop

local function now_ms()
  if uv and uv.hrtime then
    return math.floor(uv.hrtime() / 1e6)
  end
  return math.floor((vim.fn.reltimefloat(vim.fn.reltime()) or 0) * 1000)
end

-- Exposed for headless specs.
M._now_ms = now_ms

local function fmt_bytes(n)
  n = tonumber(n)
  if not n then
    return "?"
  end
  local units = { "B", "KB", "MB", "GB" }
  local u = 1
  while n >= 1024 and u < #units do
    n = n / 1024
    u = u + 1
  end
  if u == 1 then
    return string.format("%d %s", math.floor(n), units[u])
  end
  return string.format("%.1f %s", n, units[u])
end

local function fmt_time(sec)
  sec = tonumber(sec)
  if not sec then
    return "?"
  end
  -- Keep it simple and locale-safe.
  return os.date("%Y-%m-%d %H:%M:%S", sec)
end

local function stat(path)
  if not path or path == "" then
    return nil
  end
  return (uv and uv.fs_stat and uv.fs_stat(path)) or nil
end

local function cache_key(path, st)
  local m = st and st.mtime and st.mtime.sec or 0
  local s = st and st.size or 0
  return table.concat({ tostring(path), tostring(m), tostring(s) }, "|")
end

local function base_metadata_lines(path, st)
  local lines = {}
  table.insert(lines, "# JFR recording")
  table.insert(lines, "")
  table.insert(lines, "Path: " .. tostring(path))
  table.insert(lines, "Size: " .. fmt_bytes(st and st.size))
  table.insert(lines, "Modified: " .. fmt_time(st and st.mtime and st.mtime.sec))

  -- Optional sidecar metadata.
  pcall(function()
    local meta_mod = require("nvim-jfr.recording_meta")
    local meta, err = meta_mod.read_for_recording(path)
    if err then
      table.insert(lines, "")
      table.insert(lines, "Meta: (failed to read: " .. tostring(err) .. ")")
      return
    end
    if meta and type(meta) == "table" then
      local run = meta.run_config_name
      if run == nil then
        run = "<none>"
      end

      table.insert(lines, "")
      table.insert(lines, "# Recording meta")
      if meta.created_at then
        table.insert(lines, "Created: " .. tostring(meta.created_at))
      end
      if meta.jvm and type(meta.jvm) == "table" then
        if meta.jvm.pid then
          table.insert(lines, "PID: " .. tostring(meta.jvm.pid))
        end
        if meta.jvm.java_version then
          table.insert(lines, "Java: " .. tostring(meta.jvm.java_version))
        end
      end
      table.insert(lines, "Run config: " .. tostring(run))
      if meta.jfr_start and type(meta.jfr_start) == "table" then
        local s = meta.jfr_start.settings
        if type(s) == "table" then
          if s.kind == "preset" then
            table.insert(lines, "settings=: " .. tostring(s.value))
          elseif s.kind == "file" then
            table.insert(lines, "settings=: " .. tostring(s.path))
          end
        end
        if meta.jfr_start.duration then
          table.insert(lines, "duration=: " .. tostring(meta.jfr_start.duration))
        end
      end
    end
  end)
  return lines
end

-- In-memory cache for summary output keyed by path+mtime+size.
M._cache = {}

M._cache_key = cache_key

-- Build preview immediately, and optionally run `jfr summary` for small files.
--
-- @param path string Absolute file path.
-- @param cfg table? config.recordings_preview
-- @param cb fun(text:string) Callback called once or twice (initial + updated).
M.render_async = function(path, cfg, cb)
  cfg = cfg or {}
  local enabled = cfg.enabled ~= false
  local max_kb = tonumber(cfg.summary_max_kb or 0) or 0
  local timeout_ms = tonumber(cfg.timeout_ms or 0) or 0
  local jfr_cmd = cfg.jfr_command or "jfr"

  path = platform.normalize_path(path)
  local st = stat(path)
  local meta_lines = base_metadata_lines(path, st)
  if not st then
    table.insert(meta_lines, "")
    table.insert(meta_lines, "(file not found)")
    cb(table.concat(meta_lines, "\n"))
    return
  end

  if tonumber(st.size or 0) == 0 then
    table.insert(meta_lines, "")
    table.insert(meta_lines, "(summary skipped: file is empty)")
    cb(table.concat(meta_lines, "\n"))
    return
  end

  local size_kb = (st.size or 0) / 1024
  local can_summary = enabled and max_kb > 0 and size_kb <= max_kb

  if not can_summary then
    table.insert(meta_lines, "")
    table.insert(meta_lines, string.format("(summary skipped: %.0f KB > %d KB)", size_kb, max_kb))
    cb(table.concat(meta_lines, "\n"))
    return
  end

  local key = cache_key(path, st)
  local cached = M._cache[key]
  if cached and type(cached.text) == "string" then
    local lines = vim.list_extend(meta_lines, { "", "# jfr summary", "", cached.text })
    cb(table.concat(lines, "\n"))
    return
  end

  -- Initial render: metadata + loading hint.
  do
    local lines = vim.list_extend(meta_lines, { "", "# jfr summary", "", "(loading...)" })
    cb(table.concat(lines, "\n"))
  end

  -- Validate jfr executable.
  if vim.fn.executable(jfr_cmd) ~= 1 then
    local lines = vim.list_extend(meta_lines, { "", "# jfr summary", "", "(jfr command not found: " .. tostring(jfr_cmd) .. ")" })
    cb(table.concat(lines, "\n"))
    return
  end

  local started = now_ms()
  local done = false
  local out_lines = {}
  local err_lines = {}

  local job_id
  local timer

  local function finish(text)
    if done then
      return
    end
    done = true
    if timer then
      pcall(timer.stop, timer)
      pcall(timer.close, timer)
    end
    if job_id then
      -- Nothing to do; job is finished or stopped.
    end

    M._cache[key] = { text = text, at = now_ms() }
    local lines = vim.list_extend(meta_lines, { "", "# jfr summary", "", text })
    cb(table.concat(lines, "\n"))
  end

  if timeout_ms > 0 and uv and uv.new_timer then
    timer = uv.new_timer()
    timer:start(timeout_ms, 0, function()
      if done then
        return
      end
      if job_id then
        pcall(vim.fn.jobstop, job_id)
      end
      local elapsed = now_ms() - started
      vim.schedule(function()
        finish(string.format("(timed out after %dms)", elapsed))
      end)
    end)
  end

  job_id = vim.fn.jobstart({ jfr_cmd, "summary", path }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if type(data) == "table" then
        for _, l in ipairs(data) do
          if l and l ~= "" then
            table.insert(out_lines, l)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if type(data) == "table" then
        for _, l in ipairs(data) do
          if l and l ~= "" then
            table.insert(err_lines, l)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if done then
        return
      end
      vim.schedule(function()
        local txt
        if tonumber(code) == 0 and #out_lines > 0 then
          txt = table.concat(out_lines, "\n")
        else
          local err = (#err_lines > 0) and table.concat(err_lines, "\n") or "(no output)"
          txt = string.format("(jfr summary failed: exit=%s)\n%s", tostring(code), err)
        end
        finish(txt)
      end)
    end,
  })

  if not job_id or job_id <= 0 then
    finish("(failed to start job: jfr summary)")
  end
end

return M
