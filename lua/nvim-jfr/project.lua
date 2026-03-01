--- Java project detection module
--- @module nvim-jfr.project

local M = {}

local BUILD_FILES = {
  maven = { "pom.xml" },
  gradle_build = { "build.gradle", "build.gradle.kts" },
  gradle_settings = { "settings.gradle", "settings.gradle.kts" },
  wrapper = { "gradlew", "gradlew.bat", "mvnw", "mvnw.cmd" },
}

local _project_cache = {}

-- Root cache: keyed by buffer path or cwd, with TTL.
local _root_cache = {}
local ROOT_CACHE_TTL = 5 -- seconds

local function now_sec()
  return os.time()
end

local function cache_get(key)
  local ent = _root_cache[key]
  if not ent then
    return nil
  end
  if ent.at and os.difftime(now_sec(), ent.at) > ROOT_CACHE_TTL then
    _root_cache[key] = nil
    return nil
  end
  return ent.root
end

local function cache_put(key, root)
  _root_cache[key] = { root = root, at = now_sec() }
end

M.find_file = function(patterns, opts)
  opts = opts or {}
  opts.path = opts.path or vim.fn.getcwd()
  opts.upward = opts.upward ~= false
  return vim.fs.find(patterns, { path = opts.path, upward = opts.upward, type = "file" })[1]
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil
  end
  return table.concat(lines, "\n")
end

local function path_dir(path)
  return vim.fn.fnamemodify(path, ":p:h")
end

local function file_exists(path)
  if not path or path == "" then
    return false
  end
  return vim.fn.filereadable(path) == 1
end

--- Parse minimal Maven POM metadata.
--- This is a lightweight parser intended only for project detection.
---@param xml string
---@return table { modules: string[], group_id: string?, artifact_id: string?, packaging: string? }
M._parse_pom = function(xml)
  local out = { modules = {} }
  if not xml or xml == "" then
    return out
  end

  for mod in xml:gmatch("<module>%s*([^<]+)%s*</module>") do
    mod = vim.trim(mod)
    if mod ~= "" then
      table.insert(out.modules, mod)
    end
  end

  -- Best-effort metadata. Note: these may appear multiple times (e.g., in <parent>).
  out.group_id = xml:match("<groupId>%s*([^<]+)%s*</groupId>")
  out.artifact_id = xml:match("<artifactId>%s*([^<]+)%s*</artifactId>")
  out.packaging = xml:match("<packaging>%s*([^<]+)%s*</packaging>")

  return out
end

