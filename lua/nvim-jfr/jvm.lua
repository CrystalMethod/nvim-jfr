--- JVM process discovery module
--- @module nvim-jfr.jvm

local M = {}

-- Cache for per-PID Java version strings.
-- Version lookups can be slow (jcmd attach), so keep this separate from
-- the JVM list cache.
local _version_cache = {}
local _version_cache_time = {}
local VERSION_CACHE_TTL = 30 -- seconds

-- Cache for VM.system_properties (project scoping probe)
local _props_cache = {}
local _props_cache_time = {}
local PROPS_CACHE_TTL = 30 -- seconds

-- Cache for JVM list
local _jvms_cache = nil
local _cache_time = nil
local CACHE_TTL = 5 -- seconds

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

--- Run a command (argv) and capture stdout/stderr.
--- Uses jobstart/jobwait to avoid shell quoting issues.
--- @param argv string[]
--- @param timeout_ms? integer
--- @return table res { ok:boolean, code:integer, stdout:string, stderr:string, timed_out:boolean? }
local function run_argv(argv, timeout_ms)
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

  local wait = vim.fn.jobwait({ jobid }, timeout_ms or 5000)
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

local function normalize_path(p)
  if not p or p == "" then
    return p
  end
  local platform = require("nvim-jfr.platform")
  p = platform.normalize_path(p)
  -- Drop trailing separators for stable matching.
  p = p:gsub("[/\\]+$", "")
  return p
end

local function contains(haystack, needle)
  if not haystack or not needle or needle == "" then
    return false
  end
  return haystack:find(needle, 1, true) ~= nil
end

local function matches_any_pattern(s, patterns)
  if not s or s == "" or type(patterns) ~= "table" then
    return false
  end
  for _, pat in ipairs(patterns) do
    if type(pat) == "string" and pat ~= "" then
      if s:match(pat) then
        return true
      end
    end
  end
  return false
end

--- Filter a JVM list by exclude patterns (best-effort).
---@param jvms table
---@param exclude_raw_patterns table? list of Lua patterns
---@return table
M.filter_excluded = function(jvms, exclude_raw_patterns)
  if type(exclude_raw_patterns) ~= "table" or #exclude_raw_patterns == 0 then
    return jvms
  end
  local out = {}
  for _, j in ipairs(jvms or {}) do
    local raw = (j and j.raw and tostring(j.raw)) or ""
    local mc = (j and j.main_class and tostring(j.main_class)) or ""
    if not matches_any_pattern(raw, exclude_raw_patterns) and not matches_any_pattern(mc, exclude_raw_patterns) then
      table.insert(out, j)
    end
  end
  return out
end

--- Parse `jcmd <pid> VM.system_properties` output into a key/value map.
--- Best-effort: never throws.
---@param output string
---@return table<string, string>
M._parse_system_properties = function(output)
  output = output or ""
  local props = {}

  -- Strip leading header lines like:
  --   "1234: VM.system_properties"
  --   "1234:" (some JDKs)
  local body = output
  body = body:gsub("^%s*%d+:%s*VM%.system_properties%s*\n", "")
  body = body:gsub("^%s*%d+:%s*\n", "")

  for line in vim.gsplit(body, "\n", { plain = true }) do
    local k, v = line:match("^%s*([%w%._-]+)%s*=%s*(.+)$")
    if k and v then
      k = vim.trim(k)
      v = vim.trim(v)
      if k ~= "" and v ~= "" then
        props[k] = v
      end
    end
  end

  return props
end

--- Get VM.system_properties for a PID (cached).
--- Best-effort: never throws, never notifies.
---@param pid number
---@param opts? table { refresh?:boolean, timeout_ms?:integer }
---@return table<string, string>
M.get_system_properties = function(pid, opts)
  opts = opts or {}
  local refresh = opts.refresh or false
  local timeout_ms = opts.timeout_ms or 800

  local n = tonumber(pid)
  if not n then
    return {}
  end
  pid = n

  if not refresh and _props_cache[pid] and _props_cache_time[pid] then
    local age = os.difftime(os.time(), _props_cache_time[pid])
    if age < PROPS_CACHE_TTL then
      return _props_cache[pid]
    end
  end

  local res = run_argv({ "jcmd", tostring(pid), "VM.system_properties" }, timeout_ms)
  local props = {}
  if res and res.ok then
    local txt = (res.stdout ~= "" and res.stdout or res.stderr) or ""
    props = M._parse_system_properties(txt)
  end

  -- Cache both successes and failures (empty table) to avoid repeatedly
  -- paying the attach cost for PIDs that are slow/unreachable.
  _props_cache[pid] = props
  _props_cache_time[pid] = os.time()
  return props
