--- Neovim healthcheck for nvim-jfr.
---
--- Entry point for :checkhealth nvim-jfr.
--- Keep reporting thin; helper logic lives in dedicated tasks.

local M = {}

local function health_api()
  local h = vim.health or {}
  -- Neovim 0.10+: start/ok/warn/error/info
  -- Neovim 0.8-0.9: report_start/report_ok/report_warn/report_error/report_info
  return {
    start = h.start or h.report_start or function(_) end,
    ok = h.ok or h.report_ok or function(_) end,
    warn = h.warn or h.report_warn or function(_, _) end,
    error = h.error or h.report_error or function(_, _) end,
    info = h.info or h.report_info or function(_) end,
  }
end

local function version_at_least(v, min)
  if not v or not min then
    return false
  end
  local va = { tonumber(v.major) or 0, tonumber(v.minor) or 0, tonumber(v.patch) or 0 }
  local mi = { tonumber(min.major) or 0, tonumber(min.minor) or 0, tonumber(min.patch) or 0 }
  for i = 1, 3 do
    if va[i] > mi[i] then
      return true
    elseif va[i] < mi[i] then
      return false
    end
  end
  return true
end

local function ver_to_string(v)
  if not v then
    return "?"
  end
  return string.format("%d.%d.%d", tonumber(v.major) or 0, tonumber(v.minor) or 0, tonumber(v.patch) or 0)
end

local function current_version()
  if type(vim.version) == "function" then
    local ok, v = pcall(vim.version)
    if ok and type(v) == "table" then
      return v
    end
  end
  return nil
end

local function check_nvim_version(h)
  local MIN = { major = 0, minor = 8, patch = 0 }
  local RECOMMENDED = { major = 0, minor = 10, patch = 0 }
  local v = current_version()
  if v then
    if not version_at_least(v, MIN) then
      h.error(
        string.format("Neovim %s is too old", ver_to_string(v)),
        string.format("nvim-jfr requires Neovim >= %s. Upgrade: https://neovim.io/", ver_to_string(MIN))
      )
      return false
    end
    h.ok(string.format("Neovim version %s (min %s)", ver_to_string(v), ver_to_string(MIN)))
    if not version_at_least(v, RECOMMENDED) then
      h.warn(
        string.format("Neovim %s is supported but older than recommended", ver_to_string(v)),
        string.format("Consider upgrading to >= %s for improved APIs (vim.uv/vim.health).", ver_to_string(RECOMMENDED))
      )
    end
    return true
  end

  -- Fallback for older versions where vim.version() is absent.
  local ok_min = (vim.fn.has("nvim-0.8") == 1) or (vim.fn.has("nvim-0.8.0") == 1)
  if not ok_min then
    h.error("Neovim is too old", "nvim-jfr requires Neovim >= 0.8.0. Upgrade: https://neovim.io/")
    return false
  end
  h.ok("Neovim version >= 0.8.0 (vim.version() unavailable)")
  return true
end

local function check_required_apis(h)
  -- vim.fs.find is required for project root detection.
  if not (vim.fs and type(vim.fs.find) == "function") then
    h.error(
      "Missing required API: vim.fs.find",
      "Upgrade Neovim (>=0.8.0) or use a newer build with vim.fs available: https://neovim.io/"
    )
  else
    h.ok("API available: vim.fs.find")
  end

  -- libuv handle: prefer vim.uv (0.10+), fallback vim.loop.
  if vim.uv then
    h.ok("API available: vim.uv")
  elseif vim.loop then
    h.warn("API available: vim.loop (legacy)", "Upgrade to Neovim 0.10+ for vim.uv")
  else
    h.error("Missing required API: vim.uv/vim.loop", "This Neovim build lacks libuv bindings")
  end

  -- Optional, improves root detection but is feature-gated in code.
  if vim.fs and type(vim.fs.root) == "function" then
    h.ok("API available: vim.fs.root")
  else
    h.info("API missing: vim.fs.root (optional)")
  end
end

local function command_head(cmd)
  if not cmd or cmd == "" then
    return nil
  end
  cmd = vim.trim(tostring(cmd))
  if cmd == "" then
    return nil
  end
  -- Handle quoted executables: "C:\\Program Files\\...\\jcmd.exe" ...
  if cmd:sub(1, 1) == '"' then
    local q = cmd:find('"', 2, true)
    if q and q > 2 then
      return cmd:sub(2, q - 1)
    end
  end
  -- Best-effort: first token.
  return (cmd:match("^(%S+)") or cmd)
