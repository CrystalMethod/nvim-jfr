--- Capability detection for JFR/JDK features.
--- @module nvim-jfr.capabilities

local M = {}

local CACHE_TTL = 5 -- seconds
local _cache = {}

--- Compute feature support flags from a parsed JDK major.
---
--- This is the single place where we codify "feature X requires JDK Y+".
--- Keep this conservative and prefer capability detection (help output parsing)
--- for option-level support whenever possible.
---
--- @param jdk_major integer? parsed major version (e.g. 8, 11, 21, 25)
--- @return table { method_timing:boolean, method_tracing:boolean }
M._compute_features = function(jdk_major)
  local major = tonumber(jdk_major)
  local ok25 = (major ~= nil and major >= 25) or false
  return {
    -- Surfaced only for JDK 25+ (kept as a feature flag even before presets exist).
    method_timing = ok25,
    method_tracing = ok25,
  }
end

local function now_sec()
  return os.time()
end

local function cache_get(pid)
  local ent = _cache[pid]
  if not ent then
    return nil
  end
  if ent.at and os.difftime(now_sec(), ent.at) > CACHE_TTL then
    _cache[pid] = nil
    return nil
  end
  return ent.value
end

local function cache_put(pid, value)
  _cache[pid] = { value = value, at = now_sec() }
end

--- Parse `jcmd <pid> VM.version` output.
---@param output string
---@return table { major: integer?, vendor: string?, raw: string }
M._parse_vm_version = function(output)
  output = output or ""
  local out = { raw = output, major = nil, vendor = nil }

  -- `jcmd <pid> VM.version` typically prefixes output with "<pid>:" or
  -- "<pid>: VM.version" on the first line. Strip that so we don't confuse
  -- the PID for the version.
  local body = output
  body = body:gsub("^%s*%d+:%s*VM%.version%s*\n", "")
  body = body:gsub("^%s*%d+:%s*\n", "")

  -- Vendor (best-effort)
  local vendors = { "Temurin", "Corretto", "Zulu", "GraalVM", "Oracle", "OpenJDK", "Microsoft" }
  for _, v in ipairs(vendors) do
    if output:find(v, 1, true) then
      out.vendor = v
      break
    end
  end

  local function parse_major(v)
    if not v or v == "" then
      return nil
    end
    v = tostring(v)
    v = v:gsub("^[^%d]+", "")

    -- 1.8.0_402 -> 8
    local a, b = v:match("^(%d+)%.(%d+)")
    if a and b then
      a, b = tonumber(a), tonumber(b)
      if a == 1 then
        return b
      end
      return a
    end

    local m = v:match("^(%d+)")
    if m then
      return tonumber(m)
    end
    return nil
  end

  local function build_token(line)
    return (line or ""):match("%(%s*build%s+([^,%)%s]+)")
  end

  -- Major version
  -- Prefer explicit version strings over build tokens.
  local v = nil

  for line in vim.gsplit(body, "\n", { plain = true }) do
    line = vim.trim(line)
    if line == "" then
      goto continue
    end
    local vv = line:match('^%s*java%s+version%s+"([^"]+)"')
      or line:match('^%s*openjdk%s+version%s+"([^"]+)"')
      or line:match('^%s*version%s+"([^"]+)"')
    if vv then
      v = vv
      break
    end
    ::continue::
  end

  if not v then
    -- Prefer Runtime Environment build tokens (often contains the actual JDK version).
    for line in vim.gsplit(body, "\n", { plain = true }) do
      if line:find("Runtime Environment", 1, true) then
        v = build_token(line)
        if v then
          break
        end
      end
    end
  end

  if not v then
    -- Next: other build tokens, but avoid HotSpot build numbers like 25.402-b06.
    for line in vim.gsplit(body, "\n", { plain = true }) do
      local cand = build_token(line)
      if cand then
        if cand:find("+", 1, true) or cand:find("_", 1, true) or cand:find("ea", 1, true) or cand:match("^1%.") then
          v = cand
          break
        end
        -- If it's only a 2-part build (e.g. 25.402-b06) without known signals,
        -- treat as ambiguous and skip.
      end
    end
  end

  if not v then
    -- Last resort: take the first version-looking token, but avoid
    -- architecture markers like "64-Bit".
    for tok in body:gmatch("(%d+[%d%.]*[%w%+%-_]*)") do
      local tl = tok:lower()
      if tok ~= "64" and tok ~= "32" and not tl:find("bit", 1, true) then
        -- Avoid JVM build numbers like 25.402-b06 (2-part) which are not the JDK major.
        if tok:match("^%d+%.%d+[%-%w_]*$") and not tok:match("^%d+%.%d+%.%d+") and not tok:find("+", 1, true) then
          goto continue_tok
        end

        v = tok
        break
      end
      ::continue_tok::
    end
  end

  out.major = parse_major(v)

  return out
