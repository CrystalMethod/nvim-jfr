--- Per-recording metadata sidecar (.json) written next to saved .jfr files.
---
--- Goals:
--- - Make recordings self-describing (how they were produced)
--- - Avoid leaking machine-specific/private absolute paths
--- - Keep format readable by non-Lua users (JSON)
---
--- @module nvim-jfr.recording_meta

local M = {}

local platform = require("nvim-jfr.platform")
local uv = vim.uv or vim.loop

local function encode_json_compact(v)
  if vim.json and type(vim.json.encode) == "function" then
    return vim.json.encode(v)
  end
  return vim.fn.json_encode(v)
end

local function decode_json(str)
  if vim.json and type(vim.json.decode) == "function" then
    return vim.json.decode(str)
  end
  return vim.fn.json_decode(str)
end

local function is_array(t)
  if type(t) ~= "table" then
    return false
  end
  local n = #t
  for k, _ in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
    if k < 1 or k > n or k % 1 ~= 0 then
      return false
    end
  end
  return true
end

local function sorted_keys(t)
  local keys = {}
  for k, _ in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function pretty_json_lines(value, indent, level)
  indent = indent or "  "
  level = level or 0

  local pad = string.rep(indent, level)
  local pad_in = string.rep(indent, level + 1)

  if type(value) ~= "table" then
    return { pad .. encode_json_compact(value) }
  end

  if is_array(value) then
    if #value == 0 then
      return { pad .. "[]" }
    end
    local lines = { pad .. "[" }
    for i, v in ipairs(value) do
      local child = pretty_json_lines(v, indent, level + 1)
      -- child is already padded.
      for j, l in ipairs(child) do
        if j == 1 then
          local comma = (i < #value) and "," or ""
          lines[#lines + 1] = l .. comma
        else
          lines[#lines + 1] = l
        end
      end
    end
    lines[#lines + 1] = pad .. "]"
    return lines
  end

  local keys = sorted_keys(value)
  if #keys == 0 then
    return { pad .. "{}" }
  end
  local lines = { pad .. "{" }
  for idx, k in ipairs(keys) do
    local v = value[k]
    local key_json = encode_json_compact(tostring(k))
    if type(v) == "table" then
      local child = pretty_json_lines(v, indent, level + 1)
      -- Replace first line to include the key.
      child[1] = pad_in .. key_json .. ": " .. vim.trim(child[1])
      local comma = (idx < #keys) and "," or ""
      child[#child] = child[#child] .. comma
      vim.list_extend(lines, child)
    else
      local comma = (idx < #keys) and "," or ""
      lines[#lines + 1] = pad_in .. key_json .. ": " .. encode_json_compact(v) .. comma
    end
  end
  lines[#lines + 1] = pad .. "}"
  return lines
end

local function file_exists(path)
  local st = path and uv and uv.fs_stat and uv.fs_stat(path) or nil
  return st and st.type == "file" or false
end

local function normalize(path)
  if not path then
    return nil
  end
  path = vim.trim(tostring(path))
  if path == "" then
    return nil
  end
  return platform.normalize_path(path)
end

local function path_starts_with(path, prefix)
  path = platform.normalize_path(path or "")
  prefix = platform.normalize_path(prefix or "")
  if path == "" or prefix == "" then
    return false
  end
  local sep = platform.path_sep()
  if prefix:sub(-1) ~= sep then
    prefix = prefix .. sep
  end
  return path:sub(1, #prefix) == prefix
end

local function infer_project_root_from_recording_path(recording_path)
  local p = normalize(recording_path)
  if not p then
    return nil
  end
  -- We only infer roots for the canonical project layout.
  local needle = platform.normalize_path("/.jfr/recordings/")
  local idx = p:find(needle, 1, true)
  if not idx then
    return nil
  end
  return p:sub(1, idx - 1)
end

local function relpath(root, abs)
  root = normalize(root)
  abs = normalize(abs)
  if not root or not abs then
    return nil
  end
  if not path_starts_with(abs, root) then
    return nil
  end
  -- +2 to skip trailing separator we ensured in path_starts_with.
  local sep = platform.path_sep()
  if root:sub(-1) ~= sep then
    root = root .. sep
  end
  return abs:sub(#root + 1)
end

--- Compute the sidecar metadata file path for a recording.
--- @param recording_path string
--- @return string meta_path
M.meta_path = function(recording_path)
  recording_path = normalize(recording_path) or ""
  return recording_path .. ".json"
end

--- Read meta JSON for a recording (if present).
--- @param recording_path string
--- @return table? meta
--- @return string? err
M.read_for_recording = function(recording_path)
  local mp = M.meta_path(recording_path)
  if not file_exists(mp) then
    return nil, nil
  end
  local lines = vim.fn.readfile(mp)
  local txt = table.concat(lines or {}, "\n")
  local ok, decoded = pcall(decode_json, txt)
  if not ok then
    return nil, "failed to decode meta json: " .. tostring(decoded)
  end
  if type(decoded) ~= "table" then
    return nil, "meta json did not decode to a table"
  end
  return decoded, nil
end

--- Write meta JSON next to a saved .jfr recording.
--- NOTE: Will NOT write absolute paths; callers may supply absolute values
--- in `meta_raw` but they will be redacted/relativized.
---
--- @param recording_path string absolute path to saved recording
--- @param meta_raw table
--- @return boolean ok
--- @return string? err
M.write_for_recording = function(recording_path, meta_raw)
  recording_path = normalize(recording_path)
  if not recording_path or recording_path == "" then
    return false, "missing recording_path"
  end
  if vim.fn.filereadable(recording_path) ~= 1 then
    return false, "recording does not exist: " .. recording_path
  end

  meta_raw = meta_raw or {}
  if type(meta_raw) ~= "table" then
    return false, "meta must be a table"
  end

  -- Infer project root from the recording path when possible.
  local root = meta_raw.project_root or infer_project_root_from_recording_path(recording_path)
  root = normalize(root)

  local meta = vim.deepcopy(meta_raw)
  meta.schema_version = meta.schema_version or 1

  -- Never write project_root; it is machine-specific.
  meta.project_root = nil

  -- Recording path: store relative when possible, else only filename.
  local rec_rel = root and relpath(root, recording_path) or nil
  meta.recording = meta.recording or {}
  if type(meta.recording) ~= "table" then
    meta.recording = {}
  end
  meta.recording.filename = vim.fn.fnamemodify(recording_path, ":t")
  if rec_rel then
    meta.recording.path = rec_rel
    meta.recording.path_base = "project"
  else
    meta.recording.path = nil
    meta.recording.path_base = nil
  end

  -- Settings: redact absolute paths; only store a project-relative path.
  if meta.jfr_start and type(meta.jfr_start) == "table" then
    local s = meta.jfr_start.settings
    if type(s) == "string" then
      local lower = s:lower()
      if lower == "default" or lower == "profile" then
        meta.jfr_start.settings = { kind = "preset", value = lower }
      else
        local abs = normalize(s)
        local rel = (root and abs and relpath(root, abs)) or nil
        if rel then
          meta.jfr_start.settings = { kind = "file", path = rel, path_base = "project" }
        else
          meta.jfr_start.settings = { kind = "file", path = "<redacted>", redacted = true }
        end
      end
    end
  end

  local mp = M.meta_path(recording_path)

  local ok_lines, lines = pcall(pretty_json_lines, meta)
  if not ok_lines then
    return false, "failed to encode meta json: " .. tostring(lines)
  end

  local w_ok = pcall(vim.fn.writefile, lines, mp)
  if not w_ok then
    return false, "failed to write meta file: " .. mp
  end
  return true, nil
end

return M