end

local function resolve_executable(cmd)
  local head = command_head(cmd)
  if not head then
    return { ok = false, cmd = cmd, head = head, path = nil }
  end
  local ok = (vim.fn.executable(head) == 1)
  local path = nil
  if ok then
    local p = vim.fn.exepath(head)
    path = (p and p ~= "") and p or head
  end
  return { ok = ok, cmd = cmd, head = head, path = path }
end

local function install_hint(tool)
  tool = tool or "<tool>"
  return table.concat({
    "Install a JDK (not just a JRE) and ensure it's on PATH.",
    "macOS (Homebrew): `brew install openjdk`",
    "Debian/Ubuntu: `sudo apt install openjdk-21-jdk`",
    "Fedora/RHEL: `sudo dnf install java-21-openjdk-devel`",
    "Arch: `sudo pacman -S jdk-openjdk`",
    "Windows: `winget install EclipseAdoptium.Temurin.21.JDK` or `choco install temurin21`",
    "SDKMAN: `sdk install java 21.0.2-tem`",
    string.format("Then verify in a terminal: `%s --help` (or `jcmd -l`).", tool),
    "Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)",
  }, "\n")
end

local function check_executables(h)
  -- Required tools
  local jcmd = resolve_executable("jcmd")
  if jcmd.ok then
    h.ok("Executable found: jcmd", "Resolved path: " .. tostring(jcmd.path))
  else
    h.error("Missing executable: jcmd", install_hint("jcmd"))
  end

  local java = resolve_executable("java")
  if java.ok then
    h.ok("Executable found: java", "Resolved path: " .. tostring(java.path))
  else
    h.error("Missing executable: java", install_hint("java"))
  end

  -- Configurable/optional tools
  local ok_cfg, cfgmod = pcall(require, "nvim-jfr.config")
  local cfg = (ok_cfg and cfgmod and cfgmod.get and cfgmod.get()) or {}

  local jfr_cfg = cfg.recordings_preview and cfg.recordings_preview.jfr_command or nil
  local jfr_enabled = cfg.recordings_preview == nil or cfg.recordings_preview.enabled ~= false
  if jfr_enabled then
    local jfr = resolve_executable(jfr_cfg or "jfr")
    if jfr.ok then
      h.ok("Optional executable found: jfr", "Resolved path: " .. tostring(jfr.path))
    else
      h.warn(
        "Optional executable missing: jfr",
        "Used for :JFRRecordings preview (jfr summary). Fix: configure `recordings_preview.jfr_command` or install a JDK that provides `jfr`\n"
          .. install_hint("jfr")
      )
    end
  else
    h.info("Optional executable jfr not checked (recordings_preview.disabled)")
  end

  local jmc_cfg = cfg.jmc_command
  local jmc = resolve_executable(jmc_cfg or "jmc")
  if jmc.ok then
    h.ok("Optional executable found: jmc", "Resolved path: " .. tostring(jmc.path))
  else
    h.warn(
      "Optional executable missing: jmc",
      "Needed to open recordings in Mission Control from :JFRRecordings. Fix: configure `jmc_command` or install JDK Mission Control. Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)"
    )
  end

  -- Show effective configured commands (useful when overrides are set)
  if jfr_cfg and jfr_cfg ~= "" then
    h.info("Config: recordings_preview.jfr_command = " .. tostring(jfr_cfg))
  end
  if jmc_cfg and jmc_cfg ~= "" then
    h.info("Config: jmc_command = " .. tostring(jmc_cfg))
  end
end

local function type_name(v)
  local t = type(v)
  if t ~= "table" then
    return t
  end
  return "table"
end

local function is_nonempty_string(v)
  return type(v) == "string" and vim.trim(v) ~= ""
end

