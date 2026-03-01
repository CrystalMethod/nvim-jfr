--- Headless spec for nvim-jfr.recording_meta.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.recording_meta_spec').run())" -c "qa"

local M = {}

M.run = function()
  local meta = require("nvim-jfr.recording_meta")
  local platform = require("nvim-jfr.platform")

  local root = vim.fn.tempname() .. "_jfr_meta"
  local rec_dir = platform.join_path(root, ".jfr", "recordings")
  vim.fn.mkdir(rec_dir, "p")

  local rec = platform.join_path(rec_dir, "x.jfr")
  vim.fn.writefile({ "dummy" }, rec)

  local abs_settings = platform.join_path(root, ".jfr", "templates", "custom.jfc")

  local ok, err = meta.write_for_recording(rec, {
    created_at = "2026-03-01T00:00:00Z",
    project_root = root,
    run_config_name = "alloc",
    jvm = { pid = 123, java_version = "21" },
    jfr_start = {
      duration = "60s",
      settings = abs_settings,
      start_overrides = { maxsize = "250M" },
    },
  })
  assert(ok == true, err)

  local mp = meta.meta_path(rec)
  assert(vim.fn.filereadable(mp) == 1)

  -- Should be pretty-printed (multi-line).
  local raw_lines = vim.fn.readfile(mp)
  assert(type(raw_lines) == "table" and #raw_lines > 1)

  local decoded = assert(meta.read_for_recording(rec))
  assert(decoded.schema_version == 1)
  assert(decoded.project_root == nil)
  assert(decoded.run_config_name == "alloc")
  assert(decoded.recording and decoded.recording.filename == "x.jfr")
  assert(decoded.recording.path == ".jfr/recordings/x.jfr")
  assert(decoded.jfr_start and type(decoded.jfr_start.settings) == "table")
  assert(decoded.jfr_start.settings.kind == "file")
  assert(decoded.jfr_start.settings.path == ".jfr/templates/custom.jfc")

  -- Presets should be stored explicitly.
  local rec2 = platform.join_path(rec_dir, "y.jfr")
  vim.fn.writefile({ "dummy" }, rec2)
  assert(meta.write_for_recording(rec2, { project_root = root, jfr_start = { settings = "profile" } }))
  local d2 = assert(meta.read_for_recording(rec2))
  assert(d2.jfr_start.settings.kind == "preset")
  assert(d2.jfr_start.settings.value == "profile")

  return true
end

return M
