--- Overrides module - per-recording settings overrides.
---
--- This is intentionally conservative: we only support adding extra
--- `key=value` start options (e.g. maxage/maxsize/dumponexit) on top of the
--- base start options produced by commands.lua.
---
--- @module nvim-jfr.overrides

local M = {}

local function normalize_key(k)
  if k == nil then
    return nil
  end
  k = tostring(k)
  k = vim.trim(k)
  if k == "" then
    return nil
  end
  return k
end

--- Apply overrides onto an existing start options table.
---
--- @param base table base options (mutated copy is returned)
--- @param overrides table? override key->value
--- @param supported table<string, boolean>? capability supported keys
--- @return table merged
--- @return string[] applied_keys
--- @return string[] rejected_keys
M.apply = function(base, overrides, supported)
  local merged = vim.deepcopy(base or {})
  local applied, rejected = {}, {}
  overrides = overrides or {}

  -- Treat an empty supported-set as "unknown", meaning allow all keys.
  if type(supported) == "table" and next(supported) == nil then
    supported = nil
  end

  for k, v in pairs(overrides) do
    local nk = normalize_key(k)
    if nk then
      if supported and supported[nk] ~= true then
        table.insert(rejected, nk)
      else
        merged[nk] = v
        table.insert(applied, nk)
      end
    end
  end

  table.sort(applied)
  table.sort(rejected)
  return merged, applied, rejected
end

return M
