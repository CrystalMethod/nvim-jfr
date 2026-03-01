--- Configuration module for nvim-jfr
--- @module nvim-jfr.config

local M = {}

local defaults = {
  -- Output directory for recordings.
  --
  -- Supported:
  --   - "project": <project-root>/.jfr/recordings when a project root is detected
  --                (falls back to platform default when root isn't detected)
  --   - nil: platform default (~/jfr-recordings on Unix, %USERPROFILE%\jfr-recordings on Windows)
  output_dir = "project",

  -- Default recording duration (e.g., "60s", "5m", "1h")
  default_duration = "60s",

  -- Default `settings=` value passed to `jcmd <pid> JFR.start`.
  -- Supported values:
  --  - "default" | "profile" (built-in templates)
  --  - "/path/to/custom.jfc" (custom template file)
  --
  -- This is the direct analogue of the `settings=` option from `help JFR.start`.
  settings = "profile",

  -- Auto-detect project root
  auto_detect = true,

  -- Prefer project-scoped JVM discovery when possible
  project_scoped_jvms = true,

  -- Project-scoped JVM probing behavior.
  -- Used when project_scoped_jvms=true and jcmd -l lines don't contain the
  -- project root; we may probe VM.system_properties as a fallback.
  project_jvm_probe = {
    enabled = true,
    timeout_ms = 250,
    max_probes = 6,
    time_budget_ms = 600,
    stop_after_first_match = true,
    -- Exclude obvious tooling JVMs from being considered "project" matches.
    -- Matching is done against the raw `jcmd -l` line and main_class.
    exclude_raw_patterns = {
      "org%.eclipse%.equinox%.launcher", -- jdtls
      "org%.eclipse%.jdt%.ls", -- jdtls
      "org%.apache%.maven%.wrapper%.MavenWrapperMain", -- mvnw
    },
  },

  -- Show Java major version in JVM pickers.
  -- This requires calling `jcmd <pid> VM.version` per entry, which can be slow
  -- on some systems (jcmd attach). Disabled by default for responsiveness.
  show_java_version_in_picker = false,

  -- Clear cached project context on directory/project switches
  watch_project_switch = true,

  -- Show notifications
  notifications = true,

  -- Picker to use: "snacks", "telescope", "fzf", "vim", "auto"
  picker = "auto",

  -- Recordings picker preview (used by :JFRRecordings).
  -- For small .jfr files only, it may run `jfr summary` asynchronously.
  recordings_preview = {
    enabled = true,
    summary_max_kb = 1024,
    timeout_ms = 800,
    jfr_command = "jfr",
    -- Snacks layout preset for :JFRRecordings (preview on the right by default).
    -- See snacks.picker layout presets: default, telescope, vertical, ivy, sidebar, ...
    layout_preset = "default",
  },

  -- Command to open JFR files (JDK Mission Control)
  jmc_command = "jmc",

  -- Keymaps.
  -- Set `keymaps.enabled=true` to opt-in to defaults, or set `keymaps=false`
  -- to disable entirely.
  keymaps = {
    enabled = false,

    -- Optional which-key registration (if which-key is installed).
    -- Only applies when keymaps.enabled=true.
    which_key = false,

    start = "<leader>jfrs",
    stop = "<leader>jfrx",
    dump = "<leader>jfrd",
    status = "<leader>jfrt",
    open = "<leader>jfro",
    recordings = "<leader>jfrl",
    capabilities = "<leader>jfrp",
  },

  -- Status UI refresh behavior (:JFRStatus)
  status = {
    -- Periodically refresh the status float while it's open.
    auto_refresh = false,
    -- Timer interval for auto refresh.
    refresh_interval_ms = 2000,
    -- Throttle window to avoid overlapping/too-frequent refreshes.
    refresh_throttle_ms = 750,
  },

  -- Per-recording overrides for JFR.start options.
  -- Keys must be supported by the target JVM's `help JFR.start` output.
  -- Example:
  --   start_overrides = { maxage = "10m", maxsize = "250M" }
  start_overrides = {},

  -- JFC templates (for authoring/UX).
  -- These directories are scanned for *.jfc files.
  -- - project_dirs: project-local template dirs, relative to project root
  jfc_templates = {
    project_dirs = { ".jfr/templates" },

    -- If true, also include stock templates from $JAVA_HOME/lib/jfr/*.jfc
    -- (when JAVA_HOME is set and the files exist).
    include_java_home = false,
  },
}

local config = vim.deepcopy(defaults)

--- Setup the configuration
---@param opts table? User configuration
M.setup = function(opts)
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end
end

--- Get current configuration
---@return table Current configuration
M.get = function()
  return config
end

return M