end

local function props_match_project(props, project_root)
  if type(props) ~= "table" or not project_root or project_root == "" then
    return false
  end
  project_root = normalize_path(project_root)

  -- Prefer Maven multi-module root if present.
  -- NOTE: Don't build an array with nil holes and then iterate via ipairs,
  -- because ipairs stops at the first nil.
  local keys = { "maven.multiModuleProjectDirectory", "user.dir" }
  for _, k in ipairs(keys) do
    local v = props[k]
    if type(v) == "string" and v ~= "" then
      local norm = normalize_path(v) or ""
      if contains(norm, project_root) then
        return true
      end
    end
  end

  return false
end

--- Parse jcmd -l output
---@param output string Raw output from jcmd -l
---@return table List of JVM info tables
M.parse_jcmd_output = function(output)
  local jvms = {}

  if not output or output == "" then
    return jvms
  end

  -- jcmd -l output formats:
  -- macOS/Linux: 12345 /path/to/MainClass args...
  -- With hostname: 12345@hostname (com.example.MainClass) -jar app.jar
  -- jcmd itself: 12345 jdk.jcmd/sun.tools.jcmd.JCmd -l

  for line in vim.gsplit(output, "\n", { plain = true }) do
    line = vim.trim(line)
    if line == "" or line:match("^%d+ processes%.") or line:match("^%d+ jdk%.jcmd") then
      goto continue
    end

    local pid, main_class, args

    -- Try format: PID /path/to/class args...
    pid, main_class, args = line:match("^(%d+)%s+(/%S+)%s*(.*)")
    if not pid then
      -- Try format: PID@hostname (class) args...
      pid, main_class, args = line:match("^(%d+)@%S+%s+%(([^%)]+)%)%s*(.*)")
    end
    if not pid then
      -- Try format: PID classname args...
      pid, main_class, args = line:match("^(%d+)%s+(%S+)%s*(.*)")
    end

    if pid and main_class and main_class ~= "jcmd" then
      table.insert(jvms, {
        pid = tonumber(pid),
        main_class = main_class,
        args = args or "",
        raw = line,
      })
    end

    ::continue::
  end

  return jvms
end

--- List all running JVM processes (synchronous)
---@param opts table? Options: {refresh = boolean}
---@return table List of JVM info tables
M.list = function(opts)
  opts = opts or {}
  opts.refresh = opts.refresh or false

  -- Check cache
  if not opts.refresh and _jvms_cache and _cache_time then
    local age = os.difftime(os.time(), _cache_time)
    if age < CACHE_TTL then
      return _jvms_cache
    end
  end

  -- Run jcmd -l (no shell)
  local res = run_argv({ "jcmd", "-l" }, 5000)
  if not res.ok then
    local ok_u, utils = pcall(require, "nvim-jfr.utils")
    local ok_e, errors = pcall(require, "nvim-jfr.errors")
    if ok_u and ok_e then
      utils.notify(errors.format_jcmd_error("Failed to list JVMs", res), "error")
    else
      vim.notify("[nvim-jfr] Failed to list JVMs: " .. (res.stderr ~= "" and res.stderr or res.stdout), vim.log.levels.ERROR)
    end
    return {}
  end

  _jvms_cache = M.parse_jcmd_output(res.stdout)
  _cache_time = os.time()

  return _jvms_cache
end

