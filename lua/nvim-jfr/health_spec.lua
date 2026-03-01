--- Minimal headless checks for nvim-jfr.health.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.health_spec').run())" -c "qa"

local M = {}

M.run = function()
  local health = require("nvim-jfr.health")
  local api = health._health_api()
  assert(type(api.start) == "function")
  assert(type(api.ok) == "function")
  assert(type(api.warn) == "function")
  assert(type(api.error) == "function")
  assert(type(api.info) == "function")

  -- Pure helper checks
  assert(health._ver_to_string({ major = 0, minor = 8, patch = 0 }) == "0.8.0")
  assert(health._version_at_least({ major = 0, minor = 8, patch = 0 }, { major = 0, minor = 8, patch = 0 }) == true)
  assert(health._version_at_least({ major = 0, minor = 7, patch = 9 }, { major = 0, minor = 8, patch = 0 }) == false)
  assert(health._version_at_least({ major = 0, minor = 10, patch = 0 }, { major = 0, minor = 8, patch = 0 }) == true)

  assert(health._command_head("jcmd -l") == "jcmd")
  assert(health._command_head('"C:\\Program Files\\Java\\bin\\jcmd.exe" -l') == "C:\\Program Files\\Java\\bin\\jcmd.exe")
  assert(health._command_head("") == nil)

  local missing = health._resolve_executable("__definitely_missing__")
  assert(missing.ok == false)

  assert(health._is_nonempty_string("foo") == true)
  assert(health._is_nonempty_string(" ") == false)
  assert(health._is_nonempty_string(nil) == false)
  assert(health._type_name({}) == "table")

  -- resolve_executable table shape (do not require any real executables)
  do
    local r = health._resolve_executable("__definitely_missing__")
    assert(type(r) == "table")
    assert(r.ok == false)
    assert(r.head == "__definitely_missing__")
    assert(r.path == nil)
  end

  -- command_head: quoted executable
  assert(health._command_head('"/Applications/Java 21/bin/jcmd" -l') == "/Applications/Java 21/bin/jcmd")

  -- picker.detect should always return a backend string
  do
    local picker = require("nvim-jfr.picker")
    local eff = picker.detect("auto")
    assert(type(eff) == "string" and eff ~= "")
  end

  -- Smoke: picker check helper exists
  assert(type(health._check_picker_backend) == "function")
  assert(type(health._check_output_dir_and_root) == "function")
  return true
end

return M
