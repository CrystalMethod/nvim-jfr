--- Platform utilities for cross-platform support (Windows/macOS/Linux)
--- @module nvim-jfr.platform

local M = {}

--- Get the current platform
---@return string Platform: "windows", "macos", or "linux"
M.get_platform = function()
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    return "windows"
  elseif vim.fn.has("mac") == 1 then
    return "macos"
  else
    return "linux"
  end
end

--- Get the path separator for the current platform
---@return string Path separator
M.path_sep = function()
  if M.get_platform() == "windows" then
    return "\\"
  else
    return "/"
  end
end

--- Join path segments
---@vararg string Path segments
---@return string Joined path
M.join_path = function(...)
  local args = { ... }
  local sep = M.path_sep()
  local result = table.concat(args, sep)
  -- Normalize multiple separators
  result = result:gsub(sep .. "+", sep)
  return result
end

--- Get the default output directory for recordings
---@return string Default output directory path
M.get_default_output_dir = function()
  local platform = M.get_platform()
  local home = vim.env.HOME or vim.env.USERPROFILE or ""

  if platform == "windows" then
    return M.join_path(vim.env.USERPROFILE or "C:\\", "jfr-recordings")
  else
    return M.join_path(home, "jfr-recordings")
  end
end

--- Normalize a path for the current platform
---@param path string Path to normalize
---@return string Normalized path
M.normalize_path = function(path)
  if not path then
    return nil
  end
  local platform = M.get_platform()
  if platform == "windows" then
    -- Convert forward slashes to backslashes on Windows
    return (path:gsub("/", "\\"))
  else
    -- Convert backslashes to forward slashes on Unix
    return (path:gsub("\\", "/"))
  end
end

--- Get the user's home directory
---@return string Home directory path
M.home_dir = function()
  local platform = M.get_platform()
  if platform == "windows" then
    return vim.env.USERPROFILE or "C:\\Users\\" .. vim.env.USERNAME
  else
    return vim.env.HOME or "/home/" .. vim.env.USER
  end
end

--- Check if a file exists
---@param path string Path to check
---@return boolean True if file exists
M.exists = function(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

--- Create a directory if it doesn't exist
---@param path string Directory path to create
---@return boolean Success
M.mkdir = function(path)
  return vim.fn.mkdir(path, "p") == 1
end

--- Build argv for opening a path in the system UI.
--- Exposed for tests.
--- @param path string
--- @param platform? string
--- @return table argv
M._system_open_argv = function(path, platform)
  platform = platform or M.get_platform()
  if platform == "macos" then
    return { "open", path }
  elseif platform == "windows" then
    -- cmd.exe start requires a title argument.
    return { "cmd.exe", "/c", "start", "", path }
  else
    return { "xdg-open", path }
  end
end

--- Open a file or directory using the OS default handler.
--- @param path string
--- @return boolean ok
--- @return string? err
M.system_open = function(path)
  if not path or vim.trim(tostring(path)) == "" then
    return false, "missing path"
  end

  local argv = M._system_open_argv(path)
  local exe = argv[1]
  if vim.fn.executable(exe) ~= 1 then
    return false, "system opener not found: " .. tostring(exe)
  end

  local jobid = vim.fn.jobstart(argv, { detach = true })
  if jobid <= 0 then
    return false, "failed to start system opener (jobid=" .. tostring(jobid) .. ")"
  end
  return true, nil
end

return M