local function check_config_sanity(h)
  local ok_cfg, cfgmod = pcall(require, "nvim-jfr.config")
  if not ok_cfg or not cfgmod or type(cfgmod.get) ~= "function" then
    h.error("Unable to read nvim-jfr config", "Ensure the plugin is installed and `require('nvim-jfr').setup()` runs")
    return
  end

  local cfg = cfgmod.get() or {}
  h.start("nvim-jfr config")

  -- output_dir: nil | string (path) | "project"
  local od = cfg.output_dir
  if od == nil then
    h.ok("output_dir: <auto>")
  elseif od == "project" then
    h.ok("output_dir: project")
  elseif is_nonempty_string(od) then
    h.ok("output_dir: " .. tostring(od))
  else
    h.error(
      "Invalid config: output_dir",
      string.format("Expected nil | 'project' | non-empty string path, got %s", type_name(od))
    )
  end

  -- project_scoped_jvms: boolean
  if type(cfg.project_scoped_jvms) == "boolean" then
    h.ok("project_scoped_jvms: " .. tostring(cfg.project_scoped_jvms))
  else
    h.error(
      "Invalid config: project_scoped_jvms",
      string.format("Expected boolean, got %s", type_name(cfg.project_scoped_jvms))
    )
  end

  -- picker: "auto"|"snacks"|"telescope"|"fzf"|"vim"
  local picker = cfg.picker
  local allowed_picker = { auto = true, snacks = true, telescope = true, fzf = true, vim = true }
  if picker == nil then
    h.ok("picker: <default>")
  elseif allowed_picker[picker] then
    h.ok("picker: " .. tostring(picker))
  else
    h.warn(
      "Suspicious config: picker",
      "Expected one of: auto, snacks, telescope, fzf, vim. Got: " .. tostring(picker)
    )
  end

  -- recordings_preview: table with enabled:boolean, summary_max_kb:number, timeout_ms:number, jfr_command:string
  local rp = cfg.recordings_preview
  if rp == nil then
    h.warn("recordings_preview: <missing>", "Expected a table; using defaults if available")
  elseif type(rp) ~= "table" then
    h.error(
      "Invalid config: recordings_preview",
      string.format("Expected table, got %s", type_name(rp))
    )
  else
    if type(rp.enabled) ~= "boolean" then
      h.warn("recordings_preview.enabled is not boolean", "Expected boolean, got: " .. type_name(rp.enabled))
    else
      h.ok("recordings_preview.enabled: " .. tostring(rp.enabled))
    end

    if rp.summary_max_kb ~= nil and type(rp.summary_max_kb) ~= "number" then
      h.warn("recordings_preview.summary_max_kb is not a number", "Expected number (KB), got: " .. type_name(rp.summary_max_kb))
    else
      h.ok("recordings_preview.summary_max_kb: " .. tostring(rp.summary_max_kb))
    end

    if rp.timeout_ms ~= nil and type(rp.timeout_ms) ~= "number" then
      h.warn("recordings_preview.timeout_ms is not a number", "Expected number (ms), got: " .. type_name(rp.timeout_ms))
    else
      h.ok("recordings_preview.timeout_ms: " .. tostring(rp.timeout_ms))
    end

    if rp.jfr_command ~= nil and not is_nonempty_string(rp.jfr_command) then
      h.warn("recordings_preview.jfr_command is empty/invalid", "Expected non-empty string, got: " .. type_name(rp.jfr_command))
    else
      h.ok("recordings_preview.jfr_command: " .. tostring(rp.jfr_command))
    end

    if rp.layout_preset ~= nil and not is_nonempty_string(rp.layout_preset) then
      h.warn("recordings_preview.layout_preset is empty/invalid", "Expected non-empty string, got: " .. type_name(rp.layout_preset))
    elseif rp.layout_preset then
      h.ok("recordings_preview.layout_preset: " .. tostring(rp.layout_preset))
    end
  end
end