--- Return Maven info for a project root.
---@param root string Project root (directory containing pom.xml)
---@param pom_path string? Explicit pom.xml path
---@return table? info
M.maven_info = function(root, pom_path)
  if not root or root == "" then
    return nil
  end

  local platform = require("nvim-jfr.platform")
  pom_path = pom_path or M.find_file(BUILD_FILES.maven, { path = root })
  if not pom_path then
    return nil
  end

  local xml = read_file(pom_path) or ""
  local parsed = M._parse_pom(xml)

  local module_paths = {}
  for _, mod in ipairs(parsed.modules or {}) do
    table.insert(module_paths, platform.join_path(root, mod))
  end

  return {
    pom = pom_path,
    group_id = parsed.group_id,
    artifact_id = parsed.artifact_id,
    packaging = parsed.packaging,
    modules = parsed.modules or {},
    module_paths = module_paths,
    is_multi_module = (parsed.modules and #parsed.modules > 0) or false,
  }
end

--- True if the given root is a Maven project.
---@param root string
---@return boolean
M.is_maven = function(root)
  return M.find_file(BUILD_FILES.maven, { path = root }) ~= nil
end

--- Parse minimal Gradle settings metadata.
--- Supports Groovy and Kotlin DSL in a best-effort way.
---@param text string
---@return table { root_name: string?, includes: string[] }
M._parse_gradle_settings = function(text)
  local out = { includes = {} }
  if not text or text == "" then
    return out
  end

  -- Strip line comments (best-effort). Keep it simple; this parser is heuristic.
  local cleaned = {}
  for line in vim.gsplit(text, "\n", { plain = true }) do
    line = line:gsub("//.*$", "")
    table.insert(cleaned, line)
  end
  text = table.concat(cleaned, "\n")

  out.root_name = text:match("rootProject%.name%s*=%s*['\"]([^'\"]+)['\"]")

  local function add_includes(argstr)
    if not argstr or argstr == "" then
      return
    end
    -- Extract quoted strings: include ':app', ':lib' OR include(":app", ":lib")
    for q in argstr:gmatch("['\"]([^'\"]+)['\"]") do
      q = vim.trim(q)
      if q ~= "" then
        table.insert(out.includes, q)
      end
    end
  end

  -- include("...", "...") / include('...')
  for args in text:gmatch("include%s*%(([^)]+)%)") do
    add_includes(args)
  end

  -- include '...','...' (Groovy)
  for args in text:gmatch("include%s+([^\n\r]+)") do
    add_includes(args)
  end

  -- De-dupe while preserving order.
  local seen, uniq = {}, {}
  for _, inc in ipairs(out.includes) do
    if not seen[inc] then
      seen[inc] = true
      table.insert(uniq, inc)
    end
  end
  out.includes = uniq

  return out
end

--- Parse minimal Gradle wrapper properties.
---@param text string
---@return table { distribution_url: string?, gradle_version: string? }
M._parse_gradle_wrapper_properties = function(text)
  local out = {}
  if not text or text == "" then
    return out
  end

  local url = text:match("distributionUrl%s*=%s*([^\r\n]+)")
  if url then
    url = vim.trim(url)
    -- Unescape common java properties escapes (best-effort).
    url = url:gsub("\\\\:", ":"):gsub("\\\\=", "="):gsub("\\\\", "\\")
    out.distribution_url = url
    local ver, kind = url:match("gradle%-([%d%.]+)%-([%a]+)%.zip")
    if ver and (kind == "bin" or kind == "all") then
      out.gradle_version = ver
    end
  end

  return out
end

--- Return Gradle info for a project root.
---@param root string Project root (directory containing settings.gradle* or build.gradle*)
---@return table? info
M.gradle_info = function(root)
  if not root or root == "" then
    return nil
  end

  local platform = require("nvim-jfr.platform")

  local settings = M.find_file(BUILD_FILES.gradle_settings, { path = root, upward = false })
  local build = M.find_file(BUILD_FILES.gradle_build, { path = root, upward = false })

  if not settings and not build then
    return nil
  end

  local wrapper = {
    gradlew = M.find_file({ "gradlew" }, { path = root, upward = false }),
    gradlew_bat = M.find_file({ "gradlew.bat" }, { path = root, upward = false }),
    properties = platform.join_path(root, "gradle", "wrapper", "gradle-wrapper.properties"),
  }
  if not file_exists(wrapper.properties) then
    wrapper.properties = nil
  end

  local settings_parsed = nil
  if settings then
    settings_parsed = M._parse_gradle_settings(read_file(settings) or "")
  end

  local wrapper_parsed = nil
  if wrapper.properties then
    wrapper_parsed = M._parse_gradle_wrapper_properties(read_file(wrapper.properties) or "")
  end

  local includes = (settings_parsed and settings_parsed.includes) or {}
  local module_paths = {}
  for _, inc in ipairs(includes) do
    local p = inc:gsub("^:+", ""):gsub(":+", "/")
    if p ~= "" then
      table.insert(module_paths, platform.join_path(root, p))
    end
  end

  local root_name = (settings_parsed and settings_parsed.root_name) or vim.fn.fnamemodify(root, ":t")

  return {
    settings = settings,
    build = build,
    root_name = root_name,
    includes = includes,
    module_paths = module_paths,
    is_multi_module = includes and #includes > 0 or false,
    wrapper = {
      gradlew = wrapper.gradlew,
      gradlew_bat = wrapper.gradlew_bat,
      properties = wrapper.properties,
      distribution_url = wrapper_parsed and wrapper_parsed.distribution_url or nil,
      gradle_version = wrapper_parsed and wrapper_parsed.gradle_version or nil,
    },
  }
end

--- True if the given root is a Gradle project.
---@param root string
---@return boolean
M.is_gradle = function(root)
  return M.find_file(BUILD_FILES.gradle_settings, { path = root }) ~= nil
    or M.find_file(BUILD_FILES.gradle_build, { path = root }) ~= nil
    or M.find_file({ "gradlew", "gradlew.bat" }, { path = root }) ~= nil
end

M.detect = function(root)
  root = root or vim.fn.getcwd()

  -- We'll cache by the detected root (directory containing build file).
  local function cached(project_root)
    return project_root and _project_cache[project_root] or nil
  end

  local project = { root = root, type = nil, build_file = nil, name = nil }

  local pom = M.find_file(BUILD_FILES.maven, { path = root })
  if pom then
    local pom_root = path_dir(pom)
    local c = cached(pom_root)
    if c then
      return c
    end
    project.type = "maven"
    project.root = pom_root
    project.build_file = pom
    project.name = vim.fn.fnamemodify(pom_root, ":t")
    project.maven = M.maven_info(pom_root, pom)
    _project_cache[pom_root] = project
    return project
  end

  -- Prefer settings.gradle* as the project root for multi-module builds.
  local settings = M.find_file(BUILD_FILES.gradle_settings, { path = root })
  local build = M.find_file(BUILD_FILES.gradle_build, { path = root })
  local marker = settings or build

  if marker then
    local gradle_root = path_dir(marker)
    local c = cached(gradle_root)
    if c then
      return c
    end
    project.type = "gradle"
    project.root = gradle_root
    -- Keep build_file as the marker we used.
    project.build_file = marker
    project.name = vim.fn.fnamemodify(gradle_root, ":t")
    project.gradle = M.gradle_info(gradle_root)
  end

  if project.type then
    _project_cache[project.root] = project
  end

  return project.type and project or nil
end

M.get_root = function(buf)
  buf = buf or 0

  local buf_path = vim.api.nvim_buf_get_name(buf)
  local cache_key = (buf_path and buf_path ~= "") and ("buf:" .. buf_path) or ("cwd:" .. vim.fn.getcwd())
  local cached = cache_get(cache_key)
  if cached ~= nil then
    return cached
  end

  -- Prefer build system roots explicitly, because vim.fs.root will pick the
  -- nearest match (e.g., a submodule build.gradle) over settings.gradle above.
  local start = nil
  if buf_path and buf_path ~= "" then
    start = vim.fn.fnamemodify(buf_path, ":p:h")
  else
    start = vim.fn.getcwd()
  end

  local pom = vim.fs.find(BUILD_FILES.maven, { path = start, upward = true, type = "file" })[1]
  if pom then
    local root = path_dir(pom)
    cache_put(cache_key, root)
    return root
  end

  local settings = vim.fs.find(BUILD_FILES.gradle_settings, { path = start, upward = true, type = "file" })[1]
  if settings then
    local root = path_dir(settings)
    cache_put(cache_key, root)
    return root
  end

  local build = vim.fs.find(BUILD_FILES.gradle_build, { path = start, upward = true, type = "file" })[1]
  if build then
    local root = path_dir(build)
    cache_put(cache_key, root)
    return root
  end

  if vim.fs.root then
    local root = vim.fs.root(start, { "mvnw", "mvnw.cmd", "gradlew", "gradlew.bat", ".git" })
    if root then
      cache_put(cache_key, root)
      return root
    end
  end

  if buf_path and buf_path ~= "" then
    local proj = M.detect(start)
    if proj then
      cache_put(cache_key, proj.root)
      return proj.root
    end
  end

  local proj = M.detect()
  local root = proj and proj.root or nil
  cache_put(cache_key, root)
  return root
end

M.clear_cache = function()
  _project_cache = {}
  _root_cache = {}
end

--- Clear only root cache
M.clear_root_cache = function()
  _root_cache = {}
end

return M
