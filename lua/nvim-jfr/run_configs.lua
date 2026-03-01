--- Project-only named run configurations.
---
--- File: <root>/.jfr/run-configs.lua
---
--- Schema:
---   return {
---     default = "name"?,
---     configs = {
---       ["name"] = {
---         settings = "profile"|"default"|".jfr/templates/foo.jfc"|"/abs/foo.jfc"?,
---         duration = "60s"?,
---         start_overrides = { maxsize = "250M", ... }?,
---       },
---     },
---   }
---
--- Note: For run configs, custom .jfc settings MUST live under
--- <root>/.jfr/templates. (Built-in settings: default/profile)
---
--- @module nvim-jfr.run_configs

local M = {}

local platform = require("nvim-jfr.platform")
local uv = vim.uv or vim.loop

local function is_abs(path)
  if not path then
    return false
  end
  path = tostring(path)
  if path:match("^/") then
    return true
  end
  -- Windows drive letter or UNC.
  if path:match("^%a:[/\\]") or path:match("^\\\\") then
    return true
  end
  return false
end

local function normalize(p)
  if p == nil then
    return nil
  end
  p = vim.trim(tostring(p))
  if p == "" then
    return nil
  end
  return platform.normalize_path(p)
end

local function path_starts_with(path, prefix)
  path = platform.normalize_path(path or "")
  prefix = platform.normalize_path(prefix or "")
  if path == "" or prefix == "" then
    return false
  end

  -- Ensure we only match whole directory prefix.
  local sep = platform.path_sep()
  if prefix:sub(-1) ~= sep then
    prefix = prefix .. sep
  end
  return path:sub(1, #prefix) == prefix
end

local function realpath(p)
  if not p then
    return nil
  end
  local rp = uv.fs_realpath(p)
  return rp or p
end

M.file_path = function(root)
  if not root or root == "" then
    return nil
  end
  return platform.join_path(root, ".jfr", "run-configs.lua")
end

--- Load run-configs.lua for a project.
--- @param root string
--- @return table res { ok: boolean, data?: table, path?: string, err?: string }
M.load = function(root)
  local path = M.file_path(root)
  if not path then
    return { ok = false, err = "missing project root" }
  end
  if vim.fn.filereadable(path) ~= 1 then
    return { ok = false, err = "run configs file not found: " .. path, path = path }
  end

  local chunk, load_err = loadfile(path)
  if not chunk then
    return { ok = false, err = "failed to load run configs: " .. tostring(load_err), path = path }
  end

  local ok, data = pcall(chunk)
  if not ok then
    return { ok = false, err = "error evaluating run configs: " .. tostring(data), path = path }
  end
  if type(data) ~= "table" then
    return { ok = false, err = "run configs must return a table", path = path }
  end

  data.configs = data.configs or {}
  if type(data.configs) ~= "table" then
    return { ok = false, err = "run configs: 'configs' must be a table", path = path }
  end

  return { ok = true, data = data, path = path }
end

--- List run configs as picker items.
--- @param root string
--- @return table[] items { name, config }
--- @return string? err
M.list = function(root)
  local res = M.load(root)
  if not res.ok then
    return {}, res.err
  end
  local items = {}
  for name, cfg in pairs(res.data.configs or {}) do
    if type(name) == "string" and name ~= "" and type(cfg) == "table" then
      table.insert(items, { name = name, id = name, display = name, config = cfg })
    end
  end
  table.sort(items, function(a, b)
    return tostring(a.name) < tostring(b.name)
  end)
  return items, nil
end

M.get_default_name = function(root)
  local res = M.load(root)
  if not res.ok then
    return nil
  end
  local d = res.data.default
  if type(d) ~= "string" or vim.trim(d) == "" then
    return nil
  end
  return vim.trim(d)
end

M.get = function(root, name)
  name = normalize(name)
  if not name then
    return nil, "missing run config name"
  end
  local res = M.load(root)
  if not res.ok then
    return nil, res.err
  end
  local cfg = res.data.configs and res.data.configs[name] or nil
  if type(cfg) ~= "table" then
    return nil, "unknown run config: " .. name
  end
  return cfg, nil
end

--- Resolve a settings value coming from a run config.
--- Enforces that custom JFC paths live under <root>/.jfr/templates.
---
--- @param root string
--- @param value string?
--- @return string? resolved_value ("default"|"profile"|"/abs/path.jfc")
--- @return string? err
M.resolve_run_settings = function(root, value)
  value = normalize(value)
  if not value then
    return nil, nil
  end

  local s = value:lower()
  if s == "default" or s == "profile" then
    return s, nil
  end

  if not root or root == "" then
    return nil, "missing project root"
  end

  local abs = value
  if not is_abs(value) then
    abs = platform.join_path(root, value)
  end
  abs = platform.normalize_path(abs)

  local templates_dir = platform.normalize_path(platform.join_path(root, ".jfr", "templates"))

  -- Enforce containment using real paths to avoid ../ traversal and symlink escapes.
  local abs_rp = platform.normalize_path(realpath(abs))
  local templates_rp = platform.normalize_path(realpath(templates_dir))

  if not path_starts_with(abs_rp, templates_rp) then
    return nil, "run config settings path must be under <root>/.jfr/templates: " .. abs
  end

  if vim.fn.filereadable(abs) ~= 1 then
    return nil, "JFC file does not exist: " .. abs
  end

  return abs, nil
end

return M
