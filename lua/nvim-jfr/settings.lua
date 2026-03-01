--- Settings resolution for JFR.start.
--- @module nvim-jfr.settings

local M = {}

local uv = vim.uv or vim.loop

local function file_exists(path)
  if not path or path == "" then
    return false
  end
  local stat = uv.fs_stat(path)
  return stat and stat.type == "file" or false
end

local function normalize_path(p)
  if not p then
    return nil
  end
  p = tostring(p)
  p = vim.trim(p)
  if p == "" then
    return nil
  end
  return p
end

--- Resolve settings value for `jcmd <pid> JFR.start settings=...`.
---
--- Precedence:
---  1) explicit settings value (CLI)
---  2) configured settings value
---
--- @param opts table { settings_value: string?, configured_settings_value: string? }
--- @return string? settings_value
--- @return string? error
M.resolve = function(opts)
  opts = opts or {}

  local settings_value = normalize_path(opts.settings_value) or normalize_path(opts.configured_settings_value)
  if not settings_value then
    return nil, "missing settings value"
  end

  local s = settings_value:lower()
  if s == "default" or s == "profile" then
    return s, nil
  end

  -- Otherwise treat as a path to a .jfc file.
  if not file_exists(settings_value) then
    return nil, "JFC file does not exist: " .. settings_value
  end
  return settings_value, nil
end

--- Validate that a resolved settings value is supported.
--- @param settings_value string
--- @param cap table? capabilities returned from nvim-jfr.capabilities.detect
--- @return boolean ok
--- @return string? error
M.validate_supported = function(settings_value, cap)
  if not settings_value then
    return false, "missing settings value"
  end

  local validate_value = settings_value

  if not cap or not cap.jfr then
    return true, nil
  end

  -- If the JVM reports supported start options, ensure `settings` is allowed.
  if cap.jfr.start_options and next(cap.jfr.start_options) ~= nil then
    if not cap.jfr.start_options.settings then
      return false, "This JVM does not support JFR.start 'settings=' option"
    end
  end

  -- If we detected a concrete list of built-in presets, validate preset values.
  -- (paths are always allowed when settings= exists).
  if (validate_value == "default" or validate_value == "profile")
    and cap.jfr.settings_presets_found
    and cap.jfr.settings_presets
  then
    if not cap.jfr.settings_presets[validate_value] then
      local avail = {}
      for k, v in pairs(cap.jfr.settings_presets) do
        if v then
          table.insert(avail, k)
        end
      end
      table.sort(avail)
      return false,
        string.format(
          "Preset '%s' is not supported by this JVM. Supported presets: %s",
          tostring(validate_value),
          (#avail > 0 and table.concat(avail, ", ") or "<none>")
        )
    end
  end

  return true, nil
end

return M
