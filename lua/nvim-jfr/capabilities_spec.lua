--- Minimal headless checks for nvim-jfr.capabilities.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.capabilities_spec').run())" -c "qa"

local M = {}

local caps = require("nvim-jfr.capabilities")

M.run = function()
  local v8 = caps._parse_vm_version('Java HotSpot(TM) 64-Bit Server VM (build 25.402-b06, mixed mode)\njava version "1.8.0_402"\n')
  assert(v8.major == 8)

  local v21 = caps._parse_vm_version('OpenJDK 64-Bit Server VM (build 21.0.2+13)\nopenjdk version "21.0.2" 2024-01-16\n')
  assert(v21.major == 21)

  local v25 = caps._parse_vm_version('openjdk version "25-ea" 2026-03-19\nOpenJDK Runtime Environment (build 25-ea+12)\n')
  assert(v25.major == 25)

  -- Feature flags derived from JDK major.
  local f24 = caps._compute_features(24)
  assert(f24.method_timing == false and f24.method_tracing == false)
  local f25 = caps._compute_features(25)
  assert(f25.method_timing == true and f25.method_tracing == true)

  -- VM.version output without explicit `version "..."` line
  local v_build = caps._parse_vm_version('OpenJDK 64-Bit Server VM (build 21.0.2+13, mixed mode, sharing)\n')
  assert(v_build.major == 21)

  -- VM.version output with leading pid header
  local v_pid = caps._parse_vm_version('4236: VM.version\nOpenJDK 64-Bit Server VM (build 21.0.2+13, mixed mode, sharing)\n')
  assert(v_pid.major == 21)

  -- VM.version output with pid-only header
  local v_pid2 = caps._parse_vm_version('4236:\nOpenJDK 64-Bit Server VM (build 21.0.2+13, mixed mode, sharing)\n')
  assert(v_pid2.major == 21)

  -- Ensure we don't misparse "64-Bit" as JDK major
  local v_arch = caps._parse_vm_version('OpenJDK 64-Bit Server VM (build 21.0.2+13, mixed mode, sharing)\n')
  assert(v_arch.major == 21)

  -- HotSpot VM build numbers can look like versions; don't treat these as JDK major.
  local v_hotspot_only = caps._parse_vm_version('Java HotSpot(TM) 64-Bit Server VM (build 25.402-b06, mixed mode)\n')
  assert(v_hotspot_only.major == nil)

  -- system_properties parsing fallback
  local sys = caps._parse_vm_system_properties('1234: VM.system_properties\njava.runtime.version = 21.0.2+13-LTS\n')
  assert(sys.major == 21)

  local opts = caps._parse_jfr_start_options(table.concat({
    "Syntax : JFR.start [options]",
    "Options:",
    "  name=<string>",
    "  duration=<timespan>",
    "  settings=<path>|default|profile",
    "  filename=<path>",
    "  delay=<timespan>",
    "  maxage=<timespan>",
    "  maxsize=<size>",
  }, "\n"))
  assert(opts.name and opts.duration and opts.settings and opts.filename)

  -- Column-list format (as printed by many JDKs): no '=' in the option column.
  local opts_cols = caps._parse_jfr_start_options(table.concat({
    "JFR.start",
    "Options:",
    "  duration         (Optional) Length of time to record.",
    "  filename         (Optional) Output file.",
    "  name             (Optional) Name of the recording.",
    "  settings         (Optional) Settings.",
    "  maxage           (Optional) Max age.",
  }, "\n"))
  assert(opts_cols.duration and opts_cols.filename and opts_cols.name and opts_cols.settings)
  assert(opts_cols.maxage)

  local presets = caps._parse_jfr_settings_presets(table.concat({
    "Options:",
    "  name=<string>",
    "  settings=<path>|default|profile",
  }, "\n"))
  assert(presets.default and presets.profile)

  local presets2, found2 = caps._parse_jfr_settings_presets(table.concat({
    "Options:",
    "  name=<string>",
    "  settings=<path>",
  }, "\n"))
  assert(found2 == true)
  assert(presets2.default == nil and presets2.profile == nil)

  local filtered, dropped = caps.filter_start_opts({
    name = "r",
    duration = "10s",
    filename = "x.jfr",
    settings = "profile",
    maxage = "1h",
    maxsize = "100M",
    notreal = "x",
  }, opts)
  assert(filtered.name == "r")
  assert(filtered.maxage == "1h")
  assert(filtered.maxsize == "100M")
  assert(filtered.notreal == nil)
  assert(#dropped == 1 and dropped[1] == "notreal")

  -- Empty supported-set should not drop anything (unknown capabilities).
  local keep, dropped2 = caps.filter_start_opts({ name = "r", duration = "10s" }, {})
  assert(keep.name == "r" and keep.duration == "10s")
  assert(#dropped2 == 0)

  return true
end

return M