--- List all running JVM processes (asynchronous)
---@param opts table Options: {refresh = boolean, on_done = function}
---@return nil
M.list_async = function(opts)
  opts = opts or {}
  opts.refresh = opts.refresh or false

  -- Check cache first
  if not opts.refresh and _jvms_cache and _cache_time then
    local age = os.difftime(os.time(), _cache_time)
    if age < CACHE_TTL and opts.on_done then
      opts.on_done(_jvms_cache)
      return
    end
  end

  -- Run jcmd -l asynchronously (no shell)
  local stdout_lines, stderr_lines = {}, {}
  vim.fn.jobstart({ "jcmd", "-l" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      append_lines(stdout_lines, data)
    end,
    on_stderr = function(_, data)
      append_lines(stderr_lines, data)
    end,
    on_exit = function(_, code)
      local stdout = table.concat(stdout_lines, "\n")
      local stderr = table.concat(stderr_lines, "\n")

      if code == 0 then
        _jvms_cache = M.parse_jcmd_output(stdout)
        _cache_time = os.time()
        if opts.on_done then
          opts.on_done(_jvms_cache)
        end
      else
        if stderr ~= "" then
          local ok_u, utils = pcall(require, "nvim-jfr.utils")
          local ok_e, errors = pcall(require, "nvim-jfr.errors")
          if ok_u and ok_e then
            utils.notify(errors.format_jcmd_error("Failed to run jcmd -l", { ok = false, code = code, stdout = stdout, stderr = stderr }), "error")
          else
            vim.notify("[nvim-jfr] jcmd error: " .. stderr, vim.log.levels.ERROR)
          end
        end
        if opts.on_done then
          opts.on_done({})
        end
      end
    end,
  })
end

--- Find JVM by PID
---@param pid number Process ID to find
---@return table? JVM info or nil
M.find_by_pid = function(pid)
  local jvms = M.list()
  for _, jvm in ipairs(jvms) do
    if jvm.pid == pid then
      return jvm
    end
  end
  return nil
end

--- Get JDK version of a JVM
---@param pid number Process ID
---@return string? JDK version or nil
M.get_jdk_version = function(pid)
  -- Deprecated: use get_java_version() (cached + robust parser).
  return M.get_java_version(pid, { timeout_ms = 5000 })
end

--- Get a human-friendly Java version string for a PID (cached).
--- Best-effort: never throws, never notifies.
---
--- Prefers the capabilities VM.version parser (more robust across vendors).
--- Falls back to a simple token match.
---
--- @param pid number
--- @param opts? table { refresh?:boolean, timeout_ms?:integer }
--- @return string? version
M.get_java_version = function(pid, opts)
  opts = opts or {}
  pid = tonumber(pid)
  if not pid then
    return nil
  end

  if not opts.refresh then
    local at = _version_cache_time[pid]
    if at then
      local age = os.difftime(os.time(), at)
      if age < VERSION_CACHE_TTL then
        return _version_cache[pid]
      end
    end
  end

  -- Shorter timeout than general commands; picker UX should stay snappy.
  local timeout = tonumber(opts.timeout_ms or 800) or 800
  local res = run_argv({ "jcmd", tostring(pid), "VM.version" }, timeout)
  if not res or not res.ok then
    _version_cache[pid] = nil
    _version_cache_time[pid] = os.time()
    return nil
  end

  local txt = res.stdout or ""
  local v = nil

  local ok_caps, caps = pcall(require, "nvim-jfr.capabilities")
  if ok_caps and caps and type(caps._parse_vm_version) == "function" then
    local parsed = caps._parse_vm_version(txt)
    if parsed and parsed.major then
      v = tostring(parsed.major)
    end
  end

  if not v then
    -- Fallback: grab a reasonable version-ish token.
    v = txt:match('java%s+version%s+"([^"]+)"')
      or txt:match('openjdk%s+version%s+"([^"]+)"')
      or txt:match("(%d+%.%d+%.%d+[%w%+%-_]*)")
      or txt:match("(%d+%.%d+[%w%+%-_]*)")
  end

  _version_cache[pid] = v
  _version_cache_time[pid] = os.time()
  return v
end

--- Check if jcmd is available
---@return boolean True if jcmd is available
M.is_available = function()
  return vim.fn.executable("jcmd") == 1
end

--- Check if JFR is enabled on a JVM
---@param pid number Process ID
---@return boolean True if JFR is available
M.is_jfr_available = function(pid)
  local res = run_argv({ "jcmd", tostring(pid), "help", "JFR.start" }, 5000)
  local txt = (res.stdout or "") .. "\n" .. (res.stderr or "")
  return res.ok and not txt:match("not available")
end

--- Filter JVMs by project directory
---@param project_dir string Project directory path
---@return table Filtered list of JVMs
M.filter_by_project = function(project_dir)
  local jvms = M.list()
  if not project_dir or project_dir == "" then
    return jvms
  end

  project_dir = normalize_path(project_dir)

  local filtered = {}
  for _, jvm in ipairs(jvms) do
    -- Check if JVM's raw line contains the project path.
    local jvm_info = normalize_path(jvm.raw or "") or ""
    if contains(jvm_info, project_dir) then
      table.insert(filtered, jvm)
    end
  end

  return filtered