end

--- Parse `jcmd <pid> VM.system_properties` output for a runtime version.
---@param output string
---@return table { major: integer?, version: string?, raw: string }
M._parse_vm_system_properties = function(output)
  output = output or ""
  local out = { raw = output, major = nil, version = nil }

  local function parse_major(v)
    v = tostring(v or "")
    v = v:gsub("^[^%d]+", "")
    local a, b = v:match("^(%d+)%.(%d+)")
    if a and b then
      a, b = tonumber(a), tonumber(b)
      if a == 1 then
        return b
      end
      return a
    end
    local m = v:match("^(%d+)")
    return m and tonumber(m) or nil
  end

  local best = nil
  for line in vim.gsplit(output, "\n", { plain = true }) do
    local k, v = line:match("^%s*([%w%._-]+)%s*=%s*(.+)$")
    if k and v then
      k = vim.trim(k)
      v = vim.trim(v)
      if k == "java.runtime.version" then
        best = v
        break
      end
      if not best and k == "java.version" then
        best = v
      end
    end
  end

  out.version = best
  out.major = best and parse_major(best) or nil
  return out
end

--- Parse `jcmd <pid> help JFR.start` output to a set of supported option keys.
---@param help_text string
---@return table<string, boolean>
M._parse_jfr_start_options = function(help_text)
  help_text = help_text or ""
  local opts = {}

  for line in vim.gsplit(help_text, "\n", { plain = true }) do
    line = vim.trim(line)
    if line == "" then
      goto continue
    end

    -- JDKs commonly print either:
    --   - key=<type>|... (single-line synopsis)
    --   - or a two-column list without '=' in the option name column, e.g.:
    --       duration         (Optional) ...
    --       filename         (Optional) ...
    --
    -- Strategy:
    --   1) Prefer extracting tokens ending with '=' (most robust)
    --   2) Additionally accept leading "option name" tokens for the list format.

    for key in line:gmatch("([%a][%w_%-]+)=") do
      opts[key] = true
    end

    -- Column-list format: option name as first token, followed by a parenthesized
    -- Optional/Mandatory marker.
    -- Example:
    --   duration         (Optional) Length of time to record.
    local leading = line:match("^([%a][%w_%-]+)%s+%(%s*[Oo]ptional%s*%)")
      or line:match("^([%a][%w_%-]+)%s+%(%s*[Mm]andatory%s*%)")
    if leading then
      opts[leading] = true
    end

    ::continue::
  end

  return opts
end

--- Parse supported built-in values for the `settings=` option from
--- `jcmd <pid> help JFR.start` output.
---
--- Example lines seen in the wild:
---   settings=<path>|default|profile
---   settings=<path>
---
--- We only treat simple `|`-separated literals as built-in presets.
---@param help_text string
---@return table<string, boolean> presets
---@return boolean found_settings_line
M._parse_jfr_settings_presets = function(help_text)
  help_text = help_text or ""
  local presets = {}
  local found = false

  for line in vim.gsplit(help_text, "\n", { plain = true }) do
    line = vim.trim(line)
    if line == "" then
      goto continue
    end

    -- Look for the settings option definition.
    -- We accept both indented and non-indented forms.
    local rhs = line:match("^settings=([^%s]+)")
    if not rhs then
      rhs = line:match("^%s+settings=([^%s]+)")
    end
    if rhs then
      found = true
      -- rhs may contain things like "<path>|default|profile".
      for tok in rhs:gmatch("([^|]+)") do
        tok = vim.trim(tok)
        -- Only literal words count as presets; skip placeholders.
        if tok:match("^[%a][%w_-]*$") then
          presets[tok] = true
        end
      end
      break
    end

    ::continue::
  end

  return presets, found
