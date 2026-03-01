--- Minimal headless checks for nvim-jfr.recordings.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.recordings_spec').run())" -c "qa"

local M = {}

local recordings = require("nvim-jfr.recordings")

local function with_cwd(dir, fn)
  local prev = vim.fn.getcwd()
  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  local ok, err = pcall(fn)
  vim.cmd("cd " .. vim.fn.fnameescape(prev))
  if not ok then
    error(err)
  end
end

M.run = function()
  -- Avoid cross-test contamination from project root caching.
  pcall(function()
    require("nvim-jfr.project").clear_root_cache()
  end)

  local dir = vim.fn.tempname() .. "_jfr_out"
  local ok, err = recordings.ensure_output_dir(dir)
  assert(ok == true, err)
  assert(vim.fn.isdirectory(dir) == 1)

  -- create a couple fake .jfr files
  local f1 = recordings.resolve_output_path("a.jfr", dir)
  local f = assert(io.open(f1, "w"))
  f:write("x")
  f:close()

  local f2 = recordings.resolve_output_path("b.jfr", dir)
  local f_b = assert(io.open(f2, "w"))
  f_b:write("y")
  f_b:close()

  local list = recordings.list_files(dir)
  assert(type(list) == "table" and #list >= 2)
  assert(list[1].display ~= nil)

  -- Create a meta sidecar for f1 and ensure delete_file removes it too.
  local ok_meta, meta_mod = pcall(require, "nvim-jfr.recording_meta")
  assert(ok_meta and meta_mod)
  assert(meta_mod.write_for_recording(f1, { created_at = "2026-03-01T00:00:00Z" }))
  local mp1 = meta_mod.meta_path(f1)
  assert(vim.fn.filereadable(mp1) == 1)

  local ok_del, err_del = recordings.delete_file(f1)
  assert(ok_del == true, err_del)
  assert(vim.fn.filereadable(f1) ~= 1)

  -- Sidecar meta should also be deleted (best-effort).
  assert(vim.fn.filereadable(mp1) ~= 1)

  local ok2, err2 = recordings.ensure_parent_dir(recordings.resolve_output_path("nested/b.jfr", dir))
  assert(ok2 == true, err2)

  vim.fn.delete(dir, "rf")

  -- output_dir = "project" should resolve to <root>/.jfr/recordings when a root is detected.
  local proj = vim.fn.tempname() .. "_jfr_proj"
  vim.fn.mkdir(proj, "p")
  -- Create a marker so project.get_root can find it.
  local pom = assert(io.open(proj .. "/pom.xml", "w"))
  pom:write("<project></project>")
  pom:close()
  with_cwd(proj, function()
    pcall(function()
      require("nvim-jfr.project").clear_root_cache()
    end)
    local out = recordings.get_output_dir({ output_dir = "project" })
    assert(out:match("%.jfr[/\\]recordings") ~= nil)
  end)
  vim.fn.delete(proj, "rf")

  return true
end

return M