end

--- List JVMs scoped to a project root.
--- This is a best-effort filter on `jcmd -l` output.
---@param project_root string? Project root directory
---@param opts table? Options: { refresh:boolean?, filter:function? }
---@return table
M.list_for_project = function(project_root, opts)
  opts = opts or {}
  local all = M.list({ refresh = opts.refresh })
  if not project_root or project_root == "" then
    return all
  end
  project_root = normalize_path(project_root)

  local pred = opts.filter
  if type(pred) ~= "function" then
    pred = function(jvm)
      local raw = normalize_path(jvm.raw or "") or ""
      return contains(raw, project_root)
    end
  end

  local exclude_raw_patterns = opts.exclude_raw_patterns
  if type(exclude_raw_patterns) ~= "table" then
    exclude_raw_patterns = {}
  end

  local function is_excluded(j)
    local raw = (j and j.raw and tostring(j.raw)) or ""
    local mc = (j and j.main_class and tostring(j.main_class)) or ""
    return matches_any_pattern(raw, exclude_raw_patterns) or matches_any_pattern(mc, exclude_raw_patterns)
  end

  local out = {}
  for _, j in ipairs(all) do
    if not is_excluded(j) and pred(j, project_root) then
      table.insert(out, j)
    end
  end

  -- Fallback: if raw filtering yields nothing, optionally probe system properties
  -- to recover common project-launched JVMs (e.g. Maven/Spring Boot).
  -- Keep this best-effort and bounded to avoid slowing down the UI.
  if #out == 0 and opts.probe_system_properties ~= false then
    -- Defaults are tuned for UI responsiveness. For many JVMs, probing can be
    -- expensive (jcmd attach). Keep timeouts short and limit the total work.
    local max_probes = tonumber(opts.max_probes) or 6
    local timeout_ms = tonumber(opts.timeout_ms) or 250
    local time_budget_ms = tonumber(opts.time_budget_ms) or 600
    local stop_after_first_match = opts.stop_after_first_match
    if stop_after_first_match == nil then
      stop_after_first_match = true
    end

    -- reuse is_excluded() from above

    local start_ns = (vim.uv or vim.loop).hrtime()
    local function elapsed_ms()
      local now_ns = (vim.uv or vim.loop).hrtime()
      return (now_ns - start_ns) / 1e6
    end

    local function score(j)
      local s = 0
      local mc = (j and j.main_class and tostring(j.main_class):lower()) or ""
      local raw = (j and j.raw and tostring(j.raw):lower()) or ""

      -- Prefer wrapper/tooling JVMs that commonly launch apps from the project.
      if mc:find("maven", 1, true) or raw:find("maven", 1, true) then
        s = s + 30
      end
      if mc:find("gradle", 1, true) or raw:find("gradle", 1, true) then
        s = s + 25
      end
      if mc:find("spring", 1, true) or raw:find("spring", 1, true) then
        s = s + 10
      end
      if mc:find("quarkus", 1, true) or raw:find("quarkus", 1, true) then
        s = s + 10
      end
      if mc:find("jdtls", 1, true) or raw:find("jdtls", 1, true) then
        s = s - 5
      end

      return s
    end

    -- Probe likely candidates first.
    local probe = vim.deepcopy(all)
    table.sort(probe, function(a, b)
      return score(a) > score(b)
    end)

    local n = 0
    for _, j in ipairs(probe) do
      if not (j and j.pid) then
        goto continue
      end

      if is_excluded(j) then
        goto continue
      end

      if elapsed_ms() >= time_budget_ms then
        break
      end

      n = n + 1
      if n > max_probes then
        break
      end

      local props = M.get_system_properties(j.pid, { timeout_ms = timeout_ms })
      if props_match_project(props, project_root) then
        table.insert(out, j)
        if stop_after_first_match then
          break
        end
      end

      ::continue::
    end
  end

  return out
end

--- Clear the cache
M.clear_cache = function()
  _jvms_cache = nil
  _cache_time = nil
  _version_cache = {}
  _version_cache_time = {}
  _props_cache = {}
  _props_cache_time = {}
end

--- Get cache status
---@return table Cache info
M.get_cache_status = function()
  return {
    cached = _jvms_cache ~= nil,
    count = _jvms_cache and #_jvms_cache or 0,
    age = _cache_time and os.difftime(os.time(), _cache_time) or nil,
  }
end

return M