end

--- Filter a start options table to only supported keys.
---@param start_opts table
---@param supported table<string, boolean>
---@return table filtered, string[] dropped
M.filter_start_opts = function(start_opts, supported)
  -- If we couldn't detect supported keys, do not drop anything.
  if not supported or next(supported) == nil then
    return vim.deepcopy(start_opts or {}), {}
  end

  local filtered, dropped = {}, {}
  for k, v in pairs(start_opts or {}) do
    if supported and supported[k] then
      filtered[k] = v
    else
      table.insert(dropped, k)
    end
  end
  table.sort(dropped)
  return filtered, dropped
end

--- Detect capabilities for a JVM.
---@param pid number
---@param cb fun(cap: table)
---@param opts table? { refresh:boolean? }
M.detect = function(pid, cb, opts)
  opts = opts or {}
  pid = tonumber(pid)
  if not pid then
    cb({ pid = pid, ok = false, error = "invalid pid" })
    return
  end

  if not opts.refresh then
    local c = cache_get(pid)
    if c then
      cb(c)
      return
    end
  end

  local jfr = require("nvim-jfr.jfr")

  local cap = {
    pid = pid,
    ok = true,
    jdk = { major = nil, vendor = nil, raw = "" },
    jfr = {
      start_options = {},
      settings_presets = {},
      settings_presets_found = false,
      start_help_raw = "",
      has_configure = false,
      configure_options = {},
    },
    features = { method_timing = false, method_tracing = false },
  }

  jfr.jcmd(pid, "VM.version", {}, function(res_ver)
    local ver_txt = (res_ver and (res_ver.stdout ~= "" and res_ver.stdout or res_ver.stderr)) or ""
    cap.jdk = M._parse_vm_version(ver_txt)
    cap.jdk.raw = ver_txt

    local function after_version()
      jfr.jcmd(pid, "help", { "JFR.start" }, function(res_help)
        local txt = (res_help and (res_help.stdout ~= "" and res_help.stdout or res_help.stderr)) or ""
        cap.jfr.start_help_raw = txt
        cap.jfr.start_options = M._parse_jfr_start_options(txt)
        local sp, sp_found = M._parse_jfr_settings_presets(txt)
        cap.jfr.settings_presets = sp
        cap.jfr.settings_presets_found = sp_found

        -- Optional: check if JFR.configure exists
        jfr.jcmd(pid, "help", { "JFR.configure" }, function(res_cfg)
          if res_cfg and res_cfg.ok then
            local cfg_txt = (res_cfg.stdout ~= "" and res_cfg.stdout or res_cfg.stderr) or ""
            cap.jfr.has_configure = cfg_txt ~= ""
            cap.jfr.configure_options = M._parse_jfr_start_options(cfg_txt)
          end

           cap.features = M._compute_features(cap.jdk and cap.jdk.major or nil)

           cache_put(pid, cap)
           cb(cap)
         end)
       end)
    end

    -- Fallback: if VM.version is ambiguous, try system properties.
    if not cap.jdk.major then
      jfr.jcmd(pid, "VM.system_properties", {}, function(res_prop)
        local prop_txt = (res_prop and (res_prop.stdout ~= "" and res_prop.stdout or res_prop.stderr)) or ""
        local p = M._parse_vm_system_properties(prop_txt)
        if p and p.major then
          cap.jdk.major = p.major
        end
        after_version()
      end)
    else
      after_version()
    end
  end)
end

M.clear_cache = function()
  _cache = {}
end

return M
