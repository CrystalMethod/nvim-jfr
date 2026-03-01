--- Formatting helpers for :JFRCapabilities output.
--- @module nvim-jfr.capabilities_ui

local M = {}

local function keys_list(tbl)
  local keys = {}
  for k, v in pairs(tbl or {}) do
    if v then
      table.insert(keys, k)
    end
  end
  table.sort(keys)
  return keys
end

local OPTION_HELP = {
  -- JFR.start options (best-effort; varies by JDK)
  name = "Recording name (used for stop/dump).",
  settings = "Settings preset name (default/profile) or path to a .jfc file.",
  duration = "Stop after this timespan (e.g. 60s, 5m).",
  delay = "Start after this timespan.",
  filename = "Output .jfr path (when using dump/stop with filename).",
  maxage = "Discard data older than this (continuous recordings).",
  maxsize = "Max size of the recording buffer.",
  disk = "Whether to use disk (true/false) instead of only memory.",
  dumponexit = "Dump recording on JVM exit (true/false).",
  path_to_gc_roots = "Include path-to-GC-roots information (more overhead).",
}

local GROUPS = {
  { name = "Settings / presets", keys = { "settings" } },
  { name = "Recording control", keys = { "name", "duration", "delay" } },
  { name = "Output / storage", keys = { "filename", "disk", "dumponexit" } },
  { name = "Retention", keys = { "maxage", "maxsize" } },
  { name = "Advanced", keys = { "path_to_gc_roots" } },
}

local function set_from_list(list)
  local s = {}
  for _, k in ipairs(list or {}) do
    s[k] = true
  end
  return s
end

local function append_grouped_options(lines, supported_set)
  supported_set = supported_set or {}
  local all = keys_list(supported_set)
  if #all == 0 then
    return
  end

  local used = {}
  for _, g in ipairs(GROUPS) do
    local gset = set_from_list(g.keys)
    local present = {}
    for _, k in ipairs(all) do
      if gset[k] then
        table.insert(present, k)
        used[k] = true
      end
    end
    if #present > 0 then
      table.insert(lines, "### " .. g.name)
      for _, k in ipairs(present) do
        local note = OPTION_HELP[k] and (" — " .. OPTION_HELP[k]) or ""
        table.insert(lines, string.format("- `%s=`%s", k, note))
      end
      table.insert(lines, "")
    end
  end

  local other = {}
  for _, k in ipairs(all) do
    if not used[k] then
      table.insert(other, k)
    end
  end
  if #other > 0 then
    table.insert(lines, "### Other")
    for _, k in ipairs(other) do
      local note = OPTION_HELP[k] and (" — " .. OPTION_HELP[k]) or ""
      table.insert(lines, string.format("- `%s=`%s", k, note))
    end
    table.insert(lines, "")
  end
end

--- Return a best-effort jcmd docs URL for a JDK major.
--- @param major integer?
--- @return string
M.jcmd_docs_url = function(major)
  major = tonumber(major)
  if major == 8 then
    return "https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jcmd.html"
  end
  -- Oracle doc site currently publishes versioned docs for LTS lines.
  -- For non-LTS/EA majors, prefer the nearest known line.
  if major and major >= 9 then
    local mapped = major
    if major >= 25 then
      mapped = 25
    elseif major >= 21 then
      mapped = 21
    elseif major >= 17 then
      mapped = 17
    end
    return string.format("https://docs.oracle.com/en/java/javase/%d/docs/specs/man/jcmd.html", mapped)
  end
  return "https://docs.oracle.com/en/java/javase/" -- fallback hub
end

M.jfr_docs_url = function(major)
  -- JFR is described in the jcmd manpage under JFR.* commands.
  return M.jcmd_docs_url(major)
end

