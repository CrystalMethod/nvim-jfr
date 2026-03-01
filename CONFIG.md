# Configuration

This document is the **full configuration reference** for `nvim-jfr`.

If you want the shortest setup, see **README.md**.

## Full config (defaults + explanations)

```lua
require("nvim-jfr").setup({
  -- Output directory for recordings
  -- "project" = <project-root>/.jfr/recordings when a project root is detected
  -- nil = platform default (~/jfr-recordings on Unix, %USERPROFILE%\jfr-recordings on Windows)
  output_dir = "project",

  -- Default recording duration
  default_duration = "60s", -- "60s", "5m", "1h"

  -- Default `settings=` value passed to `jcmd <pid> JFR.start`.
  -- Supported values:
  --  - "default" | "profile" (built-in templates)
  --  - "/path/to/custom.jfc" (custom settings file)
  settings = "profile",

  -- Prefer JVMs that look like they belong to the current project.
  -- When true, nvim-jfr will first try to list JVMs that match the current
  -- project root, and fall back to the global JVM list if none match.
  project_scoped_jvms = true,

  -- Show Java major version in JVM pickers.
  -- This runs `jcmd <pid> VM.version` per entry, which can be slow on some
  -- systems (jcmd attach). Keep disabled for best responsiveness.
  show_java_version_in_picker = false,

  -- Project-scoped JVM probing behavior.
  -- When project_scoped_jvms=true and `jcmd -l` output doesn't contain the
  -- project root path, nvim-jfr may probe `jcmd <pid> VM.system_properties`
  -- (bounded) to recover common cases (e.g. Maven/Spring Boot).
  --
  -- Use exclude_raw_patterns to hide tooling JVMs (jdtls, mvnw, etc.)
  -- from project pickers.
  project_jvm_probe = {
    enabled = true,
    timeout_ms = 250,
    max_probes = 6,
    time_budget_ms = 600,
    stop_after_first_match = true,

    exclude_raw_patterns = {
      "org%.eclipse%.equinox%.launcher", -- jdtls
      "org%.eclipse%.jdt%.ls", -- jdtls
      "org%.apache%.maven%.wrapper%.MavenWrapperMain", -- mvnw
    },
  },

  -- Picker backend: "snacks", "telescope", "fzf", "vim", "auto"
  picker = "auto",

  -- Command to open JFR files (JDK Mission Control)
  -- On macOS you may want to set this to the app binary path.
  jmc_command = "jmc",

  -- Per-recording start option overrides (capability-gated)
  -- These are merged into the JFR.start options. Unsupported keys are
  -- rejected based on detected JVM capabilities.
  start_overrides = {
    maxage = "10m",
    maxsize = "250M",
  },

  -- Preview for :JFRRecordings (Snacks picker)
  recordings_preview = {
    enabled = true,
    summary_max_kb = 1024,
    timeout_ms = 800,
    jfr_command = "jfr",
    layout_preset = "default",
  },

  -- Keymaps (opt-in)
  keymaps = {
    enabled = false,
    which_key = false,

    start = "<leader>jfrs",
    stop = "<leader>jfrx",
    dump = "<leader>jfrd",
    status = "<leader>jfrt",
    open = "<leader>jfro",
    recordings = "<leader>jfrl",
    capabilities = "<leader>jfrp",
  },

  -- JFC templates for :JFCNew
  jfc_templates = {
    project_dirs = { ".jfr/templates" },
    include_java_home = false, -- add $JAVA_HOME/lib/jfr/*.jfc
  },
})
```

## Named run configurations (project-only)

`nvim-jfr` also supports **named run configurations** that are stored per-project at:

`<root>/.jfr/run-configs.lua`

These are applied when starting a recording via:

```vim
:JFRStart --run=<name>
:JFRStart             " JVM picker -> run config picker (if configs exist)
:JFRStart --run=none  " skip run config selection/application
```

See: **[docs/run-configs.md](docs/run-configs.md)** for the file format and rules (including the required `<root>/.jfr/templates` constraint for `.jfc` paths referenced from run configs).