local function check_picker_backend(h)
  local ok_cfg, cfgmod = pcall(require, "nvim-jfr.config")
  local cfg = (ok_cfg and cfgmod and cfgmod.get and cfgmod.get()) or {}
  local preferred = cfg.picker

  local picker = require("nvim-jfr.picker")

  local function avail(name)
    if name == "vim" then
      return true
    end
    return picker.is_available(name)
  end

  local effective = picker.detect(preferred)
  h.start("nvim-jfr picker")

  if preferred and preferred ~= "auto" then
    if avail(preferred) then
      h.ok("Configured picker available: " .. tostring(preferred))
    else
      h.warn(
        "Configured picker not available: " .. tostring(preferred),
        "Fix: install the plugin for that picker or set `picker = 'auto'` (or another backend) in setup(). Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)"
      )
    end
  else
    h.ok("Picker preference: auto")
  end

  local backends = {
    { name = "snacks", mod = "snacks.picker", notes = "Supports preview + richer UX" },
    { name = "telescope", mod = "telescope", notes = "Supports preview + multi-select" },
    { name = "fzf", mod = "fzf-lua", notes = "Fast fuzzy UI; multi-select depends on actions" },
    { name = "vim", mod = "vim.ui.select", notes = "Fallback; no multi-select" },
  }

  for _, b in ipairs(backends) do
    if b.name == "vim" then
      h.ok("Backend available: vim.ui.select", b.notes)
    else
      local ok = avail(b.name)
      if ok then
        h.ok("Backend available: " .. b.name, "module: " .. b.mod)
      else
        h.info("Backend not found: " .. b.name, "module: " .. b.mod)
      end
    end
  end

  if effective == "vim" then
    h.warn(
      "Using fallback picker: vim.ui.select",
      "This limits UX (no multi-select). Fix: install Snacks/Telescope/fzf-lua or set `picker` accordingly. Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)"
    )
  else
    h.ok("Effective picker: " .. tostring(effective))
  end
end

local function check_output_dir_and_root(h)
  local ok_cfg, cfgmod = pcall(require, "nvim-jfr.config")
  local cfg = (ok_cfg and cfgmod and cfgmod.get and cfgmod.get()) or {}

  local rec = require("nvim-jfr.recordings")
  local proj = require("nvim-jfr.project")
  local platform = require("nvim-jfr.platform")

  h.start("nvim-jfr paths")

  local out_dir = rec.get_output_dir(cfg)
  h.info("Resolved output_dir", tostring(out_dir))

  if not out_dir or out_dir == "" then
    h.error("output_dir could not be resolved", "Check config.output_dir and your environment")
  else
    if vim.fn.isdirectory(out_dir) == 1 then
      h.ok("output_dir exists", out_dir)
    else
      h.warn(
        "output_dir does not exist yet",
        "It will be created on first recording. Fix: create it now: `mkdir -p "
          .. out_dir
          .. "` (or change `output_dir` in setup()). Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)"
      )
    end

    -- Non-destructive write test: create and delete a unique temp file.
    local uv = vim.uv or vim.loop
    local test_name = platform.join_path(out_dir, ".nvim-jfr-health-" .. tostring(uv.hrtime()) .. ".tmp")
    local ok_parent, err_parent = rec.ensure_output_dir(out_dir)
    if not ok_parent then
      h.error(
        "output_dir is not writable/creatable",
        "nvim-jfr could not create the directory: "
          .. tostring(err_parent or "unknown error")
          .. "\nFix: adjust permissions or change `output_dir` in setup(). Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)"
      )
    else
      local fd = uv.fs_open(test_name, "w", 384) -- 0600
      if not fd then
        h.error(
          "output_dir is not writable",
          "Unable to create a file in output_dir. Fix: adjust permissions (chmod/chown) or choose another directory via `output_dir`. Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)"
        )
      else
        uv.fs_close(fd)
        uv.fs_unlink(test_name)
        h.ok("output_dir is writable")
      end
    end
  end

  local root = proj.get_root(0)
  if root and root ~= "" then
    h.ok("Detected project root", tostring(root))
    if cfg.output_dir == "project" then
      h.info("output_dir strategy", "project (recordings saved under <root>/.jfr/recordings)")
    end
  else
    h.warn(
      "No project root detected",
      "Project-scoped features may fall back to global behavior. Fix: open Neovim in a Maven/Gradle project (or `:cd` to the project root), or set `output_dir` to an explicit path. Docs: `:checkhealth nvim-jfr` (see README Healthcheck section)"
    )
  end
end

--- Run healthchecks.
M.check = function()
  local h = health_api()
  h.start("nvim-jfr")

  local ok_ver = check_nvim_version(h)
  if ok_ver then
    check_required_apis(h)
    check_config_sanity(h)
    check_picker_backend(h)
    check_output_dir_and_root(h)
    check_executables(h)
  end

  h.ok("healthcheck loaded")
end

-- Exposed for headless testing.
M._health_api = health_api
M._version_at_least = version_at_least
M._ver_to_string = ver_to_string
M._command_head = command_head
M._resolve_executable = resolve_executable
M._is_nonempty_string = is_nonempty_string
M._type_name = type_name
M._check_picker_backend = check_picker_backend
M._check_output_dir_and_root = check_output_dir_and_root

return M