M.jfr_configuration_docs_url = function(major)
  major = tonumber(major)
  if major and major >= 9 then
    local mapped = major
    if major >= 25 then
      mapped = 25
    elseif major >= 21 then
      mapped = 21
    elseif major >= 17 then
      mapped = 17
    end
    return string.format("https://docs.oracle.com/en/java/javase/%d/jfapi/flight-recorder.html", mapped)
  end
  -- Best-effort fallback (hub)
  return "https://docs.oracle.com/en/java/javase/"
end

--- Format capabilities as multi-line text.
--- @param cap table
--- @param opts table? { verbose:boolean?, settings_override:string? }
--- @return string
M.format = function(cap, opts)
  opts = opts or {}
  local verbose = opts.verbose == true
  local settings_override = opts.settings_override

  local jdk_major = cap and cap.jdk and cap.jdk.major or nil
  local vendor = cap and cap.jdk and cap.jdk.vendor or nil

  local lines = {}
  table.insert(lines, string.format("JFR Capabilities (pid=%s)", tostring(cap and cap.pid or "?")))
  table.insert(lines, "")

  table.insert(lines, "## Summary")
  table.insert(lines, "- JDK major: " .. tostring(jdk_major or "?"))
  table.insert(lines, "- Vendor: " .. tostring(vendor or "?"))
  table.insert(lines, "- JFR.configure available: " .. ((cap and cap.jfr and cap.jfr.has_configure) and "yes" or "no"))

  local timing = (cap and cap.features and (cap.features.method_timing or cap.features.method_tracing)) and true or false
  table.insert(lines, "- Method timing/tracing (JDK 25+): " .. (timing and "yes" or "no"))
  table.insert(lines, "")

  table.insert(lines, "## Links")
  table.insert(lines, "- jcmd manual: " .. M.jcmd_docs_url(jdk_major))
  table.insert(lines, "- JFR commands: " .. M.jfr_docs_url(jdk_major))
  table.insert(lines, "- Flight Recorder API/docs: " .. M.jfr_configuration_docs_url(jdk_major))
  table.insert(lines, "")

  table.insert(lines, "## JFR.start")
  local sp = cap and cap.jfr and cap.jfr.settings_presets or {}
  local sp_found = cap and cap.jfr and cap.jfr.settings_presets_found
  local sp_keys = keys_list(sp)
  if #sp_keys > 0 then
    table.insert(lines, "- Built-in settings presets: " .. table.concat(sp_keys, ", "))
  elseif sp_found then
    table.insert(lines, "- Built-in settings presets: <none>")
  else
    table.insert(lines, "- Built-in settings presets: <unknown>")
  end

  if settings_override then
    local s = tostring(settings_override):lower()
    if s == "default" or s == "profile" then
      local ok = (sp and sp[s]) and "supported" or "NOT supported"
      table.insert(lines, "- Settings check (--settings=" .. tostring(s) .. "): " .. ok)
    else
      table.insert(lines, "- Settings check (--settings=...): paths are not validated against preset list")
    end
  end

  local start_keys = keys_list(cap and cap.jfr and cap.jfr.start_options or {})
  if #start_keys > 0 then
    table.insert(lines, "- Supported options (from `help JFR.start`):")
    table.insert(lines, "")
    append_grouped_options(lines, cap and cap.jfr and cap.jfr.start_options or {})
  end
  table.insert(lines, "")

  table.insert(lines, "## Notes")
  table.insert(lines, "- Method timing/tracing is only surfaced for JDK 25+ (feature-gated).")
  table.insert(
    lines,
    "- If your JDK major is <25, timing/tracing features are not expected to appear here."
  )
  table.insert(lines, "- Use :JFRStart --settings=profile (or default) to start a recording.")

  if verbose then
    table.insert(lines, "")
    table.insert(lines, "## Raw (verbose)")
    table.insert(lines, "### VM.version")
    table.insert(lines, vim.trim((cap and cap.jdk and cap.jdk.raw) or ""))
    table.insert(lines, "")
    table.insert(lines, "### help JFR.start")
    table.insert(lines, vim.trim((cap and cap.jfr and cap.jfr.start_help_raw) or ""))
  end

  return table.concat(lines, "\n")
end

return M
