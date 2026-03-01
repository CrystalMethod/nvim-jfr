--- Minimal headless checks for nvim-jfr.capabilities_ui.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.capabilities_ui_spec').run())" -c "qa"

local M = {}

local ui = require("nvim-jfr.capabilities_ui")

M.run = function()
  local cap = {
    pid = 123,
    jdk = { major = 21, vendor = "OpenJDK", raw = "21 raw" },
    jfr = {
      has_configure = true,
      settings_presets = { default = true, profile = true },
      settings_presets_found = true,
      start_options = { name = true, duration = true, settings = true, filename = true, maxage = true },
      start_help_raw = "help raw",
    },
    features = { method_timing = false, method_tracing = false },
  }

  local txt = ui.format(cap, { verbose = false, settings_override = "profile" })
  assert(txt:find("## Summary", 1, true))
  assert(txt:find("JDK major: 21", 1, true))
  assert(txt:find("## Links", 1, true))
  assert(txt:find("jcmd manual:", 1, true))
  assert(txt:find("Settings check (--settings=profile): supported", 1, true))
  assert(txt:find("Supported options", 1, true))
  assert(txt:find("### Recording control", 1, true))
  assert(txt:find("`duration=`", 1, true))
  assert(txt:find("### Output / storage", 1, true))
  assert(txt:find("`filename=`", 1, true))
  assert(txt:find("### Retention", 1, true))
  assert(txt:find("`maxage=`", 1, true))
  assert(not txt:find("## Raw (verbose)", 1, true))

  local vtxt = ui.format(cap, { verbose = true })
  assert(vtxt:find("## Raw (verbose)", 1, true))
  assert(vtxt:find("### VM.version", 1, true))
  assert(vtxt:find("21 raw", 1, true))
  assert(vtxt:find("### help JFR.start", 1, true))
  assert(vtxt:find("help raw", 1, true))

  -- Docs mapping: known majors (17/21/25) and fallback
  assert(ui.jcmd_docs_url(21):find("/21/", 1, true))
  assert(ui.jcmd_docs_url(17):find("/17/", 1, true))
  assert(ui.jcmd_docs_url(25):find("/25/", 1, true))
  -- Unknown/garbage major => hub
  assert(ui.jcmd_docs_url("?") == "https://docs.oracle.com/en/java/javase/")
  -- Non-LTS major should map to nearest known line (currently 25)
  assert(ui.jcmd_docs_url(26):find("/25/", 1, true))

  return true
end

return M
