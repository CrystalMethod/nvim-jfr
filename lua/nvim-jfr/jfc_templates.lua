--- JFC templates discovery helpers.
--
-- Provides a way to list *.jfc files from configured template directories
-- (global + project-local).

local M = {}

local platform = require("nvim-jfr.platform")

local uv = vim.uv or vim.loop

local function file_exists(path)
  if not path or path == "" then
    return false
  end
  local st = uv.fs_stat(path)
  return st and st.type == "file" or false
end

local function dir_exists(path)
  if not path or path == "" then
    return false
  end
  local st = uv.fs_stat(path)
  return st and st.type == "directory" or false
end

local function normalize(path)
  return platform.normalize_path(vim.fn.expand(tostring(path or "")))
end

local function basename(path)
  return vim.fn.fnamemodify(path, ":t")
end

local function source_label(source)
  if source == "java_home" then
    return "JDK ($JAVA_HOME/lib/jfr)"
  end
  if source == "project" then
    return "project"
  end
  return tostring(source or "")
end

local function add_dir(dirs, source, dir)
  dir = normalize(dir)
  if dir and tostring(dir) ~= "" then
    table.insert(dirs, { source = source, dir = dir })
  end
end

local function scan_dir(dir)
  dir = normalize(dir)
  if not dir_exists(dir) then
    return {}
  end

  local out = {}
  local handle = uv.fs_scandir(dir)
  if not handle then
    return out
  end

  while true do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if t == "file" and name:lower():sub(-4) == ".jfc" then
      local path = platform.join_path(dir, name)
      if file_exists(path) then
        table.insert(out, platform.normalize_path(path))
      end
    end
  end
  table.sort(out)
  return out
end

--- Compute candidate template directories from config.
-- @return table dirs
M.get_template_dirs = function(cfg)
  cfg = cfg or require("nvim-jfr.config").get()
  local tcfg = (cfg and cfg.jfc_templates) or {}

  local dirs = {}

  if tcfg.include_java_home == true then
    local java_home = vim.env.JAVA_HOME
    if java_home and tostring(java_home) ~= "" then
      add_dir(dirs, "java_home", platform.join_path(java_home, "lib", "jfr"))
    end
  end

  local ok_proj, proj = pcall(require, "nvim-jfr.project")
  local root = ok_proj and proj and proj.get_root and proj.get_root(0) or nil

  local pdirs = tcfg.project_dirs
  if root and root ~= "" and type(pdirs) == "table" then
    for _, rel in ipairs(pdirs) do
      if rel and tostring(rel) ~= "" then
        table.insert(dirs, { source = "project", dir = platform.join_path(root, tostring(rel)) })
      end
    end
  end

  return dirs
end

--- List available JFC templates.
-- @return table[] templates { name, path, source, display }
M.list = function(cfg)
  local dirs = M.get_template_dirs(cfg)
  local items = {}
  local seen = {}

  for _, entry in ipairs(dirs) do
    for _, path in ipairs(scan_dir(entry.dir)) do
      if not seen[path] then
        seen[path] = true
        local name = basename(path)
        table.insert(items, {
          name = name,
          path = path,
          source = entry.source,
          display = string.format("%s [%s]", name, source_label(entry.source)),
        })
      end
    end
  end

  table.sort(items, function(a, b)
    if a.name == b.name then
      return a.source < b.source
    end
    return a.name < b.name
  end)
  return items
end

return M
