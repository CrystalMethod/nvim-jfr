--- JFC (JFR settings XML) helpers.
---
--- This module intentionally keeps only non-UI helpers.
---
--- NOTE: nvim-jfr does not provide user commands for validating/formatting JFC
--- files. Prefer an XML LSP (e.g. LemMinX) or external tooling.

local M = {}

local uv = vim.uv or vim.loop

local function file_exists(path)
  if not path or path == "" then
    return false
  end
  local st = uv.fs_stat(path)
  return st and st.type == "file" or false
end

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "failed to read file: " .. tostring(path)
  end
  if type(lines) ~= "table" then
    return nil, "failed to read file: " .. tostring(path)
  end
  return lines, nil
end

local function write_lines(path, lines)
  local ok, res = pcall(vim.fn.writefile, lines, path)
  if not ok then
    return false, "failed to write file: " .. tostring(path)
  end
  -- writefile returns 0 on success.
  if res ~= 0 then
    return false, "failed to write file: " .. tostring(path)
  end
  return true, nil
end

local function is_jfc_path(path)
  path = tostring(path or "")
  return path:lower():sub(-4) == ".jfc"
end

local function current_buf_path()
  local p = vim.api.nvim_buf_get_name(0)
  if not p or vim.trim(p) == "" then
    return nil
  end
  return p
end

--- Resolve a target .jfc path.
---
--- Precedence:
---  1) explicit path argument
---  2) current buffer path (if it looks like *.jfc)
---  3) configured config.settings (when it points at a .jfc file)
---
--- @param path_arg string?
--- @return string? path
--- @return string? error
M.resolve_target = function(path_arg)
  path_arg = path_arg and vim.trim(tostring(path_arg)) or nil
  if path_arg ~= nil and path_arg ~= "" then
    return path_arg, nil
  end

  local bufp = current_buf_path()
  if bufp and is_jfc_path(bufp) then
    return bufp, nil
  end

  local ok_cfg, cfgmod = pcall(require, "nvim-jfr.config")
  local cfg = (ok_cfg and cfgmod and cfgmod.get and cfgmod.get()) or {}
  if cfg.settings and tostring(cfg.settings) ~= "" then
    local s = tostring(cfg.settings)
    local sl = s:lower()
    if sl ~= "default" and sl ~= "profile" then
      return s, nil
    end
  end

  return nil, "No .jfc selected. Pass an explicit path, edit a .jfc buffer, or set config.settings to a .jfc path."
end

--- Copy a JFC template file to a destination path.
--- Ensures parent directories exist.
---
--- @param src string Template path
--- @param dest string Destination path
--- @param opts table? { overwrite:boolean? }
--- @return boolean ok
--- @return string? err
M.copy_template = function(src, dest, opts)
  opts = opts or {}
  src = src and vim.trim(tostring(src)) or ""
  dest = dest and vim.trim(tostring(dest)) or ""
  if src == "" then
    return false, "missing source template path"
  end
  if dest == "" then
    return false, "missing destination path"
  end

  if not file_exists(src) then
    return false, "template does not exist: " .. tostring(src)
  end

  if file_exists(dest) and opts.overwrite ~= true then
    return false, "destination already exists: " .. tostring(dest)
  end

  local rec = require("nvim-jfr.recordings")
  local ok_parent, err_parent = rec.ensure_parent_dir(dest)
  if not ok_parent then
    return false, err_parent
  end

  local lines, err_read = read_lines(src)
  if not lines then
    return false, err_read
  end

  local ok_write, err_write = write_lines(dest, lines)
  if not ok_write then
    return false, err_write
  end

  return true, nil
end

return M
