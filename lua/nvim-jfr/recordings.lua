--- Recording file/path utilities.
--- @module nvim-jfr.recordings

local M = {}

local platform = require("nvim-jfr.platform")

local function expand_path(p)
  if not p then
    return nil
  end
  p = tostring(p)
  p = vim.trim(p)
  if p == "" then
    return nil
  end
  -- expand ~ and environment variables
  return vim.fn.expand(p)
end

--- List .jfr files in output_dir.
--- @param output_dir string
--- @return table[] files { path:string, name:string, mtime:integer?, size:integer? }
M.list_files = function(output_dir)
  local dir = expand_path(output_dir)
  if not dir or vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end

  local uv = vim.uv or vim.loop
  local handle = uv.fs_scandir(dir)
  if not handle then
    return {}
  end

  local out = {}
  while true do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if t == "file" and name:sub(-4) == ".jfr" then
      local path = platform.join_path(dir, name)
      local st = uv.fs_stat(path)
      table.insert(out, {
        path = platform.normalize_path(path),
        name = name,
        display = name,
        mtime = st and st.mtime and st.mtime.sec or nil,
        size = st and st.size or nil,
      })
    end
  end

  table.sort(out, function(a, b)
    return (a.mtime or 0) > (b.mtime or 0)
  end)

  return out
end

--- Delete a recording file.
--- @param path string
--- @return boolean ok
--- @return string? err
M.delete_file = function(path)
  path = expand_path(path)
  if not path or path == "" then
    return false, "missing path"
  end
  if vim.fn.filereadable(path) ~= 1 then
    return false, "file not found: " .. path
  end

  -- Best-effort: also delete sidecar meta file (<recording>.jfr.json).
  pcall(function()
    local ok_meta, meta_mod = pcall(require, "nvim-jfr.recording_meta")
    if ok_meta and meta_mod and type(meta_mod.meta_path) == "function" then
      local mp = meta_mod.meta_path(path)
      if mp and mp ~= "" and vim.fn.filereadable(mp) == 1 then
        os.remove(mp)
      end
    end
  end)

  local ok, err = os.remove(path)
  if not ok then
    return false, err or ("failed to delete: " .. path)
  end
  return true, nil
end

local function is_abs(path)
  path = path or ""
  if platform.get_platform() == "windows" then
    -- C:\..., C:/..., or UNC \\server\share
    return path:match("^%a:[/\\]") ~= nil or path:match("^\\\\") ~= nil
  end
  return path:sub(1, 1) == "/"
end

--- Compute effective output directory.
--- @param config table? nvim-jfr config
--- @return string dir
M.get_output_dir = function(config)
  local dir = (config and config.output_dir) or platform.get_default_output_dir()

  if dir == "project" then
    local ok_proj, proj = pcall(require, "nvim-jfr.project")
    local root = ok_proj and proj and proj.get_root and proj.get_root(0) or nil
    if root and root ~= "" then
      dir = platform.join_path(root, ".jfr", "recordings")
    else
      dir = platform.get_default_output_dir()
    end
  end

  dir = expand_path(dir) or platform.get_default_output_dir()
  return platform.normalize_path(dir)
end

--- Ensure output directory exists.
--- @param dir string
--- @return boolean ok
--- @return string? err
M.ensure_output_dir = function(dir)
  dir = expand_path(dir)
  if not dir then
    return false, "missing output directory"
  end

  if vim.fn.isdirectory(dir) == 1 then
    return true, nil
  end

  if platform.exists(dir) and vim.fn.isdirectory(dir) ~= 1 then
    return false, "output_dir exists but is not a directory: " .. dir
  end

  local ok = platform.mkdir(dir)
  if not ok or vim.fn.isdirectory(dir) ~= 1 then
    return false, "failed to create output directory: " .. dir
  end
  return true, nil
end

--- Resolve a recording filename to a full path inside output_dir.
--- Absolute filenames are returned as-is.
--- @param filename string
--- @param output_dir string
--- @return string path
M.resolve_output_path = function(filename, output_dir)
  local f = expand_path(filename) or ""
  local dir = expand_path(output_dir) or platform.get_default_output_dir()
  dir = platform.normalize_path(dir)

  if is_abs(f) then
    return platform.normalize_path(f)
  end
  return platform.join_path(dir, f)
end

--- Ensure the parent directory for a file path exists.
--- @param filepath string
--- @return boolean ok
--- @return string? err
M.ensure_parent_dir = function(filepath)
  filepath = expand_path(filepath)
  if not filepath then
    return false, "missing filepath"
  end
  local parent = vim.fn.fnamemodify(filepath, ":h")
  if not parent or parent == "" then
    return true, nil
  end
  if vim.fn.isdirectory(parent) == 1 then
    return true, nil
  end
  local ok = platform.mkdir(parent)
  if not ok or vim.fn.isdirectory(parent) ~= 1 then
    return false, "failed to create directory: " .. parent
  end
  return true, nil
end

return M
